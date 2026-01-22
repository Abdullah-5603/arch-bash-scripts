#!/bin/bash

#================================================================
# Arch Linux GNOME + Complete Dev Environment Setup Script
# Author: Auto-generated for Abu Abdullah
# Caution: It will remove all existing desktop environments. Use with your own caution.
#================================================================

set -e  # Exit on first error

#---------------------------------------------
# Function to print status
#---------------------------------------------
print_status() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
    echo
}

#---------------------------------------------
# 1. Remove all existing desktop environments
#---------------------------------------------
print_status "Removing existing desktop environments..."

# Remove known desktop environments and compositors safely
sudo pacman -Rns --needed $(pacman -Qq | grep -E "plasma|kde|xfce|lxde|lxqt|mate|cinnamon|i3|budgie|awesome|deepin|gnome|hyprland|sway") --noconfirm || true

# Remove Xorg packages safely
sudo pacman -Rns --needed xorg* --noconfirm || true

# Clean orphaned packages safely
orphans=$(pacman -Qdtq)
if [[ -n "$orphans" ]]; then
    sudo pacman -Rns --needed $orphans --noconfirm || true
fi

# Update system
sudo pacman -Syu --noconfirm

#---------------------------------------------
# 2. Install GNOME and essential utilities
#---------------------------------------------
print_status "Installing GNOME and utilities..."

sudo pacman -S --noconfirm \
    gnome gnome-extra gdm \
    networkmanager \
    firefox \
    git \
    vim \
    htop \
    wget \
    curl \
    unzip \
    base-devel \
    tmux \
    zsh \
    ranger

# Enable GDM and NetworkManager
sudo systemctl enable gdm
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

#---------------------------------------------
# 3. Install Node.js, npm, and yarn
#---------------------------------------------
print_status "Installing Node.js..."
sudo pacman -S --noconfirm nodejs npm yarn

#---------------------------------------------
# 4. Install PHP, Composer, and extensions
#---------------------------------------------
print_status "Installing PHP and Composer..."
sudo pacman -S --noconfirm php php-apache php-gd php-curl php-mbstring php-intl php-xml composer

#---------------------------------------------
# 5. Install Python and pip
#---------------------------------------------
print_status "Installing Python..."
sudo pacman -S --noconfirm python python-pip python-virtualenv

#---------------------------------------------
# 6. Install C/C++ development tools
#---------------------------------------------
print_status "Installing C/C++ development tools..."
sudo pacman -S --noconfirm gcc gdb make cmake clang

#---------------------------------------------
# 7. Install Docker
#---------------------------------------------
print_status "Installing Docker..."
sudo pacman -S --noconfirm docker docker-compose
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

#---------------------------------------------
# 8. Install WordPress and WP-CLI
#---------------------------------------------
print_status "Installing WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

#---------------------------------------------
# 9. Install Laravel and Laravel Herd
#---------------------------------------------
print_status "Installing Laravel..."
composer global require laravel/installer
export PATH="$HOME/.config/composer/vendor/bin:$PATH"

print_status "Installing Laravel Herd..."
# Herd official instructions
curl -s https://laravel.build/laravel-herd.sh | bash

#---------------------------------------------
# 10. Install Code Editors
#---------------------------------------------
print_status "Installing code editors..."
# VS Code
sudo pacman -S --noconfirm code
# Neovim
sudo pacman -S --noconfirm neovim

#---------------------------------------------
# 11. Final Update
#---------------------------------------------
print_status "Final system update and cleanup..."
sudo pacman -Syu --noconfirm
sudo pacman -Sc --noconfirm

print_status "Setup Complete! Please reboot your system."

