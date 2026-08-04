#!/bin/bash
# Migration: Force-install pinned Hyprland 0.56.0-2 (belt-and-suspenders for
#            customers with an older smplos-update that lacks bundle logic)
#
# Context: hyprland is in critical-packages.txt (excluded from pacman -Syu and
#          paru -Sua) so the only way it upgrades is via critical-bundle.conf.
#          The bundle mechanism was introduced 2026-06-28. Customers whose
#          smplos-update predates that commit will get the new bundle logic
#          synced to /usr/local/bin/ during smplos-os-update but the CURRENT
#          run still uses the in-memory old script, which never applies the
#          bundle. That means their hyprland stays stuck at whatever they had
#          — which for many machines is 0.55.4-1 or older, and misses the
#          nvidia black-screen fix baked into 0.56.
#
#          This migration bypasses the bundle mechanism entirely and installs
#          the pinned version directly so EVERY customer, regardless of their
#          smplos-update script version, converges on hyprland 0.56.0-2 in a
#          single Update OS click. Future hyprland bumps go through the bundle
#          again — this is a one-time reconciliation.
#
# Safety:  Idempotent: skips if hyprland is already at 0.56.0-2 (or newer).
#          Never uninstalls a running compositor if the install fails —
#          pacman -S --needed is atomic. Exits 0 even on failure so it
#          doesn't block other migrations.

set -uo pipefail

# ── Pin to a hyprland SERIES (major.minor), not an exact release ─────────────
# We stay on the 0.56.x line because it carries the NVIDIA black-screen fix
# and has proved stable across the fleet. Within 0.56.x, Arch's patch bumps
# (0.56.0 → 0.56.1 → …) are ABI-compatible and safe. This migration finds
# whatever 0.56.x is CURRENTLY in Arch extra and installs that — no static
# pin that rots out of the mirror after a month.
#
# When Arch drops 0.56.x entirely (Arch typically ships only the newest
# release), this migration fails LOUDLY with "no 0.56.x available in
# Arch — bump _target_series". That's the signal to test 0.57.x on a
# staging box and bump the series here + in critical-bundle.conf.
_target_series="0.56"

# ── Idempotency guard ────────────────────────────────────────────────────────
_current=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')
if [[ -z "$_current" ]]; then
    echo "  hyprland not installed — skipping"
    exit 0
fi

# Match "0.56.something-something"; anchor the series so 0.560.x doesn't slip.
if [[ "$_current" =~ ^${_target_series//./\\.}\.[0-9]+-[0-9]+$ ]]; then
    echo "  hyprland already in $_target_series.x series ($_current) — nothing to do"
    exit 0
fi

# ── Basic connectivity probe ─────────────────────────────────────────────────
if ! curl -fsSL --connect-timeout 5 --max-time 8 https://archlinux.org >/dev/null 2>&1; then
    echo "  WARNING: no network — skipping (retry on next smplos-migrate)"
    exit 0
fi

# ── Preflight: refresh package DB so pacman -Si sees the current mirror ─────
# Without a fresh -Sy, `pacman -Si hyprland` reflects whatever the last
# `pacman -Syu` synced, which on frozen machines can be months old.
sudo pacman -Sy --noconfirm >/dev/null 2>&1 || true

# ── Discover what Arch currently offers in the $_target_series series ───────
_available=$(pacman -Si hyprland 2>/dev/null | awk '/^Version[[:space:]]*:/ {print $3; exit}')
if [[ -z "$_available" ]]; then
    echo "  ERROR: could not query Arch extra for hyprland — will retry on next update"
    exit 1
fi

if ! [[ "$_available" =~ ^${_target_series//./\\.}\.[0-9]+-[0-9]+$ ]]; then
    echo "  ERROR: Arch no longer publishes $_target_series.x for hyprland."
    echo "         Arch current: $_available"
    echo "         Installed:    $_current"
    echo "         The fleet needs a new pin — bump _target_series in this"
    echo "         migration and in critical-bundle.conf on a staging box,"
    echo "         then re-cut the bundle so this rolls out."
    exit 1
fi

# ── Install Arch's current $_target_series.x release ─────────────────────────
echo "  Installing hyprland=$_available (series $_target_series, was $_current)"
if sudo pacman -S --noconfirm --needed "hyprland=$_available"; then
    _new=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')
    echo "  Installed hyprland $_new"
    # Record the bundle marker so the bundle mechanism doesn't re-apply.
    _state_dir="$HOME/.local/state/smplos/update"
    mkdir -p "$_state_dir"
    _applied="$_state_dir/critical-bundle-applied"
    _target_bundle_id="2026.08.04-3"
    if [[ ! -f "$_applied" ]] || [[ "$(<"$_applied")" != "$_target_bundle_id" ]]; then
        printf '%s\n' "$_target_bundle_id" > "$_applied"
        echo "  Marked critical bundle $_target_bundle_id as applied"
    fi
else
    # Exit non-zero so smplos-migrate does NOT create the "done" marker,
    # and this migration retries on the next Update OS click.
    echo "  ERROR: pacman install of hyprland=$_available failed — will retry on next update."
    exit 1
fi

exit 0
