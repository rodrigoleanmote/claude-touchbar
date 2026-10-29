#!/bin/bash
# Opens the session shown in Touch Bar slot N (as laid out by `claudebar daemon`).
DEST="$HOME/.claude/touchbar"
# kind, app id, title, project; "-" stands in for empty fields so the tab split keeps its place.
IFS=$'\t' read -r kind id title project < "$DEST/slots/${1:-1}.tsv" 2>/dev/null
[ "$project" = - ] && project=""
if [ "$kind" = cowork ]; then
  "$DEST/claudebar" press "$title" "$project"
elif [ "$kind" = code ] && [ -n "$id" ] && [ "$id" != - ]; then
  open "claude://claude.ai/epitaxy/$id"
else
  open -a Claude
fi
