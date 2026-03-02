#!/bin/ash
# ==============================================================================
# SOCKS5 Master Manager - Alpine Linux Edition
# Description: A secure, lightweight, interactive SOCKS5 proxy manager.
# Features: OpenRC (sockd), System User Auth (Locked), SSRF Protection
# Supported OS: Alpine Linux
# Author: Your-GitHub-Username
# ==============================================================================

set -uo pipefail

# ─── COLORS & FORMATTING ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─── ROOT CHECK ───────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}ERROR:${NC} This script requires root privileges to install packages and configure firewalls."
    echo -e "Please run it again using sudo: ${YELLOW}sudo ash socks_alpine.sh${NC}"
    exit 1
fi

# ─── CONSTANTS ────────────────────────────────────────────────────────────────
CONF_FILE="/etc/sockd.conf"
USER_LIST="/etc/socks_users.list"
LOCKFILE="/var/run/socks5-manager.lock"

# ─── LOCKFILE (prevent concurrent runs) ───────────────────────────────────────
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo -e "${RED}ERROR:${NC} Another instance of this script is already running. Exiting."
    exit 1
fi
trap 'flock -u 200; rm -f "$LOCKFILE"' EXIT

# ─── INPUT VALIDATION ─────────────────────────────────────────────────────────
function validate_username() {
    local u="$1"
    if [[ ! "$u" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
        echo -e "${RED}ERROR:${NC} Username must be 1-32 alphanumeric characters, underscores, or hyphens."
        return 1
    fi
    # Prevent tampering with core Alpine system users
    if [ "$u" = "root" ] || [ "$u" = "nobody" ] || [ "$u" = "daemon" ]; then
        echo -e "${RED}ERROR:${NC} Cannot use reserved system usernames."
        return 1
    fi
    return 0
}

function validate_port() {
    local p="$1"
    if [[ ! "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1024 ] || [ "$p" -gt 65535 ]; then
        echo -e "${RED}ERROR:${NC} Port must be a number between 1024 and 65535."
        return 1
    fi
    return 0
}

# ─── HELPER: REFRESH DATA ─────────────────────────────────────────────────────
function get_current_info() {
    CUR_IP=$(curl -4 -s --max-time 5 --fail https://icanhazip.com 2>/dev/null || ip -4 route get 8.8.8.8 | grep -oP 'src \K[0-9.]+' || echo "Unknown")
    CUR_PORT=$(grep "^internal:" "$CONF_FILE" 2>/dev/null | grep -oEo 'port=[0-9]+' | cut -d= -f2 || echo "Unknown")
}

# ─── HELPER: DETECT NETWORK INTERFACE ─────────────────────────────────────────
function get_iface() {
    ip -4 route get 8.8.8.8 | grep -oEo 'dev [^ ]+' | awk '{print $2}' | head -n 1
}

# ─── ACTION: ADD USER ─────────────────────────────────────────────────────────
function add_user() {
    get_current_info
    echo -e "\n${CYAN}--- Adding New User ---${NC}"
    read -p "Enter username [Enter for RANDOM]: " INPUT_USER

    local USER_NAME
    if [ -z "$INPUT_USER" ]; then
        USER_NAME=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
    else
        USER_NAME="$INPUT_USER"
        if ! validate_username "$USER_NAME"; then
            read -p "Press Enter to return to menu..."
            return
        fi
    fi

    if id "$USER_NAME" &>/dev/null; then
        echo -e "${RED}ERROR:${NC} User '$USER_NAME' already exists on this system."
        read -p "Press Enter to return to menu..."
        return
    fi

    # Pure alphanumeric, 20 characters
    local PASSWORD
    PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 20)

    # Alpine user creation: No Home Dir (-H), No Password init (-D), Nologin Shell (-s)
    adduser -D -H -s /sbin/nologin "$USER_NAME" >/dev/null 2>&1
    echo "$USER_NAME:$PASSWORD" | chpasswd

    # Track proxy users specifically
    echo "$USER_NAME" >> "$USER_LIST"

    rc-service sockd restart >/dev/null 2>&1 || echo -e "${YELLOW}[!] Warning: sockd restart failed${NC}"

    echo "------------------------------------------------"
    echo -e "${GREEN}User Added Successfully!${NC}"
    echo -e "Public IP:  ${CYAN}$CUR_IP${NC}"
    echo -e "Port:       ${CYAN}$CUR_PORT${NC}"
    echo -e "Username:   ${YELLOW}$USER_NAME${NC}"
    echo -e "Password:   ${YELLOW}$PASSWORD${NC}"
    echo "------------------------------------------------"
    read -p "Press Enter to return to menu..."
}

# ─── ACTION: INSTALL ──────────────────────────────────────────────────────────
function install_socks() {
    echo -e "\n${CYAN}--- First Time Setup (Alpine) ---${NC}"
    read -p "Enter global port [Enter for RANDOM 10000-65000]: " INPUT_PORT

    local PORT
    if [ -z "$INPUT_PORT" ]; then
        PORT=$(awk 'BEGIN{srand();print int(rand()*(65000-10000))+10000}')
    else
        if ! validate_port "$INPUT_PORT"; then
            echo -e "${RED}Aborting install.${NC}"
            exit 1
        fi
        PORT="$INPUT_PORT"
    fi

    local IFACE
    IFACE=$(get_iface)

    if [ -z "$IFACE" ]; then
        echo -e "${RED}ERROR:${NC} Could not detect network interface. Aborting."
        exit 1
    fi

    echo -e "${CYAN}[*] Installing dependencies via apk...${NC}"
    apk update -q
    apk add -q dante-server curl shadow

    touch "$USER_LIST"
    chmod 600 "$USER_LIST"

    # Alpine uses 'username' auth method naturally (checks /etc/shadow)
    cat > "$CONF_FILE" <<EOF
internal.protocol: ipv4
internal: $IFACE port=$PORT
external.protocol: ipv4
external: $IFACE

logoutput: stderr
socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
socks block { from: 0.0.0.0/0 to: 127.0.0.0/8 log: error }
socks block { from: 0.0.0.0/0 to: 10.0.0.0/8 log: error }
socks block { from: 0.0.0.0/0 to: 172.16.0.0/12 log: error }
socks block { from: 0.0.0.0/0 to: 192.168.0.0/16 log: error }
socks block { from: 0.0.0.0/0 to: 169.254.0.0/16 log: error }
socks block { from: 0.0.0.0/0 to: 100.64.0.0/10 log: error }
socks pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
EOF

    # Basic iptables rule if installed (Alpine default firewall)
    if command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
    fi

    rc-update add sockd default >/dev/null 2>&1
    rc-service sockd restart >/dev/null 2>&1 || true

    echo -e "${GREEN}[*] Installation complete on $IFACE:$PORT${NC}"
    add_user
}

# ─── MAIN MENU LOOP ───────────────────────────────────────────────────────────
while true; do
    clear
    if rc-service sockd status &>/dev/null; then
        get_current_info
        echo -e "${CYAN}╔══════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}   ${GREEN}Alpine SOCKS5 Master Manager${NC}   ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC} Status: ${GREEN}Running${NC}                  ${CYAN}║${NC}"
        printf  "${CYAN}║${NC} IP:   %-24s${CYAN}║${NC}\n" "$CUR_IP"
        printf  "${CYAN}║${NC} Port: %-24s${CYAN}║${NC}\n" "$CUR_PORT"
        echo -e "${CYAN}╠══════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC} 1) List Users                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC} 2) Add New User                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC} 3) Remove a User                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC} 4) Change Global Port            ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC} 5) Full Uninstall                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC} 6) Exit                          ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════╝${NC}"
        read -p "Option: " OPT

        case $OPT in
            1)
                echo -e "\n${CYAN}--- Active Proxy Users ---${NC}"
                if [ ! -s "$USER_LIST" ]; then
                    echo "No proxy users found."
                else
                    awk '{print NR") " $1}' "$USER_LIST"
                fi
                echo "--------------------------"
                read -p "Press Enter to return to menu..."
                ;;
            2)
                add_user
                ;;
            3)
                echo -e "\n${CYAN}--- Remove User ---${NC}"
                if [ ! -s "$USER_LIST" ]; then
                    echo "No users available to delete."
                else
                    awk '{print NR") " $1}' "$USER_LIST"
                    read -p "Enter exact username to DELETE (Enter to cancel): " R

                    if [ -z "$R" ]; then
                        echo "Action cancelled."
                    elif grep -qx "$R" "$USER_LIST"; then
                        deluser "$R" >/dev/null 2>&1
                        sed -i "/^$R\$/d" "$USER_LIST"
                        rc-service sockd restart >/dev/null 2>&1 || echo -e "${YELLOW}[!] Warning: sockd restart failed${NC}"
                        echo -e "${GREEN}User '$R' removed successfully.${NC}"
                    else
                        echo -e "${YELLOW}User not found in proxy list — no changes made.${NC}"
                    fi
                fi
                read -p "Press Enter to return to menu..."
                ;;
            4)
                read -p "Enter NEW global port (1024-65535): " NP
                if [ -z "$NP" ]; then
                    echo "No changes made."
                elif validate_port "$NP"; then
                    sed -i "s/port=[0-9]*/port=$NP/" "$CONF_FILE"
                    if rc-service sockd restart >/dev/null 2>&1; then
                        if command -v iptables &>/dev/null; then
                            iptables -D INPUT -p tcp --dport "$CUR_PORT" -j ACCEPT 2>/dev/null || true
                            iptables -I INPUT -p tcp --dport "$NP" -j ACCEPT
                        fi
                        echo -e "${GREEN}Port updated to $NP.${NC}"
                    else
                        sed -i "s/port=$NP/port=$CUR_PORT/" "$CONF_FILE"
                        rc-service sockd restart >/dev/null 2>&1 || true
                        echo -e "${RED}ERROR: Dante failed to restart. Port change rolled back.${NC}"
                    fi
                fi
                read -p "Press Enter to return to menu..."
                ;;
            5)
                read -p "DANGER: Wipe all SOCKS5 data? Type 'yes' to confirm: " W
                if [ "$W" = "yes" ]; then
                    rc-service sockd stop >/dev/null 2>&1 || true
                    rc-update del sockd default >/dev/null 2>&1 || true
                    
                    if [ -f "$USER_LIST" ]; then
                        while read -r u; do
                            deluser "$u" >/dev/null 2>&1
                        done < "$USER_LIST"
                    fi
                    
                    apk del -q dante-server
                    rm -f "$CONF_FILE" "$USER_LIST" "$LOCKFILE"
                    echo -e "${GREEN}Wipe complete. Exiting.${NC}"
                    exit 0
                else
                    echo "Uninstall cancelled."
                fi
                read -p "Press Enter to return to menu..."
                ;;
            6)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                sleep 1
                ;;
        esac
    else
        echo -e "${YELLOW}Dante is not running or is not installed.${NC}"
        read -p "Install now? (y/n): " START
        if [ "$START" = "y" ]; then
            install_socks
        else
            exit 0
        fi
    fi
done