#!/bin/bash
# Скрипт проверки готовности системы к установке OpenVPN
# Проверяет все необходимые требования

##############################################
# Цвета
##############################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################
# Счетчики
##############################################

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

##############################################
# Функции
##############################################

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

print_check() {
    echo -n "Проверка: $1 ... "
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((CHECKS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}"
    [ ! -z "$1" ] && echo -e "${RED}  └─ $1${NC}"
    ((CHECKS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING${NC}"
    [ ! -z "$1" ] && echo -e "${YELLOW}  └─ $1${NC}"
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

##############################################
# Проверки
##############################################

check_os() {
    print_header "Проверка операционной системы"
    
    print_check "Операционная система"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "debian" ]]; then
            if [[ "$VERSION_ID" == "13" ]] || [[ "$VERSION_ID" -ge 13 ]]; then
                print_pass
                print_info "OS: $PRETTY_NAME"
            else
                print_warning "Debian $VERSION_ID обнаружен, но рекомендуется Debian 13"
                print_info "OS: $PRETTY_NAME"
            fi
        else
            print_warning "Обнаружена не Debian система"
            print_info "OS: $PRETTY_NAME"
            print_info "Скрипты могут требовать модификации"
        fi
    else
        print_fail "Не удалось определить ОС"
    fi
    
    print_check "Архитектура процессора"
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        print_pass
        print_info "Architecture: $ARCH"
    else
        print_warning "Архитектура $ARCH может не поддерживаться полностью"
    fi
    
    print_check "Kernel версия"
    KERNEL=$(uname -r)
    KERNEL_MAJOR=$(echo $KERNEL | cut -d. -f1)
    if [ "$KERNEL_MAJOR" -ge 4 ]; then
        print_pass
        print_info "Kernel: $KERNEL"
    else
        print_fail "Kernel слишком старый: $KERNEL"
    fi
}

check_privileges() {
    print_header "Проверка прав доступа"
    
    print_check "Root привилегии"
    if [[ $EUID -eq 0 ]]; then
        print_pass
    else
        print_fail "Требуются root права. Запустите с sudo."
    fi
}

check_network() {
    print_header "Проверка сети"
    
    print_check "Сетевой интерфейс"
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ ! -z "$INTERFACE" ]; then
        print_pass
        print_info "Интерфейс: $INTERFACE"
    else
        print_fail "Не удалось определить сетевой интерфейс"
    fi
    
    print_check "Внешний IP адрес"
    EXTERNAL_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null)
    if [ ! -z "$EXTERNAL_IP" ]; then
        print_pass
        print_info "IP: $EXTERNAL_IP"
    else
        print_fail "Не удалось определить внешний IP"
    fi
    
    print_check "DNS резолвинг"
    if nslookup google.com > /dev/null 2>&1; then
        print_pass
    else
        print_fail "Проблемы с DNS"
    fi
    
    print_check "Интернет соединение"
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        print_pass
    else
        print_fail "Нет доступа к интернету"
    fi
}

check_resources() {
    print_header "Проверка системных ресурсов"
    
    print_check "RAM память"
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -ge 2000 ]; then
        print_pass
        print_info "RAM: ${TOTAL_RAM}MB (достаточно)"
    elif [ "$TOTAL_RAM" -ge 1500 ]; then
        print_warning "RAM: ${TOTAL_RAM}MB (минимально)"
        print_info "Рекомендуется минимум 2GB для стабильной работы"
    else
        print_fail "RAM: ${TOTAL_RAM}MB (недостаточно)"
        print_info "Требуется минимум 2GB RAM"
    fi
    
    print_check "CPU ядра"
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -ge 2 ]; then
        print_pass
        print_info "CPU cores: $CPU_CORES"
    else
        print_warning "CPU cores: $CPU_CORES"
        print_info "Рекомендуется минимум 2 ядра"
    fi
    
    print_check "Дисковое пространство"
    DISK_AVAILABLE=$(df / | awk 'NR==2 {print $4}')
    DISK_AVAILABLE_GB=$((DISK_AVAILABLE / 1024 / 1024))
    if [ "$DISK_AVAILABLE_GB" -ge 15 ]; then
        print_pass
        print_info "Доступно: ${DISK_AVAILABLE_GB}GB"
    elif [ "$DISK_AVAILABLE_GB" -ge 10 ]; then
        print_warning "Доступно: ${DISK_AVAILABLE_GB}GB"
        print_info "Рекомендуется минимум 20GB свободного места"
    else
        print_fail "Доступно: ${DISK_AVAILABLE_GB}GB (недостаточно)"
    fi
}

