#!/bin/bash
set -e

# ===============================
# CONFIG
# ===============================
USER_NAME="abdullah"
HOME_DIR="/home/$USER_NAME"
SITES_DIR="$HOME_DIR/Sites"
TIMEZONE="Asia/Dhaka"
PHP_SOCK="/run/php-fpm/php-fpm.sock"

# ===============================
# PHP CONFIG
# ===============================
echo "Configuring PHP..."
sed -i 's/^;*cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' /etc/php/php.ini
sed -i 's/^;*memory_limit =.*/memory_limit = 512M/' /etc/php/php.ini
sed -i 's/^;*upload_max_filesize =.*/upload_max_filesize = 64M/' /etc/php/php.ini
sed -i 's/^;*post_max_size =.*/post_max_size = 64M/' /etc/php/php.ini
sed -i "s|^;*date.timezone =.*|date.timezone = $TIMEZONE|" /etc/php/php.ini

systemctl restart php-fpm

# ===============================
# NGINX STRUCTURE
# ===============================
echo "Setting up Nginx site system..."
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /etc/nginx/snippets

if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
  sed -i '/http {/a \    include sites-enabled/*;' /etc/nginx/nginx.conf
fi

# ===============================
# WORDPRESS SNIPPET
# ===============================
cat > /etc/nginx/snippets/wordpress.conf <<EOF
index index.php index.html;

location / {
    try_files \$uri \$uri/ /index.php?\$args;
}

location ~ \\.php\$ {
    include fastcgi_params;
    fastcgi_pass unix:$PHP_SOCK;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
}
EOF

nginx -t
systemctl reload nginx

# ===============================
# DNSMASQ (.test domains)
# ===============================
echo "Configuring dnsmasq..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/test.conf <<EOF
address=/.test/127.0.0.1
EOF

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/dns.conf <<EOF
[main]
dns=dnsmasq
EOF

systemctl enable --now dnsmasq
systemctl restart NetworkManager

# ===============================
# PROJECT ROOT
# ===============================
echo "Creating Sites directory..."
mkdir -p "$SITES_DIR"
chown -R $USER_NAME:$USER_NAME "$SITES_DIR"

# ===============================
# SAMPLE SITE (can delete later)
# ===============================
SITE_NAME="git"
SITE_ROOT="$SITES_DIR/$SITE_NAME"

mkdir -p "$SITE_ROOT"

cat > "$SITE_ROOT/index.php" <<EOF
<?php phpinfo();
EOF

cat > /etc/nginx/sites-available/$SITE_NAME.test <<EOF
server {
    listen 80;
    server_name $SITE_NAME.test;
    root $SITE_ROOT;

    include snippets/wordpress.conf;
}
EOF

ln -sf /etc/nginx/sites-available/$SITE_NAME.test \
       /etc/nginx/sites-enabled/$SITE_NAME.test

nginx -t
systemctl reload nginx

echo
echo "========================================="
echo " Herd-style environment is READY"
echo " Open: http://$SITE_NAME.test"
echo " Project root: $SITE_ROOT"
echo "========================================="
