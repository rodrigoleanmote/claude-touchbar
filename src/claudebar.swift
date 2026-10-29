// The Touch Bar side of claude-touchbar.
//
//   claudebar daemon          keep running: every second, lay out the Touch Bar slots from the
//                             session files; every 3s, refresh Cowork sessions from the sidebar
//   claudebar scan            refresh ~/.claude/touchbar/sessions/cowork-*.json once
//   claudebar press <title>   open that Cowork session (clicks its sidebar row)
//
// Cowork sessions are read from the Claude app's sidebar (any window in Chat & Cowork mode) and
// mirrored as files next to the Code sessions the hooks write. Must run under MTMR, which holds
// the Accessibility permission.
import Cocoa
import ApplicationServices

let sessionsDir = NSHomeDirectory() + "/.claude/touchbar/sessions"

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String {
    guard let v = attr(e, name) else { return "" }
    if let s = v as? String { return s }
    if let a = v as? [String] { return a.joined(separator: ".") }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, "AXChildren") as? [AXUIElement]) ?? [] }
func find(_ e: AXUIElement, depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    if depth > 30 { return nil }
    if match(e) { return e }
    for c in children(e) { if let f = find(c, depth: depth + 1, match) { return f } }
    return nil
}
func texts(_ e: AXUIElement, depth: Int = 0) -> [String] {
    if depth > 8 { return [] }
    var out: [String] = []
    if str(e, "AXRole") == "AXStaticText" { out.append(str(e, "AXValue")) }
    for c in children(e) { out += texts(c, depth: depth + 1) }
    return out
}

// The sidebar of every Claude window currently showing Chat & Cowork. Matched by DOM class and
// position rather than by label, so it works whatever language the app is in.
func coworkSidebars() -> [(window: AXUIElement, sidebar: AXUIElement)] {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first else { return [] }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    var result: [(AXUIElement, AXUIElement)] = []
    for w in (attr(root, "AXWindows") as? [AXUIElement]) ?? [] {
        guard let sidebar = find(w, { str($0, "AXDOMClassList").hasPrefix("dframe-sidebar.") }),
              let modes = find(sidebar, { str($0, "AXRole") == "AXRadioGroup" }) else { continue }
        // The mode switch's first option is Chat & Cowork, the second is Code.
        if let first = children(modes).first, str(first, "AXValue") == "1" { result.append((w, sidebar)) }
    }
    return result
}

struct Row { var title: String; var state: String; var project: String? }

// Session rows with a status (running or unread), plus collapsed projects whose summary
// says one of their sessions needs you ("1 session: X (Unread)").
// Any status that doesn't say "running" (in a few languages) means the session wants you.
let runningWords = ["ejecuci", "running", "execu", "läuft", "en cours", "in corso"]
func stateFor(_ status: String) -> String {
    runningWords.contains { status.localizedCaseInsensitiveContains($0) } ? "working" : "ready"
}
func isRow(_ e: AXUIElement) -> Bool { str(e, "AXRole") == "AXButton" && str(e, "AXDOMClassList").hasPrefix("w-full") }
// Project rows carry their name as a description; session rows as a title.
func isProject(_ e: AXUIElement) -> Bool { isRow(e) && !str(e, "AXDescription").isEmpty }

func rows(in sidebar: AXUIElement) -> [Row] {
    var out: [Row] = []
    var lastProject: String?
    func visit(_ e: AXUIElement, _ depth: Int) {
        if depth > 30 { return }
        let cls = str(e, "AXDOMClassList")
        if isProject(e) {
            lastProject = str(e, "AXDescription")
        } else if isRow(e) {
            // A session row: its label holds the title and, when it has one, a hidden status text.
            let label = children(e).first { str($0, "AXDOMClassList").hasPrefix("dframe-fade-label") }
            let status = label.flatMap { l in children(l).first { str($0, "AXDOMClassList").hasPrefix("sr-only") } }
            let title = label.flatMap { texts($0).first } ?? ""
            // The status is either text inside that element ("Unread reply") or its description
            // (a running Cowork session exposes "Running" only as the element's description).
            let statusText = status.map { ([str($0, "AXDescription")] + texts($0)).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces) } ?? ""
            if !title.isEmpty && !statusText.isEmpty { out.append(Row(title: title, state: stateFor(statusText))) }
        }
        if cls.hasPrefix("sr-only.select-none") {
            // Summary of a collapsed project: "<n> session(s): A (Unread), B (Running)"
            let s = texts(e).joined(separator: " ")
            if s.hasSuffix(")"), let colon = s.firstIndex(of: ":") {
                for part in s[s.index(after: colon)...].components(separatedBy: "), ") {
                    guard let open = part.lastIndex(of: "(") else { continue }
                    let title = part[..<open].trimmingCharacters(in: .whitespaces)
                    let st = part[part.index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: ") "))
                    if !title.isEmpty { out.append(Row(title: title, state: stateFor(st), project: lastProject)) }
                }
            }
        }
        for c in children(e) { visit(c, depth + 1) }
    }
    visit(sidebar, 0)
    return out
}

func fileName(_ title: String) -> String {
    let safe = title.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
    return "\(sessionsDir)/cowork-\(safe.prefix(60)).json"
}

