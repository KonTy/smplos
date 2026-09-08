#!/bin/bash
# Migration: Remove obsolete qemu-block-gluster update blocker.
#
# Context: Arch qemu-common 11.1 conflicts with the removed qemu-block-gluster
#          split package. Noninteractive pacman defaults to "no" for the
#          conflict prompt, so `pacman -Syu --noconfirm` aborts before normal
#          repo packages such as yt-dlp can update.
# Safety:  Removes only the obsolete qemu-block-gluster split and, when needed,
#          the old qemu-full meta-package that required it. Concrete QEMU
#          packages such as qemu-desktop/qemu-base remain installed, and the
#          current qemu-full meta-package is restored after cleanup.

set -uo pipefail

if ! pacman -Qq qemu-block-gluster >/dev/null 2>&1; then
    echo "  qemu-block-gluster not installed - nothing to do"
    exit 0
fi

if ! curl -fsSL --connect-timeout 5 --max-time 8 https://archlinux.org >/dev/null 2>&1; then
    echo "  WARNING: no network - will retry on next update"
    exit 1
fi

if ! sudo pacman -Sy --noconfirm >/dev/null 2>&1; then
    echo "  ERROR: could not refresh package database - will retry on next update"
    exit 1
fi

if ! pacman -Si qemu-common 2>/dev/null | grep -qE '^Conflicts With.*qemu-block-gluster'; then
    echo "  Current qemu-common does not conflict with qemu-block-gluster"
    exit 0
fi

had_qemu_full=0
if pacman -Qq qemu-full >/dev/null 2>&1; then
    had_qemu_full=1
    echo "  Removing old qemu-full meta-package and obsolete qemu-block-gluster"
    if ! sudo pacman -R --noconfirm qemu-full qemu-block-gluster; then
        echo "  ERROR: could not remove qemu-full/qemu-block-gluster - will retry"
        exit 1
    fi
else
    echo "  Removing obsolete qemu-block-gluster"
    if ! sudo pacman -R --noconfirm qemu-block-gluster; then
        echo "  ERROR: could not remove qemu-block-gluster - will retry"
        exit 1
    fi
fi

if [[ $had_qemu_full -eq 1 ]]; then
    if sudo pacman -S --needed --noconfirm qemu-full; then
        echo "  Restored qemu-full meta-package without qemu-block-gluster"
    else
        echo "  WARNING: qemu-full restore failed; concrete QEMU packages remain installed"
    fi
fi

echo "  QEMU package conflict cleaned up; pacman -Syu can continue"
exit 0
