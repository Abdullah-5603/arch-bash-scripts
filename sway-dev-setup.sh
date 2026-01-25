#!/usr/bin/env bash
set -e

USER_NAME=$(whoami)

echo "==> System update"
sudo pacman -Syu --noconfirm

# --------------------------------------------------
# Wayland + Sway (VM-safe)
# --------------------------------------------------
echo "==> Installing Wayland + Sway"
sudo pacman -S --noconfirm \
  sway swaybg swaylock swayidle \
  wayland wayland-protocols \
  xorg-xwayland \
  wl-clipboard grim slurp \
  pipewire pipewire-pulse wireplumber \
  seatd dbus polkit polkit-gnome

sudo systemctl enable seatd
sudo usermod -aG seat $USER_NAME

# --------------------------------------------------
# Hyprland-like UX layer
# --------------------------------------------------
echo "==> Installing UI components"
sudo pacman -S --noconfirm \
  waybar rofi alacritty \
  nautilus firefox \
  brightnessctl pavucontrol

# --------------------------------------------------
# Fonts, icons, themes
# --------------------------------------------------
echo "==> Installing fonts and themes"
sudo pacman -S --noconfirm \
  ttf-jetbrains-mono \
  noto-fonts noto-fonts-emoji \
  papirus-icon-theme 
  
# --------------------------------------------------
# Core dev toolchain
# --------------------------------------------------
echo "==> Installing core dev tools"
sudo pacman -S --noconfirm \
  git base-devel cmake make \
  neovim tmux zsh code\
  ripgrep fd

# --------------------------------------------------
# Languages
# --------------------------------------------------
echo "==> Installing languages"

# C / C++
sudo pacman -S --noconfirm gcc clang lldb gdb

# Python
sudo pacman -S --noconfirm python python-pip python-virtualenv

# PHP (Laravel-ready)
sudo pacman -S --noconfirm \
  php php-fpm php-gd php-intl php-pgsql php-sqlite \
  php-redis php-imagick

# Composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --quiet
sudo mv composer.phar /usr/local/bin/composer
rm composer-setup.php

# Node.js
sudo pacman -S --noconfirm nodejs npm

# Golang
sudo pacman -S --noconfirm go

# C# / .NET
sudo pacman -S --noconfirm dotnet-sdk dotnet-runtime

# --------------------------------------------------
# Docker
# --------------------------------------------------
echo "==> Installing Docker"
sudo pacman -S --noconfirm docker docker-compose
sudo systemctl enable docker
sudo usermod -aG docker $USER_NAME

# --------------------------------------------------
# WordPress + WP-CLI
# --------------------------------------------------
echo "==> Installing WordPress tools"
sudo pacman -S --noconfirm mariadb

curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# --------------------------------------------------
# Config directories
# --------------------------------------------------
mkdir -p \
  ~/.config/sway \
  ~/.config/waybar \
  ~/.config/alacritty \
  ~/.config/rofi \
  ~/.config/gtk-3.0 \
  ~/.config/gtk-4.0 \
  ~/.config/fontconfig

# --------------------------------------------------
# Sway config (Hyprland-like workflow)
# --------------------------------------------------
cat > ~/.config/sway/config <<'EOF'
set $mod Mod4
font pango:JetBrains Mono 10

gaps inner 10
gaps outer 5
default_border pixel 2

output * bg /usr/share/backgrounds/sway/Sway_Wallpaper_Blue_1920x1080.png fill

exec_always dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway
exec waybar

bindsym $mod+Return exec alacritty
bindsym $mod+d exec rofi -show drun
bindsym $mod+e exec nautilus
bindsym $mod+b exec firefox
bindsym $mod+c exec code
bindsym $mod+Shift+q kill
bindsym $mod+Shift+r reload
bindsym $mod+Shift+e exec "swaymsg exit"

floating_modifier $mod normal
EOF

# --------------------------------------------------
# Waybar
# --------------------------------------------------
cat > ~/.config/waybar/config <<'EOF'
{
  "layer": "top",
  "modules-left": ["sway/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["cpu","memory","network","pulseaudio"]
}
EOF

cat > ~/.config/waybar/style.css <<'EOF'
* {
  font-family: JetBrains Mono;
  font-size: 12px;
}
window {
  background-color: #1e1e2e;
  color: #cdd6f4;
}
EOF

# --------------------------------------------------
# Alacritty
# --------------------------------------------------
cat > ~/.config/alacritty/alacritty.yml <<'EOF'
font:
  normal:
    family: JetBrains Mono
  size: 12
EOF

# --------------------------------------------------
# GTK Theme
# --------------------------------------------------
cat > ~/.config/gtk-3.0/settings.ini <<'EOF'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrains Mono 10
EOF

cp ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini

# --------------------------------------------------
# Login Manager: greetd + regreet (Themed)
# --------------------------------------------------
echo "==> Installing greetd login manager"
sudo pacman -S --noconfirm greetd regreet

echo "==> Configuring greetd"
sudo mkdir -p /etc/greetd

sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "regreet"
user = "greeter"
EOF

echo "==> Enabling greetd"
sudo systemctl enable greetd

# --------------------------------------------------
# regreet theme (matches desktop)
# --------------------------------------------------
echo "==> Configuring regreet theme"
mkdir -p ~/.config/regreet

cat > ~/.config/regreet/regreet.toml <<'EOF'
[appearance]
theme = "Arc-Dark"
icon_theme = "Papirus-Dark"
font = "JetBrains Mono 11"
EOF

# --------------------------------------------------
# ZSH
# --------------------------------------------------
chsh -s /bin/zsh

echo "==> COMPLETE"
echo "Reboot, login on TTY, run: sway"
