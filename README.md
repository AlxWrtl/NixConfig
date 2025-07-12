# Nix-Darwin Configuration

A modular nix-darwin configuration for macOS using flakes. Combines Nix for CLI tools and Homebrew for GUI applications.

## Structure

```
flake.nix              # Main flake configuration
hosts/alex-mbp/        # Host-specific settings
modules/               # Modular system configuration
├── system.nix         # Core system settings
├── packages.nix       # CLI tools & utilities
├── development.nix    # Development environments
├── shell.nix          # Zsh & shell configuration
├── ui.nix             # macOS interface settings
├── brew.nix           # Homebrew GUI applications
└── ...
```

## Key Commands

### System Management
```bash
# Apply configuration changes
sudo darwin-rebuild switch --flake .#alex-mbp

# Preview changes
darwin-rebuild build --flake .#alex-mbp
nix store diff-closures /var/run/current-system ./result

# Update dependencies
nix flake update

# Rollback
darwin-rebuild rollback
```

### Development
```bash
# Quick rebuild (alias)
rebuild

# Git shortcuts
g, gs, ga, gc, gp, gl, gd

# Modern tools
lt        # eza --tree
cat       # bat (syntax highlighting)
find      # fd
grep      # rg (ripgrep)
```

### Maintenance
```bash
# Cleanup
nix-collect-garbage -d
sudo nix-collect-garbage -d
brew cleanup --prune=all
```

## Package Strategy

- **Nix**: CLI tools, development environments, fonts
- **Homebrew**: GUI applications, macOS-specific tools
- **Language managers**: npm/pnpm, pip/uv for libraries

See `CLAUDE.md` for detailed documentation.