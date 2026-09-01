#!/bin/bash
# Migration: Re-deploy stock theme files and re-apply the active theme
# Context: Until v0.7.17, smplos-os-update did not sync src/shared/themes/ to
#          ~/.local/share/smplos/themes/. Stock themes installed from the ISO
#          were never refreshed, so theme CSS fixes (notably the nemo right-click
#          context-menu / submenu / breadcrumb / popup colors that render
#          unreadable black-on-black on dark themes like matrix, catppuccin,
#          matte-black, kanagawa, etc.) shipped via git never reached existing
#          installs even after `smplos-os-update`.
#
#          This migration:
#            1. Copies fresh stock themes from the cloned repo to
#               ~/.local/share/smplos/themes/ (overwrites stock themes only;
#               user themes in ~/.config/smplos/themes/ are untouched)
#            2. Re-runs theme-set on the currently active theme so the deployed
#               files (~/.config/smplos/nemo-theme.css, ~/.config/eww/*, etc.)
#               are regenerated from the up-to-date stock copies.
#
#          From v0.7.17 onward smplos-os-update sync_themes does step 1 on every
#          update; this migration exists only to bring already-installed systems
#          up to date the first time they run it.

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

SMPLOS_PATH="${SMPLOS_PATH:-$HOME/.local/share/smplos}"
SMPLOS_REPO="$SMPLOS_PATH/repo"
THEMES_SRC="$SMPLOS_REPO/src/shared/themes"
THEMES_DST="$SMPLOS_PATH/themes"

if [[ ! -d "$THEMES_SRC" ]]; then
    echo "  Stock theme source not found at $THEMES_SRC, skipping"
    exit 0
fi

mkdir -p "$THEMES_DST"

n_updated=0
for theme_dir in "$THEMES_SRC"/*/; do
    [[ -d "$theme_dir" ]] || continue
    theme_name=$(basename "$theme_dir")
    [[ "$theme_name" == _* ]] && continue

    dst="$THEMES_DST/$theme_name"
    mkdir -p "$dst"
    cp -rT "$theme_dir" "$dst"
    n_updated=$((n_updated + 1))
done
echo "  Refreshed $n_updated stock themes in $THEMES_DST"

# Re-apply the active theme so deployed CSS / configs pick up the new files.
active=""
if [[ -f "$HOME/.config/smplos/current/theme.name" ]]; then
    active=$(< "$HOME/.config/smplos/current/theme.name")
fi
if [[ -n "$active" ]] && command -v theme-set &>/dev/null; then
    # theme-set live-reloads eww, hyprctl and GTK apps, all of which need the
    # graphical session env that pkexec strips. Without it the file writes
    # still land but nothing on screen actually changes.
    if smplos_run_as_user theme-set "$active" >/dev/null 2>&1 \
       || theme-set "$active" >/dev/null 2>&1; then
        echo "  Re-applied active theme: $active"
    else
        echo "  Could not re-apply theme '$active' (theme-set failed)"
    fi
else
    echo "  No active theme recorded; skipping theme reapply"
fi

# Best-effort restart of nemo so the new CSS is loaded immediately. nemo-smpl
# watches ~/.config/smplos/nemo-theme.css via GFileMonitor and reloads live, but
# restarting guarantees a clean state if a window was already open.
if pgrep -x nemo >/dev/null 2>&1; then
    pkill -x nemo 2>/dev/null || true
    sleep 1
    setsid nemo >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null || true
    echo "  Restarted nemo to load updated theme CSS"
fi
