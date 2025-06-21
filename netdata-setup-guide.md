# Инструкция по настройке мониторинга Netdata

## Обзор решения

**Выбранное ПО:** Netdata
**Обоснование выбора:**

- Открытое программное обеспечение (GPL v3+)
- Низкое потребление ресурсов
- Встроенная поддержка master-slave архитектуры
- Веб-интерфейс в реальном времени
- Простота настройки и развертывания
- Поддержка множества метрик из коробки

**Архитектура:**

- Master сервер: HQ-SRV (порт 19999)
- Slave серверы: HQ-RTR, BR-RTR, BR-SRV
- Веб-доступ: http://mon.au-team.irpo через nginx reverse proxy

## 1. Настройка Master сервера (HQ-SRV)

### 1.1 Установка Netdata

```bash
# Обновляем систему
sudo apt update && sudo apt upgrade -y

# Устанавливаем необходимые пакеты
sudo apt install curl wget git -y

# Загружаем и запускаем скрипт установки Netdata
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
sudo sh /tmp/netdata-kickstart.sh --stable-channel --dont-wait

# Проверяем статус службы
sudo systemctl status netdata
```

### 1.2 Настройка конфигурации Master сервера

```bash
# Создаем резервную копию конфигурации
sudo cp /etc/netdata/netdata.conf /etc/netdata/netdata.conf.backup

# Редактируем основную конфигурацию
sudo nano /etc/netdata/netdata.conf
```

Добавить в файл `/etc/netdata/netdata.conf`:

```ini
[global]
    # Настройки master сервера
    bind to = 0.0.0.0
    default port = 19999

    # Настройки памяти и производительности
    memory mode = dbengine
    page cache size = 32
    dbengine disk space = 256

    # Включаем веб-интерфейс
    web files owner = netdata
    web files group = netdata

[web]
    # Настройки веб-интерфейса
    allow connections from = localhost 127.0.0.1 10.* 192.168.*
    allow dashboard from = localhost 127.0.0.1 10.* 192.168.*
    allow badges from = *
    allow streaming from = *

    # Базовая аутентификация
    enable basic auth = yes

[registry]
    # Включаем реестр для централизованного управления
    enabled = yes
    registry to announce = http://HQ-SRV:19999
    registry hostname = HQ-SRV

[health]
    # Настройки алертов
    enabled = yes
    default repeat warning = never
    default repeat critical = never
```

### 1.3 Настройка аутентификации

```bash
# Устанавливаем apache2-utils для htpasswd
sudo apt install apache2-utils -y

# Создаем файл паролей
sudo htpasswd -c /etc/netdata/netdata.passwd admin

# Вводим пароль: P@ssw0rd

# Устанавливаем правильные права доступа
sudo chown netdata:netdata /etc/netdata/netdata.passwd
sudo chmod 640 /etc/netdata/netdata.passwd
```

Добавить в `/etc/netdata/netdata.conf` в секцию `[web]`:

```ini
[web]
    # ... существующие настройки ...
    web files owner = netdata
    web files group = netdata
    http auth method = basic
    http auth realm = netdata
    http auth file = /etc/netdata/netdata.passwd
```

### 1.4 Настройка приема данных от slave серверов

Создать файл `/etc/netdata/stream.conf`:

```bash
sudo nano /etc/netdata/stream.conf
```

Добавить содержимое:

```ini
[stream]
    # Включаем прием потоков данных
    enabled = yes

    # Настройки master сервера
    destination =
    api key =

# Конфигурация для приема данных от slave серверов
[11111111-2222-3333-4444-555555555555]
    # API ключ для slave серверов
    enabled = yes
    allow from = *
    default history = 3600
    default memory mode = dbengine
    health enabled by default = auto
    default postpone alarms on connect seconds = 60
```

### 1.5 Перезапуск службы

```bash
sudo systemctl restart netdata
sudo systemctl enable netdata

# Проверяем статус
sudo systemctl status netdata

# Проверяем порт
sudo netstat -tulpn | grep 19999
```

## 2. Установка и настройка nginx

### 2.1 Установка nginx

