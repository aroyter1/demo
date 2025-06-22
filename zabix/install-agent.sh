#!/bin/bash

# Скрипт установки Zabbix Agent на Debian
# Автоматически проверяет и устанавливает Docker, затем запускает агент

set -e

# Конфигурация по умолчанию
DEFAULT_SERVER_IP="192.168.1.100"  # IP сервера Zabbix
DEFAULT_HOSTNAME="$(hostname)"
DEFAULT_PORT="10050"

echo "=== Установка Zabbix Agent на Debian ==="

# Функция для получения параметров
get_config() {
    echo "Настройка Zabbix Agent:"
    echo ""

    # IP сервера Zabbix
    read -p "IP адрес Zabbix Server [$DEFAULT_SERVER_IP]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-$DEFAULT_SERVER_IP}

    # Имя хоста
    echo "Доступные варианты имен хостов:"
    echo "1. HQ-SRV (Главный сервер)"
    echo "2. HQ-RTR (Главный маршрутизатор)"
    echo "3. BR-SRV (Филиальный сервер)"
    echo "4. BR-RTR (Филиальный маршрутизатор)"
    echo "5. Другое имя"
    echo ""

    read -p "Выберите вариант (1-5) или введите имя хоста [$DEFAULT_HOSTNAME]: " HOSTNAME_CHOICE

    case $HOSTNAME_CHOICE in
        1) HOSTNAME="HQ-SRV" ;;
        2) HOSTNAME="HQ-RTR" ;;
        3) HOSTNAME="BR-SRV" ;;
        4) HOSTNAME="BR-RTR" ;;
        5)
            read -p "Введите имя хоста: " HOSTNAME
            ;;
        "")
            HOSTNAME=$DEFAULT_HOSTNAME
            ;;
        *)
            HOSTNAME=$HOSTNAME_CHOICE
            ;;
    esac

    # Порт агента
    read -p "Порт Zabbix Agent [$DEFAULT_PORT]: " AGENT_PORT
    AGENT_PORT=${AGENT_PORT:-$DEFAULT_PORT}

    echo ""
    echo "Конфигурация:"
    echo "  Zabbix Server: $SERVER_IP"
    echo "  Hostname: $HOSTNAME"
    echo "  Agent Port: $AGENT_PORT"
    echo ""

    read -p "Продолжить? (y/N): " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Установка отменена"
        exit 0
    fi
}

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

