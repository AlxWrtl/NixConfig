# Modern Nix-Darwin Configuration

A modular nix-darwin configuration for macOS using a hybrid package management strategy with Nix for reproducible CLI tools and development environments, and Homebrew for GUI applications.

## Architecture

```
├── flake.nix              # Main flake with inputs & module orchestration
├── hosts/alex-mbp/        # Host-specific configuration
│   ├── default.nix        # Host module entry point
│   └── configuration.nix  # Core host settings
└── modules/               # Modular system configuration
    ├── system.nix         # Core Nix settings, TouchID, trackpad
    ├── packages.nix       # System utilities & CLI tools
    ├── development.nix    # Development environments & tools
    ├── shell.nix          # Zsh, Starship, aliases, functions
    ├── starship.nix       # Starship prompt configuration
    ├── fonts.nix          # Programming fonts & typography
    ├── ui.nix             # macOS UI/UX & system defaults
    ├── brew.nix           # Homebrew for GUI applications
    └── claude-code.nix    # Claude Code CLI integration
```

## Main Commands

### System Management
```bash
# Apply configuration changes
sudo darwin-rebuild switch --flake .#alex-mbp

# Preview changes without applying
darwin-rebuild build --flake .#alex-mbp
nix store diff-closures /var/run/current-system ./result

# Update dependencies
nix flake update
nix flake lock --update-input nixpkgs

# Rollback to previous generation
darwin-rebuild rollback
```

### Development Workflow
```bash
# Quick rebuild alias (defined in development.nix)
rebuild

# Git shortcuts (defined in development.nix)
g, gs, ga, gc, gp, gl, gd, gco, gb

# Modern tool replacements
lt        # eza --tree
cat       # bat (syntax highlighted)
find      # fd (faster find)
grep      # rg (ripgrep)
```

### Maintenance
```bash
# Cleanup (automatic weekly GC configured)
nix-collect-garbage -d
sudo nix-collect-garbage -d
nix-store --optimise

# Homebrew cleanup (automatic on rebuild)
brew cleanup --prune=all
```

## Package Management Strategy

- **Nix**: CLI tools, development environments, fonts, system utilities
- **Homebrew**: GUI applications, macOS-specific tools, casks
- **Language Package Managers**: npm/pnpm, pip/uv for libraries