# Конфигурационные файлы OpenVPN

Эта директория содержит все необходимые конфигурационные файлы для OpenVPN сервера.

## 📄 Файлы

### server.conf
**Основная конфигурация OpenVPN сервера**

- Копировать в: `/etc/openvpn/server.conf`
- Production-ready конфигурация для 50+ клиентов
- Современное шифрование (AES-256-GCM, TLS 1.3)
- Подробные комментарии на русском

**Использование**:
```bash
cp configs/server.conf /etc/openvpn/server.conf
systemctl restart openvpn@server
```

**Важные параметры для редактирования**:
- `port` - порт сервера (по умолчанию 1194)
- `proto` - протокол udp/tcp
- `server` - VPN подсеть
- `push "dhcp-option DNS"` - DNS серверы для клиентов
- `max-clients` - максимум одновременных подключений

---

### easy-rsa-vars
**Конфигурация Certificate Authority (PKI)**

- Копировать в: `/etc/openvpn/easy-rsa/vars`
- Определяет параметры сертификатов
- RSA 4096 bit ключи
- SHA512 digest

**Использование**:
```bash
cp configs/easy-rsa-vars /etc/openvpn/easy-rsa/vars
cd /etc/openvpn/easy-rsa
source ./vars
./easyrsa init-pki
```

**Редактируемые параметры**:
- `EASYRSA_REQ_COUNTRY` - страна (RU)
- `EASYRSA_REQ_PROVINCE` - регион
- `EASYRSA_REQ_CITY` - город
- `EASYRSA_REQ_ORG` - организация
- `EASYRSA_REQ_EMAIL` - email администратора
- `EASYRSA_CA_EXPIRE` - срок действия CA (дни)
- `EASYRSA_CERT_EXPIRE` - срок действия сертификатов (дни)

**⚠️ Важно**: Отредактируйте эти параметры ПЕРЕД созданием CA!

---

### client-base.conf
**Базовая конфигурация для клиентов**

- Используется как шаблон для создания .ovpn файлов
- Совместима с Linux, macOS, Windows, iOS, Android
- Inline формат (все сертификаты внутри файла)

**Использование**:
```bash
# Автоматически используется скриптом create-client.sh
mkdir -p ~/client-configs
cp configs/client-base.conf ~/client-configs/base.conf

# Отредактируйте IP сервера
sed -i "s/YOUR_SERVER_IP/$(curl -s ifconfig.me)/" ~/client-configs/base.conf
```

**Редактируемые параметры**:
- `remote YOUR_SERVER_IP 1194` - замените на ваш IP
- `proto udp` - измените на tcp если нужно
- `cipher` - должен совпадать с сервером
- `auth` - должен совпадать с сервером

---

### fail2ban-openvpn.conf
**Защита OpenVPN от брутфорса**

- Копировать в: `/etc/fail2ban/jail.d/openvpn.conf`
- Блокирует IP после 3 неудачных попыток
- Автоматическое увеличение времени бана

**Использование**:
```bash
apt install fail2ban
cp configs/fail2ban-openvpn.conf /etc/fail2ban/jail.d/openvpn.conf
systemctl restart fail2ban

# Проверка статуса
fail2ban-client status openvpn
```

**Настраиваемые параметры**:
- `maxretry` - количество попыток (по умолчанию 3)
- `bantime` - время бана в секундах (по умолчанию 3600)
- `findtime` - окно подсчета попыток (по умолчанию 600)
- `ignoreip` - IP которые не блокируются

---

## 🔧 Порядок применения конфигураций

### 1. Установка OpenVPN и Easy-RSA
```bash
apt update && apt install -y openvpn easy-rsa
```

### 2. Настройка CA
```bash
make-cadir /etc/openvpn/easy-rsa
cp configs/easy-rsa-vars /etc/openvpn/easy-rsa/vars

# ОТРЕДАКТИРУЙТЕ vars перед следующим шагом!
vim /etc/openvpn/easy-rsa/vars

cd /etc/openvpn/easy-rsa
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-dh
./easyrsa build-server-full server nopass
openvpn --genkey secret pki/ta.key
```

### 3. Копирование сертификатов
```bash
cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/ta.key /etc/openvpn/

chmod 600 /etc/openvpn/server.key /etc/openvpn/ta.key
```

### 4. Установка конфигурации сервера
```bash
cp configs/server.conf /etc/openvpn/server.conf

# Создание директории для логов
mkdir -p /var/log/openvpn
```

### 5. Запуск сервера
```bash
systemctl start openvpn@server
systemctl enable openvpn@server
systemctl status openvpn@server
```

### 6. Настройка Fail2Ban (опционально)
```bash
apt install -y fail2ban
cp configs/fail2ban-openvpn.conf /etc/fail2ban/jail.d/openvpn.conf
systemctl restart fail2ban
```

---

## ⚙️ Проверка конфигурации

```bash
# Проверка синтаксиса конфигурации
openvpn --config /etc/openvpn/server.conf --test-crypto

# Проверка статуса
systemctl status openvpn@server

# Проверка логов
tail -f /var/log/openvpn/openvpn.log
journalctl -u openvpn@server -f

# Проверка интерфейса
ip addr show tun0
```

---

## 🔐 Безопасность

**⚠️ КРИТИЧНО: Защита приватных ключей**

```bash
# Проверьте права доступа к критичным файлам
ls -la /etc/openvpn/*.key
ls -la /etc/openvpn/easy-rsa/pki/private/

# Должно быть: -rw------- (600) и владелец root
```

**Рекомендуемые меры**:
- Регулярно обновляйте CRL
- Используйте сильные пароли для CA
- Делайте резервные копии PKI
- Мониторьте логи на подозрительную активность

---

## 📚 Дополнительная информация

- Полная документация: [../README.md](../README.md)
- Быстрый старт: [../QUICK_START.md](../QUICK_START.md)
- Безопасность: [../SECURITY.md](../SECURITY.md)
- Решение проблем: [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md)

---

**Важно**: Не коммитьте в Git файлы с приватными ключами (*.key, *.crt)!

