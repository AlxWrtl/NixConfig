{ config, pkgs, lib, inputs, ... }:

{
  # Development environment configuration
  # Language tools, runtimes, IDEs, and developer utilities
  # GUI apps are in brew.nix, core system tools are in packages.nix

  # ============================================================================
  # DEVELOPMENT PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [

    # === VERSION CONTROL & COLLABORATION ===
    git                                    # Distributed version control system
    git-lfs                                # Git Large File Storage extension
    gh                                     # GitHub CLI for repository management

    # === NIX ECOSYSTEM DEVELOPMENT ===
    nixd                                   # Primary Nix language server (recommended)
    nil                                    # Alternative Nix language server
    nixfmt-rfc-style                       # Official Nix code formatter
    nix-tree                               # Visualize Nix dependency trees
    nix-index                              # Search Nix packages efficiently
    vulnix                                 # CVE vulnerability scanner for Nix packages

    # === PYTHON DEVELOPMENT STACK ===
    python3                                # Latest Python 3 interpreter
    uv                                     # Modern Python package installer (pip replacement)
    ruff                                   # Fast Python linter and formatter

    # === JAVASCRIPT/NODE.JS DEVELOPMENT ===
    nodejs                                 # Node.js JavaScript runtime
    corepack                               # Official Node.js package manager manager
    pnpm                                   # Fast, disk space efficient package manager
    bun                                    # Ultra-fast JavaScript runtime and package manager

    # Node.js global tools
    nodePackages."@angular/cli"            # Angular framework CLI
    nodePackages.typescript                # TypeScript language and compiler
    nodePackages.eslint                    # JavaScript/TypeScript linter
    nodePackages.prettier                  # Opinionated code formatter

    # === DATABASE TOOLS ===
    sqlite                                 # Lightweight embedded database
    postgresql                             # PostgreSQL client tools and utilities

    # === API DEVELOPMENT & TESTING ===
    curl                                   # Command-line HTTP client
    wget                                   # File downloader and HTTP client
    httpie                                 # Human-friendly HTTP client
    jq                                     # Command-line JSON processor
    yq                                     # Command-line YAML processor

    # === SECURITY TOOLS ===
    age                                    # Modern file encryption tool
    sops                                   # Secrets management for Git repos
  ];

  # ============================================================================
  # DEVELOPMENT ENVIRONMENT VARIABLES
  # ============================================================================

  environment.variables = {
    # === Language Runtime Settings ===
    PYTHONPATH = "";                       # Clean Python path (avoid conflicts)
    NODE_ENV = "development";              # Default Node.js environment

    # === Development Tool Configuration ===
    GIT_EDITOR = "code --wait";            # Use VS Code as Git editor (when available)
  };

  # Note: EDITOR, VISUAL, PAGER are configured in system.nix to avoid conflicts

  # ============================================================================
  # DEVELOPMENT ALIASES & SHORTCUTS
  # ============================================================================

  environment.shellAliases = {
    # === Git Workflow Shortcuts ===
    g = "git";                             # Quick git access
    gs = "git status";                     # Check repository status
    ga = "git add";                        # Stage changes
    gc = "git commit";                     # Commit changes
    gp = "git push";                       # Push to remote
    gl = "git pull";                       # Pull from remote
    gd = "git diff";                       # Show differences
    gco = "git checkout";                  # Switch branches/restore files
    gb = "git branch";                     # List/manage branches

    # === Enhanced CLI Tools ===
    lt = "eza --tree";                     # Tree view with modern formatting
    cat = "bat";                           # Cat with syntax highlighting
    find = "fd";                           # Faster and more intuitive find
    grep = "rg";                           # Faster grep with better defaults

    # === Development Utilities ===
    serve = "python3 -m http.server";      # Quick local HTTP server
    py = "python3";                        # Python shortcut
    ipy = "ipython";                       # IPython interactive shell

    # === Nix Development ===
    nix-shell = "nix-shell --run zsh";     # Use zsh in nix development shells
    rebuild = "sudo darwin-rebuild switch --flake ."; # Quick system rebuild

    # === Container Management ===
    dc = "docker-compose";                 # Docker Compose shortcut
    dcu = "docker-compose up";             # Start services
    dcd = "docker-compose down";           # Stop services
  };

  # ============================================================================
  # LANGUAGE-SPECIFIC CONFIGURATIONS
  # ============================================================================

  # === Python Configuration ===
  environment.etc."pip.conf".text = ''
    [global]
    break-system-packages = true
    user = true
  '';

}