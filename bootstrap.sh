#!/bin/bash
set -e

# ============================================================================
# nix-darwin bootstrap — from fresh macOS to full system
# Usage: git clone https://github.com/AlxWrtl/NixConfig.git ~/.config/nix-darwin
#        cd ~/.config/nix-darwin && ./bootstrap.sh
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

step=0
step() { step=$((step + 1)); echo -e "\n${BLUE}[$step]${NC} $1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
skip() { echo -e "  ${YELLOW}→${NC} $1 (already done)"; }
wait_for_user() { echo -e "  ${YELLOW}⏸${NC} $1"; read -p "  Press Enter when done..."; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   nix-darwin bootstrap               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"

# --- Xcode CLT ---
step "Xcode Command Line Tools"
if xcode-select -p &>/dev/null; then
  skip "Xcode CLT installed"
else
  xcode-select --install
  wait_for_user "Wait for Xcode CLT installation to finish"
fi

# --- Nix ---
step "Nix package manager"
if command -v nix &>/dev/null; then
  skip "Nix $(nix --version 2>/dev/null | head -1)"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  # Source nix in current shell
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix &>/dev/null || fail "Nix install failed. Open a new terminal and re-run."
  ok "Nix installed"
fi

# --- Homebrew ---
step "Homebrew"
if command -v brew &>/dev/null; then
  skip "Homebrew $(brew --version 2>/dev/null | head -1)"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  command -v brew &>/dev/null || fail "Homebrew install failed"
  ok "Homebrew installed"
fi

# --- 1Password ---
step "1Password (needed to retrieve keys)"
if [ -d "/Applications/1Password.app" ]; then
  skip "1Password installed"
else
  brew install --cask 1password
  ok "1Password installed"
fi
wait_for_user "Open 1Password, login, and retrieve:
    - SSH keys → save to ~/.ssh/id_ed25519 and ~/.ssh/id_ed25519.pub
    - git-crypt key (\"git-crypt nix-darwin key\") → save to ~/git-crypt-key"

# --- SSH keys permissions ---
step "SSH keys permissions"
if [ -f ~/.ssh/id_ed25519 ]; then
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/id_ed25519
  chmod 644 ~/.ssh/id_ed25519.pub 2>/dev/null
  ok "SSH keys permissions set"
else
  echo -e "  ${YELLOW}⚠${NC}  No SSH key at ~/.ssh/id_ed25519 — git push will need HTTPS"
fi

# --- git-crypt unlock ---
step "Decrypt secrets"
if [ -f ~/git-crypt-key ]; then
  nix-shell -p git-crypt --run "git-crypt unlock $HOME/git-crypt-key"
  rm ~/git-crypt-key
  ok "Secrets decrypted, key removed from disk"
elif head -c 10 secrets.nix 2>/dev/null | grep -q "GITCRYPT"; then
  fail "secrets.nix is encrypted but ~/git-crypt-key not found. Get it from 1Password."
else
  skip "secrets.nix already decrypted"
fi

# --- App Store login ---
step "App Store login"
wait_for_user "Open App Store and sign in with your Apple ID (needed for: DaisyDisk, Keynote, Numbers, Pages, Trello)"

# --- Rebuild ---
step "darwin-rebuild switch"
echo "  Building system configuration..."
sudo darwin-rebuild switch --flake .#alex-mbp
ok "System built and activated"

# --- Switch remote to SSH ---
step "Switch git remote to SSH"
current_remote=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$current_remote" == *"https://"* ]] && [ -f ~/.ssh/id_ed25519 ]; then
  git remote set-url origin git@github.com:AlxWrtl/NixConfig.git
  ok "Remote switched to SSH"
elif [[ "$current_remote" == *"git@"* ]]; then
  skip "Already using SSH"
else
  skip "Keeping HTTPS (no SSH key found)"
fi

# --- VS Code extensions ---
step "VS Code extensions"
if command -v code &>/dev/null && [ -x ~/.local/bin/vscode-install-extensions ]; then
  ~/.local/bin/vscode-install-extensions
  ok "Extensions installed"
else
  skip "VS Code not found or script missing — run ~/.local/bin/vscode-install-extensions later"
fi

# --- Restore app configs from repo (decrypted by git-crypt) ---
step "Restore app configs (Plex, Logitech, Raycast)"
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/backups"

# Finder sidebar (Favorites: Downloads, Applications, Desktop, Documents + Locations)
sidebar_dest="$HOME/Library/Application Support/com.apple.sharedfilelist"
sidebar_restored=0
for f in FavoriteItems.sfl4 FavoriteVolumes.sfl4 iCloudItems.sfl4; do
  if [ -f "$BACKUP_DIR/finder-sidebar/$f" ]; then
    mkdir -p "$sidebar_dest"
    cp "$BACKUP_DIR/finder-sidebar/$f" "$sidebar_dest/com.apple.LSSharedFileList.$f"
    sidebar_restored=$((sidebar_restored + 1))
  fi
done
if [ $sidebar_restored -gt 0 ]; then
  ok "Finder sidebar restored ($sidebar_restored files)"
else
  skip "No Finder sidebar backup found"
fi

# Ice (menu bar layout)
if [ -f "$BACKUP_DIR/ice/com.jordanbaird.Ice.plist" ]; then
  defaults import com.jordanbaird.Ice "$BACKUP_DIR/ice/com.jordanbaird.Ice.plist"
  ok "Ice menu bar layout restored"
else
  skip "No Ice backup found"
fi

# Plex
if [ -f "$BACKUP_DIR/plex/com.plexapp.plexmediaserver.plist" ]; then
  defaults import com.plexapp.plexmediaserver "$BACKUP_DIR/plex/com.plexapp.plexmediaserver.plist"
  ok "Plex config restored"
else
  skip "No Plex backup found"
fi

# Logitech
logi_restored=0
for plist in com.logi.optionsplus com.logi.optionsplus.updater com.logi.cp-dev-mgr; do
  if [ -f "$BACKUP_DIR/logitech/${plist}.plist" ]; then
    defaults import "$plist" "$BACKUP_DIR/logitech/${plist}.plist"
    logi_restored=$((logi_restored + 1))
  fi
done
if [ $logi_restored -gt 0 ]; then
  ok "Logitech: $logi_restored plists restored"
else
  skip "No Logitech backup found"
fi

# Raycast (needs manual import via UI)
rayconfig=$(ls "$BACKUP_DIR/raycast/"*.rayconfig 2>/dev/null | head -1)
if [ -n "$rayconfig" ]; then
  echo -e "  ${YELLOW}Raycast${NC}: Open Raycast → Settings → Advanced → Import"
  echo -e "  File: ${BLUE}$rayconfig${NC}"
  wait_for_user "Press Enter when Raycast import is done"
else
  skip "No Raycast backup found"
fi

# --- Done ---
echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Bootstrap complete!                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "Remaining manual steps:"
echo -e "  • Set default browser: Arc → Settings → Set as Default"
echo -e "  • Login: Arc, iCloud, Discord, WhatsApp, Spark, Teams, Figma"
echo -e "  • Restart your terminal: ${BLUE}exec \$SHELL${NC}"
