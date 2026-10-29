#!/bin/bash
# Removes claude-touchbar: its hooks, its files, and its MTMR layout (restoring your previous one).
set -euo pipefail

DEST="$HOME/.claude/touchbar"
SETTINGS="$HOME/.claude/settings.json"
MTMR_CONFIG="$HOME/Library/Application Support/MTMR/items.json"
JQ=$(command -v jq || echo /usr/bin/jq)

if [ -f "$SETTINGS" ]; then
  echo "Removing hooks from $SETTINGS…"
  tmp=$(mktemp)
  "$JQ" --arg cmd "$DEST/hook.sh" '
    if .hooks then
      .hooks |= (with_entries(.value |= (map(.hooks |= map(select(.command != $cmd and .command != "~/.claude/touchbar/hook.sh")))
                                          | map(select(.hooks | length > 0))))
                 | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
fi

if [ -f "$MTMR_CONFIG.bak-claude-touchbar" ]; then
  echo "Restoring your previous MTMR layout…"
  mv "$MTMR_CONFIG.bak-claude-touchbar" "$MTMR_CONFIG"
else
  echo "Removing the MTMR layout (MTMR will fall back to its default)…"
  rm -f "$MTMR_CONFIG"
fi
pkill -x MTMR 2>/dev/null && sleep 1 && open -a MTMR || true

pkill -f "$DEST/claudebar daemon" 2>/dev/null || true
rm -rf "$DEST"
echo "Done. MTMR itself is still installed (brew uninstall --cask mtmr to remove it)."
