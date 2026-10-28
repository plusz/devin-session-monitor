#!/bin/bash
# SwiftBar plugin — Devin session monitor (refresh every 5s)
# Put this file (or a symlink) in your SwiftBar plugins folder.
DIR="$HOME/.devin-status"
now=$(date +%s)

icon() {
  case "$1" in
    working)    echo "🟢" ;;
    waiting)    echo "🟡" ;;
    permission) echo "🟠" ;;
    question)   echo "🔵" ;;
    *)          echo "⚪" ;;
  esac
}

color() {
  case "$1" in
    working)    echo "green" ;;
    waiting)    echo "yellow" ;;
    permission) echo "orange" ;;
    question)   echo "blue" ;;
    *)          echo "gray" ;;
  esac
}

title=""
menu=""
found=0
for f in "$DIR"/*.json; do
  [ -e "$f" ] || continue
  found=1
  sid=$(jq -r '.session_id' "$f" 2>/dev/null)
  project=$(jq -r '.project' "$f" 2>/dev/null)
  state=$(jq -r '.state' "$f" 2>/dev/null)
  ts=$(jq -r '.ts' "$f" 2>/dev/null)
  age=$(( now - ${ts%.*} ))
  ic=$(icon "$state")
  flag=""
  if [ "$state" = "working" ] && [ "$age" -gt 600 ]; then ic="🔴"; flag=" [stale?]"; fi
  title="$title$ic"
  menu="$menu\n$ic $project — ${state}${flag} (${age}s ago) | color=$(color "$state")"
done

if [ "$found" -eq 0 ]; then
  echo "◌ | color=gray"
  echo "---"
  echo "No Devin sessions reporting | color=gray"
else
  echo "$title | ansi=true emojize=false"
  echo "---"
  printf "%b" "$menu"
fi
echo "---"
echo "Refresh | refresh=true"
