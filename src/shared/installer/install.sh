#!/bin/bash

# smplOS Post-Install Script
# Runs inside the chroot after archinstall completes
# Based on Omarchy installer architecture

set -eEo pipefail

# Define smplOS locations
export SMPLOS_PATH="$HOME/.local/share/smplos"
export SMPLOS_INSTALL="$SMPLOS_PATH/install"
export SMPLOS_INSTALL_LOG_FILE="/var/log/smplos-install.log"
export PATH="$SMPLOS_PATH/bin:$PATH"

# Load helpers
source "$SMPLOS_INSTALL/helpers/all.sh"

# Start install timer
SMPLOS_START_EPOCH=$(date +%s)
echo "=== smplOS Installation Started: $(date '+%Y-%m-%d %H:%M:%S') ===" >>"$SMPLOS_INSTALL_LOG_FILE" 2>/dev/null || true

# Chroot-aware systemctl enable (don't use --now in chroot)
chrootable_systemctl_enable() {
  if [[ -n "${SMPLOS_CHROOT_INSTALL:-}" ]]; then
    sudo systemctl enable "$1"
  else
    sudo systemctl enable --now "$1"
  fi
}

echo "==> Configuring desktop environment..."

# Install AUR packages from the offline mirror
# Reads the merged packages-aur.txt (shared + compositor, written by build.sh)
if [[ -d /var/cache/smplos/mirror/offline ]]; then
  aur_list="$HOME/.local/share/smplos/packages-aur.txt"
  if [[ -f "$aur_list" ]]; then
    echo "==> Installing AUR packages from offline mirror..."
    while IFS= read -r pkg; do
      [[ "$pkg" =~ ^#.*$ || -z "$pkg" ]] && continue
      local_pkg=$(find /var/cache/smplos/mirror/offline -name "${pkg}-[0-9]*.pkg.tar.*" ! -name "*-debug-*" 2>/dev/null | head -1)
      if [[ -n "$local_pkg" ]]; then
        echo "    Installing: $(basename "$local_pkg")"
        sudo pacman -U --noconfirm --needed "$local_pkg" 2>/dev/null || true
      fi
    done < "$aur_list"
  fi
fi

# Copy configs to user home
if [[ -d "$SMPLOS_PATH/config" ]]; then
  mkdir -p "$HOME/.config"
  cp -r "$SMPLOS_PATH/config/"* "$HOME/.config/" 2>/dev/null || true
  # Ensure EWW listener scripts are executable (cp from skel may strip +x)
  find "$HOME/.config/eww/scripts" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
  echo "==> Config files deployed:"
  ls -la "$HOME/.config/eww/" 2>/dev/null || echo "    WARNING: eww config dir missing!"
fi

# Deploy theme system
# Always ensure all stock themes are deployed (skel may only have partial data)
if [[ -d "$SMPLOS_PATH/themes" ]]; then
  echo "==> Deploying theme system..."
  :  # themes already in place
fi

# Deploy edition desktop entries (web app wrappers like Discord)
if [[ -d "$SMPLOS_PATH/applications" ]]; then
  echo "==> Deploying edition desktop entries..."
  mkdir -p "$HOME/.local/share/applications"
  cp "$SMPLOS_PATH/applications/"*.desktop "$HOME/.local/share/applications/" 2>/dev/null || true
fi
# Deploy edition icons
if [[ -d "$SMPLOS_PATH/icons/hicolor" ]]; then
  echo "==> Deploying edition icons..."
  sudo cp -r "$SMPLOS_PATH/icons/hicolor" /usr/share/icons/
  sudo gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
fi

# Deploy custom os-release (smplOS branding)
if [[ -f "$SMPLOS_PATH/system/os-release" ]]; then
  echo "==> Setting os-release..."
  sudo cp "$SMPLOS_PATH/system/os-release" /etc/os-release
fi

# Apply default theme (catppuccin) to generate all config files
echo "==> Setting default theme..."
theme-set catppuccin || echo "    WARNING: theme-set failed (exit $?)"

# Set Fish as default shell
if command -v fish &>/dev/null; then
  echo "==> Setting Fish as default shell..."
  sudo chsh -s /usr/bin/fish "$USER"
fi

# Verify EWW theme colors were deployed
if [[ -f "$HOME/.config/eww/theme-colors.scss" ]]; then
  echo "    EWW theme-colors.scss: OK"
else
  echo "    WARNING: EWW theme-colors.scss not found after theme-set!"
fi

# Deploy default wallpaper
default_wp=$(find "$SMPLOS_PATH/wallpapers/" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' \) 2>/dev/null | head -1)
if [[ -n "$default_wp" ]]; then
  echo "==> Deploying default wallpaper..."
  mkdir -p "$HOME/Pictures/Wallpapers"
  cp "$default_wp" "$HOME/Pictures/Wallpapers/$(basename "$default_wp")"
fi

# Configure VS Code / VSCodium to use gnome-libsecret for credential storage
# Without this, Electron may fail to auto-detect the keyring on Wayland
for argv_dir in "$HOME/.vscode" "$HOME/.vscode-oss"; do
  mkdir -p "$argv_dir"
  cat > "$argv_dir/argv.json" <<'ARGVEOF'
{
  "password-store": "gnome-libsecret"
}
ARGVEOF
done

# Configure PAM for gnome-keyring auto-unlock
# Without this, gnome-keyring-daemon starts but the keyring stays locked,
# causing VS Code/Brave/git to show "no keyring found" errors
echo "==> Configuring PAM for gnome-keyring auto-unlock..."
for pam_file in /etc/pam.d/login /etc/pam.d/greetd; do
  if [[ -f "$pam_file" ]]; then
    grep -q pam_gnome_keyring "$pam_file" || {
      # auth: unlock the keyring with the login password
      echo "auth       optional     pam_gnome_keyring.so" | sudo tee -a "$pam_file" >/dev/null
      # session: auto-start the daemon
      echo "session    optional     pam_gnome_keyring.so auto_start" | sudo tee -a "$pam_file" >/dev/null
    }
  fi
done

# Setup greetd with autologin
echo "==> Setting up greetd autologin..."
sudo mkdir -p /etc/greetd

cat <<EOF | sudo tee /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --remember-session --cmd start-hyprland"
user = "greeter"

[initial_session]
command = "start-hyprland"
user = "$USER"
EOF

# Enable greetd
sudo systemctl enable greetd.service

# Setup Plymouth if installed
if command -v plymouth-set-default-theme &>/dev/null; then
  echo "==> Configuring Plymouth..."
  
  plymouth_dir="$HOME/.config/smplos/branding/plymouth"
  if [[ -d "$plymouth_dir" ]]; then
    sudo mkdir -p /usr/share/plymouth/themes/smplos
    sudo cp -r "$plymouth_dir/"* /usr/share/plymouth/themes/smplos/
    sudo plymouth-set-default-theme smplos
    
    # Replace Arch Linux watermark in spinner fallback theme with our logo
    if [[ -f "$plymouth_dir/logo.png" && -d /usr/share/plymouth/themes/spinner ]]; then
      sudo cp "$plymouth_dir/logo.png" /usr/share/plymouth/themes/spinner/watermark.png
    fi
  fi
  
  sudo mkdir -p /etc/mkinitcpio.conf.d
  sudo tee /etc/mkinitcpio.conf.d/smplos_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)
EOF

  # Configure silent boot in GRUB
  if [[ -f /etc/default/grub ]]; then
    # Ensure cleaner boot logs
    if ! grep -q "splash" /etc/default/grub; then
      sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0 mce=dont_log_ce"/' /etc/default/grub
    fi
    
    # Branding: Set GRUB Distributor to smplOS
    sudo sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="smplOS"/' /etc/default/grub

    sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi

  # Delay plymouth-quit to ensure smooth transition
  sudo mkdir -p /etc/systemd/system/plymouth-quit.service.d/
  sudo tee /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf <<'EOF' >/dev/null
[Unit]
After=multi-user.target

[Service]
ExecStart=
ExecStart=/usr/bin/plymouth quit --retain-splash
EOF
  sudo systemctl mask plymouth-quit-wait.service

  # Rebuild initramfs to include plymouth and new hooks
  sudo mkinitcpio -P
fi

# Restore standard pacman.conf (remove offline mirror, point to real repos)
echo "==> Restoring standard pacman configuration..."
sudo tee /etc/pacman.conf > /dev/null << 'PACMANEOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
ParallelDownloads = 5
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
Color
VerbosePkgLists

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
PACMANEOF

# Initialize mirrorlist if empty (use geo mirror as default)
if [[ ! -s /etc/pacman.d/mirrorlist ]]; then
  echo "==> Setting up default mirror..."
  echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist > /dev/null
fi

# Clean up offline mirror cache
sudo rm -rf /var/cache/smplos/mirror 2>/dev/null || true

# Allow passwordless reboot after install - cleaned up on first boot
sudo tee /etc/sudoers.d/99-smplos-installer-reboot >/dev/null <<EOF
$USER ALL=(ALL) NOPASSWD: /usr/bin/reboot
EOF
sudo chmod 440 /etc/sudoers.d/99-smplos-installer-reboot

echo "==> smplOS installation complete!"

# Calculate installation duration
SMPLOS_END_EPOCH=$(date +%s)
SMPLOS_DURATION=$((SMPLOS_END_EPOCH - SMPLOS_START_EPOCH))
SMPLOS_MINS=$((SMPLOS_DURATION / 60))
SMPLOS_SECS=$((SMPLOS_DURATION % 60))

# Also try to get archinstall duration from its log
ARCH_TIME_STR=""
if [[ -f /var/log/archinstall/install.log ]]; then
  ARCH_START=$(grep -m1 '^\[' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)
  ARCH_END=$(grep 'Installation completed without any errors' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)
  if [[ -n "$ARCH_START" && -n "$ARCH_END" ]]; then
    ARCH_START_EPOCH=$(date -d "$ARCH_START" +%s 2>/dev/null || true)
    ARCH_END_EPOCH=$(date -d "$ARCH_END" +%s 2>/dev/null || true)
    if [[ -n "$ARCH_START_EPOCH" && -n "$ARCH_END_EPOCH" ]]; then
      ARCH_DURATION=$((ARCH_END_EPOCH - ARCH_START_EPOCH))
      ARCH_MINS=$((ARCH_DURATION / 60))
      ARCH_SECS=$((ARCH_DURATION % 60))
      ARCH_TIME_STR="Archinstall: ${ARCH_MINS}m ${ARCH_SECS}s"
      TOTAL_DURATION=$((ARCH_DURATION + SMPLOS_DURATION))
      TOTAL_MINS=$((TOTAL_DURATION / 60))
      TOTAL_SECS=$((TOTAL_DURATION % 60))
    fi
  fi
fi

# Log the timing summary
{
  echo "=== Installation Time Summary ==="
  [[ -n "$ARCH_TIME_STR" ]] && echo "$ARCH_TIME_STR"
  echo "smplOS:      ${SMPLOS_MINS}m ${SMPLOS_SECS}s"
  [[ -n "${TOTAL_MINS:-}" ]] && echo "Total:       ${TOTAL_MINS}m ${TOTAL_SECS}s"
  echo "================================="
} >>"$SMPLOS_INSTALL_LOG_FILE" 2>/dev/null || true

# Show reboot prompt (matching Omarchy's finished.sh)
clear
echo
gum style --foreground 2 --bold --padding "1 0 1 $PADDING_LEFT" "smplOS Installation Complete!"
echo

# Display installation time
if [[ -n "${TOTAL_MINS:-}" ]]; then
  gum style --foreground 6 --padding "0 0 0 $PADDING_LEFT" "Installed in ${TOTAL_MINS}m ${TOTAL_SECS}s (archinstall: ${ARCH_MINS}m ${ARCH_SECS}s + smplOS: ${SMPLOS_MINS}m ${SMPLOS_SECS}s)"
else
  gum style --foreground 6 --padding "0 0 0 $PADDING_LEFT" "Installed in ${SMPLOS_MINS}m ${SMPLOS_SECS}s"
fi
echo
gum style --foreground 3 --padding "0 0 1 $PADDING_LEFT" "Please remove the installation media (USB/CD) before rebooting."
echo

# Only prompt if using gum is available, otherwise just mark complete
if gum confirm --padding "0 0 0 $PADDING_LEFT" --show-help=false --default --affirmative "Reboot Now" --negative "" ""; then
  clear
  
  # If running in chroot, just mark complete and exit - outer script handles reboot
  if [[ -n "${SMPLOS_CHROOT_INSTALL:-}" ]]; then
    # Create marker BEFORE removing sudoers (while we still have NOPASSWD)
    sudo touch /var/tmp/smplos-install-completed
    # Remove installer sudoers override
    sudo rm -f /etc/sudoers.d/99-smplos-installer
    exit 0
  else
    # Not in chroot - cleanup and reboot directly
    sudo rm -f /etc/sudoers.d/99-smplos-installer
    sudo reboot 2>/dev/null
  fi
else
  # User declined reboot, just cleanup
  sudo rm -f /etc/sudoers.d/99-smplos-installer
fi