check_packages() {
    print_header "Проверка необходимых пакетов"
    
    print_check "OpenVPN"
    if command -v openvpn &> /dev/null; then
        VERSION=$(openvpn --version | head -1)
        print_pass
        print_info "$VERSION"
    else
        print_fail "OpenVPN не установлен (apt install openvpn)"
    fi
    
    print_check "Easy-RSA"
    if [ -f "/usr/share/easy-rsa/easyrsa" ] || command -v easyrsa &> /dev/null; then
        print_pass
    else
        print_fail "Easy-RSA не установлен (apt install easy-rsa)"
    fi
    
    print_check "iptables"
    if command -v iptables &> /dev/null; then
        print_pass
    else
        print_fail "iptables не установлен (apt install iptables)"
    fi
    
    print_check "curl"
    if command -v curl &> /dev/null; then
        print_pass
    else
        print_warning "curl не установлен (apt install curl)"
    fi
    
    print_check "OpenSSL"
    if command -v openssl &> /dev/null; then
        print_pass
        VERSION=$(openssl version | awk '{print $2}')
        print_info "OpenSSL: $VERSION"
    else
        print_fail "OpenSSL не установлен"
    fi
}

check_kernel_modules() {
    print_header "Проверка kernel модулей"
    
    print_check "TUN/TAP модуль"
    if [ -e /dev/net/tun ]; then
        print_pass
    else
        print_fail "/dev/net/tun не найден"
        print_info "Загрузите модуль: modprobe tun"
    fi
    
    print_check "iptables модули"
    if lsmod | grep -q ip_tables; then
        print_pass
    else
        print_warning "ip_tables модуль не загружен"
        print_info "Обычно загружается автоматически"
    fi
}

check_firewall() {
    print_header "Проверка firewall"
    
    print_check "UFW статус"
    if command -v ufw &> /dev/null; then
        UFW_STATUS=$(ufw status | head -1)
        print_info "UFW установлен: $UFW_STATUS"
    else
        print_info "UFW не установлен"
    fi
    
    print_check "iptables правила"
    RULES_COUNT=$(iptables -L | wc -l)
    print_info "Правил: $RULES_COUNT"
}

check_security() {
    print_header "Проверка безопасности"
    
    print_check "Fail2Ban"
    if command -v fail2ban-client &> /dev/null; then
        print_pass
        print_info "Fail2Ban установлен"
    else
        print_warning "Fail2Ban не установлен"
        print_info "Рекомендуется для защиты от брутфорса"
    fi
    
    print_check "SSH конфигурация"
    if [ -f /etc/ssh/sshd_config ]; then
        if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
            print_pass
            print_info "Root login отключен"
        else
            print_warning "Root login разрешен"
            print_info "Рекомендуется отключить в production"
        fi
    fi
    
    print_check "Автоматические обновления"
    if dpkg -l | grep -q unattended-upgrades; then
        print_pass
        print_info "unattended-upgrades установлен"
    else
        print_warning "Автообновления не настроены"
        print_info "apt install unattended-upgrades"
    fi
}

check_ports() {
    print_header "Проверка портов"
    
    print_check "Порт 1194 (OpenVPN)"
    if netstat -tuln 2>/dev/null | grep -q ":1194 " || ss -tuln 2>/dev/null | grep -q ":1194 "; then
        print_warning "Порт 1194 уже используется"
        print_info "OpenVPN может быть уже запущен"
    else
        print_pass
        print_info "Порт свободен"
    fi
    
    print_check "SSH порт"
    SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
    fi
    print_info "SSH слушает на порту: $SSH_PORT"
}

generate_report() {
    print_header "Итоговый отчет"
    
    TOTAL_CHECKS=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNING))
    
    echo ""
    echo -e "${GREEN}Пройдено: $CHECKS_PASSED${NC}"
    echo -e "${RED}Провалено: $CHECKS_FAILED${NC}"
    echo -e "${YELLOW}Предупреждений: $CHECKS_WARNING${NC}"
    echo "Всего проверок: $TOTAL_CHECKS"
    echo ""
    
    if [ $CHECKS_FAILED -eq 0 ]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✓ Система готова к установке OpenVPN!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "Следующие шаги:"
        echo "1. Прочитайте QUICK_START.md или README.md"
        echo "2. Запустите ./scripts/setup-firewall.sh"
        echo "3. Следуйте инструкциям в документации"
        echo ""
        return 0
    else
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}✗ Обнаружены критические проблемы!${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "Устраните ошибки перед установкой:"
        echo ""
        if ! command -v openvpn &> /dev/null; then
            echo "• Установите OpenVPN: apt install openvpn"
        fi
        if ! command -v easyrsa &> /dev/null && [ ! -f "/usr/share/easy-rsa/easyrsa" ]; then
            echo "• Установите Easy-RSA: apt install easy-rsa"
        fi
        if ! command -v iptables &> /dev/null; then
            echo "• Установите iptables: apt install iptables iptables-persistent"
        fi
        if [ ! -e /dev/net/tun ]; then
            echo "• Загрузите TUN модуль: modprobe tun"
        fi
        echo ""
        return 1
    fi
}

##############################################
# Основная логика
##############################################

main() {
    clear
    
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   OpenVPN Installation Readiness Check          ║"
    echo "║   Traffic Shark VPN                             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    # Выполнение всех проверок
    check_privileges
    check_os
    check_network
    check_resources
    check_packages
    check_kernel_modules
    check_firewall
    check_security
    check_ports
    
    # Итоговый отчет
    generate_report
    
    exit $?
}

# Запуск
main "$@"

