#!/bin/bash
# Скрипт автоматической настройки firewall для OpenVPN
# Поддержка iptables и UFW

set -e

##############################################
# Конфигурация
##############################################

VPN_SUBNET="10.8.0.0/24"
VPN_PORT="1194"
VPN_PROTOCOL="udp"
SSH_PORT="22"  # Измените если используете нестандартный порт

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################
# Функции
##############################################

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от root (sudo)"
        exit 1
    fi
}

detect_network_interface() {
    print_info "Определение сетевого интерфейса..."
    
    # Получение основного интерфейса
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [ -z "$INTERFACE" ]; then
        print_error "Не удалось автоматически определить сетевой интерфейс"
        echo ""
        echo "Доступные интерфейсы:"
        ip link show | grep "^[0-9]" | awk '{print $2}' | sed 's/://g'
        echo ""
        read -p "Введите имя интерфейса (например, eth0): " INTERFACE
    fi
    
    print_success "Используется интерфейс: $INTERFACE"
}

check_firewall_tool() {
    if command -v ufw &> /dev/null; then
        FIREWALL_TOOL="ufw"
        print_info "Обнаружен UFW"
    elif command -v iptables &> /dev/null; then
        FIREWALL_TOOL="iptables"
        print_info "Используется iptables"
    else
        print_error "Не найдены ни UFW, ни iptables"
        exit 1
    fi
}

backup_rules() {
    print_info "Создание резервной копии текущих правил..."
    
    local backup_dir="/root/firewall-backups"
    mkdir -p "$backup_dir"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [ "$FIREWALL_TOOL" == "ufw" ]; then
        ufw status numbered > "$backup_dir/ufw-backup-$timestamp.txt"
    else
        iptables-save > "$backup_dir/iptables-backup-$timestamp.txt"
        if command -v ip6tables &> /dev/null; then
            ip6tables-save > "$backup_dir/ip6tables-backup-$timestamp.txt"
        fi
    fi
    
    print_success "Резервная копия сохранена в $backup_dir"
}

setup_iptables() {
    print_header "Настройка iptables"
    
    # Установка iptables-persistent для сохранения правил
    print_info "Установка iptables-persistent..."
    if ! dpkg -l | grep -q iptables-persistent; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    fi
    
    # Очистка существующих правил (опционально)
    # print_warning "Очистка существующих правил..."
    # iptables -F
    # iptables -X
    # iptables -t nat -F
    # iptables -t nat -X
    
    # Базовые правила безопасности
    print_info "Настройка базовых правил..."
    
    # Разрешить установленные и связанные соединения
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Разрешить loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Разрешить SSH (ВАЖНО: не блокируйте себя!)
    print_info "Разрешение SSH на порту $SSH_PORT..."
    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    
    # Разрешить OpenVPN
    print_info "Разрешение OpenVPN на порту $VPN_PORT/$VPN_PROTOCOL..."
    iptables -A INPUT -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT
    
    # Разрешить трафик через TUN интерфейс
    print_info "Разрешение трафика через tun0..."
    iptables -A INPUT -i tun0 -j ACCEPT
    iptables -A FORWARD -i tun0 -j ACCEPT
    iptables -A FORWARD -o tun0 -j ACCEPT
    
    # NAT для VPN клиентов
    print_info "Настройка NAT для VPN подсети $VPN_SUBNET..."
    iptables -t nat -A POSTROUTING -s $VPN_SUBNET -o $INTERFACE -j MASQUERADE
    
    # Пересылка пакетов между интерфейсами
    iptables -A FORWARD -i $INTERFACE -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i tun0 -o $INTERFACE -j ACCEPT
    
    # Защита от основных атак
    print_info "Настройка защиты от атак..."
    
    # SYN flood protection
    iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
    iptables -A INPUT -p tcp --syn -j DROP
    
    # Защита от ping flood
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
    
    # Блокировка недействительных пакетов
    iptables -A INPUT -m state --state INVALID -j DROP
    
    # Защита от port scanning
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    
    # Логирование дропнутых пакетов (опционально, создает много логов)
    # iptables -A INPUT -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
    
    # Политики по умолчанию (осторожно!)
    print_warning "Установка политик по умолчанию..."
    # iptables -P INPUT DROP
    # iptables -P FORWARD DROP
    # iptables -P OUTPUT ACCEPT
    
    # Сохранение правил
    print_info "Сохранение правил iptables..."
    
    # Для Debian/Ubuntu
    if [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4
        if command -v ip6tables &> /dev/null; then
            ip6tables-save > /etc/iptables/rules.v6
        fi
    fi
    
    # Для систем с netfilter-persistent
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    fi
    
    print_success "iptables настроен успешно"
}

setup_ufw() {
    print_header "Настройка UFW"
    
    # Установка UFW если не установлен
    if ! command -v ufw &> /dev/null; then
        print_info "Установка UFW..."
        apt-get update
        apt-get install -y ufw
    fi
    
    # Отключение UFW для настройки
    print_info "Временное отключение UFW..."
    ufw --force disable
    
    # Сброс правил (опционально)
    # print_warning "Сброс существующих правил..."
    # ufw --force reset
    
    # Политики по умолчанию
    print_info "Настройка политик по умолчанию..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw default allow routed
    
    # SSH (ВАЖНО: добавляем перед включением UFW!)
    print_info "Разрешение SSH на порту $SSH_PORT..."
    ufw allow $SSH_PORT/tcp comment 'SSH access'
    
    # OpenVPN
    print_info "Разрешение OpenVPN на порту $VPN_PORT/$VPN_PROTOCOL..."
    ufw allow $VPN_PORT/$VPN_PROTOCOL comment 'OpenVPN server'
    
    # Дополнительные порты (если нужны)
    # ufw allow 443/tcp comment 'HTTPS/OpenVPN-TCP'
    
    # Настройка NAT через UFW
    print_info "Настройка NAT в UFW..."
    
    # Backup конфигурации
    cp /etc/ufw/before.rules /etc/ufw/before.rules.backup.$(date +%Y%m%d)
    
    # Добавление NAT правил в before.rules
    if ! grep -q "POSTROUTING -s $VPN_SUBNET" /etc/ufw/before.rules; then
        # Добавляем в начало файла после комментариев
        sed -i '/^# Don.t delete these required lines/i \
# NAT table rules for OpenVPN\n\
*nat\n\
:POSTROUTING ACCEPT [0:0]\n\
-A POSTROUTING -s '"$VPN_SUBNET"' -o '"$INTERFACE"' -j MASQUERADE\n\
COMMIT\n' /etc/ufw/before.rules
    fi
    
    # Разрешить forwarding в sysctl (UFW конфигурация)
    print_info "Включение IP forwarding в UFW..."
    sed -i 's|^#net/ipv4/ip_forward=1|net/ipv4/ip_forward=1|g' /etc/ufw/sysctl.conf
    sed -i 's|^#net/ipv6/conf/default/forwarding=1|net/ipv6/conf/default/forwarding=1|g' /etc/ufw/sysctl.conf
    sed -i 's|^#net/ipv6/conf/all/forwarding=1|net/ipv6/conf/all/forwarding=1|g' /etc/ufw/sysctl.conf
    
    # Включение UFW
    print_info "Включение UFW..."
    ufw --force enable
    
    print_success "UFW настроен успешно"
}

display_status() {
    print_header "Статус Firewall"
    
    if [ "$FIREWALL_TOOL" == "ufw" ]; then
        ufw status verbose
    else
        echo "=== iptables INPUT ==="
        iptables -L INPUT -n -v --line-numbers
        echo ""
        echo "=== iptables FORWARD ==="
        iptables -L FORWARD -n -v --line-numbers
        echo ""
        echo "=== NAT POSTROUTING ==="
        iptables -t nat -L POSTROUTING -n -v --line-numbers
    fi
    
    echo ""
    print_info "IP Forwarding статус:"
    sysctl net.ipv4.ip_forward
}

test_connectivity() {
    print_header "Тест подключения"
    
    # Проверка SSH доступности
    print_info "Проверка SSH порта $SSH_PORT..."
    if netstat -tuln | grep -q ":$SSH_PORT "; then
        print_success "SSH порт открыт"
    else
        print_warning "SSH порт не найден. Убедитесь, что SSH сервер запущен."
    fi
    
    # Проверка OpenVPN порта
    print_info "Проверка OpenVPN порта $VPN_PORT/$VPN_PROTOCOL..."
    if netstat -uln | grep -q ":$VPN_PORT "; then
        print_success "OpenVPN порт открыт"
    else
        print_warning "OpenVPN не прослушивает порт. Возможно, сервер не запущен."
    fi
    
    # Проверка IP forwarding
    print_info "Проверка IP forwarding..."
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]; then
        print_success "IP forwarding включен"
    else
        print_error "IP forwarding выключен!"
        print_info "Включение через: sysctl -w net.ipv4.ip_forward=1"
    fi
}