```bash
sudo apt install nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 2.2 Настройка виртуального хоста

```bash
# Создаем конфигурацию сайта
sudo nano /etc/nginx/sites-available/netdata
```

Добавить содержимое:

```nginx
server {
    listen 80;
    server_name mon.au-team.irpo;

    # Логи
    access_log /var/log/nginx/netdata_access.log;
    error_log /var/log/nginx/netdata_error.log;

    # Проксирование к Netdata
    location / {
        proxy_pass http://127.0.0.1:19999;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Таймауты
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Статические файлы Netdata
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://127.0.0.1:19999;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### 2.3 Активация конфигурации

```bash
# Создаем символическую ссылку
sudo ln -s /etc/nginx/sites-available/netdata /etc/nginx/sites-enabled/

# Удаляем дефолтную конфигурацию
sudo rm /etc/nginx/sites-enabled/default

# Проверяем конфигурацию
sudo nginx -t

# Перезапускаем nginx
sudo systemctl restart nginx
```

## 3. Настройка Slave серверов

### 3.1 Установка на каждом slave сервере (HQ-RTR, BR-RTR, BR-SRV)

```bash
# Устанавливаем Netdata
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
sudo sh /tmp/netdata-kickstart.sh --stable-channel --dont-wait
```

### 3.2 Настройка конфигурации slave серверов

На каждом slave сервере редактируем `/etc/netdata/netdata.conf`:

```bash
sudo nano /etc/netdata/netdata.conf
```

**Для HQ-RTR:**

```ini
[global]
    hostname = HQ-RTR
    bind to = 127.0.0.1
    default port = 19999

[web]
    mode = none

[registry]
    enabled = no
```

**Для BR-RTR:**

```ini
[global]
    hostname = BR-RTR
    bind to = 127.0.0.1
    default port = 19999

[web]
    mode = none

[registry]
    enabled = no
```

**Для BR-SRV:**

```ini
[global]
    hostname = BR-SRV
    bind to = 127.0.0.1
    default port = 19999

[web]
    mode = none

[registry]
    enabled = no
```

### 3.3 Настройка отправки данных на master

На каждом slave сервере создаем `/etc/netdata/stream.conf`:

```bash
sudo nano /etc/netdata/stream.conf
```

Добавить (заменить IP*MASTER*СЕРВЕРА на IP адрес HQ-SRV):

```ini
[stream]
    enabled = yes
    destination = IP_MASTER_СЕРВЕРА:19999
    api key = 11111111-2222-3333-4444-555555555555
    timeout seconds = 60
    default port = 19999
    send charts matching = *
    buffer size bytes = 1048576
    reconnect delay seconds = 5
    initial clock resync iterations = 60
```

### 3.4 Перезапуск служб на slave серверах

```bash
sudo systemctl restart netdata
sudo systemctl enable netdata

# Проверяем статус
sudo systemctl status netdata
```

## 4. Проверка и настройка мониторинга

### 4.1 Проверка подключения slave серверов

На master сервере:

```bash
# Проверяем логи Netdata
sudo tail -f /var/log/netdata/netdata.log

# Проверяем активные подключения
sudo netstat -an | grep 19999
```

### 4.2 Доступ к веб-интерфейсу

1. Откройте браузер и перейдите по адресу: `http://mon.au-team.irpo`
2. Введите логин: `admin`
3. Введите пароль: `P@ssw0rd`

### 4.3 Проверка отображения метрик

В веб-интерфейсе должны отображаться:

**Для каждого сервера:**

- **CPU:** Загрузка процессора (%)
- **Memory:** Использование оперативной памяти (MB/GB)
- **Disk:** Использование дискового пространства (GB)
- **Network:** Сетевой трафик
- **System Load:** Системная нагрузка

## 5. Дополнительные настройки

### 5.1 Настройка алертов

Создать файл `/etc/netdata/health.d/custom.conf`:

```bash
sudo nano /etc/netdata/health.d/custom.conf
```

```ini
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
```

### 5.2 Автоматический запуск служб

```bash
# Проверяем автозапуск
sudo systemctl is-enabled netdata
sudo systemctl is-enabled nginx

# Если не включен, включаем
sudo systemctl enable netdata
sudo systemctl enable nginx
```

## 6. Устранение неполадок

### 6.1 Проблемы с подключением slave серверов

```bash
# На master сервере проверяем порт
sudo ufw allow 19999/tcp

# Проверяем логи
sudo tail -f /var/log/netdata/netdata.log | grep stream

# На slave сервере проверяем подключение
telnet IP_MASTER_СЕРВЕРА 19999
```

### 6.2 Проблемы с nginx

```bash
# Проверяем логи nginx
sudo tail -f /var/log/nginx/netdata_error.log

# Проверяем статус
sudo systemctl status nginx

# Перезапускаем службы
sudo systemctl restart nginx
sudo systemctl restart netdata
```

## 7. Итоговая информация

**Параметры мониторинга:**

- **Порт Netdata:** 19999
- **Веб-доступ:** http://mon.au-team.irpo (порт 80)
- **Логин:** admin
- **Пароль:** P@ssw0rd
- **Архитектура:** Master-Slave
- **Мониторируемые устройства:** HQ-SRV, HQ-RTR, BR-RTR, BR-SRV

**Отображаемые метрики:**

- Загрузка процессора (CPU Usage %)
- Использование оперативной памяти (RAM Usage MB/GB)
- Занятое место на диске (Disk Usage GB)
- Сетевой трафик
- Системная нагрузка

**Файлы конфигурации:**

- Master: `/etc/netdata/netdata.conf`, `/etc/netdata/stream.conf`
- Slave: `/etc/netdata/netdata.conf`, `/etc/netdata/stream.conf`
- Nginx: `/etc/nginx/sites-available/netdata`