func scan() {
    let sidebars = coworkSidebars()
    // No window shows Cowork right now: keep what we last saw (the stale timers clean it up).
    guard !sidebars.isEmpty else { return }
    let now = Int(Date().timeIntervalSince1970)
    var keep = Set<String>()
    for (_, sidebar) in sidebars {
        for r in rows(in: sidebar) {
            let path = fileName(r.title)
            if keep.contains(path) { continue }
            keep.insert(path)
            var created = now
            if let d = FileManager.default.contents(atPath: path),
               let old = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = old["created"] as? Int { created = c }
            var obj: [String: Any] = ["kind": "cowork", "state": r.state, "title": r.title, "ts": now, "created": created]
            if let p = r.project { obj["project"] = p }
            if let d = try? JSONSerialization.data(withJSONObject: obj) {
                FileManager.default.createFile(atPath: path + ".tmp", contents: d)
                _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: path + ".tmp"))
            }
        }
    }
    for f in (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir)) ?? [] where f.hasPrefix("cowork-") {
        let path = "\(sessionsDir)/\(f)"
        if !keep.contains(path) { try? FileManager.default.removeItem(atPath: path) }
    }
}

func press(_ title: String, project: String?) {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first else { return }
    app.activate(options: [.activateIgnoringOtherApps])
    for (window, sidebar) in coworkSidebars() {
        let isTarget: (AXUIElement) -> Bool = { isRow($0) && !isProject($0) && texts($0).first == title }
        var target = find(sidebar, isTarget)
        if target == nil, let p = project {
            // Session hidden inside a collapsed project: expand it, then look again.
            if let row = find(sidebar, { isProject($0) && str($0, "AXDescription") == p }),
               let toggle = children(row).first(where: { str($0, "AXRole") == "AXButton" }) {
                AXUIElementPerformAction(toggle, kAXPressAction as CFString)
                Thread.sleep(forTimeInterval: 0.5)
                target = find(sidebar, isTarget)
            }
        }
        if let t = target {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementPerformAction(t, kAXPressAction as CFString)
            return
        }
    }
}

// MARK: - Touch Bar slots

let baseDir = NSHomeDirectory() + "/.claude/touchbar"
let slotsDir = baseDir + "/slots"
let slotCount = 6
let readyTTL = 8 * 3600     // forget finished sessions after 8h without activity
let workingTTL = 30 * 60    // a "working" session silent for 30 min probably died
let maxTitle = 10
let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

struct Session { var kind, state, title, appId, project: String; var ts, created: Int }

func loadSessions(now: Int) -> [Session] {
    var out: [Session] = []
    for f in (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir)) ?? [] where f.hasSuffix(".json") {
        let path = "\(sessionsDir)/\(f)"
        guard let d = FileManager.default.contents(atPath: path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
        let s = Session(kind: o["kind"] as? String ?? "code", state: o["state"] as? String ?? "ready",
                        title: o["title"] as? String ?? "", appId: o["app_id"] as? String ?? "",
                        project: o["project"] as? String ?? "", ts: o["ts"] as? Int ?? 0,
                        created: o["created"] as? Int ?? o["ts"] as? Int ?? 0)
        let ttl = s.state == "working" ? workingTTL : readyTTL
        if now - s.ts > ttl { try? FileManager.default.removeItem(atPath: path); continue }
        out.append(s)
    }
    // Stable positions: sessions keep the order in which they started.
    return out.sorted { ($0.created, $0.title) < ($1.created, $1.title) }
}

func writeIfChanged(_ path: String, _ text: String) {
    if let old = FileManager.default.contents(atPath: path), String(data: old, encoding: .utf8) == text { return }
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
}

// For each slot, N.txt is what MTMR shows ("title<TAB>icon", icon = "<kind>-<state>"; empty
// hides the button) and N.tsv is what a tap opens (kind, app id, title, project).
func layout(now: Int) {
    try? FileManager.default.createDirectory(atPath: slotsDir, withIntermediateDirectories: true)
    let sessions = loadSessions(now: now)
    for i in 0..<slotCount {
        var display = "", target = ""
        if i < sessions.count {
            let s = sessions[i]
            var title = s.title
            if title.count > maxTitle { title = String(title.prefix(maxTitle - 1)) + "…" }
            if s.state == "working" { title += " " + spinner[now % spinner.count] }
            display = "\(title)\t\(s.kind)-\(s.state)"
            let dash = { (v: String) in v.isEmpty ? "-" : v }
            target = [s.kind, dash(s.appId), dash(s.title), dash(s.project)].joined(separator: "\t")
        }
        writeIfChanged("\(slotsDir)/\(i + 1).txt", display)
        writeIfChanged("\(slotsDir)/\(i + 1).tsv", target)
    }
}

func daemon() {
    // One daemon at a time: MTMR may try to start it again after a restart.
    let lock = open(baseDir + "/claudebar.lock", O_CREAT | O_RDWR, 0o644)
    guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
    var tick = 0
    while true {
        let now = Int(Date().timeIntervalSince1970)
        if tick % 3 == 0 { scan() }
        layout(now: now)
        tick += 1
        Thread.sleep(forTimeInterval: 1)
    }
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "daemon": daemon()
case "scan": scan()
case "press" where args.count > 2: press(args[2], project: args.count > 3 && !args[3].isEmpty ? args[3] : nil)
default: print("usage: claudebar daemon | scan | press <title> [project]")
}
