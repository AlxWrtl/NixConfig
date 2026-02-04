{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Shell environment: Zsh + Starship + Direnv + Aliases
  # Consolidated from: shell.nix, starship.nix, direnv.nix, config.nix

  # ============================================================================
  # ZSH CONFIGURATION
  # ============================================================================

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # ============================================================================
  # DIRENV - PER-DIRECTORY ENVIRONMENTS
  # ============================================================================

  programs.direnv = {
    enable = true;
    silent = false;
    nix-direnv.enable = true;
  };

  # ============================================================================
  # STARSHIP PROMPT
  # ============================================================================

  environment.etc."starship.toml".source = (pkgs.formats.toml { }).generate "starship-config" {
    add_newline = true;
    command_timeout = 500;
    scan_timeout = 30;

    format = "$directory$git_branch$git_status$git_state$line_break$character";
    right_format = "$status$cmd_duration$jobs\${custom.python_smart}$nodejs$java$nix_shell";

    # Directory
    directory = {
      style = "#88ccc5";
      format = "[$path]($style)[$read_only]($read_only_style)";
      read_only = "🔒";
      read_only_style = "red";
      truncation_length = 0;
      truncate_to_repo = false;
      truncation_symbol = "…/";
      home_symbol = "~";
      use_logical_path = true;
      fish_style_pwd_dir_length = 0;
    };

    # Git
    git_branch = {
      symbol = " ";
      style = "#f5bde6";
      format = " [$symbol$branch(:$remote_branch)]($style)";
      truncation_length = 32;
      truncation_symbol = "…";
      only_attached = false;
    };

    git_status = {
      style = "#f5bde6";
      format = "[.$all_status$ahead_behind]($style)";
      conflicted = "~\${count}";
      ahead = "⇡\${count}";
      behind = "⇣\${count}";
      diverged = "⇡\${ahead_count}⇣\${behind_count}";
      up_to_date = "";
      untracked = "?\${count}";
      stashed = "*\${count}";
      modified = "!\${count}";
      staged = "+\${count}";
      renamed = "»\${count}";
      deleted = "✘\${count}";
    };

    git_state = {
      style = "#ff0000";
      format = "[\($state( $progress_current of $progress_total)\)]($style)";
    };

    # Prompt
    line_break.disabled = false;

    character = {
      success_symbol = "[➜](bold #d75f87)";
      error_symbol = "[➜](bold #ff0000)";
      vimcmd_symbol = "[❮](bold #d75f87)";
      vimcmd_replace_one_symbol = "[▶](bold #d75f87)";
      vimcmd_replace_symbol = "[▶](bold #d75f87)";
      vimcmd_visual_symbol = "[V](bold #d75f87)";
    };

    # Status & Performance
    status = {
      format = "[$symbol$status]($style)";
      style = "#d70000";
      symbol = "✘";
      success_symbol = "";
      not_executable_symbol = "🚫";
      not_found_symbol = "🔍";
      sigint_symbol = "🧱";
      signal_symbol = "⚡";
      disabled = false;
      map_symbol = true;
    };

    cmd_duration = {
      format = "[$duration]($style)";
      style = "#d75f5f";
      min_time = 5000;
      show_milliseconds = false;
    };

    jobs = {
      format = "[$symbol$number]($style)";
      style = "#00af00";
      symbol = "✦";
      number_threshold = 1;
      symbol_threshold = 1;
    };

    # Language Detection
    nodejs = {
      format = "[$symbol$version]($style)";
      symbol = " ";
      style = "#5faf00";
      detect_extensions = [
        "js"
        "mjs"
        "cjs"
        "ts"
        "mts"
        "cts"
      ];
      detect_files = [ ];
      detect_folders = [ ];
    };

    java = {
      format = "[$symbol$version]($style)";
      symbol = " ";
      style = "#008700";
      detect_extensions = [
        "java"
        "class"
        "jar"
        "gradle"
        "clj"
        "cljc"
      ];
      detect_files = [
        "pom.xml"
        "build.gradle.kts"
        "build.sbt"
        ".java-version"
        "deps.edn"
        "project.clj"
        "build.boot"
      ];
    };

    nix_shell = {
      format = "[$symbol$state( $name)]($style)";
      symbol = "󱄅 ";
      style = "#87d7af";
      impure_msg = "[impure]";
      pure_msg = "[pure]";
      unknown_msg = "[unknown]";
    };

    python.disabled = true;

    custom.python_smart = {
      disabled = false;
      command = ''
        if [ -n "$VIRTUAL_ENV" ]; then
            project_dir=$(dirname "$VIRTUAL_ENV")
            current_dir=$(pwd)
            case "$current_dir" in
                "$project_dir"*) python --version | cut -d' ' -f2 ;;
            esac
        fi
      '';
      when = "test -n \"$VIRTUAL_ENV\"";
      ignore_timeout = true;
      format = "[ $output]($style)";
      style = "#00afaf";
    };

    # Disabled modules (performance)
    package.disabled = true;
    conda.disabled = true;
    memory_usage.disabled = true;
    time.disabled = true;
    username.disabled = true;
    hostname.disabled = true;
    shlvl.disabled = true;
    env_var.disabled = true;
    aws.disabled = true;
    azure.disabled = true;
    gcloud.disabled = true;
    kubernetes.disabled = true;
    terraform.disabled = true;
    docker_context.disabled = true;
    direnv.disabled = true;
    lua.disabled = true;
    perl.disabled = true;
    php.disabled = true;
    haskell.disabled = true;
    dart.disabled = true;
    kotlin.disabled = true;
    scala.disabled = true;
    dotnet.disabled = true;
    golang.disabled = true;
    rust.disabled = true;
    ruby.disabled = true;
  };

  # ============================================================================
  # ENVIRONMENT VARIABLES
  # ============================================================================

  environment.variables = {
    # Starship
    STARSHIP_CONFIG = "/etc/starship.toml";

    # Direnv
    DIRENV_LOG_FORMAT = "";

    # FZF Configuration
    FZF_CTRL_R_OPTS = "--no-preview";
    FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :500 {}'";
    FZF_ALT_C_OPTS = "--preview 'eza --tree --color=always {} | head -200'";
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --ansi";

    # Tool Appearance
    BAT_THEME = "TwoDark";
    LESS = "-R --use-color";
    DOCKER_DEFAULT_PLATFORM = "linux/amd64";

    # Tool Directories
    EZA_CONFIG_DIR = "$HOME/.config/eza";
    PNPM_HOME = "$HOME/Library/pnpm";

    # Homebrew
    HOMEBREW_NO_ANALYTICS = "1";
    HOMEBREW_NO_INSECURE_REDIRECT = "1";
    HOMEBREW_PREFIX = "/opt/homebrew";
  };

  # ============================================================================
  # SHELL ALIASES
  # ============================================================================

  environment.shellAliases = {
    # Git shortcuts
    g = "git";
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gp = "git push";
    gl = "git pull";
    gd = "git diff";
    gco = "git checkout";
    gb = "git branch";

    # Enhanced CLI tools
    lt = "eza --tree";
    cat = "bat";
    find = "fd";
    grep = "rg";
  };
}
