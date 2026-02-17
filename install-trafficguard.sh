#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v16.1 (Whitelist Edition) — Улучшенная версия

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"
MANUAL_FILE="/opt/trafficguard-manual.list"
EXCLUDE_FILE="/opt/trafficguard-exclude.list"

# Удаляем старые файлы
rm -f "$MANAGER_PATH" "$LINK_PATH"

cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -euo pipefail

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
    apt-get update -qq
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils whois

    systemctl enable --now rsyslog >/dev/null 2>&1

    if command -v curl >/dev/null; then
        curl -fsSL "$TG_URL" | bash
    else
        wget -qO- "$TG_URL" | bash
    fi

    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    touch "$MANUAL_FILE"
    touch "$EXCLUDE_FILE"

    apply_whitelist

    echo -e "${GREEN}✅ Установка завершена!${NC}"
    sleep 2
}

# Применение whitelist (исключение подсетей из блока)
apply_whitelist() {
    if [ ! -s "$EXCLUDE_FILE" ]; then
        return
    fi

    echo -e "${CYAN}Применяем whitelist...${NC}"
    while read -r subnet || [ -n "$subnet" ]; do
        [[ -z "$subnet" ]] && continue
        ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null || true
        ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null || true
    done < "$EXCLUDE_FILE"
}

# ---------------- UNINSTALL ----------------
uninstall_process() {
    echo -e "\n${RED}=== УДАЛЕНИЕ TRAFFICGUARD ===${NC}"
    read -p "Вы уверены? (y/N): " confirm < /dev/tty
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return

    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null || true
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null || true

    rm -f /usr/local/bin/traffic-guard
    rm -f /usr/local/bin/antiscan-aggregate-logs.sh
    rm -f /etc/systemd/system/antiscan-*
    rm -f /etc/rsyslog.d/10-iptables-scanners.conf
    rm -f /etc/logrotate.d/iptables-scanners
    rm -f "$LINK_PATH"
    rm -f "$MANAGER_PATH"
    rm -f "$MANUAL_FILE" "$EXCLUDE_FILE"

    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null || true
    iptables -F SCANNERS-BLOCK 2>/dev/null || true
    iptables -X SCANNERS-BLOCK 2>/dev/null || true

    ipset flush SCANNERS-BLOCK-V4 2>/dev/null || true
    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null || true
    ipset flush SCANNERS-BLOCK-V6 2>/dev/null || true
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null || true

    echo -e "${GREEN}✅ TrafficGuard полностью удалён.${NC}"
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
        echo -e " ${CYAN}0.${NC} ↩️ Назад"
        echo ""

        read -p "👉 Действие: " action < /dev/tty

        case $action in
            1)
                read -p "Подсеть (пример: 1.2.3.0/24 или 2a00::/32): " subnet < /dev/tty
                [[ -z "$subnet" ]] && continue

                if grep -Fxq "$subnet" "$EXCLUDE_FILE"; then
                    echo -e "${YELLOW}Эта подсеть уже в whitelist${NC}"
                else
                    echo "$subnet" >> "$EXCLUDE_FILE"
                    ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null || true
                    ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null || true
                    echo -e "${GREEN}✅ Подсеть добавлена в whitelist${NC}"
                fi
                read -p "[Enter]..." < /dev/tty
                ;;

            2)
                mapfile -t NETS < "$EXCLUDE_FILE"
                if [ ${#NETS[@]} -eq 0 ]; then
                    echo -e "${RED}Whitelist пуст${NC}"
                    read -p "[Enter]..." < /dev/tty
                    continue
                fi

                echo -e "${YELLOW}Текущий whitelist:${NC}"
                for i in "${!NETS[@]}"; do
                    printf "%2d) %s\n" $((i+1)) "${NETS[i]}"
                done

                read -p "Номер для удаления: " num < /dev/tty
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#NETS[@]}" ]; then
                    TARGET="${NETS[$((num-1))]}"

                    # Удаляем из файла
                    grep -vFx -- "$TARGET" "$EXCLUDE_FILE" > "${EXCLUDE_FILE}.tmp" && mv "${EXCLUDE_FILE}.tmp" "$EXCLUDE_FILE"

                    # ВАЖНО: Возвращаем в блок
                    if [[ "$TARGET" == *:* ]]; then
                        ipset add SCANNERS-BLOCK-V6 "$TARGET" 2>/dev/null || true
                    else
                        ipset add SCANNERS-BLOCK-V4 "$TARGET" 2>/dev/null || true
                    fi

                    echo -e "${GREEN}✅ $TARGET удалён из whitelist и возвращён в блок${NC}"
                else
                    echo -e "${RED}Неверный номер${NC}"
                fi
                read -p "[Enter]..." < /dev/tty
                ;;

            3)
                if [ -s "$EXCLUDE_FILE" ]; then
                    echo -e "${YELLOW}Содержимое whitelist:${NC}"
                    cat -n "$EXCLUDE_FILE"
                else
                    echo -e "${YELLOW}Whitelist пуст${NC}"
                fi
                read -p "[Enter]..." < /dev/tty
                ;;

            0) return ;;
            *) echo -e "${RED}Неверный выбор${NC}"; read -p "[Enter]..." < /dev/tty ;;
        esac
    done
}

