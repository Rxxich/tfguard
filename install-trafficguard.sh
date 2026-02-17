#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v18.9 (Final Debian Edition)

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"
MANUAL_FILE="/opt/trafficguard-manual.list"
WHITE_LIST="/opt/trafficguard-whitelist.list"
CONFIG_FILE="/etc/trafficguard.conf"

# 1. ЗАПИСЬ МЕНЕДЖЕРА
cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -u

# --- ЦВЕТА ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

TG_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
LIST_GOV="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list"
LIST_SCAN="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"
MANUAL_FILE="/opt/trafficguard-manual.list"
WHITE_LIST="/opt/trafficguard-whitelist.list"
CONFIG_FILE="/etc/trafficguard.conf"

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Запуск только от root!${NC}"; exit 1; }
}

view_log() {
    local file=$1
    echo -e "\n${YELLOW}=== LIVE LOG (Ctrl+C для возврата) ===${NC}"
    trap ':' INT
    tail -f "$file"
    trap 'exit 0' INT
}

apply_whitelist() {
    touch "$WHITE_LIST"
    ipset create WHITE-LIST-V4 hash:net family inet hashsize 1024 maxelem 65536 2>/dev/null
    ipset flush WHITE-LIST-V4
    while read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        ipset add WHITE-LIST-V4 "$line" 2>/dev/null
    done < "$WHITE_LIST"

    if ! iptables -C INPUT -m set --match-set WHITE-LIST-V4 src -j ACCEPT 2>/dev/null; then
        iptables -I INPUT 1 -m set --match-set WHITE-LIST-V4 src -j ACCEPT
    fi
}

manage_whitelist() {
    while true; do
        clear
        echo -e "${CYAN}🏳️ УПРАВЛЕНИЕ БЕЛЫМ СПИСКОМ (Исключения)${NC}"
        echo -e "1) Добавить IP/подсеть"
        echo -e "2) Показать список"
        echo -e "3) Удалить из списка"
        echo -e "0) Назад"
        read -p ">> " wl_choice < /dev/tty
        case $wl_choice in
            1) read -p "IP/CIDR: " wl_ip < /dev/tty; [[ -n "$wl_ip" ]] && echo "$wl_ip" >> "$WHITE_LIST"; apply_whitelist ;;
            2) cat "$WHITE_LIST"; read -p "[Enter]" < /dev/tty ;;
            3) read -p "Удалить IP/CIDR: " wl_del < /dev/tty; sed -i "\|^$wl_del$|d" "$WHITE_LIST"; apply_whitelist ;;
            0) return ;;
        esac
    done
}

