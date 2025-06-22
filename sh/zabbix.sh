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

# Проверка подключения к интернету
check_internet() {
    print_status "Проверка подключения к интернету..."

    # Список серверов для проверки
    TEST_HOSTS=("8.8.8.8" "1.1.1.1" "google.com" "debian.org")

    for host in "${TEST_HOSTS[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            print_success "Подключение к интернету работает (проверено через $host)"
            return 0
        fi
    done

    print_error "Нет подключения к интернету!"
    print_error "Проверьте сетевые настройки и повторите попытку"
    exit 1
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

    # Сначала добавляем GPG ключ
    print_status "Добавление GPG ключа Zabbix..."

    # Пробуем несколько способов добавления ключа
    if ! wget -qO - https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-A14FE591 | apt-key add - 2>/dev/null; then
        print_warning "Не удалось добавить ключ через apt-key, пробуем альтернативный способ..."

        # Альтернативный способ через gpg
        wget -qO - https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-A14FE591 | gpg --dearmor | tee /usr/share/keyrings/zabbix-archive-keyring.gpg > /dev/null

        if [[ $? -ne 0 ]]; then
            print_error "Не удалось добавить GPG ключ. Проверьте подключение к интернету."
            exit 1
        fi
    fi

    print_success "GPG ключ Zabbix добавлен"

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

    # Проверяем доступность репозитория
    print_status "Проверка доступности репозитория..."
    if ! curl -s --head "$ZABBIX_REPO" | head -n 1 | grep -q "200 OK"; then
        print_warning "Основной репозиторий недоступен, пробуем альтернативную версию..."

        # Пробуем более новую версию
        case $DEBIAN_VERSION in
            "12")
                ZABBIX_REPO="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-2+debian12_all.deb"
                ;;
            *)
                ZABBIX_REPO="https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian$DEBIAN_VERSION_all.deb"
                ;;
        esac
    fi

    print_status "Скачивание пакета репозитория: $ZABBIX_REPO"

    # Скачивание с retry логикой
    for i in {1..3}; do
        if wget "$ZABBIX_REPO" -O /tmp/zabbix-release.deb; then
            break
        else
            print_warning "Попытка $i/3 неудачна, повторяем через 5 секунд..."
            sleep 5
            if [[ $i -eq 3 ]]; then
                print_error "Не удалось скачать пакет репозитория после 3 попыток"
                exit 1
            fi
        fi
    done

    # Установка пакета репозитория
    print_status "Установка пакета репозитория..."
    if ! dpkg -i /tmp/zabbix-release.deb; then
        print_warning "Ошибка установки, пробуем исправить зависимости..."
        apt --fix-broken install -y
        dpkg -i /tmp/zabbix-release.deb
    fi

    # Обновление списка пакетов с retry логикой
    print_status "Обновление списка пакетов..."
    for i in {1..3}; do
        if apt update; then
            break
        else
            print_warning "Ошибка обновления пакетов, попытка $i/3..."
            sleep 5
            if [[ $i -eq 3 ]]; then
                print_error "Не удалось обновить список пакетов"
                exit 1
            fi
        fi
    done

    print_success "Репозиторий Zabbix добавлен"
}

# Установка компонентов Zabbix
install_zabbix() {
    print_status "Установка Zabbix Server, Frontend и Agent..."

    # Список пакетов для установки
    ZABBIX_PACKAGES="zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent"

    # Проверяем доступность пакетов
    print_status "Проверка доступности пакетов..."
    for package in $ZABBIX_PACKAGES; do
        if ! apt-cache show "$package" >/dev/null 2>&1; then
            print_warning "Пакет $package недоступен, пробуем альтернативы..."
            case $package in
                "zabbix-agent")
                    # Пробуем zabbix-agent2 как альтернативу
                    if apt-cache show "zabbix-agent2" >/dev/null 2>&1; then
                        ZABBIX_PACKAGES="${ZABBIX_PACKAGES/zabbix-agent/zabbix-agent2}"
                        print_status "Используем zabbix-agent2 вместо zabbix-agent"
                    fi
                    ;;
            esac
        fi
    done

    # Установка пакетов с retry логикой
    print_status "Установка пакетов: $ZABBIX_PACKAGES"

    for i in {1..3}; do
        if apt install -y $ZABBIX_PACKAGES; then
            print_success "Все пакеты Zabbix установлены успешно"
            return 0
        else
            print_warning "Ошибка установки, попытка $i/3..."

            if [[ $i -lt 3 ]]; then
                print_status "Пробуем исправить зависимости..."
                apt --fix-broken install -y
                apt update
                sleep 5
            else
                print_error "Не удалось установить пакеты Zabbix после 3 попыток"
                print_status "Пробуем установить пакеты по отдельности..."

                # Пробуем установить каждый пакет отдельно
                for package in $ZABBIX_PACKAGES; do
                    print_status "Установка $package..."
                    if apt install -y "$package"; then
                        print_success "$package установлен"
                    else
                        print_warning "Не удалось установить $package"
                    fi
                done

                break
            fi
        fi
    done

    # Проверяем, что основные компоненты установлены
    if ! command -v zabbix_server >/dev/null 2>&1; then
        print_error "zabbix-server не установлен!"
        exit 1
    fi

    print_success "Компоненты Zabbix установлены"
}