# ---------------- UPDATE ----------------
update_lists() {
    echo -e "\n${CYAN}🔄 Обновление списков блокировок...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging
    apply_whitelist
    echo -e "${GREEN}✅ Списки обновлены и whitelist применён${NC}"
    sleep 2
}

# ---------------- LOGS ----------------
view_log() {
    clear
    echo -e "${YELLOW}=== LIVE LOG (Ctrl+C для выхода) ===${NC}"
    echo -e "${CYAN}Файл: $1${NC}"
    tail -f "$1"
}

# ---------------- MENU ----------------
show_menu() {
    trap 'exit 0' INT
    while true; do
        clear

        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -oP 'Number of entries: \K\d+' || echo 0)
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | awk '/LOG/ {sum += $1} END {print sum+0}' || echo 0)

        printf "${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
        printf "${CYAN}║ 🛡️  TRAFFICGUARD PRO MANAGER v16.1                  ║${NC}\n"
        printf "${CYAN}╠══════════════════════════════════════════════════════╣${NC}\n"
        printf "║ 📊 Заблокировано подсетей : ${GREEN}%-28s${NC}║\n" "$IPSET_CNT"
        printf "║ 🔥 Атак отбито            : ${RED}%-28s${NC}║\n" "$PKTS_CNT"
        printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"
        echo ""

        echo -e " ${GREEN}1.${NC} 📈 Топ атак (последние 20)"
        echo -e " ${GREEN}2.${NC} 🕵 Логи IPv4 (Live)"
        echo -e " ${GREEN}3.${NC} 🕵 Логи IPv6 (Live)"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить списки"
        echo -e " ${GREEN}5.${NC} 🛠️  Переустановить"
        echo -e " ${GREEN}8.${NC} 🤍 Управление whitelist"
        echo -e " ${RED}7.${NC} 🗑️  Полностью удалить"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""

        read -p "👉 Ваш выбор: " choice < /dev/tty

        case $choice in
            1)
                echo -e "\n${GREEN}ТОП 20 атак:${NC}"
                if [ -f /var/log/iptables-scanners-aggregate.csv ]; then
                    tail -20 /var/log/iptables-scanners-aggregate.csv
                else
                    echo "Нет данных"
                fi
                read -p $'\n[Enter] для продолжения...' < /dev/tty
                ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) update_lists ;;
            5) install_process ;;
            7) uninstall_process ;;
            8) manage_whitelist ;;
            0) exit 0 ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

# ================== MAIN ==================
check_root

case "${1:-}" in
    install)   install_process ;;
    update)    update_lists ;;
    uninstall) uninstall_process ;;
    *)         show_menu ;;
esac
EOF

chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$LINK_PATH"

echo -e "${GREEN}✅ TrafficGuard PRO Manager v16.1 успешно установлен!${NC}"
echo -e "Запуск: ${CYAN}rknpidor${NC} (или просто выполни команду ниже)"

# Запуск меню
exec "$MANAGER_PATH"#!/bin/bash
# 🔥 TrafficGuard PRO INSTALLER v16.1 (Whitelist Edition) — Улучшенная версия

MANAGER_PATH="/opt/trafficguard-manager.sh"
LINK_PATH="/usr/local/bin/rknpidor"
MANUAL_FILE="/opt/trafficguard-manual.list"
EXCLUDE_FILE="/opt/trafficguard-exclude.list"

# Удаляем старые файлы
rm -f "$MANAGER_PATH" "$LINK_PATH"

