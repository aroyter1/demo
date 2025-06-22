#!/bin/bash

# Скрипт для установки Zabbix на Debian 12

# Скачиваем репозиторий Zabbix
wget https://repo.zabbix.com/zabbix/7.4/release/debian/pool/main/z/zabbix-release/zabbix-release_7.4-0.2%2Bdebian12_all.deb

# Устанавливаем репозиторий
sudo dpkg -i zabbix-release_7.4-0.2+debian12_all.deb

# Обновляем список пакетов
sudo apt update

# Устанавливаем необходимые пакеты
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-agent php php-mysql php-bcmath php-mbstring

# Запрос пароля для пользователя root MySQL
read -s -p "Введите пароль для пользователя root MySQL: " MYSQL_ROOT_PASS
echo
read -s -p "Введите пароль для пользователя zabbix (будет создан): " ZABBIX_PASS
echo

# Создание базы данных и пользователя
mysql -u root -p"$MYSQL_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '$ZABBIX_PASS';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

# Импорт схемы базы данных
zcat /usr/share/doc/zabbix-sql-scripts/mysql/create.sql.gz | mysql -u zabbix -p"$ZABBIX_PASS" zabbix

echo "База данных и пользователь созданы, схема импортирована."
echo "иди sudo nano /etc/zabbix/zabbix_server.conf"