#!/bin/bash
# EWW USB storage listener
# Output: single-line JSON {"present","count","icon"}

emit() {
  local count present icon

  count=$(find /dev/disk/by-id/ -name '*usb*' -not -name '*part*' 2>/dev/null | wc -l)

  if (( count > 0 )); then
    present="yes"; icon="󰕓"
  else
    present="no"; icon=""
  fi

  printf '{"present":"%s","count":"%s","icon":"%s"}\n' "$present" "$count" "$icon"
}

emit

# Watch for device changes via udevadm
if command -v udevadm &>/dev/null; then
  udevadm monitor --subsystem-match=block --property 2>/dev/null | while read -r line; do
    [[ "$line" == *"ACTION="* ]] && emit
  done
else
  while sleep 5; do emit; done
fi
