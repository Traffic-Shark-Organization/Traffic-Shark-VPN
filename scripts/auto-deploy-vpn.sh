#!/bin/bash

################################################################################
# Скрипт автоматического разворачивания OpenVPN сервера
# Traffic Shark VPN - Production Ready для 50+ клиентов
# Версия: 1.0.0
################################################################################

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Функция для отображения заголовка
print_header() {
    clear
    echo "========================================================================="
    echo "  Traffic Shark VPN - Автоматическая установка OpenVPN сервера"
    echo "  Production Ready для 50+ клиентов"
    echo "========================================================================="
    echo ""
}

# Проверка root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root (sudo)"
        exit 1
    fi
}

# Проверка ОС
check_os() {
    log_info "Проверка операционной системы..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        
        if [[ "$OS" != "debian" && "$OS" != "ubuntu" ]]; then
            log_warning "Обнаружена ОС: $OS $VERSION"
            log_warning "Скрипт оптимизирован для Debian/Ubuntu, но продолжим установку..."
        else
            log_success "ОС: $OS $VERSION - поддерживается"
        fi
    else
        log_error "Не удалось определить операционную систему"
        exit 1
    fi
}

# Сбор информации от пользователя
collect_user_input() {
    log_info "Сбор конфигурационных данных..."
    echo ""
    
    # Установка curl если его нет (нужен для определения IP)
    if ! command -v curl &> /dev/null; then
        log_info "Установка curl для определения внешнего IP..."
        apt update -qq && apt install -y curl &> /dev/null
    fi
    
    # Определение внешнего IP
    EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
    log_info "Обнаружен внешний IP: $EXTERNAL_IP"
    read -p "Использовать этот IP для VPN? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        SERVER_IP=$EXTERNAL_IP
    else
        read -p "Введите IP адрес или домен сервера: " SERVER_IP
    fi
    
    # Определение сетевого интерфейса
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    log_info "Обнаружен сетевой интерфейс: $DEFAULT_INTERFACE"
    read -p "Использовать этот интерфейс? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        NETWORK_INTERFACE=$DEFAULT_INTERFACE
    else
        read -p "Введите имя сетевого интерфейса: " NETWORK_INTERFACE
    fi
    
    # Выбор firewall
    echo ""
    log_info "Выберите систему firewall:"
    echo "1) UFW (рекомендуется - проще в использовании)"
    echo "2) iptables-persistent (для продвинутых пользователей)"
    read -p "Выбор (1-2): " FIREWALL_CHOICE
    
    # Данные организации для сертификатов
    echo ""
    log_info "Данные для сертификатов (можно оставить по умолчанию):"
    read -p "Страна [RU]: " CERT_COUNTRY
    CERT_COUNTRY=${CERT_COUNTRY:-RU}
    
    read -p "Регион [Moscow]: " CERT_PROVINCE
    CERT_PROVINCE=${CERT_PROVINCE:-Moscow}
    
    read -p "Город [Moscow]: " CERT_CITY
    CERT_CITY=${CERT_CITY:-Moscow}
    
    read -p "Организация [Traffic Shark VPN]: " CERT_ORG
    CERT_ORG=${CERT_ORG:-Traffic Shark VPN}
    
    read -p "Email [admin@trafficshark.local]: " CERT_EMAIL
    CERT_EMAIL=${CERT_EMAIL:-admin@trafficshark.local}
    
    read -p "Подразделение [IT Security]: " CERT_OU
    CERT_OU=${CERT_OU:-IT Security}
    
    # DNS серверы
    echo ""
    log_info "Выберите DNS серверы:"
    echo "1) Cloudflare (1.1.1.1, 1.0.0.1) - рекомендуется"
    echo "2) Google (8.8.8.8, 8.8.4.4)"
    echo "3) Quad9 (9.9.9.9, 149.112.112.112)"
    read -p "Выбор (1-3): " DNS_CHOICE
    
    case $DNS_CHOICE in
        2)
            DNS_PRIMARY="8.8.8.8"
            DNS_SECONDARY="8.8.4.4"
            ;;
        3)
            DNS_PRIMARY="9.9.9.9"
            DNS_SECONDARY="149.112.112.112"
            ;;
        *)
            DNS_PRIMARY="1.1.1.1"
            DNS_SECONDARY="1.0.0.1"
            ;;
    esac
    
    # Создать первого клиента
    echo ""
    read -p "Создать первого клиента? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        read -p "Имя первого клиента [client1]: " FIRST_CLIENT
        FIRST_CLIENT=${FIRST_CLIENT:-client1}
        CREATE_FIRST_CLIENT=true
    else
        CREATE_FIRST_CLIENT=false
    fi
    
    # Подтверждение
    echo ""
    log_info "===== Конфигурация ====="
    echo "Сервер IP/Домен: $SERVER_IP"
    echo "Сетевой интерфейс: $NETWORK_INTERFACE"
    echo "Firewall: $([ "$FIREWALL_CHOICE" == "1" ] && echo "UFW" || echo "iptables-persistent")"
    echo "DNS: $DNS_PRIMARY, $DNS_SECONDARY"
    echo "Организация: $CERT_ORG"
    echo "Первый клиент: $([ "$CREATE_FIRST_CLIENT" == true ] && echo "$FIRST_CLIENT" || echo "Не создавать")"
    echo ""
    read -p "Продолжить установку с этими параметрами? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Установка отменена пользователем"
        exit 0
    fi
}

