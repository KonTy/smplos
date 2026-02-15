#!/bin/bash
# smplOS Hyprland Post-installation Script
# Runs after packages are installed to configure Hyprland environment

set -e

echo "Configuring Hyprland environment..."

# Enable essential services
systemctl enable NetworkManager
systemctl enable bluetooth

# Enable pipewire for user
# This is typically done via user services, enabled by default

# Set default shell to zsh for the user
if id "smplos" &>/dev/null; then
    chsh -s /bin/zsh smplos 2>/dev/null || true
fi

# Create XDG directories
sudo -u smplos mkdir -p /home/smplos/{Desktop,Documents,Downloads,Music,Pictures,Videos}
sudo -u smplos mkdir -p /home/smplos/Pictures/Screenshots
sudo -u smplos mkdir -p /home/smplos/Pictures/Wallpapers

# Ensure .config directory exists
sudo -u smplos mkdir -p /home/smplos/.config

# Set proper permissions
chown -R smplos:smplos /home/smplos

# Configure GTK theme settings (settings.ini — X11 fallback)
sudo -u smplos mkdir -p /home/smplos/.config/gtk-3.0
cat > /home/smplos/.config/gtk-3.0/settings.ini << 'GTKEOF'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=JetBrains Mono 11
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
gtk-overlay-scrolling=0
GTKEOF
chown smplos:smplos /home/smplos/.config/gtk-3.0/settings.ini

# Configure dconf/GSettings for Wayland
# On Wayland, GTK apps ignore settings.ini and read from dconf instead.
# gsettings won't work in chroot (no dbus), so write the dconf database directly.
sudo -u smplos mkdir -p /home/smplos/.config/dconf
sudo -u smplos dbus-run-session -- gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark" 2>/dev/null || true
sudo -u smplos dbus-run-session -- gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
sudo -u smplos dbus-run-session -- gsettings set org.gnome.desktop.interface icon-theme "Adwaita" 2>/dev/null || true
sudo -u smplos dbus-run-session -- gsettings set org.gnome.desktop.interface cursor-theme "Adwaita" 2>/dev/null || true
sudo -u smplos dbus-run-session -- gsettings set org.gnome.desktop.interface font-name "JetBrains Mono 11" 2>/dev/null || true

# Configure Qt to use kvantum
echo "export QT_QPA_PLATFORMTHEME=qt5ct" >> /etc/environment

# Enable XDG portal environment variables
cat >> /etc/environment << 'ENVEOF'
XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=Hyprland
ENVEOF

echo "Hyprland configuration complete!"
