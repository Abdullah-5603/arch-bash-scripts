#!/bin/bash
# Full Arch Dev + Hyprland Setup Script for HP Victus
# Run as root or sudo

# --- VARIABLES ---
read -p "Enter your Linux username: " USER
HOME_DIR="/home/$USER"

# --- STEP 1: Update System ---
pacman -Syu --noconfirm

# --- STEP 2: Essential Packages ---
pacman -S --noconfirm base-devel git sudo wget curl unzip htop neofetch networkmanager \
vim nano tmux zsh

# Enable NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager

# --- STEP 3: Install Hyprland & Wayland Utilities ---
pacman -S --noconfirm hyprland swaybg swaylock wayland wayland-protocols xdg-desktop-portal xdg-desktop-portal-hyprland alacritty mako swayidle grim slurp wl-clipboard \
waybar qt5-wayland qt6-wayland qt5ct qt6ct noto-fonts ttf-jetbrains-mono ttf-ubuntu-font-family

# --- STEP 4: Enable SDDM + Themes ---
echo "Select SDDM Theme:"
echo "1) Layan"
echo "2) Sweet"
echo "3) Nordic"
read -p "Enter number [1-3]: (default: 1)" THEME_CHOICE

case $THEME_CHOICE in
  1) THEME_NAME="layan" && git clone https://github.com/tildearrow/layan-sddm.git /usr/share/sddm/themes/layan ;;
  2) THEME_NAME="sweet" && git clone https://github.com/sddm/sddm-theme-sweet.git /usr/share/sddm/themes/sweet ;;
  3) THEME_NAME="nordic" && git clone https://github.com/kalvn/Nordic-SDDM.git /usr/share/sddm/themes/nordic ;;
  *) echo "Invalid choice, defaulting to Layan" && THEME_NAME="layan" ;;
esac

sed -i "s/^Current=.*/Current=$THEME_NAME/" /etc/sddm.conf

# # Download a stunning SDDM theme (example: sweet theme)
# git clone https://github.com/sddm/sddm-theme-breeze.git /usr/share/sddm/themes/breeze
# sed -i 's/^Current=.*/Current=breeze/' /etc/sddm.conf

# # --- STEP 5: Setup Hyprland configs ---
# mkdir -p $HOME_DIR/.config/hypr
# cat <<EOF > $HOME_DIR/.config/hypr/hyprland.conf
# # Basic Hyprland config with multiple workspaces
# general {
#     mod=SUPER
# }

# monitor=1,1920x1080@60,0,0,1

# workspace=1,Terminal
# workspace=2,Web
# workspace=3,Code
# workspace=4,Media
# workspace=5,Docs

# bind=SUPER+Return,exec,alacritty
# bind=SUPER+d,exec,dmenu_run
# bind=SUPER+q,close
# EOF

# Set ownership
chown -R $USER:$USER $HOME_DIR/.config/hypr

# --- STEP 6: Programming Languages ---
pacman -S --noconfirm nodejs npm python python-pip php composer go gcc clang make

# --- STEP 7: Editors & IDE ---
pacman -S --noconfirm code code-server vim neovim

# --- STEP 8: Web Development Tools ---
pacman -S --noconfirm wp-cli
# Laravel Herd (requires PHP + Composer)
sudo -u $USER composer global require tightenco/laravel-herd

# --- STEP 9: Docker & Docker Compose ---
pacman -S --noconfirm docker docker-compose
systemctl enable docker
systemctl start docker
usermod -aG docker $USER

# --- STEP 10: Additional eye-catchy visual tweaks ---
# Alacritty config
mkdir -p $HOME_DIR/.config/alacritty
cat <<EOF > $HOME_DIR/.config/alacritty/alacritty.yml
colors:
  primary:
    background: '0x1e1e2e'
    foreground: '0xf5f5f5'
font:
  normal:
    family: "JetBrains Mono"
    size: 13.0
EOF

# Waybar theme
mkdir -p $HOME_DIR/.config/waybar
cat <<EOF > $HOME_DIR/.config/waybar/style.css
* {
    font-family: "JetBrains Mono";
    font-size: 12px;
    color: #f5f5f5;
}
#clock {
    color: #ff79c6;
}
EOF

chown -R $USER:$USER $HOME_DIR/.config/waybar
chown -R $USER:$USER $HOME_DIR/.config/alacritty

# --- STEP 11: Finish ---
echo "Setup complete! Reboot to start Hyprland with SDDM login."
