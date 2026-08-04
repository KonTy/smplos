#!/bin/bash
# Migration: Install eww-smplos (fork with Wayland button-grab fixes)
#
# Context: Vanilla AUR `eww` (upstream tag v0.6.0) has a bug where clicking
#          a button on the eww bar frequently no-ops until the mouse is moved
#          — GTK's default button-press handler installs an implicit pointer
#          grab that Wayland never sees released. The smplOS fork at
#          github.com/smpl-os/eww adds two commits on top of upstream master
#          that fix this (78105f3, 169e47a). Every customer machine currently
#          has vanilla `eww` and hits this bug.
#
#          This migration builds eww-smplos from src/shared/pkgbuilds/eww-smplos/
#          and installs it. The PKGBUILD's provides=/conflicts=/replaces=eww
#          make pacman -U swap the two cleanly.
#
# Safety:  Idempotent — exits early if eww-smplos is already installed. Never
#          uninstalls the running eww if the build/install fails (the old
#          package stays functional). Exits 0 even on failure so it doesn't
#          block other migrations; the user can re-run smplos-migrate later
#          when they're online or after installing base-devel.

set -uo pipefail

# ── Idempotency guards ───────────────────────────────────────────────────────
if pacman -Q eww-smplos &>/dev/null; then
    echo "  eww-smplos already installed — nothing to do"
    exit 0
fi

# ── Prerequisites ────────────────────────────────────────────────────────────
SMPLOS_PATH="${SMPLOS_PATH:-$HOME/.local/share/smplos}"
PKGBUILD_DIR="$SMPLOS_PATH/repo/src/shared/pkgbuilds/eww-smplos"

if [[ ! -f "$PKGBUILD_DIR/PKGBUILD" ]]; then
    echo "  WARNING: $PKGBUILD_DIR/PKGBUILD not found — skipping"
    echo "  Re-run smplos-migrate after the next 'Update OS'."
    exit 0
fi

for dep in makepkg git curl; do
    if ! command -v "$dep" &>/dev/null; then
        echo "  WARNING: $dep not found (install base-devel + git) — skipping"
        exit 0
    fi
done

# Basic connectivity probe — git clone of the fork needs network.
if ! curl -fsSL --connect-timeout 5 --max-time 8 https://github.com >/dev/null 2>&1; then
    echo "  WARNING: no network — skipping (will retry on next smplos-migrate)"
    exit 0
fi

# ── Build in a scratch dir owned by the invoking user ────────────────────────
BUILD_DIR=$(mktemp -d /tmp/eww-smplos-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT

cp "$PKGBUILD_DIR/PKGBUILD" "$BUILD_DIR/"
cd "$BUILD_DIR"

# makepkg refuses to run as root. Migrations normally run as the invoking
# user, so a plain makepkg call is fine; guard against the rare case of a
# manual root run by falling back to a temp system user.
echo "  Building eww-smplos from source (this takes ~5-10 minutes)..."
if [[ $EUID -eq 0 ]]; then
    sudo useradd -m -r _ewwbuild 2>/dev/null || true
    sudo chown -R _ewwbuild:_ewwbuild "$BUILD_DIR"
    if ! sudo -u _ewwbuild bash -c "cd '$BUILD_DIR' && makepkg -s --noconfirm --skippgpcheck"; then
        echo "  ERROR: makepkg failed — leaving existing eww in place"
        sudo userdel -r _ewwbuild 2>/dev/null || true
        exit 0
    fi
    sudo userdel -r _ewwbuild 2>/dev/null || true
else
    if ! makepkg -s --noconfirm --skippgpcheck; then
        echo "  ERROR: makepkg failed — leaving existing eww in place"
        exit 0
    fi
fi

# ── Install the freshly built package ────────────────────────────────────────
PKG_FILE=$(ls "$BUILD_DIR"/eww-smplos-*.pkg.tar.* 2>/dev/null | head -1)
if [[ ! -f "$PKG_FILE" ]]; then
    echo "  ERROR: makepkg produced no package file — leaving existing eww in place"
    exit 0
fi

if ! sudo pacman -U --noconfirm "$PKG_FILE"; then
    echo "  ERROR: pacman -U failed — leaving existing eww in place"
    exit 0
fi

# ── Restart the bar so the user picks up the fixed binary immediately ────────
# Best-effort: bar-ctl is a smplOS script that manages the eww daemon lifecycle.
if command -v bar-ctl &>/dev/null; then
    bar-ctl stop  &>/dev/null || true
    bar-ctl start &>/dev/null || true
    echo "  Bar restarted with fixed eww binary"
fi

echo "  Installed eww-smplos $(pacman -Q eww-smplos 2>/dev/null | awk '{print $2}')"
exit 0
