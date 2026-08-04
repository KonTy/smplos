#!/bin/bash
# Migration: Remove `IgnorePkg = hyprland eww` from /etc/pacman.conf
#
# Context: smplOS ISO installer (src/shared/installer/install.sh) historically
#          baked `IgnorePkg = hyprland eww` into every customer's pacman.conf
#          as a belt-and-suspenders freeze for the compositor + bar.
#
#          That worked in the old model where the whole hypr* stack was pinned
#          manually. In the current model, smplos-update passes an --ignore
#          list computed at runtime from critical-packages.txt (source-controlled,
#          slimmed to just hyprland + xdg-desktop-portal-hyprland). The
#          pacman.conf IgnorePkg entry is now REDUNDANT with that flag AND
#          silently sabotages fleet upgrades:
#
#          - Any `pacman -S hyprland=X.Y.Z` command (from a migration, or from
#            the critical bundle apply) prompts "hyprland is in IgnorePkg.
#            Install anyway? [Y/n]". `--noconfirm` picks the default (Y here,
#            good), but the extra prompt is noise and depends on pacman's
#            default choice never changing.
#          - Any `pacman -Syu` (even without --ignore) skips hyprland/eww,
#            which is fine for the general update but creates ABI-lockstep
#            drift: aquamarine/hyprutils get bumped, hyprland stays behind,
#            and eventually every future -Syu fails with unresolvable deps.
#
#          Deleting the pacman.conf entry hands ignore-list authority back to
#          smplos-update (source of truth = critical-packages.txt).
#
# Safety: idempotent (no-op if the line is already gone), keeps a .smplos-bak
#         backup, only touches an exact-match line so we never trash a
#         manually-customized pacman.conf.

set -uo pipefail

_conf=/etc/pacman.conf

if [[ ! -f "$_conf" ]]; then
    echo "  $_conf not found — skipping"
    exit 0
fi

# Check if any IgnorePkg line contains hyprland or eww.
if ! grep -qE '^[[:space:]]*IgnorePkg[[:space:]]*=.*\b(hyprland|eww)\b' "$_conf"; then
    echo "  $_conf: no IgnorePkg entry for hyprland/eww — nothing to do"
    exit 0
fi

echo "  $_conf: found IgnorePkg for hyprland/eww — cleaning up"
# Show what we're touching.
grep -nE '^[[:space:]]*IgnorePkg[[:space:]]*=' "$_conf" | sed 's/^/    before: /'

# Keep a backup so a rollback is one `mv` away.
if ! sudo cp -a "$_conf" "$_conf.smplos-bak-$(date +%Y%m%d-%H%M%S)"; then
    echo "  ERROR: could not back up $_conf — will retry on next update"
    exit 1
fi

# Rewrite the IgnorePkg line: strip hyprland and eww, keep everything else.
# If nothing remains, comment the whole line out.
_tmp=$(mktemp)
awk '
    BEGIN { changed = 0 }
    /^[[:space:]]*IgnorePkg[[:space:]]*=/ {
        # Split "IgnorePkg = a b c" into key and list.
        key = $1; sub(/^[^=]*=[[:space:]]*/, "", $0)
        n = split($0, arr, /[[:space:]]+/)
        out = ""
        for (i = 1; i <= n; i++) {
            if (arr[i] != "hyprland" && arr[i] != "eww" && arr[i] != "") {
                out = (out == "" ? arr[i] : out " " arr[i])
            }
        }
        if (out == "") {
            print "# IgnorePkg =   # smplOS: managed via smplos-update --ignore from critical-packages.txt"
        } else {
            print "IgnorePkg   = " out "   # smplOS: managed via smplos-update --ignore from critical-packages.txt"
        }
        changed = 1
        next
    }
    { print }
    END { exit changed ? 0 : 1 }
' "$_conf" > "$_tmp"

if [[ ! -s "$_tmp" ]]; then
    echo "  ERROR: rewrite produced empty file — aborting"
    rm -f "$_tmp"
    exit 1
fi

# Sanity: pacman.conf must still parse — quick heuristic, must contain [options].
if ! grep -q '^\[options\]' "$_tmp"; then
    echo "  ERROR: rewritten pacman.conf is missing [options] — aborting"
    rm -f "$_tmp"
    exit 1
fi

if ! sudo install -m 0644 -o root -g root "$_tmp" "$_conf"; then
    echo "  ERROR: could not install rewritten $_conf — will retry on next update"
    rm -f "$_tmp"
    exit 1
fi
rm -f "$_tmp"

echo "  Cleaned. Showing new IgnorePkg line:"
grep -nE '^([[:space:]]*IgnorePkg|#.*IgnorePkg)' "$_conf" | sed 's/^/    after:  /'

exit 0
