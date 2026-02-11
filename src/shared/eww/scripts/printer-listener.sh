#!/bin/bash
# EWW printer job listener
# Output: single-line JSON {"active","count","icon"}

emit() {
  local count active icon

  if ! command -v lpstat &>/dev/null; then
    echo '{"active":"no","count":"0","icon":""}'
    return
  fi

  count=$(lpstat -o 2>/dev/null | wc -l)

  if (( count > 0 )); then
    active="yes"; icon="󰐪"
  else
    active="no"; icon=""
  fi

  printf '{"active":"%s","count":"%s","icon":"%s"}\n' "$active" "$count" "$icon"
}

emit

while sleep 10; do emit; done
