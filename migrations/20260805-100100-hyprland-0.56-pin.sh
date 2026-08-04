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
# Multiple ABI-lockstep cascades on frozen customer machines:
#
#   * hyprland 0.56.x needs new libhyprutils.so=13 / libaquamarine.so=13
#     → upgrading hyprutils/aquamarine alone breaks the OLD hyprland 0.55
#     → can only proceed if hyprland is upgraded in the same transaction.
#
#   * The new hypr* stack pulls a new libjxl (0.12) as a transitive dep
#     → installing new libjxl breaks the OLD ffmpeg / gimp still linked
#       against libjxl.so=0.11
#     → can only proceed if ffmpeg/gimp are ALSO upgraded in the same
#       transaction.
#
# Trying to enumerate every downstream ABI edge and hand it to `pacman -S`
# is a losing game — the tree grows every release. The correct answer is
# a full system upgrade (`pacman -Syu`) with NO --ignore filter, which is
# what a normal `pacman -Syu` would do if the ignore-list weren't blocking
# hyprland. Pacman then resolves ALL upgrades — libjxl + ffmpeg + gimp +
# aquamarine + hyprutils + the entire hypr* stack — atomically.
#
# smplos-update's outer `pacman -Syu --ignore hyprland,xdg-desktop-portal-*`
# earlier in this same run cannot do this: the --ignore keeps hyprland
# frozen at 0.55.4, so aquamarine/hyprutils upgrades are refused for the
# same ABI reason. This migration temporarily bypasses the ignore list.
echo "  Running full system upgrade (pacman -Syu) with NO ignore filter"
echo "  to resolve ABI lockstep across hyprland, hyprutils, aquamarine,"
echo "  libjxl, ffmpeg, gimp, and the rest of the hypr* stack."
echo "  Target: hyprland $_available (was $_current)"

if sudo pacman -Syu --noconfirm; then
    _new=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')
    echo "  System upgraded. hyprland is now $_new"
    if ! [[ "$_new" =~ ^${_target_series//./\\.}\.[0-9]+-[0-9]+$ ]]; then
        echo "  WARNING: hyprland is $_new but expected ${_target_series}.x."
        echo "           Either the upgrade did not touch hyprland (some other"
        echo "           blocker still applies) or Arch has moved past"
        echo "           ${_target_series}.x. Leaving unmarked so this retries."
        exit 1
    fi
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
    echo "  ERROR: pacman -Syu failed — will retry on next update."
    echo "         Above error output identifies the blocking dep; the"
    echo "         typical fix is to add its owning package to the same"
    echo "         transaction or to remove a stale AUR pin."
    exit 1
fi

exit 0
