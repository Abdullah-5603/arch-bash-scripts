#!/bin/bash
# -------------------------------
# Complete Hyprland Setup on Arch Linux
# Author: Auto-generated for Abu Abdullah
# -------------------------------

set -e

echo "1. Updating system..."
sudo pacman -Syu --noconfirm

echo "2. Installing core dependencies..."
sudo pacman -S --needed --noconfirm base-devel cmake meson ninja pkgconf \
wayland-protocols qt5-wayland qt6-wayland extra-cmake-modules libxkbcommon \
wlroots0.18 cairo pango libinput xdg-desktop-portal-wlr \
pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
swaybg swayidle swaylock grim slurp mako git

# -------------------------------
# Install yay (AUR helper) if missing
# -------------------------------
if ! command -v yay &> /dev/null
then
    echo "3. Installing yay (AUR helper)..."
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
fi

# -------------------------------
# Install Hyprland from AUR
# -------------------------------
echo "4. Installing Hyprland..."
yay -S --noconfirm hyprland hyprland-xdg-desktop-portal-git hyprpaper-git hyprpicker-git hyprshot-git foot wofi

# -------------------------------
# Setup configuration directory
# -------------------------------
echo "5. Creating Hyprland config..."
mkdir -p ~/.config/hypr

cat > ~/.config/hypr/hyprland.conf << 'EOF'
# ------------------------------
# Hyprland basic config
# ------------------------------

# Monitor setup
monitor=*,preferred,auto

# Wallpaper
exec-once=hyprpaper &

# Terminal
terminal=foot

# Launcher
exec-once=wofi --show drun &

# Workspaces
workspace=1:Web
workspace=2:Code
workspace=3:Chat
workspace=4:Media
workspace=5:Misc

# Keybindings
bind=SUPER+ENTER,exec,foot                  # open terminal
bind=SUPER+SHIFT+Q,close                   # close window
bind=SUPER+SHIFT+R,restart                 # restart Hyprland
bind=SUPER+H,moveleft
bind=SUPER+L,moveright
bind=SUPER+J,movedown
bind=SUPER+K,moveup

# Move windows between workspaces
bind=SUPER+SHIFT+1,movetoworkspace,1
bind=SUPER+SHIFT+2,movetoworkspace,2
bind=SUPER+SHIFT+3,movetoworkspace,3

# Workspace switching
bind=SUPER+1,workspace,1
bind=SUPER+2,workspace,2
bind=SUPER+3,workspace,3

# Floating windows
floatclass=popup,centered

# Notifications
exec-once=mako &

# Screenshots
bind=PRINT,exec,grim -g "$(slurp)" ~/Pictures/screenshot_$(date +%F_%T).png

# Autostart KDE apps (optional)
exec-once=kdeconnect-indicator &
exec-once=kdeconnect-settings &
EOF

# -------------------------------
# Setup Pictures directory for screenshots
# -------------------------------
mkdir -p ~/Pictures

echo "6. Hyprland setup complete!"
echo "Log out of KDE, and select 'Hyprland' session from your login manager."
echo "Use SUPER+ENTER to open terminal, SUPER+SHIFT+R to restart Hyprland."
