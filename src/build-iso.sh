#!/bin/bash
#
# smplOS ISO Builder - Docker Wrapper
# Builds the ISO in a clean Arch Linux container for reproducibility
#
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }

###############################################################################
# Help
###############################################################################

show_help() {
    cat << 'HELPEOF'
smplOS ISO Builder

Usage: build-iso.sh [OPTIONS]

Options:
    -c, --compositor NAME   Compositor to build (hyprland, dwm) [default: hyprland]
    -e, --edition NAME      Edition variant (lite, creators) [optional]
    -r, --release           Release build: max xz compression (slow, ~2h, smallest ISO)
    -n, --no-cache          Don't use package cache
    -v, --verbose           Verbose output
    --skip-aur              Skip building AUR packages
    --skip-flatpak          Skip including Flatpak packages
    --skip-appimage         Skip including AppImages
    -h, --help              Show this help message

Package Sources:
    Official:  packages.txt         - Standard Arch repos
    AUR:       packages-aur.txt     - Arch User Repository
    Flatpak:   packages-flatpak.txt - Flathub applications
    AppImage:  packages-appimage.txt - AppImage bundles (format: name|url)

Examples:
    ./build-iso.sh                        # Build with all package sources
    ./build-iso.sh --skip-aur             # Skip AUR (faster build)
    ./build-iso.sh -c hyprland -e lite    # Build Hyprland Lite edition
    ./build-iso.sh --release              # Max compression for GitHub release
HELPEOF
}

###############################################################################
# Arguments
###############################################################################

COMPOSITOR="hyprland"
EDITION=""
RELEASE=""
NO_CACHE=""
VERBOSE=""
SKIP_AUR=""
SKIP_FLATPAK=""
SKIP_APPIMAGE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--compositor)
                COMPOSITOR="$2"
                shift 2
                ;;
            -e|--edition)
                EDITION="$2"
                shift 2
                ;;
            -r|--release)
                RELEASE="1"
                shift
                ;;
            -n|--no-cache)
                NO_CACHE="1"
                shift
                ;;
            -v|--verbose)
                VERBOSE="1"
                shift
                ;;
            --skip-aur)
                SKIP_AUR="1"
                shift
                ;;
            --skip-flatpak)
                SKIP_FLATPAK="1"
                shift
                ;;
            --skip-appimage)
                SKIP_APPIMAGE="1"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

###############################################################################
# Build Missing AUR Packages
###############################################################################

