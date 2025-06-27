# 🚀 Modern Nix-Darwin Configuration

A production-ready, modular nix-darwin configuration optimized for Apple Silicon Macs. This setup provides a reproducible development environment with intelligent package management, leveraging both Nix and Homebrew strategically.

## 🏗️ Architecture Overview

```
📁 Configuration Structure
├── 🔧 flake.nix                 # Main flake with inputs & module orchestration
├── 🔒 flake.lock               # Locked dependency versions
│
├── 🖥️  hosts/                   # Host-specific configurations
│   └── alex-mbp/
│       └── configuration.nix    # Hostname, users, platform settings
│
├── 📦 modules/                  # Modular system configuration
│   ├── system.nix              # Core Nix settings, GC, security
│   ├── packages.nix            # System utilities & CLI tools
│   ├── development.nix         # Development environments & tools
│   ├── shell.nix               # Zsh, Starship, aliases, functions
│   ├── fonts.nix               # Programming fonts & typography
│   ├── ui.nix                  # macOS UI/UX & system defaults
│   └── brew.nix                # Homebrew for GUI applications
│
└── 📚 docs/                    # Configuration documentation
    ├── NIX_VS_HOMEBREW.md     # Package management strategy
    ├── PURIFICATION_SUMMARY.md # Nix migration overview
    └── PACKAGE_OPTIMIZATION_SUMMARY.md # Performance optimizations
```

## 🎯 Design Philosophy

### **Hybrid Package Management Strategy**

| Category         | Nix        | Homebrew   | Rationale                        |
| ---------------- | ---------- | ---------- | -------------------------------- |
| **CLI Tools**    | ✅ Primary | Minimal    | Reproducibility, version control |
| **Development**  | ✅ Primary | None       | Declarative dev environments     |
| **Fonts**        | ✅ Primary | None       | Consistent typography management |
| **GUI Apps**     | Optional   | ✅ Primary | Native macOS integration         |
| **System Tools** | Limited    | ✅ Primary | macOS-specific functionality     |

### **Modular Design Principles**

- **Separation of Concerns**: Each module handles a specific aspect
- **Clear Interfaces**: Well-defined module boundaries
- **Composability**: Mix and match modules for different setups
- **Documentation**: Comprehensive inline comments and docs

## 🚀 Quick Start

### Prerequisites

**Install Git** (required for cloning):

```bash
# Triggers Xcode Command Line Tools installation
git --version
# Click "Install" when prompted
```

### Installation

1. **Install Nix** (Determinate Systems installer):

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **Install Homebrew**:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

3. **Clone and Apply Configuration**:

   ```bash
   git clone <your-repo-url> ~/.config/nix-darwin
   cd ~/.config/nix-darwin
   nix run nix-darwin -- switch --flake .#alex-mbp
   ```

4. **Subsequent Updates**:
   ```bash
   darwin-rebuild switch --flake .#alex-mbp
   ```

## 📦 What's Included

### 🛠️ **Core System** (`modules/system.nix`)

- **Nix Configuration**: Optimized settings, binary caches, flakes enabled
- **Garbage Collection**: Automatic weekly cleanup (7-day retention)
- **Store Optimization**: Automatic deduplication and optimization
- **TouchID Integration**: Sudo authentication via TouchID
- **Trackpad Settings**: Enhanced sensitivity and gestures

### 🧰 **System Packages** (`modules/packages.nix`)

```nix
# Modern CLI Replacements
zsh, starship                    # Shell & prompt
eza, bat, fd, ripgrep           # File navigation & search
zoxide, fzf                     # Directory jumping & fuzzy finding
atuin                           # Shell history management

# System Monitoring
btop, neofetch                  # System information & monitoring
```

### 👨‍💻 **Development Environment** (`modules/development.nix`)

```nix
# Version Control
git, git-lfs, gh, lazygit       # Git ecosystem & GitHub integration

# Languages & Runtimes
python3, uv, ruff               # Python development
nodejs, pnpm, typescript        # JavaScript/Node.js ecosystem
postgresql, sqlite              # Database tools

# API & Testing
curl, wget, httpie, jq, yq      # HTTP clients & data processing

# Nix Development
nixd, nil, nixfmt-rfc-style     # Nix language support
```

