// Dev tool: dumps the Claude desktop app's accessibility tree, to see how the sidebar is built
// when the app changes. Run it from MTMR (it needs the Accessibility permission), e.g. a
// temporary shellScriptTitledButton with: ~/.claude/touchbar/axprobe /tmp/claude-ax.txt
import Cocoa
import ApplicationServices

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/dev/stdout"
var lines = ["trusted=\(AXIsProcessTrusted())"]
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first else {
    try? "no claude".write(toFile: out, atomically: true, encoding: .utf8); exit(0)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 1.5)

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String {
    guard let v = attr(e, name) else { return "" }
    if let s = v as? String { return s }
    if let a = v as? [String] { return a.joined(separator: ".") }
    return ""
}
func walk(_ e: AXUIElement, _ depth: Int) {
    if depth > 40 || lines.count > 6000 { return }
    let role = str(e, "AXRole"), title = str(e, "AXTitle"), desc = str(e, "AXDescription")
    let value = str(e, "AXValue"), cls = str(e, "AXDOMClassList"), id = str(e, "AXDOMIdentifier")
    var l = String(repeating: " ", count: depth) + role
    if !title.isEmpty { l += " t=\(title.prefix(80))" }
    if !desc.isEmpty { l += " d=\(desc.prefix(80))" }
    if !value.isEmpty { l += " v=\(value.prefix(80))" }
    if !id.isEmpty { l += " id=\(id)" }
    if !cls.isEmpty { l += " c=\(cls.prefix(120))" }
    lines.append(l)
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, depth + 1) }
}
// axprobe <file> --mode "<mode label>": briefly switch the sidebar mode, dump, and switch back to Code.
func find(_ e: AXUIElement, _ role: String, _ desc: String, _ depth: Int = 0) -> AXUIElement? {
    if depth > 40 { return nil }
    if str(e, "AXRole") == role && str(e, "AXDescription") == desc { return e }
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { if let f = find(c, role, desc, depth + 1) { return f } }
    return nil
}
if CommandLine.arguments.count > 3, let b = find(root, "AXRadioButton", CommandLine.arguments[3]) {
    AXUIElementPerformAction(b, kAXPressAction as CFString)
    Thread.sleep(forTimeInterval: 2.5)
    walk(root, 0)
    if let back = find(root, "AXRadioButton", "Code") { AXUIElementPerformAction(back, kAXPressAction as CFString) }
} else {
    walk(root, 0)
}
try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
