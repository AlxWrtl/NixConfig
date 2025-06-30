{ config, pkgs, lib, inputs, ... }:

{
    # High-performance Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = false;     # Completely disable nix-managed completions
    enableBashCompletion = false; # Disable bash completion integration

    # Optimized prompt initialization
    promptInit = ''
      # ---- Performance: Skip unnecessary checks ----
      skip_global_compinit=1

            # ---- Production-grade completion optimization ----
      () {
        setopt local_options extendedglob
        autoload -Uz compinit
        local zcompdump="''${ZDOTDIR:-$HOME}/.zcompdump"
        local lockfile="''${zcompdump}.lock"
        local lock_timeout=1

        # Handle concurrent shell startups
        if [[ -f "$lockfile" ]]; then
          if [[ -f $lockfile(#qN.mm+$lock_timeout) ]]; then
            echo "Warning: compinit lockfile timeout" >&2
          fi
          compinit -C -d "$zcompdump"
          return
        fi

        # Create lock and ensure cleanup
        echo $$ > "$lockfile"
        trap "rm -f '$lockfile'" EXIT

        # Time-based cache + compilation
        if [[ -n $zcompdump(#qN.mh+24) ]]; then
          compinit -d "$zcompdump"
        else
          compinit -C -d "$zcompdump"
        fi

        # Background bytecode compilation
        {
          if [[ -s "$zcompdump" && (! -s "''${zcompdump}.zwc" || "$zcompdump" -nt "''${zcompdump}.zwc") ]]; then
            zcompile "$zcompdump"
          fi
        } &!
      }

      # ---- Minimal completion configuration ----
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
      zstyle ':completion:*' menu select

      # Skip slow completion features
      zstyle ':completion:*' use-cache on
      zstyle ':completion:*' cache-path ~/.zsh/cache

      # ---- Starship Prompt ----
      if command -v starship >/dev/null 2>&1; then
        eval "$(starship init zsh)"
      fi
    '';

    # Initialisation shell (.zshrc)
    shellInit = ''
      # ---- Performance: Early exits for non-interactive shells ----
      [[ $- != *i* ]] && return

      # ---- PATH & PNPM (cached) ----
      export PNPM_HOME="$HOME/Library/pnpm"
      case ":$PATH:" in
        *":$PNPM_HOME:"*) ;;
        *) export PATH="$PNPM_HOME:$PATH" ;;
      esac

      # ---- EZA & Aliases ----
      export EZA_CONFIG_DIR="$HOME/.config/eza"

      alias ls="eza --group-directories-first --color=always --long --git --icons=always --grid --no-filesize --no-user --no-time --no-permissions"
      alias la="eza --group-directories-first --color=always --icons=always --all"
      alias ll="eza --group-directories-first --color=always --long --git --icons=always"
      alias lla="eza --group-directories-first --color=always --long --git --icons=always --all"
      alias lld="eza --group-directories-first --color=always --long --git --icons=always --list-dirs"
      alias tree="eza --group-directories-first --color=always --long --tree --icons=always --git"
      alias treeall="eza --group-directories-first --color=always --long --tree --icons=always --git --all"

      # ---- General Utilities (shell-specific) ----
      alias vim='nvim'
      alias top='htop'

      # Note: Development-related aliases (git, docker, python, modern tools) are in development.nix

      # ---- Command History Configuration ----
      HISTFILE=$HOME/.zhistory
      SAVEHIST=1000  # Increased history storage (matching user's .zshrc)
      HISTSIZE=999

      # History settings
      setopt share_history           # Share history between all sessions
      setopt hist_expire_dups_first  # Expire duplicate entries first
      setopt hist_ignore_dups        # Ignore duplicate entries
      setopt hist_verify             # Verify history substitution

      # Performance options
      setopt AUTO_CD
      setopt CORRECT
      setopt NO_BEEP

      # Performance: Disable unnecessary features
      unsetopt BEEP
      unsetopt NOMATCH

      # ---- FNM (Fast Node Manager) Configuration ----
      export FNM_DIR="$HOME/.fnm"
    '';

    # Performance-optimized interactive initialization
    interactiveShellInit = ''
      # ---- Performance: Only load for interactive shells ----
      [[ $- != *i* ]] && return

      # ---- ZSH Autosuggestions (Lazy loaded) ----
      if [[ -f ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
        # Performance tuning
        ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
        ZSH_AUTOSUGGEST_USE_ASYNC=1
      fi

      # ---- ZSH Fast Syntax Highlighting ----
      if [[ -f ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh ]]; then
        source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh
      fi

      # ---- Zoxide Configuration ----
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init zsh)"
      fi

      # ---- FNM (Fast Node Manager) Initialization ----
      if command -v fnm >/dev/null 2>&1; then
        eval "$(fnm env --use-on-cd)"
      fi

      # ---- FZF Configuration ----
      if command -v fzf >/dev/null 2>&1; then
        # Enhanced _fzf_comprun function with better previews
        _fzf_comprun() {
          local command=$1
          shift
          case "$command" in
            cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
            export|unset) fzf --preview "eval 'echo $'{}" "$@" ;;
            ssh)          fzf --preview 'dig {}' "$@" ;;
            *)            fzf --preview "bat -n --color=always --line-range :500 {}" "$@" ;;
          esac
        }

        # Initialize FZF key bindings and completion
        eval "$(fzf --zsh)"
      fi

      # ---- Sudo Plugin Replacement ----
      # ESC twice to add sudo to current command (replaces Oh My Zsh sudo plugin)
      sudo-command-line() {
        [[ -z $BUFFER ]] && zle up-history
        if [[ $BUFFER == sudo\ * ]]; then
          LBUFFER="''${LBUFFER#sudo }"
        else
          LBUFFER="sudo $LBUFFER"
        fi
      }
      zle -N sudo-command-line
      # Press ESC twice to toggle sudo
      bindkey "\e\e" sudo-command-line

      # Force history search bindings (runs after all other initializations)
      bindkey '^[[A' history-search-backward  # Up arrow
      bindkey '^[[B' history-search-forward   # Down arrow
      bindkey '^[OA' history-search-backward  # Alternative up arrow
      bindkey '^[OB' history-search-forward   # Alternative down arrow
    '';
  };

  # Définir zsh comme shell par défaut
  environment.shells = [ pkgs.zsh ];

  # Variables d'environnement générales
  environment.variables = {
    FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :500 {}'";
    FZF_ALT_C_OPTS = "--preview 'eza --tree --color=always {} | head -200'";
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";

    BAT_THEME = "TwoDark";
    LESS = "-R --use-color -Dd+r -Du+b";
    EDITOR = "nvim";
    VISUAL = "nvim";
    DOCKER_DEFAULT_PLATFORM = "linux/amd64";
    EZA_CONFIG_DIR = "$HOME/.config/eza";
    PNPM_HOME = "$HOME/Library/pnpm";
    FNM_DIR = "$HOME/.fnm";
  };
}
