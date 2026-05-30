#!/bin/bash
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
WHITE='\e[37m'
NC='\e[0m'

new_php(){
    echo -e "${GREEN}"
    echo "===================================="
    echo "1) 8.1"
    echo "2) 8.2"
    echo "3) 8.3"
    echo "4) 8.4"
    echo "5) 8.5"
    echo "6) 8.6"
    echo "7) 7.4"
    echo "===================================="
    echo -e "${NC}"
    read -p "Select option:[1-3] " opt

    case $opt in
        1) PHP_VERSION='8.1' ;;
        2) PHP_VERSION='8.2' ;;
        3) PHP_VERSION='8.3' ;;
        4) PHP_VERSION='8.4' ;;
        5) PHP_VERSION='8.5' ;;
        6) PHP_VERSION='8.6' ;;
        7) PHP_VERSION='7.4' ;;
        *)
            echo "Неверный выбор"
            return 1
        ;;
    esac
}


install_php(){

    if systemctl list-units --full -all | grep -Fq "php${PHP_VERSION}-fpm.service"; then
        echo "PHP ${PHP_VERSION} уже установлен"
    else
        sudo apt install software-properties-common ca-certificates lsb-release apt-transport-https -y
        sudo add-apt-repository ppa:ondrej/php -y
        sudo apt update -y

        apt install -y \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-redis \
        php${PHP_VERSION}-opcache

        systemctl enable php${PHP_VERSION}-fpm
        systemctl start php${PHP_VERSION}-fpm

        echo "PHP ${PHP_VERSION} установлен"
    fi
  
}
add_php(){
    new_php
    install_php
}
install(){
if [ -d "/usr/share/phpmyadmin" ]; then
    echo "Настройка сервера уже производилась выберите другой пункт меню"
    return 1
fi
set -e

new_php

read -p "Введите логин для Basic Auth phpMyAdmin: " HTUSER
read -sp "Введите пароль для Basic Auth phpMyAdmin: " HTPASS
echo
read -sp "Введите пароль для MariaDB root: " MYSQL_ROOT_PASSWORD
echo

echo "======================================"
echo "Установка production LEMP"
echo "PHP Version: ${PHP_VERSION}"
echo "======================================"
apt update && apt upgrade -y

apt install -y \
software-properties-common \
ca-certificates \
lsb-release \
apt-transport-https \
curl \
gnupg2 \
ufw \
htop \
unzip \
git \
composer \
certbot python3-certbot-nginx

add-apt-repository ppa:ondrej/php -y
apt update -y

# ---------------------------------
# NGINX
# ---------------------------------
apt install -y nginx
systemctl enable nginx
systemctl start nginx

# ---------------------------------
# MARIADB
# ---------------------------------
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb



install_php

# ---------------------------------
# PHPMYADMIN
# ---------------------------------
DEBIAN_FRONTEND=noninteractive apt install -y phpmyadmin
# ---------------------------------
# BASIC AUTH
# ---------------------------------
apt install -y apache2-utils

if [ ! -f /etc/nginx/.htpasswd ]; then
    htpasswd -bc /etc/nginx/.htpasswd ${HTUSER} ${HTPASS}
fi

# ---------------------------------
# MARIADB ROOT PASSWORD
# ---------------------------------
mysql -e "
ALTER USER 'root'@'localhost'
IDENTIFIED VIA mysql_native_password
USING PASSWORD('${MYSQL_ROOT_PASSWORD}');
FLUSH PRIVILEGES;
"

# ==========================================
# PHPMYADMIN CONFIG
# ==========================================

echo "Configuring phpMyAdmin..."

cat > /etc/nginx/sites-available/default <<EOF
   server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /var/www/html;
    index index.php index.html;

    client_max_body_size 64M;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # -----------------------------
    # Main site
    # -----------------------------
    location / {
        try_files \$uri \$uri/ =404;
    }

    # -----------------------------
    # PHP
    # -----------------------------
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }

    # -----------------------------
    # phpMyAdmin
    # -----------------------------
    location /phpmyadmin {
        auth_basic "Restricted Area";
        auth_basic_user_file /etc/nginx/.htpasswd;

        root /usr/share;
        index index.php;

        location ~ ^/phpmyadmin/(.+\.php)\$ {
            root /usr/share;

            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        }
    }

    # -----------------------------
    # Security
    # -----------------------------
    location ~ /\. {
        deny all;
    }

    location ~* \.(env|log|ini)\$ {
        deny all;
    }
}
EOF

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

systemctl restart nginx
systemctl restart mariadb
systemctl restart php${PHP_VERSION}-fpm


