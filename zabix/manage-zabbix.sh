#!/bin/bash

# Главный скрипт управления системой Zabbix
# Предоставляет единый интерфейс для управления сервером и агентами

set -e

echo "=== Система мониторинга Zabbix для Debian ==="
echo ""

# Функция для отображения статуса контейнеров
show_status() {
    echo "=== Статус контейнеров ==="
    echo ""

    if command -v docker &> /dev/null; then
        echo "Сервер Zabbix:"
        if docker ps | grep -q zabbix-server; then
            echo "  ✓ Zabbix Server - ЗАПУЩЕН"
            SERVER_IP=$(docker inspect zabbix-server | grep '"IPAddress"' | head -1 | awk '{print $2}' | tr -d '",' || echo "localhost")
            echo "    Веб-интерфейс: http://$SERVER_IP/zabbix"
        else
            echo "  ✗ Zabbix Server - НЕ ЗАПУЩЕН"
        fi

        echo ""
        echo "Агенты Zabbix:"

        for agent in zabbix-agent-hq_srv zabbix-agent-hq_rtr zabbix-agent-br_srv zabbix-agent-br_rtr; do
            if docker ps | grep -q $agent; then
                echo "  ✓ $agent - ЗАПУЩЕН"
            else
                echo "  ✗ $agent - НЕ ЗАПУЩЕН"
            fi
        done

        echo ""
        echo "Используемые порты:"
        docker ps --format "table {{.Names}}\t{{.Ports}}" | grep zabbix || echo "  Нет запущенных контейнеров Zabbix"
    else
        echo "Docker не установлен"
    fi
    echo ""
}

# Функция для остановки всех контейнеров
stop_all() {
    echo "Останавливаем все контейнеры Zabbix..."

    # Останавливаем сервер
    if docker ps | grep -q zabbix-server; then
        docker stop zabbix-server
        echo "✓ Zabbix Server остановлен"
    fi

    # Останавливаем агентов
    for agent in zabbix-agent-hq_srv zabbix-agent-hq_rtr zabbix-agent-br_srv zabbix-agent-br_rtr; do
        if docker ps | grep -q $agent; then
            docker stop $agent
            echo "✓ $agent остановлен"
        fi
    done

    echo "Все контейнеры остановлены"
}

# Функция для удаления всех контейнеров
remove_all() {
    echo "Удаляем все контейнеры Zabbix..."

    # Останавливаем сначала
    stop_all

    # Удаляем контейнеры
    docker rm zabbix-server 2>/dev/null || true
    docker rm zabbix-agent-hq_srv 2>/dev/null || true
    docker rm zabbix-agent-hq_rtr 2>/dev/null || true
    docker rm zabbix-agent-br_srv 2>/dev/null || true
    docker rm zabbix-agent-br_rtr 2>/dev/null || true

    echo "Все контейнеры удалены"

    read -p "Удалить также Docker образы? (y/N): " REMOVE_IMAGES
    if [[ $REMOVE_IMAGES =~ ^[Yy]$ ]]; then
        docker rmi zabbix-server-custom 2>/dev/null || true
        docker rmi zabbix-agent-custom 2>/dev/null || true
        echo "Образы удалены"
    fi
}

# Функция для показа логов
show_logs() {
    echo "Доступные контейнеры для просмотра логов:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep zabbix
    echo ""

    read -p "Введите имя контейнера: " CONTAINER_NAME
    if docker ps | grep -q $CONTAINER_NAME; then
        echo "Показываем логи $CONTAINER_NAME (Ctrl+C для выхода):"
        docker logs -f $CONTAINER_NAME
    else
        echo "Контейнер $CONTAINER_NAME не найден или не запущен"
    fi
}

# Функция для перезапуска контейнеров
restart_all() {
    echo "Перезапускаем все контейнеры Zabbix..."

    # Перезапускаем сервер
    if docker ps -a | grep -q zabbix-server; then
        docker restart zabbix-server
        echo "✓ Zabbix Server перезапущен"
    fi

    # Перезапускаем агентов
    for agent in zabbix-agent-hq_srv zabbix-agent-hq_rtr zabbix-agent-br_srv zabbix-agent-br_rtr; do
        if docker ps -a | grep -q $agent; then
            docker restart $agent
            echo "✓ $agent перезапущен"
        fi
    done

    echo "Все контейнеры перезапущены"
}

# Функция для обновления системы
update_system() {
    echo "Обновляем систему Zabbix..."

    # Останавливаем контейнеры
    stop_all

    # Удаляем старые образы
    docker rmi zabbix-server-custom 2>/dev/null || true
    docker rmi zabbix-agent-custom 2>/dev/null || true

    # Пересобираем образы
    if [[ -f "Dockerfile.server" ]]; then
        echo "Пересобираем образ сервера..."
        docker build -f Dockerfile.server -t zabbix-server-custom .
    fi

    if [[ -f "Dockerfile.agent" ]]; then
        echo "Пересобираем образ агента..."
        docker build -f Dockerfile.agent -t zabbix-agent-custom .
    fi

    echo "Система обновлена. Запустите контейнеры заново."
}

# Главное меню
show_menu() {
    echo "=========================================="
    echo "        УПРАВЛЕНИЕ ZABBIX СИСТЕМОЙ"
    echo "=========================================="
    echo ""
    echo "1. Показать статус"
    echo "2. Установить Zabbix Server"
    echo "3. Установить Zabbix Agent"
    echo "4. Настройка хостов (помощник)"
    echo "5. Показать логи"
    echo "6. Перезапустить все"
    echo "7. Остановить все"
    echo "8. Удалить все"
    echo "9. Обновить систему"
    echo "0. Выход"
    echo ""
}

# Основная логика
main() {
    while true; do
        show_menu
        read -p "Выберите действие (0-9): " CHOICE
        echo ""

        case $CHOICE in
            1)
                show_status
                read -p "Нажмите Enter для продолжения..."
                ;;
            2)
                if [[ -f "install-server.sh" ]]; then
                    chmod +x install-server.sh
                    ./install-server.sh
                else
                    echo "Файл install-server.sh не найден"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            3)
                if [[ -f "install-agent.sh" ]]; then
                    chmod +x install-agent.sh
                    ./install-agent.sh
                else
                    echo "Файл install-agent.sh не найден"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            4)
                if [[ -f "setup-hosts.sh" ]]; then
                    chmod +x setup-hosts.sh
                    ./setup-hosts.sh
                else
                    echo "Файл setup-hosts.sh не найден"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            5)
                show_logs
                ;;
            6)
                restart_all
                read -p "Нажмите Enter для продолжения..."
                ;;
            7)
                stop_all
                read -p "Нажмите Enter для продолжения..."
                ;;
            8)
                echo "ВНИМАНИЕ! Это удалит все контейнеры и данные!"
                read -p "Вы уверены? (yes/no): " CONFIRM
                if [[ $CONFIRM == "yes" ]]; then
                    remove_all
                else
                    echo "Отменено"
                fi
                read -p "Нажмите Enter для продолжения..."
                ;;
            9)
                update_system
                read -p "Нажмите Enter для продолжения..."
                ;;
            0)
                echo "До свидания!"
                exit 0
                ;;
            *)
                echo "Неверный выбор. Попробуйте снова."
                ;;
        esac

        clear
    done
}

# Проверяем наличие Docker
if ! command -v docker &> /dev/null; then
    echo "Docker не установлен. Сначала установите Docker или запустите install-server.sh/install-agent.sh"
    exit 1
fi

# Запускаем главное меню
clear
main