{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./claude-code.nix
  ];

  # ============================================================================
  # HOME MANAGER USER CONFIGURATION
  # ============================================================================
  # Modern user-level configuration managed by home-manager
  # This separates user settings from system settings for better modularity

  # === Basic Configuration ===
  home.username = "alx";
  home.homeDirectory = "/Users/alx";
  home.stateVersion = "24.11";

  home.sessionVariables = {
    CLAUDE_CONFIG_DIR = "$HOME/.claude";
  };

  # === Allow Home Manager to manage itself ===
  programs.home-manager.enable = true;

  # ============================================================================
  # USER SHELL CONFIGURATION
  # ============================================================================

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = false;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 50000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
    };

    # === Initial Shell Setup (runs for all shells) ===
    initContent = ''
      # ---- Performance: Skip expensive operations for non-interactive shells ----
      skip_global_compinit=1

      # ---- Production-Grade Completion System ----
      # Custom compinit with 24-hour caching and background bytecode compilation
      () {
        setopt local_options extendedglob
        autoload -Uz compinit
        local zcompdump="''${ZDOTDIR:-$HOME}/.zcompdump"

        # Quick 24-hour cache check (performance optimization)
        if [[ -n $zcompdump(#qN.mh+24) ]]; then
          compinit -d "$zcompdump"                 # Full security check (daily)
        else
          compinit -C -d "$zcompdump"              # Skip security check (trusted cache)
        fi

        # Background bytecode compilation (non-blocking startup)
        {
          if [[ -s "$zcompdump" && (! -s "''${zcompdump}.zwc" || "$zcompdump" -nt "''${zcompdump}.zwc") ]]; then
            zcompile "$zcompdump" &!
          fi
        } 2>/dev/null
      }

      # ---- Completion Behavior Configuration ----
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
      zstyle ':completion:*' menu select
      zstyle ':completion:*' use-cache on
      zstyle ':completion:*' cache-path ~/.zsh/cache

      # ---- Cached Starship Prompt Initialization ----
      if command -v starship >/dev/null 2>&1; then
        local starship_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/starship_init.zsh"
        if [[ ! -f "$starship_cache" || $(command -v starship) -nt "$starship_cache" ]]; then
          command mkdir -p "''${starship_cache%/*}"
          starship init zsh > "$starship_cache" 2>/dev/null
        fi
        [[ -r "$starship_cache" ]] && source "$starship_cache"
      fi

      # ---- Performance: Early exit for non-interactive shells ----
      [[ $- != *i* ]] && return

      # ---- PATH Configuration ----
      export PNPM_HOME="$HOME/Library/pnpm"
      case ":$PATH:" in
        *":$PNPM_HOME:"*) ;;
        *) export PATH="$PNPM_HOME:$PATH" ;;
      esac

      # ---- Command History Configuration ----
      HISTFILE=$HOME/.zhistory
      SAVEHIST=1000
      HISTSIZE=999

      # History behavior options
      setopt share_history                         # Share history between sessions
      setopt hist_expire_dups_first                # Remove duplicates first when trimming
      setopt hist_ignore_dups                      # Don't record duplicates
      setopt hist_verify                           # Show history expansion before executing

      # ---- Shell Behavior Options ----
      setopt AUTO_CD                               # Auto cd when typing directory name
      setopt CORRECT                               # Spelling correction for commands
      setopt NO_BEEP                               # Disable beeping
      unsetopt BEEP                                # Ensure no beeping
      unsetopt NOMATCH                             # Don't error on glob no matches

      # ---- Tool-Specific Environment ----
      export EZA_CONFIG_DIR="$HOME/.config/eza"

      # ============================================================================
      # PLUGIN LOADING & EXTENSIONS
      # ============================================================================

      # ---- Direct Plugin Loading (maximum performance) ----
      # Load plugins directly from Nix store paths (no plugin manager overhead)

      if [[ -f ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      fi

      if [[ -f ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh ]]; then
        source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh
      fi

      # ---- Plugin Performance Tuning ----
      ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20           # Limit autosuggestion buffer size
      ZSH_AUTOSUGGEST_USE_ASYNC=1                  # Use async suggestions

      # ============================================================================
      # TOOL INTEGRATIONS (with caching)
      # ============================================================================

      # ---- High-Performance Eval Caching Function ----
      # Cache expensive command initializations for major speed improvements
      _eval_cache() {
        local cmd="$1" cache_file="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh_eval_cache_''${cmd//[^a-zA-Z0-9]/_}"
        shift

        if [[ ! -f "$cache_file" || $(command -v "$cmd") -nt "$cache_file" ]]; then
          command mkdir -p "''${cache_file%/*}"
          eval "$@" > "$cache_file" 2>/dev/null
        fi
        [[ -r "$cache_file" ]] && source "$cache_file"
      }

      # ---- Cached Tool Initializations ----

      # ---- Zoxide (z command) ----
      _eval_cache zoxide 'zoxide init zsh'

      # ---- FZF Integration with Enhanced Previews ----
      if command -v fzf >/dev/null 2>&1; then
        # Custom preview function for different command contexts
        _fzf_comprun() {
          local command=$1
          shift
          case "$command" in
            cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
            export|unset) fzf --preview "eval 'echo {}'" "$@" ;;
            ssh)          fzf --preview 'dig {}' "$@" ;;
            *)            fzf --preview "bat -n --color=always --line-range :500 {}" "$@" ;;
          esac
        }

        # Initialize FZF with zsh integration
        eval "$(fzf --zsh)"
      fi

      # ============================================================================
      # KEY BINDINGS & SHORTCUTS
      # ============================================================================

      # ---- Sudo Toggle Function ----
      # Press ESC twice to toggle sudo on current command
      sudo-command-line() {
        [[ -z $BUFFER ]] && zle up-history
        if [[ $BUFFER == sudo\ * ]]; then
          LBUFFER="''${LBUFFER#sudo }"              # Remove sudo if present
        else
          LBUFFER="sudo $LBUFFER"                   # Add sudo if not present
        fi
      }
      zle -N sudo-command-line
      bindkey "\e\e" sudo-command-line              # ESC ESC to toggle sudo

      # ---- Enhanced History Search ----
      bindkey '^[[A' history-search-backward        # Up arrow: search backward
      bindkey '^[[B' history-search-forward         # Down arrow: search forward
    '';

    shellAliases = {
      # Security tools
      vulnscan = "vulnix --system /var/run/current-system";
      secrets = "sops";
      encrypt = "age";

      # Home Manager
      hm = "home-manager";
      hms = "home-manager switch";
      hmb = "home-manager build";

      # ---- Modern File Listing (eza-based) ----
      ls = "eza --group-directories-first --color=always --long --git --icons=always --grid --no-filesize --no-user --no-time --no-permissions";
      la = "eza --group-directories-first --color=always --icons=always --all";
      ll = "eza --group-directories-first --color=always --long --git --icons=always";
      lla = "eza --group-directories-first --color=always --long --git --icons=always --all";
      lld = "eza --group-directories-first --color=always --long --git --icons=always --list-dirs";
      tree = "eza --group-directories-first --color=always --long --tree --icons=always --git";
      treeall = "eza --group-directories-first --color=always --long --tree --icons=always --git --all";

      # ---- System Tool Replacements ----
      vim = "nvim";
      top = "htop";

      # ---- Miscellaneous Shortcuts ----
      cc = "claude";
      lt = "eza --tree";
      cat = "bat";
      find = "fd";
      grep = "rg";
    };

    sessionVariables = {
      HOMEBREW_NO_ANALYTICS = "1";
      HOMEBREW_NO_INSECURE_REDIRECT = "1";

      GNUPGHOME = "$XDG_CONFIG_HOME/gnupg";
      AGE_DIR = "$XDG_CONFIG_HOME/age";

      CLAUDE_CONFIG_DIR = "$HOME/.claude";

      # FZF Configuration
      FZF_CTRL_R_OPTS = "--no-preview";
      FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :500 {}'";
      FZF_ALT_C_OPTS = "--preview 'eza --tree --color=always {} | head -200'";
      FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
      FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --ansi";

      # Tool Appearance & Behavior
      BAT_THEME = "TwoDark";
      LESS = "-R --use-color";
      DOCKER_DEFAULT_PLATFORM = "linux/amd64";

      # Tool Configuration Directories
      EZA_CONFIG_DIR = "$HOME/.config/eza";
      PNPM_HOME = "$HOME/Library/pnpm";
    };
  };

  # ============================================================================
  # USER GIT CONFIGURATION
  # ============================================================================

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Alexandre";
        email = "indexes-benzine0p@icloud.com";
      };

      init.defaultBranch = "main";
      push.default = "simple";
      pull.rebase = true;
      rerere.enabled = true;

      # Security settings
      transfer.fsckObjects = true;
      fetch.fsckObjects = true;
      receive.fsckObjects = true;

      # Modern Git features
      feature.manyFiles = true;
      index.version = 4;
    };
  };

  # ============================================================================
  # USER DEVELOPMENT ENVIRONMENT
  # ============================================================================

  # User-specific packages (development tools, utilities)
  home.packages = with pkgs; [
    # Development utilities that should be user-scoped
    gh-dash # GitHub dashboard
    gitleaks # Git secrets scanner
    pre-commit # Git pre-commit hooks

    # Personal productivity tools
    tree # Directory tree viewer
    watch # Execute programs periodically
    tldr # Simplified man pages
  ];

  # ============================================================================
  # USER SERVICES & AUTOMATION
  # ============================================================================

  # Personal security scanning service
  # DISABLED: Redundant with system security-vulnerability-scan
  # launchd.agents.personal-security-scan = {
  #   enable = true;
  #   config = {
  #     ProgramArguments = [
  #       "${pkgs.vulnix}/bin/vulnix"
  #       "--system"
  #       "/var/run/current-system"
  #       "--json"
  #       "/Users/alx/.cache/vulnix-scan.json"
  #     ];
  #     StartCalendarInterval = [
  #       {
  #         Weekday = 1;
  #         Hour = 10;
  #         Minute = 0;
  #       } # Monday 10 AM
  #     ];
  #     StandardOutPath = "/Users/alx/.cache/vulnix-scan.log";
  #     StandardErrorPath = "/Users/alx/.cache/vulnix-scan-error.log";
  #   };
  # };

  # ============================================================================
  # XDG DIRECTORIES
  # ============================================================================

  xdg = {
    enable = true;
    # Note: userDirs is Linux-only, macOS uses standard directories
  };

  # ============================================================================
  # USER FONTS
  # ============================================================================

  fonts.fontconfig.enable = true;

}
