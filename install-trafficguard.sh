#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v16.0 (Whitelist Edition)

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"
MANUAL_FILE="/opt/trafficguard-manual.list"
EXCLUDE_FILE="/opt/trafficguard-exclude.list"

rm -f "$MANAGER_PATH" "$LINK_PATH"

cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

TG_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST_GOV="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST_SCAN="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"

MANUAL_FILE="/opt/trafficguard-manual.list"
EXCLUDE_FILE="/opt/trafficguard-exclude.list"

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Запуск только от root!${NC}"; exit 1; }
}

# ---------------- INSTALL ----------------

install_process() {
    clear
    echo -e "${CYAN}🚀 УСТАНОВКА TRAFFICGUARD PRO${NC}"

    apt-get update
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils whois
    systemctl enable --now rsyslog

    if command -v curl >/dev/null; then
        curl -fsSL "$TG_URL" | bash
    else
        wget -qO- "$TG_URL" | bash
    fi

    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    touch "$MANUAL_FILE"
    touch "$EXCLUDE_FILE"

    echo -e "${GREEN}✅ Установка завершена!${NC}"
    sleep 2
}

# ---------------- UNINSTALL ----------------

uninstall_process() {
    echo -e "\n${RED}=== УДАЛЕНИЕ TRAFFICGUARD ===${NC}"
    read -p "Вы уверены? (y/N): " confirm < /dev/tty
    [[ "$confirm" != "y" ]] && return

    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null

    rm -f /usr/local/bin/traffic-guard
    rm -f /usr/local/bin/antiscan-aggregate-logs.sh
    rm -f /etc/systemd/system/antiscan-* 
    rm -f /etc/rsyslog.d/10-iptables-scanners.conf
    rm -f /etc/logrotate.d/iptables-scanners

    rm -f /usr/local/bin/rknpidor
    rm -f /opt/trafficguard-manager.sh
    rm -f "$MANUAL_FILE" "$EXCLUDE_FILE"

    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null
    iptables -F SCANNERS-BLOCK 2>/dev/null
    iptables -X SCANNERS-BLOCK 2>/dev/null

    ipset flush SCANNERS-BLOCK-V4 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
    ipset flush SCANNERS-BLOCK-V6 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null

    echo -e "${GREEN}✅ Полностью удалено.${NC}"
    exit 0
}

# ---------------- WHITELIST ----------------

manage_whitelist() {
    touch "$EXCLUDE_FILE"

    while true; do
        clear
        echo -e "${YELLOW}=== 🤍 БЕЛЫЕ СЕТИ (Whitelist) ===${NC}"
        echo -e " ${GREEN}1.${NC} ➕ Добавить подсеть"
        echo -e " ${RED}2.${NC} ➖ Удалить подсеть"
        echo -e " ${CYAN}3.${NC} 📄 Показать список"
        echo -e " ${CYAN}0.${NC} ↩️  Назад"
        echo ""
        read -p "👉 Действие: " action < /dev/tty

        case $action in
            1)
                read -p "Подсеть (пример 1.2.3.0/24): " subnet < /dev/tty
                [[ -z "$subnet" ]] && continue
                grep -Fxq "$subnet" "$EXCLUDE_FILE" || echo "$subnet" >> "$EXCLUDE_FILE"
                ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null
                ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null
                echo -e "${GREEN}✅ Добавлено.${NC}"
                read -p "[Enter]..." < /dev/tty
                ;;
            2)
                mapfile -t NETS < "$EXCLUDE_FILE"
                i=1
                for net in "${NETS[@]}"; do
                    echo "$i) $net"
                    ((i++))
                done
                read -p "Номер: " num < /dev/tty
                INDEX=$((num-1))
                TARGET="${NETS[$INDEX]}"
                sed -i "/^$TARGET$/d" "$EXCLUDE_FILE"
                echo -e "${GREEN}Удалено.${NC}"
                read -p "[Enter]..." < /dev/tty
                ;;
            3)
                cat "$EXCLUDE_FILE"
                read -p "[Enter]..." < /dev/tty
                ;;
            0) return ;;
        esac
    done
}

# ---------------- UPDATE ----------------

update_lists() {
    echo -e "\n${CYAN}🔄 Обновление списков...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    if [ -f "$EXCLUDE_FILE" ]; then
        while read -r subnet; do
            ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null
            ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null
        done < "$EXCLUDE_FILE"
    fi

    echo -e "${GREEN}✅ Готово!${NC}"
    sleep 2
}

# ---------------- LOGS ----------------

view_log() {
    clear
    echo -e "${YELLOW}=== LIVE LOG (Ctrl+C для выхода) ===${NC}"
    tail -f "$1"
}

# ---------------- MENU ----------------

show_menu() {
    trap 'exit 0' INT
    while true; do
        clear

        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        [[ -z "$IPSET_CNT" ]] && IPSET_CNT="0"

        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | grep "LOG" | awk '{print $1}')
        [[ -z "$PKTS_CNT" ]] && PKTS_CNT="0"

        printf "${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
        printf "${CYAN}║           🛡️  TRAFFICGUARD PRO MANAGER               ║${NC}\n"
        printf "${CYAN}╠══════════════════════════════════════════════════════╣${NC}\n"
        printf "║  📊 Подсетей:       ${GREEN}%-36s${NC}║\n" "$IPSET_CNT"
        printf "║  🔥 Атак отбито:    ${RED}%-36s${NC}║\n" "$PKTS_CNT"
        printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"

        echo ""
        echo -e " ${GREEN}1.${NC} 📈 Топ атак (CSV)"
        echo -e " ${GREEN}2.${NC} 🕵 Логи IPv4 (Live)"
        echo -e " ${GREEN}3.${NC} 🕵 Логи IPv6 (Live)"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить списки"
        echo -e " ${GREEN}5.${NC} 🛠️  Переустановить"
        echo -e " ${GREEN}8.${NC} 🤍 Белые сети"
        echo -e " ${RED}7.${NC} 🗑️  Удалить"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        read -p "👉 Ваш выбор: " choice < /dev/tty

        case $choice in
            1) 
                echo -e "\n${GREEN}ТОП 20:${NC}"
                [ -f /var/log/iptables-scanners-aggregate.csv ] && tail -20 /var/log/iptables-scanners-aggregate.csv || echo "Нет данных"
                read -p $'\n[Enter] назад...' < /dev/tty
                ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) update_lists ;;
            5) install_process ;;
            7) uninstall_process ;;
            8) manage_whitelist ;;
            0) exit 0 ;;
        esac
    done
}

check_root

case "${1:-}" in
    install) install_process ;;
    update) update_lists ;;
    uninstall) uninstall_process ;;
    *) show_menu ;;
esac
EOF

chmod +x "$MANAGER_PATH"
ln -s "$MANAGER_PATH" "$LINK_PATH"

if [[ ! -f /usr/local/bin/traffic-guard ]]; then
    /opt/trafficguard-manager.sh install
fi

/opt/trafficguard-manager.sh monitor
