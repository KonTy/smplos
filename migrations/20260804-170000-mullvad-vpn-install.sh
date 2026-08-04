#!/bin/bash
# Migration: Install Mullvad VPN on existing customer machines
#
# Context: mullvad-vpn-bin is registered as a default AUR-style package in
#          src/shared/packages-aur.txt (installed on every edition at ISO
#          build time). Customer machines built from older ISOs — before
#          the mullvad-vpn-bin PKGBUILD landed on main — never got it, and
#          `smplos-update` only runs `pacman -Syu`, which cannot install
#          new packages (only upgrade existing ones).
#
#          This migration builds src/shared/pkgbuilds/mullvad-vpn-bin/ from
#          the local repo clone and installs it. The PKGBUILD verifies the
#          upstream .deb by pinned SHA-256 + pinned Mullvad PGP fingerprint,
#          so the trust chain matches the ISO build.
#
# Safety:  Idempotent — exits 0 if mullvad-vpn-bin is already installed.
#          Exits 0 on any prerequisite failure (offline, no makepkg, no
#          PKGBUILD synced yet) so it never blocks other migrations. The
#          bundled .install hook enables mullvad-daemon.service on first
#          install; no separate systemctl call needed here.

set -uo pipefail

# ── Idempotency guards ───────────────────────────────────────────────────────
if pacman -Q mullvad-vpn-bin &>/dev/null; then
    echo "  mullvad-vpn-bin already installed — nothing to do"
    exit 0
fi

# ── Prerequisites ────────────────────────────────────────────────────────────
SMPLOS_PATH="${SMPLOS_PATH:-$HOME/.local/share/smplos}"
PKGBUILD_DIR="$SMPLOS_PATH/repo/src/shared/pkgbuilds/mullvad-vpn-bin"

if [[ ! -f "$PKGBUILD_DIR/PKGBUILD" ]]; then
    echo "  WARNING: $PKGBUILD_DIR/PKGBUILD not found — skipping"
    echo "  Re-run smplos-migrate after the next 'Update OS'."
    exit 0
fi

for dep in makepkg gpg curl; do
    if ! command -v "$dep" &>/dev/null; then
        echo "  WARNING: $dep not found (install base-devel + gnupg) — skipping"
        exit 0
    fi
done

# The PKGBUILD downloads the .deb from cdn.mullvad.net; skip if offline.
if ! curl -fsSL --connect-timeout 5 --max-time 8 https://cdn.mullvad.net >/dev/null 2>&1; then
    echo "  WARNING: cdn.mullvad.net unreachable — skipping (will retry next migrate)"
    exit 0
fi

# ── Build in a scratch dir owned by the invoking user ────────────────────────
BUILD_DIR=$(mktemp -d /tmp/mullvad-vpn-bin-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT

# Copy the whole pkgbuild dir (need the embedded gpg key + .install alongside).
cp -a "$PKGBUILD_DIR"/. "$BUILD_DIR/"
# Drop any stale build artifacts the source dir might carry.
rm -rf "$BUILD_DIR/pkg" "$BUILD_DIR/src" "$BUILD_DIR"/*.pkg.tar.* 2>/dev/null || true

echo "  Building mullvad-vpn-bin (fetch + verify signed .deb from cdn.mullvad.net)..."
if [[ $EUID -eq 0 ]]; then
    sudo useradd -m -r _mvbuild 2>/dev/null || true
    sudo chown -R _mvbuild:_mvbuild "$BUILD_DIR"
    if ! sudo -u _mvbuild bash -c "cd '$BUILD_DIR' && makepkg -s --noconfirm --skippgpcheck"; then
        echo "  ERROR: makepkg failed — skipping"
        sudo userdel -r _mvbuild 2>/dev/null || true
        exit 0
    fi
    sudo userdel -r _mvbuild 2>/dev/null || true
else
    if ! (cd "$BUILD_DIR" && makepkg -s --noconfirm --skippgpcheck); then
        echo "  ERROR: makepkg failed — skipping"
        exit 0
    fi
fi

# ── Install the freshly built package ────────────────────────────────────────
PKG_FILE=$(ls "$BUILD_DIR"/mullvad-vpn-bin-*.pkg.tar.* 2>/dev/null | head -1)
if [[ ! -f "$PKG_FILE" ]]; then
    echo "  ERROR: makepkg produced no package file — skipping"
    exit 0
fi

if ! sudo pacman -U --noconfirm "$PKG_FILE"; then
    echo "  ERROR: pacman -U failed — skipping"
    exit 0
fi

echo "  Installed $(pacman -Q mullvad-vpn-bin 2>/dev/null | awk '{print $1" "$2}')"
echo "  mullvad-daemon.service enabled by the pkgbuild's .install hook."
echo "  Next step for the user: 'mullvad account login' + 'mullvad connect'."
exit 0
