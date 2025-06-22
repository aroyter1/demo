#!/bin/bash

# Скрипт автоматической установки Zabbix на Debian
# Версия: 1.0
# Поддерживаемые версии: Debian 10/11/12

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав суперпользователя
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Определение версии Debian
get_debian_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DEBIAN_VERSION=$VERSION_ID
        print_status "Обнаружена версия Debian: $DEBIAN_VERSION"
    else
        print_error "Не удалось определить версию Debian"
        exit 1
    fi
}

# Обновление системы
update_system() {
    print_status "Обновление списка пакетов..."
    apt update

    print_status "Обновление системы..."
    apt upgrade -y

    print_status "Установка базовых пакетов..."
    apt install -y wget curl gnupg2 software-properties-common apt-transport-https ca-certificates
}

# Установка и настройка Apache
install_apache() {
    print_status "Установка Apache веб-сервера..."
    apt install -y apache2

    print_status "Включение и запуск Apache..."
    systemctl enable apache2
    systemctl start apache2

    print_success "Apache установлен и запущен"
}

# Установка PHP и необходимых модулей
install_php() {
    print_status "Установка PHP и необходимых модулей для Zabbix..."

    apt install -y php php-mysql php-gd php-xml php-mbstring php-gettext php-bcmath php-ldap php-curl php-zip php-fpm

    # Настройка PHP для Zabbix
    print_status "Настройка PHP для Zabbix..."

    PHP_INI="/etc/php/$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')/apache2/php.ini"

    if [[ -f $PHP_INI ]]; then
        sed -i 's/max_execution_time = 30/max_execution_time = 300/' $PHP_INI
        sed -i 's/max_input_time = 60/max_input_time = 300/' $PHP_INI
        sed -i 's/memory_limit = 128M/memory_limit = 256M/' $PHP_INI
        sed -i 's/post_max_size = 8M/post_max_size = 32M/' $PHP_INI
        sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 16M/' $PHP_INI
        sed -i 's/;date.timezone =/date.timezone = Europe\/Moscow/' $PHP_INI

        print_success "PHP настроен для Zabbix"
    else
        print_warning "Не удалось найти php.ini, возможно потребуется ручная настройка"
    fi
}

# Установка и настройка MariaDB
install_mariadb() {
    print_status "Установка MariaDB..."
    apt install -y mariadb-server mariadb-client

    print_status "Запуск и включение MariaDB..."
    systemctl enable mariadb
    systemctl start mariadb

    print_success "MariaDB установлена и запущена"
}

# Создание базы данных для Zabbix
create_zabbix_database() {
    print_status "Создание базы данных для Zabbix..."

    # Фиксированный пароль для базы данных
    DB_PASSWORD="P@ssw0rd"

    # Создание базы данных и пользователя
    mysql -u root <<EOF
CREATE DATABASE zabbix character set utf8mb4 collate utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

    print_success "База данных zabbix создана"
    print_success "Пользователь: zabbix"
    print_success "Пароль: $DB_PASSWORD"

    # Сохранение пароля в файл
    echo "DB_PASSWORD=$DB_PASSWORD" > /root/zabbix_db_credentials.txt
    chmod 600 /root/zabbix_db_credentials.txt
    print_status "Данные для подключения к БД сохранены в /root/zabbix_db_credentials.txt"
}

# Добавление репозитория Zabbix
add_zabbix_repository() {
    print_status "Добавление официального репозитория Zabbix..."

    # Определение правильного репозитория для версии Debian
    case $DEBIAN_VERSION in
        "10")
            ZABBIX_REPO="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian10_all.deb"
            ;;
        "11")
            ZABBIX_REPO="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
            ;;
        "12")
            ZABBIX_REPO="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian12_all.deb"
            ;;
        *)
            print_warning "Неизвестная версия Debian, используется репозиторий для Debian 11"
            ZABBIX_REPO="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
            ;;
    esac

    wget $ZABBIX_REPO -O /tmp/zabbix-release.deb
    dpkg -i /tmp/zabbix-release.deb
    apt update

    print_success "Репозиторий Zabbix добавлен"
}

# Установка компонентов Zabbix
install_zabbix() {
    print_status "Установка Zabbix Server, Frontend и Agent..."

    apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent

    print_success "Компоненты Zabbix установлены"
}

# Импорт схемы базы данных
import_database_schema() {
    print_status "Импорт схемы базы данных Zabbix..."

    # Загрузка пароля из файла
    source /root/zabbix_db_credentials.txt

    # Импорт схемы
    zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -uzabbix -p$DB_PASSWORD zabbix

    print_success "Схема базы данных импортирована"
}

# Настройка Zabbix Server
configure_zabbix_server() {
    print_status "Настройка Zabbix Server..."

    # Загрузка пароля из файла
    source /root/zabbix_db_credentials.txt

    # Редактирование конфигурационного файла
    sed -i "s/# DBPassword=/DBPassword=$DB_PASSWORD/" /etc/zabbix/zabbix_server.conf

    print_success "Zabbix Server настроен"
}