### 🖥️ **Shell Configuration** (`modules/shell.nix`)

- **Zsh Setup**: Autosuggestions, syntax highlighting, completion
- **Starship Prompt**: Modern, fast prompt with Git integration
- **Enhanced Aliases**: Git shortcuts, modern tool replacements
- **Key Bindings**: ESC+ESC for sudo, enhanced history search
- **FZF Integration**: Enhanced file/directory previews

### 🎨 **Typography** (`modules/fonts.nix`)

```nix
# Programming Fonts with Nerd Font Icons
nerd-fonts.meslo-lg             # Recommended for terminals
nerd-fonts.jetbrains-mono       # Modern programming font
nerd-fonts.fira-code           # Programming ligatures
nerd-fonts.hack                # Clean monospace

# Additional Fonts
cascadia-code, inconsolata      # Microsoft & Google fonts
noto-fonts-*                    # International & emoji support
```

### 🎨 **macOS Interface** (`modules/ui.nix`)

```nix
# Dock Configuration
- Position: Left side, auto-hide enabled
- Icon size: 25px (magnified: 48px)
- Minimal hot corners, no recents

# Finder Enhancements
- Column view, path bar, status bar
- Show all extensions, hide internal drives
- Folders first, no extension warnings

# Global Settings
- Dark mode interface
- Disabled smart substitutions
- Fast key repeat, F-keys as standard
```

### 🍺 **GUI Applications** (`modules/brew.nix`)

```nix
# Development Tools
"docker-desktop"                # Container development
"visual-studio-code"           # Code editor
"ghostty"                      # GPU-accelerated terminal
"cursor"                       # AI-powered editor

# Productivity
"raycast"                      # Spotlight replacement
"notion"                       # Workspace & notes
"1password"                    # Password management

# Communication
"discord", "spotify"           # Social & entertainment
"microsoft-teams"              # Corporate communication

# macOS-Specific Tools
"jordanbaird-ice"             # Menu bar organization
"onyx"                        # System maintenance
"logi-options+"               # Logitech device management

# Mac App Store Apps
"Pages", "Numbers", "Keynote"  # Apple productivity suite
"DaisyDisk"                   # Disk usage analyzer
```

## ⚙️ Customization Guide

### Adding New Packages

**System Tools** (in `modules/packages.nix`):

```nix
environment.systemPackages = with pkgs; [
  # Add your CLI tools here
  your-cli-tool
];
```

**Development Tools** (in `modules/development.nix`):

```nix
environment.systemPackages = with pkgs; [
  # Add development-specific tools
  your-dev-tool
];
```

**GUI Applications** (in `modules/brew.nix`):

```nix
casks = [
  "your-gui-app"  # For macOS-native applications
];
```

### Creating New Hosts

1. **Create host directory**:

   ```bash
   mkdir hosts/your-hostname
   cp hosts/alex-mbp/configuration.nix hosts/your-hostname/
   ```

2. **Update configuration**:

   ```nix
   # hosts/your-hostname/configuration.nix
   networking.hostName = "your-hostname";
   networking.computerName = "Your Computer Name";
   ```

3. **Add to flake.nix**:
   ```nix
   darwinConfigurations."your-hostname" = nix-darwin.lib.darwinSystem {
     system = "aarch64-darwin";
     specialArgs = { inherit inputs; };
     modules = [ ./hosts/your-hostname/configuration.nix ] ++ defaultModules;
   };
   ```

### Module Customization

**Disable modules** by commenting them out in `flake.nix`:

```nix
modules = [
  ./modules/system.nix
  ./modules/packages.nix
  # ./modules/ui.nix           # Disable UI customizations
  ./modules/development.nix
  # ... other modules
];
```

**Override module settings** in your host configuration:

```nix
# hosts/your-hostname/configuration.nix
{ config, pkgs, lib, inputs, ... }: {
  # Disable TouchID if desired
  security.pam.services.sudo_local.touchIdAuth = false;

  # Custom dock position
  system.defaults.dock.orientation = "bottom";
}
```

## 🔄 Maintenance & Updates

### System Updates

```bash
# Standard rebuild
darwin-rebuild switch --flake .#alex-mbp

# Preview changes without applying
darwin-rebuild build --flake .#alex-mbp
nix store diff-closures /var/run/current-system ./result
```

