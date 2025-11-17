#!/bin/bash
# Скрипт для отзыва клиентских сертификатов OpenVPN
# Добавляет сертификат в Certificate Revocation List (CRL)

set -e

##############################################
# Конфигурация
##############################################

EASYRSA_DIR="/etc/openvpn/easy-rsa"
OPENVPN_DIR="/etc/openvpn"
CLIENT_CONFIG_DIR="$HOME/client-configs"
CLIENT_FILES_DIR="$CLIENT_CONFIG_DIR/files"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
}

check_client_exists() {
    local client_name=$1
    
    # Проверка в PKI
    if ! grep -q "^V.*CN=${client_name}$" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null; then
        print_error "Клиент $client_name не найден или уже отозван"
        
        # Проверка, не отозван ли уже
        if grep -q "^R.*CN=${client_name}$" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null; then
            print_warning "Сертификат уже был отозван ранее"
        fi
        
        return 1
    fi
    
    return 0
}

show_client_info() {
    local client_name=$1
    
    print_info "Информация о сертификате:"
    
    local cert_file="$EASYRSA_DIR/pki/issued/${client_name}.crt"
    
    if [ -f "$cert_file" ]; then
        echo ""
        echo "Common Name: $(openssl x509 -in "$cert_file" -noout -subject | sed 's/.*CN = //')"
        echo "Выдан: $(openssl x509 -in "$cert_file" -noout -startdate | sed 's/notBefore=//')"
        echo "Истекает: $(openssl x509 -in "$cert_file" -noout -enddate | sed 's/notAfter=//')"
        echo "Serial: $(openssl x509 -in "$cert_file" -noout -serial | sed 's/serial=//')"
        echo ""
    fi
}

revoke_certificate() {
    local client_name=$1
    
    print_info "Отзыв сертификата $client_name..."
    
    cd "$EASYRSA_DIR"
    
    # Причина отзыва:
    # - unspecified (по умолчанию)
    # - keyCompromise (ключ скомпрометирован)
    # - CACompromise (CA скомпрометирован)
    # - affiliationChanged (изменение принадлежности)
    # - superseded (заменен)
    # - cessationOfOperation (прекращение операций)
    
    echo "Выберите причину отзыва:"
    echo "1) Общая (unspecified) - по умолчанию"
    echo "2) Ключ скомпрометирован (keyCompromise)"
    echo "3) Замена сертификата (superseded)"
    echo "4) Прекращение использования (cessationOfOperation)"
    read -p "Введите номер (1-4, Enter = 1): " reason_choice
    
    case $reason_choice in
        2) reason="keyCompromise" ;;
        3) reason="superseded" ;;
        4) reason="cessationOfOperation" ;;
        *) reason="unspecified" ;;
    esac
    
    print_info "Причина отзыва: $reason"
    
    # Отзыв сертификата
    # echo "yes" | ./easyrsa revoke "$client_name" "$reason"
    ./easyrsa --batch revoke "$client_name"
    
    if [ $? -eq 0 ]; then
        print_success "Сертификат успешно отозван"
    else
        print_error "Ошибка при отзыве сертификата"
        exit 1
    fi
}

generate_crl() {
    print_info "Генерация CRL (Certificate Revocation List)..."
    
    cd "$EASYRSA_DIR"
    
    ./easyrsa gen-crl
    
    if [ $? -eq 0 ]; then
        print_success "CRL успешно создан"
    else
        print_error "Ошибка при создании CRL"
        exit 1
    fi
    
    # Копирование CRL в OpenVPN директорию
    cp "$EASYRSA_DIR/pki/crl.pem" "$OPENVPN_DIR/crl.pem"
    chmod 644 "$OPENVPN_DIR/crl.pem"
    
    print_success "CRL скопирован в $OPENVPN_DIR/crl.pem"
}

restart_openvpn() {
    print_info "Перезапуск OpenVPN сервера..."
    
    systemctl restart openvpn@server
    
    if [ $? -eq 0 ]; then
        print_success "OpenVPN сервер перезапущен"
        
        # Проверка статуса
        sleep 2
        if systemctl is-active --quiet openvpn@server; then
            print_success "Сервер работает корректно"
        else
            print_error "Сервер не запустился, проверьте логи!"
            print_info "Команда для просмотра логов: journalctl -u openvpn@server -n 50"
        fi
    else
        print_error "Ошибка при перезапуске OpenVPN"
        exit 1
    fi
}

