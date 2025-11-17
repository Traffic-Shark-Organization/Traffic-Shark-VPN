#!/bin/bash
# Скрипт резервного копирования OpenVPN конфигурации и PKI
# Создает архив со всеми критическими файлами

set -e

##############################################
# Конфигурация
##############################################

BACKUP_DIR="/root/openvpn-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openvpn-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Директории для бэкапа
OPENVPN_DIR="/etc/openvpn"
CLIENT_CONFIG_DIR="$HOME/client-configs"
FIREWALL_BACKUP="/etc/iptables"

# Retention policy (количество дней хранения)
RETENTION_DAYS=30

# Encryption (опционально)
ENCRYPT_BACKUP=false
ENCRYPTION_PASSWORD=""

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

create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        print_info "Создание директории для бэкапов..."
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
        print_success "Директория создана: $BACKUP_DIR"
    fi
}

check_disk_space() {
    print_info "Проверка доступного места на диске..."
    
    local available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    local required_space=102400  # 100 MB в KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        print_warning "Мало свободного места на диске!"
        print_info "Доступно: $(($available_space / 1024)) MB"
        print_info "Рекомендуется: $(($required_space / 1024)) MB"
        
        read -p "Продолжить? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Достаточно места: $(($available_space / 1024)) MB"
    fi
}

create_backup_structure() {
    print_info "Создание структуры бэкапа..."
    
    mkdir -p "${BACKUP_PATH}"
    mkdir -p "${BACKUP_PATH}/openvpn"
    mkdir -p "${BACKUP_PATH}/easy-rsa"
    mkdir -p "${BACKUP_PATH}/client-configs"
    mkdir -p "${BACKUP_PATH}/firewall"
    mkdir -p "${BACKUP_PATH}/logs"
    
    print_success "Структура создана"
}

backup_openvpn_config() {
    print_info "Резервное копирование конфигурации OpenVPN..."
    
    if [ -d "$OPENVPN_DIR" ]; then
        # Конфигурационные файлы
        if [ -f "$OPENVPN_DIR/server.conf" ]; then
            cp "$OPENVPN_DIR/server.conf" "${BACKUP_PATH}/openvpn/"
        fi
        
        # Сертификаты и ключи
        for file in ca.crt server.crt server.key dh.pem ta.key crl.pem; do
            if [ -f "$OPENVPN_DIR/$file" ]; then
                cp "$OPENVPN_DIR/$file" "${BACKUP_PATH}/openvpn/"
            fi
        done
        
        print_success "Конфигурация OpenVPN скопирована"
    else
        print_warning "Директория OpenVPN не найдена"
    fi
}

backup_easy_rsa_pki() {
    print_info "Резервное копирование PKI (Certificate Authority)..."
    
    local easyrsa_dir="$OPENVPN_DIR/easy-rsa"
    
    if [ -d "$easyrsa_dir/pki" ]; then
        # Копирование всей PKI директории
        cp -r "$easyrsa_dir/pki" "${BACKUP_PATH}/easy-rsa/"
        
        # Копирование vars файла
        if [ -f "$easyrsa_dir/vars" ]; then
            cp "$easyrsa_dir/vars" "${BACKUP_PATH}/easy-rsa/"
        fi
        
        print_success "PKI скопирован"
        
        # Статистика сертификатов
        local valid_certs=$(grep "^V" "$easyrsa_dir/pki/index.txt" 2>/dev/null | wc -l || echo "0")
        local revoked_certs=$(grep "^R" "$easyrsa_dir/pki/index.txt" 2>/dev/null | wc -l || echo "0")
        print_info "Активных сертификатов: $valid_certs"
        print_info "Отозванных сертификатов: $revoked_certs"
    else
        print_warning "PKI директория не найдена"
    fi
}

