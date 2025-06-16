# 🍎 Alexandre's Modern Nix-Darwin Configuration

A modern, modular nix-darwin configuration following 2025 best practices for macOS Apple Silicon systems. This setup maximizes the use of Nix for reproducible development environments while strategically using Homebrew for macOS-native applications.

## 📁 Structure

```
NixConfig/
├── flake.nix                 # Main flake configuration
├── flake.lock               # Lock file for reproducible builds
├── README.md                # This file
├── docs/                    # Documentation
│   ├── NIX_VS_HOMEBREW.md  # Package management philosophy
│   └── PURIFICATION_SUMMARY.md # Migration documentation
├── hosts/                   # Host-specific configurations
│   └── alex-mbp/
│       └── configuration.nix # Host-specific settings
└── modules/                 # Modular system configuration
    ├── system.nix           # Core Nix system settings & garbage collection
    ├── packages.nix         # Development tools & system packages
    ├── shell.nix            # Shell configuration (Zsh + Powerlevel10k)
    ├── fonts.nix            # Nerd Fonts management
    ├── ui.nix               # macOS UI/UX settings & system defaults
    └── brew.nix             # Minimal Homebrew for macOS-native apps
```

## 🚀 Quick Start

### Prerequisites

**⚠️ Important**: Git is **not** included by default on a clean Mac. You'll need to install it first.

**Install Git** (choose one method):

**Option A: Xcode Command Line Tools** (Recommended):
```bash
# This will prompt you to install Xcode Command Line Tools
git --version
# Click "Install" in the dialog that appears
```

**Option B: Manual installation**:
```bash
xcode-select --install
```

**Option C: Homebrew** (if you prefer):
```bash
# Install Homebrew first: https://brew.sh
brew install git
```

### Installation Steps

1. **Install Nix** (if not already installed):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **Clone this repository**:
   ```bash
   git clone https://github.com/AlxWrtl/NixConfig.git ~/.config/nix-darwin
   cd ~/.config/nix-darwin
   ```

3. **Apply the configuration**:
   ```bash
   nix run nix-darwin -- switch --flake .#alex-mbp
   ```

4. **For subsequent updates**:
   ```bash
   darwin-rebuild switch --flake .#alex-mbp
   ```

### Post-Installation

After applying the configuration:
- **Git will be managed by Nix** (more recent version than Xcode Command Line Tools)
- **Restart your terminal** to ensure all paths are updated
- **All development tools** will be available via Nix

## 🏗️ What's Included

### 📦 Development Tools (via Nix)
- **Editors**: VSCode with prettierd
- **Languages & Runtimes**: Node.js 23, UV (Python package manager)
- **Package Managers**: PNPM, Yarn
- **Development Utilities**: Git, GitHub CLI, jq, yq
- **Build Tools**: CMake, pkg-config

### 🖥️ Terminal & CLI Tools (via Nix)
- **Shell**: Zsh with Powerlevel10k theme, autosuggestions, syntax highlighting
- **Navigation**: zoxide (smart cd), fzf (fuzzy finder), eza (modern ls)
- **File Tools**: bat (syntax-highlighted cat), tree, fd (find alternative), ripgrep
- **Utilities**: rsync, keka (archive tool), atuin (shell history)

### 🌐 Browsers (via Nix)
- **Arc Browser**: Modern browsing experience
- **Google Chrome**: Comprehensive web development

### 🍺 macOS-Native Applications (via Homebrew)
- **Terminal**: Ghostty (GPU-accelerated)
- **Productivity**: Raycast (Spotlight replacement), Notion (workspace)
- **Communication**: Discord, Spotify
- **Development**: Docker Desktop, Figma
- **System Tools**: 1Password, OnyX, Cleaner-One, Dozer, iStat Menus
- **Professional**: Microsoft Teams, Plex Media Server, Spark

### 📱 Mac App Store Applications
- **Apple Suite**: Pages, Numbers, Keynote, Xcode
- **Design Tools**: Affinity Publisher, Designer, Photo
- **Utilities**: DaisyDisk, The Unarchiver, Trello

### 🎨 Fonts (via Nix)
- **Nerd Fonts**: MesloLG, Hack, FiraCode, JetBrains Mono
- **Programming fonts** with ligature support
- **International language** support

### ⚙️ System Configuration
- **macOS Settings**: Dock, Finder, Trackpad optimizations
- **Security**: Touch ID for sudo authentication
- **Performance**: Optimized Nix settings with automated garbage collection
- **UI/UX**: Dark mode, custom dock placement, enhanced trackpad sensitivity

## 🔧 Customization

### Adding New Packages

**Development tools** (in `modules/packages.nix`):
```nix
environment.systemPackages = with pkgs; [
  # Add development tools here
  your-dev-tool
];
```

**GUI Applications** (in `modules/brew.nix`):
```nix
casks = [
  "your-gui-app"  # For macOS-native apps
];
```

**Mac App Store apps** (in `modules/brew.nix`):
```nix
masApps = {
  "App Name" = 123456789;  # Find ID on App Store Connect
};
```

### Package Management Philosophy

