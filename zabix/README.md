# Zabbix Monitoring System Docker

Система мониторинга на основе Zabbix с поддержкой мониторинга устройств HQ-RTR, HQ-SRV, BR-RTR и BR-SRV.

## Файлы проекта

- `Dockerfile.server` - Docker образ для Zabbix Server (включает MySQL, Apache, Zabbix Server и веб-интерфейс)
- `Dockerfile.agent` - Docker образ для Zabbix Agent
- `start-server.bat` - Скрипт запуска сервера для Windows
- `start-agents.bat` - Скрипт запуска всех агентов для Windows
- `conf/zabbix_server.conf` - Конфигурация Zabbix Server

## Быстрый запуск

### 🚀 Метод 1: Docker Compose (Рекомендуется)

```cmd
start-compose.bat
```

Это запустит всю систему одной командой:

- MySQL база данных
- Zabbix Server (порт 10051)
- Apache веб-сервер (порты 80, 443)
- Веб-интерфейс Zabbix
- Все 4 агента (HQ-SRV, HQ-RTR, BR-SRV, BR-RTR)

### 🛑 Остановка системы

```cmd
stop-compose.bat
```

### 🔧 Метод 2: Отдельные Dockerfile

#### Запуск Zabbix Server

```cmd
start-server.bat
```

#### Запуск агентов

```cmd
start-agents.bat
```

## Доступ к системе

### Веб-интерфейс

- **URL**: http://localhost/zabbix или https://localhost/zabbix
- **Логин**: Admin
- **Пароль**: P@ssw0rd

### Настройка DNS (опционально)

Для доступа по адресу https://mon.au-team.irpo добавьте в hosts файл:

```
127.0.0.1 mon.au-team.irpo
```

Windows: `C:\Windows\System32\drivers\etc\hosts`

## Мониторинг

Система автоматически настроена для мониторинга:

### Устройства

- **HQ-SRV** - Главный сервер
- **HQ-RTR** - Главный маршрутизатор
- **BR-SRV** - Филиальный сервер
- **BR-RTR** - Филиальный маршрутизатор

### Метрики

- **ЦП**: Загрузка процессора в %
- **Память**: Использование оперативной памяти в %
- **Диск**: Использование дискового пространства в %
- **Сеть**: Трафик входящий/исходящий

## Управление контейнерами

### Просмотр статуса

```cmd
docker ps
```

### Просмотр логов

```cmd
# Логи сервера
docker logs -f zabbix-server

# Логи агентов
docker logs -f zabbix-agent-hq-srv
docker logs -f zabbix-agent-hq-rtr
docker logs -f zabbix-agent-br-srv
docker logs -f zabbix-agent-br-rtr
```

### Остановка

```cmd
# Остановка сервера
docker stop zabbix-server

# Остановка всех агентов
docker stop zabbix-agent-hq-srv zabbix-agent-hq-rtr zabbix-agent-br-srv zabbix-agent-br-rtr
```

### Удаление

```cmd
# Удаление контейнеров
docker rm zabbix-server zabbix-agent-hq-srv zabbix-agent-hq-rtr zabbix-agent-br-srv zabbix-agent-br-rtr

# Удаление образов
docker rmi zabbix-server-custom zabbix-agent-custom
```

## Настройка мониторинга

### Добавление хостов в Zabbix

1. Войдите в веб-интерфейс Zabbix
2. Перейдите в **Configuration → Hosts**
3. Нажмите **Create host**
4. Укажите:
   - **Host name**: название устройства (HQ-SRV, HQ-RTR, BR-SRV, BR-RTR)
   - **Visible name**: отображаемое имя
   - **Groups**: Linux servers или создайте новую группу
   - **Interfaces**:
     - Type: Agent
     - IP address: IP адрес агента
     - Port: 10050
5. Добавьте шаблоны мониторинга:
   - **Linux by Zabbix agent** - для базового мониторинга
   - **Template Module Linux CPU by Zabbix agent**
   - **Template Module Linux memory by Zabbix agent**
   - **Template Module Linux filesystems by Zabbix agent**

### Настройка дашборда

1. Перейдите в **Monitoring → Dashboard**
2. Нажмите **Edit dashboard**
3. Добавьте виджеты:
   - **Graph** - для отображения метрик ЦП
   - **Graph** - для отображения использования памяти
   - **Graph** - для отображения использования диска
   - **Problems** - для отображения проблем

## Технические характеристики

### Порты

- **80, 443** - Веб-интерфейс Apache
- **10050-10054** - Zabbix агенты
- **10051** - Zabbix Server
- **3306** - MySQL (внутренний)

### Используемые технологии

- **Zabbix 6.4** - Система мониторинга
- **MySQL 8.0** - База данных
- **Apache 2.4** - Веб-сервер
- **PHP 8.1** - Веб-интерфейс
- **Ubuntu 22.04** - Базовая ОС

### Обоснование выбора Zabbix

1. **Открытое ПО** - бесплатное решение корпоративного уровня
2. **Масштабируемость** - поддержка тысяч устройств
3. **Гибкость** - настраиваемые метрики и алерты
4. **Веб-интерфейс** - удобное управление через браузер
5. **API** - возможность интеграции с другими системами
6. **Поддержка SNMP** - мониторинг сетевого оборудования

## Troubleshooting

### Контейнер не запускается

```cmd
# Проверьте логи
docker logs zabbix-server

# Проверьте порты
netstat -an | findstr :80
netstat -an | findstr :10051
```

### Агенты не подключаются

```cmd
# Проверьте IP сервера
docker inspect zabbix-server | findstr IPAddress

# Проверьте логи агента
docker logs zabbix-agent-hq-srv
```

### Веб-интерфейс недоступен

```cmd
# Проверьте статус Apache в контейнере
docker exec zabbix-server service apache2 status

# Перезапустите контейнер
docker restart zabbix-server
```
