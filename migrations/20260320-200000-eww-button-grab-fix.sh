#!/bin/bash
# Migration: Remove EWW button click sleep workarounds
# Context: The EWW button widget had a pointer-grab bug on Wayland where
#          clicking a button that opens a window would leave the pointer grab
#          stuck, requiring the user to wiggle the mouse before clicking again.
#          We added "sleep 0.05 &&" workarounds to all tray button onclick
#          handlers. With the patched EWW binary (eww-0.6.0-2, which replaces
#          emit_activate() with manual CSS state management), the root cause
#          is fixed and the workarounds should be removed.

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

EWW_YUCK="$HOME/.config/eww/eww.yuck"

if [[ ! -f "$EWW_YUCK" ]]; then
    echo "  eww.yuck not found, skipping"
    exit 0
fi

# Check if any sleep workarounds exist
if ! grep -q 'sleep 0\.05' "$EWW_YUCK"; then
    echo "  No sleep workarounds found in eww.yuck, already clean"
    exit 0
fi

# Remove "sleep 0.05 && " prefix and trailing " &" from onclick handlers
# Pattern: :onclick "sleep 0.05 && <command> &"  →  :onclick "<command>"
sed -i 's/:onclick "sleep 0\.05 && \(.*\) &"/:onclick "\1"/g' "$EWW_YUCK"

# grep -c prints "0" *and* exits 1 when there are no matches, so a
# `|| echo 0` fallback would append a second line and break the -gt test.
n_remaining=$(grep -c 'sleep 0\.05' "$EWW_YUCK" 2>/dev/null) || n_remaining=0
if [[ "$n_remaining" -gt 0 ]]; then
    echo "  WARNING: $n_remaining sleep workaround(s) remain — manual check needed"
else
    echo "  Removed sleep workarounds from eww.yuck"
fi

# ── Restart the EWW bar so the yuck change takes effect ─────────────────────
# SAFETY INVARIANT: only kill the daemon if we can start it again.
#
# Migrations run under pkexec, which strips XDG_RUNTIME_DIR and
# WAYLAND_DISPLAY. Without them `eww kill` still succeeds but every restart
# creates its IPC socket under /tmp instead of /run/user/<uid> and then dies
# with "Failed to initialize GTK" — leaving the user with no bar at all.
if pgrep -x eww &>/dev/null; then
    if smplos_have_session; then
        smplos_run_as_user eww --config "${SMPLOS_SESSION_HOME:-$HOME}/.config/eww" kill \
            &>/dev/null || true
        sleep 0.5
        if smplos_run_as_user bar-ctl start &>/dev/null; then
            echo "  Restarted EWW bar"
        else
            echo "  WARNING: bar restart failed — run 'bar-ctl start' manually"
        fi
    else
        echo "  No graphical session detected — NOT restarting the bar"
        echo "  (tearing it down here would leave you with no bar until re-login)."
        echo "  Run 'bar-ctl start', or log out and back in, to apply the change."
    fi
fi
