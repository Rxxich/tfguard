#!/bin/bash

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"

rm -f "$MANAGER_PATH" "$LINK_PATH"

cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

TG_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST_GOV="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST_SCAN="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"

MANUAL_FILE="/opt/trafficguard-manual.list"
EXCLUDE_FILE="/opt/trafficguard-exclude.list"

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Запуск только от root!${NC}"; exit 1; }
}

# --- 🧪 УПРАВЛЕНИЕ РУЧНЫМИ БАНАМИ ---
manage_test_ip() {
    touch "$MANUAL_FILE"

    while true; do
        clear
        echo -e "${YELLOW}=== 🧪 РУЧНЫЕ БАНЫ ===${NC}"
        echo "1) Забанить IP"
        echo "2) Разбанить IP"
        echo "0) Назад"
        read -p "Выбор: " action < /dev/tty

        case $action in
            1)
                read -p "IP: " ip < /dev/tty
                [[ -z "$ip" ]] && continue
                ipset add SCANNERS-BLOCK-V4 "$ip" 2>/dev/null && \
                echo "$ip" >> "$MANUAL_FILE"
                echo "Готово"; sleep 1
                ;;
            2)
                read -p "IP: " ip < /dev/tty
                [[ -z "$ip" ]] && continue
                ipset del SCANNERS-BLOCK-V4 "$ip" 2>/dev/null
                sed -i "/^$ip$/d" "$MANUAL_FILE"
                echo "Удалено"; sleep 1
                ;;
            0) return ;;
        esac
    done
}

# --- 🤍 WHITELIST ---
manage_whitelist() {
    touch "$EXCLUDE_FILE"

    while true; do
        clear
        echo -e "${CYAN}=== 🤍 БЕЛЫЕ СЕТИ (ИСКЛЮЧЕНИЯ) ===${NC}"
        echo "1) Добавить подсеть"
        echo "2) Удалить подсеть"
        echo "3) Показать список"
        echo "0) Назад"
        read -p "Выбор: " action < /dev/tty

        case $action in
            1)
                read -p "Подсеть (пример 1.2.3.0/24): " subnet < /dev/tty
                [[ -z "$subnet" ]] && continue

                if ! grep -Fxq "$subnet" "$EXCLUDE_FILE"; then
                    echo "$subnet" >> "$EXCLUDE_FILE"
                fi

                ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null
                ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null

                echo -e "${GREEN}Добавлено в whitelist.${NC}"
                sleep 1
                ;;
            2)
                if [ ! -s "$EXCLUDE_FILE" ]; then
                    echo "Список пуст"; sleep 1; continue
                fi

                mapfile -t NETS < "$EXCLUDE_FILE"
                i=1
                for net in "${NETS[@]}"; do
                    echo "$i) $net"
                    ((i++))
                done

                read -p "Номер: " num < /dev/tty
                [[ -z "$num" ]] && continue

                INDEX=$((num-1))
                TARGET="${NETS[$INDEX]}"

                sed -i "/^$TARGET$/d" "$EXCLUDE_FILE"

                echo -e "${GREEN}Удалено из whitelist.${NC}"
                sleep 1
                ;;
            3)
                echo -e "\n${YELLOW}Список исключений:${NC}"
                cat "$EXCLUDE_FILE"
                read -p "[Enter]" < /dev/tty
                ;;
            0) return ;;
        esac
    done
}

# --- ОБНОВЛЕНИЕ СПИСКОВ ---
update_lists() {
    echo -e "\n${CYAN}Обновление списков...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    if [ -f "$EXCLUDE_FILE" ]; then
        while read -r subnet; do
            ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null
            ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null
        done < "$EXCLUDE_FILE"
    fi

    echo -e "${GREEN}Готово.${NC}"
    sleep 1
}

install_process() {
    clear
    echo -e "${CYAN}Установка TrafficGuard...${NC}"

    apt-get update
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils

    if command -v curl >/dev/null; then
        curl -fsSL "$TG_URL" | bash
    else
        wget -qO- "$TG_URL" | bash
    fi

    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    touch "$MANUAL_FILE"
    touch "$EXCLUDE_FILE"

    echo -e "${GREEN}Установка завершена.${NC}"
    sleep 2
}

show_menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TRAFFICGUARD MANAGER ===${NC}"
        echo "1) Управление банами"
        echo "2) Обновить списки"
        echo "3) Переустановить"
        echo "8) 🤍 Белые сети"
        echo "0) Выход"
        read -p "Выбор: " choice < /dev/tty

        case $choice in
            1) manage_test_ip ;;
            2) update_lists ;;
            3) install_process ;;
            8) manage_whitelist ;;
            0) exit 0 ;;
        esac
    done
}

check_root

case "${1:-}" in
    install) install_process ;;
    update) update_lists ;;
    *) show_menu ;;
esac
EOF

chmod +x "$MANAGER_PATH"
ln -s "$MANAGER_PATH" "$LINK_PATH"

if [[ ! -f /usr/local/bin/traffic-guard ]]; then
    /opt/trafficguard-manager.sh install
fi

/opt/trafficguard-manager.sh
