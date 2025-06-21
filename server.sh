#!/bin/bash

# Zabbix Server Installation Script for Debian
# Скрипт установки Zabbix Server на Debian

set -e

echo "=== Установка Zabbix Server ==="

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка пакетов
echo "Установка пакетов Zabbix и MySQL..."
apt install zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent mysql-server -y

# Запуск MySQL
systemctl start mysql
systemctl enable mysql

# Создание базы данных
echo "Создание базы данных Zabbix..."
mysql -u root <<EOF
CREATE DATABASE zabbix character set utf8 collate utf8_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

# Импорт схемы базы данных
echo "Импорт схемы базы данных..."
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -uzabbix -pP@ssw0rd zabbix

# Настройка Zabbix Server
echo "Настройка Zabbix Server..."
sed -i 's/# DBPassword=/DBPassword=P@ssw0rd/' /etc/zabbix/zabbix_server.conf

# Настройка PHP
echo "Настройка PHP..."
sed -i 's/# php_value date.timezone Europe\/Riga/php_value date.timezone Europe\/Moscow/' /etc/zabbix/apache.conf

# Настройка локального агента
echo "Настройка локального Zabbix Agent..."
cat > /etc/zabbix/zabbix_agentd.conf << EOF
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=HQ-SRV
Include=/etc/zabbix/zabbix_agentd.d/*.conf
EOF

# Настройка SSL для доступа по HTTPS
echo "Настройка SSL..."
a2enmod ssl
cat > /etc/apache2/sites-available/zabbix-ssl.conf << EOF
<VirtualHost *:443>
    ServerName mon.au-team.irpo
    DocumentRoot /usr/share/zabbix
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
    
    <Directory "/usr/share/zabbix">
        Options FollowSymLinks
        AllowOverride None
        Require all granted
        
        <IfModule mod_php.c>
            php_value max_execution_time 300
            php_value memory_limit 128M
            php_value post_max_size 16M
            php_value upload_max_filesize 2M
            php_value max_input_time 300
            php_value max_input_vars 10000
            php_value always_populate_raw_post_data -1
            php_value date.timezone Europe/Moscow
        </IfModule>
    </Directory>
</VirtualHost>
EOF

a2ensite zabbix-ssl

# Запуск служб
echo "Запуск служб..."
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2

# Открытие портов в firewall (если используется)
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 10050/tcp
    ufw allow 10051/tcp
fi

echo "=== Установка завершена! ==="
echo ""
echo "Доступ к веб-интерфейсу:"
echo "HTTP:  http://$(hostname -I | awk '{print $1}')/zabbix"
echo "HTTPS: https://mon.au-team.irpo (настройте DNS)"
echo ""
echo "Логин: Admin"
echo "Пароль: zabbix"
echo ""
echo "После первого входа смените пароль на: P@ssw0rd"