#!/bin/bash
# Migration: Suppress hyprshell "Unable to load hyprland plugin" notification
# Context: Since Hyprland 0.55, hyprshell tries to build its plugin at runtime
#          against the current Hyprland headers, but the build fails because
#          of include-path mismatches in upstream Hyprland headers. Hyprshell
#          falls back to default keybinds and Alt-Tab still works fine, but
#          the user sees a scary notification on every boot and config reload.
#
#          Setting HYPRSHELL_NO_USE_PLUGIN=1 tells hyprshell to skip the plugin
#          attempt entirely. This is the upstream-supported way to silence it.
#          We ship this as a system-wide systemd user drop-in.

set -euo pipefail

# ── Session env (see src/shared/lib/smplos-session-env.sh) ──────────────────
# pkexec strips XDG_RUNTIME_DIR / WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE,
# so session-scoped commands must be re-attached to the invoker's session.
# shellcheck source=../src/shared/lib/smplos-session-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../src/shared/lib/smplos-session-env.sh" 2>/dev/null || {
    echo "  WARNING: smplos-session-env.sh not found — skipping session-scoped steps"
    smplos_have_session()  { return 1; }
    smplos_have_hyprland() { return 1; }
    smplos_have_user_bus() { return 1; }
    smplos_run_as_user()   { return 1; }
}

DROPIN_DIR="/etc/systemd/user/hyprshell.service.d"
DROPIN="$DROPIN_DIR/no-plugin.conf"

if [[ -f "$DROPIN" ]] && grep -q "HYPRSHELL_NO_USE_PLUGIN=1" "$DROPIN"; then
    echo "  hyprshell no-plugin drop-in already present, skipping"
    exit 0
fi

echo "  Writing $DROPIN"
sudo mkdir -p "$DROPIN_DIR"
sudo tee "$DROPIN" >/dev/null << 'EOF'
[Service]
Environment=HYPRSHELL_NO_USE_PLUGIN=1
EOF

# `systemctl --user` needs XDG_RUNTIME_DIR to reach the user manager. pkexec
# strips it, so these calls used to abort with "Failed to connect to user scope
# bus" and the drop-in only took effect after the next login.
if smplos_have_user_bus; then
    echo "  Reloading systemd user units"
    smplos_run_as_user systemctl --user daemon-reload 2>/dev/null || true

    if smplos_run_as_user systemctl --user is-active --quiet hyprshell.service 2>/dev/null; then
        echo "  Restarting hyprshell"
        smplos_run_as_user systemctl --user restart hyprshell.service || true
    fi
else
    echo "  No user session bus reachable — drop-in applies on next login"
fi

echo "  Done — the plugin warning will no longer appear"
