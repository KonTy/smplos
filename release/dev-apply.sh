#!/usr/bin/env bash
set -euo pipefail
#
# dev-apply.sh -- Apply all pushed files inside the running VM
#
# Usage:  sudo bash /mnt/dev-apply.sh          (everything except st)
#         sudo bash /mnt/dev-apply.sh st        (also install st-wl binary)
#

SHARE="/mnt"
USER_HOME="$HOME"

# If running as root, find the real user
if [[ "$EUID" -eq 0 ]]; then
    REAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-}")
    if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
        USER_HOME="/home/$REAL_USER"
        USER_ID=$(id -u "$REAL_USER")
    fi
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[apply]${NC} $*"; }
warn() { echo -e "${YELLOW}[apply]${NC} $*"; }

# Run a command as the real user with Wayland/Hyprland env
# Uses runuser instead of su to avoid PAM login sessions that break sudo
run_as_user() {
    local cmd="$1"
    if [[ "$EUID" -eq 0 && -n "${REAL_USER:-}" ]]; then
        local xdg_dir="/run/user/$USER_ID"
        local env_vars="XDG_RUNTIME_DIR=$xdg_dir"

        # Detect WAYLAND_DISPLAY
        for sock in "$xdg_dir"/wayland-*; do
            [[ -S "$sock" ]] || continue
            env_vars+=" WAYLAND_DISPLAY=$(basename "$sock")"
            break
        done

        # Detect HYPRLAND_INSTANCE_SIGNATURE
        local hypr_sig=""
        [[ -d /tmp/hypr ]] && hypr_sig=$(ls -1 /tmp/hypr/ 2>/dev/null | head -n1)
        [[ -z "$hypr_sig" && -d "$xdg_dir/hypr" ]] && hypr_sig=$(ls -1 "$xdg_dir/hypr/" 2>/dev/null | head -n1)
        if [[ -z "$hypr_sig" ]]; then
            local child_pid=$(pgrep -u "$REAL_USER" -f 'eww|hyprctl' 2>/dev/null | head -n1)
            [[ -n "$child_pid" ]] && hypr_sig=$(tr '\0' '\n' < /proc/"$child_pid"/environ 2>/dev/null | grep ^HYPRLAND_INSTANCE_SIGNATURE= | cut -d= -f2)
        fi
        [[ -n "$hypr_sig" ]] && env_vars+=" HYPRLAND_INSTANCE_SIGNATURE=$hypr_sig"

        runuser -u "$REAL_USER" -- env $env_vars bash -c "$cmd"
    else
        bash -c "$cmd"
    fi
}

# Check mount
if [[ ! -f "$SHARE/dev-apply.sh" ]]; then
    echo "Shared folder not mounted. Run:"
    echo "  sudo mount -t 9p -o trans=virtio hostshare /mnt"
    exit 1
fi

restart_eww=false
restart_hypr=false

own() { chown -R "$(stat -c '%U:%G' "$USER_HOME")" "$1" 2>/dev/null || true; }

# ── EWW configs ─────────────────────────────────────────────
if [[ -d "$SHARE/eww" && "$(ls -A "$SHARE/eww" 2>/dev/null)" ]]; then
    log "Applying EWW configs..."
    rm -rf "$USER_HOME/.config/eww"
    mkdir -p "$USER_HOME/.config/eww"
    cp -r "$SHARE/eww/"* "$USER_HOME/.config/eww/"
    find "$USER_HOME/.config/eww/scripts" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
    own "$USER_HOME/.config/eww/"
    restart_eww=true
    log "  done"
fi

# ── Shared icons (SVG templates for EWW bar) ───────────────
if [[ -d "$SHARE/icons" && "$(ls -A "$SHARE/icons" 2>/dev/null)" ]]; then
    log "Applying icon templates..."
    ICONS_DEST="$USER_HOME/.local/share/smplos/icons"
    mkdir -p "$ICONS_DEST"
    cp -r "$SHARE/icons/"* "$ICONS_DEST/"
    own "$ICONS_DEST"
    log "  done (theme-set will bake colors into these)"
fi

