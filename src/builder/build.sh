#!/bin/bash
#
# smplOS ISO Builder - Docker Container Build Script
# Based on omarchy-iso build process
# Supports: Official repos, AUR (via prebuilt), Flatpak, AppImages
#
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

BUILD_DIR="/build"
SRC_DIR="$BUILD_DIR/src"
RELEASE_DIR="$BUILD_DIR/release"
PREBUILT_DIR="$BUILD_DIR/prebuilt"
CACHE_DIR="/var/cache/smplos"
OFFLINE_MIRROR_DIR="$CACHE_DIR/mirror/offline"
WORK_DIR="$CACHE_DIR/work"
PROFILE_DIR="$CACHE_DIR/profile"

# From environment
COMPOSITOR="${COMPOSITOR:-hyprland}"
EDITION="${EDITION:-}"
VERBOSE="${VERBOSE:-}"
SKIP_AUR="${SKIP_AUR:-}"
SKIP_FLATPAK="${SKIP_FLATPAK:-}"
SKIP_APPIMAGE="${SKIP_APPIMAGE:-}"
RELEASE="${RELEASE:-}"
NO_CACHE="${NO_CACHE:-}"

# ISO metadata
ISO_NAME="smplos"
ISO_VERSION="$(date +%y%m%d-%H%M)"
ISO_LABEL="SMPLOS_$(date +%Y%m)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${BLUE}==>${NC} $*"; }
log_sub()   { echo -e "${CYAN}  ->${NC} $*"; }

# Package arrays
declare -a ALL_PACKAGES=()
declare -a AUR_PACKAGES=()
declare -a FLATPAK_PACKAGES=()
declare -a APPIMAGE_PACKAGES=()

###############################################################################
# System Setup (runs in Docker container)
###############################################################################

setup_build_env() {
    log_step "Setting up build environment"
    
    # Initialize pacman keyring
    pacman-key --init
    pacman --noconfirm -Sy archlinux-keyring
    
    # Install build dependencies (these go in the build container, not the ISO)
    pacman --noconfirm -Sy archiso git sudo base-devel jq grub
    
    # Create build user for any AUR packages we need to compile
    if ! id "builder" &>/dev/null; then
        useradd -m -G wheel builder
        echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    fi
    
    log_info "Build environment ready"
}

###############################################################################
# Package Collection
###############################################################################

