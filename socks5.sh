#!/bin/bash
# ==============================================================================
# SOCKS5 Master Manager - Ultra-Light Edition
# Description: A secure, lightweight, interactive SOCKS5 proxy manager.
# Features: Non-root Auth, SSRF Protection, SHA-512, Low-RAM Auto-Swap
# Supported OS: Debian 11+, Ubuntu 20.04+
# ==============================================================================

set -uo pipefail

# ─── COLORS & FORMATTING ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─── ROOT CHECK ───────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}ERROR:${NC} This script requires root privileges to install packages and configure firewalls."
    echo -e "Please run it again using sudo: ${YELLOW}sudo bash socks_manager.sh${NC}"
    exit 1
fi

# ─── CONSTANTS ────────────────────────────────────────────────────────────────
PASSWD_FILE="/etc/danted.passwd"
CONF_FILE="/etc/danted.conf"
LOCKFILE="/var/run/socks5-manager.lock"

# ─── LOCKFILE (prevent concurrent runs) ───────────────────────────────────────
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo -e "${RED}ERROR:${NC} Another instance of this script is already running. Exiting."
    exit 1
fi
trap 'flock -u 200; rm -f "$LOCKFILE"' EXIT

# Sanitize passwd file of any CRLF line endings on startup
if [ -f "$PASSWD_FILE" ]; then
    sed -i 's/\r//' "$PASSWD_FILE"
fi

