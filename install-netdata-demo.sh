#!/bin/bash

# Скрипт установки Netdata с демо-данными для 4 серверов
# Использование: sudo bash install-netdata-demo.sh

echo "=== Установка Netdata Demo с фейковыми данными ==="

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root (sudo)"
   exit 1
fi

# Массив серверов для демонстрации
SERVERS=("HQ-SRV" "HQ-RTR" "BR-RTR" "BR-SRV")

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
apt install curl wget git apache2-utils nginx bc python3 -y

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

[plugins]
    charts.d = yes
    python.d = yes
EOF

# Создание файла паролей
echo "Настройка аутентификации..."
echo "admin:$(openssl passwd -apr1 'P@ssw0rd')" > /etc/netdata/netdata.passwd
chown netdata:netdata /etc/netdata/netdata.passwd
chmod 640 /etc/netdata/netdata.passwd

# Создание Python плагина для демо данных
echo "Создание генератора фейковых данных..."
cat > /etc/netdata/python.d/demo_servers.chart.py << 'EOF'
# -*- coding: utf-8 -*-
# Netdata python plugin для демо данных серверов

import random
import time
from bases.FrameworkServices.SimpleService import SimpleService

priority = 60000
update_every = 5

ORDER = []
CHARTS = {}

# Список серверов
SERVERS = ['HQ-SRV', 'HQ-RTR', 'BR-RTR', 'BR-SRV']

# Создание чартов для каждого сервера
for server in SERVERS:
    server_id = server.lower().replace('-', '_')

    # CPU Chart
    cpu_chart_id = f'{server_id}_cpu'
    ORDER.append(cpu_chart_id)
    CHARTS[cpu_chart_id] = {
        'options': [None, f'CPU Usage - {server}', 'percentage', 'cpu', f'{server}.cpu', 'stacked'],
        'lines': [
            ['user', 'User', 'absolute'],
            ['system', 'System', 'absolute'],
            ['idle', 'Idle', 'absolute']
        ]
    }

    # Memory Chart
    mem_chart_id = f'{server_id}_memory'
    ORDER.append(mem_chart_id)
    CHARTS[mem_chart_id] = {
        'options': [None, f'Memory Usage - {server}', 'MB', 'memory', f'{server}.memory', 'stacked'],
        'lines': [
            ['used', 'Used', 'absolute'],
            ['free', 'Free', 'absolute'],
            ['cached', 'Cached', 'absolute']
        ]
    }

    # Disk Chart
    disk_chart_id = f'{server_id}_disk'
    ORDER.append(disk_chart_id)
    CHARTS[disk_chart_id] = {
        'options': [None, f'Disk Usage - {server}', 'GB', 'disk', f'{server}.disk', 'stacked'],
        'lines': [
            ['disk_used', 'Used', 'absolute'],
            ['disk_free', 'Free', 'absolute']
        ]
    }

class Service(SimpleService):
    def __init__(self, configuration=None, name=None):
        SimpleService.__init__(self, configuration=configuration, name=name)
        self.order = ORDER
        self.definitions = CHARTS
        self.server_states = {}

        # Инициализация состояний серверов
        for server in SERVERS:
            self.server_states[server] = {
                'cpu_base': random.randint(15, 40),
                'ram_total': random.randint(4000, 16000),
                'disk_total': random.randint(100, 1000),
                'trend': random.choice([-1, 1])
            }

    def get_data(self):
        data = {}

        for server in SERVERS:
            server_id = server.lower().replace('-', '_')
            state = self.server_states[server]

            # Generate CPU data with some persistence
            cpu_variation = random.randint(-10, 15)
            cpu_usage = max(5, min(95, state['cpu_base'] + cpu_variation))

            # Update base occasionally
            if random.randint(1, 20) == 1:
                state['cpu_base'] = max(10, min(80, state['cpu_base'] + random.randint(-5, 5)))

            data[f'{server_id}_cpu_user'] = int(cpu_usage * 0.6)
            data[f'{server_id}_cpu_system'] = int(cpu_usage * 0.4)
            data[f'{server_id}_cpu_idle'] = 100 - cpu_usage

            # Generate Memory data
            ram_total = state['ram_total']
            ram_used_percent = random.randint(30, 85)
            ram_used = int(ram_total * ram_used_percent / 100)
            ram_cached = int(ram_total * random.randint(10, 20) / 100)
            ram_free = ram_total - ram_used - ram_cached

            data[f'{server_id}_memory_used'] = ram_used
            data[f'{server_id}_memory_free'] = ram_free
            data[f'{server_id}_memory_cached'] = ram_cached

            # Generate Disk data
            disk_total = state['disk_total']
            disk_used_percent = random.randint(25, 90)
            disk_used = int(disk_total * disk_used_percent / 100)
            disk_free = disk_total - disk_used

            data[f'{server_id}_disk_disk_used'] = disk_used
            data[f'{server_id}_disk_disk_free'] = disk_free

        return data
EOF

# Настройка конфигурации Python плагина
cat > /etc/netdata/python.d/demo_servers.conf << 'EOF'
# Demo servers configuration
update_every: 5
priority: 60000
EOF

