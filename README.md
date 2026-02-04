# Nix-Darwin Configuration

> Modern macOS system configuration using Nix flakes

[![Nix](https://img.shields.io/badge/Nix-flakes-blue)]() [![macOS](https://img.shields.io/badge/macOS-aarch64--darwin-lightgrey)]()

## Quick Start

```bash
git clone https://github.com/AlxWrtl/NixConfig.git ~/.config/nix-darwin
cd ~/.config/nix-darwin

# Build & apply
sudo darwin-rebuild switch --flake .#alex-mbp

# Or use the alias
rebuild
```

## Structure

```
flake.nix
├── hosts/alex-mbp/              # Host identity
├── modules/                     # 5 system modules
│   ├── system.nix               # Nix settings, env, security, shell
│   ├── packages.nix             # CLI tools
│   ├── services.nix             # Background services (launchd)
│   ├── ui.nix                   # Fonts, Dock, Finder, defaults
│   └── brew.nix                 # GUI apps (Homebrew casks)
└── home/                        # User config (home-manager)
    ├── default.nix              # User packages & settings
    ├── git.nix                  # Git configuration
    ├── zsh.nix                  # Shell configuration
    ├── starship.nix             # Prompt
    ├── direnv.nix               # Directory environments
    └── claude-code/             # Claude Code CLI (agents, hooks, skills)
```

## Commands

```bash
# Rebuild
rebuild                          # alias: sudo darwin-rebuild switch --flake .#alex-mbp

# Update & rollback
nix flake update
darwin-rebuild rollback

# Debug
darwin-rebuild switch --flake .#alex-mbp --show-trace -v

# Preview changes
nix build .#darwinConfigurations.alex-mbp.system
nix store diff-closures /var/run/current-system ./result

# Dev shell (vulnix, nix-tree, nixfmt, nil)
nix develop

# Tests
nix flake check
```

## Package Strategy

| Type | Tool | Example |
|------|------|---------|
| CLI tools | Nix (`modules/packages.nix`) | eza, bat, ripgrep, fd |
| GUI apps | Homebrew (`modules/brew.nix`) | Arc, VS Code, Docker Desktop |
| Fonts | Nix (`modules/ui.nix`) | JetBrains Mono, Fira Code |
| User config | home-manager (`home/`) | zsh, git, starship, direnv |

## Shell Aliases

```bash
lt           # eza --tree
cat          # bat
find         # fd
grep         # rg
g/gs/ga/gc   # git shortcuts
```

## Troubleshooting

```bash
exec $SHELL                      # Reload shell
fc-cache -f -v                   # Rebuild font cache
sudo chown -R $(whoami) ~/.config/nix-darwin  # Fix permissions
```

## Best Practices

- No `with pkgs;` (explicit `pkgs.` prefix)
- 5 modules (optimal range: 5–8)
- System/user separation (modules/ vs home/)
- Home-manager native features over manual shell code
- `nixfmt` for formatting

## Credits

Built with [nix-darwin](https://github.com/LnL7/nix-darwin), [home-manager](https://github.com/nix-community/home-manager), [Nix](https://nixos.org/), [Homebrew](https://brew.sh/).

## License

MIT
