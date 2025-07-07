{ config, pkgs, lib, inputs, ... }:

{
  # === DEVELOPMENT ENVIRONMENT CONFIGURATION ===
  # Language-specific tools, IDEs, and development utilities

  environment.systemPackages = with pkgs; [

    # === VERSION CONTROL & COLLABORATION ===
    git                 # Git version control
    git-lfs            # Git Large File Storage
    gh                 # GitHub CLI
    lazygit            # Git terminal UI

    # === NIX DEVELOPMENT ===
    nixd                # Nix language server (primary)
    nil                 # Alternative Nix LSP
    nixfmt-rfc-style   # Nix code formatter
    nix-tree           # Nix dependency tree viewer
    nix-index          # Nix package search

    # === PYTHON DEVELOPMENT ===
    python3             # Latest Python 3
    uv                  # Modern Python package manager
    ruff                # Python linter and formatter

    # === JAVASCRIPT/NODE DEVELOPMENT ===
    nodejs              # Node.js runtime
    pnpm                # Fast package manager
    nodePackages."@angular/cli" # Angular CLI
    nodePackages.typescript     # TypeScript compiler
    nodePackages.eslint        # JavaScript linter
    nodePackages.prettier      # Code formatter

    # === DATABASE TOOLS ===
    sqlite              # Lightweight database
    postgresql          # PostgreSQL client tools

    # === API & TESTING TOOLS ===
    curl                # HTTP client
    wget                # File downloader
    httpie              # Human-friendly HTTP client
    jq                  # JSON processor
    yq                  # YAML processor

    # === AI & MACHINE LEARNING ===
    #ollama              # AI model server and CLI

  ];

    # === DEVELOPMENT-SPECIFIC ENVIRONMENT VARIABLES ===
  environment.variables = {
    # Language-specific settings
    PYTHONPATH = "";              # Clean Python path
    NODE_ENV = "development";     # Default Node environment

    # Git configuration helpers
    GIT_EDITOR = "code --wait";   # Git editor (specific to development)
  };

  # Note: EDITOR, VISUAL, PAGER are configured in modules/shell.nix to avoid conflicts

  # === DEVELOPMENT SHELL ALIASES ===
  environment.shellAliases = {
    # Git shortcuts (logical here since development.nix includes git packages)
    g = "git";
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gp = "git push";
    gl = "git pull";
    gd = "git diff";
    gco = "git checkout";
    gb = "git branch";

    # Modern tool replacements (logical here since they're dev tools)
    lt = "eza --tree";            # Tree view
    cat = "bat";                  # Syntax highlighted cat
    find = "fd";                  # Faster find
    grep = "rg";                  # Faster grep

    # Development shortcuts
    serve = "python3 -m http.server"; # Quick HTTP server
    py = "python3";               # Python shortcut
    ipy = "ipython";             # IPython shortcut

    # Nix shortcuts
    nix-shell = "nix-shell --run zsh"; # Use zsh in nix-shell
    rebuild = "sudo darwin-rebuild switch --flake .";

    # Docker shortcuts (logical here since Docker is dev-related)
    dc = "docker-compose";
    dcu = "docker-compose up";
    dcd = "docker-compose down";
  };

  # === PROGRAMMING LANGUAGE CONFIGURATIONS ===

  # Python configuration
  environment.etc."pip.conf".text = ''
    [global]
    break-system-packages = true
    user = true
  '';

  # === DEVELOPMENT NOTES ===
  # - GUI development tools (VS Code, Docker Desktop) are in brew.nix
  # - Language-specific package managers (pip, npm) handle library dependencies
  # - System packages focus on core development utilities
  # - User-specific development tools can be added via users.users.alx.packages
}