# Обновление системы
update_system() {
    log_info "Обновление системы..."
    apt update -y
    DEBIAN_FRONTEND=noninteractive apt upgrade -y
    log_success "Система обновлена"
}

# Установка пакетов
install_packages() {
    log_info "Установка необходимых пакетов..."
    
    if [[ "$FIREWALL_CHOICE" == "1" ]]; then
        # UFW
        DEBIAN_FRONTEND=noninteractive apt install -y \
            openvpn \
            easy-rsa \
            iptables \
            fail2ban \
            htop \
            net-tools \
            curl \
            wget \
            vim \
            ufw \
            unattended-upgrades
    else
        # iptables-persistent
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        
        DEBIAN_FRONTEND=noninteractive apt install -y \
            openvpn \
            easy-rsa \
            iptables \
            iptables-persistent \
            fail2ban \
            htop \
            net-tools \
            curl \
            wget \
            vim \
            unattended-upgrades
    fi
    
    log_success "Пакеты установлены"
    openvpn --version | head -n1
}

# Настройка IP forwarding
setup_ip_forwarding() {
    log_info "Настройка IP forwarding..."
    
    # Создать sysctl.conf если не существует
    touch /etc/sysctl.conf
    
    # Удаление старых записей если есть
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf 2>/dev/null || true
    
    # Добавление новых
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    
    # Применить немедленно
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
    
    log_success "IP forwarding настроен"
}

# Настройка Certificate Authority
setup_ca() {
    log_info "Настройка Certificate Authority (Easy-RSA)..."
    
    # Создание директории Easy-RSA
    make-cadir /etc/openvpn/easy-rsa
    cd /etc/openvpn/easy-rsa
    
    # Создание vars файла
    cat > vars << EOF
# Easy-RSA 3 Parameter Settings
set_var EASYRSA_ALGO rsa
set_var EASYRSA_KEY_SIZE 4096
set_var EASYRSA_DIGEST "sha512"
set_var EASYRSA_CA_EXPIRE 3650
set_var EASYRSA_CERT_EXPIRE 730
set_var EASYRSA_CRL_DAYS 180

# Distinguished Name параметры
set_var EASYRSA_REQ_COUNTRY "$CERT_COUNTRY"
set_var EASYRSA_REQ_PROVINCE "$CERT_PROVINCE"
set_var EASYRSA_REQ_CITY "$CERT_CITY"
set_var EASYRSA_REQ_ORG "$CERT_ORG"
set_var EASYRSA_REQ_EMAIL "$CERT_EMAIL"
set_var EASYRSA_REQ_OU "$CERT_OU"

set_var EASYRSA_BATCH "yes"
set_var EASYRSA_SSL_CONF "\$EASYRSA/openssl-easyrsa.cnf"
EOF
    
    log_info "Инициализация PKI..."
    ./easyrsa init-pki
    
    log_info "Создание CA (может занять время)..."
    ./easyrsa build-ca nopass
    
    log_info "Генерация параметров Diffie-Hellman (это займет несколько минут)..."
    ./easyrsa gen-dh
    
    log_info "Генерация TLS-auth ключа..."
    openvpn --genkey secret /etc/openvpn/easy-rsa/pki/ta.key
    
    log_info "Генерация серверного сертификата..."
    ./easyrsa build-server-full server nopass
    
    log_info "Создание пустого CRL..."
    ./easyrsa gen-crl
    
    # Копирование файлов
    cp pki/ca.crt /etc/openvpn/
    cp pki/issued/server.crt /etc/openvpn/
    cp pki/private/server.key /etc/openvpn/
    cp pki/dh.pem /etc/openvpn/
    cp pki/ta.key /etc/openvpn/
    cp pki/crl.pem /etc/openvpn/
    
    # Установка прав доступа
    chmod 600 /etc/openvpn/server.key
    chmod 600 /etc/openvpn/ta.key
    
    log_success "Certificate Authority настроен"
}