echo "<?php phpinfo(); ?>" > /var/www/html/info.php

# ---------------------------------
# OUTPUT
# ---------------------------------
IP=$(hostname -I | awk '{print $1}')

echo "======================================"
echo "LEMP STACK INSTALLED"
echo "======================================"
echo "Main Site:"
echo "http://${IP}"
echo ""
echo "phpMyAdmin:"
echo "http://${IP}/phpmyadmin"
echo ""
echo "Basic Auth:"
echo "login: ${HTUSER}"
echo "password: ${HTPASS}"
echo ""
echo "MariaDB root password:"
echo "${MYSQL_ROOT_PASSWORD}"
echo ""
echo "PHP Info:"
echo "http://${IP}/info.php"
echo "======================================"


}



create_site(){

# ---------------------------------
# CHECK INITIAL SETUP
# ---------------------------------
if [ ! -d "/usr/share/phpmyadmin" ]; then
  echo "Еще не выполнена первноначальная настройка сервера выберите 1 пункт"
  return 1
fi

# ---------------------------------
# DOMAIN INPUT
# ---------------------------------
read -p "Введите домен: " DOMAIN

# ❗ защита от повторного создания
if [ -d "/var/www/${DOMAIN}" ] || [ -f "/etc/nginx/sites-available/${DOMAIN}" ]; then
    echo "❌ Сайт уже существует"
    return 1
fi

# ❗ базовая проверка домена
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "❌ Некорректный домен"
    return 1
fi

# ---------------------------------
# SSL CHOICE
# ---------------------------------
echo "Выберите тип HTTPS:"
echo "1) HTTP"
echo "2) Let's Encrypt"
echo "3) Self-signed"
read -p "Choice: " SSL_TYPE

# ---------------------------------
# PHP SELECTION
# ---------------------------------
new_php
install_php

# ---------------------------------
# CREATE PROJECT DIR
# ---------------------------------
mkdir -p /var/www/${DOMAIN}/public
chown -R $SUDO_USER:www-data /var/www/${DOMAIN}

# ---------------------------------
# NGINX CONFIG BASE
# ---------------------------------
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"

# ---------------------------------
# HTTP ONLY
# ---------------------------------
if [ "$SSL_TYPE" = "1" ]; then

cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root /var/www/${DOMAIN}/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

fi

# ---------------------------------
# SELF SIGNED SSL
# ---------------------------------
if [ "$SSL_TYPE" = "3" ]; then

mkdir -p /etc/ssl/${DOMAIN}

openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/ssl/${DOMAIN}/self.key \
    -out /etc/ssl/${DOMAIN}/self.crt \
    -subj "/CN=${DOMAIN}"

cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/ssl/${DOMAIN}/self.crt;
    ssl_certificate_key /etc/ssl/${DOMAIN}/self.key;

    root /var/www/${DOMAIN}/public;
    index index.php;

    client_max_body_size 64M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

fi

# ---------------------------------
# LETSENCRYPT SSL
# ---------------------------------
if [ "$SSL_TYPE" = "2" ]; then

cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root /var/www/${DOMAIN}/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }

    location ~ /\. {
        deny all;
    }
}
EOF
# ---------------------------------
# ENABLE SITE
# ---------------------------------
ln -sf $NGINX_CONF /etc/nginx/sites-enabled/${DOMAIN}
# ❗ проверка DNS перед certbot
echo "⏳ Проверка DNS..."
ping -c1 ${DOMAIN} >/dev/null 2>&1 || echo "⚠ DNS может быть не настроен"

systemctl reload nginx

fi



# ---------------------------------
# FIREWALL (ONLY ONCE SAFE CHECK)
# ---------------------------------
if ! ufw status | grep -q "Status: active"; then
    ufw allow OpenSSH
    ufw allow 'Nginx Full'
    ufw --force enable
fi

# ---------------------------------
# SERVICES
# ---------------------------------
systemctl restart nginx
systemctl restart php${PHP_VERSION}-fpm

if [ "$SSL_TYPE" = "2" ]; then
certbot --nginx -d ${DOMAIN} \
    --non-interactive \
    --agree-tos \
    -m admin@${DOMAIN} || {
        echo "❌ Certbot не смог выпустить сертификат"
        return 1
    }
fi
# ---------------------------------
# TEST FILE
# ---------------------------------
echo "<?php phpinfo(); ?>" > /var/www/${DOMAIN}/public/index.php

# ---------------------------------
# OUTPUT
# ---------------------------------
IP=$(hostname -I | awk '{print $1}')