build_missing_aur_packages() {
    local prebuilt_dir="$SCRIPT_DIR/iso/prebuilt"
    mkdir -p "$prebuilt_dir"
    
    # Read AUR packages from shared + compositor package lists (single source of truth)
    local aur_packages=()
    for aur_file in "$SCRIPT_DIR/shared/packages-aur.txt" "$SCRIPT_DIR/compositors/${COMPOSITOR:-hyprland}/packages-aur.txt"; do
        [[ -f "$aur_file" ]] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            aur_packages+=("$line")
        done < "$aur_file"
    done
    
    local need_build=()
    
    for pkg in "${aur_packages[@]}"; do
        # Check if package already exists
        if ! ls "$prebuilt_dir"/${pkg}-[0-9]*.pkg.tar.* &>/dev/null; then
            need_build+=("$pkg")
        else
            log_info "Found prebuilt: $pkg"
        fi
    done
    
    if [[ ${#need_build[@]} -eq 0 ]]; then
        log_info "All AUR packages are already built"
        return 0
    fi
    
    log_step "Building missing AUR packages: ${need_build[*]}"
    log_info "This may take a while on first run..."
    
    # Build missing packages in Docker container
    docker run --rm \
        -v "$prebuilt_dir:/output" \
        archlinux:latest bash -c "
            set -e
            
            # Setup build environment
            pacman -Syu --noconfirm
            pacman -S --noconfirm --needed base-devel git rustup
            
            # Setup rust
            rustup default stable
            
            # Create build user (makepkg doesn't run as root)
            useradd -m builder
            echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
            
            cd /home/builder
            
            for pkg in ${need_build[*]}; do
                echo '==> Building \$pkg...'
                
                # Clone from AUR
                sudo -u builder git clone https://aur.archlinux.org/\$pkg.git
                cd \$pkg
                
                # Build package
                sudo -u builder makepkg -s --noconfirm
                
                # Copy to output
                cp *.pkg.tar.* /output/
                
                cd ..
            done
            
            echo '==> All packages built successfully!'
        "
    
    log_info "AUR packages built and saved to: $prebuilt_dir"
}

###############################################################################
# Docker Build
###############################################################################

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        echo "Install Docker: https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or you don't have permission"
        echo "Try: sudo systemctl start docker"
        echo "Or add yourself to the docker group: sudo usermod -aG docker \$USER"
        exit 1
    fi
}

run_build() {
    log_step "Starting smplOS ISO build in Docker container"
    log_info "Compositor: $COMPOSITOR"
    [[ -n "$EDITION" ]] && log_info "Edition: $EDITION"
    [[ -n "$RELEASE" ]] && log_info "Release mode: max xz compression (this will be slow)"
    [[ -n "$SKIP_AUR" ]] && log_info "Skipping: AUR packages"
    [[ -n "$SKIP_FLATPAK" ]] && log_info "Skipping: Flatpak packages"
    [[ -n "$SKIP_APPIMAGE" ]] && log_info "Skipping: AppImages"
    
    # Create output directory
    local release_dir="$PROJECT_ROOT/release"
    mkdir -p "$release_dir"
    
    # Create cache directories for persistence between builds
    local cache_dir="$PROJECT_ROOT/.cache"
    mkdir -p "$cache_dir/pacman"
    mkdir -p "$cache_dir/offline-repo"
    
    # Prebuilt packages directory (for EWW and other pre-compiled AUR packages)
    local prebuilt_dir="$SCRIPT_DIR/iso/prebuilt"
    
    # Build Docker arguments
    local docker_args=(
        --rm
        --privileged
        -v "$SCRIPT_DIR:/build/src:ro"
        -v "$release_dir:/build/release"
        -v "$cache_dir/pacman:/var/cache/pacman/pkg"
        -v "$cache_dir/offline-repo:/var/cache/smplos/mirror/offline"
        -e "COMPOSITOR=$COMPOSITOR"
    )
    
    # Mount prebuilt directory if it exists
    if [[ -d "$prebuilt_dir" ]]; then
        log_info "Using prebuilt packages from: $prebuilt_dir"
        docker_args+=(-v "$prebuilt_dir:/build/prebuilt:ro")
    fi
    
    [[ -n "$EDITION" ]] && docker_args+=(-e "EDITION=$EDITION")
    [[ -n "$RELEASE" ]] && docker_args+=(-e "RELEASE=1")
    [[ -n "$NO_CACHE" ]] && docker_args+=(-e "NO_CACHE=1")
    [[ -n "$VERBOSE" ]] && docker_args+=(-e "VERBOSE=1")
    
    # Pass host UID/GID so output files are owned by the user, not root
    docker_args+=(-e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)")
    [[ -n "$SKIP_AUR" ]] && docker_args+=(-e "SKIP_AUR=1")
    [[ -n "$SKIP_FLATPAK" ]] && docker_args+=(-e "SKIP_FLATPAK=1")
    [[ -n "$SKIP_APPIMAGE" ]] && docker_args+=(-e "SKIP_APPIMAGE=1")
    
    log_info "Pulling latest Arch Linux image..."
    docker pull archlinux:latest
    
    log_info "Starting build container..."
    docker run "${docker_args[@]}" archlinux:latest /build/src/builder/build.sh
    
    log_info ""
    log_info "Build complete!"
    log_info "ISO location: $release_dir/"
    ls -lh "$release_dir"/*.iso 2>/dev/null || log_warn "No ISO found"
}

###############################################################################
# Main
###############################################################################

main() {
    parse_args "$@"
    check_docker
    
    # Build AUR packages if missing (skip if --skip-aur is set)
    if [[ -z "$SKIP_AUR" ]]; then
        build_missing_aur_packages
    fi
    
    run_build
}

main "$@"