collect_packages() {
    log_step "Collecting package lists"
    
    # Compositor packages
    local compositor_dir="$SRC_DIR/compositors/$COMPOSITOR"
    
    # Official packages
    if [[ -f "$compositor_dir/packages.txt" ]]; then
        log_sub "Adding official packages from $COMPOSITOR"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            ALL_PACKAGES+=("$line")
        done < "$compositor_dir/packages.txt"
    fi
    
    # AUR packages
    if [[ -f "$compositor_dir/packages-aur.txt" && -z "$SKIP_AUR" ]]; then
        log_sub "Adding AUR packages from $COMPOSITOR"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            AUR_PACKAGES+=("$line")
        done < "$compositor_dir/packages-aur.txt"
    fi
    
    # Flatpak packages  
    if [[ -f "$compositor_dir/packages-flatpak.txt" && -z "$SKIP_FLATPAK" ]]; then
        log_sub "Adding Flatpak packages from $COMPOSITOR"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            FLATPAK_PACKAGES+=("$line")
        done < "$compositor_dir/packages-flatpak.txt"
    fi
    
    # AppImage packages
    if [[ -f "$compositor_dir/packages-appimage.txt" && -z "$SKIP_APPIMAGE" ]]; then
        log_sub "Adding AppImages from $COMPOSITOR"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            APPIMAGE_PACKAGES+=("$line")
        done < "$compositor_dir/packages-appimage.txt"
    fi
    
    # Shared packages
    if [[ -f "$SRC_DIR/shared/packages.txt" ]]; then
        log_sub "Adding shared official packages"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            ALL_PACKAGES+=("$line")
        done < "$SRC_DIR/shared/packages.txt"
    fi

    # Shared AUR packages
    if [[ -f "$SRC_DIR/shared/packages-aur.txt" && -z "$SKIP_AUR" ]]; then
        log_sub "Adding shared AUR packages"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            AUR_PACKAGES+=("$line")
        done < "$SRC_DIR/shared/packages-aur.txt"
    fi

    # Shared Flatpak packages
    if [[ -f "$SRC_DIR/shared/packages-flatpak.txt" && -z "$SKIP_FLATPAK" ]]; then
        log_sub "Adding shared Flatpak packages"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            FLATPAK_PACKAGES+=("$line")
        done < "$SRC_DIR/shared/packages-flatpak.txt"
    fi

    # Shared AppImage packages
    if [[ -f "$SRC_DIR/shared/packages-appimage.txt" && -z "$SKIP_APPIMAGE" ]]; then
        log_sub "Adding shared AppImages"
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            APPIMAGE_PACKAGES+=("$line")
        done < "$SRC_DIR/shared/packages-appimage.txt"
    fi
    
    # Remove duplicates
    ALL_PACKAGES=($(printf '%s\n' "${ALL_PACKAGES[@]}" | sort -u))
    [[ ${#AUR_PACKAGES[@]} -gt 0 ]] && AUR_PACKAGES=($(printf '%s\n' "${AUR_PACKAGES[@]}" | sort -u))
    
    log_info "Package counts:"
    log_info "  Official: ${#ALL_PACKAGES[@]}"
    log_info "  AUR: ${#AUR_PACKAGES[@]}"
    log_info "  Flatpak: ${#FLATPAK_PACKAGES[@]}"
    log_info "  AppImage: ${#APPIMAGE_PACKAGES[@]}"
}

###############################################################################
# Profile Setup - copy releng as base, then add our configs
###############################################################################

setup_profile() {
    log_step "Setting up archiso profile"
    
    # Create directories
    mkdir -p "$CACHE_DIR"
    mkdir -p "$OFFLINE_MIRROR_DIR"
    mkdir -p "$WORK_DIR"
    mkdir -p "$PROFILE_DIR"
    
    # We base our ISO on the official arch ISO (releng) config
    cp -r /usr/share/archiso/configs/releng/* "$PROFILE_DIR/"
    
    # Remove reflector service (we'll use our offline mirror)
    rm -rf "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service" 2>/dev/null || true
    rm -rf "$PROFILE_DIR/airootfs/etc/systemd/system/reflector.service.d" 2>/dev/null || true
    rm -rf "$PROFILE_DIR/airootfs/etc/xdg/reflector" 2>/dev/null || true
    
    # Remove the default motd
    rm -f "$PROFILE_DIR/airootfs/etc/motd" 2>/dev/null || true
    
    log_info "Base releng profile copied"
}

###############################################################################
# Download All Packages to Offline Mirror
###############################################################################

download_packages() {
    log_step "Downloading packages to offline mirror"
    
    # If --no-cache was passed, wipe the offline mirror to force fresh downloads
    if [[ -n "$NO_CACHE" ]]; then
        log_warn "--no-cache: clearing offline mirror (full re-download)"
        rm -rf "$OFFLINE_MIRROR_DIR"/*
    fi
    
    # Get packages from the base releng packages.x86_64
    local releng_packages=()
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        releng_packages+=("$line")
    done < "$PROFILE_DIR/packages.x86_64"
    
    # Combine all packages: releng base + our additions
    local all_download_packages=("${releng_packages[@]}" "${ALL_PACKAGES[@]}")
    
    # Remove duplicates
    all_download_packages=($(printf '%s\n' "${all_download_packages[@]}" | sort -u))
    
    # Count existing cached packages
    local cached_count=0
    cached_count=$(find "$OFFLINE_MIRROR_DIR" -name '*.pkg.tar.*' ! -name '*.sig' 2>/dev/null | wc -l)
    log_info "Cached packages: $cached_count, requested: ${#all_download_packages[@]}"
    
    # pacman -Syw skips packages already present in --cachedir,
    # so only new/updated packages are actually downloaded
    mkdir -p /tmp/offlinedb
    pacman --noconfirm -Sy --dbpath /tmp/offlinedb
    pacman --noconfirm -Syw "${all_download_packages[@]}" \
        --cachedir "$OFFLINE_MIRROR_DIR/" \
        --dbpath /tmp/offlinedb
    
    local new_count
    new_count=$(find "$OFFLINE_MIRROR_DIR" -name '*.pkg.tar.*' ! -name '*.sig' 2>/dev/null | wc -l)
    log_info "Packages after sync: $new_count (downloaded $((new_count - cached_count)) new)"
    
    # Clean stale package versions: if foo-1.0 and foo-1.1 both exist, remove foo-1.0
    # paccache keeps only the latest version per package (-rk1), matching our cachedir
    if command -v paccache &>/dev/null; then
        log_info "Cleaning stale package versions..."
        paccache -rk1 -c "$OFFLINE_MIRROR_DIR" 2>/dev/null || true
    fi
}

###############################################################################
# Handle AUR Packages (use prebuilt or build)
###############################################################################

process_aur_packages() {
    log_step "Processing AUR packages"
    
    if [[ ${#AUR_PACKAGES[@]} -eq 0 ]]; then
        log_info "No AUR packages to process"
        return
    fi
    
    for pkg in "${AUR_PACKAGES[@]}"; do
        log_sub "Processing: $pkg"
        
        # Check for prebuilt package first
        local found=0
        if [[ -d "$PREBUILT_DIR" ]]; then
            shopt -s nullglob
            for prebuilt_file in "$PREBUILT_DIR"/${pkg}-[0-9]*.pkg.tar.{zst,xz}; do
                if [[ -f "$prebuilt_file" && ! "$prebuilt_file" == *"-debug-"* ]]; then
                    log_info "Using prebuilt: $(basename "$prebuilt_file")"
                    cp "$prebuilt_file" "$OFFLINE_MIRROR_DIR/"
                    found=1
                    break
                fi
            done
            shopt -u nullglob
        fi
        
        if [[ $found -eq 0 ]]; then
            log_warn "No prebuilt package found for $pkg"
            log_warn "Run the prebuilt script first to build AUR packages"
        fi
    done
    
    log_info "AUR packages processed"
}

###############################################################################
# Create Repository Database
###############################################################################

create_repo_database() {
    log_step "Creating offline repository database"
    
    cd "$OFFLINE_MIRROR_DIR"
    
    # Count packages
    local pkg_count=$(ls -1 *.pkg.tar.* 2>/dev/null | wc -l || echo 0)
    
    if [[ $pkg_count -eq 0 ]]; then
        log_error "No packages found in offline mirror!"
        exit 1
    fi
    
    # Create repo database
    log_info "Creating repository database with $pkg_count packages..."
    repo-add --new "$OFFLINE_MIRROR_DIR/offline.db.tar.gz" "$OFFLINE_MIRROR_DIR/"*.pkg.tar.zst 2>/dev/null || \
    repo-add --new "$OFFLINE_MIRROR_DIR/offline.db.tar.gz" "$OFFLINE_MIRROR_DIR/"*.pkg.tar.* || {
        log_error "Failed to create repo database"
        exit 1
    }
    
    log_info "Repository database created"
}

###############################################################################
# Create pacman.conf for the ISO
###############################################################################

setup_pacman_conf() {
    log_step "Setting up pacman configuration"
    
    # Create pacman.conf that uses our offline mirror
    cat > "$PROFILE_DIR/pacman.conf" << 'PACMANCONF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
ParallelDownloads = 5
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[offline]
SigLevel = Optional TrustAll
Server = file:///var/cache/smplos/mirror/offline/

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
PACMANCONF

    # Create a symlink so mkarchiso can access the offline mirror
    mkdir -p /var/cache/smplos/mirror
    if [[ ! -L /var/cache/smplos/mirror/offline && "$OFFLINE_MIRROR_DIR" != "/var/cache/smplos/mirror/offline" ]]; then
        ln -sf "$OFFLINE_MIRROR_DIR" /var/cache/smplos/mirror/offline
    fi
    
    # Also copy pacman.conf to the ISO's /etc for use after boot
    mkdir -p "$PROFILE_DIR/airootfs/etc"
    cp "$PROFILE_DIR/pacman.conf" "$PROFILE_DIR/airootfs/etc/pacman.conf"
    
    log_info "pacman.conf configured"
}

###############################################################################
# Update packages.x86_64
###############################################################################

update_package_list() {
    log_step "Updating package list"
    
    # Add our packages to the existing packages.x86_64
    printf '%s\n' "${ALL_PACKAGES[@]}" >> "$PROFILE_DIR/packages.x86_64"
    
    # Add AUR packages (they're in our offline repo now)
    if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
        printf '%s\n' "${AUR_PACKAGES[@]}" >> "$PROFILE_DIR/packages.x86_64"
    fi
    
    # Remove duplicates while preserving order
    local temp_file=$(mktemp)
    awk '!seen[$0]++' "$PROFILE_DIR/packages.x86_64" > "$temp_file"
    mv "$temp_file" "$PROFILE_DIR/packages.x86_64"
    
    log_info "Package list updated: $(wc -l < "$PROFILE_DIR/packages.x86_64") packages"
}

###############################################################################
# Update profiledef.sh
###############################################################################

update_profiledef() {
    log_step "Updating profile definition"
    
    cat > "$PROFILE_DIR/profiledef.sh" << PROFILEDEF
#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="$ISO_NAME"
iso_label="$ISO_LABEL"
iso_publisher="smplOS"
iso_application="smplOS Live/Installer"
iso_version="$ISO_VERSION"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.grub.esp' 'uefi-x64.grub.esp'
           'uefi-ia32.grub.eltorito' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
$(if [[ -n "$RELEASE" ]]; then
    echo "airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-Xdict-size' '1M' '-b' '1M')"
else
    echo "airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')"
fi)
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/"]="0:0:755"
  ["/var/cache/smplos/mirror/offline/"]="0:0:775"
)
PROFILEDEF
    chmod +x "$PROFILE_DIR/profiledef.sh"
    
    log_info "Profile definition updated"
}

###############################################################################
# Build st (suckless terminal) from source
###############################################################################

build_st() {
    log_step "Building st from source"

    local airootfs="$PROFILE_DIR/airootfs"
    local st_src="$SRC_DIR/compositors/$COMPOSITOR/st"

    if [[ ! -f "$st_src/Makefile" ]]; then
        log_info "No st source found for $COMPOSITOR, skipping"
        return 0
    fi

    # Install build dependencies on the build host
    local st_deps=()
    if [[ "$COMPOSITOR" == "hyprland" ]]; then
        st_deps=(wayland wayland-protocols libxkbcommon pixman fontconfig freetype2 harfbuzz imlib2 pkg-config)
    else
        st_deps=(libx11 libxft libxrender libxcursor fontconfig freetype2 harfbuzz imlib2 gd pkg-config)
    fi
    pacman --noconfirm --needed -S "${st_deps[@]}" 2>/dev/null || true

    # Build in a temp dir to avoid polluting the source tree
    local build_dir="/tmp/st-build"
    rm -rf "$build_dir"
    cp -r "$st_src" "$build_dir"
    cd "$build_dir"

    log_info "Compiling st ($COMPOSITOR)..."
    # Ensure config.h and patches.h exist (shipped in source tree) and are newer
    # than .def.h so Make doesn't overwrite them with defaults
    [[ -f "$build_dir/config.h" ]]  || cp "$build_dir/config.def.h" "$build_dir/config.h"
    [[ -f "$build_dir/patches.h" ]] || cp "$build_dir/patches.def.h" "$build_dir/patches.h"
    sleep 0.1
    touch "$build_dir/config.h" "$build_dir/patches.h"
    make -j"$(nproc)"

    # Install binary and terminfo into the ISO
    local bin_name
    if [[ "$COMPOSITOR" == "hyprland" ]]; then
        bin_name="st-wl"
    else
        bin_name="st"
    fi

    install -Dm755 "$bin_name" "$airootfs/usr/local/bin/$bin_name"
    # Only strip release builds; debug builds need symbols for crash analysis
    if ! grep -q 'STWL_DEBUG' "$build_dir/config.mk"; then
        strip "$airootfs/usr/local/bin/$bin_name"
    else
        log_info "Debug build detected, skipping strip"
    fi

    # Also stage for the installer to deploy to the installed system
    install -Dm755 "$bin_name" "$airootfs/root/smplos/bin/$bin_name"
    if ! grep -q 'STWL_DEBUG' "$build_dir/config.mk"; then
        strip "$airootfs/root/smplos/bin/$bin_name"
    fi

    # Install terminfo
    if [[ -f "$build_dir/${bin_name}.info" ]]; then
        tic -sx "$build_dir/${bin_name}.info" -o "$airootfs/usr/share/terminfo" 2>/dev/null || true
    elif [[ -f "$build_dir/st.info" ]]; then
        tic -sx "$build_dir/st.info" -o "$airootfs/usr/share/terminfo" 2>/dev/null || true
    fi

    # Install desktop file for xdg-terminal-exec
    if [[ -f "$st_src/${bin_name}.desktop" ]]; then
        install -Dm644 "$st_src/${bin_name}.desktop" "$airootfs/usr/share/applications/${bin_name}.desktop"
    fi

    cd "$SRC_DIR"
    rm -rf "$build_dir"

    log_info "st built and installed successfully"
}

###############################################################################
# Configure Airootfs
###############################################################################

setup_airootfs() {
    log_step "Configuring airootfs"
    
    local airootfs="$PROFILE_DIR/airootfs"
    local skel="$airootfs/etc/skel"
    
    # Create directories
    mkdir -p "$skel/.config"
    mkdir -p "$airootfs/usr/local/bin"

    # 1. Populate /etc/skel from src/shared/skel (dotfiles)
    if [[ -d "$SRC_DIR/shared/skel" ]]; then
       log_info "Populating /etc/skel from src/shared/skel..."
       cp -r "$SRC_DIR/shared/skel/"* "$skel/" 2>/dev/null || true
    fi

    # 2. Populate /etc/skel/.config from src/shared/configs
    if [[ -d "$SRC_DIR/shared/configs" ]]; then
        log_info "Populating /etc/skel/.config from src/shared/configs..."
        cp -r "$SRC_DIR/shared/configs/"* "$skel/.config/" 2>/dev/null || true
    fi

    mkdir -p "$airootfs/root/smplos/install/helpers"
    mkdir -p "$airootfs/root/smplos/config"
    mkdir -p "$airootfs/root/smplos/branding/plymouth"
    mkdir -p "$airootfs/opt/appimages"
    mkdir -p "$airootfs/opt/flatpaks"
    mkdir -p "$airootfs/var/cache/smplos/mirror"
    
    # Copy offline repository to airootfs
    log_info "Copying offline repository to airootfs..."
    cp -r "$OFFLINE_MIRROR_DIR" "$airootfs/var/cache/smplos/mirror/offline"
    
    # Copy shared bin scripts
    if [[ -d "$SRC_DIR/shared/bin" ]]; then
        log_info "Copying shared scripts"
        cp -r "$SRC_DIR/shared/bin/"* "$airootfs/usr/local/bin/" 2>/dev/null || true
        chmod +x "$airootfs/usr/local/bin/"* 2>/dev/null || true
        
        # Also stage scripts for the installer to deploy to the installed system
        mkdir -p "$airootfs/root/smplos/bin"
        cp -r "$SRC_DIR/shared/bin/"* "$airootfs/root/smplos/bin/" 2>/dev/null || true
        chmod +x "$airootfs/root/smplos/bin/"* 2>/dev/null || true
    fi
    
    # Deploy custom os-release (so fastfetch shows "smplOS" not "Arch Linux")
    if [[ -f "$SRC_DIR/shared/system/os-release" ]]; then
        log_info "Deploying custom os-release"
        mkdir -p "$airootfs/etc"
        cp "$SRC_DIR/shared/system/os-release" "$airootfs/etc/os-release"
        # Also stage for installer to deploy to installed system
        mkdir -p "$airootfs/root/smplos/system"
        cp "$SRC_DIR/shared/system/os-release" "$airootfs/root/smplos/system/os-release"
    fi
    
    # Copy EWW configs
    if [[ -d "$SRC_DIR/shared/eww" ]]; then
        log_info "Copying EWW configuration"
        mkdir -p "$skel/.config/eww"
        cp -r "$SRC_DIR/shared/eww/"* "$skel/.config/eww/" 2>/dev/null || true
        # Ensure EWW listener scripts are executable (archiso skel copy may strip +x)
        find "$skel/.config/eww/scripts" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
        # Also copy to smplos install path so install.sh deploys it to the installed system
        mkdir -p "$airootfs/root/smplos/config/eww"
        cp -r "$SRC_DIR/shared/eww/"* "$airootfs/root/smplos/config/eww/" 2>/dev/null || true
        find "$airootfs/root/smplos/config/eww/scripts" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
    fi

    # Deploy default wallpaper (catppuccin theme)
    if [[ -d "$SRC_DIR/shared/themes/catppuccin/backgrounds" ]]; then
        log_info "Deploying default wallpaper"
        local default_bg=$(find "$SRC_DIR/shared/themes/catppuccin/backgrounds" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' \) | sort | head -1)
        if [[ -n "$default_bg" ]]; then
            local ext="${default_bg##*.}"
            # To skel (for live ISO session)
            mkdir -p "$skel/Pictures/Wallpapers"
            cp "$default_bg" "$skel/Pictures/Wallpapers/default.$ext"
            # To smplos install path (for installed system via install.sh)
            mkdir -p "$airootfs/root/smplos/wallpapers"
            cp "$default_bg" "$airootfs/root/smplos/wallpapers/default.$ext"
        fi
    fi

    # Deploy theme system
    if [[ -d "$SRC_DIR/shared/themes" ]]; then
        log_info "Deploying theme system"
        
        # Stock themes — each is self-contained with pre-baked configs
        # Skip _templates (dev-only, not needed at runtime)
        local smplos_data="$airootfs/root/smplos"
        mkdir -p "$smplos_data/themes"
        for theme_dir in "$SRC_DIR/shared/themes"/*/; do
            [[ "$(basename "$theme_dir")" == _* ]] && continue
            cp -r "$theme_dir" "$smplos_data/themes/"
        done
        
        # Also to skel for live session
        local smplos_skel_data="$skel/.local/share/smplos"
        mkdir -p "$smplos_skel_data/themes"
        cp -r "$smplos_data/themes/"* "$smplos_skel_data/themes/"
        
        # Pre-set catppuccin as the active theme for live session
        # Each theme ships all its configs pre-baked, just copy the whole dir
        mkdir -p "$skel/.config/smplos/current/theme"
        echo "catppuccin" > "$skel/.config/smplos/current/theme.name"
        cp -r "$SRC_DIR/shared/themes/catppuccin/"* "$skel/.config/smplos/current/theme/"
        
        # Link pre-baked configs into app config dirs for live session
        local theme_src="$SRC_DIR/shared/themes/catppuccin"
        cp "$theme_src/eww-colors.scss" "$skel/.config/eww/theme-colors.scss" 2>/dev/null || true
        mkdir -p "$skel/.config/kitty" && cp "$theme_src/kitty.conf" "$skel/.config/kitty/theme.conf" 2>/dev/null || true
        mkdir -p "$skel/.config/hypr" && cp "$theme_src/hyprland.conf" "$skel/.config/hypr/theme.conf" 2>/dev/null || true
        cp "$theme_src/hyprlock.conf" "$skel/.config/hypr/hyprlock-theme.conf" 2>/dev/null || true
        mkdir -p "$skel/.config/foot" && cp "$theme_src/foot.ini" "$skel/.config/foot/theme.ini" 2>/dev/null || true
        # st -- no config file to copy, colors applied at runtime via OSC escape sequences
        mkdir -p "$skel/.config/btop/themes" && cp "$theme_src/btop.theme" "$skel/.config/btop/themes/current.theme" 2>/dev/null || true
        # Fish shell theme colors
        mkdir -p "$skel/.config/fish" && cp "$theme_src/fish.theme" "$skel/.config/fish/theme.fish" 2>/dev/null || true
        # Browser (Brave/Chromium) -- set toolbar color via managed policy
        local browser_bg
        browser_bg=$(grep '^background' "$theme_src/colors.toml" | sed 's/.*"\(#[0-9a-fA-F]*\)".*/\1/')
        if [[ -n "$browser_bg" ]]; then
            local policy="{\"BrowserThemeColor\": \"$browser_bg\"}"
            mkdir -p "$airootfs/etc/brave/policies/managed"
            echo "$policy" > "$airootfs/etc/brave/policies/managed/color.json"
            mkdir -p "$airootfs/etc/chromium/policies/managed"
            echo "$policy" > "$airootfs/etc/chromium/policies/managed/color.json"
        fi
        # Dunst: concatenate core settings + theme colors
        local dunst_core="$SRC_DIR/shared/configs/dunst/dunstrc"
        if [[ -f "$SRC_DIR/compositors/$COMPOSITOR/configs/dunst/dunstrc" ]]; then
            dunst_core="$SRC_DIR/compositors/$COMPOSITOR/configs/dunst/dunstrc"
        fi
        if [[ -f "$dunst_core" ]]; then
            mkdir -p "$skel/.config/dunst"
            cat "$dunst_core" "$theme_src/dunstrc.theme" > "$skel/.config/dunst/dunstrc.active"
        fi
    fi
    
    # Copy compositor configurations
    local compositor_dir="$SRC_DIR/compositors/$COMPOSITOR"
    if [[ -d "$compositor_dir" ]]; then
        if [[ -d "$compositor_dir/hypr" ]]; then
            log_info "Copying Hyprland configuration"
            mkdir -p "$skel/.config/hypr"
            cp -r "$compositor_dir/hypr/"* "$skel/.config/hypr/"
        fi
        
        if [[ -d "$compositor_dir/configs" ]]; then
            cp -r "$compositor_dir/configs/"* "$skel/.config/" 2>/dev/null || true
        fi
    fi

    # Copy shared bindings.conf into the compositor config dir
    # This file is the single source of truth for keybindings across compositors
    if [[ -f "$SRC_DIR/shared/configs/smplos/bindings.conf" ]]; then
        log_info "Copying shared bindings.conf"
        mkdir -p "$skel/.config/hypr" "$skel/.config/smplos"
        cp "$SRC_DIR/shared/configs/smplos/bindings.conf" "$skel/.config/hypr/bindings.conf"
        cp "$SRC_DIR/shared/configs/smplos/bindings.conf" "$skel/.config/smplos/bindings.conf"
    fi
    
    # Copy installer (gum-based configurator + helpers)
    if [[ -d "$SRC_DIR/shared/installer" ]]; then
        log_info "Copying smplOS installer stack"
        
        # Copy configurator
        cp "$SRC_DIR/shared/installer/configurator" "$airootfs/root/configurator"
        chmod +x "$airootfs/root/configurator"
        
        # Copy helpers
        cp -r "$SRC_DIR/shared/installer/helpers/"* "$airootfs/root/smplos/install/helpers/"
        
        # Copy post-install script
        cp "$SRC_DIR/shared/installer/install.sh" "$airootfs/root/smplos/install.sh"
        chmod +x "$airootfs/root/smplos/install.sh"
        
        # Copy automated script
        cp "$SRC_DIR/shared/installer/automated_script.sh" "$airootfs/root/.automated_script.sh"
        chmod +x "$airootfs/root/.automated_script.sh"
    fi

    # Copy package lists so the configurator can read them at install time
    # Merge shared + compositor packages into a single list (the configurator reads one file)
    local compositor_dir="$SRC_DIR/compositors/$COMPOSITOR"
    log_info "Merging shared + compositor package lists for installer"
    : > "$airootfs/root/smplos/packages.txt"  # start empty
    if [[ -f "$SRC_DIR/shared/packages.txt" ]]; then
        cat "$SRC_DIR/shared/packages.txt" >> "$airootfs/root/smplos/packages.txt"
    fi
    if [[ -f "$compositor_dir/packages.txt" ]]; then
        cat "$compositor_dir/packages.txt" >> "$airootfs/root/smplos/packages.txt"
    fi
    # Merge shared + compositor AUR package lists
    : > "$airootfs/root/smplos/packages-aur.txt"  # start empty
    if [[ -f "$SRC_DIR/shared/packages-aur.txt" ]]; then
        cat "$SRC_DIR/shared/packages-aur.txt" >> "$airootfs/root/smplos/packages-aur.txt"
    fi
    if [[ -f "$compositor_dir/packages-aur.txt" ]]; then
        cat "$compositor_dir/packages-aur.txt" >> "$airootfs/root/smplos/packages-aur.txt"
    fi
    # Copy edition extra packages if building an edition
    if [[ -n "${EDITION:-}" && -f "$SRC_DIR/editions/$EDITION/packages-extra.txt" ]]; then
        log_info "Copying edition ($EDITION) extra packages"
        cp "$SRC_DIR/editions/$EDITION/packages-extra.txt" "$airootfs/root/smplos/packages-extra.txt"
    fi
    
    # Copy Plymouth theme
    local branding_plymouth="$SRC_DIR/shared/configs/smplos/branding/plymouth"
    if [[ -d "$branding_plymouth" ]]; then
        log_info "Copying Plymouth theme"
        cp -r "$branding_plymouth/"* "$airootfs/root/smplos/branding/plymouth/"
        
        # Install smplOS Plymouth theme into the airootfs overlay
        # mkarchiso applies airootfs BEFORE installing packages, then runs
        # pacstrap which triggers our hook to set the theme properly.
        
        # 1. Pre-place the theme files (they'll survive pacstrap)
        mkdir -p "$airootfs/usr/share/plymouth/themes/smplos"
        cp -r "$branding_plymouth/"* "$airootfs/usr/share/plymouth/themes/smplos/"
        
        # 2. Store logo for watermark replacement
        mkdir -p "$airootfs/usr/share/smplos"
        cp "$branding_plymouth/logo.png" "$airootfs/usr/share/smplos/logo.png"
        
        # 3. Pacman hook: runs after plymouth install, BEFORE mkinitcpio (89 < 90)
        #    Sets our theme as default and replaces spinner watermark as fallback
        mkdir -p "$airootfs/etc/pacman.d/hooks"
        cat > "$airootfs/etc/pacman.d/hooks/89-smplos-plymouth.hook" << 'HOOKEOF'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = plymouth

[Action]
Description = Setting up smplOS Plymouth theme...
When = PostTransaction
Exec = /usr/local/bin/setup-plymouth
HOOKEOF
        
        # 4. Setup script called by the hook
        cat > "$airootfs/usr/local/bin/setup-plymouth" << 'SETUPEOF'
#!/bin/bash
# Install and activate smplOS Plymouth theme
THEME_SRC="/usr/share/plymouth/themes/smplos"
SPINNER_DIR="/usr/share/plymouth/themes/spinner"

# Set smplOS as default Plymouth theme
if [[ -f "$THEME_SRC/smplos.plymouth" ]]; then
    plymouth-set-default-theme smplos 2>/dev/null || true
fi

# Also replace spinner watermark as fallback
if [[ -f /usr/share/smplos/logo.png && -d "$SPINNER_DIR" ]]; then
    cp /usr/share/smplos/logo.png "$SPINNER_DIR/watermark.png"
fi
SETUPEOF
        chmod +x "$airootfs/usr/local/bin/setup-plymouth"
        log_info "Plymouth theme and pacman hook installed"
    fi
    
    # Font cache hook: rebuild fc-cache after font packages install
    # This eliminates the ~3s cold-start penalty on first terminal launch
    mkdir -p "$airootfs/etc/pacman.d/hooks"
    cat > "$airootfs/etc/pacman.d/hooks/90-fc-cache.hook" << 'FCHOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = ttf-*
Target = otf-*
Target = noto-fonts*

[Action]
Description = Rebuilding font cache...
When = PostTransaction
Exec = /usr/bin/fc-cache -f
FCHOOK
    log_info "Font cache pacman hook installed"
    
    # Copy configs for post-install
    if [[ -d "$SRC_DIR/shared/configs" ]]; then
        cp -r "$SRC_DIR/shared/configs/"* "$airootfs/root/smplos/config/" 2>/dev/null || true
    fi
    if [[ -d "$compositor_dir/hypr" ]]; then
        mkdir -p "$airootfs/root/smplos/config/hypr"
        cp -r "$compositor_dir/hypr/"* "$airootfs/root/smplos/config/hypr/" 2>/dev/null || true
    fi
    # Copy shared bindings.conf into post-install hypr config
    if [[ -f "$SRC_DIR/shared/configs/smplos/bindings.conf" ]]; then
        mkdir -p "$airootfs/root/smplos/config/hypr" "$airootfs/root/smplos/config/smplos"
        cp "$SRC_DIR/shared/configs/smplos/bindings.conf" "$airootfs/root/smplos/config/hypr/bindings.conf"
        cp "$SRC_DIR/shared/configs/smplos/bindings.conf" "$airootfs/root/smplos/config/smplos/bindings.conf"
    fi
    # Copy shared configs (dunst, etc.) into post-install store
    if [[ -d "$SRC_DIR/shared/configs/dunst" ]]; then
        mkdir -p "$airootfs/root/smplos/config/dunst"
        cp -r "$SRC_DIR/shared/configs/dunst/"* "$airootfs/root/smplos/config/dunst/" 2>/dev/null || true
    fi
    # Copy other compositor configs (share-picker, etc.)
    if [[ -d "$compositor_dir/configs" ]]; then
        cp -r "$compositor_dir/configs/"* "$airootfs/root/smplos/config/" 2>/dev/null || true
    fi
    
    # Setup systemd services
    setup_services "$airootfs"
    
    # Setup helper scripts
    setup_helper_scripts "$airootfs"
    
    log_info "Airootfs configured"
}

setup_services() {
    local airootfs="$1"
    
    log_info "Setting up systemd services"
    
    mkdir -p "$airootfs/etc/systemd/system/multi-user.target.wants"
    mkdir -p "$airootfs/etc/systemd/system/getty@tty1.service.d"
    
    # Enable NetworkManager
    ln -sf /usr/lib/systemd/system/NetworkManager.service \
        "$airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service" 2>/dev/null || true
    
    # Auto-login on tty1
    cat > "$airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux
AUTOLOGIN

    echo "smplos" > "$airootfs/etc/hostname"
    echo "LANG=en_US.UTF-8" > "$airootfs/etc/locale.conf"
    echo "en_US.UTF-8 UTF-8" >> "$airootfs/etc/locale.gen"
}

setup_helper_scripts() {
    local airootfs="$1"
    
    cat > "$airootfs/usr/local/bin/smplos-flatpak-setup" << 'FLATPAKSETUP'
#!/bin/bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

for bundle in /opt/flatpaks/*.flatpak; do
    [[ -f "$bundle" ]] || continue
    echo "Installing: $(basename "$bundle")"
    flatpak install --noninteractive --user "$bundle" 2>/dev/null || true
done
FLATPAKSETUP
    chmod +x "$airootfs/usr/local/bin/smplos-flatpak-setup"
    
    cat > "$airootfs/usr/local/bin/smplos-appimage-setup" << 'APPIMAGESETUP'
#!/bin/bash
mkdir -p "$HOME/.local/share/applications"

for appimage in /opt/appimages/*.AppImage; do
    [[ -f "$appimage" ]] || continue
    name=$(basename "$appimage" .AppImage)
    cat > "$HOME/.local/share/applications/$name.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$appimage
Icon=application-x-executable
Terminal=false
Categories=Utility;
EOF
done
APPIMAGESETUP
    chmod +x "$airootfs/usr/local/bin/smplos-appimage-setup"
}

###############################################################################
# Setup Boot Configuration
###############################################################################

setup_boot() {
    log_step "Configuring boot"
    
    mkdir -p "$PROFILE_DIR/grub"
    cat > "$PROFILE_DIR/grub/grub.cfg" << 'GRUBCFG'
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod all_video
insmod font

set default="0"
set timeout=5
set gfxmode=auto
set gfxpayload=keep

# Function to load initrd with optional microcode
# Microcode may be bundled in initramfs or separate files
menuentry "smplOS (Hyprland)" --class arch --class gnu-linux --class gnu --class os {
    linux /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash
    initrd /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
}

menuentry "smplOS (Safe Mode)" --class arch --class gnu-linux --class gnu --class os {
    linux /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% nomodeset
    initrd /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
}
GRUBCFG

    mkdir -p "$PROFILE_DIR/syslinux"
    cat > "$PROFILE_DIR/syslinux/syslinux.cfg" << 'SYSLINUXCFG'
DEFAULT select

LABEL select
COM32 whichsys.c32
APPEND -pxe- pxe -sys- sys -iso- sys

LABEL pxe
CONFIG archiso_pxe.cfg

LABEL sys
CONFIG archiso_sys.cfg
SYSLINUXCFG

    cat > "$PROFILE_DIR/syslinux/archiso_sys.cfg" << 'ARCHISOSYS'
DEFAULT arch
PROMPT 0
TIMEOUT 50

UI vesamenu.c32
MENU TITLE smplOS Boot Menu

LABEL arch
    MENU LABEL smplOS (Hyprland)
    LINUX /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
    APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash

LABEL arch_safe
    MENU LABEL smplOS (Safe Mode)
    LINUX /%INSTALL_DIR%/boot/x86_64/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img
    APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% nomodeset
ARCHISOSYS
    
    log_info "Boot configuration updated"
}

###############################################################################
# Build ISO
###############################################################################

build_iso() {
    log_step "Building ISO image"
    
    mkdir -p "$RELEASE_DIR"
    
    mkarchiso -v -w "$WORK_DIR" -o "$RELEASE_DIR" "$PROFILE_DIR"
    
    local iso_file
    iso_file=$(find "$RELEASE_DIR" -maxdepth 1 -name "*.iso" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -n "$iso_file" && -f "$iso_file" ]]; then
        local new_name="${ISO_NAME}-${COMPOSITOR}"
        [[ -n "$EDITION" ]] && new_name="${new_name}-${EDITION}"
        new_name="${new_name}-${ISO_VERSION}.iso"
        
        mv "$iso_file" "$RELEASE_DIR/$new_name"
        
        log_info ""
        log_info "ISO built successfully!"
        log_info "File: $new_name"
        log_info "Size: $(du -h "$RELEASE_DIR/$new_name" | cut -f1)"
    else
        log_error "ISO file not found!"
        exit 1
    fi
    
    if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
        chown -R "$HOST_UID:$HOST_GID" "$RELEASE_DIR/"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    log_info "smplOS ISO Builder"
    log_info "=================="
    log_info "Compositor: $COMPOSITOR"
    [[ -n "$EDITION" ]] && log_info "Edition: $EDITION"
    [[ -n "$RELEASE" ]] && log_info "Release mode: max xz compression"
    [[ -n "$SKIP_AUR" ]] && log_info "AUR: disabled"
    [[ -n "$SKIP_FLATPAK" ]] && log_info "Flatpak: disabled"
    [[ -n "$SKIP_APPIMAGE" ]] && log_info "AppImage: disabled"
    log_info ""
    
    setup_build_env
    collect_packages
    setup_profile
    download_packages
    process_aur_packages
    create_repo_database
    setup_pacman_conf
    update_package_list
    update_profiledef
    setup_airootfs
    build_st
    setup_boot
    build_iso
    
    log_info ""
    log_info "Build completed successfully!"
}

main "$@"
