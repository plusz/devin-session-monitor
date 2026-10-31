#!/bin/bash
# SwiftBar plugin — Devin instance monitor (refresh every 5s)
# Groups by parent Devin process (pid) — one dot per Devin window/instance.
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

rows=$(ls "$DIR"/*.json 2>/dev/null | xargs jq -rs '
  def rank: {"permission":4,"question":3,"working":2,"waiting":1} as $m | ($m[.state] // 0);
  map(. + {key: (. as $s | ($s.pid | if . == null then "s:\($s.session_id)" else "p:\(.)" end))})
  | group_by(.key)
  | map({
      project: (max_by(.ts).project),
      state:   (max_by(rank).state),
      ts:      (map(.ts) | max),
      cnt:     length
    })
  | sort_by(.project)[]
  | [.project, .state, .ts, .cnt] | @tsv
' 2>/dev/null)

if [ -z "$rows" ]; then
  echo "◌ | color=gray"
  echo "---"
  echo "No Devin instances reporting | color=gray"
else
  title=""
  menu=""
  while IFS=$'\t' read -r project state ts cnt; do
    [ -z "$project" ] && continue
    age=$(( now - ${ts%.*} ))
    ic=$(icon "$state")
    flag=""
    if [ "$state" = "working" ] && [ "$age" -gt 600 ]; then ic="🔴"; flag=" [stale?]"; fi
    title="$title$ic"
    cntstr=""; [ "$cnt" -gt 1 ] && cntstr=" ($cnt sessions)"
    menu="$menu\n$ic $project — ${state}${flag}${cntstr} (${age}s ago) | color=$(color "$state")"
  done <<< "$rows"
  echo "$title | ansi=true emojize=false"
  echo "---"
  printf "%b" "$menu"
fi
echo "---"
echo "Refresh | refresh=true"
