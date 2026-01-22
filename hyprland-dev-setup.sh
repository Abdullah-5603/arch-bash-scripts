#!/bin/bash
# --------------------------------------------------
# COMPLETE Hyprland Polyglot Dev Setup
# WordPress • Laravel • PHP • JS • C/C++ • Python
# OS: Arch Linux
# --------------------------------------------------

set -e

echo "=============================="
echo "0. Base directories..."
mkdir -p \
  ~/Pictures \
  ~/Projects \
  ~/.config/hypr \
  ~/.config/hyprpaper \
  ~/.config/fish

echo "=============================="
echo "1. Hyprland configuration..."
cat > ~/.config/hypr/hyprland.conf << 'EOF'
monitor=*,preferred,auto
terminal=foot

exec-once=hyprpaper &
exec-once=wofi --show drun &
exec-once=mako &
exec-once=discord &

workspace=1:Code
workspace=2:Browser
workspace=3:Database
workspace=4:Chat
workspace=5:Media

bind=SUPER+ENTER,exec,foot
bind=SUPER+SHIFT+ENTER,exec,foot -e bash
bind=SUPER+SHIFT+V,exec,code
bind=SUPER+B,exec,firefox
bind=SUPER+SHIFT+M,exec,phpstorm
bind=SUPER+SHIFT+Q,close
bind=SUPER+SHIFT+R,restart

bind=SUPER+H,moveleft
bind=SUPER+L,moveright
bind=SUPER+J,movedown
bind=SUPER+K,moveup

bind=SUPER+1,workspace,1
bind=SUPER+2,workspace,2
bind=SUPER+3,workspace,3
bind=SUPER+4,workspace,4
bind=SUPER+5,workspace,5

bind=SUPER+SHIFT+1,movetoworkspace,1
bind=SUPER+SHIFT+2,movetoworkspace,2
bind=SUPER+SHIFT+3,movetoworkspace,3
bind=SUPER+SHIFT+4,movetoworkspace,4
bind=SUPER+SHIFT+5,movetoworkspace,5

bind=PRINT,exec,grim -g "$(slurp)" ~/Pictures/screenshot_$(date +%F_%T).png
EOF

echo "=============================="
echo "2. Core system + dev packages..."
sudo pacman -Syu --needed --noconfirm \
  base-devel git curl wget unzip \
  foot wofi mako grim slurp hyprpaper \
  firefox code discord \
  docker docker-compose \
  fish zsh starship \
  gcc clang make cmake gdb lldb \
  python python-pip python-virtualenv pipx \
  mariadb

echo "=============================="
echo "3. PHP + extensions (WordPress / Laravel)..."
sudo pacman -S --needed --noconfirm \
  php php-fpm composer \
  php-gd php-intl php-pgsql php-sqlite \
  php-mysql php-curl php-zip php-mbstring

sudo systemctl enable --now php-fpm

echo "=============================="
echo "4. Node.js LTS + npm..."
sudo pacman -S --needed --noconfirm nodejs-lts-iron npm

echo "=============================="
echo "5. pnpm + yarn (Corepack)..."
sudo corepack enable
corepack prepare pnpm@latest --activate
corepack prepare yarn@stable --activate

echo "=============================="
echo "6. Bun runtime..."
curl -fsSL https://bun.sh/install | bash
echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc

echo "=============================="
echo "7. Docker enable..."
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

echo "=============================="
echo "8. MongoDB (Docker)..."
docker volume create mongodb_data || true
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  -v mongodb_data:/data/db \
  --restart unless-stopped \
  mongo:7 || true

echo "=============================="
echo "9. yay (AUR helper)..."
if ! command -v yay &>/dev/null; then
  cd /tmp
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
fi

echo "=============================="
echo "10. MongoDB Compass..."
yay -S --noconfirm mongodb-compass

echo "=============================="
echo "11. MariaDB initialization..."
sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
sudo systemctl enable --now mariadb

echo "=============================="
echo "12. Python tooling..."
pipx ensurepath
pipx install black || true
pipx install flake8 || true
pipx install pytest || true

echo "=============================="
echo "13. WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

echo "=============================="
echo "14. Laravel Sail..."
composer global require laravel/sail
echo 'export PATH="$HOME/.config/composer/vendor/bin:$PATH"' >> ~/.bashrc

echo "=============================="
echo "15. Shells + Starship..."
chsh -s /bin/zsh
chsh -s /bin/fish

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
echo 'eval "$(starship init zsh)"' >> ~/.zshrc
echo 'starship init fish | source' >> ~/.config/fish/config.fish

echo "=============================="
echo "16. Verification..."
php -v
composer --version
node -v
npm -v
pnpm -v
yarn -v
bun -v
gcc --version
python --version
docker --version
wp --info

echo "=============================="
echo "✅ COMPLETE DEV ENVIRONMENT READY"
echo ""
echo "Stacks installed:"
echo "• PHP: php | php-fpm | composer | Laravel | WordPress"
echo "• JS: node | npm | pnpm | yarn | bun"
echo "• DB: MariaDB | MongoDB | Compass"
echo "• C/C++: gcc | clang | cmake | gdb"
echo "• Python: python | pip | venv | pipx"
echo "• Tools: Docker | VS Code | Hyprland"
echo ""
echo "⚠️ REBOOT REQUIRED (docker group + shells)"