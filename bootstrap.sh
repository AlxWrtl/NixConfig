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

# --- Checkpoint system ---
PROGRESS_FILE="$HOME/.bootstrap-progress"

checkpoint() {
  echo "$1" >> "$PROGRESS_FILE"
}

past_checkpoint() {
  [ -f "$PROGRESS_FILE" ] && grep -qx "$1" "$PROGRESS_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   nix-darwin bootstrap               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"

if [ -f "$PROGRESS_FILE" ]; then
  echo -e "  ${YELLOW}→${NC} Resuming from checkpoint..."
fi

# --- Xcode CLT ---
step "Xcode Command Line Tools"
if past_checkpoint "xcode_clt"; then
  skip "Xcode CLT installed"
else
  if xcode-select -p &>/dev/null; then
    skip "Xcode CLT installed"
  else
    xcode-select --install
    wait_for_user "Wait for Xcode CLT installation to finish"
  fi
  checkpoint "xcode_clt"
fi

# --- Nix ---
step "Nix package manager"
if past_checkpoint "nix"; then
  skip "Nix (checkpointed)"
  # Still source nix so subsequent steps can use it
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
  elif [ -e /etc/profile.d/nix.sh ]; then
    . /etc/profile.d/nix.sh
  fi
else
  if command -v nix &>/dev/null; then
    skip "Nix $(nix --version 2>/dev/null | head -1)"
  else
    NIX_INSTALL_LOG="$(mktemp)"
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
      | sh -s -- install 2>&1 | tee "$NIX_INSTALL_LOG" || {
        if grep -qE "Volume on disk|failed to mount" "$NIX_INSTALL_LOG"; then
          rm -f "$NIX_INSTALL_LOG"
          echo -e "  ${RED}✗${NC} Nix volume failed to mount."
          echo -e "  ${YELLOW}→${NC} Please restart your Mac and re-run this script."
          echo -e "  ${YELLOW}→${NC} Progress has been saved — the script will resume where it left off."
          exit 1
        fi
        rm -f "$NIX_INSTALL_LOG"
        fail "Nix install failed. Open a new terminal and re-run."
      }
    rm -f "$NIX_INSTALL_LOG"
    # Source nix in current shell (Determinate Nix path)
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
    elif [ -e /etc/profile.d/nix.sh ]; then
      . /etc/profile.d/nix.sh
    fi
    command -v nix &>/dev/null || fail "Nix install failed. Open a new terminal and re-run."
    ok "Nix installed"
  fi
  checkpoint "nix"
fi

# --- Homebrew ---
step "Homebrew"
if past_checkpoint "homebrew"; then
  skip "Homebrew (checkpointed)"
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
else
  if command -v brew &>/dev/null; then
    skip "Homebrew $(brew --version 2>/dev/null | head -1)"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
    command -v brew &>/dev/null || fail "Homebrew install failed"
    ok "Homebrew installed"
  fi
  checkpoint "homebrew"
fi

# --- 1Password ---
step "1Password (needed to retrieve keys)"
if past_checkpoint "1password"; then
  skip "1Password (checkpointed)"
else
  if [ -d "/Applications/1Password.app" ]; then
    skip "1Password installed"
  else
    brew install --cask 1password
    ok "1Password installed"
  fi
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  wait_for_user "Open 1Password, login, and retrieve:
    - SSH key (auth + signing) → save to ~/.ssh/id_ed25519 and ~/.ssh/id_ed25519.pub
    - git-crypt key (\"git-crypt nix-darwin key\") → save to ~/git-crypt-nix-darwin.key"
  checkpoint "1password"
fi

# --- SSH key permissions ---
step "SSH key permissions"
if past_checkpoint "ssh_perms"; then
  skip "SSH key permissions (checkpointed)"
else
  if [ -f ~/.ssh/id_ed25519 ]; then
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_ed25519
    chmod 644 ~/.ssh/id_ed25519.pub 2>/dev/null
    ok "SSH key permissions set (auth + signing)"
  else
    echo -e "  ${YELLOW}⚠${NC}  No SSH key at ~/.ssh/id_ed25519 — git push will need HTTPS"
  fi
  checkpoint "ssh_perms"
fi

# --- GitHub CLI auth ---
step "GitHub CLI authentication"
if past_checkpoint "gh_auth"; then
  skip "gh auth (checkpointed)"
else
  if ! command -v gh &>/dev/null; then
    brew install gh
    ok "gh CLI installed"
  fi
  if gh auth status &>/dev/null; then
    skip "gh already authenticated"
  else
    echo -e "  ${YELLOW}→${NC} Run: gh auth login"
    echo -e "  ${YELLOW}→${NC} Choose: GitHub.com → SSH → Yes (use SSH key) → Login with a web browser"
    gh auth login
    gh auth status &>/dev/null && ok "gh authenticated" || fail "gh auth failed"
  fi
  checkpoint "gh_auth"
fi

# --- git-crypt unlock ---
step "Decrypt secrets"
if past_checkpoint "decrypt_secrets"; then
  skip "Secrets (checkpointed)"
else
  if [ -f ~/git-crypt-nix-darwin.key ]; then
    CRYPT_KEY="$HOME/git-crypt-nix-darwin.key"
  elif [ -f ~/git-crypt-key ]; then
    CRYPT_KEY="$HOME/git-crypt-key"
  else
    CRYPT_KEY=""
  fi

  if [ -n "$CRYPT_KEY" ]; then
    nix shell nixpkgs#git-crypt -c git-crypt unlock "$CRYPT_KEY"
    rm "$CRYPT_KEY"
    ok "Secrets decrypted, key removed from disk"
  elif head -c 10 secrets.nix 2>/dev/null | grep -q "GITCRYPT"; then
    fail "secrets.nix is encrypted but no git-crypt key found (tried ~/git-crypt-nix-darwin.key and ~/git-crypt-key). Get it from 1Password."
  else
    skip "secrets.nix already decrypted"
  fi
  checkpoint "decrypt_secrets"
fi

# --- App Store login ---
step "App Store login"
if past_checkpoint "appstore_login"; then
  skip "App Store login (checkpointed)"
else
  wait_for_user "Open App Store and sign in with your Apple ID (needed for: DaisyDisk, Keynote, Numbers, Pages, Trello)"
  checkpoint "appstore_login"
fi

# --- Rebuild ---
step "darwin-rebuild switch"
if past_checkpoint "darwin_rebuild"; then
  skip "darwin-rebuild (checkpointed)"
else
  echo "  Building system configuration..."
  if command -v darwin-rebuild &>/dev/null; then
    darwin-rebuild switch --flake .#alex-mbp
  else
    sudo nix run nix-darwin/master -- switch --flake .#alex-mbp
  fi
  ok "System built and activated"
  checkpoint "darwin_rebuild"
  echo -e "  ${YELLOW}→${NC} Re-launching in a fresh shell to pick up nix-darwin changes..."
  exec "$SHELL" -l -c "cd '$(pwd)' && exec bash '$0'"
fi

# --- Switch remote to SSH ---
step "Switch git remote to SSH"
if past_checkpoint "git_remote_ssh"; then
  skip "Git remote (checkpointed)"
else
  current_remote=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$current_remote" == *"https://"* ]] && [ -f ~/.ssh/id_ed25519 ]; then
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
      git remote set-url origin git@github.com:AlxWrtl/NixConfig.git
      ok "Remote switched to SSH"
    else
      echo -e "  ${YELLOW}⚠${NC}  SSH key not recognized by GitHub — add it at github.com/settings/keys"
      skip "Keeping HTTPS until SSH is configured on GitHub"
    fi
  elif [[ "$current_remote" == *"git@"* ]]; then
    skip "Already using SSH"
  else
    skip "Keeping HTTPS (no SSH key found)"
  fi
  checkpoint "git_remote_ssh"
fi

# --- VS Code extensions ---
step "VS Code extensions"
if past_checkpoint "vscode_extensions"; then
  skip "VS Code extensions (checkpointed)"
else
  if command -v code &>/dev/null && [ -x ~/.local/bin/vscode-install-extensions ]; then
    ~/.local/bin/vscode-install-extensions
    ok "Extensions installed"
  else
    skip "VS Code not found or script missing — run ~/.local/bin/vscode-install-extensions later"
  fi
  checkpoint "vscode_extensions"
fi

# --- Restore app configs from repo (decrypted by git-crypt) ---
step "Restore app configs (Plex, Logitech, Raycast)"
if past_checkpoint "restore_configs"; then
  skip "App configs (checkpointed)"
else
  BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/backups"

  # WiFi & Bluetooth (reference)
  if [ -f "$BACKUP_DIR/wifi-bluetooth/wifi-networks.txt" ]; then
    echo -e "  ${YELLOW}WiFi${NC}: passwords restore via iCloud Keychain (sign in to Apple ID)"
    ok "WiFi: $(wc -l < "$BACKUP_DIR/wifi-bluetooth/wifi-networks.txt" | tr -d ' ') networks in iCloud Keychain"
  else
    skip "No WiFi backup found"
  fi
  if [ -f "$BACKUP_DIR/wifi-bluetooth/bluetooth-devices.txt" ]; then
    echo -e "  ${YELLOW}Bluetooth${NC}: devices need manual re-pairing:"
    grep "Name:" "$BACKUP_DIR/wifi-bluetooth/bluetooth-devices.txt" | grep -v "Controller" | sed 's/.*Name: /    /' | head -10
    ok "Bluetooth: re-pair devices listed above"
  else
    skip "No Bluetooth backup found"
  fi

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

  checkpoint "restore_configs"
fi

# --- Done ---
rm -f "$PROGRESS_FILE"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Bootstrap complete!                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "Remaining manual steps:"
echo -e "  • GitHub SSH: github.com/settings/keys → add ~/.ssh/id_ed25519.pub as Authentication key AND Signing key"
echo -e "  • Arc: login to restore Spaces, Folders & Tabs via Arc Sync → Set as Default"
echo -e "  • iCloud: System Settings → Apple ID → iCloud → iCloud Drive → Options → enable Desktop & Documents"
echo -e "  • Login: Discord, WhatsApp, Spark, Figma, Notion, Plex, Claude,"
echo -e "          Docker Desktop, Google Chrome, Microsoft (Teams/Excel/Word/PowerPoint),"
echo -e "          Tailscale, Trello"
echo -e "  • Restart your terminal: ${BLUE}exec \$SHELL${NC}"
