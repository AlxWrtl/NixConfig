# 🔄 Nix Packages vs Homebrew Casks

## Overview

Your configuration has been optimized to prefer **Nix packages** over Homebrew casks whenever possible. This approach provides better reproducibility, version pinning, and declarative management.

## ✅ Applications Moved from Homebrew to Nix

### GUI Applications (now in `modules/packages.nix`)
- **VLC** → `vlc` (Media player)
- **Spotify** → `spotify` (Music streaming)
- **Discord** → `discord` (Communication)
- **WhatsApp** → `whatsapp-for-mac` (Messaging)
- **Obsidian** → `obsidian` (Note-taking)
- **Raycast** → `raycast` (Spotlight replacement)
- **Rectangle** → `rectangle` (Window management)
- **Stats** → `stats` (System monitor)
- **Zoom** → `zoom-us` (Video conferencing)
- **Slack** → `slack` (Team communication)
- **Telegram** → `telegram-desktop` (Messaging)
- **Firefox** → `firefox` (Browser)
- **Brave** → `brave` (Privacy browser)
- **Postman** → `postman` (API testing)
- **Docker** → `docker` (Containerization)
- **Notion** → `notion` (Workspace)

### CLI Tools (now in `modules/packages.nix`)
- **wget** → `wget` (Web downloader)
- **curl** → `curl` (HTTP client)
- **httpie** → `httpie` (Modern HTTP client)
- **nmap** → `nmap` (Network scanner)
- **htop** → `htop` (Process viewer)
- **btop** → `btop` (System monitor)
- **tree** → `tree` (Directory tree)
- **watch** → `watch` (Command execution)
- **gh** → `gh` (GitHub CLI)
- **git-delta** → `git-delta` (Better git diff)
- **ffmpeg** → `ffmpeg` (Media processing)

## 🍺 Applications Kept in Homebrew

### Why Some Apps Stay in Homebrew:

#### 1. **macOS-Specific Features**
```nix
"1password"      # Deep macOS integration, Touch ID, Keychain
"bartender"      # macOS menu bar management
"onyx"           # macOS system maintenance
"appcleaner"     # macOS app bundle cleanup
```

#### 2. **Latest Versions & Updates**
```nix
"ghostty"        # Cutting-edge terminal, frequent updates
"figma"          # Latest design features, auto-updates
"warp"           # Modern terminal with latest features
```

#### 3. **Proprietary Software**
```nix
"adobe-creative-cloud"  # Proprietary licensing
"sketch"               # macOS-exclusive design tool
"microsoft-teams"      # Corporate features, licensing
```

#### 4. **Complex Dependencies**
```nix
"orbstack"       # Docker alternative with system integration
"tableplus"      # Database GUI with native performance
"istat-menus"    # Deep system monitoring
```

## 🎯 Benefits of This Approach

### ✅ **Nix Packages Advantages:**
- **Reproducible**: Exact same versions across machines
- **Declarative**: Configuration as code
- **Atomic**: All-or-nothing updates
- **Rollback**: Easy to revert changes
- **No System Pollution**: Packages are isolated
- **Version Pinning**: Lock specific versions

### ✅ **Selective Homebrew Advantages:**
- **Native macOS Integration**: Better system integration
- **Latest Versions**: Often more up-to-date
- **Proprietary Software**: Access to commercial apps
- **macOS-Specific Features**: Leverages platform capabilities

## 🔧 How It Works

### Nix Package Installation
```bash
# Applications installed via Nix are symlinked to /Applications
ls -la /Applications/ | grep nix
# You'll see symlinks like: Firefox.app -> /nix/store/...
```

### Finding Nix Packages
```bash
# Search for packages
nix search nixpkgs discord
nix search nixpkgs vlc

# Check if package exists
nix-env -qaP | grep -i "package-name"
```

### Adding New Nix Packages
```nix
# In modules/packages.nix
environment.systemPackages = with pkgs; [
  your-new-package
];
```

### Adding Homebrew Casks (when necessary)
```nix
# In modules/brew.nix
casks = [
  "your-macos-specific-app"
];
```

## 📊 Current Distribution

### Managed by Nix (~80%)
- All CLI tools
- Most cross-platform GUI apps
- Development tools
- Open source software

### Managed by Homebrew (~20%)
- macOS-specific utilities
- Proprietary software
- Apps requiring latest versions
- Complex system integrations

## 🚀 Best Practices

### ✅ **Choose Nix When:**
- App is available in nixpkgs
- You want version reproducibility
- App is cross-platform
- You prefer declarative management

### ✅ **Choose Homebrew When:**
- App requires deep macOS integration
- App is macOS-exclusive
- You need the absolute latest version
- App has complex licensing requirements

## 🔄 Migration Commands

### Apply Changes
```bash
# Apply the updated configuration
darwin-rebuild switch --flake .#alex-mbp

# This will:
# 1. Install new Nix packages
# 2. Remove moved Homebrew casks
# 3. Create symlinks in /Applications
```

### Verify Installation
```bash
# Check Nix-managed apps
ls -la /Applications/ | grep -E "(VLC|Discord|Spotify)"

# Check Homebrew-managed apps
brew list --cask
```

### Clean Up
```bash
# Remove orphaned Homebrew packages
brew autoremove
brew cleanup
```

## 💡 Tips

1. **Symlinks**: Nix packages appear as symlinks in `/Applications` - this is normal!
2. **Updates**: `darwin-rebuild switch` updates both Nix and Homebrew packages
3. **Rollback**: Use `darwin-rebuild rollback` if something breaks
4. **Search**: Always check nixpkgs first before adding to Homebrew

This hybrid approach gives you the best of both worlds: reproducible, declarative management via Nix for most software, while keeping Homebrew for macOS-specific needs.