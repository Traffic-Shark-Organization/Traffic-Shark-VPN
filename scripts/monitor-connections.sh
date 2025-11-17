#!/bin/bash
# Скрипт для мониторинга OpenVPN подключений
# Показывает статистику и активные соединения

##############################################
# Конфигурация
##############################################

STATUS_FILE="/var/log/openvpn/openvpn-status.log"
LOG_FILE="/var/log/openvpn/openvpn.log"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

##############################################
# Функции
##############################################

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}$1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "────────────────────────────────────────────────────────────────────"
}

check_openvpn_status() {
    if ! systemctl is-active --quiet openvpn@server; then
        echo -e "${RED}✗ OpenVPN сервер не запущен!${NC}"
        echo ""
        echo "Запустите сервер: systemctl start openvpn@server"
        exit 1
    fi
}

check_status_file() {
    if [ ! -f "$STATUS_FILE" ]; then
        echo -e "${RED}✗ Файл статуса не найден: $STATUS_FILE${NC}"
        echo ""
        echo "Проверьте конфигурацию OpenVPN (директива status)"
        exit 1
    fi
}

format_bytes() {
    local bytes=$1
    
    if [ $bytes -lt 1024 ]; then
        echo "${bytes} B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}") KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
    fi
}

format_duration() {
    local seconds=$1
    
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $days -gt 0 ]; then
        printf "%dd %dh %dm" $days $hours $minutes
    elif [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

get_uptime() {
    local start_time=$(systemctl show openvpn@server -p ActiveEnterTimestamp --value)
    if [ ! -z "$start_time" ]; then
        local start_epoch=$(date -d "$start_time" +%s)
        local current_epoch=$(date +%s)
        local uptime_seconds=$((current_epoch - start_epoch))
        format_duration $uptime_seconds
    else
        echo "Unknown"
    fi
}

show_server_info() {
    print_section "Информация о сервере"
    
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "N/A")
    local uptime=$(get_uptime)
    local tun_ip=$(ip addr show tun0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    
    echo -e "${GREEN}Сервер:${NC} $(hostname)"
    echo -e "${GREEN}Внешний IP:${NC} $server_ip"
    echo -e "${GREEN}VPN IP:${NC} ${tun_ip:-N/A}"
    echo -e "${GREEN}Uptime:${NC} $uptime"
    echo -e "${GREEN}Статус:${NC} $(systemctl is-active openvpn@server)"
}

show_active_connections() {
    print_section "Активные подключения"
    
    if [ ! -f "$STATUS_FILE" ]; then
        echo "Файл статуса не найден"
        return
    fi
    
    # Подсчет клиентов
    local client_count=$(grep -c "^CLIENT_LIST" "$STATUS_FILE" 2>/dev/null || echo "0")
    
    if [ "$client_count" -eq 0 ]; then
        echo -e "${YELLOW}Нет активных подключений${NC}"
        return
    fi
    
    echo -e "${GREEN}Всего клиентов: $client_count${NC}"
    echo ""
    
    # Заголовок таблицы
    printf "%-20s %-15s %-15s %-12s %-12s %-12s\n" \
        "Клиент" "Реальный IP" "VPN IP" "RX" "TX" "Подключен"
    echo "────────────────────────────────────────────────────────────────────────────────────────"
    
    # Парсинг CLIENT_LIST
    grep "^CLIENT_LIST" "$STATUS_FILE" | while IFS=',' read -r prefix name real_ip virtual_ip bytes_rx bytes_tx connected_since; do
        # Вычисление длительности подключения
        local connect_epoch=$(date -d "$connected_since" +%s 2>/dev/null || echo "0")
        local current_epoch=$(date +%s)
        local duration=$((current_epoch - connect_epoch))
        local duration_str=$(format_duration $duration)
        
        # Форматирование трафика
        local rx_formatted=$(format_bytes $bytes_rx)
        local tx_formatted=$(format_bytes $bytes_tx)
        
        # Извлечение только IP без порта
        local ip_only=$(echo "$real_ip" | cut -d':' -f1)
        
        printf "%-20s %-15s %-15s %-12s %-12s %-12s\n" \
            "$name" "$ip_only" "$virtual_ip" "$rx_formatted" "$tx_formatted" "$duration_str"
    done
}

show_routing_table() {
    print_section "Таблица маршрутизации клиентов"
    
    if [ ! -f "$STATUS_FILE" ]; then
        echo "Файл статуса не найден"
        return
    fi
    
    # Проверка наличия routing таблицы
    if ! grep -q "^ROUTING_TABLE" "$STATUS_FILE"; then
        echo "Routing таблица пуста"
        return
    fi
    
    printf "%-15s %-20s %-15s %-20s\n" \
        "VPN IP" "Клиент" "Реальный IP" "Последняя активность"
    echo "────────────────────────────────────────────────────────────────────────────────────"
    
    grep "^ROUTING_TABLE" "$STATUS_FILE" | while IFS=',' read -r prefix vip name real_ip timestamp; do
        local ip_only=$(echo "$real_ip" | cut -d':' -f1)
        local time_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")
        
        printf "%-15s %-20s %-15s %-20s\n" \
            "$vip" "$name" "$ip_only" "$time_str"
    done
}

show_traffic_stats() {
    print_section "Статистика трафика"
    
    if [ ! -f "$STATUS_FILE" ]; then
        echo "Файл статуса не найден"
        return
    fi
    
    local total_rx=0
    local total_tx=0
    
    # Суммирование трафика всех клиентов
    while IFS=',' read -r prefix name real_ip virtual_ip bytes_rx bytes_tx rest; do
        total_rx=$((total_rx + bytes_rx))
        total_tx=$((total_tx + bytes_tx))
    done < <(grep "^CLIENT_LIST" "$STATUS_FILE")
    
    local total_traffic=$((total_rx + total_tx))
    
    echo -e "${GREEN}Получено (RX):${NC} $(format_bytes $total_rx)"
    echo -e "${GREEN}Отправлено (TX):${NC} $(format_bytes $total_tx)"
    echo -e "${GREEN}Всего:${NC} $(format_bytes $total_traffic)"
}

show_system_stats() {
    print_section "Системная информация"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    
    # Memory usage
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_used=$(free -m | awk '/^Mem:/{print $3}')
    local mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")
    
    # Disk usage
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    
    # Network stats for tun0
    if [ -d "/sys/class/net/tun0" ]; then
        local tun_rx=$(cat /sys/class/net/tun0/statistics/rx_bytes)
        local tun_tx=$(cat /sys/class/net/tun0/statistics/tx_bytes)
        
        echo -e "${GREEN}CPU:${NC} ${cpu_usage}%"
        echo -e "${GREEN}RAM:${NC} ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"
        echo -e "${GREEN}Диск:${NC} $disk_usage"
        echo -e "${GREEN}TUN0 RX:${NC} $(format_bytes $tun_rx)"
        echo -e "${GREEN}TUN0 TX:${NC} $(format_bytes $tun_tx)"
    else
        echo -e "${GREEN}CPU:${NC} ${cpu_usage}%"
        echo -e "${GREEN}RAM:${NC} ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"
        echo -e "${GREEN}Диск:${NC} $disk_usage"
        echo -e "${YELLOW}TUN0 интерфейс не активен${NC}"
    fi
}

show_recent_connections() {
    print_section "Последние подключения (10 шт.)"
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "Лог-файл не найден"
        return
    fi
    
    grep "CONNECTED" "$LOG_FILE" | tail -10 | while read line; do
        echo "$line"
    done
}

show_recent_disconnections() {
    print_section "Последние отключения (10 шт.)"
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "Лог-файл не найден"
        return
    fi
    
    grep "SIGTERM\|connection reset" "$LOG_FILE" | tail -10 | while read line; do
        echo "$line"
    done
}

watch_mode() {
    while true; do
        clear
        main_display
        echo ""
        echo -e "${YELLOW}Обновление каждые 5 секунд. Ctrl+C для выхода.${NC}"
        sleep 5
    done
}

main_display() {
    print_header "OpenVPN Connection Monitor - Traffic Shark VPN"
    
    show_server_info
    show_active_connections
    show_traffic_stats
    show_system_stats
    
    if [ "$1" == "--full" ] || [ "$1" == "-f" ]; then
        show_routing_table
        show_recent_connections
        show_recent_disconnections
    fi
    
    echo ""
    print_header "$(date '+%Y-%m-%d %H:%M:%S')"
}

##############################################
# Основная логика
##############################################

main() {
    check_openvpn_status
    check_status_file
    
    case "$1" in
        --watch|-w)
            watch_mode
            ;;
        --full|-f)
            main_display --full
            ;;
        --help|-h)
            echo "OpenVPN Connection Monitor"
            echo ""
            echo "Использование: $0 [ОПЦИЯ]"
            echo ""
            echo "Опции:"
            echo "  (нет)        Базовая информация"
            echo "  -f, --full   Полная информация с routing таблицей и логами"
            echo "  -w, --watch  Режим реального времени (обновление каждые 5 сек)"
            echo "  -h, --help   Эта справка"
            echo ""
            ;;
        *)
            main_display
            ;;
    esac
}

# Запуск
main "$@"

