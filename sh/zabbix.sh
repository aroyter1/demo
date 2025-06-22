#!/bin/bash

# Скрипт для установки Zabbix на Debian 12

# Проверяем, что скрипт запущен с правами root
if [[ $EUID -ne 0 ]]; then
   echo "Пожалуйста, запустите скрипт с помощью sudo или под root."
   exit 1
fi

# Скачиваем репозиторий Zabbix
wget https://repo.zabbix.com/zabbix/7.4/release/debian/pool/main/z/zabbix-release/zabbix-release_7.4-0.2+debian12_all.deb
if [[ $? -ne 0 ]]; then
    echo "Ошибка при скачивании репозитория Zabbix. Проверьте подключение к интернету или ссылку."
    exit 1
fi

# Устанавливаем репозиторий
dpkg -i zabbix-release_7.4-0.2+debian12_all.deb
if [[ $? -ne 0 ]]; then
    echo "Ошибка при установке репозитория. Проверьте, что файл zabbix-release_7.4-0.2+debian12_all.deb существует."
    exit 1
fi

# Обновляем список пакетов
apt update
if [[ $? -ne 0 ]]; then
    echo "Ошибка при обновлении списка пакетов. Проверьте настройки репозиториев."
    exit 1
fi

# Устанавливаем необходимые пакеты
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-agent php php-mysql php-bcmath php-mbstring
if [[ $? -ne 0 ]]; then
    echo "Ошибка при установке пакетов. Проверьте наличие пакетов и доступность репозиториев."
    exit 1
fi

# Проверяем наличие файла схемы базы данных
if [[ ! -f /usr/share/doc/zabbix-sql-scripts/mysql/create.sql.gz ]]; then
    echo "Файл схемы базы данных не найден: /usr/share/doc/zabbix-sql-scripts/mysql/create.sql.gz"
    echo "Возможные причины: пакет zabbix-server-mysql не установлен или структура пакетов изменилась."
    exit 1
fi

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

if [[ $? -ne 0 ]]; then
    echo "Ошибка при создании базы данных или пользователя. Проверьте правильность пароля root MySQL."
    exit 1
fi

# Импорт схемы базы данных
zcat /usr/share/doc/zabbix-sql-scripts/mysql/create.sql.gz | mysql -u zabbix -p"$ZABBIX_PASS" zabbix
if [[ $? -ne 0 ]]; then
    echo "Ошибка при импорте схемы базы данных. Проверьте правильность пароля пользователя zabbix и наличие файла схемы."
    exit 1
fi

echo "База данных и пользователь созданы, схема импортирована."
echo "Дальше настройте файл: sudo nano /etc/zabbix/zabbix_server.conf"