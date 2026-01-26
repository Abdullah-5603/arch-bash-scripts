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
DEFAULT_SITE="example"

# ===============================
# PHP CONFIG
# ===============================
sed -i 's/^;*cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' /etc/php/php.ini
sed -i 's/^;*memory_limit =.*/memory_limit = 512M/' /etc/php/php.ini
sed -i 's/^;*upload_max_filesize =.*/upload_max_filesize = 64M/' /etc/php/php.ini
sed -i 's/^;*post_max_size =.*/post_max_size = 64M/' /etc/php/php.ini
sed -i "s|^;*date.timezone =.*|date.timezone = $TIMEZONE|" /etc/php/php.ini

systemctl enable --now php-fpm

# ===============================
# NGINX CORE CONFIG
# ===============================
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets

if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
  sed -i '/http {/a \    include sites-enabled/*;' /etc/nginx/nginx.conf
fi

if ! grep -q "types_hash_max_size" /etc/nginx/nginx.conf; then
  sed -i '/http {/a \    types_hash_max_size 4096;\n    types_hash_bucket_size 128;' /etc/nginx/nginx.conf
fi

# ===============================
# WORDPRESS FASTCGI SNIPPET
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

systemctl enable --now nginx
nginx -t
systemctl reload nginx

# ===============================
# DNSMASQ (.test DOMAINS)
# ===============================
mkdir -p /etc/dnsmasq.d /etc/NetworkManager/conf.d

cat > /etc/dnsmasq.d/test.conf <<EOF
address=/.test/127.0.0.1
EOF

cat > /etc/NetworkManager/conf.d/dns.conf <<EOF
[main]
dns=dnsmasq
EOF

systemctl enable --now dnsmasq
systemctl restart NetworkManager

# ===============================
# PROJECT ROOT
# ===============================
mkdir -p "$SITES_DIR"
chown -R $USER_NAME:$USER_NAME "$SITES_DIR"

# ===============================
# DEFAULT SITE
# ===============================
SITE_ROOT="$SITES_DIR/$DEFAULT_SITE"
mkdir -p "$SITE_ROOT"

cat > "$SITE_ROOT/index.php" <<EOF
<?php phpinfo();
EOF

cat > /etc/nginx/sites-available/$DEFAULT_SITE.test <<EOF
server {
    listen 80;
    server_name $DEFAULT_SITE.test;
    root $SITE_ROOT;

    include snippets/wordpress.conf;
}
EOF

ln -sf /etc/nginx/sites-available/$DEFAULT_SITE.test \
       /etc/nginx/sites-enabled/$DEFAULT_SITE.test

nginx -t
systemctl reload nginx