# ── Bin scripts ─────────────────────────────────────────────
if [[ -d "$SHARE/bin" && "$(ls -A "$SHARE/bin" 2>/dev/null)" ]]; then
    log "Applying bin scripts..."
    for existing in /usr/local/bin/*; do
        [[ -f "$existing" ]] || continue
        name=$(basename "$existing")
        [[ -f "$SHARE/bin/$name" ]] || {
            head -5 "$existing" 2>/dev/null | grep -qi 'smplos\|smplOS' && rm -f "$existing" && log "  Removed stale: $name"
        }
    done
    cp -r "$SHARE/bin/"* /usr/local/bin/
    for f in "$SHARE/bin/"*; do
        chmod +x "/usr/local/bin/$(basename "$f")" 2>/dev/null || true
    done
    log "  $(ls "$SHARE/bin" | wc -l) scripts installed"
fi

# ── Shared configs ──────────────────────────────────────────
if [[ -d "$SHARE/configs" && "$(ls -A "$SHARE/configs" 2>/dev/null)" ]]; then
    log "Applying shared configs..."
    for f in "$SHARE/configs/"*; do
        [[ -f "$f" ]] && cp "$f" "$USER_HOME/.config/"
    done
    for d in "$SHARE/configs/"*/; do
        [[ -d "$d" ]] || continue
        name=$(basename "$d")
        mkdir -p "$USER_HOME/.config/$name"
        cp -r "$d"* "$USER_HOME/.config/$name/" 2>/dev/null || true
    done
    own "$USER_HOME/.config/"
    log "  done"
fi

# ── Systemd user units ──────────────────────────────────────
if [[ -d "$USER_HOME/.config/systemd/user" ]]; then
    log "Enabling systemd user units..."
    USER_WANTS="$USER_HOME/.config/systemd/user/default.target.wants"
    mkdir -p "$USER_WANTS"
    for unit in smplos-app-cache.service smplos-app-cache.path; do
        if [[ -f "$USER_HOME/.config/systemd/user/$unit" ]]; then
            ln -sf "../$unit" "$USER_WANTS/$unit"
            log "  enabled $unit"
        fi
    done
    own "$USER_HOME/.config/systemd"
    # Reload systemd user daemon so it picks up new units
    run_as_user "systemctl --user daemon-reload" 2>/dev/null || true
    run_as_user "systemctl --user restart smplos-app-cache.path" 2>/dev/null || true
fi

# ── App cache (populate for launcher) ───────────────────────
if command -v rebuild-app-cache &>/dev/null; then
    log "Building app cache..."
    run_as_user "rebuild-app-cache" 2>/dev/null && log "  done" || warn "  failed"
fi

# ── notif-center ─────────────────────────────────────────────
if [[ -f "$SHARE/notif-center/notif-center" ]]; then
    log "Applying notif-center binary..."
    # If a directory exists (from previous bug), remove it
    if [[ -d "/usr/local/bin/notif-center" ]]; then
        rm -rf "/usr/local/bin/notif-center"
    fi
    cp "$SHARE/notif-center/notif-center" "/usr/local/bin/"
    chmod +x "/usr/local/bin/notif-center"
    own "/usr/local/bin/notif-center"
    log "  done"
fi

# ── Hyprland configs ────────────────────────────────────────
if [[ -d "$SHARE/hypr" && "$(ls -A "$SHARE/hypr" 2>/dev/null)" ]]; then
    log "Applying Hyprland configs..."
    mkdir -p "$USER_HOME/.config/hypr"
    cp -r "$SHARE/hypr/"* "$USER_HOME/.config/hypr/"
    own "$USER_HOME/.config/hypr/"
    if [[ -f "$SHARE/hypr/bindings.conf" ]]; then
        mkdir -p "$USER_HOME/.config/smplos"
        cp "$SHARE/hypr/bindings.conf" "$USER_HOME/.config/smplos/bindings.conf"
        own "$USER_HOME/.config/smplos/"
    fi
    restart_hypr=true
    log "  done"
fi

# ── Themes ──────────────────────────────────────────────────
if [[ -d "$SHARE/themes" && "$(ls -A "$SHARE/themes" 2>/dev/null)" ]]; then
    THEMES_DEST="$USER_HOME/.local/share/smplos/themes"
    log "Applying themes..."
    mkdir -p "$THEMES_DEST"
    cp -r "$SHARE/themes/"* "$THEMES_DEST/"
    own "$THEMES_DEST"
    log "  done"