# Функция для создания Dockerfile агента
create_agent_dockerfile() {
    echo "Создаем Dockerfile для агента..."

    cat > Dockerfile.agent << 'EOF'
FROM ubuntu:22.04

# Избегаем интерактивного режима
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Moscow

# Переменные окружения для агента (можно переопределить при запуске)
ENV ZBX_HOSTNAME="Agent-Host"
ENV ZBX_SERVER_HOST="zabbix-server"
ENV ZBX_SERVER_PORT="10051"

# Устанавливаем часовой пояс
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Обновляем систему и устанавливаем необходимые пакеты
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    gnupg \
    lsb-release \
    procps \
    net-tools \
    htop \
    iotop \
    sysstat \
    lm-sensors \
    smartmontools \
    && rm -rf /var/lib/apt/lists/*

# Добавляем репозиторий Zabbix
RUN wget https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb \
    && dpkg -i zabbix-release_6.4-1+ubuntu22.04_all.deb \
    && apt-get update

# Устанавливаем Zabbix Agent
RUN apt-get install -y zabbix-agent \
    && rm -rf /var/lib/apt/lists/*

# Создаем скрипт инициализации
RUN cat > /init.sh << 'SCRIPT_EOF'
#!/bin/bash

# Создаем конфигурацию агента
cat > /etc/zabbix/zabbix_agentd.conf << AGENT_EOF
# Базовые настройки
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0
DebugLevel=3

# Настройки сервера
Server=${ZBX_SERVER_HOST}
ServerActive=${ZBX_SERVER_HOST}:${ZBX_SERVER_PORT}
Hostname=${ZBX_HOSTNAME}

# Настройки производительности
StartAgents=3
RefreshActiveChecks=120
BufferSend=5
BufferSize=100

# Настройки timeout
Timeout=3

# Безопасность
AllowRoot=0

# Пользовательские параметры
UserParameter=custom.cpu.util,cat /proc/loadavg | awk '{print \$1}'
UserParameter=custom.memory.used,free | grep Mem | awk '{printf "%.2f", \$3/\$2 * 100.0}'
UserParameter=custom.disk.used[*],df -h \$1 | tail -1 | awk '{print \$5}' | sed 's/%//'
UserParameter=custom.network.bytes.in[*],cat /proc/net/dev | grep \$1 | awk '{print \$2}'
UserParameter=custom.network.bytes.out[*],cat /proc/net/dev | grep \$1 | awk '{print \$10}'

# Включаем дополнительные файлы конфигурации
Include=/etc/zabbix/zabbix_agentd.d/*.conf
AGENT_EOF

# Создаем директории для Zabbix Agent
mkdir -p /var/run/zabbix
mkdir -p /var/log/zabbix
chown zabbix:zabbix /var/run/zabbix
chown zabbix:zabbix /var/log/zabbix

echo "=== Запуск Zabbix Agent ==="
echo "Hostname: ${ZBX_HOSTNAME}"
echo "Server: ${ZBX_SERVER_HOST}:${ZBX_SERVER_PORT}"

# Запускаем Zabbix Agent
service zabbix-agent start

# Показываем статус
sleep 2
service zabbix-agent status

# Бесконечный цикл для поддержания контейнера
tail -f /var/log/zabbix/zabbix_agentd.log
SCRIPT_EOF

# Делаем скрипт исполняемым
RUN chmod +x /init.sh

# Создаем пользователя zabbix
RUN useradd --system --shell /bin/false zabbix

# Открываем порт для агента
EXPOSE 10050

# Запускаем инициализацию
CMD ["/init.sh"]
EOF

    echo "✓ Dockerfile создан"
}

# Функция для запуска Zabbix Agent
start_zabbix_agent() {
    echo "Запускаем Zabbix Agent..."

    # Останавливаем существующий контейнер если есть
    CONTAINER_NAME="zabbix-agent-$(echo $HOSTNAME | tr '[:upper:]' '[:lower:]' | tr '-' '_')"

    if docker ps -a | grep -q $CONTAINER_NAME; then
        echo "Останавливаем существующий контейнер..."
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
    fi

    # Создаем образ если его нет
    if ! docker images | grep -q zabbix-agent-custom; then
        echo "Создаем Docker образ..."
        docker build -f Dockerfile.agent -t zabbix-agent-custom .
    fi

    # Запускаем контейнер
    docker run -d \
        --name $CONTAINER_NAME \
        --restart unless-stopped \
        -p $AGENT_PORT:10050 \
        -e ZBX_HOSTNAME="$HOSTNAME" \
        -e ZBX_SERVER_HOST="$SERVER_IP" \
        -e ZBX_SERVER_PORT="10051" \
        --privileged \
        -v /proc:/host/proc:ro \
        -v /sys:/host/sys:ro \
        -v /dev:/host/dev:ro \
        zabbix-agent-custom

    echo "✓ Zabbix Agent запущен"
    echo "Контейнер: $CONTAINER_NAME"
}

# Функция для отображения информации о настройке
show_setup_info() {
    echo ""
    echo "=== Информация для настройки в Zabbix ==="
    echo "Добавьте этот хост в веб-интерфейсе Zabbix:"
    echo ""
    echo "Host name: $HOSTNAME"
    echo "Visible name: $HOSTNAME"
    echo "Groups: Linux servers"
    echo "Interfaces:"
    echo "  Type: Agent"
    echo "  IP address: $(hostname -I | awk '{print $1}')"
    echo "  Port: $AGENT_PORT"
    echo ""
    echo "Шаблоны для добавления:"
    echo "  - Linux by Zabbix agent"
    echo "  - Template Module Linux CPU by Zabbix agent"
    echo "  - Template Module Linux memory by Zabbix agent"
    echo "  - Template Module Linux filesystems by Zabbix agent"
    echo ""
    echo "Полезные команды:"
    echo "  Логи: docker logs -f $CONTAINER_NAME"
    echo "  Остановка: docker stop $CONTAINER_NAME"
    echo "  Перезапуск: docker restart $CONTAINER_NAME"
}

# Основная логика
main() {
    # Проверяем права root для установки
    if [[ $EUID -eq 0 ]]; then
        echo "Не запускайте скрипт от root. Используйте sudo при необходимости."
        exit 1
    fi

    # Получаем конфигурацию
    get_config

    # Проверяем наличие Docker
    if ! check_docker; then
        echo "Устанавливаем Docker..."
        install_docker
        echo "Перезайдите в систему или выполните: newgrp docker"
        echo "Затем запустите скрипт снова."
        exit 0
    fi

    # Создаем Dockerfile если его нет
    if [[ ! -f "Dockerfile.agent" ]]; then
        create_agent_dockerfile
    fi

    # Запускаем Zabbix Agent
    start_zabbix_agent

    # Ждем запуска
    echo "Ждем запуска агента..."
    sleep 5

    # Проверяем статус
    CONTAINER_NAME="zabbix-agent-$(echo $HOSTNAME | tr '[:upper:]' '[:lower:]' | tr '-' '_')"
    if docker ps | grep -q $CONTAINER_NAME; then
        echo "✓ Zabbix Agent успешно запущен"
        show_setup_info
    else
        echo "✗ Ошибка запуска Zabbix Agent"
        echo "Проверьте логи: docker logs $CONTAINER_NAME"
        exit 1
    fi
}

# Запускаем основную функцию
main "$@"