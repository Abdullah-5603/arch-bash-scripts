#!/usr/bin/env bash

set -euo pipefail

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

WIFI_IFACE="${1:-}"

echo -e "${YELLOW}Checking NetworkManager...${NC}"

if ! command -v nmcli >/dev/null 2>&1; then
    echo -e "${RED}Error: nmcli not found. Install NetworkManager first.${NC}"
    exit 1
fi

if ! systemctl is-active --quiet NetworkManager; then
    echo -e "${YELLOW}Starting NetworkManager...${NC}"
    sudo systemctl enable --now NetworkManager
fi

nmcli radio wifi on

if [[ -z "$WIFI_IFACE" ]]; then
    WIFI_IFACE="$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2=="wifi"{print $1; exit}')"
fi

if [[ -z "$WIFI_IFACE" ]]; then
    echo -e "${RED}No Wi-Fi device found.${NC}"
    exit 1
fi

echo -e "${GREEN}Using Wi-Fi device:${NC} $WIFI_IFACE"
echo -e "${YELLOW}Scanning Wi-Fi networks...${NC}"

nmcli device wifi rescan ifname "$WIFI_IFACE" >/dev/null 2>&1 || true
sleep 2

mapfile -t WIFI_LIST < <(
    nmcli -t -f SSID,SIGNAL,SECURITY device wifi list ifname "$WIFI_IFACE" |
    awk -F: '
        $1 != "" && !seen[$1]++ {
            printf "%s|%s|%s\n", $1, $2, $3
        }
    '
)

if [[ ${#WIFI_LIST[@]} -eq 0 ]]; then
    echo -e "${RED}No Wi-Fi networks found.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}Available Wi-Fi networks:${NC}"
echo

for i in "${!WIFI_LIST[@]}"; do
    IFS='|' read -r SSID SIGNAL SECURITY <<< "${WIFI_LIST[$i]}"
    printf "%2d) %-35s Signal: %-4s Security: %s\n" "$((i + 1))" "$SSID" "$SIGNAL" "$SECURITY"
done

echo
read -rp "Select Wi-Fi number: " CHOICE

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#WIFI_LIST[@]} )); then
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi

IFS='|' read -r SELECTED_SSID SELECTED_SIGNAL SELECTED_SECURITY <<< "${WIFI_LIST[$((CHOICE - 1))]}"

echo
echo -e "${GREEN}Selected:${NC} $SELECTED_SSID"

if [[ "$SELECTED_SECURITY" == "--" || -z "$SELECTED_SECURITY" ]]; then
    PASSWORD=""
else
    read -rsp "Enter Wi-Fi password: " PASSWORD
    echo
fi

echo -e "${YELLOW}Saving connection permanently...${NC}"

# Remove old saved connection with same name to avoid broken secrets.
if nmcli connection show "$SELECTED_SSID" >/dev/null 2>&1; then
    nmcli connection delete "$SELECTED_SSID" >/dev/null 2>&1 || true
fi

if [[ -z "$PASSWORD" ]]; then
    nmcli connection add \
        type wifi \
        ifname "$WIFI_IFACE" \
        con-name "$SELECTED_SSID" \
        ssid "$SELECTED_SSID"

    nmcli connection modify "$SELECTED_SSID" connection.autoconnect yes
else
    nmcli connection add \
        type wifi \
        ifname "$WIFI_IFACE" \
        con-name "$SELECTED_SSID" \
        ssid "$SELECTED_SSID"

    nmcli connection modify "$SELECTED_SSID" wifi-sec.key-mgmt wpa-psk
    nmcli connection modify "$SELECTED_SSID" wifi-sec.psk "$PASSWORD"
    nmcli connection modify "$SELECTED_SSID" connection.autoconnect yes
fi

echo -e "${YELLOW}Connecting...${NC}"

if nmcli connection up "$SELECTED_SSID"; then
    echo
    echo -e "${GREEN}Connected successfully.${NC}"
    echo -e "${GREEN}This Wi-Fi is saved and will auto-connect after restart.${NC}"
else
    echo
    echo -e "${RED}Connection failed.${NC}"
    echo -e "${YELLOW}Trying interactive fallback...${NC}"
    nmcli --ask device wifi connect "$SELECTED_SSID" ifname "$WIFI_IFACE"
fi

echo
echo -e "${GREEN}Active connection:${NC}"
nmcli connection show --active

echo
echo -e "${GREEN}Internet test:${NC}"
ping -c 3 8.8.8.8
