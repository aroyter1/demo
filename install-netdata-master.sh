#!/bin/bash

# Скрипт установки и настройки Netdata Master сервера
# Для использования: sudo bash install-netdata-master.sh

echo "=== Установка Netdata Master сервера ==="

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root (sudo)"
   exit 1
fi

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
apt install curl wget git apache2-utils nginx -y

# Установка Netdata
echo "Установка Netdata..."
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
sh /tmp/netdata-kickstart.sh --stable-channel --dont-wait

# Создание резервной копии конфигурации
echo "Создание резервной копии..."
cp /etc/netdata/netdata.conf /etc/netdata/netdata.conf.backup

# Настройка основной конфигурации Netdata
echo "Настройка конфигурации Netdata..."
cat > /etc/netdata/netdata.conf << 'EOF'
[global]
    bind to = 0.0.0.0
    default port = 19999
    memory mode = dbengine
    page cache size = 32
    dbengine disk space = 256
    web files owner = netdata
    web files group = netdata

[web]
    allow connections from = localhost 127.0.0.1 10.* 192.168.*
    allow dashboard from = localhost 127.0.0.1 10.* 192.168.*
    allow badges from = *
    allow streaming from = *
    enable basic auth = yes
    web files owner = netdata
    web files group = netdata
    http auth method = basic
    http auth realm = netdata
    http auth file = /etc/netdata/netdata.passwd

[registry]
    enabled = yes
    registry to announce = http://HQ-SRV:19999
    registry hostname = HQ-SRV

[health]
    enabled = yes
    default repeat warning = never
    default repeat critical = never
EOF

# Создание файла паролей
echo "Настройка аутентификации..."
echo "admin:$(openssl passwd -apr1 'P@ssw0rd')" > /etc/netdata/netdata.passwd
chown netdata:netdata /etc/netdata/netdata.passwd
chmod 640 /etc/netdata/netdata.passwd

# Настройка streaming конфигурации
echo "Настройка приема данных от slave серверов..."
cat > /etc/netdata/stream.conf << 'EOF'
[stream]
    enabled = yes
    destination =
    api key =

[11111111-2222-3333-4444-555555555555]
    enabled = yes
    allow from = *
    default history = 3600
    default memory mode = dbengine
    health enabled by default = auto
    default postpone alarms on connect seconds = 60
EOF

# Настройка алертов
echo "Настройка алертов..."
cat > /etc/netdata/health.d/custom.conf << 'EOF'
# Алерт для высокой загрузки CPU
 alarm: cpu_usage
    on: system.cpu
lookup: average -3m unaligned of user,system,softirq,irq,guest
 every: 10s
  warn: $this > 80
  crit: $this > 95
  info: CPU usage is high

# Алерт для высокого использования RAM
 alarm: ram_usage
    on: system.ram
lookup: average -1m unaligned of used
 every: 10s
  warn: $this > 80
  crit: $this > 95
  info: RAM usage is high

# Алерт для заполнения диска
 alarm: disk_space_usage
    on: disk_space._
lookup: average -1m unaligned of used
 every: 10s
  warn: $this > 80
  crit: $this > 95
  info: Disk space usage is high
EOF

# Настройка nginx
echo "Настройка nginx..."
cat > /etc/nginx/sites-available/netdata << 'EOF'
server {
    listen 80;
    server_name mon.au-team.irpo;

    access_log /var/log/nginx/netdata_access.log;
    error_log /var/log/nginx/netdata_error.log;

    location / {
        proxy_pass http://127.0.0.1:19999;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://127.0.0.1:19999;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Активация nginx конфигурации
ln -sf /etc/nginx/sites-available/netdata /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации nginx
nginx -t

# Настройка firewall
echo "Настройка firewall..."
ufw allow 19999/tcp
ufw allow 80/tcp
ufw allow 22/tcp
ufw --force enable

# Запуск и включение служб
echo "Запуск служб..."
systemctl enable netdata
systemctl enable nginx
systemctl restart netdata
systemctl restart nginx

# Проверка статуса служб
echo "=== Проверка статуса служб ==="
systemctl status netdata --no-pager -l
systemctl status nginx --no-pager -l

# Проверка портов
echo "=== Проверка открытых портов ==="
netstat -tulpn | grep -E ":80|:19999"

echo ""
echo "=== Установка завершена! ==="
echo "Доступ к мониторингу: http://mon.au-team.irpo"
echo "Логин: admin"
echo "Пароль: P@ssw0rd"
echo ""
echo "Для подключения slave серверов используйте API ключ:"
echo "11111111-2222-3333-4444-555555555555"
echo ""
echo "Логи Netdata: tail -f /var/log/netdata/netdata.log"
echo "Логи nginx: tail -f /var/log/nginx/netdata_error.log"