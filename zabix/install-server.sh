#!/bin/bash

# Скрипт установки Zabbix Server на Debian
# Автоматически проверяет и устанавливает Docker, затем запускает сервер

set -e

echo "=== Установка Zabbix Server на Debian ==="
echo "Проверяем наличие Docker..."

# Функция для проверки установки Docker
check_docker() {
    if command -v docker &> /dev/null; then
        echo "✓ Docker уже установлен"
        docker --version
        return 0
    else
        echo "✗ Docker не установлен"
        return 1
    fi
}

# Функция для установки Docker
install_docker() {
    echo "Устанавливаем Docker..."

    # Обновляем систему
    sudo apt-get update

    # Устанавливаем зависимости
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Добавляем официальный GPG ключ Docker
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Добавляем репозиторий Docker
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Обновляем индекс пакетов
    sudo apt-get update

    # Устанавливаем Docker Engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Добавляем текущего пользователя в группу docker
    sudo usermod -aG docker $USER

    # Запускаем и включаем Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    echo "✓ Docker успешно установлен"
}

# Функция для запуска Zabbix Server
start_zabbix_server() {
    echo "Запускаем Zabbix Server..."

    # Останавливаем существующий контейнер если есть
    if docker ps -a | grep -q zabbix-server; then
        echo "Останавливаем существующий контейнер..."
        docker stop zabbix-server 2>/dev/null || true
        docker rm zabbix-server 2>/dev/null || true
    fi

    # Создаем образ если его нет
    if ! docker images | grep -q zabbix-server-custom; then
        echo "Создаем Docker образ..."
        docker build -f Dockerfile.server -t zabbix-server-custom .
    fi

    # Запускаем контейнер
    docker run -d \
        --name zabbix-server \
        --restart unless-stopped \
        -p 80:80 \
        -p 443:443 \
        -p 10051:10051 \
        -v zabbix-data:/var/lib/mysql \
        -v zabbix-logs:/var/log/zabbix \
        zabbix-server-custom

    echo "✓ Zabbix Server запущен"
}

# Функция для отображения информации о доступе
show_access_info() {
    echo ""
    echo "=== Информация о доступе ==="
    echo "Веб-интерфейс Zabbix:"
    echo "  HTTP:  http://$(hostname -I | awk '{print $1}')/zabbix"
    echo "  HTTP:  http://localhost/zabbix"
    echo ""
    echo "Логин: Admin"
    echo "Пароль: P@ssw0rd"
    echo ""
    echo "Для настройки DNS добавьте в /etc/hosts:"
    echo "$(hostname -I | awk '{print $1}') mon.au-team.irpo"
    echo ""
    echo "Порты:"
    echo "  80, 443 - Веб-интерфейс"
    echo "  10051   - Zabbix Server"
    echo ""
    echo "Для просмотра логов: docker logs -f zabbix-server"
    echo "Для остановки: docker stop zabbix-server"
}

# Основная логика
main() {
    # Проверяем права root для установки
    if [[ $EUID -eq 0 ]]; then
        echo "Не запускайте скрипт от root. Используйте sudo при необходимости."
        exit 1
    fi

    # Проверяем наличие Docker
    if ! check_docker; then
        echo "Устанавливаем Docker..."
        install_docker
        echo "Перезайдите в систему или выполните: newgrp docker"
        echo "Затем запустите скрипт снова."
        exit 0
    fi

    # Проверяем наличие Dockerfile
    if [[ ! -f "Dockerfile.server" ]]; then
        echo "Ошибка: Файл Dockerfile.server не найден"
        echo "Убедитесь что вы находитесь в папке с проектом"
        exit 1
    fi

    # Запускаем Zabbix Server
    start_zabbix_server

    # Ждем запуска
    echo "Ждем запуска сервера..."
    sleep 10

    # Проверяем статус
    if docker ps | grep -q zabbix-server; then
        echo "✓ Zabbix Server успешно запущен"
        show_access_info
    else
        echo "✗ Ошибка запуска Zabbix Server"
        echo "Проверьте логи: docker logs zabbix-server"
        exit 1
    fi
}

# Запускаем основную функцию
main "$@"