#!/bin/bash
# 🔥 TrafficGuard PRO v21.0 (Original Menu + Whitelist + Fixes)

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"
CONFIG_FILE="/etc/trafficguard.conf"

check_root() {
    [[ $EUID -ne 0 ]] && { echo "Запуск только от root!"; exit 1; }
}

# --- НАЧАЛО ЗАПИСИ СКРИПТА ---
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

# --- ТВОЯ ПРОВЕРКА FIREWALL ---
check_firewall_safety() {
    echo -e "${BLUE}[CHECK] Проверка конфигурации Firewall...${NC}"
    if command -v ufw >/dev/null; then
        UFW_STATUS=$(ufw status | grep "Status" | awk '{print $2}')
        UFW_RULES=$(ufw show added 2>/dev/null)
        if [[ "$UFW_STATUS" == "inactive" ]]; then
            if [[ "$UFW_RULES" != *"22"* ]] && [[ "$UFW_RULES" != *"SSH"* ]] && [[ "$UFW_RULES" != *"OpenSSH"* ]]; then
                echo -e "\n${RED}⛔ АВАРИЙНАЯ ОСТАНОВКА!${NC}"
                echo -e "${YELLOW}UFW выключен и нет правил SSH.${NC}"
                echo "Выполните: ufw allow ssh"
                exit 1
            fi
        fi
    else
        if ! dpkg -l | grep -q netfilter-persistent; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
        fi
    fi
}

# --- ЛОГИКА ПРОСМОТРА ЛОГОВ (FIX CTRL+C) ---
view_log() {
    local file=$1
    echo -e "\n${YELLOW}=== LIVE LOG (Нажми Ctrl+C для возврата в меню) ===${NC}"
    # trap ':' INT означает "игнорировать прерывание скрипта", 
    # но команда tail сама по себе остановится.
    trap ':' INT
    tail -f "$file"
    # Возвращаем стандартное поведение (выход) для меню
    trap 'exit 0' INT
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
    # Правило whitelist всегда первое
    if ! iptables -C INPUT -m set --match-set WHITE-LIST-V4 src -j ACCEPT 2>/dev/null; then
        iptables -I INPUT 1 -m set --match-set WHITE-LIST-V4 src -j ACCEPT
    fi
}

