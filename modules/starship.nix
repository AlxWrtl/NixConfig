{ config, pkgs, lib, ... }:

{
  environment.etc."starship.toml".source = (pkgs.formats.toml {}).generate "starship-config" {
    add_newline = true;
    command_timeout = 3000;  # Match original timeout
    scan_timeout = 30;

    # Main format (left side)
    format = "$directory$git_branch$git_status$git_state$line_break$character";

    # Right prompt with environment indicators (like original)
    right_format = "$status$cmd_duration$jobs\${custom.python_env}$nodejs$java$nix_shell";

    directory = {
      style = "#88ccc5";  # User's preferred color
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

    git_branch = {
      symbol = " ";  # Cat icon (actual character)
      style = "#f5bde6";  # User's preferred color
      format = " [$symbol$branch(:$remote_branch)]($style)";
      truncation_length = 32;
      truncation_symbol = "…";
      only_attached = false;
    };

    git_status = {
      style = "#f5bde6";  # Same as git_branch
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

    line_break = {
      disabled = false;
    };

    character = {
      success_symbol = "[➜](bold #d75f87)";
      error_symbol = "[➜](bold #ff0000)";
      vimcmd_symbol = "[❮](bold #d75f87)";
      vimcmd_replace_one_symbol = "[▶](bold #d75f87)";
      vimcmd_replace_symbol = "[▶](bold #d75f87)";
      vimcmd_visual_symbol = "[V](bold #d75f87)";
    };

    # Status indicator - only show on errors
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

    # Command execution time
    cmd_duration = {
      format = "[$duration]($style)";
      style = "#d75f5f";
      min_time = 3000;
      show_milliseconds = false;
    };

    # Background jobs
    jobs = {
      format = "[$symbol$number]($style)";
      style = "#00af00";
      symbol = "✦";
      number_threshold = 1;
      symbol_threshold = 1;
    };

    # Custom Python environment module
    custom = {
      python_env = {
        command = ''
          # Only show if we're in a directory with .venv AND python points to it
          if [ -f ".venv/bin/python" ]; then
              current_python=$(which python 2>/dev/null)
              local_python="$(pwd)/.venv/bin/python"
              if [ "$current_python" = "$local_python" ]; then
                  version=$(.venv/bin/python --version 2>&1 | cut -d' ' -f2)
                  echo "v$version"
              fi
          elif [ -n "$VIRTUAL_ENV" ] && [ "$(basename "$VIRTUAL_ENV")" != ".venv" ]; then
              # Show for named virtual environments (not local .venv)
              version=$(python --version 2>&1 | cut -d' ' -f2)
              echo "v$version"
          elif [ -n "$CONDA_DEFAULT_ENV" ]; then
              version=$(python --version 2>&1 | cut -d' ' -f2)
              echo "v$version"
          fi
        '';
        when = ''[ -f ".venv/bin/python" ] && [ "$(which python 2>/dev/null)" = "$(pwd)/.venv/bin/python" ] || ([ -n "$VIRTUAL_ENV" ] && [ "$(basename "$VIRTUAL_ENV")" != ".venv" ]) || [ -n "$CONDA_DEFAULT_ENV" ]'';
        format = "[ $output]($style)";
        style = "#00afaf";
      };
    };

    # Node.js - only show when actively working with JS/TS files
    nodejs = {
      format = "[$symbol$version]($style)";
      symbol = " ";
      style = "#5faf00";
      detect_extensions = ["js" "mjs" "cjs" "ts" "mts" "cts"];
      detect_files = [];
      detect_folders = [];
    };

    # Java
    java = {
      format = "[$symbol$version]($style)";
      symbol = " ";
      style = "#008700";
      detect_extensions = ["java" "class" "jar" "gradle" "clj" "cljc"];
      detect_files = ["pom.xml" "build.gradle.kts" "build.sbt" ".java-version" "deps.edn" "project.clj" "build.boot"];
    };

    # Nix shell
    nix_shell = {
      format = "[$symbol$state( $name)]($style)";
      symbol = "󱄅 ";
      style = "#87d7af";
      impure_msg = "[impure]";
      pure_msg = "[pure]";
      unknown_msg = "[unknown]";
    };

    # Python - disabled in favor of custom UV module
    python = {
      disabled = true;
    };

    # Disable unnecessary modules
    package = {
      disabled = true;
    };

    conda = {
      disabled = true;
    };

    memory_usage = {
      disabled = true;
    };

    time = {
      disabled = true;
    };

    username = {
      disabled = true;
    };

    hostname = {
      disabled = true;
    };

    shlvl = {
      disabled = true;
    };

    env_var = {
      disabled = true;
    };

    aws = {
      disabled = true;
    };

    azure = {
      disabled = true;
    };

    gcloud = {
      disabled = true;
    };

    kubernetes = {
      disabled = true;
    };

    terraform = {
      disabled = true;
    };

    docker_context = {
      disabled = true;
    };

    direnv = {
      disabled = true;
    };

    # Disable other language modules that might conflict
    lua = {
      disabled = true;
    };

    perl = {
      disabled = true;
    };

    php = {
      disabled = true;
    };

    haskell = {
      disabled = true;
    };

    dart = {
      disabled = true;
    };

    kotlin = {
      disabled = true;
    };

    scala = {
      disabled = true;
    };

    dotnet = {
      disabled = true;
    };

    golang = {
      disabled = true;
    };

    rust = {
      disabled = true;
    };

    ruby = {
      disabled = true;
    };
  };

  environment.variables = {
    STARSHIP_CONFIG = "/etc/starship.toml";
  };
}