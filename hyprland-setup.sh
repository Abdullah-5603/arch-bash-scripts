#!/bin/bash
# -------------------------------
# Complete Stable Hyprland Setup on Arch Linux
# Author: Auto-generated for Abu Abdullah
# -------------------------------

set -e

echo "=============================="
echo "1. Updating system..."
sudo pacman -Syu --noconfirm

echo "=============================="
echo "2. Removing conflicting Hyprland packages (if any)..."
sudo pacman -Rns --noconfirm hyprutils hyprland hyprland-xdg-desktop-portal hyprpaper hyprpicker hyprshot || true
yay -Rns --noconfirm hyprutils-git hyprwayland-scanner-git hyprshot-git || true

echo "=============================="
echo "3. Installing core dependencies..."
sudo pacman -S --needed --noconfirm base-devel cmake meson ninja pkgconf \
wayland-protocols qt5-wayland qt6-wayland extra-cmake-modules libxkbcommon \
wlroots0.18 cairo pango libinput xdg-desktop-portal-wlr \
pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
swaybg swayidle swaylock grim slurp mako git

echo "=============================="
echo "4. Installing stable Hyprland and utilities..."
sudo pacman -S --needed --noconfirm hyprland hyprland-xdg-desktop-portal \
foot wofi hyprpaper mako grim slurp

echo "=============================="
echo "5. Setting up Hyprland configuration..."
mkdir -p ~/.config/hypr

cat > ~/.config/hypr/hyprland.conf << 'EOF'
# ------------------------------
# Hyprland stable config
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

echo "=============================="
echo "6. Creating Pictures directory for screenshots..."
mkdir -p ~/Pictures

echo "=============================="
echo "Hyprland stable setup complete!"
echo "Log out of KDE, select 'Hyprland' session from your login manager, and use:"
echo "  SUPER+ENTER -> Open terminal"
echo "  SUPER+SHIFT+R -> Restart Hyprland"
echo "Screenshots -> PRINT key"