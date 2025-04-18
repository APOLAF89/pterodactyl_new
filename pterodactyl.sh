if (( $EUID != 0 )); then
    echo ""
    echo "Please run as root"
    echo ""
    exit
fi

clear

GitHub_Account="https://raw.githubusercontent.com/TobiDev01/Pterodactyl/main/src"

VPS_IPv4=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
blowfish_secret=""
FQDN=""
FQDN_Node=""
MYSQL_PASSWORD=""
SSL_AVAILABLE=false
Node_SSL_AVAILABLE=false
Pterodactyl_conf="pterodactyl-no_ssl.conf"
email=""
user_username=""
user_password=""
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

installPhpMyAdmin() {
    cd

    mkdir pma
    cd pma

    wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
    tar xvzf phpMyAdmin-latest-all-languages.tar.gz

    mv phpMyAdmin-*-all-languages/* $1/pma

    rm -rf phpM*

    mkdir $1/pma/tmp
    
    chmod -R 777 $1/pma/tmp

    rm config.sample.inc.php

    curl -o $1/pma/config.inc.php $GitHub_Account/config.inc.php
    sed -i -e "s@<blowfish_secret>@${blowfish_secret}@g" $1/pma/config.inc.php

    rm -rf $1/pma/setup

    cd
}

installPanel() {
    cd

    rm /etc/apt/sources.list.d/mariadb.list
    rm /etc/apt/sources.list.d/mariadb.list.old*

    #rm /etc/mysql/my.cnf
    #rm /etc/mysql/mariadb.conf.d/50-server.cnf

    rm /etc/systemd/system/pteroq.service

    rm /etc/nginx/sites-enabled/default
    rm /etc/nginx/sites-enabled/pterodactyl.conf

    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

    if [ -f /etc/lsb-release ]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    elif [ -f /etc/debian_version ]; then
        curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
    fi

    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    
    apt update

    apt -y install php8.3 php8.3-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    rm /var/www/pterodactyl/panel.tar.gz

    mariadb -u root -e "DROP USER 'pterodactyl'@'127.0.0.1';"
    mariadb -u root -e "DROP DATABASE panel;"
    mariadb -u root -e "DROP USER 'pterodactyluser'@'127.0.0.1';"
    mariadb -u root -e "DROP USER 'pterodactyluser'@'%';"

    mariadb -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mariadb -u root -e "CREATE DATABASE panel;"
    mariadb -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"

    mariadb -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mariadb -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;"
    
    mariadb -u root -e "flush privileges;"

    #curl -o /etc/mysql/my.cnf $GitHub_Account/my.cnf
    #curl -o /etc/mysql/mariadb.conf.d/50-server.cnf $GitHub_Account/50-server.cnf

    sed -i '$a\\n[mysqld]\nbind-address=0.0.0.0' "/etc/mysql/my.cnf"
    sed -i "s@127.0.0.1@0.0.0.0@g" /etc/mysql/mariadb.conf.d/50-server.cnf

    systemctl restart mysql
    systemctl restart mariadb

    mv .env.example .env
    
    COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
        
    app_url="http://$FQDN"
    if [ "$SSL_AVAILABLE" == true ]
        then
        app_url="https://$FQDN"
        Pterodactyl_conf="pterodactyl.conf"
        apt update
        apt install -y certbot
        apt install -y python3-certbot-nginx
        certbot certonly --nginx --redirect --no-eff-email --register-unsafely-without-email -d "$FQDN"
    fi

    php artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="America/New_York" \
    --cache="file" \
    --session="file" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true \
    --telemetry=false

    php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pterodactyl" \
    --password="${MYSQL_PASSWORD}"

    php artisan migrate --seed --force

    php artisan p:user:make \
    --email="$email" \
    --username="$user_username" \
    --name-first="$user_username" \
    --name-last="$user_username" \
    --password="$user_password" \
    --admin=1

    echo "TRUSTED_PROXIES=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22" >> .env

    chown -R www-data:www-data /var/www/pterodactyl/*

    crontab -l | {
        cat
        echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    } | crontab -

    curl -o /etc/systemd/system/pteroq.service $GitHub_Account/pteroq.service

    systemctl enable --now redis-server
    systemctl enable --now pteroq.service
    
    curl -o /etc/nginx/sites-enabled/pterodactyl.conf $GitHub_Account/$Pterodactyl_conf
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf

    systemctl restart nginx

    cd
}

installWings() {
    cd

    rm /etc/apt/sources.list.d/mariadb.list
    rm /etc/apt/sources.list.d/mariadb.list.old*

    rm /etc/default/grub

    #rm /etc/mysql/my.cnf
    #rm /etc/mysql/mariadb.conf.d/50-server.cnf

    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    curl -o /etc/default/grub $GitHub_Account/grub
    update-grub
    
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    
    apt update

    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

    mariadb -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mariadb -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;"
    
    mariadb -u root -e "flush privileges;"

    #curl -o /etc/mysql/my.cnf $GitHub_Account/my.cnf
    #curl -o /etc/mysql/mariadb.conf.d/50-server.cnf $GitHub_Account/50-server.cnf

    sed -i '$a\\n[mysqld]\nbind-address=0.0.0.0' "/etc/mysql/my.cnf"
    sed -i "s@127.0.0.1@0.0.0.0@g" /etc/mysql/mariadb.conf.d/50-server.cnf
    
    systemctl restart mysql
    systemctl restart mariadb

    app_url="http://$FQDN"
    if [ "$SSL_AVAILABLE" == true ]
        then
        apt update
        apt install -y certbot
        apt install -y python3-certbot-nginx
        certbot certonly --nginx --redirect --no-eff-email --register-unsafely-without-email -d "$FQDN"
    fi
    
    rm /etc/systemd/system/wings.service
    curl -o /etc/systemd/system/wings.service $GitHub_Account/wings.service

    cd /etc/pterodactyl
    echo > config.yml
    
    cd
}

updatePanel() {
    cd /var/www/pterodactyl
    php artisan down

    curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv

    rm panel.tar.gz

    chmod -R 755 storage/* bootstrap/cache

    composer install --no-dev --optimize-autoloader

    php artisan optimize:clear
    php artisan migrate --seed --force

    chown -R www-data:www-data /var/www/pterodactyl/*

    php artisan queue:restart

    php artisan up

    cd
}

installPanelAndwings() {
    cd
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    
    if [ -f /etc/lsb-release ]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    elif [ -f /etc/debian_version ]; then
        curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
    fi

    add-apt-repository ppa:redislabs/redis -y
    rm /etc/apt/sources.list.d/mariadb.list
    rm /etc/apt/sources.list.d/mariadb.list.old*
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
    apt update
    
    apt -y install php8.3 php8.3-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    rm /var/www/pterodactyl/panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    mariadb -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mariadb -u root -e "CREATE DATABASE panel;"
    mariadb -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    
    mariadb -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mariadb -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;"
    mariadb -u root -e "flush privileges;"

    #rm /etc/mysql/my.cnf
    #rm /etc/mysql/mariadb.conf.d/50-server.cnf

    #curl -o /etc/mysql/my.cnf $GitHub_Account/my.cnf
    #curl -o /etc/mysql/mariadb.conf.d/50-server.cnf $GitHub_Account/50-server.cnf

    sed -i '$a\\n[mysqld]\nbind-address=0.0.0.0' "/etc/mysql/my.cnf"
    sed -i "s@127.0.0.1@0.0.0.0@g" /etc/mysql/mariadb.conf.d/50-server.cnf

    systemctl restart mysql
    systemctl restart mariadb

    mv .env.example .env
    
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
        
    app_url="http://$FQDN"
    if [ "$SSL_AVAILABLE" == true ]
        then
        app_url="https://$FQDN"
        Pterodactyl_conf="pterodactyl.conf"
        apt update
        apt install -y certbot
        apt install -y python3-certbot-nginx
        certbot certonly --nginx --redirect --no-eff-email --register-unsafely-without-email -d "$FQDN"
    fi

    if [ "$Node_SSL_AVAILABLE" == true ]
        then
        apt update
        apt install -y certbot
        apt install -y python3-certbot-nginx
        certbot certonly --nginx --redirect --no-eff-email --register-unsafely-without-email -d "$FQDN_Node"
    fi

    php artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="America/New_York" \
    --cache="file" \
    --session="file" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true \
    --telemetry=false

    php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pterodactyl" \
    --password="${MYSQL_PASSWORD}"

    php artisan migrate --seed --force

    php artisan p:user:make \
    --email="$email" \
    --username="$user_username" \
    --name-first="$user_username" \
    --name-last="$user_username" \
    --password="$user_password" \
    --admin=1

    echo "TRUSTED_PROXIES=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22" >> .env

    chown -R www-data:www-data /var/www/pterodactyl/*

    crontab -l | {
        cat
        echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    } | crontab -

    rm /etc/systemd/system/pteroq.service
    curl -o /etc/systemd/system/pteroq.service $GitHub_Account/pteroq.service

    systemctl enable --now redis-server
    systemctl enable --now pteroq.service

    rm /etc/nginx/sites-enabled/default
    rm /etc/nginx/sites-enabled/pterodactyl.conf

    curl -o /etc/nginx/sites-enabled/pterodactyl.conf $GitHub_Account/$Pterodactyl_conf
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf

    systemctl restart nginx

    curl -sSL https://get.docker.com/ | CHANNEL=stable bash

    systemctl enable --now docker

    rm /etc/default/grub
    curl -o /etc/default/grub $GitHub_Account/grub
    update-grub
    
    mkdir -p /etc/pterodactyl
    
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    
    rm /etc/systemd/system/wings.service
    curl -o /etc/systemd/system/wings.service $GitHub_Account/wings.service
    
    cd /etc/pterodactyl
    echo > config.yml

    cd
}

print_error() {
    COLOR_RED='\033[0;31m'
    COLOR_NC='\033[0m'

    echo ""
    echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
    echo ""
}

required_input() {
    local __resultvar=$1
    local result=''

    while [ -z "$result" ]; do
        echo -n "* ${2}"
        read -r result

        if [ -z "${3}" ]; then
        [ -z "$result" ] && result="${4}"
        else
        [ -z "$result" ] && print_error "${3}"
        fi
    done

    eval "$__resultvar="'$result'""
}

valid_email() {
    [[ $1 =~ ${email_regex} ]]
}

checkFQDN() {
    local input=$1
    local -n boolean_var=$2

    local ipv4_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

    local fqdn_regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$"

    if [[ $input =~ $ipv4_regex ]]; then
        boolean_var=false
        return 0
    elif [[ $input =~ $fqdn_regex ]]; then
        boolean_var=true
        return 0
    else
        boolean_var=false
        return 1
    fi
}

password_input() {
    local __resultvar=$1
    local result=''
    local default="$4"

    while [ -z "$result" ]; do
        echo -n "* ${2}"

        while IFS= read -r -s -n1 char; do
        [[ -z $char ]] && {
            printf '\n'
            break
        }
        if [[ $char == $'\x7f' ]]; then
            if [ -n "$result" ]; then
            [[ -n $result ]] && result=${result%?}
            printf '\b \b'
            fi
        else
            result+=$char
            printf '*'
        fi
        done
        [ -z "$result" ] && [ -n "$default" ] && result="$default"
        [ -z "$result" ] && print_error "${3}"
    done

    eval "$__resultvar="'$result'""
}

email_input() {
    local __resultvar=$1
    local result=''

    while ! valid_email "$result"; do
        echo -n "* ${2}"
        read -r result

        valid_email "$result" || print_error "${3}"
    done

    eval "$__resultvar="'$result'""
}

summary() {
    clear
    echo ""
    echo -e "\033[1;94mDatabase credentials:\033[0m"
    echo -e "\033[1;92m*\033[0m Database name: panel"
    echo -e "\033[1;92m*\033[0m IPv4: 127.0.0.1"
    echo -e "\033[1;92m*\033[0m Port: 3306"
    echo -e "\033[1;92m*\033[0m User: pterodactyl, pterodactyluser"
    echo -e "\033[1;92m*\033[0m Password: $MYSQL_PASSWORD"
    echo ""
    echo -e "\033[1;94mPanel credentials:\033[0m"
    echo -e "\033[1;92m*\033[0m Email: $email"
    echo -e "\033[1;92m*\033[0m Username: $user_username"
    echo -e "\033[1;92m*\033[0m Password: $user_password"
    echo ""
    echo -e "\033[1;96mDomain/IPv4:\033[0m $FQDN"
    echo ""
}

echo ""
echo "[0] Exit"
echo "[1] Install panel"
echo "[2] Install wings"
echo "[3] Install panel & wings"
echo "[4] Update panel"
echo "[5] uninstall panel & wings"
echo "[6] Install theme"
echo "[7] Install phpMyAdmin"
echo "[8] Uninstall phpMyAdmin"
echo ""
read -p "Please enter a number: " choice
echo ""

if [ $choice == "0" ]
then
    echo -e "\033[0;96mCya\033[0m"
    echo ""
    exit
fi

if [ $choice == "1" ]
    then
    password_input MYSQL_PASSWORD "Provide password for database: " "MySQL password cannot be empty"
    email_input email "Provide email address for panel: " "Email cannot be empty or invalid"
    required_input user_username "Provide username for panel: " "Username cannot be empty"
    password_input user_password "Provide password for panel: " "Password cannot be empty"

    while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of this panel (panel.example.com | 0.0.0.0): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
    done

    checkFQDN "$FQDN" SSL_AVAILABLE
    installPanel
    summary
    exit
fi

if [ $choice == "2" ]
    then
    password_input MYSQL_PASSWORD "Provide password for database: " "MySQL password cannot be empty"

    while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of the node (node.example.com | 0.0.0.0): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
    done

    checkFQDN "$FQDN" SSL_AVAILABLE
    installWings
    clear
    echo ""
    echo -e "\033[0;92mWings installed successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "3" ]
    then
    password_input MYSQL_PASSWORD "Provide password for database: " "MySQL password cannot be empty"
    email_input email "Provide email address for panel: " "Email cannot be empty or invalid"
    required_input user_username "Provide username for panel: " "Username cannot be empty"
    password_input user_password "Provide password for panel: " "Password cannot be empty"

    while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of this panel (panel.example.com | 0.0.0.0): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
    done

    while [ -z "$FQDN_Node" ]; do
    echo -n "* Set the FQDN of the node (node.example.com | 0.0.0.0): "
    read -r FQDN_Node
    [ -z "$FQDN_Node" ] && print_error "FQDN cannot be empty"
    done

    checkFQDN "$FQDN" SSL_AVAILABLE
    checkFQDN "$FQDN_Node" Node_SSL_AVAILABLE
    installPanelAndwings
    summary
    exit
fi

if [ $choice == "4" ]
then
    updatePanel
    clear
    echo ""
    echo -e "\033[0;92mPanel updated successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "5" ]
then
    rm -rf /var/www/pterodactyl
    rm /etc/systemd/system/pteroq.service
    rm /etc/nginx/sites-available/pterodactyl.conf
    rm /etc/nginx/sites-enabled/pterodactyl.conf
    ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    systemctl stop wings
    rm -rf /var/lib/pterodactyl
    rm -rf /etc/pterodactyl
    rm /usr/local/bin/wings
    rm /etc/systemd/system/wings.service
    rm /etc/apt/sources.list.d/mariadb.list
    rm /etc/apt/sources.list.d/mariadb.list.old*
    mariadb -u root -e "DROP USER 'pterodactyl'@'127.0.0.1';"
    mariadb -u root -e "DROP DATABASE panel;"
    mariadb -u root -e "DROP USER 'pterodactyluser'@'127.0.0.1';"
    mariadb -u root -e "DROP USER 'pterodactyluser'@'%';"
    systemctl restart nginx
    clear
    echo ""
    echo -e "\033[0;92mPanel uninstalled successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "6" ]
then
    echo -n "Provide the URL of an image for the background: "
    read -r BG_URL
    
    Theme=theme_2
    BG_URL=$BG_URL
    authIcon_URL=""
    favIcon_URL=""

    [ -z "$BG_URL" ] && Theme=theme

    required_input authIcon_URL "Provide the URL of an image for the auth icon: " "URL cannot be empty"
    required_input favIcon_URL "Provide the URL of an image for the favicon: " "URL cannot be empty"

    cd /var/www/pterodactyl
    
    rm /var/www/pterodactyl/resources/scripts/theme.css
    rm /var/www/pterodactyl/resources/scripts/index.tsx
    rm /var/www/pterodactyl/resources/scripts/components/auth/LoginFormContainer.tsx
    rm /var/www/pterodactyl/resources/views/templates/wrapper.blade.php
    rm /var/www/pterodactyl/resources/views/layouts/admin.blade.php

    curl -o /var/www/pterodactyl/resources/scripts/index.tsx $GitHub_Account/index.tsx
    curl -o /var/www/pterodactyl/resources/scripts/theme.css $GitHub_Account/$Theme.css
    curl -o /var/www/pterodactyl/resources/scripts/components/auth/LoginFormContainer.tsx $GitHub_Account/LoginFormContainer.tsx
    curl -o /var/www/pterodactyl/resources/views/templates/wrapper.blade.php $GitHub_Account/wrapper.blade.php
    curl -o /var/www/pterodactyl/resources/views/layouts/admin.blade.php $GitHub_Account/admin.blade.php
    
    sed -i -e "s@<URL>@${BG_URL}@g" /var/www/pterodactyl/resources/scripts/theme.css
    sed -i -e "s@<URL>@${authIcon_URL}@g" /var/www/pterodactyl/resources/scripts/components/auth/LoginFormContainer.tsx
    sed -i -e "s@<URL>@${favIcon_URL}@g" /var/www/pterodactyl/resources/views/templates/wrapper.blade.php
    sed -i -e "s@<URL>@${favIcon_URL}@g" /var/www/pterodactyl/resources/views/layouts/admin.blade.php
    
    apt remove -y nodejs

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_16.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    
    apt update
    apt install -y nodejs

    npm i -g yarn
    
    yarn

    yarn build:production

    php artisan optimize:clear
    
    rm -rf node_modules
    apt remove -y nodejs
    clear
    
    echo ""
    echo -e "\033[0;92mTheme installed successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "7" ]
    then
    required_input blowfish_secret "Provide blowfish secret for phpMyAdmin: " "Blowfish secret cannot be empty"

    installPhpMyAdmin "/var/www/pterodactyl/public"
    clear
    echo ""
    echo -e "\033[0;92mphpMyAdmin installed successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "8" ]
then
    rm -rf /var/pterodactyl/public/pma
    clear
    echo ""
    echo -e "\033[0;92mphpMyAdmin uninstalled successfully\033[0m"
    echo ""
    exit
fi
