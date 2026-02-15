#!/bin/bash
#
# smplOS ISO Builder
# Builds the ISO in a clean Arch Linux container for reproducibility.
# Designed to work on first run on any Linux distro.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${BLUE}${BOLD}==>${NC}${BOLD} $*${NC}"; }

die() { log_error "$@"; exit 1; }

###############################################################################
# Help
###############################################################################

show_help() {
    cat << 'EOF'
smplOS ISO Builder

Usage: build-iso.sh [OPTIONS]

Options:
    -c, --compositor NAME   Compositor to build (hyprland, dwm) [default: hyprland]
    -e, --edition NAME      Edition variant (lite, creators) [optional]
    -r, --release           Release build: max xz compression (slow, smallest ISO)
    -n, --no-cache          Force fresh package downloads
    -v, --verbose           Verbose output
    --skip-aur              Skip AUR packages (faster, no Rust compilation)
    --skip-flatpak          Skip Flatpak packages
    --skip-appimage         Skip AppImages
    -h, --help              Show this help

Examples:
    ./build-iso.sh                        # Standard build
    ./build-iso.sh --skip-aur             # Skip AUR (much faster)
    ./build-iso.sh -c hyprland -e lite    # Hyprland Lite edition
    ./build-iso.sh --release              # Max compression for release
EOF
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
            -c|--compositor) COMPOSITOR="$2"; shift 2 ;;
            -e|--edition)    EDITION="$2"; shift 2 ;;
            -r|--release)    RELEASE="1"; shift ;;
            -n|--no-cache)   NO_CACHE="1"; shift ;;
            -v|--verbose)    VERBOSE="1"; shift ;;
            --skip-aur)      SKIP_AUR="1"; shift ;;
            --skip-flatpak)  SKIP_FLATPAK="1"; shift ;;
            --skip-appimage) SKIP_APPIMAGE="1"; shift ;;
            -h|--help)       show_help; exit 0 ;;
            *) die "Unknown option: $1 (see --help)" ;;
        esac
    done
}

###############################################################################
# Prerequisite Detection & Auto-Install
###############################################################################

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    elif command -v lsb_release &>/dev/null; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

install_docker() {
    local distro="$1"
    log_step "Installing Docker"

    case "$distro" in
        arch|endeavouros|manjaro|garuda|cachyos)
            sudo pacman -S --noconfirm --needed docker
            ;;
        ubuntu|debian|pop|linuxmint|zorin)
            if ! command -v docker &>/dev/null; then
                sudo apt-get update
                sudo apt-get install -y ca-certificates curl gnupg
                sudo install -m 0755 -d /etc/apt/keyrings
                # Map derivatives to base distro for Docker repo
                local base_id="$distro"
                case "$distro" in pop|linuxmint|zorin) base_id="ubuntu" ;; esac
                curl -fsSL "https://download.docker.com/linux/$base_id/gpg" \
                    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                sudo chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                    https://download.docker.com/linux/$base_id \
                    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
                    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt-get update
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            fi
            ;;
        fedora|nobara)
            sudo dnf install -y docker
            ;;
        opensuse*|sles)
            sudo zypper install -y docker
            ;;
        void)
            sudo xbps-install -y docker
            ;;
        *)
            die "Unknown distro '$distro'. Install Docker manually: https://docs.docker.com/engine/install/"
            ;;
    esac

    # Enable and start Docker
    if command -v systemctl &>/dev/null; then
        sudo systemctl enable --now docker
    fi

    # Add user to docker group
    if ! groups | grep -qw docker; then
        sudo usermod -aG docker "$USER"
        log_warn "Added $USER to docker group. You may need to log out and back in."
        log_warn "For now, using sudo for Docker commands."
    fi
}

# Docker command (may be overridden to "sudo docker" if needed)
DOCKER_CMD="docker"

