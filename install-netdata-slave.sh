#!/bin/bash

# Скрипт установки и настройки Netdata Slave сервера
# Использование: sudo bash install-netdata-slave.sh HOSTNAME MASTER_IP
# Пример: sudo bash install-netdata-slave.sh HQ-RTR 192.168.1.10

echo "=== Установка Netdata Slave сервера ==="

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root (sudo)"
   exit 1
fi

# Проверка параметров
if [ $# -ne 2 ]; then
    echo "Использование: $0 HOSTNAME MASTER_IP"
    echo "Пример: $0 HQ-RTR 192.168.1.10"
    echo ""
    echo "Доступные имена хостов:"
    echo "  HQ-RTR  - для роутера главного офиса"
    echo "  BR-RTR  - для роутера филиала"
    echo "  BR-SRV  - для сервера филиала"
    exit 1
fi

HOSTNAME=$1
MASTER_IP=$2

echo "Настройка сервера: $HOSTNAME"
echo "Master сервер: $MASTER_IP"

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
apt install curl wget git -y

# Установка Netdata
echo "Установка Netdata..."
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
sh /tmp/netdata-kickstart.sh --stable-channel --dont-wait

# Создание резервной копии конфигурации
echo "Создание резервной копии..."
cp /etc/netdata/netdata.conf /etc/netdata/netdata.conf.backup

# Настройка конфигурации slave сервера
echo "Настройка конфигурации Netdata slave..."
cat > /etc/netdata/netdata.conf << EOF
[global]
    hostname = $HOSTNAME
    bind to = 127.0.0.1
    default port = 19999

[web]
    mode = none

[registry]
    enabled = no

[health]
    enabled = no
EOF

# Настройка streaming конфигурации для отправки данных на master
echo "Настройка отправки данных на master сервер..."
cat > /etc/netdata/stream.conf << EOF
[stream]
    enabled = yes
    destination = $MASTER_IP:19999
    api key = 11111111-2222-3333-4444-555555555555
    timeout seconds = 60
    default port = 19999
    send charts matching = *
    buffer size bytes = 1048576
    reconnect delay seconds = 5
    initial clock resync iterations = 60
EOF

# Установка hostname в системе
echo "Установка hostname..."
hostnamectl set-hostname $HOSTNAME
echo "127.0.0.1 $HOSTNAME" >> /etc/hosts

# Настройка firewall (разрешаем только SSH)
echo "Настройка firewall..."
ufw allow 22/tcp
ufw --force enable

# Запуск и включение службы
echo "Запуск службы Netdata..."
systemctl enable netdata
systemctl restart netdata

# Проверка статуса службы
echo "=== Проверка статуса службы ==="
systemctl status netdata --no-pager -l

# Проверка подключения к master серверу
echo "=== Проверка подключения к master серверу ==="
echo "Проверяем доступность master сервера..."
if nc -z $MASTER_IP 19999; then
    echo "✓ Master сервер $MASTER_IP:19999 доступен"
else
    echo "✗ Master сервер $MASTER_IP:19999 недоступен"
    echo "Проверьте сетевое подключение и настройки firewall на master сервере"
fi

# Проверка логов streaming
echo "=== Проверка логов streaming ==="
sleep 5
tail -20 /var/log/netdata/netdata.log | grep -i stream

echo ""
echo "=== Установка завершена! ==="
echo "Сервер: $HOSTNAME"
echo "Master: $MASTER_IP:19999"
echo "API ключ: 11111111-2222-3333-4444-555555555555"
echo ""
echo "Для проверки логов streaming: tail -f /var/log/netdata/netdata.log | grep stream"
echo "Данные должны появиться в веб-интерфейсе master сервера через 1-2 минуты"