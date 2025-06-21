#!/bin/bash

# Zabbix Agent Installation Script for Debian
# Скрипт установки Zabbix Agent на Debian

set -e

# Параметры (измените под ваши нужды)
ZABBIX_SERVER_IP="192.168.100.2"  # IP адрес Zabbix Server (HQ-SRV)
HOSTNAME=$(hostname)               # Автоматически определяем hostname

echo "=== Установка Zabbix Agent ==="
echo "Сервер Zabbix: $ZABBIX_SERVER_IP"
echo "Hostname: $HOSTNAME"

# Обновление системы
echo "Обновление системы..."
apt update

# Установка Zabbix Agent
echo "Установка Zabbix Agent..."
apt install zabbix-agent -y

# Создание конфигурационного файла
echo "Настройка Zabbix Agent..."
cat > /etc/zabbix/zabbix_agentd.conf << EOF
# Zabbix Agent Configuration File

# PID файл
PidFile=/var/run/zabbix/zabbix_agentd.pid

# Лог файл
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0

# Отладка (0-4)
DebugLevel=3

# IP адрес Zabbix Server (пассивные проверки)
Server=$ZABBIX_SERVER_IP

# IP адрес Zabbix Server (активные проверки)
ServerActive=$ZABBIX_SERVER_IP

# Имя хоста (должно совпадать с настройкой в Zabbix Server)
Hostname=$HOSTNAME

# Порт для пассивных проверок
ListenPort=10050

# IP адрес для прослушивания (0.0.0.0 = все интерфейсы)
ListenIP=0.0.0.0

# Интервал обновления активных проверок (в секундах)
RefreshActiveChecks=120

# Буфер для активных проверок
BufferSend=5
BufferSize=100

# Таймауты
Timeout=3

# Дополнительные параметры пользователя
AllowRoot=0
User=zabbix

# Включение дополнительных конфигураций
Include=/etc/zabbix/zabbix_agentd.d/*.conf

# Небезопасные пользовательские параметры (не рекомендуется в продакшене)
UnsafeUserParameters=0

# Системные параметры
EnableRemoteCommands=0
LogRemoteCommands=0

# Дополнительные пользовательские параметры
UserParameter=custom.disk.discovery,/usr/bin/sudo /bin/ls -1 /sys/block | /bin/grep -E '^[sv]d[a-z]$|^nvme[0-9]+n[0-9]+$' | /usr/bin/awk 'BEGIN{print "{"} {printf "%s{\"{#DEVICENAME}\":\"%s\"}", (NR>1?",":""), \$1} END{print "}"}'
EOF

# Создание директории для дополнительных конфигураций
mkdir -p /etc/zabbix/zabbix_agentd.d

# Настройка прав доступа
chown -R zabbix:zabbix /etc/zabbix/
chmod 640 /etc/zabbix/zabbix_agentd.conf

# Проверка соединения с сервером
echo "Проверка соединения с Zabbix Server..."
if ping -c 3 $ZABBIX_SERVER_IP > /dev/null 2>&1; then
    echo "✓ Ping до сервера успешен"
else
    echo "⚠ Предупреждение: Ping до сервера неуспешен"
fi

if nc -zv $ZABBIX_SERVER_IP 10051 2>/dev/null; then
    echo "✓ Порт 10051 на сервере доступен"
else
    echo "⚠ Предупреждение: Порт 10051 на сервере недоступен"
fi

# Открытие порта в firewall (если используется)
if command -v ufw &> /dev/null; then
    echo "Открытие порта 10050 в UFW..."
    ufw allow 10050/tcp
fi

if command -v iptables &> /dev/null; then
    echo "Открытие порта 10050 в iptables..."
    iptables -I INPUT -p tcp --dport 10050 -j ACCEPT
fi

# Запуск и включение службы
echo "Запуск Zabbix Agent..."
systemctl restart zabbix-agent
systemctl enable zabbix-agent

# Проверка статуса
echo "Проверка статуса службы..."
if systemctl is-active --quiet zabbix-agent; then
    echo "✓ Zabbix Agent запущен успешно"
else
    echo "✗ Ошибка запуска Zabbix Agent"
    systemctl status zabbix-agent
    exit 1
fi

# Тест агента
echo "Тестирование агента..."
if zabbix_agentd -t system.hostname 2>/dev/null; then
    echo "✓ Тест агента успешен"
else
    echo "⚠ Предупреждение: Тест агента неуспешен"
fi

echo "=== Установка завершена! ==="
echo ""
echo "Настройки агента:"
echo "- IP Сервера: $ZABBIX_SERVER_IP"
echo "- Hostname: $HOSTNAME"
echo "- Порт: 10050"
echo ""
echo "Следующие шаги:"
echo "1. Добавьте хост '$HOSTNAME' в веб-интерфейсе Zabbix Server"
echo "2. Используйте шаблон 'Linux by Zabbix agent'"
echo "3. Укажите IP адрес этого хоста: $(hostname -I | awk '{print $1}')"
echo ""
echo "Проверка логов: journalctl -u zabbix-agent -f"