cat > "$MANAGER_PATH" << 'EOF'
#!/bin/bash
set -euo pipefail

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
    apt-get update -qq
    apt-get install -y curl wget rsyslog ipset ufw grep sed coreutils whois

    systemctl enable --now rsyslog >/dev/null 2>&1

    if command -v curl >/dev/null; then
        curl -fsSL "$TG_URL" | bash
    else
        wget -qO- "$TG_URL" | bash
    fi

    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging

    touch "$MANUAL_FILE"
    touch "$EXCLUDE_FILE"

    apply_whitelist

    echo -e "${GREEN}✅ Установка завершена!${NC}"
    sleep 2
}

# Применение whitelist (исключение подсетей из блока)
apply_whitelist() {
    if [ ! -s "$EXCLUDE_FILE" ]; then
        return
    fi

    echo -e "${CYAN}Применяем whitelist...${NC}"
    while read -r subnet || [ -n "$subnet" ]; do
        [[ -z "$subnet" ]] && continue
        ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null || true
        ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null || true
    done < "$EXCLUDE_FILE"
}

# ---------------- UNINSTALL ----------------
uninstall_process() {
    echo -e "\n${RED}=== УДАЛЕНИЕ TRAFFICGUARD ===${NC}"
    read -p "Вы уверены? (y/N): " confirm < /dev/tty
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return

    systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null || true
    systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null || true

    rm -f /usr/local/bin/traffic-guard
    rm -f /usr/local/bin/antiscan-aggregate-logs.sh
    rm -f /etc/systemd/system/antiscan-*
    rm -f /etc/rsyslog.d/10-iptables-scanners.conf
    rm -f /etc/logrotate.d/iptables-scanners
    rm -f "$LINK_PATH"
    rm -f "$MANAGER_PATH"
    rm -f "$MANUAL_FILE" "$EXCLUDE_FILE"

    iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null || true
    iptables -F SCANNERS-BLOCK 2>/dev/null || true
    iptables -X SCANNERS-BLOCK 2>/dev/null || true

    ipset flush SCANNERS-BLOCK-V4 2>/dev/null || true
    ipset destroy SCANNERS-BLOCK-V4 2>/dev/null || true
    ipset flush SCANNERS-BLOCK-V6 2>/dev/null || true
    ipset destroy SCANNERS-BLOCK-V6 2>/dev/null || true

    echo -e "${GREEN}✅ TrafficGuard полностью удалён.${NC}"
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
        echo -e " ${CYAN}0.${NC} ↩️ Назад"
        echo ""

        read -p "👉 Действие: " action < /dev/tty

        case $action in
            1)
                read -p "Подсеть (пример: 1.2.3.0/24 или 2a00::/32): " subnet < /dev/tty
                [[ -z "$subnet" ]] && continue

                if grep -Fxq "$subnet" "$EXCLUDE_FILE"; then
                    echo -e "${YELLOW}Эта подсеть уже в whitelist${NC}"
                else
                    echo "$subnet" >> "$EXCLUDE_FILE"
                    ipset del SCANNERS-BLOCK-V4 "$subnet" 2>/dev/null || true
                    ipset del SCANNERS-BLOCK-V6 "$subnet" 2>/dev/null || true
                    echo -e "${GREEN}✅ Подсеть добавлена в whitelist${NC}"
                fi
                read -p "[Enter]..." < /dev/tty
                ;;

            2)
                mapfile -t NETS < "$EXCLUDE_FILE"
                if [ ${#NETS[@]} -eq 0 ]; then
                    echo -e "${RED}Whitelist пуст${NC}"
                    read -p "[Enter]..." < /dev/tty
                    continue
                fi

                echo -e "${YELLOW}Текущий whitelist:${NC}"
                for i in "${!NETS[@]}"; do
                    printf "%2d) %s\n" $((i+1)) "${NETS[i]}"
                done

                read -p "Номер для удаления: " num < /dev/tty
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#NETS[@]}" ]; then
                    TARGET="${NETS[$((num-1))]}"

                    # Удаляем из файла
                    grep -vFx -- "$TARGET" "$EXCLUDE_FILE" > "${EXCLUDE_FILE}.tmp" && mv "${EXCLUDE_FILE}.tmp" "$EXCLUDE_FILE"

                    # ВАЖНО: Возвращаем в блок
                    if [[ "$TARGET" == *:* ]]; then
                        ipset add SCANNERS-BLOCK-V6 "$TARGET" 2>/dev/null || true
                    else
                        ipset add SCANNERS-BLOCK-V4 "$TARGET" 2>/dev/null || true
                    fi

                    echo -e "${GREEN}✅ $TARGET удалён из whitelist и возвращён в блок${NC}"
                else
                    echo -e "${RED}Неверный номер${NC}"
                fi
                read -p "[Enter]..." < /dev/tty
                ;;

            3)
                if [ -s "$EXCLUDE_FILE" ]; then
                    echo -e "${YELLOW}Содержимое whitelist:${NC}"
                    cat -n "$EXCLUDE_FILE"
                else
                    echo -e "${YELLOW}Whitelist пуст${NC}"
                fi
                read -p "[Enter]..." < /dev/tty
                ;;

            0) return ;;
            *) echo -e "${RED}Неверный выбор${NC}"; read -p "[Enter]..." < /dev/tty ;;
        esac
    done
}

