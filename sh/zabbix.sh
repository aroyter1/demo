#!/bin/bash

# Скрипт для исправления проблем с репозиторием Zabbix
# Используйте этот скрипт если основной скрипт не работает

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    print_error "Запустите скрипт с правами root: sudo $0"
    exit 1
fi

print_status "Исправление проблем с репозиторием Zabbix..."

# Очистка старых ключей и репозиториев
print_status "Очистка старых настроек..."
rm -f /etc/apt/sources.list.d/*zabbix*
rm -f /tmp/zabbix-release.deb

# Обновление системы
print_status "Обновление системы..."
apt update
apt install -y wget curl gnupg2 ca-certificates

# Определение версии Debian
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DEBIAN_VERSION=$VERSION_ID
    print_status "Версия Debian: $DEBIAN_VERSION"
else
    print_error "Не удалось определить версию Debian"
    exit 1
fi

# Попытка 1: Официальный репозиторий с новым ключом
print_status "Попытка 1: Добавление GPG ключа через keyring..."
if wget -qO - https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-A14FE591 | gpg --dearmor | tee /usr/share/keyrings/zabbix-archive-keyring.gpg > /dev/null 2>&1; then
    print_success "GPG ключ добавлен через keyring"

    # Добавляем репозиторий с новым ключом
    echo "deb [signed-by=/usr/share/keyrings/zabbix-archive-keyring.gpg] https://repo.zabbix.com/zabbix/6.4/debian bookworm main" > /etc/apt/sources.list.d/zabbix.list

    if apt update; then
        print_success "Репозиторий добавлен успешно"
        exit 0
    fi
fi

# Попытка 2: Старый способ через apt-key
print_status "Попытка 2: Добавление ключа через apt-key..."
if wget -qO - https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-A14FE591 | apt-key add - 2>/dev/null; then
    print_success "GPG ключ добавлен через apt-key"

    # Скачиваем пакет репозитория
    case $DEBIAN_VERSION in
        "12")
            REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian12_all.deb"
            ;;
        "11")
            REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
            ;;
        "10")
            REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian10_all.deb"
            ;;
        *)
            REPO_URL="https://repo.zabbix.com/zabbix/6.4/debian/pool/main/z/zabbix-release/zabbix-release_6.4-1+debian11_all.deb"
            ;;
    esac

    if wget "$REPO_URL" -O /tmp/zabbix-release.deb && dpkg -i /tmp/zabbix-release.deb; then
        if apt update; then
            print_success "Репозиторий добавлен успешно"
            exit 0
        fi
    fi
fi

# Попытка 3: Альтернативный репозиторий
print_status "Попытка 3: Использование альтернативного репозитория..."
cat > /etc/apt/sources.list.d/zabbix.list <<EOF
# Альтернативный репозиторий Zabbix
deb https://repo.zabbix.com/zabbix/6.0/debian bookworm main
EOF

apt update --allow-insecure-repositories
if apt update; then
    print_success "Альтернативный репозиторий работает"
    exit 0
fi

# Попытка 4: Ручная установка
print_status "Попытка 4: Ручная установка пакетов..."
print_status "Все автоматические методы не работают."
print_status "Рекомендации:"
echo "1. Проверьте подключение к интернету"
echo "2. Попробуйте использовать VPN"
echo "3. Проверьте настройки DNS"
echo "4. Обратитесь к системному администратору"

print_error "Не удалось настроить репозиторий Zabbix"
exit 1