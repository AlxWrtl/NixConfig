# nix-darwin Config

Modular nix-darwin for macOS. Nix=CLI/dev, Homebrew=GUI, lang managers=libs.

## Structure
```
flake.nix + hosts/alex-mbp/ + modules/(12) + home/claude-code.nix
```

## Commands
```bash
# Rebuild
sudo darwin-rebuild switch --flake .#alex-mbp
rebuild  # alias

# Update/rollback
nix flake update
darwin-rebuild rollback

# Debug
darwin-rebuild switch --flake .#alex-mbp --show-trace -v
nix store diff-closures /var/run/current-system ./result

# Tools: lt(eza tree), bat(cat), fd(find), rg(grep)
# Git: g,gs,ga,gc,gp,gl,gd,gco,gb
```

## Dev Stack
- **Python**: uv, ruff | **JS/Node**: pnpm, TS, Angular, ESLint, Prettier | **Nix**: nixd, nixfmt-rfc-style
- **VCS**: git, gh, lazygit | **DB/API**: sqlite, postgresql, curl, httpie, jq
- **Env**: EDITOR=nvim, GIT_EDITOR="code --wait"

## System Features
- **Shell**: Zsh + Starship + FZF | ESC+ESC=sudo
- **macOS**: TouchID sudo, auto GC (weekly), Dock left+autohide, Finder column view
- **Fixes**: `exec $SHELL` | `fc-cache -fv` | `sudo chown -R $(whoami) ~/.config/nix-darwin`

## Adding Config
- CLI: `modules/packages.nix` or `development.nix`
- GUI: `modules/brew.nix` casks
- Fonts: `modules/fonts.nix`
- New host: `hosts/name/configuration.nix` + update `flake.nix`

## Docs
**Ref**: https://nix-darwin.github.io/nix-darwin/manual/ | `darwin-help` | `man 5 configuration.nix`
- `system.defaults.*` pour options built-in
- `system.defaults.CustomUserPreferences` pour app-specific
- UI/UX settings dans `modules/ui.nix`

## Workflow
- **Nix-specific**: Utiliser `nixfmt-rfc-style`, `--show-trace -v` pour debug, reference docs first
- **Tools priority**: `rg`>grep, `fd`>find, `bat`>cat, `uv`>pip, `pnpm`>npm, `gh` pour GitHub ops