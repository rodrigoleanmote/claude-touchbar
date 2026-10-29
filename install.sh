#!/bin/bash
# Installs claude-touchbar: Claude Code hooks + MTMR Touch Bar tiles for your Claude sessions.
# Safe to re-run; it backs up ~/.claude/settings.json and your MTMR config before changing them.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/touchbar"
SETTINGS="$HOME/.claude/settings.json"
MTMR_DIR="$HOME/Library/Application Support/MTMR"
MTMR_CONFIG="$MTMR_DIR/items.json"
SLOTS=6   # must match slotCount in src/claudebar.swift

JQ=$(command -v jq || true)
[ -z "$JQ" ] && [ -x /usr/bin/jq ] && JQ=/usr/bin/jq
if [ -z "$JQ" ]; then echo "jq is required (brew install jq)."; exit 1; fi
if ! command -v swiftc >/dev/null; then echo "swiftc is required (xcode-select --install)."; exit 1; fi

if [ ! -d /Applications/MTMR.app ]; then
  if command -v brew >/dev/null; then
    echo "Installing MTMR…"; brew install --cask mtmr
  else
    echo "Install MTMR first: https://mtmr.app (or brew install --cask mtmr)"; exit 1
  fi
fi

echo "Copying scripts to $DEST…"
mkdir -p "$DEST/sessions"
rm -f "$DEST/status.sh" "$DEST/bot.png"
cp "$REPO/src/hook.sh" "$REPO/src/open.sh" "$DEST/"
chmod +x "$DEST"/*.sh

# Each kind of session (icons/<kind>.png, a white glyph) gets a blue tile icon for "waiting
# for you" and a gray one for "working".
echo "Drawing the tile icons…"
rm -rf "$DEST/icons" && mkdir -p "$DEST/icons"
KINDS=$(cd "$REPO/icons" && ls *.png | sed 's/\.png$//' | "$JQ" -Rsc 'split("\n") | map(select(. != ""))')
for k in $("$JQ" -r '.[]' <<< "$KINDS"); do
  python3 "$REPO/src/make_icon.py" badge "$REPO/icons/$k.png" "#1F6FEB" "$DEST/icons/$k-ready.png"
  python3 "$REPO/src/make_icon.py" badge "$REPO/icons/$k.png" "#5A5A60" "$DEST/icons/$k-working.png"
done

echo "Building claudebar…"
pkill -f "$DEST/claudebar daemon" 2>/dev/null || true
swiftc -O "$REPO/src/claudebar.swift" -o "$DEST/claudebar"

echo "Adding hooks to $SETTINGS…"
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-claude-touchbar"
CMD="$DEST/hook.sh"
tmp=$(mktemp)
"$JQ" --arg cmd "$CMD" '
  def ours: [{"hooks":[{"type":"command","command":$cmd,"timeout":5}]}];
  def ours_tools: [{"matcher":"*","hooks":[{"type":"command","command":$cmd,"timeout":5}]}];
  # Drop any earlier copy of our hook, then add it to each event.
  def strip: map(.hooks |= map(select(.command != $cmd and .command != "~/.claude/touchbar/hook.sh")))
             | map(select(.hooks | length > 0));
  .hooks //= {}
  | reduce ("UserPromptSubmit","Stop","Notification","SessionEnd") as $e (.; .hooks[$e] = ((.hooks[$e] // []) | strip) + ours)
  | reduce ("PreToolUse","PostToolUse") as $e (.; .hooks[$e] = ((.hooks[$e] // []) | strip) + ours_tools)
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Writing the MTMR Touch Bar layout…"
mkdir -p "$MTMR_DIR"
if [ -f "$MTMR_CONFIG" ] && [ ! -f "$MTMR_CONFIG.bak-claude-touchbar" ]; then
  cp "$MTMR_CONFIG" "$MTMR_CONFIG.bak-claude-touchbar"
fi
# The tiles are AppleScript buttons that just read the slot files `claudebar daemon` writes:
# AppleScript runs inside MTMR, while MTMR's shell buttons leak a pipe on every run and crash
# it after a few minutes at a 1s refresh. The one shell button only (re)starts the daemon,
# every 10 minutes; the daemon keeps a single copy running.
"$JQ" -n --arg dest "$DEST" --argjson slots "$SLOTS" --argjson kinds "$KINDS" '
  def tile($i): "try
	set s to read (POSIX file \"\($dest)/slots/\($i).txt\") as «class utf8»
on error
	return \"\"
end try
if s is \"\" then return \"\"
set AppleScript'"'"'s text item delimiters to tab
set p to text items of s
return {item 1 of p, item 2 of p}";
  [{
    type: "shellScriptTitledButton", refreshInterval: 600, align: "left",
    source: { inline: "nohup \"\($dest)/claudebar\" daemon >/dev/null 2>&1 &" }
  }]
  + [range(1; $slots + 1) as $i | {
    type: "appleScriptTitledButton",
    source: { inline: tile($i) },
    refreshInterval: 1, align: "left", bordered: false,
    alternativeImages: ([$kinds[] as $k | ("ready", "working") as $s
      | { key: "\($k)-\($s)", value: { filePath: "\($dest)/icons/\($k)-\($s).png" } }] | from_entries),
    action: "shellScript", executablePath: "/bin/bash", shellArguments: ["\($dest)/open.sh", "\($i)"]
  }]
  + [ "previous", "play", "next", "brightnessDown", "brightnessUp", "volumeDown", "volumeUp", "mute"
      | { type: ., width: 36, align: "right" } ]
' > "$MTMR_CONFIG"

pkill -x MTMR 2>/dev/null || true
sleep 1
open -a MTMR

cat <<EOF

Done. Next steps:
  1. If macOS blocks MTMR, open System Settings → Privacy & Security and click "Open Anyway".
  2. Grant MTMR the Accessibility permission when asked (needed for Cowork sessions and tapping).
  3. Keep one Claude window in "Chat & Cowork" mode if you want Cowork sessions on the Touch Bar.
Code sessions show up the next time they do something.
EOF