# Импорт схемы базы данных
import_database_schema() {
    print_status "Импорт схемы базы данных Zabbix..."

    # Загрузка пароля из файла
    source /root/zabbix_db_credentials.txt

    # Поиск файла схемы в разных возможных расположениях
    SCHEMA_PATHS=(
        "/usr/share/zabbix-sql-scripts/mysql/server.sql.gz"
        "/usr/share/doc/zabbix-sql-scripts/mysql/create.sql.gz"
        "/usr/share/doc/zabbix-server-mysql/create.sql.gz"
        "/usr/share/zabbix-sql-scripts/mysql/create.sql.gz"
    )

    SCHEMA_FILE=""
    for path in "${SCHEMA_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            SCHEMA_FILE="$path"
            print_status "Найден файл схемы: $SCHEMA_FILE"
            break
        fi
    done

    if [[ -z "$SCHEMA_FILE" ]]; then
        print_error "Файл схемы базы данных не найден!"
        print_status "Поиск файлов схемы в системе..."

        # Поиск всех возможных файлов схемы
        find /usr -name "*.sql.gz" -path "*zabbix*" 2>/dev/null | while read -r file; do
            print_status "Найден: $file"
        done

        # Пробуем найти без .gz
        find /usr -name "*.sql" -path "*zabbix*" 2>/dev/null | while read -r file; do
            print_status "Найден: $file"
        done

        print_error "Установите пакет zabbix-sql-scripts и повторите попытку"
        exit 1
    fi

    # Проверяем подключение к базе данных
    print_status "Проверка подключения к базе данных..."
    if ! mysql -uzabbix -p"$DB_PASSWORD" zabbix -e "SELECT 1" >/dev/null 2>&1; then
        print_error "Не удается подключиться к базе данных zabbix"
        print_status "Проверьте что база данных создана и пользователь настроен правильно"
        exit 1
    fi

    # Проверяем, не импортирована ли уже схема
    TABLE_COUNT=$(mysql -uzabbix -p"$DB_PASSWORD" zabbix -e "SHOW TABLES;" 2>/dev/null | wc -l)
    if [[ $TABLE_COUNT -gt 1 ]]; then
        print_warning "В базе данных уже есть таблицы ($((TABLE_COUNT-1)) таблиц)"
        read -p "Хотите переимпортировать схему? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Пропускаем импорт схемы"
            return 0
        else
            print_warning "Очищаем базу данных..."
            mysql -uzabbix -p"$DB_PASSWORD" zabbix -e "DROP DATABASE zabbix; CREATE DATABASE zabbix character set utf8mb4 collate utf8mb4_bin;"
            mysql -u root -p"$MYSQL_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null || true
        fi
    fi

    # Импорт схемы
    print_status "Импортирование схемы из файла: $SCHEMA_FILE"

    if [[ "$SCHEMA_FILE" == *.gz ]]; then
        # Файл сжат
        if zcat "$SCHEMA_FILE" | mysql -uzabbix -p"$DB_PASSWORD" zabbix; then
            print_success "Схема базы данных импортирована успешно"
        else
            print_error "Ошибка при импорте схемы из сжатого файла"
            exit 1
        fi
    else
        # Файл не сжат
        if mysql -uzabbix -p"$DB_PASSWORD" zabbix < "$SCHEMA_FILE"; then
            print_success "Схема базы данных импортирована успешно"
        else
            print_error "Ошибка при импорте схемы из несжатого файла"
            exit 1
        fi
    fi

    # Проверяем успешность импорта
    FINAL_TABLE_COUNT=$(mysql -uzabbix -p"$DB_PASSWORD" zabbix -e "SHOW TABLES;" 2>/dev/null | wc -l)
    if [[ $FINAL_TABLE_COUNT -gt 100 ]]; then
        print_success "Схема импортирована успешно ($((FINAL_TABLE_COUNT-1)) таблиц создано)"
    else
        print_warning "Импорт завершен, но количество таблиц кажется малым: $((FINAL_TABLE_COUNT-1))"
    fi
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
    check_internet
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
