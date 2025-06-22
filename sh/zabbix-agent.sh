#!/bin/bash

# Скрипт автоматической установки Zabbix Agent
# Версия: 1.0
# Поддерживаемые системы: Debian 10/11/12, Ubuntu 18.04/20.04/22.04

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация по умолчанию
DEFAULT_ZABBIX_SERVER="mon.au-team.irpo"
DEFAULT_ZABBIX_SERVER_IP=""
DEFAULT_HOSTNAME=""
DEFAULT_HOST_METADATA="Linux"

# Функции для вывода сообщений
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Функция помощи
show_help() {
    cat << EOF
Скрипт установки Zabbix Agent

Использование: $0 [ОПЦИИ]

ОПЦИИ:
    -s, --server СЕРВЕР         IP или домен Zabbix сервера (по умолчанию: $DEFAULT_ZABBIX_SERVER)
    -h, --hostname ИМЯ_ХОСТА    Имя хоста для агента (по умолчанию: hostname системы)
    -m, --metadata МЕТАДАННЫЕ   Метаданные хоста (по умолчанию: $DEFAULT_HOST_METADATA)
    -p, --passive-only          Только пассивные проверки (по умолчанию: активные + пассивные)
    --help                      Показать эту справку

Примеры:
    $0                                          # Установка с параметрами по умолчанию
    $0 -s 192.168.1.100                        # Указать IP сервера Zabbix
    $0 -s zabbix.company.com -h web-server-01  # Указать домен сервера и имя хоста
    $0 -m "Linux Web Server" -h nginx-01       # Указать метаданные и имя хоста

EOF
}

# Парсинг аргументов командной строки
parse_arguments() {
    ZABBIX_SERVER="$DEFAULT_ZABBIX_SERVER"
    HOSTNAME="$DEFAULT_HOSTNAME"
    HOST_METADATA="$DEFAULT_HOST_METADATA"
    PASSIVE_ONLY=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server)
                ZABBIX_SERVER="$2"
                shift 2
                ;;
            -h|--hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            -m|--metadata)
                HOST_METADATA="$2"
                shift 2
                ;;
            -p|--passive-only)
                PASSIVE_ONLY=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Если hostname не указан, используем системное имя
    if [[ -z "$HOSTNAME" ]]; then
        HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    fi
}

# Проверка прав суперпользователя
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Определение операционной системы
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        print_status "Обнаружена система: $PRETTY_NAME"
    else
        print_error "Не удалось определить операционную систему"
        exit 1
    fi
}

# Обновление системы
update_system() {
    print_status "Обновление системы..."

    case $OS in
        debian|ubuntu)
            apt update
            apt install -y wget curl gnupg2 ca-certificates
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf update -y
                dnf install -y wget curl gnupg2 ca-certificates
            else
                yum update -y
                yum install -y wget curl ca-certificates
            fi
            ;;
        *)
            print_error "Неподдерживаемая операционная система: $OS"
            exit 1
            ;;
    esac
}

# Добавление репозитория Zabbix
add_zabbix_repository() {
    print_status "Добавление репозитория Zabbix..."

    case $OS in
        debian)
            case $OS_VERSION in
                "10")
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian10_all.deb"
                    ;;
                "11")
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
                    ;;
                "12")
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian12_all.deb"
                    ;;
                *)
                    print_warning "Неизвестная версия Debian, используется репозиторий для Debian 11"
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
                    ;;
            esac
            wget $REPO_URL -O /tmp/zabbix-release.deb
            dpkg -i /tmp/zabbix-release.deb
            apt update
            ;;
        ubuntu)
            case $OS_VERSION in
                "18.04")
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu18.04_all.deb"
                    ;;
                "20.04")
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu20.04_all.deb"
                    ;;
                "22.04")
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb"
                    ;;
                *)
                    print_warning "Неизвестная версия Ubuntu, используется репозиторий для Ubuntu 20.04"
                    REPO_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu20.04_all.deb"
                    ;;
            esac
            wget $REPO_URL -O /tmp/zabbix-release.deb
            dpkg -i /tmp/zabbix-release.deb
            apt update
            ;;
        centos|rhel)
            if [[ "$OS_VERSION" == "7" ]]; then
                rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/7/x86_64/zabbix-release-6.4-1.el7.noarch.rpm
            elif [[ "$OS_VERSION" == "8" ]]; then
                rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/8/x86_64/zabbix-release-6.4-1.el8.noarch.rpm
            elif [[ "$OS_VERSION" == "9" ]]; then
                rpm -Uvh https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm
            fi
            ;;
    esac

    print_success "Репозиторий Zabbix добавлен"
}

# Установка Zabbix Agent
install_zabbix_agent() {
    print_status "Установка Zabbix Agent..."

    case $OS in
        debian|ubuntu)
            apt install -y zabbix-agent
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y zabbix-agent
            else
                yum install -y zabbix-agent
            fi
            ;;
    esac

    print_success "Zabbix Agent установлен"
}

