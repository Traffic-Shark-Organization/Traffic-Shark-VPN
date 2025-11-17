#!/bin/bash
# Скрипт для создания клиентских конфигураций OpenVPN
# Автоматически генерирует сертификат и .ovpn файл

set -e  # Выход при ошибке

##############################################
# Конфигурация
##############################################

EASYRSA_DIR="/etc/openvpn/easy-rsa"
CLIENT_CONFIG_DIR="$HOME/client-configs"
CLIENT_FILES_DIR="$CLIENT_CONFIG_DIR/files"
BASE_CONFIG="$CLIENT_CONFIG_DIR/base.conf"
OPENVPN_DIR="/etc/openvpn"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

##############################################
# Функции
##############################################

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от root (sudo)"
        exit 1
    fi
}

check_dependencies() {
    if [ ! -d "$EASYRSA_DIR" ]; then
        print_error "Easy-RSA не найден в $EASYRSA_DIR"
        exit 1
    fi
    
    if [ ! -f "$EASYRSA_DIR/easyrsa" ]; then
        print_error "Исполняемый файл easyrsa не найден"
        exit 1
    fi
    
    if [ ! -f "$OPENVPN_DIR/ca.crt" ]; then
        print_error "CA сертификат не найден. Сначала настройте OpenVPN сервер."
        exit 1
    fi
}

create_directories() {
    mkdir -p "$CLIENT_CONFIG_DIR"
    mkdir -p "$CLIENT_FILES_DIR"
    chmod 700 "$CLIENT_FILES_DIR"
}

check_client_exists() {
    local client_name=$1
    
    if [ -f "$CLIENT_FILES_DIR/${client_name}.ovpn" ]; then
        print_error "Клиент $client_name уже существует!"
        print_info "Файл: $CLIENT_FILES_DIR/${client_name}.ovpn"
        read -p "Перезаписать? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Проверка в PKI
    if grep -q "^V.*CN=${client_name}$" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null; then
        print_info "Сертификат для $client_name уже существует в PKI"
    fi
}

generate_certificate() {
    local client_name=$1
    
    print_info "Генерация сертификата для $client_name..."
    
    cd "$EASYRSA_DIR"
    
    # Генерация ключа и сертификата клиента (без пароля для удобства)
    # Для повышения безопасности можно использовать: build-client-full $client_name
    ./easyrsa build-client-full "$client_name" nopass > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "Сертификат успешно создан"
    else
        print_error "Ошибка при создании сертификата"
        exit 1
    fi
}

create_base_config() {
    if [ ! -f "$BASE_CONFIG" ]; then
        print_info "Создание базовой конфигурации..."
        
        # Получение внешнего IP сервера
        SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip)
        
        if [ -z "$SERVER_IP" ]; then
            print_error "Не удалось определить внешний IP сервера"
            read -p "Введите IP или домен сервера: " SERVER_IP
        fi
        
        cat > "$BASE_CONFIG" << 'EOF'
client
dev tun
proto udp
remote SERVERIP 1194
resolv-retry infinite
nobind
topology subnet
user nobody
group nogroup
persist-key
persist-tun
tls-version-min 1.3
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384
cipher AES-256-GCM
auth SHA512
remote-cert-tls server
key-direction 1
sndbuf 393216
rcvbuf 393216
compress migrate
verb 3
mute 20
reneg-sec 0
explicit-exit-notify 3
EOF
        
        # Замена IP в конфигурации
        sed -i "s/SERVERIP/$SERVER_IP/g" "$BASE_CONFIG"
        
        print_success "Базовая конфигурация создана"
    fi
}

generate_ovpn() {
    local client_name=$1
    local output_file="$CLIENT_FILES_DIR/${client_name}.ovpn"
    
    print_info "Создание .ovpn файла..."
    
    # Копирование базовой конфигурации
    cat "$BASE_CONFIG" > "$output_file"
    
    # Добавление сертификатов в inline формате
    echo "" >> "$output_file"
    echo "<ca>" >> "$output_file"
    cat "$OPENVPN_DIR/ca.crt" >> "$output_file"
    echo "</ca>" >> "$output_file"
    
    echo "" >> "$output_file"
    echo "<cert>" >> "$output_file"
    # Извлечение только сертификата (без лишних данных)
    sed -ne '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$EASYRSA_DIR/pki/issued/${client_name}.crt" >> "$output_file"
    echo "</cert>" >> "$output_file"
    
    echo "" >> "$output_file"
    echo "<key>" >> "$output_file"
    cat "$EASYRSA_DIR/pki/private/${client_name}.key" >> "$output_file"
    echo "</key>" >> "$output_file"
    
    echo "" >> "$output_file"
    echo "<tls-auth>" >> "$output_file"
    cat "$OPENVPN_DIR/ta.key" >> "$output_file"
    echo "</tls-auth>" >> "$output_file"
    
    # Установка правильных прав доступа
    chmod 600 "$output_file"
    
    print_success "Файл конфигурации создан: $output_file"
}

display_instructions() {
    local client_name=$1
    local output_file="$CLIENT_FILES_DIR/${client_name}.ovpn"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Клиент $client_name успешно создан!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 Файл конфигурации:"
    echo "   $output_file"
    echo ""
    echo "📋 Инструкции по использованию:"
    echo ""
    echo "   Linux/macOS:"
    echo "   sudo openvpn --config ${client_name}.ovpn"
    echo ""
    echo "   Windows:"
    echo "   1. Установите OpenVPN GUI"
    echo "   2. Скопируйте ${client_name}.ovpn в C:\\Program Files\\OpenVPN\\config"
    echo "   3. Запустите OpenVPN GUI и подключитесь"
    echo ""
    echo "   iOS:"
    echo "   1. Установите OpenVPN Connect"
    echo "   2. Отправьте .ovpn файл на устройство"
    echo "   3. Импортируйте файл в приложение"
    echo ""
    echo "   Android:"
    echo "   1. Установите OpenVPN for Android"
    echo "   2. Импортируйте .ovpn файл"
    echo ""
    echo "📥 Скачивание файла с сервера:"
    echo "   scp root@$(hostname -I | awk '{print $1}'):$output_file ."
    echo ""
    echo "🧪 Тестирование подключения:"
    echo "   curl ifconfig.me  # Должен показать IP VPN сервера"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

##############################################
# Основная логика
##############################################

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   OpenVPN Client Configuration Generator        ║"
    echo "║   Traffic Shark VPN                             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    # Проверки
    check_root
    check_dependencies
    create_directories
    create_base_config
    
    # Получение имени клиента
    if [ -z "$1" ]; then
        print_error "Не указано имя клиента"
        echo "Использование: $0 <client_name>"
        echo "Пример: $0 john.doe"
        exit 1
    fi
    
    CLIENT_NAME=$1
    
    # Валидация имени (только буквы, цифры, точки, дефисы, подчеркивания)
    if [[ ! "$CLIENT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        print_error "Недопустимое имя клиента"
        print_info "Используйте только буквы, цифры, точки, дефисы и подчеркивания"
        exit 1
    fi
    
    # Проверка существования
    check_client_exists "$CLIENT_NAME"
    
    # Генерация сертификата
    generate_certificate "$CLIENT_NAME"
    
    # Создание .ovpn файла
    generate_ovpn "$CLIENT_NAME"
    
    # Вывод инструкций
    display_instructions "$CLIENT_NAME"
    
    # Логирование
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Created client: $CLIENT_NAME" >> "$CLIENT_CONFIG_DIR/client-creation.log"
}

# Запуск
main "$@"