check_prerequisites() {
    log_step "Checking prerequisites"
    local distro
    distro=$(detect_distro)
    log_info "Detected distro: $distro"

    # Docker installed?
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not found"
        read -rp "Install Docker automatically? [Y/n] " answer
        if [[ "${answer,,}" != "n" ]]; then
            install_docker "$distro"
        else
            die "Docker is required. Install from https://docs.docker.com/engine/install/"
        fi
    fi

    # Docker daemon running? Self-heal if not.
    if ! docker info &>/dev/null 2>&1; then
        # Check if it's a permissions issue first (daemon running but user not in docker group)
        if sudo -n docker info &>/dev/null 2>&1; then
            log_warn "Docker requires sudo (run 'sudo usermod -aG docker \$USER' and re-login to fix)"
            DOCKER_CMD="sudo docker"
        else
            # Daemon genuinely not running -- try to start it
            log_warn "Docker daemon is not running"
            if command -v systemctl &>/dev/null; then
                log_info "Requesting sudo to start Docker service..."
                sudo systemctl start docker
                sleep 2
            fi
            # Verify it came up
            if docker info &>/dev/null 2>&1; then
                log_info "Docker started successfully"
            elif sudo -n docker info &>/dev/null 2>&1; then
                log_warn "Docker requires sudo (run 'sudo usermod -aG docker \$USER' and re-login to fix)"
                DOCKER_CMD="sudo docker"
            else
                # Last resort: restart the daemon (fixes stale network/bridge issues)
                log_warn "Docker failed to respond, attempting restart..."
                if command -v systemctl &>/dev/null; then
                    sudo systemctl restart docker
                    sleep 3
                fi
                if docker info &>/dev/null 2>&1; then
                    log_info "Docker recovered after restart"
                elif sudo docker info &>/dev/null 2>&1; then
                    DOCKER_CMD="sudo docker"
                else
                    die "Cannot start Docker. Try manually: sudo systemctl restart docker"
                fi
            fi
        fi
    fi

    # Disk space check (need ~10GB)
    local free_gb
    free_gb=$(df --output=avail -BG "$PROJECT_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [[ -n "$free_gb" && "$free_gb" -lt 10 ]]; then
        log_warn "Low disk space: ${free_gb}GB free (10GB+ recommended)"
        read -rp "Continue anyway? [y/N] " answer
        [[ "${answer,,}" == "y" ]] || exit 1
    fi

    log_info "Prerequisites OK (Docker $(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1))"
}

###############################################################################
# Build Missing AUR Packages (with retries and proper DNS)
###############################################################################

build_missing_aur_packages() {
    local prebuilt_dir="$SCRIPT_DIR/iso/prebuilt"
    mkdir -p "$prebuilt_dir"

    # Collect AUR package names from all package lists
    local aur_packages=()
    for f in "$SCRIPT_DIR/shared/packages-aur.txt" "$SCRIPT_DIR/compositors/${COMPOSITOR}/packages-aur.txt"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            aur_packages+=("$line")
        done < "$f"
    done
    [[ ${#aur_packages[@]} -eq 0 ]] && return 0

    # Check which need building
    local need_build=()
    for pkg in "${aur_packages[@]}"; do
        if ! ls "$prebuilt_dir"/${pkg}-[0-9]*.pkg.tar.* &>/dev/null; then
            need_build+=("$pkg")
        else
            log_info "Found prebuilt: $pkg"
        fi
    done
    [[ ${#need_build[@]} -eq 0 ]] && { log_info "All AUR packages already built"; return 0; }

    log_step "Building AUR packages: ${need_build[*]}"
    log_info "This may take a while on first run..."

    # Detect if any package needs Rust (avoid installing rustup otherwise)
    local rust_line=""
    for pkg in "${need_build[@]}"; do
        case "$pkg" in eww|eww-git|eww-wayland|*-rs|*-rust)
            rust_line="retry pacman -S --noconfirm --needed rustup && rustup default stable"
            break ;;
        esac
    done

    # Write package list to file (avoids shell quoting bugs in heredoc)
    local pkg_list_file
    pkg_list_file=$(mktemp)
    printf '%s\n' "${need_build[@]}" > "$pkg_list_file"

    local docker_run_args=(
        run --rm
        --dns 1.1.1.1 --dns 8.8.8.8
        -v "$prebuilt_dir:/output"
        -v "$pkg_list_file:/tmp/packages.txt:ro"
        archlinux:latest bash -c "
            set -e
            retry() {
                local n=0
                while true; do
                    \"\$@\" && return 0
                    ((n++))
                    [[ \$n -ge 3 ]] && { echo \"FAILED after 3 tries: \$*\"; return 1; }
                    echo \"RETRY \$n/3: \$*\"
                    sleep \$((n * 5))
                done
            }
            retry pacman -Syu --noconfirm
            retry pacman -S --noconfirm --needed base-devel git
            ${rust_line}
            useradd -m builder
            echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
            cd /home/builder
            while IFS= read -r pkg; do
                [[ -z \"\$pkg\" ]] && continue
                echo \"==> Building \$pkg...\"
                retry sudo -u builder git clone \"https://aur.archlinux.org/\$pkg.git\"
                cd \"\$pkg\"
                # Import any PGP keys required by the package
                if grep -q 'validpgpkeys' PKGBUILD; then
                    grep -A 20 'validpgpkeys=' PKGBUILD \
                        | grep -oP '[0-9A-F]{16,}' \
                        | while read -r key; do
                            echo \"==> Importing GPG key: \$key\"
                            sudo -u builder gpg --keyserver keyserver.ubuntu.com --recv-keys \"\$key\" 2>/dev/null \
                                || sudo -u builder gpg --keyserver keys.openpgp.org --recv-keys \"\$key\" 2>/dev/null \
                                || echo \"WARN: could not import key \$key\"
                        done
                fi
                sudo -u builder makepkg -s --noconfirm
                cp *.pkg.tar.* /output/
                cd ..
                echo \"==> \$pkg done\"
            done < /tmp/packages.txt
            echo '==> All AUR packages built!'
        "
    )

    # Run with auto-recovery for Docker network failures
    if ! $DOCKER_CMD "${docker_run_args[@]}" 2>/tmp/docker-aur-err.log; then
        if grep -qi 'network\|veth\|bridge\|endpoint' /tmp/docker-aur-err.log 2>/dev/null; then
            log_warn "Docker networking failed -- restarting Docker to recover..."
            log_info "Requesting sudo to restart Docker service..."
            sudo systemctl restart docker
            sleep 3
            log_info "Retrying AUR build..."
            $DOCKER_CMD "${docker_run_args[@]}" || die "AUR build failed after Docker restart"
        else
            cat /tmp/docker-aur-err.log >&2
            die "AUR package build failed"
        fi
    fi
    rm -f /tmp/docker-aur-err.log

    rm -f "$pkg_list_file"
    log_info "AUR packages saved to: $prebuilt_dir"
}

###############################################################################
# Docker Build
###############################################################################

run_build() {
    log_step "Starting ISO build in Docker"
    log_info "Compositor: $COMPOSITOR"
    [[ -n "$EDITION" ]]  && log_info "Edition: $EDITION"
    [[ -n "$RELEASE" ]]  && log_info "Release: max xz compression"
    [[ -n "$SKIP_AUR" ]] && log_info "Skipping: AUR"

    local release_dir="$PROJECT_ROOT/release"
    mkdir -p "$release_dir"

    # Dated build cache: same-day rebuilds reuse packages, new day = fresh
    local build_date
    build_date=$(date +%Y-%m-%d)
    local cache_dir="$PROJECT_ROOT/.cache/build_${build_date}"
    mkdir -p "$cache_dir/pacman" "$cache_dir/offline-repo"

    # Prune old caches (keep last 3 days)
    if [[ -d "$PROJECT_ROOT/.cache" ]]; then
        find "$PROJECT_ROOT/.cache" -maxdepth 1 -name 'build_*' -type d \
            | sort | head -n -3 | xargs -r rm -rf
    fi

    local prebuilt_dir="$SCRIPT_DIR/iso/prebuilt"

    local docker_args=(
        --rm --privileged
        --dns 1.1.1.1 --dns 8.8.8.8
        -v "$SCRIPT_DIR:/build/src:ro"
        -v "$release_dir:/build/release"
        -v "$cache_dir/offline-repo:/var/cache/smplos/mirror/offline"
        -v "$cache_dir/pacman:/var/cache/smplos/pacman-cache"
        -e "COMPOSITOR=$COMPOSITOR"
        -e "HOST_UID=$(id -u)"
        -e "HOST_GID=$(id -g)"
    )

    # Mount host pacman cache if on Arch-based system (huge speedup)
    if [[ -d /var/cache/pacman/pkg ]]; then
        log_info "Mounting host pacman cache (Arch detected)"
        docker_args+=(-v "/var/cache/pacman/pkg:/var/cache/pacman/pkg:ro")
    fi

    # Mount prebuilt AUR packages
    if [[ -d "$prebuilt_dir" ]] && ls "$prebuilt_dir"/*.pkg.tar.* &>/dev/null 2>&1; then
        log_info "Mounting prebuilt AUR packages"
        docker_args+=(-v "$prebuilt_dir:/build/prebuilt:ro")
    fi

    [[ -n "$EDITION" ]]       && docker_args+=(-e "EDITION=$EDITION")
    [[ -n "$RELEASE" ]]       && docker_args+=(-e "RELEASE=1")
    [[ -n "$NO_CACHE" ]]      && docker_args+=(-e "NO_CACHE=1")
    [[ -n "$VERBOSE" ]]       && docker_args+=(-e "VERBOSE=1")
    [[ -n "$SKIP_AUR" ]]      && docker_args+=(-e "SKIP_AUR=1")
    [[ -n "$SKIP_FLATPAK" ]]  && docker_args+=(-e "SKIP_FLATPAK=1")
    [[ -n "$SKIP_APPIMAGE" ]] && docker_args+=(-e "SKIP_APPIMAGE=1")

    log_info "Pulling Arch Linux image..."
    $DOCKER_CMD pull archlinux:latest

    log_info "Starting build container..."
    if ! $DOCKER_CMD run "${docker_args[@]}" archlinux:latest /build/src/builder/build.sh 2>/tmp/docker-build-err.log; then
        if grep -qi 'network\|veth\|bridge\|endpoint' /tmp/docker-build-err.log 2>/dev/null; then
            log_warn "Docker networking failed -- restarting Docker to recover..."
            log_info "Requesting sudo to restart Docker service..."
            sudo systemctl restart docker
            sleep 3
            log_info "Retrying ISO build..."
            $DOCKER_CMD run "${docker_args[@]}" archlinux:latest /build/src/builder/build.sh \
                || { cat /tmp/docker-build-err.log >&2; die "ISO build failed after Docker restart"; }
        else
            cat /tmp/docker-build-err.log >&2
            die "ISO build failed"
        fi
    fi
    rm -f /tmp/docker-build-err.log

    echo ""
    log_info "Build complete!"
    ls -lh "$release_dir"/*.iso 2>/dev/null || log_warn "No ISO found in output"
}

###############################################################################
# Main
###############################################################################

main() {
    echo -e "${BOLD}smplOS ISO Builder${NC}\n"

    parse_args "$@"
    check_prerequisites

    if [[ -z "$SKIP_AUR" ]]; then
        build_missing_aur_packages
    fi

    run_build
}

main "$@"
