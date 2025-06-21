# Быстрое развертывание мониторинга Netdata

## Краткая последовательность команд

### 1. Настройка Master сервера (HQ-SRV)

```bash
# Загрузить и запустить скрипт автоустановки
wget https://raw.githubusercontent.com/yourrepo/netdata-setup/main/install-netdata-master.sh
sudo bash install-netdata-master.sh

# Или ручная установка:
sudo apt update && sudo apt install curl wget git apache2-utils nginx -y
wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
sudo sh /tmp/netdata-kickstart.sh --stable-channel --dont-wait
```

### 2. Настройка Slave серверов

```bash
# Для HQ-RTR (замените 192.168.1.10 на IP master сервера)
wget https://raw.githubusercontent.com/yourrepo/netdata-setup/main/install-netdata-slave.sh
sudo bash install-netdata-slave.sh HQ-RTR 192.168.1.10

# Для BR-RTR
sudo bash install-netdata-slave.sh BR-RTR 192.168.1.10

# Для BR-SRV
sudo bash install-netdata-slave.sh BR-SRV 192.168.1.10
```

### 3. Проверка работы

```bash
# На master сервере проверить подключения
sudo netstat -an | grep 19999
sudo tail -f /var/log/netdata/netdata.log | grep stream

# Открыть в браузере
# http://mon.au-team.irpo
# Логин: admin
# Пароль: P@ssw0rd
```

## Основные файлы конфигурации

```bash
# Master сервер
/etc/netdata/netdata.conf       # Основная конфигурация
/etc/netdata/stream.conf        # Настройки приема данных
/etc/netdata/netdata.passwd     # Файл паролей
/etc/nginx/sites-available/netdata  # Конфигурация nginx

# Slave серверы
/etc/netdata/netdata.conf       # Основная конфигурация
/etc/netdata/stream.conf        # Настройки отправки данных
```

## Полезные команды

```bash
# Перезапуск служб
sudo systemctl restart netdata
sudo systemctl restart nginx

# Проверка статуса
sudo systemctl status netdata
sudo systemctl status nginx

# Просмотр логов
tail -f /var/log/netdata/netdata.log
tail -f /var/log/nginx/netdata_error.log

# Проверка портов
sudo netstat -tulpn | grep -E ":80|:19999"

# Проверка streaming (на master)
curl -H "X-Auth-Token: 11111111-2222-3333-4444-555555555555" http://localhost:19999/api/v1/info
```

## Устранение проблем

```bash
# Если slave не подключается к master
# На master:
sudo ufw allow 19999/tcp
sudo tail -f /var/log/netdata/netdata.log | grep stream

# На slave:
telnet MASTER_IP 19999
sudo tail -f /var/log/netdata/netdata.log | grep stream

# Если не работает веб-интерфейс
sudo nginx -t
sudo systemctl reload nginx
curl -I http://mon.au-team.irpo
```

## Конфигурация DNS/hosts

```bash
# Добавить в /etc/hosts на клиентских машинах:
MASTER_SERVER_IP    mon.au-team.irpo

# Или настроить DNS запись:
# mon.au-team.irpo A MASTER_SERVER_IP
```

## Итоговые параметры

- **Порт Netdata:** 19999
- **Веб-доступ:** http://mon.au-team.irpo (порт 80)
- **Логин:** admin / Пароль: P@ssw0rd
- **API ключ:** 11111111-2222-3333-4444-555555555555
- **Мониторируемые серверы:** HQ-SRV, HQ-RTR, BR-RTR, BR-SRV