##############################################
# Основная логика
##############################################

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   OpenVPN Firewall Setup Script                 ║"
    echo "║   Traffic Shark VPN                             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    # Проверки
    check_root
    detect_network_interface
    check_firewall_tool
    
    # Предупреждение
    print_warning "ВНИМАНИЕ: Этот скрипт изменит настройки firewall!"
    print_warning "Убедитесь, что у вас есть альтернативный доступ к серверу"
    print_warning "на случай проблем с SSH подключением."
    echo ""
    
    # Вопрос о SSH порте
    read -p "SSH порт (текущий: $SSH_PORT, Enter = оставить): " input_ssh_port
    if [ ! -z "$input_ssh_port" ]; then
        SSH_PORT=$input_ssh_port
    fi
    
    echo ""
    read -p "Продолжить настройку firewall? (yes/NO): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_info "Отмена операции"
        exit 0
    fi
    
    # Резервная копия
    backup_rules
    
    # Настройка в зависимости от выбранного инструмента
    if [ "$FIREWALL_TOOL" == "ufw" ]; then
        setup_ufw
    else
        setup_iptables
    fi
    
    # Отображение статуса
    display_status
    
    # Тест подключения
    test_connectivity
    
    # Итоговая информация
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Firewall успешно настроен!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_info "Конфигурация:"
    echo "  • Сетевой интерфейс: $INTERFACE"
    echo "  • VPN подсеть: $VPN_SUBNET"
    echo "  • OpenVPN порт: $VPN_PORT/$VPN_PROTOCOL"
    echo "  • SSH порт: $SSH_PORT"
    echo "  • Firewall: $FIREWALL_TOOL"
    echo ""
    print_info "Следующие шаги:"
    echo "  1. Проверьте SSH подключение в новом терминале"
    echo "  2. Запустите OpenVPN: systemctl start openvpn@server"
    echo "  3. Проверьте логи: journalctl -u openvpn@server -f"
    echo ""
    print_warning "Если потеряли доступ по SSH, используйте консоль VPS провайдера"
    print_info "Резервные копии сохранены в /root/firewall-backups/"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Запуск
main "$@"

