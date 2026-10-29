#!/bin/bash
# Claude Code hook: records each session's state for the Touch Bar.
# working = Claude is busy; ready = finished, asked something or needs permission.
DIR="$HOME/.claude/touchbar/sessions"
JQ=/usr/bin/jq; [ -x $JQ ] || JQ=/opt/homebrew/bin/jq
mkdir -p "$DIR"
input=$(cat)
sid=$(echo "$input" | $JQ -r '.session_id // empty')
event=$(echo "$input" | $JQ -r '.hook_event_name // empty')
[ -z "$sid" ] && exit 0
file="$DIR/$sid.json"

case "$event" in
  UserPromptSubmit|PreToolUse|PostToolUse) state=working ;;
  Stop|Notification) state=ready ;;
  SessionEnd) rm -f "$file"; exit 0 ;;
  *) exit 0 ;;
esac

cwd=$(echo "$input" | $JQ -r '.cwd // empty')
transcript=$(echo "$input" | $JQ -r '.transcript_path // empty')

# Session title as shown in the app, else the project folder name.
title=""
if [ -f "$transcript" ]; then
  title=$(grep '"type":"custom-title"' "$transcript" | tail -1 | $JQ -r '.customTitle // empty' 2>/dev/null)
fi
if [ -z "$title" ]; then
  case "$cwd" in
    */.claude/worktrees/*) title="${cwd##*/}" ;;
    *scratch-workspaces*)  title="chat" ;;
    *)                     title="${cwd##*/}" ;;
  esac
fi

# The desktop app's id for this session (local_…), used to open it from the Touch Bar.
app_id=$($JQ -r '.app_id // empty' "$file" 2>/dev/null)
if [ -z "$app_id" ]; then
  match=$(grep -l -F "\"cliSessionId\":\"$sid\"" "$HOME/Library/Application Support/Claude/claude-code-sessions"/*/*/local_*.json 2>/dev/null | head -1)
  [ -n "$match" ] && app_id=$(basename "$match" .json)
fi

# Keep when we first saw the session so its Touch Bar slot doesn't move around.
now=$(date +%s)
created=$($JQ -r '.created // empty' "$file" 2>/dev/null)
tmp=$(mktemp "$DIR/.tmp.XXXXXX")
$JQ -n --arg s "$state" --arg t "$title" --arg c "$cwd" --argjson ts "$now" --argjson cr "${created:-$now}" --arg id "$app_id" \
  '{state:$s, title:$t, cwd:$c, ts:$ts, created:$cr, app_id:$id}' > "$tmp" && mv "$tmp" "$file"
exit 0