# Создание конфигурации сервера
create_server_config() {
    log_info "Создание конфигурации OpenVPN сервера..."
    
    # Создание директории для логов
    mkdir -p /var/log/openvpn
    
    cat > /etc/openvpn/server.conf << EOF
# OpenVPN Server Configuration для корпоративного VPN 50+ клиентов
# Auto-generated by Traffic Shark VPN deployment script

port 1194
proto udp
dev tun

# SSL/TLS параметры
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
tls-auth /etc/openvpn/ta.key 0

# TLS настройки (максимальная безопасность)
tls-version-min 1.3
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384
cipher AES-256-GCM
auth SHA512
tls-ciphersuites TLS_AES_256_GCM_SHA384

# Сетевые настройки
server 10.8.0.0 255.255.255.0
topology subnet
ifconfig-pool-persist /var/log/openvpn/ipp.txt

# Редирект всего трафика через VPN
push "redirect-gateway def1 bypass-dhcp"

# DNS серверы
push "dhcp-option DNS $DNS_PRIMARY"
push "dhcp-option DNS $DNS_SECONDARY"

# Разрешить клиентам видеть друг друга
client-to-client

# Производительность (оптимизация для 50+ клиентов)
max-clients 100
keepalive 10 120
sndbuf 393216
rcvbuf 393216
push "sndbuf 393216"
push "rcvbuf 393216"
fast-io

# Отключение compression (безопасность)
compress migrate
push "compress migrate"

# Безопасность
user nobody
group nogroup
persist-key
persist-tun
crl-verify /etc/openvpn/crl.pem
duplicate-cn
remote-cert-tls client
replay-window 64 15

# Логирование
verb 3
mute 20
status /var/log/openvpn/openvpn-status.log 1
log-append /var/log/openvpn/openvpn.log

# Безопасность renegotiation
reneg-sec 0
tls-timeout 120
EOF
    
    log_success "Конфигурация сервера создана"
}

# Настройка firewall (UFW)
setup_firewall_ufw() {
    log_info "Настройка UFW firewall..."
    
    # Отключить UFW если включен
    ufw --force disable
    
    # Настройка IP forwarding для UFW
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    
    # Раскомментировать IP forwarding в sysctl
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/ufw/sysctl.conf
    sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/ufw/sysctl.conf
    
    # Backup оригинального файла
    cp /etc/ufw/before.rules /etc/ufw/before.rules.backup
    
    # Добавление NAT правил
    sed -i '/# Don'"'"'t delete these required lines/i \
# NAT table rules for OpenVPN\
*nat\
:POSTROUTING ACCEPT [0:0]\
-A POSTROUTING -s 10.8.0.0/24 -o '"$NETWORK_INTERFACE"' -j MASQUERADE\
COMMIT\
' /etc/ufw/before.rules
    
    # Добавление правил для tun0 в секцию filter
    sed -i '/# allow all on loopback/i \
# Allow traffic from OpenVPN clients\
-A ufw-before-input -i tun0 -j ACCEPT\
-A ufw-before-forward -i tun0 -j ACCEPT\
-A ufw-before-forward -m state --state RELATED,ESTABLISHED -j ACCEPT\
' /etc/ufw/before.rules
    
    # Настройка правил UFW
    # Разрешить SSH (ВАЖНО - иначе потеряете доступ!)
    ufw --force allow 22/tcp comment 'SSH'
    
    # Разрешить OpenVPN
    ufw --force allow 1194/udp comment 'OpenVPN'
    
    # Включение UFW
    ufw --force enable
    
    log_success "UFW firewall настроен"
    ufw status verbose
}