echo "======================================"
echo "SITE CREATED SUCCESSFULLY"
echo "======================================"
echo "Domain: http://${DOMAIN}"

if [ "$SSL_TYPE" = "2" ]; then
echo "HTTPS: https://${DOMAIN}"
fi

if [ "$SSL_TYPE" = "3" ]; then
echo "HTTPS (self-signed): https://${DOMAIN}"
fi

echo "Server IP: ${IP}"
echo "======================================"

}
delete_site() {

    echo "=========================="
    echo "Список сайтов:"
    echo "=========================="

    sites=()

    for file in /etc/nginx/sites-available/*; do
        name=$(basename "$file")

        if [ "$name" != "default" ]; then
            sites+=("$file")
        fi
    done

    for i in "${!sites[@]}"; do
        echo "$((i+1))) $(basename "${sites[$i]}")"
    done



    echo "=========================="

    read -p "Выберите сайт для удаления: " choice

    DOMAIN=$(basename "${sites[$((choice-1))]}")

    if [ -z "$DOMAIN" ]; then
        echo "Неверный выбор"
        return 1
    fi

    rm -f /etc/nginx/sites-available/$DOMAIN
    rm -f /etc/nginx/sites-enabled/$DOMAIN
    rm -rf /var/www/$DOMAIN

    systemctl reload nginx

    echo "Сайт $DOMAIN удален"
}


list_sites() {
    ls /etc/nginx/sites-available
}

show_php(){
     for sock in /run/php/php*-fpm.sock; do
        version=$(basename "$sock" | sed 's/php\(.*\)-fpm.sock/\1/')
        echo "PHP $version"
    done
}

install_ftp(){

echo "===================================="
echo "FTP INSTALL (vsftpd)"
echo "===================================="

apt update -y
apt install -y vsftpd ftp

# ---------------------------------
# BACKUP CONFIG
# ---------------------------------
cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

# ---------------------------------
# BASIC CONFIG
# ---------------------------------
cat > /etc/vsftpd.conf <<EOF
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES

local_umask=022

dirmessage_enable=YES
use_localtime=YES

xferlog_enable=YES
connect_from_port_20=YES

chroot_local_user=YES
allow_writeable_chroot=YES

pam_service_name=vsftpd

# Passive mode (важно для FileZilla)
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
EOF

systemctl restart vsftpd
systemctl enable vsftpd

# ---------------------------------
# USER CREATION
# ---------------------------------
read -p "Введите FTP пользователя: " FTP_USER
read -sp "Введите пароль FTP: " FTP_PASS
echo

# создаём пользователя без shell доступа
# useradd -m -d /var/www -s /usr/sbin/nologin $FTP_USER
useradd -m -d /var/www -s /bin/bash $FTP_USER
echo "$FTP_USER:$FTP_PASS" | chpasswd

# даём права на сайты
usermod -aG www-data $FTP_USER
chown -R $FTP_USER:www-data /var/www

# ---------------------------------
# FIREWALL
# ---------------------------------
ufw allow 21/tcp
ufw allow 40000:40100/tcp

systemctl restart vsftpd

echo "===================================="
echo "FTP READY"
echo "===================================="
echo "Host: $(hostname -I | awk '{print $1}')"
echo "User: $FTP_USER"
echo "Password: $FTP_PASS"
echo "Port: 21"
echo "Passive ports: 40000-40100"
echo "Root: /var/www"
echo "===================================="

}

while true; do
    echo -e "${GREEN}"
    echo "===================================="
    echo " LEMP НАСТРОЙКА ВЕБ СЕРВЕРА"
    echo "===================================="
    echo "1) ПЕРВОНАЧАЛЬНАЯ НАСТРОЙКА PHP NGINX PHPMYADMIN"
    echo "2) ДОБАВИТЬ САЙТ"
    echo "3) ПОКАЗАТЬ САЙТЫ"
    echo "4) УДАЛИТЬ САЙТ"
    echo "5) ПЕРЕЗАГРУЗИТЬ NGINX"
    echo "6) ПОКАЗАТЬ УСТАНОВЛЕННЫЕ ВЕРСИИ PHP"
    echo "7) УСТАНОВИТЬ PHP"
    echo "8) УСТАНОВИТЬ FTP"
    echo "0) Выход"
    echo "===================================="
    echo -e "${NC}"
    read -p "Select option: " opt

    case $opt in
        1) install ;;
        2) create_site ;;
        3) list_sites ;;
        4) delete_site ;;
        5) restart_services ;;
        6) show_php ;;
        7) add_php ;;
        8) install_ftp ;;
        0) exit 0 ;;
    esac

done
