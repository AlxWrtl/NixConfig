{ config, pkgs, lib, inputs, ... }:

{
  # System packages configuration - Maximizing Nix usage

  environment.systemPackages = with pkgs; [

    # === Text Editors & Development Tools ===
    vscode              # Visual Studio Code
    prettierd           # Code formatter daemon
    git                 # Version control

    # === Programming Languages & Runtimes ===
    # Python
    uv                  # Fast Python package manager

    # JavaScript/Node.js
    nodejs_23           # Latest Node.js
    pnpm                # Fast package manager

    # === Development Utilities ===
    jq                  # JSON processor
    yq                  # YAML processor

    # Network tools
    curl                # HTTP client

    # Shell enhancements
    zsh                 # Z shell
    zsh-powerlevel10k   # Shell theme
    zsh-autosuggestions # Command autosuggestions
    zsh-syntax-highlighting # Syntax highlighting

    # Navigation & file management
    zoxide              # Smart directory jumper
    fzf                 # Fuzzy finder
    eza                 # Modern ls replacement
    bat                 # Cat with syntax highlighting
    tree                # Directory tree viewer
    fd                  # Find alternative
    ripgrep             # Grep alternative
    rsync               # File synchronization
    keka                # Archive extractor

    # History & session management
    atuin               # Shell history manager

    # === Media Applications ===
    vlc                 # Media player

    # === System Utilities & Window Management ===
    appcleaner          # App uninstaller
  ];

  # Enable unfree packages globally
  nixpkgs.config.allowUnfree = true;
}