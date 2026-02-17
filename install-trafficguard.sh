#!/bin/bash
# 🔥 TrafficGuard PRO v19.0 (FINAL DEBIAN FIX)

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"
CONFIG_FILE="/etc/trafficguard.conf"

check_root() {
    [[ $EUID -ne 0 ]] && { echo "Запуск только от root!"; exit 1; }
}

# 1. ЗАПИСЬ ТЕЛА МЕНЕДЖЕРА
cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

CONFIG_FILE="/etc/trafficguard.conf"
WHITE_LIST="/opt/trafficguard-whitelist.list"
MANUAL_FILE="/opt/trafficguard-manual.list"

apply_whitelist() {
    touch "$WHITE_LIST"
    ipset create WHITE-LIST-V4 hash:net family inet 2>/dev/null
    ipset flush WHITE-LIST-V4
    while read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        ipset add WHITE-LIST-V4 "$line" 2>/dev/null
    done < "$WHITE_LIST"
    iptables -I INPUT 1 -m set --match-set WHITE-LIST-V4 src -j ACCEPT 2>/dev/null
}

uninstall_process() {
    clear
    echo -e "${RED}▶ Полное удаление...${NC}"
    
    # 1. Отключаем сервисы
    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null

    # 2. Чистим правила и ipset
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

    # 3. Чистим конфиги UFW (твои блоки)
    sed -i '/SCANNERS-BLOCK/d' /etc/ufw/before.rules /etc/ufw/after.rules /etc/ufw/user.rules 2>/dev/null
    sed -i '/WHITE-LIST/d' /etc/ufw/before.rules 2>/dev/null
    sed -i '/ipset restore/d' /etc/ufw/before.rules 2>/dev/null

    # 4. Удаляем ВСЕ файлы
    rm -f /usr/local/bin/traffic-guard
    rm -f /usr/local/bin/rknpidor
    rm -f /opt/trafficguard-manager.sh
    rm -f /etc/trafficguard.conf
    rm -f /opt/trafficguard-manual.list
    rm -f /opt/trafficguard-whitelist.list
    rm -f /etc/systemd/system/antiscan-*
    rm -f /var/log/iptables-scanners-*
    
    # 5. ВКЛЮЧАЕМ UFW ОБРАТНО
    echo -e "${YELLOW}▶ Принудительное включение UFW...${NC}"
    ufw --force enable
    ufw reload
    
    echo -e "${GREEN}✔ Система очищена. UFW работает.${NC}"
    exit 0
}

install_process() {
    clear
    echo -e "${CYAN}🚀 НАСТРОЙКА СПИСКОВ${NC}"
    echo -e "1) Гос. сети  2) Антисканнеры  3) Все вместе"
    read -p "Выбор: " choice < /dev/tty
    
    case $choice in
        1) URLS="-u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list" ;;
        2) URLS="-u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list" ;;
        *) URLS="-u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list -u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list" ;;
    esac
    echo "URLS=\"$URLS\"" > "$CONFIG_FILE"

    apt-get update && apt-get install -y curl ipset ufw rsyslog
    curl -fsSL https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh | bash
    
    source "$CONFIG_FILE"
    traffic-guard full $URLS --enable-logging
    apply_whitelist
    echo -e "${GREEN}✅ Установка завершена!${NC}"
}

show_menu() {
    while true; do
        clear
        apply_whitelist 2>/dev/null
        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | awk 'NR>2 {sum+=$1} END {print sum+0}')
        echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
        echo -e "║      🛡️  TRAFFICGUARD PRO MANAGER       ║"
        echo -e "╠══════════════════════════════════════════╣${NC}"
        echo -e "║  📊 Подсетей: ${GREEN}${IPSET_CNT:-0}${NC}  🔥 Атак: ${RED}${PKTS_CNT:-0}${NC} ║"
        echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
        echo -e " 1. 📈 Топ (CSV)   2. 🕵 Лог v4   3. 🕵 Лог v6"
        echo -e " 4. 🧪 Бан/Разбан  5. 🏳️ Белый список"
        echo -e " 6. 🔄 Обновить    7. 🗑️  УДАЛИТЬ С КОРНЕМ"
        echo -e " 0. ❌ Выход"
        read -p ">> " m < /dev/tty
        case $m in
            1) tail -20 /var/log/iptables-scanners-aggregate.csv; read -p "..." < /dev/tty ;;
            2) tail -f /var/log/iptables-scanners-ipv4.log ;;
            3) tail -f /var/log/iptables-scanners-ipv6.log ;;
            4) read -p "IP: " ip < /dev/tty; ipset add SCANNERS-BLOCK-V4 "$ip" ;;
            5) read -p "IP/CIDR: " wl < /dev/tty; echo "$wl" >> "$WHITE_LIST"; apply_whitelist ;;
            6) source "$CONFIG_FILE"; traffic-guard full $URLS --enable-logging; apply_whitelist ;;
            7) uninstall_process ;;
            0) exit 0 ;;
        esac
    done
}

[[ ! -f "$CONFIG_FILE" ]] && install_process
show_menu
EOF

# 2. ЗАПУСК
check_root
chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$LINK_PATH"
bash "$MANAGER_PATH"
