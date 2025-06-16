{ config, pkgs, lib, inputs, ... }:

{
  # Shell configuration (Zsh with Powerlevel10k)

  programs.zsh = {
    enable = true;

    # Shell prompt and theme configuration
    promptInit = ''
      # Powerlevel10k Theme
      if [[ -r "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme" ]]; then
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      fi

      # Zsh Syntax Highlighting
      if [[ -r "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
        source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      fi

      # Zsh Autosuggestions
      if [[ -r "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      fi

      # Zoxide (smart cd)
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init zsh)"
      fi

      # Atuin (shell history)
      if command -v atuin >/dev/null 2>&1; then
        eval "$(atuin init zsh --disable-up-arrow)"
      fi

      # FZF key bindings
      if command -v fzf >/dev/null 2>&1; then
        eval "$(fzf --zsh)"
      fi
    '';

    # Shell options
    shellInit = ''
      # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
      # Initialization code that may require console input (password prompts, [y/n]
      # confirmations, etc.) must go above this block; everything else may go below.
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

      # Zsh options
      setopt AUTO_CD              # Change directory just by typing directory name
      setopt HIST_VERIFY          # Show command with history expansion to user before running it
      setopt SHARE_HISTORY        # Share command history data
      setopt HIST_IGNORE_SPACE    # Don't save commands that start with space
      setopt HIST_IGNORE_DUPS     # Don't save duplicates
      setopt CORRECT              # Auto correct mistakes
      setopt NO_BEEP              # No beep

      # Modern replacements aliases
      alias ls='eza --color=auto --group-directories-first'
      alias ll='eza -la --color=auto --group-directories-first'
      alias lt='eza --tree --color=auto'
      alias cat='bat --style=plain'
      alias grep='rg'
      alias find='fd'
      alias cd='z'

      # Utility aliases
      alias vim='nvim'
      alias vi='nvim'
      alias top='htop'

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
    '';

    # Enable completion
    enableCompletion = true;
    enableBashCompletion = true;
  };

  # Set zsh as default shell
  environment.shells = [ pkgs.zsh ];

  # Environment variables for shell
  environment.variables = {
    # Zsh configuration
    ZDOTDIR = "$HOME/.config/zsh";

    # FZF configuration
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
    FZF_CTRL_T_COMMAND = "$FZF_DEFAULT_COMMAND";
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border";

    # Bat configuration
    BAT_THEME = "TwoDark";

    # Less configuration
    LESS = "-R --use-color -Dd+r -Du+b";

    # Editor configuration
    EDITOR = "nvim";
    VISUAL = "nvim";

    # Development environment variables
    DOCKER_DEFAULT_PLATFORM = "linux/amd64";  # For compatibility with Apple Silicon
  };
}