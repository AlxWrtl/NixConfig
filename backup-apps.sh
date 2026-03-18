#!/bin/bash
set -e

# ============================================================================
# Export app configs into repo (encrypted by git-crypt)
# Run before clean install, then commit to save in repo
# Usage: ./backup-apps.sh
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"

echo -e "${BLUE}Exporting app configs to:${NC} $BACKUP_DIR"
echo -e "${BLUE}(encrypted by git-crypt on push)${NC}"
echo ""

mkdir -p "$BACKUP_DIR"/{raycast,plex,logitech,ice,finder-sidebar}

# --- Raycast ---
echo -e "${YELLOW}[Raycast]${NC} Open Raycast → Settings → Advanced → Export"
echo -e "  Save the .rayconfig file to: ${BLUE}$BACKUP_DIR/raycast/${NC}"
read -p "  Press Enter when done (or Enter to skip)..."
if ls "$BACKUP_DIR/raycast/"*.rayconfig &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Found $(ls "$BACKUP_DIR/raycast/"*.rayconfig | wc -l | tr -d ' ') rayconfig file(s)"
else
  echo -e "  ${YELLOW}→${NC} No .rayconfig found, skipping"
fi

# --- Plex ---
echo -ne "${YELLOW}[Plex]${NC} "
if defaults read com.plexapp.plexmediaserver &>/dev/null 2>&1; then
  defaults export com.plexapp.plexmediaserver "$BACKUP_DIR/plex/com.plexapp.plexmediaserver.plist"
  echo -e "${GREEN}✓${NC} Exported"
else
  echo "not installed, skipping"
fi

# --- Logitech ---
echo -ne "${YELLOW}[Logitech]${NC} "
exported=0
for plist in com.logi.optionsplus com.logi.optionsplus.updater com.logi.cp-dev-mgr; do
  if defaults read "$plist" &>/dev/null 2>&1; then
    defaults export "$plist" "$BACKUP_DIR/logitech/${plist}.plist"
    exported=$((exported + 1))
  fi
done
if [ $exported -gt 0 ]; then
  echo -e "${GREEN}✓${NC} Exported $exported plists"
else
  echo "not installed, skipping"
fi

# --- WiFi & Bluetooth ---
echo -ne "${YELLOW}[WiFi]${NC} "
mkdir -p "$BACKUP_DIR/wifi-bluetooth"
networksetup -listpreferredwirelessnetworks en0 > "$BACKUP_DIR/wifi-bluetooth/wifi-networks.txt" 2>/dev/null
echo -e "${GREEN}✓${NC} $(wc -l < "$BACKUP_DIR/wifi-bluetooth/wifi-networks.txt" | tr -d ' ') networks saved"

echo -ne "${YELLOW}[Bluetooth]${NC} "
system_profiler SPBluetoothDataType > "$BACKUP_DIR/wifi-bluetooth/bluetooth-devices.txt" 2>/dev/null
sudo cp /Library/Preferences/com.apple.Bluetooth.plist "$BACKUP_DIR/wifi-bluetooth/" 2>/dev/null
echo -e "${GREEN}✓${NC} Devices + pairing plist saved"

# --- Finder sidebar ---
echo -ne "${YELLOW}[Finder sidebar]${NC} "
sidebar_src="$HOME/Library/Application Support/com.apple.sharedfilelist"
sidebar_count=0
for f in FavoriteItems.sfl4 FavoriteVolumes.sfl4 iCloudItems.sfl4; do
  if [ -f "$sidebar_src/com.apple.LSSharedFileList.$f" ]; then
    cp "$sidebar_src/com.apple.LSSharedFileList.$f" "$BACKUP_DIR/finder-sidebar/"
    sidebar_count=$((sidebar_count + 1))
  fi
done
if [ $sidebar_count -gt 0 ]; then
  echo -e "${GREEN}✓${NC} Exported $sidebar_count sidebar files"
else
  echo "no sidebar files found, skipping"
fi

# --- Ice (menu bar manager) ---
echo -ne "${YELLOW}[Ice]${NC} "
if defaults read com.jordanbaird.Ice &>/dev/null 2>&1; then
  defaults export com.jordanbaird.Ice "$BACKUP_DIR/ice/com.jordanbaird.Ice.plist"
  echo -e "${GREEN}✓${NC} Exported (includes menu bar item layout)"
else
  echo "not installed, skipping"
fi

# --- Summary ---
echo ""
echo -e "${GREEN}Done!${NC} Configs saved in backups/"
echo -e "Commit and push to save (encrypted by git-crypt):"
echo -e "  ${BLUE}git add backups/ && git commit -m 'chore: update app config backups'${NC}"
