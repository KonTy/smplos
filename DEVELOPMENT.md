# smplOS Development Guide

How to extend, modify, and contribute to smplOS.

---

## Table of Contents

- [Development Iteration](#development-iteration)
- [VM Testing](#vm-testing)
- [Adding a Settings Entry](#adding-a-settings-entry)

---

## Development Iteration

For config/script changes, avoid full ISO rebuilds (~15 min). Instead, push changes directly to a running VM:

```bash
# Host: push changes to VM shared folder
cd release && ./dev-push.sh eww    # or: bin, hypr, themes, all

# VM: apply changes to the live system
sudo bash /mnt/dev-apply.sh
```

ISO rebuilds are only needed when adding or removing **packages**.

## VM Testing

Use QEMU for testing -- it provides a `virtio-gpu` device that Hyprland works with out of the box:

```bash
cd release && ./test-iso.sh
```

This launches a QEMU VM with KVM acceleration, UEFI firmware, a 20 GB virtual disk, and a 9p shared folder for live hot-reloading. The script auto-detects OVMF, finds the newest ISO in `release/`, and opens the VM window.

Once the VM boots, mount the shared folder to enable hot-reload:

```bash
# Inside the VM:
sudo mount -t 9p -o trans=virtio hostshare /mnt
```

Then iterate without rebuilding the ISO:

```bash
# Host: push changes to the shared folder
cd release && ./dev-push.sh

# VM: apply them to the live system
sudo bash /mnt/dev-apply.sh
```

The 9p mount is live -- `dev-push.sh` writes to `release/vmshare/` and changes are immediately visible inside the VM. No remount needed.

Use `--reset` to wipe the VM disk and start fresh:

```bash
./test-iso.sh --reset
```

> **VirtualBox is not supported.** Hyprland requires a working DRM/KMS device with OpenGL support. VirtualBox's virtual GPU (`VBoxVGA` / `VMSVGA`) does not provide this -- Hyprland will crash immediately on startup. Use QEMU with KVM (`test-iso.sh`) or VMware with 3D acceleration instead.

---

## Adding a Settings Entry

The start menu has a **Settings** category. Each entry there launches a system tool -- Appearance opens the theme picker, Audio opens pavucontrol, etc. Here's how to add a new one.

### Overview

Settings entries involve two pieces:

| File | Role |
|------|------|
| `src/shared/bin/rebuild-app-cache` | Registers the entry in the app index |
| `src/shared/bin/smplos-settings` | Dispatches the entry to the right tool |

The flow:

```
rebuild-app-cache          builds ~/.cache/smplos/app_index
       |
start-menu                 reads app_index, shows entries by category
       |
user clicks an entry       start-menu executes the command
       |
smplos-settings <category> dispatches to the right tool
```

### Step 1: Register the entry in the app cache

Open `src/shared/bin/rebuild-app-cache` and find the `emit_settings()` function. Add a line in the heredoc:

```bash
emit_settings() {
  cat <<'EOF'
App Center;toggle-app-center;settings;system-software-install
Web Apps;webapp-center;settings;applications-internet
Appearance;smplos-settings appearance;settings;preferences-desktop-theme
Display;smplos-settings display;settings;preferences-desktop-display
Keyboard;smplos-settings keyboard;settings;preferences-desktop-keyboard
Network;smplos-settings network;settings;preferences-system-network
Bluetooth;smplos-settings bluetooth;settings;bluetooth
Audio;smplos-settings audio;settings;audio-volume-high
My New Entry;smplos-settings my-entry;settings;my-icon-name    # <-- add here
Power Menu;smplos-settings power;settings;system-shutdown
About smplOS;smplos-settings about;settings;help-about
EOF
}
```

The format is semicolon-delimited:

```
Name;Command;Category;Icon
```

| Field | Description |
|-------|-------------|
| **Name** | What the user sees in the start menu |
| **Command** | What gets executed when the entry is selected |
| **Category** | Must be `settings` to appear in the Settings tab |
| **Icon** | A freedesktop icon name (from your icon theme) or leave empty |

> **Tip:** Browse available icon names with `gtk3-icon-browser` or check `/usr/share/icons/`. Common settings icons: `preferences-desktop-*`, `preferences-system-*`, `audio-*`, `network-*`, `input-keyboard`, `bluetooth`.

### Step 2: Add the dispatcher case

Open `src/shared/bin/smplos-settings` and add a `case` branch for your new category:

```bash
  my-entry)
    command -v my-tool &>/dev/null && exec my-tool
    die "my-tool not found (install my-tool-package)"
    ;;
```

**Cross-compositor pattern:** If the tool differs between Wayland and X11, detect at runtime:

```bash
  my-entry)
    if [[ -n "$WAYLAND_DISPLAY" ]]; then
      command -v wayland-tool &>/dev/null && exec wayland-tool
    else
      command -v x11-tool &>/dev/null && exec x11-tool
    fi
    die "No tool found for my-entry"
    ;;
```

**Terminal-based tools:** If the tool is a TUI (runs in a terminal), use the `term()` helper:

```bash
  my-entry)
    command -v my-tui &>/dev/null && exec term my-tui
    die "my-tui not found"
    ;;
```

Don't forget to update the usage string at the bottom of the file:

```bash
  *)
    echo "Usage: smplos-settings {appearance|display|keyboard|...|my-entry|...}" >&2
    exit 1
    ;;
```

### Step 3: Rebuild the cache and test

```bash
# Rebuild the app index
rebuild-app-cache

# Open the start menu and click the Settings category
```

Your new entry should appear in the list. Click it (or press Enter) to launch.

If you're iterating in a VM:

```bash
# Host
cd release && ./dev-push.sh bin

# VM
sudo bash /mnt/dev-apply.sh
rebuild-app-cache
```

### Example: the Keyboard entry

Here's the real commit that added the Keyboard Center to the settings menu:

**`rebuild-app-cache` -- `emit_settings()`:**
```
Keyboard;smplos-settings keyboard;settings;preferences-desktop-keyboard
```

**`smplos-settings` -- new case:**
```bash
  keyboard)
    command -v kb-center &>/dev/null && exec kb-center
    die "Keyboard Center not found"
    ;;
```

Two lines of code, and Keyboard Center appears in the start menu's Settings category.