### Dependency Updates

```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Check for security updates
nix flake check
```

### Cleanup & Optimization

```bash
# Manual garbage collection (automatic weekly)
nix-collect-garbage -d
sudo nix-collect-garbage -d

# Optimize Nix store
nix-store --optimise

# Homebrew cleanup (automatic on rebuild)
brew cleanup && brew autoremove

# Removes all cache files and outdated versions
brew cleanup --prune=all
```

### Rollback if Needed

```bash
# List generations
darwin-rebuild --list-generations

# Rollback to previous generation
darwin-rebuild rollback

# Rollback to specific generation
sudo nix-env -p /nix/var/nix/profiles/system --switch-generation <number>
```

## 🔧 Advanced Configuration

### Performance Optimization

The configuration includes several performance optimizations:

```nix
# Binary caches for faster downloads
nix.settings.substituters = [
  "https://cache.nixos.org/"
  "https://nix-community.cachix.org"
];

# Build optimization
nix.settings = {
  max-jobs = "auto";           # Use all CPU cores
  cores = 0;                   # Max cores per job
  auto-optimise-store = true;  # Automatic deduplication
};
```

### Environment Variables

Key environment variables are set across modules:

```bash
# Development (modules/development.nix)
EDITOR="code --wait"
NODE_ENV="development"

# Shell (modules/shell.nix)
BAT_THEME="TwoDark"
FZF_DEFAULT_COMMAND="fd --type f --hidden --follow"

# Fonts (modules/fonts.nix)
TERMINAL_FONT="MesloLGS Nerd Font"
```

## 🆘 Troubleshooting

### Common Issues

**Homebrew not activating**:

```bash
# Check if nix.enable = true in modules/system.nix
# Rebuild and check for errors
darwin-rebuild switch --flake .#alex-mbp --show-trace
```

**Command not found after rebuild**:

```bash
# Reload shell environment
exec $SHELL
# or restart terminal completely
```

**Font issues**:

```bash
# Rebuild font cache
fc-cache -f -v
# Restart applications using fonts
```

**Permission errors**:

```bash
# Fix ownership of config directory
sudo chown -R $(whoami) ~/.config/nix-darwin
```

**Build failures**:

```bash
# Clean build cache
nix-collect-garbage -d
# Retry with verbose output
darwin-rebuild switch --flake .#alex-mbp --show-trace -v
```

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Verbose rebuild with trace
darwin-rebuild switch --flake .#alex-mbp --show-trace -v

# Check system differences
nix store diff-closures /var/run/current-system ./result

# Verify module loading
nix flake show
```

## 📚 Documentation & Resources

### Internal Documentation

- **Package Strategy**: [`docs/NIX_VS_HOMEBREW.md`](docs/NIX_VS_HOMEBREW.md)
- **Migration Guide**: [`docs/PURIFICATION_SUMMARY.md`](docs/PURIFICATION_SUMMARY.md)
- **Optimizations**: [`docs/PACKAGE_OPTIMIZATION_SUMMARY.md`](docs/PACKAGE_OPTIMIZATION_SUMMARY.md)

### External Resources

- **Nix Darwin Manual**: [daiderd.com/nix-darwin](https://daiderd.com/nix-darwin/manual/)
- **Package Search**: [search.nixos.org](https://search.nixos.org/)
- **macOS Options**: [darwin.modules.system.defaults](https://daiderd.com/nix-darwin/manual/index.html#sec-options)
- **Homebrew Casks**: [formulae.brew.sh](https://formulae.brew.sh/cask/)

## 🎖️ Key Benefits

### ✅ **Production Ready**

- Battle-tested module structure
- Comprehensive error handling
- Automated cleanup and maintenance
- Rollback capabilities

### ✅ **Developer Optimized**

- Complete development environments
- Modern CLI tool replacements
- Intelligent shell configuration
- Fast build times with binary caches

### ✅ **Apple Silicon Native**

- Optimized for ARM64 architecture
- Native hardware integration
- Battery-efficient configurations
- macOS-specific optimizations

### ✅ **Reproducible & Maintainable**

- Declarative configuration as code
- Version-controlled dependencies
- Modular architecture for customization
- Comprehensive documentation

---

**Built with ❤️ for modern macOS development workflows**
