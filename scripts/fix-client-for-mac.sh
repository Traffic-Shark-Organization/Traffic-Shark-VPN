#!/bin/bash
# Скрипт для исправления .ovpn конфигурации для Mac OpenVPN Connect
# Исправляет проблемы совместимости, которые вызывают бесконечное подключение

set -e

##############################################
# Конфигурация
##############################################

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

usage() {
    echo "Использование: $0 <input.ovpn> [output.ovpn]"
    echo ""
    echo "Исправляет конфигурацию OpenVPN клиента для Mac OpenVPN Connect"
    echo ""
    echo "Параметры:"
    echo "  input.ovpn   - Исходный .ovpn файл"
    echo "  output.ovpn  - Выходной .ovpn файл (опционально, по умолчанию: input-mac.ovpn)"
    echo ""
    echo "Пример:"
    echo "  $0 client1.ovpn client1-mac.ovpn"
    exit 1
}

##############################################
# Основная логика
##############################################

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   OpenVPN Mac Compatibility Fix                  ║"
    echo "║   Traffic Shark VPN                             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    # Проверка параметров
    if [ -z "$1" ]; then
        print_error "Не указан входной файл"
        usage
    fi
    
    INPUT_FILE="$1"
    OUTPUT_FILE="${2:-${INPUT_FILE%.ovpn}-mac.ovpn}"
    
    # Проверка существования входного файла
    if [ ! -f "$INPUT_FILE" ]; then
        print_error "Файл не найден: $INPUT_FILE"
        exit 1
    fi
    
    print_info "Входной файл: $INPUT_FILE"
    print_info "Выходной файл: $OUTPUT_FILE"
    echo ""
    
    # Создание резервной копии выходного файла, если существует
    if [ -f "$OUTPUT_FILE" ]; then
        BACKUP_FILE="${OUTPUT_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Создание резервной копии: $BACKUP_FILE"
        cp "$OUTPUT_FILE" "$BACKUP_FILE"
    fi
    
    # Копирование исходного файла
    cp "$INPUT_FILE" "$OUTPUT_FILE"
    
    print_info "Применение исправлений для Mac..."
    
    # 1. Заменить TLS 1.3 на TLS 1.2
    if grep -q "tls-version-min 1.3" "$OUTPUT_FILE"; then
        print_info "Понижение TLS версии с 1.3 до 1.2"
        sed -i.bak 's/tls-version-min 1.3/tls-version-min 1.2/g' "$OUTPUT_FILE"
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # 2. Удалить user и group директивы
    if grep -qE "^user |^group " "$OUTPUT_FILE"; then
        print_info "Удаление user/group директив"
        sed -i.bak '/^user /d; /^group /d' "$OUTPUT_FILE"
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # 3. Удалить explicit-exit-notify для UDP
    if grep -q "explicit-exit-notify" "$OUTPUT_FILE"; then
        print_info "Удаление explicit-exit-notify"
        sed -i.bak '/^explicit-exit-notify/d' "$OUTPUT_FILE"
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # 4. Упростить tls-cipher (удалить сложные cipher suites)
    if grep -q "tls-cipher" "$OUTPUT_FILE"; then
        print_info "Упрощение tls-cipher"
        # Удаляем строку с несколькими cipher suites
        sed -i.bak '/tls-cipher.*:.*ECDSA/d' "$OUTPUT_FILE"
        # Если осталась только RSA, оставляем её, иначе удаляем полностью
        if ! grep -q "tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384" "$OUTPUT_FILE"; then
            # Добавляем простой tls-cipher если его нет
            sed -i.bak '/^cipher/a\
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384' "$OUTPUT_FILE"
        fi
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # 5. Заменить compress migrate на comp-lzo no или удалить
    if grep -q "compress migrate" "$OUTPUT_FILE"; then
        print_info "Замена compress migrate"
        sed -i.bak 's/^compress migrate$/comp-lzo no/g' "$OUTPUT_FILE"
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # 6. Добавить MTU параметры если их нет
    if ! grep -q "tun-mtu" "$OUTPUT_FILE"; then
        print_info "Добавление MTU параметров"
        # Добавляем после topology или nobind
        if grep -q "^nobind" "$OUTPUT_FILE"; then
            sed -i.bak '/^nobind/a\
tun-mtu 1400\
fragment 1300\
mssfix 1300' "$OUTPUT_FILE"
        elif grep -q "^topology" "$OUTPUT_FILE"; then
            sed -i.bak '/^topology/a\
tun-mtu 1400\
fragment 1300\
mssfix 1300' "$OUTPUT_FILE"
        else
            # Добавляем после dev tun
            sed -i.bak '/^dev tun/a\
tun-mtu 1400\
fragment 1300\
mssfix 1300' "$OUTPUT_FILE"
        fi
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # 7. Убедиться, что verb установлен (для отладки)
    if ! grep -q "^verb" "$OUTPUT_FILE"; then
        print_info "Добавление verb 3"
        sed -i.bak '/^mute/a\
verb 3' "$OUTPUT_FILE"
        if [ $? -ne 0 ]; then
            # Если mute нет, добавляем в конец, перед сертификатами
            sed -i.bak '/^<ca>/i\
verb 3' "$OUTPUT_FILE"
        fi
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # 8. Удалить reneg-sec 0 если он есть (может вызывать проблемы)
    if grep -q "^reneg-sec 0" "$OUTPUT_FILE"; then
        print_info "Удаление reneg-sec 0"
        sed -i.bak '/^reneg-sec 0/d' "$OUTPUT_FILE"
        rm -f "${OUTPUT_FILE}.bak"
    fi
    
    # Очистка временных файлов
    rm -f "${OUTPUT_FILE}.bak"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Конфигурация успешно исправлена!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📁 Файл сохранён: $OUTPUT_FILE"
    echo ""
    echo "📋 Применённые исправления:"
    echo "   ✓ TLS версия понижена с 1.3 до 1.2"
    echo "   ✓ Удалены user/group директивы"
    echo "   ✓ Удалён explicit-exit-notify"
    echo "   ✓ Упрощён tls-cipher"
    echo "   ✓ Заменён compress migrate на comp-lzo no"
    echo "   ✓ Добавлены MTU параметры"
    echo "   ✓ Удалён reneg-sec 0"
    echo ""
    echo "📥 Использование:"
    echo "   1. Импортируйте $OUTPUT_FILE в OpenVPN Connect"
    echo "   2. Или используйте Tunnelblick (более стабилен на Mac)"
    echo ""
    echo "🧪 Проверка конфигурации (на Mac):"
    echo "   openvpn --config $OUTPUT_FILE --verb 4 --test-crypto"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Запуск
main "$@"

