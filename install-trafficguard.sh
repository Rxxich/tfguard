#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v18.0 (Debian + Original Style + Smart Uninstall)

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

check_firewall_safety() {
    echo -e "${BLUE}[CHECK] Проверка конфигурации Firewall...${NC}"
    if command -v ufw >/dev/null; then
        UFW_STATUS=$(ufw status | grep "Status" | awk '{print $2}')
        if [[ "$UFW_STATUS" == "inactive" ]]; then
            UFW_RULES=$(ufw show added 2>/dev/null)
            if [[ "$UFW_RULES" != *"22"* ]] && [[ "$UFW_RULES" != *"SSH"* ]]; then
                echo -e "\n${RED}⛔ АВАРИЙНАЯ ОСТАНОВКА!${NC}"
                echo -e "${YELLOW}UFW выключен и нет правил SSH. Сначала сделайте: ufw allow ssh${NC}"
                exit 1
            fi
        fi
    fi
}

# --- БЕЛЫЙ СПИСОК ---
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
        read -p ">> " wl_choice
        case $wl_choice in
            1) read -p "IP/CIDR: " wl_ip; [[ -n "$wl_ip" ]] && echo "$wl_ip" >> "$WHITE_LIST"; apply_whitelist ;;
            2) cat "$WHITE_LIST"; read -p "[Enter]" ;;
            3) read -p "Удалить IP/CIDR: " wl_del; sed -i "\|^$wl_del$|d" "$WHITE_LIST"; apply_whitelist ;;
            0) return ;;
        esac
    done
}

# --- УДАЛЕНИЕ ---
uninstall_process() {
    clear
    echo -e "${RED}⚠ Полное удаление TrafficGuard...${NC}"
    
    # Запоминаем статус UFW перед действиями
    UFW_WAS_ACTIVE=$(ufw status | grep -q "active" && echo "yes" || echo "no")

    echo -e "${YELLOW}▶ Остановка сервисов...${NC}"
    ufw --force disable 2>/dev/null
    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null

    echo -e "${YELLOW}▶ Чистка iptables и ipset...${NC}"
    iptables -D INPUT -m set --match-set WHITE-LIST-V4 src -j ACCEPT 2>/dev/null
    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null
    iptables -F SCANNERS-BLOCK 2>/dev/null
    iptables -X SCANNERS-BLOCK 2>/dev/null
    
    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null
    ipset destroy WHITE-LIST-V4 2>/dev/null

    echo -e "${YELLOW}▶ Чистка конфигов UFW...${NC}"
    sed -i '/SCANNERS-BLOCK/d' /etc/ufw/before.rules /etc/ufw/after.rules /etc/ufw/user.rules 2>/dev/null
    sed -i '/WHITE-LIST/d' /etc/ufw/before.rules 2>/dev/null

    echo -e "${YELLOW}▶ Удаление файлов...${NC}"
    rm -f /usr/local/bin/traffic-guard /usr/local/bin/rknpidor "$MANAGER_PATH" "$CONFIG_FILE" "$MANUAL_FILE" "$WHITE_LIST"
    rm -f /etc/systemd/system/antiscan-* /var/log/iptables-scanners-*

    if [[ "$UFW_WAS_ACTIVE" == "yes" ]]; then
        echo -e "${YELLOW}▶ Возврат UFW в активное состояние...${NC}"
        ufw --force enable 2>/dev/null
        ufw reload 2>/dev/null
    fi

    echo -e "${GREEN}✔ Удаление завершено.${NC}"
    exit 0
}

install_process() {
    clear
    echo -e "${CYAN}🚀 УСТАНОВКА TRAFFICGUARD PRO${NC}"
    check_firewall_safety

    echo -e "\n${YELLOW}Выберите списки:${NC}"
    echo "1) LIST_GOV (Гос. сети)"
    echo "2) LIST_SCAN (Антисканнеры)"
    echo "3) ВСЕ ВМЕСТЕ"
    read -p "Выбор: " c
    case $c in
        1) echo "URLS=\"-u $LIST_GOV\"" > "$CONFIG_FILE" ;;
        2) echo "URLS=\"-u $LIST_SCAN\"" > "$CONFIG_FILE" ;;
        *) echo "URLS=\"-u $LIST_GOV -u $LIST_SCAN\"" > "$CONFIG_FILE" ;;
    esac

    apt-get update && apt-get install -y curl ipset ufw rsyslog
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
        # Считаем подсети
        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        [[ -z "$IPSET_CNT" ]] && IPSET_CNT="0"
        # Считаем пакеты (атаки)
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | awk 'END{print $1}')
        [[ -z "$PKTS_CNT" || "$PKTS_CNT" == "pkts" ]] && PKTS_CNT="0"

        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           🛡️  TRAFFICGUARD PRO MANAGER              ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "║  📊 Подсетей:       ${GREEN}${IPSET_CNT}${NC}                             "
        echo -e "║  🔥 Атак отбито:    ${RED}${PKTS_CNT}${NC}                             "
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e " ${GREEN}1.${NC} 🕵 Логи IPv4 (Live)"
        echo -e " ${GREEN}2.${NC} 🧪 Управление IP (Ban/Unban)"
        echo -e " ${YELLOW}3. 🏳️ Белый список (Whitelist)${NC}"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить списки"
        echo -e " ${RED}5.${NC} 🗑️  Удалить (Uninstall)"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        read -p "👉 Выбор: " choice
        case $choice in
            1) tail -f /var/log/iptables-scanners-ipv4.log ;;
            2) 
               read -p "Введите IP для бана: " r_ip
               [[ -n "$r_ip" ]] && ipset add SCANNERS-BLOCK-V4 "$r_ip" && echo "$r_ip" >> "$MANUAL_FILE"
               ;;
            3) manage_whitelist ;;
            4) source "$CONFIG_FILE"; traffic-guard full $URLS --enable-logging; apply_whitelist ;;
            5) uninstall_process ;;
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
else
    $MANAGER_PATH
fi
