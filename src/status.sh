#!/bin/bash
# Touch Bar tile for the Nth Claude session (sessions ordered by when they started).
# Prints an ANSI-colored title: blue tile when the session needs you, gray with a spinner while it works,
# nothing (hidden tile) when there's no Nth session.
DIR="$HOME/.claude/touchbar/sessions"
JQ=/usr/bin/jq; [ -x $JQ ] || JQ=/opt/homebrew/bin/jq
slot=${1:-1}
now=$(date +%s)
READY_TTL=$((8*3600))   # forget finished sessions after 8h without activity
WORK_TTL=$((30*60))     # a "working" session silent for 30 min probably died
MAXLEN=10

# Drop stale sessions every 30s (only slot 1, so the others don't race it).
if [ "$slot" = 1 ] && [ $((now % 30)) = 0 ]; then
  for f in "$DIR"/*.json; do
    [ -e "$f" ] || continue
    read -r state ts < <($JQ -r '[.state, .ts] | @tsv' "$f" 2>/dev/null)
    age=$((now - ${ts:-0}))
    { [ "$state" = ready ] && [ $age -gt $READY_TTL ]; } || { [ "$state" = working ] && [ $age -gt $WORK_TTL ]; } && rm -f "$f"
  done
fi

# Cowork sessions come from the Claude sidebar; slot 1 refreshes them every 3s in the
# background (output detached so MTMR doesn't wait for it).
if [ "$slot" = 1 ] && [ $((now % 3)) = 0 ]; then
  nohup "$HOME/.claude/touchbar/claudebar" scan >/dev/null 2>&1 &
fi

files=("$DIR"/*.json)
[ -e "${files[0]}" ] || exit 0
read -r state title < <($JQ -rs --argjson n "$slot" \
  'sort_by(.created // .ts) | .[$n-1] // empty | [.state, .title] | @tsv' "${files[@]}" 2>/dev/null)
[ -z "$state" ] && exit 0

[ ${#title} -gt $MAXLEN ] && title="${title:0:$((MAXLEN-1))}…"
if [ "$state" = ready ]; then
  label=$(printf '\033[44m\342\200\213\033[0m %s ' "$title")
else
  spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  label=$(printf '\033[100m\342\200\213\033[0m %s %s ' "$title" "${spin[$((now % 10))]}")
fi
echo "$label"
