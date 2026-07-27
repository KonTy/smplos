#!/usr/bin/env bash
set -euo pipefail
#
# fetch-st.sh — Fetch the latest pre-built st-wl binary from GitHub.
#
# Usage:
#   ./fetch-st.sh              # fetch the latest st-smpl release
#   ./fetch-st.sh --force      # re-fetch even if already current
#
# Outputs binary to: .cache/app-binaries/st-wl
# This is the same output path the ISO builder (builder/build.sh) reads.
#
# WHY THIS EXISTS
# ───────────────
# st-smpl is a fully independent repo with its own CI that builds and publishes
# a stripped, tested binary to GitHub Releases on every tag. Historically
# smplos also carried a subtree copy of the source at
# src/compositors/hyprland/st/ and build-apps.sh would compile that copy in a
# podman container. Two source trees inevitably drift: the smplos subtree was
# last touched 2026-03-23 and never received the 2026-06-29 scroll-down fix
# (st-smpl commit 9295a5e). Whenever anyone ran build-apps.sh, the resulting
# binary from that stale subtree got installed to /usr/local/bin/st-wl,
# silently overwriting the good binary that smplos-update-apps had just
# fetched from st-smpl's GitHub release — regressing the scroll fix.
#
# The subtree has been deleted (2026-07-26). This script replaces the container
# build with a straight download, exactly matching what smplos-update-apps
# does at runtime: single source of truth, no drift.
#
# Integration contract: smplos always uses whatever st-smpl just released.
# st-smpl owns the build. smplos owns the integration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

REPO="smpl-os/st-smpl"
BIN_OUTPUT="$PROJECT_ROOT/.cache/app-binaries"
MARKER="$BIN_OUTPUT/st-smpl.fetched-version"
OUT_BIN="$BIN_OUTPUT/st-wl"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[fetch-st]${NC} $*"; }
warn() { echo -e "${YELLOW}[fetch-st]${NC} $*"; }
die()  { echo -e "${RED}[fetch-st]${NC} $*" >&2; exit 1; }

FORCE=false
for arg in "$@"; do
    [[ "$arg" == "--force" ]] && FORCE=true
done

mkdir -p "$BIN_OUTPUT"

# ── Resolve latest release version ───────────────────────────────────────────
log "Checking latest st-smpl release..."
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    LATEST=$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null)
else
    LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep '"tag_name"' | head -1 | grep -oP 'v[\d.]+')
fi
[[ -n "$LATEST" ]] || die "Could not determine latest release from $REPO"

# ── Skip if already up to date ────────────────────────────────────────────────
if [[ "$FORCE" == "false" && -f "$MARKER" && "$(cat "$MARKER")" == "$LATEST" \
      && -f "$OUT_BIN" ]]; then
    log "Already at latest ($LATEST) — nothing to do"
    exit 0
fi

# ── Download ──────────────────────────────────────────────────────────────────
VERSION_BARE="${LATEST#v}"
ASSET="st-smpl-${VERSION_BARE}-x86_64"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST}/${ASSET}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "Downloading st-smpl $LATEST..."
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    gh release download "$LATEST" --repo "$REPO" \
        --pattern "$ASSET" --dir "$TMP" --clobber
else
    curl -fsSL --progress-bar -o "$TMP/$ASSET" "$DOWNLOAD_URL" \
        || die "Download failed: $DOWNLOAD_URL"
fi

# ── Install ───────────────────────────────────────────────────────────────────
[[ -f "$TMP/$ASSET" ]] || die "Downloaded asset not found at $TMP/$ASSET"
install -m 755 "$TMP/$ASSET" "$OUT_BIN"

# ── Fetch companion metadata from the release tag ────────────────────────────
# The release publishes a single binary asset; terminfo/desktop/manpage live in
# the source tree at the same tag. Grab them so the ISO builder has everything
# it needs to install a proper st-wl (terminfo -> tic, desktop -> applications,
# man page -> mandb) without falling back to a stale local copy.
log "Fetching companion files (terminfo, desktop, man page) at $LATEST..."
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${LATEST}"
for f in st-wl.info st-wl.desktop st-wl.1; do
    curl -fsSL "$RAW_BASE/$f" -o "$BIN_OUTPUT/$f" \
        || die "Failed to fetch $f from $RAW_BASE"
done

# ── Record installed version ──────────────────────────────────────────────────
echo "$LATEST" > "$MARKER"

log "st-wl $LATEST installed:  $(ls -lh "$OUT_BIN" | awk '{print $5}')  ($OUT_BIN)"
log "Companion files:  st-wl.info, st-wl.desktop, st-wl.1  (in $BIN_OUTPUT/)"
