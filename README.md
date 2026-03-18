# Nix-Darwin Configuration

> Declarative macOS system configuration using Nix flakes

[![Nix](https://img.shields.io/badge/Nix-flakes-blue)]() [![macOS](https://img.shields.io/badge/macOS-aarch64--darwin-lightgrey)]()

## Clean Install

```bash
# 1. Prerequisites (git + clone access)
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh
gh auth login                    # authenticate with GitHub

# 2. Clone and run bootstrap (handles everything else)
git clone https://github.com/AlxWrtl/NixConfig.git ~/.config/nix-darwin
cd ~/.config/nix-darwin
./bootstrap.sh
```

The script automates: Nix → 1Password → SSH keys → git-crypt unlock → App Store → rebuild → VS Code extensions → app config restore. It pauses for manual steps and skips what's already done.

<details>
<summary>Manual step-by-step (if you prefer)</summary>

```bash
# 1. Xcode Command Line Tools
xcode-select --install

# 2. Install Homebrew + GitHub CLI
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh
gh auth login

# 3. Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh

# 4. Clone
git clone https://github.com/AlxWrtl/NixConfig.git ~/.config/nix-darwin
cd ~/.config/nix-darwin

# 5. Install 1Password and retrieve keys
brew install --cask 1password
# Open 1Password → login → save SSH keys to ~/.ssh/ and git-crypt key to ~/git-crypt-key

# 6. Decrypt secrets
nix-shell -p git-crypt --run "git-crypt unlock ~/git-crypt-key"
rm ~/git-crypt-key

# 7. Login to App Store (for masApps)

# 7. Build & apply
sudo darwin-rebuild switch --flake .#alex-mbp

# 8. Post-install
git remote set-url origin git@github.com:AlxWrtl/NixConfig.git
~/.local/bin/vscode-install-extensions
```
</details>

## Structure

```
flake.nix
├── hosts/alex-mbp/              # Host identity
├── modules/                     # System modules
│   ├── system.nix               # Nix settings, env, security, shell
│   ├── packages.nix             # CLI tools
│   ├── services.nix             # Background services (launchd, power, network)
│   ├── ui.nix                   # Fonts, Dock, Finder, macOS defaults, wallpaper
│   └── brew.nix                 # GUI apps (Homebrew casks)
├── home/                        # User config (home-manager)
│   ├── default.nix              # User packages & imports
│   ├── git.nix                  # Git + SSH signing
│   ├── ssh.nix                  # SSH hosts
│   ├── zsh.nix                  # Shell (zsh + fzf + zoxide)
│   ├── starship.nix             # Prompt
│   ├── direnv.nix               # Directory environments
│   ├── ghostty.nix              # Terminal (Catppuccin, quick terminal)
│   ├── vscode.nix               # VS Code settings, keybindings, extensions
│   └── claude-code/             # Claude Code CLI (agents, hooks, skills)
├── secrets.nix                  # 🔒 Encrypted (git-crypt) — emails, IPs, usernames
├── wallpapers/                  # Desktop wallpaper
└── .gitattributes               # git-crypt filter rules
```

## Secrets

Sensitive values (email, SSH hosts) live in `secrets.nix`, encrypted by [git-crypt](https://github.com/AGWA/git-crypt).

- **Locally**: readable, transparent workflow
- **On GitHub**: encrypted binary
- **Key backup**: 1Password → "git-crypt nix-darwin key"

```bash
git-crypt status                 # Check encryption status
git-crypt lock                   # Re-encrypt (rarely needed)
git-crypt unlock <key-file>      # Decrypt after clone
```

## Commands

```bash
rebuild                          # alias: sudo darwin-rebuild switch --flake .#alex-mbp
nix flake update                 # Update inputs
darwin-rebuild rollback          # Rollback to previous generation
darwin-rebuild switch --flake .#alex-mbp --show-trace -v  # Debug
```

## What's Managed

| Layer | Tool | Contents |
|-------|------|----------|
| CLI tools | Nix (`modules/packages.nix`) | eza, bat, rg, fd, git-crypt, nodejs, pnpm, uv, ruff |
| GUI apps | Homebrew (`modules/brew.nix`) | Arc, Ghostty, VS Code, Docker, 1Password, Raycast, ... (29 casks) |
| App Store | mas (`modules/brew.nix`) | DaisyDisk, Keynote, Numbers, Pages, Trello |
| Fonts | Nix (`modules/ui.nix`) | JetBrains Mono, Fira Code, MesloLGS, Noto |
| macOS defaults | Nix (`modules/ui.nix`) | Dock, Finder, trackpad, clock, screensaver, Window Manager |
| Services | Nix (`modules/services.nix`) | Power/network optimization, flake update, brew update |
| Terminal | home-manager (`home/ghostty.nix`) | Catppuccin Macchiato, quick terminal, keybindings |
| Editor | home-manager (`home/vscode.nix`) | Settings, keybindings, extension list |
| Shell | home-manager (`home/zsh.nix`) | Zsh + fzf + zoxide + aliases |
| Git | home-manager (`home/git.nix`) | SSH signing, rebase, fsck |
| SSH | home-manager (`home/ssh.nix`) | Host configs (Tailscale) |
| Wallpaper | activation script (`wallpapers/`) | Applied on rebuild |
| Secrets | git-crypt (`secrets.nix`) | Git email, SSH hosts |

## Post Clean Install Checklist

- [ ] SSH keys restored (`~/.ssh/id_ed25519*`)
- [ ] VS Code extensions installed (`~/.local/bin/vscode-install-extensions`)
- [ ] Default browser set (Arc)
- [ ] 1Password logged in + browser extension
- [ ] iCloud signed in (Desktop & Documents sync)
- [ ] Arc signed in (sync spaces)
- [ ] App logins: Discord, WhatsApp, Spark, Teams, Figma
- [ ] Raycast settings imported (if backed up)

## Shell Aliases

```bash
lt / tree      # eza --tree
cat            # bat
find           # fd
grep           # rg
g/gs/ga/gc/gp  # git shortcuts
rebuild        # darwin-rebuild switch
```

## Troubleshooting

```bash
exec $SHELL                      # Reload shell
fc-cache -f -v                   # Rebuild font cache
sudo chown -R $(whoami) ~/.config/nix-darwin  # Fix permissions
darwin-rebuild switch --flake .#alex-mbp --show-trace -v  # Debug build
```

## Credits

Built with [nix-darwin](https://github.com/LnL7/nix-darwin), [home-manager](https://github.com/nix-community/home-manager), [Nix](https://nixos.org/), [Homebrew](https://brew.sh/), [git-crypt](https://github.com/AGWA/git-crypt).

## License

MIT