remove_client_files() {
    local client_name=$1
    
    print_info "Удаление клиентских файлов..."
    
    # Архивирование перед удалением
    if [ -f "$CLIENT_FILES_DIR/${client_name}.ovpn" ]; then
        local archive_dir="$CLIENT_CONFIG_DIR/revoked"
        mkdir -p "$archive_dir"
        
        mv "$CLIENT_FILES_DIR/${client_name}.ovpn" "$archive_dir/${client_name}.ovpn.revoked.$(date +%Y%m%d_%H%M%S)"
        print_success "Конфигурация перемещена в архив отозванных"
    else
        print_warning "Файл конфигурации не найден"
    fi
}

disconnect_client() {
    local client_name=$1
    
    print_info "Отключение активных сессий клиента..."
    
    # Проверка статус-файла
    if [ -f "/var/log/openvpn/openvpn-status.log" ]; then
        if grep -q "$client_name" "/var/log/openvpn/openvpn-status.log"; then
            print_warning "Клиент $client_name активно подключен!"
            print_info "После перезапуска сервера соединение будет разорвано"
        else
            print_info "Клиент не подключен в данный момент"
        fi
    fi
}

log_revocation() {
    local client_name=$1
    local reason=$2
    
    local log_file="$CLIENT_CONFIG_DIR/revocation.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Revoked: $client_name (Reason: ${reason:-unspecified})" >> "$log_file"
}

list_revoked_certificates() {
    print_info "Список отозванных сертификатов:"
    echo ""
    
    if [ -f "$EASYRSA_DIR/pki/index.txt" ]; then
        local revoked_count=$(grep "^R" "$EASYRSA_DIR/pki/index.txt" | wc -l)
        
        if [ $revoked_count -eq 0 ]; then
            print_info "Нет отозванных сертификатов"
        else
            echo "Всего отозвано: $revoked_count"
            echo ""
            
            grep "^R" "$EASYRSA_DIR/pki/index.txt" | while read line; do
                cn=$(echo "$line" | grep -o "CN=[^/]*" | sed 's/CN=//')
                revoke_date=$(echo "$line" | awk '{print $3}')
                echo "  • $cn (отозван: $revoke_date)"
            done
        fi
    else
        print_error "PKI index файл не найден"
    fi
    
    echo ""
}

##############################################
# Основная логика
##############################################

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   OpenVPN Certificate Revocation Tool           ║"
    echo "║   Traffic Shark VPN                             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    # Проверки
    check_root
    check_dependencies
    
    # Специальная опция для просмотра списка
    if [ "$1" == "--list" ] || [ "$1" == "-l" ]; then
        list_revoked_certificates
        exit 0
    fi
    
    # Получение имени клиента
    if [ -z "$1" ]; then
        print_error "Не указано имя клиента"
        echo "Использование: $0 <client_name>"
        echo "           или: $0 --list  (просмотр отозванных)"
        echo "Пример: $0 john.doe"
        exit 1
    fi
    
    CLIENT_NAME=$1
    
    # Проверка существования
    if ! check_client_exists "$CLIENT_NAME"; then
        exit 1
    fi
    
    # Показать информацию о сертификате
    show_client_info "$CLIENT_NAME"
    
    # Подтверждение
    print_warning "ВЫ СОБИРАЕТЕСЬ ОТОЗВАТЬ СЕРТИФИКАТ: $CLIENT_NAME"
    print_warning "Это действие НЕОБРАТИМО!"
    echo ""
    read -p "Продолжить? (yes/NO): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_info "Отмена операции"
        exit 0
    fi
    
    echo ""
    
    # Проверка активных подключений
    disconnect_client "$CLIENT_NAME"
    
    # Отзыв сертификата
    revoke_certificate "$CLIENT_NAME"
    
    # Генерация CRL
    generate_crl
    
    # Перезапуск OpenVPN
    restart_openvpn
    
    # Удаление клиентских файлов
    remove_client_files "$CLIENT_NAME"
    
    # Логирование
    log_revocation "$CLIENT_NAME" "$reason"
    
    # Итоговая информация
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Сертификат $CLIENT_NAME успешно отозван!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_info "CRL обновлен и OpenVPN перезапущен"
    print_info "Клиент больше не сможет подключиться к серверу"
    echo ""
    print_info "Для просмотра всех отозванных сертификатов:"
    echo "   $0 --list"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Запуск
main "$@"