manage_whitelist() {
    while true; do
        clear
        echo -e "${CYAN}🏳️ УПРАВЛЕНИЕ БЕЛЫМ СПИСКОМ${NC}"
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

manage_test_ip() {
    touch "$MANUAL_FILE"
    while true; do
        clear
        echo -e "${YELLOW}=== 🧪 УПРАВЛЕНИЕ IP (Ручной бан) ===${NC}"
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
                    echo -e "${RED}Ошибка.${NC}"
                fi; sleep 1 ;;
            2)
                mapfile -t IPS < "$MANUAL_FILE"
                [[ ${#IPS[@]} -eq 0 ]] && echo "Список пуст" && sleep 1 && continue
                for i in "${!IPS[@]}"; do echo -e "${CYAN}$((i+1)))${NC} ${IPS[$i]}"; done
                read -p "Номер или IP: " target < /dev/tty
                if [[ "$target" =~ ^[0-9]+$ ]] && [ "$target" -le "${#IPS[@]}" ]; then
                    target="${IPS[$((target-1))]}"
                fi
                ipset del SCANNERS-BLOCK-V4 "$target" 2>/dev/null
                sed -i "\|^$target$|d" "$MANUAL_FILE"
                echo -e "${GREEN}Разбанен.${NC}"; sleep 1 ;;
            0) return ;;
        esac
    done
}

uninstall_process() {
    clear
    echo -e "${RED}⚠ УДАЛЕНИЕ TRAFFICGUARD...${NC}"
    
    # Отключаем UFW для очистки
    ufw --force disable 2>/dev/null
    
    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null

    iptables -D INPUT -m set --match-set WHITE-LIST-V4 src -j ACCEPT 2>/dev/null
    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null
    iptables -F SCANNERS-BLOCK 2>/dev/null
    iptables -X SCANNERS-BLOCK 2>/dev/null
    
    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null
    ipset destroy WHITE-LIST-V4 2>/dev/null

    # Чистка конфигов UFW
    sed -i '/SCANNERS-BLOCK/d' /etc/ufw/before.rules /etc/ufw/after.rules /etc/ufw/user.rules 2>/dev/null
    sed -i '/WHITE-LIST/d' /etc/ufw/before.rules 2>/dev/null
    sed -i '/ipset restore/d' /etc/ufw/before.rules 2>/dev/null

    # Удаление файлов
    rm -f /usr/local/bin/traffic-guard /usr/local/bin/rknpidor
    rm -f "$MANAGER_PATH" "$CONFIG_FILE" "$MANUAL_FILE" "$WHITE_LIST"
    rm -f /etc/systemd/system/antiscan-* /var/log/iptables-scanners-*

    echo -e "${YELLOW}▶ Включение UFW...${NC}"
    ufw --force enable
    ufw reload
    
    echo -e "${GREEN}✔ Готово. UFW работает.${NC}"
    exit 0
}

update_lists() {
    echo -e "\n${CYAN}🔄 Обновление...${NC}"
    source "$CONFIG_FILE"
    traffic-guard full $URLS --enable-logging
    apply_whitelist
    echo -e "${GREEN}✅ Готово!${NC}"; sleep 2
}

install_process() {
    clear
    echo -e "${CYAN}🚀 УСТАНОВКА TRAFFICGUARD PRO${NC}"
    check_firewall_safety

    echo -e "\n${YELLOW}Выберите списки:${NC}"
    echo "1) LIST_GOV (Гос. сети)"
    echo "2) LIST_SCAN (Антисканнеры)"
    echo "3) ВСЕ ВМЕСТЕ"
    
    # Читаем обязательно из терминала
    while [[ -z "${list_choice:-}" ]]; do
        read -p "Ваш выбор [1-3]: " list_choice < /dev/tty
    done
    
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
    
    # Создаем пустой файл CSV для корректной работы меню п.1
    touch /var/log/iptables-scanners-aggregate.csv
    
    echo -e "${GREEN}✅ Установка завершена!${NC}"
    sleep 2
}

show_menu() {
    # При выходе из меню - завершаем скрипт корректно
    trap 'exit 0' INT
    while true; do
        clear
        # Обновляем ipset перед показом
        apply_whitelist 2>/dev/null
        
        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep "Number of entries" | awk '{print $4}')
        [[ -z "$IPSET_CNT" ]] && IPSET_CNT="${RED}0${NC}"
        # Исправленный подсчет пакетов
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | grep "LOG" | awk '{print $1}') 
        # Если grep ничего не нашел или там пусто - ставим 0
        [[ -z "$PKTS_CNT" ]] && PKTS_CNT="0"
        
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
        echo -e " ${GREEN}4.${NC} 🏳️ Белый список (Whitelist)" 
        echo -e " ${GREEN}6.${NC} 🔄 Обновить списки (Update)"
        echo -e " ${GREEN}7.${NC} 🛠️  Переустановить (Reinstall)"
        echo -e " ${RED}8.${NC} 🗑️  Удалить (Uninstall)"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""
        
        echo -ne "${CYAN}👉 Ваш выбор:${NC} "
        read -r choice < /dev/tty

        case $choice in
            1)
                echo -e "\n${GREEN}ТОП 20:${NC}"
                [ -f /var/log/iptables-scanners-aggregate.csv ] && tail -20 /var/log/iptables-scanners-aggregate.csv || echo "Нет данных"
                read -p $'\n[Enter] назад...' < /dev/tty
                ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) manage_test_ip ;;
            5) manage_whitelist ;;
            6) update_lists ;;
            7) 
                rm -f /var/log/iptables-scanners-aggregate.csv
                install_process 
                ;;
            8) uninstall_process ;;
            0) exit 0 ;;
            *) echo "Неверно"; sleep 1 ;;
        esac
    done
}

check_root

# Если конфига нет — запускаем установку
if [[ ! -f "$CONFIG_FILE" ]]; then
    install_process
fi

# Иначе (или после установки) показываем меню
show_menu
EOF

# --- ПРАВА И ЗАПУСК ---
chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$LINK_PATH"
bash "$MANAGER_PATH"