backup_client_configs() {
    print_info "Резервное копирование клиентских конфигураций..."
    
    if [ -d "$CLIENT_CONFIG_DIR" ]; then
        # Копирование всех .ovpn файлов
        if [ -d "$CLIENT_CONFIG_DIR/files" ]; then
            cp -r "$CLIENT_CONFIG_DIR/files" "${BACKUP_PATH}/client-configs/"
        fi
        
        # Базовая конфигурация
        if [ -f "$CLIENT_CONFIG_DIR/base.conf" ]; then
            cp "$CLIENT_CONFIG_DIR/base.conf" "${BACKUP_PATH}/client-configs/"
        fi
        
        # Логи создания/отзыва клиентов
        for log in client-creation.log revocation.log; do
            if [ -f "$CLIENT_CONFIG_DIR/$log" ]; then
                cp "$CLIENT_CONFIG_DIR/$log" "${BACKUP_PATH}/client-configs/"
            fi
        done
        
        local ovpn_count=$(find "$CLIENT_CONFIG_DIR/files" -name "*.ovpn" 2>/dev/null | wc -l || echo "0")
        print_success "Клиентские конфигурации скопированы ($ovpn_count файлов)"
    else
        print_warning "Директория клиентских конфигураций не найдена"
    fi
}

backup_firewall_rules() {
    print_info "Резервное копирование правил firewall..."
    
    # iptables
    if [ -d "$FIREWALL_BACKUP" ]; then
        cp -r "$FIREWALL_BACKUP" "${BACKUP_PATH}/firewall/"
        print_success "Правила iptables скопированы"
    fi
    
    # Текущие правила
    iptables-save > "${BACKUP_PATH}/firewall/iptables-current.txt"
    
    # UFW (если используется)
    if command -v ufw &> /dev/null; then
        ufw status numbered > "${BACKUP_PATH}/firewall/ufw-status.txt" 2>/dev/null || true
        
        if [ -f /etc/ufw/before.rules ]; then
            cp /etc/ufw/before.rules "${BACKUP_PATH}/firewall/"
        fi
    fi
}

backup_logs() {
    print_info "Резервное копирование логов..."
    
    # OpenVPN логи (последние 10000 строк для экономии места)
    if [ -f "/var/log/openvpn/openvpn.log" ]; then
        tail -10000 /var/log/openvpn/openvpn.log > "${BACKUP_PATH}/logs/openvpn.log"
    fi
    
    if [ -f "/var/log/openvpn/openvpn-status.log" ]; then
        cp /var/log/openvpn/openvpn-status.log "${BACKUP_PATH}/logs/"
    fi
    
    # Systemd журнал OpenVPN (последние 5000 строк)
    journalctl -u openvpn@server -n 5000 > "${BACKUP_PATH}/logs/openvpn-systemd.log" 2>/dev/null || true
    
    print_success "Логи скопированы"
}

backup_system_info() {
    print_info "Сохранение информации о системе..."
    
    local info_file="${BACKUP_PATH}/system-info.txt"
    
    {
        echo "=== OpenVPN Backup Info ==="
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo ""
        echo "=== OpenVPN Version ==="
        openvpn --version | head -1
        echo ""
        echo "=== Network Interfaces ==="
        ip addr show
        echo ""
        echo "=== Routing Table ==="
        ip route show
        echo ""
        echo "=== Active Connections ==="
        if [ -f "/var/log/openvpn/openvpn-status.log" ]; then
            cat /var/log/openvpn/openvpn-status.log
        fi
        echo ""
        echo "=== OpenVPN Service Status ==="
        systemctl status openvpn@server --no-pager
    } > "$info_file"
    
    print_success "Системная информация сохранена"
}

