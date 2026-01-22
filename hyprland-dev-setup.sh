#!/bin/bash
# -------------------------------
# Hyprland Dev Setup for WordPress & Laravel
# Author: Auto-generated for Abu Abdullah
# -------------------------------

set -e

echo "=============================="
echo "1. Ensuring Pictures and Projects directories exist..."
mkdir -p ~/Pictures
mkdir -p ~/Projects

echo "=============================="
echo "2. Creating Hyprland developer config..."
mkdir -p ~/.config/hypr

cat > ~/.config/hypr/hyprland.conf << 'EOF'
# ------------------------------
# Hyprland Developer Config
# ------------------------------

# Monitor setup
monitor=*,preferred,auto

# Wallpaper
exec-once=hyprpaper &

# Terminal
terminal=foot

# Launcher
exec-once=wofi --show drun &

# Workspaces (dev-focused)
workspace=1:Code
workspace=2:Browser
workspace=3:Database
workspace=4:Chat
workspace=5:Media

# Keybindings
bind=SUPER+ENTER,exec,foot                  # open terminal
bind=SUPER+SHIFT+ENTER,exec,foot -e bash   # terminal with bash
bind=SUPER+SHIFT+V,exec,code               # VSCode
bind=SUPER+B,exec,firefox                  # Browser
bind=SUPER+SHIFT+M,exec,phpstorm           # PHPStorm (if installed)
bind=SUPER+SHIFT+R,restart                 # restart Hyprland
bind=SUPER+SHIFT+Q,close                   # close window
bind=SUPER+H,moveleft
bind=SUPER+L,moveright
bind=SUPER+J,movedown
bind=SUPER+K,moveup

# Move windows between workspaces
bind=SUPER+SHIFT+1,movetoworkspace,1
bind=SUPER+SHIFT+2,movetoworkspace,2
bind=SUPER+SHIFT+3,movetoworkspace,3
bind=SUPER+SHIFT+4,movetoworkspace,4
bind=SUPER+SHIFT+5,movetoworkspace,5

# Workspace switching
bind=SUPER+1,workspace,1
bind=SUPER+2,workspace,2
bind=SUPER+3,workspace,3
bind=SUPER+4,workspace,4
bind=SUPER+5,workspace,5

# Floating windows
floatclass=popup,centered

# Notifications
exec-once=mako &

# Screenshots
bind=PRINT,exec,grim -g "$(slurp)" ~/Pictures/screenshot_$(date +%F_%T).png

# Autostart developer apps (optional)
exec-once=docker-desktop &
exec-once=discord &
EOF

echo "=============================="
echo "3. Installing optional developer apps..."
sudo pacman -S --needed --noconfirm code firefox phpstorm docker docker-compose

echo "=============================="
echo "4. Hyprland WordPress/Laravel dev setup complete!"
echo "Log out of KDE, select 'Hyprland' session from your login manager."
echo "Use:"
echo "  SUPER+ENTER -> Terminal"
echo "  SUPER+SHIFT+V -> VSCode"
echo "  SUPER+B -> Browser"
echo "  SUPER+SHIFT+R -> Restart Hyprland"
echo "Screenshots -> PRINT key"