chown netdata:netdata /etc/netdata/python.d/demo_servers.chart.py
chown netdata:netdata /etc/netdata/python.d/demo_servers.conf
chmod 644 /etc/netdata/python.d/demo_servers.chart.py
chmod 644 /etc/netdata/python.d/demo_servers.conf

# Создание дополнительного bash плагина для сетевых метрик
mkdir -p /etc/netdata/charts.d
cat > /etc/netdata/charts.d/demo_network.chart.sh << 'EOF'
#!/bin/bash

# Demo network metrics for servers

demo_network_update_every=5
demo_network_priority=60001

demo_network_check() {
    return 0
}

demo_network_create() {
    for server in HQ-SRV HQ-RTR BR-RTR BR-SRV; do
        server_id=$(echo $server | tr '[:upper:]' '[:lower:]' | tr '-' '_')

        cat << EOF
CHART ${server_id}.network '' "Network Traffic - $server" "KB/s" network ${server}.network area $demo_network_priority $demo_network_update_every
DIMENSION received '' absolute 1 1
DIMENSION sent '' absolute -1 1

EOF
    done
    return 0
}

demo_network_update() {
    for server in HQ-SRV HQ-RTR BR-RTR BR-SRV; do
        server_id=$(echo $server | tr '[:upper:]' '[:lower:]' | tr '-' '_')

        # Generate random network data
        received=$((RANDOM % 5000 + 100))
        sent=$((RANDOM % 3000 + 50))

        cat << EOF
BEGIN ${server_id}.network $(date +%s)
SET received = $received
SET sent = $sent
END

EOF
    done
    return 0
}
EOF

chmod +x /etc/netdata/charts.d/demo_network.chart.sh
chown netdata:netdata /etc/netdata/charts.d/demo_network.chart.sh

# Включение charts.d плагина
cat >> /etc/netdata/netdata.conf << 'EOF'

[plugin:charts.d]
    update every = 5
    command options =
EOF

# Настройка nginx
echo "Настройка nginx..."
cat > /etc/nginx/sites-available/netdata << 'EOF'
server {
    listen 80;
    server_name mon.au-team.irpo localhost;

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

# Перезапуск служб
echo "Запуск служб..."
systemctl enable netdata
systemctl enable nginx
systemctl restart netdata
sleep 5
systemctl restart nginx

# Проверка статуса служб
echo "=== Проверка статуса служб ==="
systemctl status netdata --no-pager -l
systemctl status nginx --no-pager -l

# Проверка портов
echo "=== Проверка открытых портов ==="
netstat -tulpn | grep -E ":80|:19999"

# Получение IP адреса
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo "================================================================="
echo "🎉 УСТАНОВКА ДЕМО МОНИТОРИНГА ЗАВЕРШЕНА!"
echo "================================================================="
echo ""
echo "🌐 ВЕБ-ДОСТУП К МОНИТОРИНГУ:"
echo "   • http://mon.au-team.irpo"
echo "   • http://$IP_ADDRESS"
echo "   • http://localhost (локально)"
echo ""
echo "🔐 ДАННЫЕ ДЛЯ ВХОДА:"
echo "   Логин: admin"
echo "   Пароль: P@ssw0rd"
echo ""
echo "📊 МОНИТОРИРУЕМЫЕ СЕРВЕРЫ (с фейковыми данными):"
echo "   ✅ HQ-SRV - Главный сервер"
echo "   ✅ HQ-RTR - Роутер главного офиса"
echo "   ✅ BR-RTR - Роутер филиала"
echo "   ✅ BR-SRV - Сервер филиала"
echo ""
echo "📈 ОТОБРАЖАЕМЫЕ МЕТРИКИ:"
echo "   • CPU Usage (загрузка процессора в %)"
echo "   • Memory Usage (использование ОЗУ в MB)"
echo "   • Disk Usage (использование диска в GB)"
echo "   • Network Traffic (сетевой трафик в KB/s)"
echo ""
echo "⚙️  ТЕХНИЧЕСКИЕ ПАРАМЕТРЫ:"
echo "   • Порт Netdata: 19999"
echo "   • Веб-порт: 80"
echo "   • Обновление данных: каждые 5 секунд"
echo "   • Фейковые данные: случайные значения"
echo ""
echo "🔧 ПОЛЕЗНЫЕ КОМАНДЫ:"
echo "   Логи Netdata:     sudo tail -f /var/log/netdata/netdata.log"
echo "   Логи nginx:       sudo tail -f /var/log/nginx/netdata_error.log"
echo "   Перезапуск:       sudo systemctl restart netdata nginx"
echo "   Статус служб:     sudo systemctl status netdata nginx"
echo ""

# Добавляем localhost в hosts если нужно
if ! grep -q "mon.au-team.irpo" /etc/hosts; then
    echo "127.0.0.1 mon.au-team.irpo" >> /etc/hosts
    echo "✅ Добавлен localhost mapping для mon.au-team.irpo"
fi

echo "================================================================="
echo "🚀 ГОТОВО! Откройте браузер и перейдите по указанным адресам"
echo "   Фейковые данные генерируются автоматически для демонстрации"
echo "================================================================="