# Настройка Zabbix Agent
configure_zabbix_agent() {
    print_status "Настройка Zabbix Agent..."

    # Создание резервной копии оригинального конфига
    cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.backup

    # Основные настройки
    sed -i "s/^Server=.*/Server=$ZABBIX_SERVER/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" /etc/zabbix/zabbix_agentd.conf

    if [[ "$PASSIVE_ONLY" == "false" ]]; then
        sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER/" /etc/zabbix/zabbix_agentd.conf
        sed -i "s/^# HostMetadata=.*/HostMetadata=$HOST_METADATA/" /etc/zabbix/zabbix_agentd.conf
    else
        sed -i "s/^ServerActive=.*/# ServerActive=/" /etc/zabbix/zabbix_agentd.conf
    fi

    # Дополнительные настройки безопасности и производительности
    sed -i "s/^# EnableRemoteCommands=.*/EnableRemoteCommands=0/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^# LogRemoteCommands=.*/LogRemoteCommands=1/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^# Timeout=.*/Timeout=30/" /etc/zabbix/zabbix_agentd.conf

    print_success "Zabbix Agent настроен"
}

# Настройка файрвола
configure_firewall() {
    print_status "Настройка файрвола для Zabbix Agent..."

    if command -v ufw &> /dev/null; then
        ufw allow 10050/tcp
        print_success "Правило UFW добавлено (порт 10050)"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=10050/tcp
        firewall-cmd --reload
        print_success "Правила firewalld добавлены"
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport 10050 -j ACCEPT
        print_warning "Правило iptables добавлено, но может быть сброшено при перезагрузке"
    fi
}

# Запуск и включение сервиса
start_service() {
    print_status "Запуск и включение службы Zabbix Agent..."

    systemctl enable zabbix-agent
    systemctl start zabbix-agent

    # Проверка статуса
    if systemctl is-active --quiet zabbix-agent; then
        print_success "Служба Zabbix Agent запущена"
    else
        print_error "Ошибка запуска службы Zabbix Agent"
        systemctl status zabbix-agent
        exit 1
    fi
}

# Проверка подключения к серверу
test_connection() {
    print_status "Проверка подключения к Zabbix серверу..."

    # Попытка подключения к серверу на порт 10051
    if timeout 5 bash -c "</dev/tcp/$ZABBIX_SERVER/10051"; then
        print_success "Подключение к серверу $ZABBIX_SERVER:10051 успешно"
    else
        print_warning "Не удалось подключиться к серверу $ZABBIX_SERVER:10051"
        print_warning "Убедитесь, что сервер доступен и файрвол настроен правильно"
    fi
}

# Вывод информации об установке
print_installation_info() {
    print_success "╔══════════════════════════════════════════════════════════════╗"
    print_success "║                УСТАНОВКА ZABBIX AGENT ЗАВЕРШЕНА              ║"
    print_success "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    print_status "Конфигурация агента:"
    print_status "Сервер Zabbix: $ZABBIX_SERVER"
    print_status "Имя хоста: $HOSTNAME"
    print_status "Метаданные: $HOST_METADATA"
    print_status "Режим: $(if [[ "$PASSIVE_ONLY" == "true" ]]; then echo "Только пассивные проверки"; else echo "Активные + пассивные проверки"; fi)"
    echo ""
    print_status "Файлы конфигурации:"
    print_status "Основной: /etc/zabbix/zabbix_agentd.conf"
    print_status "Резервная копия: /etc/zabbix/zabbix_agentd.conf.backup"
    echo ""
    print_status "Полезные команды:"
    print_status "Статус службы: systemctl status zabbix-agent"
    print_status "Перезапуск: systemctl restart zabbix-agent"
    print_status "Логи: tail -f /var/log/zabbix/zabbix_agentd.log"
    print_status "Тест конфигурации: zabbix_agentd -t"
    echo ""
    print_warning "Следующие шаги:"
    print_warning "1. Добавьте хост в веб-интерфейсе Zabbix: http://mon.au-team.irpo"
    print_warning "2. Используйте имя хоста: $HOSTNAME"
    print_warning "3. Укажите IP адрес этого хоста: $(hostname -I | awk '{print $1}')"
}

# Основная функция
main() {
    parse_arguments "$@"

    print_status "╔══════════════════════════════════════════════════════════════╗"
    print_status "║              УСТАНОВКА ZABBIX AGENT                         ║"
    print_status "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    print_status "Параметры установки:"
    print_status "Сервер: $ZABBIX_SERVER"
    print_status "Имя хоста: $HOSTNAME"
    print_status "Метаданные: $HOST_METADATA"
    echo ""

    check_root
    detect_os
    update_system
    add_zabbix_repository
    install_zabbix_agent
    configure_zabbix_agent
    configure_firewall
    start_service
    test_connection
    print_installation_info

    print_success "Установка Zabbix Agent завершена успешно!"
}

# Запуск основной функции
main "$@"