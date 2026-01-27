{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # Development environment configuration
  # Language tools, runtimes, IDEs, and developer utilities
  # GUI apps are in brew.nix, core system tools are in packages.nix

  # ============================================================================
  # DEVELOPMENT PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [

    # === VERSION CONTROL & COLLABORATION ===
    git # Distributed version control system
    git-lfs # Git Large File Storage extension
    gh # GitHub CLI for repository management

    # === NIX ECOSYSTEM DEVELOPMENT ===
    nixd # Primary Nix language server (recommended)
    nil # Alternative Nix language server
    nixfmt # Official Nix code formatter (RFC style)
    nix-tree # Visualize Nix dependency trees
    nix-index # Search Nix packages efficiently
    vulnix # CVE vulnerability scanner for Nix packages

    # === JAVASCRIPT/NODE.JS DEVELOPMENT ===
    nodejs_20 # Node.js LTS runtime (includes npm/npx)
    pnpm # Fast, disk space efficient package manager

    # Node.js global tools
    nodePackages."@angular/cli" # Angular framework CLI
    nodePackages.typescript # TypeScript language and compiler
    nodePackages.eslint # JavaScript/TypeScript linter
    nodePackages.prettier # Opinionated code formatter

    # === DATABASE TOOLS ===
    sqlite # Lightweight embedded database
    postgresql # PostgreSQL client tools and utilities

    # === API DEVELOPMENT & TESTING ===
    curl # Command-line HTTP client
    wget # File downloader and HTTP client
    httpie # Human-friendly HTTP client
    jq # Command-line JSON processor
    yq # Command-line YAML processor
    redis # In-memory data structure store

    # === SECURITY TOOLS ===
    age # Modern file encryption tool
    sops # Secrets management for Git repos
  ]
  # === PYTHON DEVELOPMENT STACK (Optional) ===
  ++ lib.optionals config.nix-darwin.enablePython [
    python3 # Latest Python 3 interpreter
    uv # Modern Python package installer (pip replacement)
    ruff # Fast Python linter and formatter
  ];

  # ============================================================================
  # DEVELOPMENT ENVIRONMENT VARIABLES
  # ============================================================================

  environment.variables = {
    # === Language Runtime Settings ===
    PYTHONPATH = ""; # Clean Python path (avoid conflicts)
    NODE_ENV = "development"; # Default Node.js environment

    # === Development Tool Configuration ===
    GIT_EDITOR = "code --wait"; # Use VS Code as Git editor (when available)
  };

  # Note: EDITOR, VISUAL, PAGER are configured in system.nix to avoid conflicts

  # ============================================================================
  # DEVELOPMENT ALIASES & SHORTCUTS
  # ============================================================================

  environment.shellAliases = {

    # === Development Utilities ===
    serve = "python3 -m http.server"; # Quick local HTTP server
    py = "python3"; # Python shortcut
    ipy = "ipython"; # IPython interactive shell

    # === Nix Development ===
    nix-shell = "nix-shell --run zsh"; # Use zsh in nix development shells
    rebuild = "sudo darwin-rebuild switch --flake ."; # Quick system rebuild

    # === Container Management ===
    dc = "docker-compose"; # Docker Compose shortcut
    dcu = "docker-compose up"; # Start services
    dcd = "docker-compose down"; # Stop services
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
