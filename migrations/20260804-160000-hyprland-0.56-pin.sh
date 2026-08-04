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

_target_pkgver="0.56.0-2"

# ── Idempotency guard ────────────────────────────────────────────────────────
_current=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')
if [[ -z "$_current" ]]; then
    echo "  hyprland not installed — skipping"
    exit 0
fi

if [[ "$_current" == "$_target_pkgver" ]]; then
    echo "  hyprland already at $_target_pkgver — nothing to do"
    exit 0
fi

# vercmp returns positive if $_current > $_target, so we skip only if current is
# already newer (a customer who applied a future bundle bump beyond this pin).
if [[ $(vercmp "$_current" "$_target_pkgver" 2>/dev/null || echo 0) -gt 0 ]]; then
    echo "  hyprland already newer than $_target_pkgver ($_current) — nothing to do"
    exit 0
fi

# ── Basic connectivity probe ─────────────────────────────────────────────────
if ! curl -fsSL --connect-timeout 5 --max-time 8 https://archlinux.org >/dev/null 2>&1; then
    echo "  WARNING: no network — skipping (retry on next smplos-migrate)"
    exit 0
fi

# ── Install pinned version ───────────────────────────────────────────────────
echo "  Installing hyprland=$_target_pkgver (was $_current)"
if sudo pacman -S --noconfirm --needed "hyprland=$_target_pkgver"; then
    echo "  Installed hyprland $(pacman -Q hyprland 2>/dev/null | awk '{print $2}')"
    # Record the state-file marker so the bundle mechanism doesn't re-apply
    # the same set (idempotent with the bundle path).
    _state_dir="$HOME/.local/state/smplos/update"
    mkdir -p "$_state_dir"
    # Only touch the bundle marker if it doesn't already claim a newer bundle.
    _applied="$_state_dir/critical-bundle-applied"
    _target_bundle_id="2026.08.03-1"
    if [[ ! -f "$_applied" ]] || [[ "$(<"$_applied")" != "$_target_bundle_id" ]]; then
        printf '%s\n' "$_target_bundle_id" > "$_applied"
        echo "  Marked critical bundle $_target_bundle_id as applied"
    fi
else
    echo "  WARNING: pacman install failed (target version may no longer be in Arch extra)"
    echo "           Bundle mechanism will retry on next smplos-update run."
fi

exit 0
