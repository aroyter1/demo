#!/bin/bash

# Автоматическая установка Zabbix Server и настройка базы данных на HQ-SRV

# Параметры
DB_NAME="zabbix"
DB_USER="zabbix"
DB_PASSWORD="P@ssw0rd"
DB_PORT="3306"
ZABBIX_VERSION="7.4"

# Проверка, что скрипт запущен с правами root
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен быть запущен с правами root" 1>&2
   exit 1
fi

# Обновление системы и установка необходимых утилит
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка wget и других необходимых пакетов
apt install -y wget

# Добавление репозитория Zabbix
echo "Добавление репозитория Zabbix $ZABBIX_VERSION..."
wget https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/release/debian/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-0.2%2Bdebian12_all.deb
dpkg -i zabbix-release_${ZABBIX_VERSION}-0.2%2Bdebian12_all.deb
apt update

# Установка Zabbix Server, веб-интерфейса и агента
echo "Установка Zabbix Server, веб-интерфейса и агента..."
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-agent php php-mysql php-bcmath php-mbstring

# Установка MariaDB, если не установлена
if ! command -v mysql &> /dev/null; then
    echo "Установка MariaDB..."
    apt install -y mariadb-server
    systemctl enable --now mariadb
fi

# Настройка базы данных
echo "Настройка базы данных Zabbix..."
mysql -u root -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Импорт схемы базы данных
echo "Импорт схемы базы данных Zabbix..."
zcat /usr/share/doc/zabbix-sql-scripts/mysql/create.sql.gz | mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME

# Настройка конфигурации Zabbix Server
echo "Настройка конфигурационного файла Zabbix Server..."
cat << EOF > /etc/zabbix/zabbix_server.conf
DBName=$DB_NAME
DBUser=$DB_USER
DBPassword=$DB_PASSWORD
DBPort=$DB_PORT
EOF

# Запуск и включение службы Zabbix Server
echo "Запуск Zabbix Server..."
systemctl enable --now zabbix-server

# Очистка
echo "Очистка временных файлов..."
rm zabbix-release_${ZABBIX_VERSION}-0.2%2Bdebian12_all.deb

echo "Установка Zabbix Server завершена! Настройте веб-интерфейс по инструкции."