# Настройка firewall (iptables-persistent)
setup_firewall_iptables() {
    log_info "Настройка iptables firewall..."
    
    # Очистка существующих правил
    iptables -F
    iptables -t nat -F
    
    # Настройка NAT
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $NETWORK_INTERFACE -j MASQUERADE
    
    # Разрешение трафика через VPN
    iptables -A INPUT -i tun0 -j ACCEPT
    iptables -A FORWARD -i tun0 -j ACCEPT
    iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Разрешение OpenVPN порта
    iptables -A INPUT -p udp --dport 1194 -j ACCEPT
    
    # Разрешение SSH
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Разрешение loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Сохранение правил
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    fi
    
    log_success "iptables firewall настроен"
    iptables -L -n -v
}

# Настройка Fail2Ban
setup_fail2ban() {
    log_info "Настройка Fail2Ban для OpenVPN..."
    
    cat > /etc/fail2ban/jail.d/openvpn.conf << 'EOF'
[openvpn]
enabled = true
port = 1194
protocol = udp
filter = openvpn
logpath = /var/log/openvpn/openvpn.log
maxretry = 3
bantime = 86400
findtime = 3600
EOF
    
    # Создание фильтра для Fail2Ban
    cat > /etc/fail2ban/filter.d/openvpn.conf << 'EOF'
[Definition]
failregex = ^.*TLS Error: TLS handshake failed.*<HOST>
            ^.*VERIFY ERROR.*<HOST>
            ^.*TLS Error: TLS key negotiation failed to occur within.*<HOST>
ignoreregex =
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_success "Fail2Ban настроен"
}

# Оптимизация системы для 50+ клиентов
optimize_system() {
    log_info "Оптимизация системы для 50+ клиентов..."
    
    # Увеличение лимитов файлов
    if ! grep -q "nofile 65536" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << 'EOF'

# OpenVPN optimization для 50+ клиентов
* soft nofile 65536
* hard nofile 65536
EOF
    fi
    
    # Оптимизация сетевых параметров
    cat >> /etc/sysctl.conf << 'EOF'

# OpenVPN network optimization
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF
    
    sysctl -p > /dev/null
    
    log_success "Система оптимизирована"
}

# Настройка автоматических обновлений безопасности
setup_auto_updates() {
    log_info "Настройка автоматических обновлений безопасности..."
    
    # Настройка unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
    
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    
    log_success "Автоматические обновления настроены"
}

# Запуск OpenVPN
start_openvpn() {
    log_info "Запуск OpenVPN сервера..."
    
    systemctl enable openvpn@server
    systemctl start openvpn@server
    
    sleep 3
    
    if systemctl is-active --quiet openvpn@server; then
        log_success "OpenVPN сервер успешно запущен!"
    else
        log_error "Ошибка запуска OpenVPN сервера"
        journalctl -u openvpn@server -n 50 --no-pager
        exit 1
    fi
}

# Создание базовой конфигурации клиента
create_client_base_config() {
    log_info "Создание базовой конфигурации клиента..."
    
    mkdir -p ~/client-configs/files
    chmod 700 ~/client-configs/files
    
    cat > ~/client-configs/base.conf << EOF
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA512
tls-version-min 1.3
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384
tls-ciphersuites TLS_AES_256_GCM_SHA384
compress migrate
verb 3
key-direction 1
EOF
    
    log_success "Базовая конфигурация клиента создана"
}

# Создание первого клиента
create_first_client() {
    log_info "Создание первого клиента: $FIRST_CLIENT..."
    
    cd /etc/openvpn/easy-rsa
    ./easyrsa build-client-full "$FIRST_CLIENT" nopass
    
    # Создание .ovpn файла
    cat ~/client-configs/base.conf \
        <(echo -e '<ca>') \
        /etc/openvpn/ca.crt \
        <(echo -e '</ca>\n<cert>') \
        /etc/openvpn/easy-rsa/pki/issued/"$FIRST_CLIENT".crt \
        <(echo -e '</cert>\n<key>') \
        /etc/openvpn/easy-rsa/pki/private/"$FIRST_CLIENT".key \
        <(echo -e '</key>\n<tls-auth>') \
        /etc/openvpn/ta.key \
        <(echo -e '</tls-auth>') \
        > ~/client-configs/files/"$FIRST_CLIENT".ovpn
    
    chmod 600 ~/client-configs/files/"$FIRST_CLIENT".ovpn
    
    log_success "Клиент $FIRST_CLIENT создан: ~/client-configs/files/$FIRST_CLIENT.ovpn"
}

