{
  config,
  pkgs,
  lib,
  ...
}:

{
  # System and development packages
  # Consolidated from: packages.nix, development.nix

  config = lib.mkMerge [
    # ============================================================================
    # BASE PACKAGES (ALWAYS LOADED)
    # ============================================================================

    {
      environment.systemPackages = with pkgs; [
        # === SHELL & TERMINAL ===
        zsh
        starship
        zsh-autosuggestions
        zsh-fast-syntax-highlighting

        # === MODERN CLI TOOLS ===
        eza # Modern ls
        bat # Modern cat
        fd # Modern find
        ripgrep # Modern grep
        tree # Directory visualization

        # === NAVIGATION & SEARCH ===
        zoxide # Smart cd
        fzf # Fuzzy finder
        atuin # Enhanced shell history

        # === FILE OPERATIONS ===
        rsync # File synchronization

        # === SYSTEM MONITORING ===
        btop # System monitor
        fastfetch # System info

        # === VERSION CONTROL ===
        git
        git-lfs
        gh # GitHub CLI

        # === NIX DEVELOPMENT ===
        nixd # Nix language server (primary)
        nil # Nix language server (alternative)
        nixfmt-rfc-style # Nix formatter
        nix-tree # Dependency visualization
        nix-index # Package search
        vulnix # CVE scanner

        # === JAVASCRIPT/NODE.JS ===
        nodejs_20 # Node.js LTS
        pnpm # Package manager
        bun # Fast JS runtime
        nodePackages."@angular/cli"
        nodePackages.typescript
        nodePackages.eslint
        nodePackages.prettier

        # === DATABASES ===
        sqlite
        postgresql

        # === API DEVELOPMENT ===
        curl
        wget
        httpie
        jq # JSON processor
        yq # YAML processor
        redis

        # === SECURITY ===
        age # Encryption
        sops # Secrets management
      ];

      # === DEVELOPMENT ENVIRONMENT VARIABLES ===
      environment.variables = {
        PYTHONPATH = "";
        NODE_ENV = "development";
        GIT_EDITOR = "code --wait";
      };

      # === DEVELOPMENT ALIASES ===
      environment.shellAliases = {
        # Python
        serve = "python3 -m http.server";
        py = "python3";
        ipy = "ipython";

        # Nix
        nix-shell = "nix-shell --run zsh";
        rebuild = "sudo darwin-rebuild switch --flake .";

        # Docker
        dc = "docker-compose";
        dcu = "docker-compose up";
        dcd = "docker-compose down";
      };

      # === PYTHON CONFIGURATION ===
      environment.etc."pip.conf".text = ''
        [global]
        break-system-packages = true
        user = true
      '';
    }

    # ============================================================================
    # PYTHON DEVELOPMENT
    # ============================================================================

    {
      environment.systemPackages = with pkgs; [
        python3
        uv # Modern Python package installer
        ruff # Fast Python linter/formatter
      ];
    }
  ];
}
