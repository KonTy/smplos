#!/bin/bash
# EWW USB storage listener
# Output: single-line JSON with device list for the USB popup
# {"present","count","icon","devices":[{"name","path","size","label"},...]}

emit() {
  local devices_json="[]"
  local count=0

  # Find mounted removable devices (udiskie mounts to /run/media/$USER/)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local dev mount fstype
    dev=$(echo "$line" | awk '{print $1}')
    mount=$(echo "$line" | awk '{print $2}')
    fstype=$(echo "$line" | awk '{print $3}')

    # Skip non-removable mounts
    local dev_base
    dev_base=$(basename "$dev" | sed 's/[0-9]*$//')
    [[ -f "/sys/block/$dev_base/removable" ]] || continue
    [[ "$(cat "/sys/block/$dev_base/removable" 2>/dev/null)" == "1" ]] || continue

    local label size
    label=$(lsblk -no LABEL "$dev" 2>/dev/null | head -1)
    size=$(lsblk -no SIZE "$dev" 2>/dev/null | head -1 | tr -d ' ')
    [[ -z "$label" ]] && label=$(basename "$mount")

    # Escape quotes in label
    label="${label//\"/\\\"}"

    local entry
    entry=$(printf '{"name":"%s","path":"%s","size":"%s","label":"%s"}' \
      "$(basename "$dev")" "$mount" "$size" "$label")

    if [[ "$devices_json" == "[]" ]]; then
      devices_json="[$entry"
    else
      devices_json="$devices_json,$entry"
    fi
    ((count++))
  done < <(findmnt -rno SOURCE,TARGET,FSTYPE -t vfat,ntfs,ntfs3,exfat,ext4,btrfs,xfs 2>/dev/null \
    | grep -E "^/dev/sd|^/dev/nvme" | grep "/run/media/")

  # Also check for unmounted USB block devices (plugged in but not mounted)
  local unmounted=0
  while IFS= read -r dev; do
    [[ -z "$dev" ]] && continue
    local dev_path="/dev/$(basename "$(readlink -f "$dev")")"
    # Skip if already counted as mounted
    findmnt -rno SOURCE "$dev_path" &>/dev/null && continue
    ((unmounted++))
  done < <(find /dev/disk/by-id/ -name '*usb*' -not -name '*part*' 2>/dev/null)

  local total=$((count + unmounted))
  [[ "$devices_json" != "[]" ]] && devices_json="$devices_json]" || devices_json="[]"

  local present icon
  if (( total > 0 )); then
    present="yes"; icon="󰕓"
  else
    present="no"; icon=""
  fi

  printf '{"present":"%s","count":"%s","icon":"%s","mounted":"%s","devices":%s}\n' \
    "$present" "$total" "$icon" "$count" "$devices_json"
}

# Debounce: udevadm fires multiple events per device action
last_emit=0
debounced_emit() {
  local now
  now=$(date +%s)
  (( now - last_emit < 2 )) && return
  last_emit=$now
  emit
}

emit

# Watch for device changes via udevadm
if command -v udevadm &>/dev/null; then
  udevadm monitor --subsystem-match=block --property 2>/dev/null | while read -r line; do
    [[ "$line" == *"ACTION="* ]] && debounced_emit
  done
else
  while sleep 5; do emit; done
fi
