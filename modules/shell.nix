{ config, pkgs, lib, inputs, ... }:

{
  # Shell configuration (Zsh with Powerlevel10k) - Matching existing .zshrc and .p10k.zsh

  programs.zsh = {
    enable = true;

    # Shell prompt and theme configuration
    promptInit = ''
      # ---- Instant Prompt for Powerlevel10k ----
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

      # ---- Powerlevel10k Configuration ----
      # Source the p10k configuration (will be managed by Nix)
      if [[ -f ~/.p10k.zsh ]]; then
        source ~/.p10k.zsh
      fi

      # Load Powerlevel10k theme from Nix
      if [[ -r "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme" ]]; then
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      fi

      # ---- Zsh Plugins ----
      # Zsh Syntax Highlighting
      if [[ -r "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
        source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      fi

      # Zsh Autosuggestions
      if [[ -r "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      fi

      # Enhanced cd with Zoxide
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init zsh)"
      fi

      # FZF Configuration and key bindings
      if command -v fzf >/dev/null 2>&1; then
        eval "$(fzf --zsh)"
      fi
    '';

    # Shell initialization matching your .zshrc
    shellInit = ''
      # ---- PATH Configuration ----
      # Note: Nix will manage most PATH entries, but keeping structure for compatibility

      # ---- PNPM Configuration ----
      export PNPM_HOME="$HOME/Library/pnpm"
      case ":$PATH:" in
        *":$PNPM_HOME:"*) ;;
        *) export PATH="$PNPM_HOME:$PATH" ;;
      esac

      # ---- Aliases (Enhanced EZA commands matching your config) ----
      export EZA_CONFIG_DIR="$HOME/.config/eza"

      # Enhanced ls commands with eza (matching your exact aliases)
      alias ls="eza --group-directories-first --color=always --long --git --icons=always --grid --no-filesize --no-user --no-time --color-scale-mode=gradient --no-permissions"
      alias la="eza --group-directories-first --color=always --long --git --icons=always --grid --no-filesize --no-user --no-time --no-permissions --all"
      alias ll="eza --group-directories-first --color=always --long --git --icons=always"
      alias lla="eza --group-directories-first --color=always --long --git --icons=always --all"
      alias lld="eza --group-directories-first --color=always --long --git --icons=always --list-dirs"
      alias tree="eza --group-directories-first --color=always --long --tree --icons=always --git"
      alias treeall="eza --group-directories-first --color=always --long --tree --icons=always --git --all"

      # Enhanced grep and find
      alias grep='rg'
      alias find='fd'

      # Utility aliases
      alias vim='nvim'
      alias vi='nvim'
      alias top='htop'
      alias cat='bat --style=plain'

      # Git aliases
      alias gs='git status'
      alias ga='git add'
      alias gc='git commit'
      alias gp='git push'
      alias gl='git pull'
      alias gd='git diff'
      alias gco='git checkout'
      alias gb='git branch'

      # Docker aliases
      alias d='docker'
      alias dc='docker-compose'
      alias dps='docker ps'
      alias di='docker images'

      # Python/UV aliases
      alias py='python'
      alias pip='uv pip'
      alias uvx='uv tool run'

      # ---- Command History Configuration ----
      HISTFILE=$HOME/.zhistory
      SAVEHIST=1000
      HISTSIZE=999

      # History settings (matching your config)
      setopt share_history           # Share history between all sessions
      setopt hist_expire_dups_first  # Expire duplicate entries first
      setopt hist_ignore_dups        # Ignore duplicate entries
      setopt hist_verify             # Verify history substitution

      # Enable history search with arrow keys
      bindkey '^[[A' history-search-backward
      bindkey '^[[B' history-search-forward

      # ---- Zsh Options ----
      setopt AUTO_CD              # Change directory just by typing directory name
      setopt CORRECT              # Auto correct mistakes
      setopt NO_BEEP              # No beep

      # ---- Angular CLI autocompletion ----
      # Load Angular CLI autocompletion if available
      if command -v ng >/dev/null 2>&1; then
        eval "$(ng completion script 2>/dev/null || true)"
      fi

      # ---- NVM Configuration ----
      # Note: NVM managed by Homebrew, but keeping for compatibility
      export NVM_DIR="$HOME/.nvm"
      if [[ -s "/opt/homebrew/opt/nvm/nvm.sh" ]]; then
        source "/opt/homebrew/opt/nvm/nvm.sh"
      fi
    '';

    # Enable completion
    enableCompletion = true;
    enableBashCompletion = true;
  };

  # Set zsh as default shell
  environment.shells = [ pkgs.zsh ];

  # Environment variables matching your setup
  environment.variables = {
    # FZF configuration (matching your exact settings)
    FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :500 {}'";
    FZF_ALT_C_OPTS = "--preview 'eza --tree --color=always {} | head -200'";
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";

    # Bat configuration
    BAT_THEME = "TwoDark";

    # Less configuration
    LESS = "-R --use-color -Dd+r -Du+b";

    # Editor configuration
    EDITOR = "nvim";
    VISUAL = "nvim";

    # Development environment variables
    DOCKER_DEFAULT_PLATFORM = "linux/amd64";  # For Apple Silicon compatibility

    # EZA configuration
    EZA_CONFIG_DIR = "$HOME/.config/eza";

    # PNPM configuration
    PNPM_HOME = "$HOME/Library/pnpm";

    # NVM configuration
    NVM_DIR = "$HOME/.nvm";
  };

  # Additional shell functions matching your FZF configuration
  programs.zsh.initExtra = ''
    # ---- FZF Functions (matching your config) ----
    _fzf_comprun() {
      local command=$1
      shift
      case "$command" in
        cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
        export|unset) fzf --preview "eval 'echo \${}'" "$@" ;;
        ssh)          fzf --preview 'dig {}' "$@" ;;
        *)            fzf --preview "bat -n --color=always --line-range :500 {}" "$@" ;;
      esac
    }
  '';
}