This configuration follows a **"Nix-first, Homebrew-selective"** approach:

- **Nix for**: Development tools, CLI utilities, system packages, fonts
- **Homebrew for**: macOS-native GUI apps, proprietary software, App Store alternatives
- **Rationale**: Maximum reproducibility with practical macOS integration

See `docs/NIX_VS_HOMEBREW.md` for detailed reasoning.

### Creating a New Host

1. Create a new directory in `hosts/`:
   ```bash
   mkdir hosts/your-hostname
   ```

2. Copy and modify the configuration:
   ```bash
   cp hosts/alex-mbp/configuration.nix hosts/your-hostname/
   ```

3. Update `flake.nix` to include the new host:
   ```nix
   darwinConfigurations."your-hostname" = nix-darwin.lib.darwinSystem {
     system = "aarch64-darwin";
     specialArgs = { inherit inputs; };
     modules = [ ./hosts/your-hostname/configuration.nix /* ... */ ];
   };
   ```

### Modifying System Defaults

Edit `modules/ui.nix` to customize:
- **Dock**: Position, size, auto-hide behavior
- **Finder**: View options, sidebar, search behavior
- **Trackpad**: Sensitivity, gestures, scrolling
- **System**: Sleep settings, screenshots, menu bar

## 🔄 Updates & Maintenance

### System Updates
```bash
# Update and rebuild
darwin-rebuild switch --flake .#alex-mbp

# Check what would change
darwin-rebuild build --flake .#alex-mbp
```

### Flake Updates
```bash
# Update all inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Then rebuild
darwin-rebuild switch --flake .#alex-mbp
```

### Maintenance & Cleanup
```bash
# Garbage collection (automatic every 7 days)
nix-collect-garbage -d
sudo nix-collect-garbage -d

# Homebrew cleanup (automatic on activation)
brew cleanup

# Rollback if needed
darwin-rebuild --rollback
```

## 📋 Key Features

### ✅ 2025 Best Practices
- **Modular Architecture**: Separated concerns, maintainable structure
- **Reproducible Builds**: Locked dependencies, declarative configuration
- **Performance Optimized**: Binary caches, garbage collection, build optimization
- **Type Safety**: Proper module interfaces and validation

### ✅ Apple Silicon Optimized
- **Native ARM64**: Prioritized native packages
- **Hardware Integration**: Touch ID, trackpad, display optimization
- **Battery Efficiency**: Optimized settings for laptop usage

### ✅ Developer Experience
- **Modern Shell**: Zsh + Powerlevel10k with smart completions
- **CLI Tools**: Best-in-class replacements for standard Unix tools
- **Development Ready**: Git, Node.js, package managers pre-configured
- **Editor Integration**: VSCode and development tools ready

### ✅ Hybrid Package Management
- **~95% Nix**: Development tools, CLI utilities, system packages
- **~5% Homebrew**: macOS-native apps, proprietary software
- **Automatic Management**: Cleanup, updates, dependency resolution

## 🆘 Troubleshooting

### Common Issues

**Git not found on clean Mac**:
```bash
# Install Xcode Command Line Tools first
xcode-select --install
# Then proceed with the installation steps
```

**Command not found after rebuild**:
```bash
# Reload shell environment
exec $SHELL
# or restart terminal
```

**Multiple Git versions conflict**:
```bash
# Check which Git is being used
which git
# Should show /nix/store/... after Nix installation
# If showing /usr/bin/git, restart terminal
```

**Homebrew path issues**:
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

**Fonts not rendering**:
```bash
fc-cache -f -v  # Rebuild font cache
```

**Nix store permissions**:
```bash
sudo chown -R $(whoami) ~/.config/nix-darwin
```

**Build failures**:
```bash
# Clear build cache and retry
nix-collect-garbage -d
darwin-rebuild switch --flake .#alex-mbp --show-trace
```

## 📚 Resources & Documentation

- **Configuration Docs**: `docs/` directory in this repo
- **Nix Darwin Manual**: [daiderd.com/nix-darwin](https://daiderd.com/nix-darwin/manual/)
- **Package Search**: [search.nixos.org](https://search.nixos.org/)
- **Flakes Guide**: [nixos.wiki/wiki/Flakes](https://nixos.wiki/wiki/Flakes)
- **macOS Options**: [nix-darwin options search](https://daiderd.com/nix-darwin/manual/index.html#sec-options)

## 🎯 Philosophy

This configuration prioritizes:
1. **Reproducibility**: Declarative configuration for consistent environments
2. **Performance**: Optimized settings for development workflows
3. **Maintainability**: Modular structure for easy updates and customization
4. **Practicality**: Balanced approach between Nix purity and macOS integration
5. **Developer Experience**: Modern tools and optimized workflows

## 🤝 Contributing

Contributions welcome:
- **Issues**: Bug reports, feature requests, optimization suggestions
- **Pull Requests**: Improvements, additional modules, documentation
- **Discussions**: Share your own configurations and best practices

## 📄 License

This configuration is provided as-is for educational and personal use.

---

*Built with ❤️ using Nix-Darwin following 2025 best practices for modular, reproducible macOS development environments.*