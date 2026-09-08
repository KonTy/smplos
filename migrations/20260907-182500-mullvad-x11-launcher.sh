#!/bin/bash
# Migration: Force Mullvad VPN GUI through XWayland.
#
# Context: smplOS globally prefers native Wayland for Electron/Chromium apps.
#          Mullvad VPN 2026.3's Electron Wayland path can leave a blank,
#          semi-transparent 320x568 surface on Hyprland. Launching the same GUI
#          through XWayland renders normally, while the VPN daemon remains
#          unchanged.
# Safety:  Idempotent. Rewrites only the Exec= line in Mullvad's desktop entry
#          and leaves missing/non-Mullvad installs alone.

set -uo pipefail

DESKTOP_FILE="/usr/share/applications/mullvad-vpn.desktop"
EXPECTED_EXEC='Exec=env ELECTRON_OZONE_PLATFORM_HINT=x11 OZONE_PLATFORM=x11 "/opt/Mullvad VPN/mullvad-vpn" --ozone-platform=x11 %U'

if [[ ! -f "$DESKTOP_FILE" ]]; then
    echo "  Mullvad desktop entry not found - skipping"
    exit 0
fi

current_exec=$(grep -m1 '^Exec=' "$DESKTOP_FILE" 2>/dev/null || true)
if [[ "$current_exec" == "$EXPECTED_EXEC" ]]; then
    echo "  Mullvad desktop entry already forces XWayland"
    exit 0
fi

if [[ "$current_exec" != Exec=*mullvad* ]]; then
    echo "  Mullvad desktop entry has unexpected Exec line - leaving alone"
    exit 0
fi

backup="${DESKTOP_FILE}.pre-xwayland-fix.$(date +%s)"

if [[ $EUID -eq 0 ]]; then
    cp -f "$DESKTOP_FILE" "$backup" 2>/dev/null || {
        echo "  WARNING: could not back up Mullvad desktop entry - skipping"
        exit 0
    }
    sed -i "s|^Exec=.*|$EXPECTED_EXEC|" "$DESKTOP_FILE" 2>/dev/null || {
        echo "  WARNING: could not patch Mullvad desktop entry"
        exit 0
    }
else
    sudo cp -f "$DESKTOP_FILE" "$backup" 2>/dev/null || {
        echo "  WARNING: could not back up Mullvad desktop entry - skipping"
        exit 0
    }
    sudo sed -i "s|^Exec=.*|$EXPECTED_EXEC|" "$DESKTOP_FILE" 2>/dev/null || {
        echo "  WARNING: could not patch Mullvad desktop entry"
        exit 0
    }
fi

echo "  Patched Mullvad desktop entry to launch via XWayland (backup $backup)"
echo "  Restart Mullvad VPN to use the fixed launcher."
exit 0
