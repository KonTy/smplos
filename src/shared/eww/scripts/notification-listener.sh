#!/bin/bash
# EWW notification listener (dunst)
# Output: single-line JSON {"count","icon","paused"}
# Icons: bell outline (empty), bell filled (has notifications), bell-slash (paused)

emit() {
  local count paused icon

  if ! command -v dunstctl &>/dev/null; then
    echo '{"count":"0","icon":"󰂜","paused":"no"}'
    return
  fi

  count=$(dunstctl count history 2>/dev/null || echo 0)
  paused=$(dunstctl is-paused 2>/dev/null || echo false)

  if [[ "$paused" == "true" ]]; then
    icon="󰂛"; paused="yes"           # bell-slash (DND)
  elif [[ "$count" -gt 0 ]]; then
    icon="󰂞"; paused="no"            # bell-ring (has notifications)
  else
    icon="󰂜"; paused="no"            # bell-outline (empty)
  fi

  printf '{"count":"%s","icon":"%s","paused":"%s"}\n' "$count" "$icon" "$paused"
}

emit

# dunst doesn't have a subscribe mechanism, poll every 3s
while sleep 3; do emit; done