# Настройка Apache для Zabbix
configure_apache_zabbix() {
    print_status "Настройка Apache для Zabbix..."

    # Включение необходимых модулей Apache
    a2enmod rewrite

    # Создание виртуального хоста для mon.au-team.irpo
    print_status "Создание виртуального хоста для mon.au-team.irpo..."

    cat > /etc/apache2/sites-available/zabbix-mon.conf <<EOF
<VirtualHost *:80>
    ServerName mon.au-team.irpo
    DocumentRoot /usr/share/zabbix

    <Directory "/usr/share/zabbix">
        Options FollowSymLinks
        AllowOverride None
        Require all granted

        <IfModule mod_php7.c>
            php_value max_execution_time 300
            php_value memory_limit 256M
            php_value post_max_size 32M
            php_value upload_max_filesize 16M
            php_value max_input_time 300
            php_value max_input_vars 10000
            php_value always_populate_raw_post_data -1
            php_value date.timezone Europe/Moscow
        </IfModule>
        <IfModule mod_php8.c>
            php_value max_execution_time 300
            php_value memory_limit 256M
            php_value post_max_size 32M
            php_value upload_max_filesize 16M
            php_value max_input_time 300
            php_value max_input_vars 10000
            php_value date.timezone Europe/Moscow
        </IfModule>
    </Directory>

    <Directory "/usr/share/zabbix/conf">
        Require all denied
    </Directory>

    <Directory "/usr/share/zabbix/app">
        Require all denied
    </Directory>

    <Directory "/usr/share/zabbix/include">
        Require all denied
    </Directory>

    <Directory "/usr/share/zabbix/local">
        Require all denied
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/zabbix_error.log
    CustomLog \${APACHE_LOG_DIR}/zabbix_access.log combined
</VirtualHost>
EOF

    # Включение сайта и отключение дефолтного
    a2ensite zabbix-mon.conf
    a2dissite 000-default.conf

    # Добавление записи в /etc/hosts для локального тестирования
    if ! grep -q "mon.au-team.irpo" /etc/hosts; then
        echo "127.0.0.1 mon.au-team.irpo" >> /etc/hosts
        print_status "Добавлена запись в /etc/hosts для локального доступа"
    fi

    # Перезапуск Apache
    systemctl restart apache2

    print_success "Apache настроен для Zabbix с доменом mon.au-team.irpo"
}

# Запуск и включение сервисов
start_services() {
    print_status "Запуск и включение сервисов Zabbix..."

    systemctl restart zabbix-server zabbix-agent apache2
    systemctl enable zabbix-server zabbix-agent

    print_success "Сервисы Zabbix запущены и включены"
}

# Настройка файрвола (если установлен)
configure_firewall() {
    if command -v ufw &> /dev/null; then
        print_status "Настройка UFW для Zabbix..."
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 10050/tcp
        ufw allow 10051/tcp
        print_success "Правила файрвола добавлены"
    elif command -v iptables &> /dev/null; then
        print_status "Настройка iptables для Zabbix..."
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        iptables -A INPUT -p tcp --dport 10050 -j ACCEPT
        iptables -A INPUT -p tcp --dport 10051 -j ACCEPT
        print_warning "Правила iptables добавлены, но могут быть сброшены при перезагрузке"
    fi
}

# Вывод информации об установке
print_installation_info() {
    print_success "╔════════════════════════════════════════════════════════════════════════════════════════╗"
    print_success "║                                УСТАНОВКА ZABBIX ЗАВЕРШЕНА                             ║"
    print_success "╚════════════════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    print_status "Доступ к веб-интерфейсу Zabbix:"
    print_status "URL: http://mon.au-team.irpo"
    print_status "Локальный доступ: http://localhost"
    print_status "IP доступ: http://$(hostname -I | awk '{print $1}')"
    echo ""
    print_status "Данные для входа по умолчанию:"
    print_status "Логин: Admin"
    print_status "Пароль: zabbix"
    echo ""
    print_status "Данные подключения к базе данных:"
    print_status "Пользователь: zabbix"
    print_status "База данных: zabbix"
    print_status "Пароль сохранен в: /root/zabbix_db_credentials.txt"
    echo ""
    print_warning "ВАЖНО: Смените пароль администратора после первого входа!"
    print_warning "ВАЖНО: Настройте безопасность базы данных с помощью: mysql_secure_installation"
    echo ""
    print_status "Полезные команды:"
    print_status "Статус сервисов: systemctl status zabbix-server zabbix-agent"
    print_status "Логи сервера: tail -f /var/log/zabbix/zabbix_server.log"
    print_status "Логи агента: tail -f /var/log/zabbix/zabbix_agentd.log"
}

# Основная функция
main() {
    print_status "Начинаем установку Zabbix на Debian..."

    check_root
    get_debian_version
    update_system
    install_apache
    install_php
    install_mariadb
    create_zabbix_database
    add_zabbix_repository
    install_zabbix
    import_database_schema
    configure_zabbix_server
    configure_apache_zabbix
    start_services
    configure_firewall
    print_installation_info

    print_success "Скрипт установки Zabbix выполнен успешно!"
}

# Запуск основной функции
main "$@"