create_archive() {
    print_info "Создание архива..."
    
    cd "$BACKUP_DIR"
    
    local archive_name="${BACKUP_NAME}.tar.gz"
    tar -czf "$archive_name" "$BACKUP_NAME" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local archive_size=$(du -h "${archive_name}" | awk '{print $1}')
        print_success "Архив создан: ${archive_name} (${archive_size})"
        
        # Удаление временной директории
        rm -rf "$BACKUP_PATH"
        
        # Установка правильных прав
        chmod 600 "$archive_name"
        
        # Возврат пути к архиву для других функций
        echo "$BACKUP_DIR/$archive_name"
    else
        print_error "Ошибка при создании архива"
        exit 1
    fi
}

encrypt_backup() {
    local archive_path=$1
    
    if [ "$ENCRYPT_BACKUP" = true ]; then
        print_info "Шифрование архива..."
        
        if [ -z "$ENCRYPTION_PASSWORD" ]; then
            read -sp "Введите пароль для шифрования: " ENCRYPTION_PASSWORD
            echo
            read -sp "Подтвердите пароль: " password_confirm
            echo
            
            if [ "$ENCRYPTION_PASSWORD" != "$password_confirm" ]; then
                print_error "Пароли не совпадают!"
                return 1
            fi
        fi
        
        # Шифрование с помощью openssl
        openssl enc -aes-256-cbc -salt -pbkdf2 \
            -in "$archive_path" \
            -out "${archive_path}.enc" \
            -pass pass:"$ENCRYPTION_PASSWORD"
        
        if [ $? -eq 0 ]; then
            print_success "Архив зашифрован"
            rm "$archive_path"
            print_info "Незашифрованная версия удалена"
            echo "${archive_path}.enc"
        else
            print_error "Ошибка при шифровании"
            return 1
        fi
    else
        echo "$archive_path"
    fi
}

cleanup_old_backups() {
    print_info "Очистка старых бэкапов (старше $RETENTION_DAYS дней)..."
    
    local deleted_count=0
    
    # Удаление архивов старше RETENTION_DAYS
    find "$BACKUP_DIR" -name "openvpn-backup-*.tar.gz*" -mtime +$RETENTION_DAYS -type f | while read file; do
        rm "$file"
        ((deleted_count++))
        print_info "Удален: $(basename $file)"
    done
    
    if [ $deleted_count -eq 0 ]; then
        print_success "Нет устаревших бэкапов для удаления"
    else
        print_success "Удалено бэкапов: $deleted_count"
    fi
    
    # Отображение оставшихся бэкапов
    local remaining_count=$(find "$BACKUP_DIR" -name "openvpn-backup-*.tar.gz*" -type f | wc -l)
    print_info "Всего бэкапов: $remaining_count"
}

verify_backup() {
    local archive_path=$1
    
    print_info "Проверка целостности архива..."
    
    tar -tzf "$archive_path" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "Архив валиден"
        
        # Отображение содержимого
        print_info "Содержимое архива:"
        tar -tzf "$archive_path" | head -20
        
        local total_files=$(tar -tzf "$archive_path" | wc -l)
        print_info "Всего файлов в архиве: $total_files"
    else
        print_error "Архив поврежден!"
        return 1
    fi
}

list_backups() {
    print_header "Список доступных бэкапов"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_warning "Директория бэкапов не существует"
        return
    fi
    
    local backups=$(find "$BACKUP_DIR" -name "openvpn-backup-*.tar.gz*" -type f | sort -r)
    
    if [ -z "$backups" ]; then
        print_warning "Бэкапы не найдены"
        return
    fi
    
    echo ""
    printf "%-35s %-10s %-20s\n" "Имя файла" "Размер" "Дата"
    echo "────────────────────────────────────────────────────────────────────"
    
    echo "$backups" | while read backup; do
        local filename=$(basename "$backup")
        local size=$(du -h "$backup" | awk '{print $1}')
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1 || stat -f "%Sm" -t "%Y-%m-%d" "$backup")
        
        printf "%-35s %-10s %-20s\n" "$filename" "$size" "$date"
    done
    
    echo ""
}

