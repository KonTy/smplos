#!/bin/bash
# Migration: Harden the "Exit Hyprland" keybinding.
#
# Context: bindings.conf shipped `bindd = SUPER SHIFT, E, Exit Hyprland, exit`
#          — trivially easy to fat-finger while doing anything else. Reports
#          of accidental exits during workspace binds (SUPER+SHIFT+number)
#          when the finger slipped one key over. Nuke the compositor session
#          without warning, lose all in-progress work.
#
# Fix:     Change the modifier chord to SUPER+CTRL+ALT+SHIFT+E. Requires a
#          deliberate 4-key claw and is essentially impossible to hit by
#          accident. Matches the niri equivalent (Mod+Ctrl+Shift+Alt+e) so
#          the two compositors stay consistent.
#
# Safety:  Idempotent — grep guard bails cleanly when the file already has
#          the safe combo, or when the file doesn't exist. Only rewrites the
#          single line; every other user-customised binding is preserved.
#          Backs up before touching so a bad sed can't strand the user.
#          Never fatal — exits 0 even on failure so Update OS keeps going.

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

# bindings_loader.lua reads ~/.config/smplos/bindings.conf FIRST, then falls
# back to ~/.config/hypr/bindings.conf. Both are user-owned + preserved by
# smplos-os-update (bindings.conf is on the "protected" list because Settings
# → Keyboard writes it), so template updates never propagate here — that's
# why this migration exists. Rewrite either / both if the old easy-to-hit
# combo is present.

harden_file() {
    local conf="$1"

    if [[ ! -f "$conf" ]]; then
        return 0
    fi

    # Idempotent guard
    if grep -qE '^bindd\s*=\s*SUPER\s+CTRL\s+ALT\s+SHIFT\s*,\s*E\s*,\s*Exit\s+Hyprland' "$conf"; then
        echo "  $conf: already hardened"
        return 0
    fi

    if ! grep -qE '^bindd\s*=\s*SUPER\s+SHIFT\s*,\s*E\s*,\s*Exit\s+Hyprland' "$conf"; then
        echo "  $conf: no SUPER+SHIFT+E exit binding found — leaving alone"
        return 0
    fi

    local bak="$conf.pre-exit-hardening.$(date +%s)"
    cp -f "$conf" "$bak" 2>/dev/null || {
        echo "  $conf: WARNING backup failed — skipping"
        return 0
    }

    if sed -i -E 's|^bindd[[:space:]]*=[[:space:]]*SUPER[[:space:]]+SHIFT[[:space:]]*,[[:space:]]*E[[:space:]]*,[[:space:]]*Exit[[:space:]]+Hyprland[[:space:]]*,[[:space:]]*exit[[:space:]]*$|bindd = SUPER CTRL ALT SHIFT, E, Exit Hyprland, exit|' "$conf"; then
        echo "  $conf: SUPER+SHIFT+E → SUPER+CTRL+ALT+SHIFT+E (backup $bak)"
    else
        echo "  $conf: WARNING sed failed"
    fi
}

harden_file "$HOME/.config/smplos/bindings.conf"
harden_file "$HOME/.config/hypr/bindings.conf"

# Live-reload if we're inside a Hyprland session.
# Was guarded on $HYPRLAND_INSTANCE_SIGNATURE, which pkexec strips — so this
# step silently skipped on every Update OS run.
if smplos_have_hyprland; then
    smplos_run_as_user hyprctl reload >/dev/null 2>&1 || true
fi

exit 0
