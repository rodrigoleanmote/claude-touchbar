#!/bin/bash
# Opens the Nth Claude session (same order as status.sh) in the desktop app.
DIR="$HOME/.claude/touchbar/sessions"
JQ=/usr/bin/jq; [ -x $JQ ] || JQ=/opt/homebrew/bin/jq
files=("$DIR"/*.json)
[ -e "${files[0]}" ] || { open -a Claude; exit 0; }
# "-" stands in for empty fields: tabs are whitespace to read, so empty ones would collapse.
IFS=$'\t' read -r kind id title project < <($JQ -rs --argjson n "${1:-1}" \
  'sort_by(.created // .ts) | .[$n-1] // {} | [.kind // "code", (.app_id // "" | if . == "" then "-" else . end), .title // "-", .project // "-"] | @tsv' "${files[@]}" 2>/dev/null)
[ "$project" = - ] && project=""
if [ "$kind" = cowork ]; then
  "$HOME/.claude/touchbar/claudebar" press "$title" "$project"
elif [ "$id" != - ] && [ -n "$id" ]; then
  open "claude://claude.ai/epitaxy/$id"
else
  open -a Claude
fi