# ---------------- UPDATE ----------------
update_lists() {
    echo -e "\n${CYAN}🔄 Обновление списков блокировок...${NC}"
    traffic-guard full -u "$LIST_GOV" -u "$LIST_SCAN" --enable-logging
    apply_whitelist
    echo -e "${GREEN}✅ Списки обновлены и whitelist применён${NC}"
    sleep 2
}

# ---------------- LOGS ----------------
view_log() {
    clear
    echo -e "${YELLOW}=== LIVE LOG (Ctrl+C для выхода) ===${NC}"
    echo -e "${CYAN}Файл: $1${NC}"
    tail -f "$1"
}

# ---------------- MENU ----------------
show_menu() {
    trap 'exit 0' INT
    while true; do
        clear

        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -oP 'Number of entries: \K\d+' || echo 0)
        PKTS_CNT=$(iptables -vnL SCANNERS-BLOCK 2>/dev/null | awk '/LOG/ {sum += $1} END {print sum+0}' || echo 0)

        printf "${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
        printf "${CYAN}║ 🛡️  TRAFFICGUARD PRO MANAGER v16.1                  ║${NC}\n"
        printf "${CYAN}╠══════════════════════════════════════════════════════╣${NC}\n"
        printf "║ 📊 Заблокировано подсетей : ${GREEN}%-28s${NC}║\n" "$IPSET_CNT"
        printf "║ 🔥 Атак отбито            : ${RED}%-28s${NC}║\n" "$PKTS_CNT"
        printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"
        echo ""

        echo -e " ${GREEN}1.${NC} 📈 Топ атак (последние 20)"
        echo -e " ${GREEN}2.${NC} 🕵 Логи IPv4 (Live)"
        echo -e " ${GREEN}3.${NC} 🕵 Логи IPv6 (Live)"
        echo -e " ${GREEN}4.${NC} 🔄 Обновить списки"
        echo -e " ${GREEN}5.${NC} 🛠️  Переустановить"
        echo -e " ${GREEN}8.${NC} 🤍 Управление whitelist"
        echo -e " ${RED}7.${NC} 🗑️  Полностью удалить"
        echo -e " ${RED}0.${NC} ❌ Выход"
        echo ""

        read -p "👉 Ваш выбор: " choice < /dev/tty

        case $choice in
            1)
                echo -e "\n${GREEN}ТОП 20 атак:${NC}"
                if [ -f /var/log/iptables-scanners-aggregate.csv ]; then
                    tail -20 /var/log/iptables-scanners-aggregate.csv
                else
                    echo "Нет данных"
                fi
                read -p $'\n[Enter] для продолжения...' < /dev/tty
                ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) update_lists ;;
            5) install_process ;;
            7) uninstall_process ;;
            8) manage_whitelist ;;
            0) exit 0 ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

# ================== MAIN ==================
check_root

case "${1:-}" in
    install)   install_process ;;
    update)    update_lists ;;
    uninstall) uninstall_process ;;
    *)         show_menu ;;
esac
EOF

chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$LINK_PATH"

echo -e "${GREEN}✅ TrafficGuard PRO Manager v16.1 успешно установлен!${NC}"
echo -e "Запуск: ${CYAN}rknpidor${NC} (или просто выполни команду ниже)"

# Запуск меню
exec "$MANAGER_PATH"
