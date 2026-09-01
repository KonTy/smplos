#!/bin/bash
# Migration: Enable the packaged hypridle systemd user service.
#
# Context: Historically smplOS relied on Hyprland's `exec-once = hypridle` in
#          the autostart config to launch the idle daemon. That works for the
#          first Hyprland session per boot — but if hypridle ever dies (crash,
#          manual kill during debugging, Wayland reconnect failure) it stays
#          dead until the next full logout/login. Users then see the Settings
#          app cheerfully advertising "Lock 5m / Screen off 5m / Suspend 10m"
#          while nothing actually fires, because there is no daemon running to
#          arm those timeouts. Two people burned by this in the same week
#          triggered the fix.
#
# Fix:     Enable the packaged `hypridle.service` user unit (shipped by the
#          `hypridle` Arch package). The unit has `Restart=on-failure` and is
#          wanted by `graphical-session.target`, so it starts every session and
#          respawns automatically on crash. Enabling it does NOT conflict with
#          the exec-once launch: hypridle refuses to bind Wayland twice, so
#          whichever wins first stays alive and the second exits quietly.
#
# Safety:  Idempotent — `systemctl --user enable` on an already-enabled unit
#          is a no-op. Skips cleanly on systems without the hypridle package
#          (e.g. mid-migration recovery images). Never touches user config.
#          Always exits 0 so a hiccup here can't halt Update OS.

set -uo pipefail

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

UNIT_SRC="/usr/lib/systemd/user/hypridle.service"

if [[ ! -f "$UNIT_SRC" ]]; then
    echo "  hypridle package not installed ($UNIT_SRC missing) — skipping"
    exit 0
fi

# ── Also patch the user's Hyprland Lua autostart to stop it from
#    re-spawning a bare hypridle at every session start.
#
# Hyprland is Lua-configured — hyprland.lua sources autostart.lua for the
# `hyprland.start` event. Older versions of autostart.lua included
# `hl.exec_cmd("hypridle")`, which fires a BARE hypridle from every session
# regardless of what autostart.conf says (the .conf file is only for
# cross-compositor sharing / reference; the .lua is what actually runs).
# We updated sync_hypr_configs to overwrite autostart.lua too, but this
# migration idempotently patches user files that were installed before
# that sync began carrying the fix, and also handles the case where the
# user has customised their autostart.lua and we shouldn't blow it away.
for f in "$HOME/.config/hypr/autostart.lua"; do
    [[ -f "$f" ]] || continue
    if grep -qE '^\s*hl\.exec_cmd\("hypridle"\)' "$f"; then
        bak="$f.pre-hypridle-fix.$(date +%s)"
        cp -f "$f" "$bak" 2>/dev/null || continue
        # Comment out the line rather than delete, so a future user reading
        # the file can see what was there and why.
        sed -i -E 's|^(\s*)(hl\.exec_cmd\("hypridle"\))|\1-- \2  -- disabled: managed by hypridle.service (see .conf note)|' "$f"
        echo "  patched $f to stop respawning bare hypridle (backup $bak)"
    fi
done

# Everything below needs the user's systemd manager. `systemctl --user` reads
# $XDG_RUNTIME_DIR to find it, and pkexec strips that variable — so under Update
# OS every call here aborted with "Failed to connect to user scope bus".
#
# That mattered a lot more than a no-op: the pkill below would still succeed,
# killing the user's running hypridle, and the enable that was supposed to
# replace it would then fail — leaving the machine with NO idle handling (no
# lock, no screen-off) until the next login. Bail out before touching anything
# when the user bus is unreachable.
if ! smplos_have_user_bus; then
    echo "  No user session bus reachable — deferring hypridle service setup"
    echo "  (it will be enabled on the next update run from a graphical session)"
    exit 0
fi

# Kill any bare `hypridle` process that came from the OLD
# `hl.exec_cmd("hypridle")` line in autostart.lua (or the equivalent
# `exec-once = hypridle` in autostart.conf that pre-dates the Lua migration).
# Same-release sync_hypr_configs removes that line from both files, but the
# running Hyprland session already spawned the daemon at session start, so
# it survives until logout. Leaving it alive means the systemd-managed
# instance and the exec-once instance both respond to logind Lock/Sleep
# signals, doubling every after_sleep_cmd. Kill only bare-name matches so
# we don't touch the /usr/bin/hypridle from systemd.
if smplos_run_as_user pgrep -x hypridle >/dev/null 2>&1; then
    # -f matches command line; pgrep -x on the bare name catches the exec-once
    # invocation (argv[0] = "hypridle") without hitting the fullpath one.
    smplos_run_as_user pkill -x hypridle 2>/dev/null || true
    sleep 0.3
    echo "  killed stale bare hypridle (was likely from Hyprland exec-once)"
fi

# Check if already enabled (idempotent guard)
if smplos_run_as_user systemctl --user is-enabled hypridle.service >/dev/null 2>&1; then
    echo "  hypridle.service already enabled — nothing to do"
    # Make sure it's actually running too, in case a prior session left it dead
    if ! smplos_run_as_user systemctl --user is-active hypridle.service >/dev/null 2>&1; then
        smplos_run_as_user systemctl --user start hypridle.service >/dev/null 2>&1 || true
        echo "  started hypridle.service (was inactive)"
    fi
    exit 0
fi

if smplos_run_as_user systemctl --user enable --now hypridle.service >/dev/null 2>&1; then
    echo "  enabled and started hypridle.service"
else
    echo "  WARNING: could not enable hypridle.service — Settings app will fall back to setsid spawn"
fi

exit 0