manage_manual_ips() {
    touch "$MANUAL_FILE"
    while true; do
        clear
        echo -e "${YELLOW}=== 🧪 УПРАВЛЕНИЕ IP ===${NC}"
        echo -e " 1. ⛔ ЗАБАНИТЬ IP"
        echo -e " 2. ✅ РАЗБАНИТЬ IP (из списка)"
        echo -e " 0. ↩️ Назад"
        read -p "Выбор: " act < /dev/tty
        case $act in
            1)
                read -p "Введите IP: " ip < /dev/tty
                [[ -z "$ip" ]] && continue
                if ipset add SCANNERS-BLOCK-V4 "$ip" 2>/dev/null; then
                    [[ -z $(grep -Fx "$ip" "$MANUAL_FILE") ]] && echo "$ip" >> "$MANUAL_FILE"
                    echo -e "${GREEN}Заблокирован.${NC}"
                else
                    echo -e "${RED}Ошибка блокировки.${NC}"
                fi; sleep 1 ;;
            2)
                mapfile -t IPS < "$MANUAL_FILE"
                [[ ${#IPS[@]} -eq 0 ]] && echo "Список пуст" && sleep 1 && continue
                for i in "${!IPS[@]}"; do echo -e "${CYAN}$((i+1)))${NC} ${IPS[$i]}"; done
                read -p "Номер или IP: " target < /dev/tty
                [[ -z "$target" ]] && continue
                if [[ "$target" =~ ^[0-9]+$ ]] && [ "$target" -le "${#IPS[@]}" ]; then
                    IP_TO_DEL="${IPS[$((target-1))]}"
                else
                    IP_TO_DEL="$target"
                fi
                ipset del SCANNERS-BLOCK-V4 "$IP_TO_DEL" 2>/dev/null
                sed -i "\|^$IP_TO_DEL$|d" "$MANUAL_FILE"
                echo -e "${GREEN}Разбанен.${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}

uninstall_process() {
    clear
    echo -e "${RED}⚠ Полное удаление TrafficGuard...${NC}"
    
    # Отключаем UFW для безопасной чистки правил
    ufw --force disable 2>/dev/null
    
    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null

    echo -e "${YELLOW}▶ Чистка iptables и ipset...${NC}"
    iptables -D INPUT -m set --match-set WHITE-LIST-V4 src -j ACCEPT 2>/dev/null
    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null
    iptables -F SCANNERS-BLOCK 2>/dev/null
    iptables -X SCANNERS-BLOCK 2>/dev/null
    
    ip6tables -D INPUT -j SCANNERS-BLOCK-V6 2>/dev/null
    ip6tables -F SCANNERS-BLOCK-V6 2>/dev/null
    ip6tables -X SCANNERS-BLOCK-V6 2>/dev/null

    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null
    ipset destroy WHITE-LIST-V4 2>/dev/null

    echo -e "${YELLOW}▶ Чистка конфигов UFW...${NC}"
    sed -i '/SCANNERS-BLOCK/d' /etc/ufw/before.rules /etc/ufw/after.rules /etc/ufw/user.rules 2>/dev/null
    sed -i '/WHITE-LIST/d' /etc/ufw/before.rules 2>/dev/null
    sed -i '/ipset restore/d' /etc/ufw/before.rules 2>/dev/null

    echo -e "${YELLOW}▶ Удаление файлов...${NC}"
    rm -f /usr/local/bin/traffic-guard /usr/local/bin/rknpidor "$MANAGER_PATH" "$CONFIG_FILE" "$MANUAL_FILE" "$WHITE_LIST"
    rm -f /etc/systemd/system/antiscan-* /var/log/iptables-scanners-*

    echo -e "${YELLOW}▶ Принудительное включение UFW...${NC}"
    ufw --force enable
    ufw reload

    echo -e "${GREEN}✔ TrafficGuard удалён. UFW включен.${NC}"
    exit 0
}

install_process() {
    clear
    echo -e "${CYAN}🚀 УСТАНОВКА TRAFFICGUARD PRO${NC}"
    
    echo -e "\n${YELLOW}Выберите списки:${NC}"
    echo "1) LIST_GOV (Гос. сети)"
    echo "2) LIST_SCAN (Антисканнеры)"
    echo "3) ВСЕ ВМЕСТЕ"
    read -p "Выбор: " list_choice < /dev/tty
    
    case $list_choice in
        1) echo "URLS=\"-u $LIST_GOV\"" > "$CONFIG_FILE" ;;
        2) echo "URLS=\"-u $LIST_SCAN\"" > "$CONFIG_FILE" ;;
        *) echo "URLS=\"-u $LIST_GOV -u $LIST_SCAN\"" > "$CONFIG_FILE" ;;
    esac

    apt-get update -qq && apt-get install -y curl ipset ufw rsyslog iptables-persistent -qq
    curl -fsSL "$TG_URL" | bash
    
    source "$CONFIG_FILE"
    traffic-guard full $URLS --enable-logging
    apply_whitelist
    echo -e "${GREEN}✅ Готово!${NC}"; sleep 2
}

show_menu() {
    while true; do
        clear
        apply_whitelist 2>/dev/null
        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        [[ -z "$IPSET_CNT" ]] && IPSET_CNT="0"
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | awk 'NR>2 {sum+=$1} END {print sum+0}')

        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           🛡️  TRAFFICGUARD PRO MANAGER              ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "║  📊 Подсетей:       ${GREEN}${IPSET_CNT}${NC}                             "
        echo -e "║  🔥 Атак отбито:    ${RED}${PKTS_CNT}${NC}                             "
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e " ${GREEN}1.${NC} 📈 Топ атак (CSV)"
        echo -e " ${GREEN}2.${NC} 🕵 Логи IPv4 (Live)"
        echo -e " ${GREEN}3.${NC} 🕵 Логи IPv6 (Live)"
        echo -e " ${GREEN}4.${NC} 🧪 Управление IP (Ban/Unban)"
        echo -e " ${YELLOW}5. 🏳️ Белый список (Whitelist)${NC}"
        echo -e " ${GREEN}6.${NC} 🔄 Обновить списки"
        echo -e " ${RED}7.${NC} 🗑️ Удалить (Uninstall)"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        read -p "👉 Ваш выбор: " choice < /dev/tty
        case $choice in
            1) 
                echo -e "\n${GREEN}ТОП 20:${NC}"
                [ -f /var/log/iptables-scanners-aggregate.csv ] && tail -20 /var/log/iptables-scanners-aggregate.csv || echo "Нет данных"
                read -p $'\n[Enter] назад...' < /dev/tty ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) manage_manual_ips ;;
            5) manage_whitelist ;;
            6) source "$CONFIG_FILE"; traffic-guard full $URLS --enable-logging; apply_whitelist ;;
            7) uninstall_process ;;
            0) exit 0 ;;
        esac
    done
}

check_root
case "${1:-}" in
    install) install_process ;;
    *) show_menu ;; 
esac
EOF

# 2. ПРАВА И ЗАПУСК
chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$LINK_PATH"

if [[ ! -f "$CONFIG_FILE" ]]; then
    $MANAGER_PATH install
fi
$MANAGER_PATH
