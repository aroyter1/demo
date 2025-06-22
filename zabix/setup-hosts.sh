#!/bin/bash

# Скрипт-помощник для настройки хостов в Zabbix
# Показывает информацию о том, как добавить хосты в веб-интерфейс

echo "=== Настройка хостов в Zabbix ==="
echo ""

# Функция для отображения информации о хосте
show_host_info() {
    local hostname=$1
    local ip=$2
    local description=$3

    echo "=== $hostname ==="
    echo "Описание: $description"
    echo "Host name: $hostname"
    echo "Visible name: $hostname"
    echo "Groups: Linux servers"
    echo "Interfaces:"
    echo "  Type: Agent"
    echo "  IP address: $ip"
    echo "  Port: 10050"
    echo "Шаблоны:"
    echo "  - Linux by Zabbix agent"
    echo "  - Template Module Linux CPU by Zabbix agent"
    echo "  - Template Module Linux memory by Zabbix agent"
    echo "  - Template Module Linux filesystems by Zabbix agent"
    echo ""
}

echo "Инструкция по добавлению хостов в Zabbix:"
echo ""
echo "1. Откройте веб-интерфейс Zabbix: http://IP_СЕРВЕРА/zabbix"
echo "2. Войдите под учетными данными: Admin / P@ssw0rd"
echo "3. Перейдите в Configuration → Hosts"
echo "4. Нажмите 'Create host'"
echo "5. Заполните данные для каждого хоста:"
echo ""

# Запрашиваем IP адреса хостов
echo "Введите IP адреса ваших хостов:"
echo ""

read -p "IP адрес HQ-SRV [192.168.1.101]: " HQ_SRV_IP
HQ_SRV_IP=${HQ_SRV_IP:-192.168.1.101}

read -p "IP адрес HQ-RTR [192.168.1.102]: " HQ_RTR_IP
HQ_RTR_IP=${HQ_RTR_IP:-192.168.1.102}

read -p "IP адрес BR-SRV [192.168.1.103]: " BR_SRV_IP
BR_SRV_IP=${BR_SRV_IP:-192.168.1.103}

read -p "IP адрес BR-RTR [192.168.1.104]: " BR_RTR_IP
BR_RTR_IP=${BR_RTR_IP:-192.168.1.104}

echo ""
echo "=========================================="
echo "ИНФОРМАЦИЯ ДЛЯ ДОБАВЛЕНИЯ ХОСТОВ"
echo "=========================================="
echo ""

show_host_info "HQ-SRV" "$HQ_SRV_IP" "Главный сервер"
show_host_info "HQ-RTR" "$HQ_RTR_IP" "Главный маршрутизатор"
show_host_info "BR-SRV" "$BR_SRV_IP" "Филиальный сервер"
show_host_info "BR-RTR" "$BR_RTR_IP" "Филиальный маршрутизатор"

echo "=========================================="
echo "ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ"
echo "=========================================="
echo ""
echo "Для создания дашборда:"
echo "1. Перейдите в Monitoring → Dashboard"
echo "2. Нажмите 'Edit dashboard'"
echo "3. Добавьте виджеты:"
echo "   - Graph (CPU utilization)"
echo "   - Graph (Memory utilization)"
echo "   - Graph (Disk space usage)"
echo "   - Problems (Current problems)"
echo ""

echo "Для настройки уведомлений:"
echo "1. Перейдите в Administration → Media types"
echo "2. Настройте Email, SMS или другие способы уведомлений"
echo "3. Перейдите в Administration → Users"
echo "4. Добавьте контакты пользователям"
echo "5. Настройте Actions в Configuration → Actions"
echo ""

echo "Полезные команды для проверки агентов:"
echo "  docker ps | grep zabbix-agent"
echo "  docker logs -f zabbix-agent-hq_srv"
echo "  docker logs -f zabbix-agent-hq_rtr"
echo "  docker logs -f zabbix-agent-br_srv"
echo "  docker logs -f zabbix-agent-br_rtr"
echo ""

# Создаем файл с конфигурацией для сохранения
cat > hosts-config.txt << EOF
=== Конфигурация хостов Zabbix ===

HQ-SRV:
- IP: $HQ_SRV_IP
- Port: 10050
- Description: Главный сервер

HQ-RTR:
- IP: $HQ_RTR_IP
- Port: 10050
- Description: Главный маршрутизатор

BR-SRV:
- IP: $BR_SRV_IP
- Port: 10050
- Description: Филиальный сервер

BR-RTR:
- IP: $BR_RTR_IP
- Port: 10050
- Description: Филиальный маршрутизатор

Шаблоны для всех хостов:
- Linux by Zabbix agent
- Template Module Linux CPU by Zabbix agent
- Template Module Linux memory by Zabbix agent
- Template Module Linux filesystems by Zabbix agent

Дата создания: $(date)
EOF

echo "Конфигурация сохранена в файл: hosts-config.txt"
echo ""
echo "Готово! Используйте эту информацию для добавления хостов в Zabbix."