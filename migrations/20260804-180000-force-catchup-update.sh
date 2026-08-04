#!/bin/bash
# Migration: One-click fleet catch-up — force pacman -Syu with the FRESH
#            critical-packages.txt ignore list + apply the current bundle
#            baseline (linux-lts, nvidia-open-dkms, kernel-modules-hook,
#            xdg-desktop-portal-hyprland, hyprland=0.56.0-2).
#
# Context: smplos-update loads critical-packages.txt into memory at line
#          ~296 (load_critical_packages) BEFORE it calls smplos-os-update
#          (which does the `git pull` that refreshes the file on disk).
#          Result: on ANY given "Update OS" click, the pacman -Syu ignore
#          list used is the STALE version from the PREVIOUS click. New
#          entries — or in our case, the newly-slimmed ignore list — only
#          take effect two clicks later. That is exactly the reason a
#          customer machine can click Update OS repeatedly and still not
#          upgrade hyprland, mesa, linux-lts, etc.
#
#          Migrations run FRESH from the just-pulled repo, so this
#          migration:
#            1. Reads the FRESH critical-packages.txt to build the current
#               --ignore list.
#            2. Re-runs `pacman -Syu` with that fresh list, catching up any
#               packages the parent smplos-update skipped with its stale
#               list. In particular this rolls forward the packages that
#               used to be frozen: kernels, microcode, nvidia stack,
#               mkinitcpio (which triggers initramfs rebuild for the NVIDIA
#               suspend/resume fix), grub, mesa, xdg-desktop-portal (base),
#               hyprpaper/hypridle/hyprlock, hyprsunset/hyprpicker.
#            3. Applies the current critical-bundle.conf baseline via
#               `pacman -S --needed`. This covers customers whose installed
#               smplos-update predates the bundle-prompt logic (introduced
#               fd2944e, 2026-06-28) and would otherwise never install
#               linux-lts / nvidia-open-dkms / kernel-modules-hook /
#               xdg-desktop-portal-hyprland / the hyprland=0.56.0-2 pin.
#            4. Writes the bundle-applied marker so post-fd2944e customers'
#               smplos-update doesn't then prompt for the same bundle.
#            5. Rebuilds the initramfs so the NVIDIA modprobe options
#               (see 20260701-011500-nvidia-suspend-resume.sh) load early.
#
# Safety: every step is idempotent and exits 0 on failure so downstream
#         migrations still run. Skips gracefully offline.

set -uo pipefail

SMPLOS_PATH="${SMPLOS_PATH:-$HOME/.local/share/smplos}"
POLICY_DIR="$SMPLOS_PATH/repo/src/shared/update-policy"
CRITICAL_LIST_FILE="$POLICY_DIR/critical-packages.txt"
CRITICAL_BUNDLE_FILE="$POLICY_DIR/critical-bundle.conf"
STATE_DIR="$HOME/.local/state/smplos/update"
APPLIED_BUNDLE_FILE="$STATE_DIR/critical-bundle-applied"

# ── Prerequisites ────────────────────────────────────────────────────────────
if [[ ! -f "$CRITICAL_LIST_FILE" ]] || [[ ! -f "$CRITICAL_BUNDLE_FILE" ]]; then
    echo "  WARNING: update-policy files missing at $POLICY_DIR — skipping"
    exit 0
fi

if ! curl -fsSL --connect-timeout 5 --max-time 8 https://archlinux.org >/dev/null 2>&1; then
    echo "  WARNING: no network — skipping (will retry on next smplos-migrate)"
    exit 0
fi

# ── 1. Build fresh ignore list from the just-pulled critical-packages.txt ────
FRESH_IGNORE_ARR=()
while IFS= read -r line; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    FRESH_IGNORE_ARR+=("$line")
done < "$CRITICAL_LIST_FILE"

# Comma-join for pacman --ignore.
FRESH_IGNORE=""
for p in "${FRESH_IGNORE_ARR[@]}"; do
    FRESH_IGNORE="${FRESH_IGNORE:+$FRESH_IGNORE,}$p"
done
echo "  Fresh ignore list: ${FRESH_IGNORE:-<empty>}"

# ── 2. Second-pass pacman -Syu with the fresh (short) ignore list ────────────
# This catches every package the parent smplos-update skipped with its
# stale in-memory ignore list.
echo "  Running pacman -Syu with fresh ignore list..."
if [[ -n "$FRESH_IGNORE" ]]; then
    if ! sudo pacman -Syu --noconfirm --ignore "$FRESH_IGNORE"; then
        echo "  WARNING: catch-up pacman -Syu failed — non-fatal, continuing"
    fi
else
    if ! sudo pacman -Syu --noconfirm; then
        echo "  WARNING: catch-up pacman -Syu failed — non-fatal, continuing"
    fi
fi

# ── 3. Apply critical-bundle.conf baseline ───────────────────────────────────
# Parse BUNDLE_ID and PACKAGES out of the conf file in a sandboxed subshell so
# nothing else in the migration script gets tainted by variable expansion.
_bundle_meta=$(
    # shellcheck disable=SC1090
    . "$CRITICAL_BUNDLE_FILE" 2>/dev/null || true
    printf '%s\n%s\n' "${BUNDLE_ID:-}" "${PACKAGES:-}"
)
BUNDLE_ID=$(printf '%s' "$_bundle_meta" | sed -n '1p')
BUNDLE_PACKAGES=$(printf '%s' "$_bundle_meta" | sed -n '2p')

if [[ -z "$BUNDLE_ID" ]] || [[ -z "$BUNDLE_PACKAGES" ]]; then
    echo "  WARNING: could not parse critical-bundle.conf — skipping bundle apply"
else
    # shellcheck disable=SC2086
    read -ra _bundle_arr <<< "$BUNDLE_PACKAGES"
    echo "  Applying critical bundle $BUNDLE_ID (${#_bundle_arr[@]} packages)..."
    if sudo pacman -S --noconfirm --needed "${_bundle_arr[@]}"; then
        echo "  Bundle applied"
        # ── 4. Write bundle marker ───────────────────────────────────────────
        mkdir -p "$STATE_DIR"
        printf '%s\n' "$BUNDLE_ID" > "$APPLIED_BUNDLE_FILE"
        echo "  Marked bundle $BUNDLE_ID as applied"
    else
        echo "  WARNING: bundle apply failed — machine will be prompted on next click"
    fi
fi

# ── 5. Rebuild initramfs so NVIDIA modprobe options take effect ──────────────
# The nvidia-suspend-resume migration writes /etc/modprobe.d/nvidia.conf, but
# if the kernel was frozen for months, the initramfs may still be stale. This
# is a cheap belt-and-suspenders — mkinitcpio is a no-op when everything's
# already current.
if lspci 2>/dev/null | grep -qi 'nvidia' && command -v mkinitcpio &>/dev/null; then
    echo "  Rebuilding initramfs to pick up NVIDIA power-management options..."
    if ! sudo mkinitcpio -P >/dev/null 2>&1; then
        echo "  WARNING: mkinitcpio -P failed — run manually before next reboot"
    fi
fi

echo "  Fleet catch-up complete."
exit 0