fi

# ── st-wl terminal (only when 'st' arg passed -- replacing st while running from it kills the shell) ──
if [[ -f "$SHARE/st/st-wl" ]] && [[ " ${*:-} " == *" st "* ]]; then
    log "Installing st-wl binary..."
    cp "$SHARE/st/st-wl" /usr/local/bin/st-wl
    chmod +x /usr/local/bin/st-wl
    log "  done"
elif [[ -f "$SHARE/st/st-wl" ]]; then
    log "Skipping st-wl (pass 'st' arg to install, e.g.: sudo bash /mnt/dev-apply.sh st)"
fi

# ── Logseq theme plugins ────────────────────────────────────
if [[ -d "$SHARE/.logseq/plugins" ]]; then
    log "Applying Logseq theme plugins..."
    mkdir -p "$USER_HOME/.logseq/plugins" "$USER_HOME/.logseq/settings"
    cp -r "$SHARE/.logseq/plugins/"* "$USER_HOME/.logseq/plugins/"
    [[ -d "$SHARE/.logseq/settings" ]] && cp -r "$SHARE/.logseq/settings/"* "$USER_HOME/.logseq/settings/"
    own "$USER_HOME/.logseq"
    log "  $(ls "$SHARE/.logseq/plugins" | wc -l) plugins installed"
fi

# ── Restart xdg-desktop-portal (picks up portals.conf changes) ──
if [[ -f "$USER_HOME/.config/xdg-desktop-portal/portals.conf" ]]; then
    log "Restarting xdg-desktop-portal..."
    run_as_user "systemctl --user restart xdg-desktop-portal" 2>/dev/null || warn "  portal restart failed"
    log "  done"
fi

# ── Ensure essential services ───────────────────────────────
systemctl is-active --quiet NetworkManager 2>/dev/null || {
    log "Starting NetworkManager..."
    systemctl start NetworkManager 2>/dev/null && log "  NetworkManager started" || warn "  Failed to start NetworkManager"
}

# ── Restart services ────────────────────────────────────────

# Re-apply current theme (copies theme-colors.scss, bakes SVG icons, etc.)
current_theme=$(cat "$USER_HOME/.config/smplos/current/theme.name" 2>/dev/null || true)
if [[ -n "${current_theme:-}" ]] && ($restart_eww || $restart_hypr); then
    log "Killing EWW before theme re-apply..."
    run_as_user "eww --config ~/.config/eww kill 2>/dev/null; killall -9 eww 2>/dev/null" || true
    sleep 0.5
    log "Re-applying theme '$current_theme'..."
    run_as_user "theme-set '$current_theme'" 2>/dev/null || warn "  theme-set failed"
    # theme-set skips bar restart since we killed eww above — start it now
    sleep 0.3
    log "Starting EWW bar..."
    run_as_user "bar-ctl start"

    # Browser policies need root -- theme-set skips them when non-root,
    # so we handle them here directly (we're already root)
    THEME_DIR="$USER_HOME/.local/share/smplos/themes/$current_theme"
    BROWSER_BG=$(grep '^background' "$THEME_DIR/colors.toml" 2>/dev/null | head -1 | sed 's/.*"\(#[^"]*\)".*/\1/')
    if [[ -n "${BROWSER_BG:-}" ]]; then
        BROWSER_POLICY="{\"BrowserThemeColor\": \"$BROWSER_BG\", \"BackgroundModeEnabled\": false}"
        for browser in chromium brave; do
            command -v "$browser" &>/dev/null || continue
            mkdir -p "/etc/$browser/policies/managed" 2>/dev/null
            echo "$BROWSER_POLICY" > "/etc/$browser/policies/managed/color.json" 2>/dev/null
        done
    fi
fi

if $restart_hypr; then
    log "Reloading Hyprland..."
    run_as_user "pkill rofi" 2>/dev/null || true
    run_as_user "hyprctl reload" 2>/dev/null || warn "  hyprctl reload failed"
    log "  Hyprland reloaded"
fi

log ""
log "All done!"