restore_info() {
    local archive_path=$1
    
    echo ""
    print_header "Информация о восстановлении"
    
    echo "Для восстановления из этого бэкапа:"
    echo ""
    echo "1. Распаковка архива:"
    echo "   tar -xzf $(basename $archive_path) -C /tmp/"
    echo ""
    echo "2. Остановка OpenVPN:"
    echo "   systemctl stop openvpn@server"
    echo ""
    echo "3. Восстановление файлов:"
    echo "   cp -r /tmp/${BACKUP_NAME}/openvpn/* /etc/openvpn/"
    echo "   cp -r /tmp/${BACKUP_NAME}/easy-rsa/* /etc/openvpn/easy-rsa/"
    echo ""
    echo "4. Восстановление firewall:"
    echo "   cp /tmp/${BACKUP_NAME}/firewall/iptables/rules.v4 /etc/iptables/"
    echo "   iptables-restore < /etc/iptables/rules.v4"
    echo ""
    echo "5. Запуск OpenVPN:"
    echo "   systemctl start openvpn@server"
    echo ""
    echo "6. Проверка:"
    echo "   systemctl status openvpn@server"
    echo ""
}

##############################################
# Основная логика
##############################################

main() {
    print_header "OpenVPN Backup Script - Traffic Shark VPN"
    
    # Обработка аргументов
    case "$1" in
        --list|-l)
            list_backups
            exit 0
            ;;
        --help|-h)
            echo "OpenVPN Backup Script"
            echo ""
            echo "Использование: $0 [ОПЦИЯ]"
            echo ""
            echo "Опции:"
            echo "  (нет)         Создать новый бэкап"
            echo "  -e, --encrypt Создать зашифрованный бэкап"
            echo "  -l, --list    Показать список существующих бэкапов"
            echo "  -h, --help    Эта справка"
            echo ""
            echo "Retention policy: $RETENTION_DAYS дней"
            echo "Backup directory: $BACKUP_DIR"
            echo ""
            exit 0
            ;;
        --encrypt|-e)
            ENCRYPT_BACKUP=true
            ;;
    esac
    
    # Проверки
    check_root
    create_backup_dir
    check_disk_space
    
    # Создание бэкапа
    print_info "Начало резервного копирования..."
    echo ""
    
    create_backup_structure
    backup_openvpn_config
    backup_easy_rsa_pki
    backup_client_configs
    backup_firewall_rules
    backup_logs
    backup_system_info
    
    # Создание архива
    echo ""
    archive_path=$(create_archive)
    
    # Шифрование (если требуется)
    if [ "$ENCRYPT_BACKUP" = true ]; then
        archive_path=$(encrypt_backup "$archive_path")
    fi
    
    # Проверка
    if [ -f "$archive_path" ]; then
        verify_backup "$archive_path"
    fi
    
    # Очистка старых бэкапов
    echo ""
    cleanup_old_backups
    
    # Итоговая информация
    print_header "Резервное копирование завершено"
    
    print_success "Бэкап сохранен: $archive_path"
    
    if [ "$ENCRYPT_BACKUP" = true ]; then
        print_warning "Бэкап зашифрован! Сохраните пароль в безопасном месте!"
        echo ""
        echo "Для расшифровки используйте:"
        echo "openssl enc -aes-256-cbc -d -pbkdf2 -in $(basename $archive_path) -out $(basename $archive_path .enc)"
    fi
    
    restore_info "$archive_path"
    
    # Рекомендации
    print_header "Рекомендации"
    echo "1. Сохраните бэкап в безопасном месте (не только на VPS)"
    echo "2. Регулярно тестируйте восстановление из бэкапов"
    echo "3. Используйте шифрование для удаленного хранения (-e опция)"
    echo "4. Настройте автоматическое создание бэкапов через cron:"
    echo "   0 3 * * * /root/scripts/backup.sh > /var/log/openvpn-backup.log 2>&1"
    echo ""
}

# Запуск
main "$@"