# ─── INPUT VALIDATION ─────────────────────────────────────────────────────────
function validate_username() {
    local u="$1"
    if [[ ! "$u" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
        echo -e "${RED}ERROR:${NC} Username must be 1-32 alphanumeric characters, underscores, or hyphens."
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
    CUR_PORT=$(grep "^internal:" "$CONF_FILE" 2>/dev/null | grep -oP 'port=\K[0-9]+' || echo "Unknown")
}

# ─── HELPER: DETECT NETWORK INTERFACE ─────────────────────────────────────────
function get_iface() {
    ip -4 route get 8.8.8.8 | grep -oP 'dev \K\S+'
}

# ─── ACTION: ADD USER ─────────────────────────────────────────────────────────
function add_user() {
    get_current_info
    echo -e "\n${CYAN}--- Adding New User ---${NC}"
    read -rp "Enter username [Enter for RANDOM]: " INPUT_USER

    local USER_NAME
    if [ -z "$INPUT_USER" ]; then
        USER_NAME=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
    else
        USER_NAME="$INPUT_USER"
        if ! validate_username "$USER_NAME"; then
            read -rp "Press Enter to return to menu..."
            return
        fi
    fi

    if grep -q "^${USER_NAME}:" "$PASSWD_FILE" 2>/dev/null; then
        echo -e "${RED}ERROR:${NC} User '$USER_NAME' already exists."
        read -rp "Press Enter to return to menu..."
        return
    fi

    local PASSWORD
    PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 20)
    local HASHED
    HASHED=$(openssl passwd -6 -stdin <<< "$PASSWORD")

    printf '%s:%s\n' "$USER_NAME" "$HASHED" >> "$PASSWD_FILE"
    chmod 600 "$PASSWD_FILE"
    systemctl restart danted || echo -e "${YELLOW}[!] Warning: danted restart failed${NC}"

    echo "------------------------------------------------"
    echo -e "${GREEN}User Added Successfully!${NC}"
    echo -e "Public IP:  ${CYAN}$CUR_IP${NC}"
    echo -e "Port:       ${CYAN}$CUR_PORT${NC}"
    echo -e "Username:   ${YELLOW}$USER_NAME${NC}"
    echo -e "Password:   ${YELLOW}$PASSWORD${NC}"
    echo "------------------------------------------------"
    read -rp "Press Enter to return to menu..."
}

# ─── ACTION: INSTALL ──────────────────────────────────────────────────────────
function install_socks() {
    echo -e "\n${CYAN}--- First Time Setup ---${NC}"
    read -rp "Enter global port [Enter for RANDOM 10000-65000]: " INPUT_PORT

    local PORT
    if [ -z "$INPUT_PORT" ]; then
        PORT=$(shuf -i 10000-65000 -n 1)
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

    local SWAP_CREATED=0
    local TOTAL_RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    local SWAP_SIZE
    SWAP_SIZE=$(free -m | awk '/^Swap:/{print $2}')

    if [ "$TOTAL_RAM" -lt 512 ] && [ "$SWAP_SIZE" -eq 0 ]; then
        echo -e "${YELLOW}[*] Low memory detected (${TOTAL_RAM}MB). Creating temporary swap...${NC}"
        if fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null; then
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null 2>&1
            swapon /swapfile >/dev/null 2>&1
            SWAP_CREATED=1
        fi
    fi

    echo -e "${CYAN}[*] Installing dependencies...${NC}"
    apt-get update -qq
    apt-get install -y libpam-pwdfile openssl curl wget

    if ! apt-get install -y dante-server 2>/dev/null; then
        echo -e "${YELLOW}[!] dante-server missing from repo. Pulling Debian fallback...${NC}"
        ARCH=$(dpkg --print-architecture)
        wget -qO dante.deb "http://ftp.us.debian.org/debian/pool/main/d/dante/dante-server_1.4.2+dfsg-7+b8_${ARCH}.deb"
        apt-get install -y ./dante.deb
        rm -f dante.deb
    fi

    touch "$PASSWD_FILE"
    chmod 600 "$PASSWD_FILE"
    chown root:root "$PASSWD_FILE"

    cat > /etc/pam.d/sockd <<EOF
auth    required pam_pwdfile.so nodelay pwdfile=$PASSWD_FILE
account required pam_permit.so
EOF

    cat > "$CONF_FILE" <<EOF
internal.protocol: ipv4
internal: $IFACE port=$PORT
external.protocol: ipv4
external: $IFACE

logoutput: stderr
socksmethod: pam.any
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

    if command -v ufw &>/dev/null; then
        ufw allow "$PORT"/tcp
    fi

    systemctl enable danted
    systemctl restart danted || true

    if [ "$SWAP_CREATED" -eq 1 ]; then
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
    fi

    echo -e "${GREEN}[*] Installation complete on $IFACE:$PORT${NC}"
    add_user
}

# ─── MAIN MENU LOOP ───────────────────────────────────────────────────────────
while true; do
    clear
    if systemctl is-active --quiet danted; then
        get_current_info
        echo -e "${CYAN}╔══════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}      ${GREEN}SOCKS5 Master Manager${NC}       ${CYAN}║${NC}"
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
        read -rp "Option: " OPT

        case $OPT in
            1)
                echo -e "\n${CYAN}--- Active Users ---${NC}"
                if [ ! -s "$PASSWD_FILE" ]; then
                    echo "No users found."
                else
                    awk -F: '{print NR") " $1}' "$PASSWD_FILE"
                fi
                echo "--------------------"
                read -rp "Press Enter to return to menu..."
                ;;
            2)
                add_user
                ;;
            3)
                echo -e "\n${CYAN}--- Remove User ---${NC}"
                if [ ! -s "$PASSWD_FILE" ]; then
                    echo "No users available to delete."
                else
                    awk -F: '{print NR") " $1}' "$PASSWD_FILE"
                    read -rp "Enter exact username to DELETE (Enter to cancel): " R

                    if [ -z "$R" ]; then
                        echo "Action cancelled."
                    elif ! validate_username "$R"; then
                        echo -e "${RED}Invalid username format — no changes made.${NC}"
                    elif grep -qP "^${R}:" <(sed 's/\r//' "$PASSWD_FILE"); then
                        sed 's/\r//' "$PASSWD_FILE" | grep -vP "^${R}:" > "${PASSWD_FILE}.tmp"
                        mv "${PASSWD_FILE}.tmp" "$PASSWD_FILE"
                        chmod 600 "$PASSWD_FILE"
                        systemctl restart danted || echo -e "${YELLOW}[!] Warning: danted restart failed${NC}"
                        echo -e "${GREEN}User '$R' removed successfully.${NC}"
                    else
                        echo -e "${YELLOW}User not found — no changes made.${NC}"
                    fi
                fi
                read -rp "Press Enter to return to menu..."
                ;;
            4)
                read -rp "Enter NEW global port (1024-65535): " NP
                if [ -z "$NP" ]; then
                    echo "No changes made."
                elif validate_port "$NP"; then
                    sed -i "s/port=[0-9]*/port=$NP/" "$CONF_FILE"
                    if systemctl restart danted; then
                        if command -v ufw &>/dev/null; then
                            ufw delete allow "$CUR_PORT"/tcp 2>/dev/null || true
                            ufw allow "$NP"/tcp
                        fi
                        echo -e "${GREEN}Port updated to $NP.${NC}"
                    else
                        sed -i "s/port=$NP/port=$CUR_PORT/" "$CONF_FILE"
                        systemctl restart danted || true
                        echo -e "${RED}ERROR: Dante failed to restart. Port change rolled back.${NC}"
                    fi
                fi
                read -rp "Press Enter to return to menu..."
                ;;
            5)
                read -rp "DANGER: Wipe all SOCKS5 data? This cannot be undone. Type 'yes' to confirm: " W
                if [ "$W" = "yes" ]; then
                    systemctl stop danted || true
                    apt-get purge -y dante-server libpam-pwdfile
                    rm -f "$CONF_FILE" "$PASSWD_FILE" "$LOCKFILE"
                    echo -e "${GREEN}Wipe complete. Exiting.${NC}"
                    exit 0
                else
                    echo "Uninstall cancelled."
                fi
                read -rp "Press Enter to return to menu..."
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
        read -rp "Install now? (y/n): " START
        if [[ "$START" == "y" ]]; then
            install_socks
        else
            exit 0
        fi
    fi
done