# Создание скрипта для создания новых клиентов
create_client_management_script() {
    log_info "Создание скриптов управления клиентами..."
    
    mkdir -p /root/scripts
    
    # Скрипт создания клиента
    cat > /root/scripts/create-client.sh << 'EOFSCRIPT'
#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Использование: $0 <client-name>"
    exit 1
fi

CLIENT_NAME=$1
EASYRSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_CONFIG_DIR="$HOME/client-configs/files"

cd $EASYRSA_DIR

# Создание сертификата клиента
./easyrsa build-client-full "$CLIENT_NAME" nopass

# Создание .ovpn файла
cat $HOME/client-configs/base.conf \
    <(echo -e '<ca>') \
    /etc/openvpn/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    $EASYRSA_DIR/pki/issued/"$CLIENT_NAME".crt \
    <(echo -e '</cert>\n<key>') \
    $EASYRSA_DIR/pki/private/"$CLIENT_NAME".key \
    <(echo -e '</key>\n<tls-auth>') \
    /etc/openvpn/ta.key \
    <(echo -e '</tls-auth>') \
    > "$CLIENT_CONFIG_DIR/${CLIENT_NAME}.ovpn"

chmod 600 "$CLIENT_CONFIG_DIR/${CLIENT_NAME}.ovpn"

echo "Клиент $CLIENT_NAME создан: $CLIENT_CONFIG_DIR/${CLIENT_NAME}.ovpn"
echo ""
echo "Для скачивания файла на локальный компьютер:"
echo "scp root@$(hostname -I | awk '{print $1}'):$CLIENT_CONFIG_DIR/${CLIENT_NAME}.ovpn ./"
EOFSCRIPT
    
    # Скрипт отзыва клиента
    cat > /root/scripts/revoke-client.sh << 'EOFSCRIPT'
#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Использование: $0 <client-name>"
    exit 1
fi

CLIENT_NAME=$1
EASYRSA_DIR="/etc/openvpn/easy-rsa"

cd $EASYRSA_DIR

# Отзыв сертификата
./easyrsa revoke "$CLIENT_NAME"

# Генерация нового CRL
./easyrsa gen-crl

# Копирование CRL
cp pki/crl.pem /etc/openvpn/

# Перезапуск OpenVPN
systemctl restart openvpn@server

echo "Сертификат клиента $CLIENT_NAME отозван"
EOFSCRIPT
    
    # Скрипт мониторинга
    cat > /root/scripts/monitor-vpn.sh << 'EOFSCRIPT'
#!/bin/bash

echo "===== OpenVPN Server Status ====="
echo ""
systemctl status openvpn@server --no-pager
echo ""
echo "===== Connected Clients ====="
cat /var/log/openvpn/openvpn-status.log | grep "^CLIENT_LIST" | awk '{print $2 " - " $3 " (" $4 ")"}'
echo ""
echo "===== Total Clients Connected ====="
cat /var/log/openvpn/openvpn-status.log | grep "^CLIENT_LIST" | wc -l
echo ""
echo "===== Server Network Interface ====="
ip addr show tun0
echo ""
echo "===== Last 10 Log Entries ====="
tail -10 /var/log/openvpn/openvpn.log
EOFSCRIPT
    
    chmod +x /root/scripts/*.sh
    
    log_success "Скрипты управления созданы в /root/scripts/"
}

# Создание скрипта резервного копирования
create_backup_script() {
    log_info "Создание скрипта резервного копирования..."
    
    cat > /root/scripts/backup-vpn.sh << 'EOFSCRIPT'
#!/bin/bash

BACKUP_DIR="/root/vpn-backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/openvpn-backup-$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

# Создание архива
tar -czf "$BACKUP_FILE" \
    /etc/openvpn/ \
    /root/client-configs/ \
    /etc/fail2ban/jail.d/openvpn.conf \
    /etc/ufw/ 2>/dev/null || \
    /etc/iptables/ 2>/dev/null

echo "Backup создан: $BACKUP_FILE"
echo "Размер: $(du -h $BACKUP_FILE | cut -f1)"

# Удаление старых бэкапов (старше 30 дней)
find "$BACKUP_DIR" -name "openvpn-backup-*.tar.gz" -mtime +30 -delete

echo "Старые бэкапы (>30 дней) удалены"
EOFSCRIPT
    
    chmod +x /root/scripts/backup-vpn.sh
    
    # Настройка cron для автоматического бэкапа
    (crontab -l 2>/dev/null; echo "0 3 * * * /root/scripts/backup-vpn.sh >> /var/log/openvpn-backup.log 2>&1") | crontab -
    
    log_success "Скрипт резервного копирования создан (запускается ежедневно в 3:00)"
}

# Вывод финальной информации
print_final_info() {
    clear
    echo "========================================================================="
    echo "  Traffic Shark VPN - Установка завершена успешно!"
    echo "========================================================================="
    echo ""
    log_success "OpenVPN сервер успешно установлен и запущен!"
    echo ""
    echo "===== Информация о сервере ====="
    echo "IP/Домен сервера: $SERVER_IP"
    echo "Порт: 1194 (UDP)"
    echo "Сетевой интерфейс: $NETWORK_INTERFACE"
    echo "Firewall: $([ "$FIREWALL_CHOICE" == "1" ] && echo "UFW" || echo "iptables-persistent")"
    echo "DNS серверы: $DNS_PRIMARY, $DNS_SECONDARY"
    echo ""
    
    if [ "$CREATE_FIRST_CLIENT" == true ]; then
        echo "===== Первый клиент ====="
        echo "Имя: $FIRST_CLIENT"
        echo "Файл: ~/client-configs/files/$FIRST_CLIENT.ovpn"
        echo ""
        echo "Для скачивания на локальный компьютер:"
        echo "scp root@$SERVER_IP:~/client-configs/files/$FIRST_CLIENT.ovpn ./"
        echo ""
    fi
    
    echo "===== Полезные команды ====="
    echo "Статус сервера:         systemctl status openvpn@server"
    echo "Перезапуск:             systemctl restart openvpn@server"
    echo "Логи:                   tail -f /var/log/openvpn/openvpn.log"
    echo "Подключенные клиенты:   cat /var/log/openvpn/openvpn-status.log"
    echo ""
    echo "===== Скрипты управления (в /root/scripts/) ====="
    echo "Создать клиента:        ./create-client.sh <имя>"
    echo "Отозвать клиента:       ./revoke-client.sh <имя>"
    echo "Мониторинг:             ./monitor-vpn.sh"
    echo "Резервное копирование:  ./backup-vpn.sh"
    echo ""
    echo "===== Безопасность ====="
    echo "✓ Шифрование: AES-256-GCM + TLS 1.3"
    echo "✓ RSA ключи: 4096 bit"
    echo "✓ Fail2Ban: включен"
    echo "✓ Автообновления: включены"
    echo "✓ IP Forwarding: включен"
    echo "✓ Firewall: настроен"
    echo "✓ Оптимизация: для 50+ клиентов"
    echo ""
    echo "===== Рекомендации ====="
    echo "1. Настройте SSH ключи и отключите парольную аутентификацию"
    echo "2. Регулярно проверяйте логи: journalctl -u openvpn@server"
    echo "3. Бэкапы создаются автоматически каждый день в 3:00"
    echo "4. Для macOS клиентов используйте: ./fix-client-for-mac.sh"
    echo "5. Проверьте документацию: https://github.com/traffic-shark/vpn"
    echo ""
    echo "========================================================================="
    echo ""
    
    # Проверка статуса
    if systemctl is-active --quiet openvpn@server; then
        log_success "VPN сервер работает корректно!"
    else
        log_warning "VPN сервер может иметь проблемы. Проверьте логи."
    fi
    
    echo ""
    echo "Для просмотра статуса подключений запустите: /root/scripts/monitor-vpn.sh"
    echo ""
}

# Основная функция
main() {
    print_header
    check_root
    check_os
    collect_user_input
    
    echo ""
    log_info "Начинается установка... Это может занять 5-10 минут."
    echo ""
    
    update_system
    install_packages
    setup_ip_forwarding
    setup_ca
    create_server_config
    
    if [[ "$FIREWALL_CHOICE" == "1" ]]; then
        setup_firewall_ufw
    else
        setup_firewall_iptables
    fi
    
    setup_fail2ban
    optimize_system
    setup_auto_updates
    create_client_base_config
    
    if [ "$CREATE_FIRST_CLIENT" == true ]; then
        create_first_client
    fi
    
    create_client_management_script
    create_backup_script
    start_openvpn
    
    # Первый бэкап
    /root/scripts/backup-vpn.sh > /dev/null 2>&1
    
    print_final_info
}

# Запуск скрипта
main

