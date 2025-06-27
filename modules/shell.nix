{ config, pkgs, lib, inputs, ... }:

{
  # Configuration de Zsh avec Starship prompt
  programs.zsh = {
    enable = true;
    enableCompletion = false;  # Disable to avoid order conflicts
    enableBashCompletion = false;

    # Starship Prompt Configuration
    promptInit = ''
      # ---- Initialize completion system FIRST ----
      autoload -Uz compinit
      compinit -C

      # ---- Configure case-insensitive completion ----
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
      zstyle ':completion:*' menu select
      zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
      zstyle ':completion:*:cd:*' ignore-parents parent pwd

      # ---- Initialize bash completion ----
      autoload -U bashcompinit
      bashcompinit

      # ---- Angular Autocompletion (after compinit) ----
      if command -v ng >/dev/null 2>&1; then
        eval "$(ng completion script 2>/dev/null || true)"
      fi

      # ---- Starship Prompt ----
      if command -v starship >/dev/null 2>&1; then
        eval "$(starship init zsh)"
      fi
    '';

    # Initialisation shell (.zshrc)
    shellInit = ''
      # ---- PATH & PNPM ----
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

            # NOTE: Key bindings are set in interactiveShellInit to run after all other initializations

            setopt AUTO_CD
      setopt CORRECT
      setopt NO_BEEP



      # ---- NVM Configuration ----
      export NVM_DIR="$HOME/.nvm"
      if [[ -s "/opt/homebrew/opt/nvm/nvm.sh" ]]; then
        source "/opt/homebrew/opt/nvm/nvm.sh"
      fi
    '';

    # Ajout des fonctions shell personnalisées et key bindings finaux
    interactiveShellInit = ''
            # ---- ZSH Autosuggestions ----
      # Load autosuggestions (gray text suggestions as you type)
      if [[ -f ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      fi

      # ---- ZSH Syntax Highlighting ----
      # Load syntax highlighting (green for valid commands, red for invalid)
      # NOTE: This must be loaded AFTER autosuggestions
      if [[ -f ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
        source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      fi

            # ---- Zoxide Configuration ----
      # Initialize zoxide (smart cd replacement)
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init zsh)"
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
    NVM_DIR = "$HOME/.nvm";
  };
}
