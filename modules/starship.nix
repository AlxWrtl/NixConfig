{ config, pkgs, lib, ... }:

{
  # Starship shell prompt configuration

  # ============================================================================
  # STARSHIP CONFIGURATION FILE GENERATION
  # ============================================================================

  environment.etc."starship.toml".source = (pkgs.formats.toml {}).generate "starship-config" {

    # === Global Performance Settings ===
    add_newline = true;                       # Add blank line before prompt
    command_timeout = 100;                   # Increased timeout to prevent warnings (ms)
    scan_timeout = 1;                         # Minimal directory scanning for fast startup (ms)

    # === Prompt Layout Configuration ===
    # Left side: directory, git status, and input
    format = "$directory$git_branch$git_status$git_state$line_break$character";

    # Right side: execution status and development environment context
    right_format = "$status$cmd_duration$jobs\${custom.python_smart}$nodejs$java$nix_shell";

    # ============================================================================
    # DIRECTORY DISPLAY
    # ============================================================================

    directory = {
      style = "#88ccc5";                      # Cyan color for directory path
      format = "[$path]($style)[$read_only]($read_only_style)";
      read_only = "🔒";                       # Lock icon for read-only directories
      read_only_style = "red";                # Red color for read-only indicator
      truncation_length = 0;                  # No path truncation
      truncate_to_repo = false;               # Show full path even in git repos
      truncation_symbol = "…/";               # Symbol for truncated paths
      home_symbol = "~";                      # Home directory symbol
      use_logical_path = true;                # Use logical path (follow symlinks)
      fish_style_pwd_dir_length = 0;          # Don't abbreviate directory names
    };

    # ============================================================================
    # GIT INTEGRATION
    # ============================================================================

    git_branch = {
      symbol = " ";                          # Cat icon for git branch
      style = "#f5bde6";                      # Pink color for git branch
      format = " [$symbol$branch(:$remote_branch)]($style)";
      truncation_length = 32;                 # Truncate long branch names
      truncation_symbol = "…";                # Symbol for truncated branch names
      only_attached = false;                  # Show branch even in detached HEAD
    };

    git_status = {
      style = "#f5bde6";                      # Match git_branch color
      format = "[.$all_status$ahead_behind]($style)";

      # === Git Status Symbols ===
      conflicted = "~\${count}";              # Merge conflicts
      ahead = "⇡\${count}";                   # Commits ahead of remote
      behind = "⇣\${count}";                  # Commits behind remote
      diverged = "⇡\${ahead_count}⇣\${behind_count}"; # Diverged from remote
      up_to_date = "";                        # No status when up to date
      untracked = "?\${count}";               # Untracked files
      stashed = "*\${count}";                 # Stashed changes
      modified = "!\${count}";                # Modified files
      staged = "+\${count}";                  # Staged changes
      renamed = "»\${count}";                 # Renamed files
      deleted = "✘\${count}";                 # Deleted files
    };

    git_state = {
      style = "#ff0000";                      # Red color for git operations
      format = "[\($state( $progress_current of $progress_total)\)]($style)";
    };

    # ============================================================================
    # PROMPT CHARACTER AND LINE BREAKS
    # ============================================================================

    line_break = {
      disabled = false;                       # Enable line break between info and prompt
    };

    character = {
      success_symbol = "[➜](bold #d75f87)";   # Arrow for successful commands
      error_symbol = "[➜](bold #ff0000)";     # Red arrow for failed commands
      vimcmd_symbol = "[❮](bold #d75f87)";    # Vim command mode indicator
      vimcmd_replace_one_symbol = "[▶](bold #d75f87)"; # Vim replace mode
      vimcmd_replace_symbol = "[▶](bold #d75f87)";     # Vim replace mode
      vimcmd_visual_symbol = "[V](bold #d75f87)";      # Vim visual mode
    };

    # ============================================================================
    # EXECUTION STATUS AND PERFORMANCE
    # ============================================================================

    status = {
      format = "[$symbol$status]($style)";    # Show exit status on errors
      style = "#d70000";                      # Red color for errors
      symbol = "✘";                           # Cross symbol for errors
      success_symbol = "";                    # No symbol for successful commands
      not_executable_symbol = "🚫";           # Not executable indicator
      not_found_symbol = "🔍";                # Command not found indicator
      sigint_symbol = "🧱";                   # SIGINT (Ctrl+C) indicator
      signal_symbol = "⚡";                   # Other signal indicator
      disabled = false;                       # Enable status display
      map_symbol = true;                      # Map signals to symbols
    };

    cmd_duration = {
      format = "[$duration]($style)";         # Show command execution time
      style = "#d75f5f";                      # Red color for duration
      min_time = 5000;                        # Only show for commands taking >5s
      show_milliseconds = false;              # Show in seconds, not milliseconds
    };

    jobs = {
      format = "[$symbol$number]($style)";    # Show background jobs
      style = "#00af00";                      # Green color for jobs
      symbol = "✦";                           # Star symbol for jobs
      number_threshold = 1;                   # Show number when >1 job
      symbol_threshold = 1;                   # Show symbol when ≥1 job
    };

    # ============================================================================
    # DEVELOPMENT ENVIRONMENT DETECTION
    # ============================================================================

    # === Node.js Environment ===
    nodejs = {
      format = "[$symbol$version]($style)";   # Show Node.js version
      symbol = " ";                          # Node.js icon
      style = "#5faf00";                      # Green color for Node.js
      detect_extensions = ["js" "mjs" "cjs" "ts" "mts" "cts"]; # File extensions
      detect_files = [];                      # Don't detect by config files
      detect_folders = [];                    # Don't detect by folder presence
    };

    # === Java Environment ===
    java = {
      format = "[$symbol$version]($style)";   # Show Java version
      symbol = " ";                          # Java icon
      style = "#008700";                      # Dark green for Java
      detect_extensions = ["java" "class" "jar" "gradle" "clj" "cljc"];
      detect_files = ["pom.xml" "build.gradle.kts" "build.sbt" ".java-version"
                     "deps.edn" "project.clj" "build.boot"];
    };

    # === Nix Development Environment ===
    nix_shell = {
      format = "[$symbol$state( $name)]($style)"; # Show nix-shell status
      symbol = "󱄅 ";                           # Nix snowflake icon
      style = "#87d7af";                      # Light blue for Nix
      impure_msg = "[impure]";                # Impure shell indicator
      pure_msg = "[pure]";                    # Pure shell indicator
      unknown_msg = "[unknown]";              # Unknown shell type
    };

    # ============================================================================
    # CUSTOM PYTHON ENVIRONMENT DETECTION
    # ============================================================================

    # === Disable Built-in Python Module ===
    python = {
      disabled = true;                        # Use custom implementation instead
    };

    # === Smart Python Environment Detection ===
    custom = {
      python_smart = {
        disabled = false;
        # Show venv only when in project directory or subdirectories
        command = ''
          if [ -n "$VIRTUAL_ENV" ]; then
              project_dir=$(dirname "$VIRTUAL_ENV")
              current_dir=$(pwd)
              # Check if current directory is the project directory or a subdirectory
              case "$current_dir" in
                  "$project_dir"*) python --version | cut -d' ' -f2 ;;
              esac
          fi
        '';
        when = "test -n \"$VIRTUAL_ENV\"";
        format = "[ $output]($style)";         # Format with Python icon
        style = "#00afaf";                     # Cyan color for Python
      };
    };

    # ============================================================================
    # DISABLED MODULES (PERFORMANCE OPTIMIZATION)
    # ============================================================================

    # === System Information (Disabled for Performance) ===
    package = { disabled = true; };           # Package version detection
    conda = { disabled = true; };             # Conda environment
    memory_usage = { disabled = true; };      # Memory usage display
    time = { disabled = true; };              # Current time display
    username = { disabled = true; };          # Username display
    hostname = { disabled = true; };          # Hostname display
    shlvl = { disabled = true; };             # Shell level indicator
    env_var = { disabled = true; };           # Environment variable display

    # === Cloud & Infrastructure (Disabled) ===
    aws = { disabled = true; };               # AWS profile
    azure = { disabled = true; };             # Azure subscription
    gcloud = { disabled = true; };            # Google Cloud project
    kubernetes = { disabled = true; };        # Kubernetes context
    terraform = { disabled = true; };         # Terraform workspace
    docker_context = { disabled = true; };    # Docker context
    direnv = { disabled = true; };            # Direnv status

    # === Programming Languages (Disabled for Performance) ===
    lua = { disabled = true; };               # Lua version
    perl = { disabled = true; };              # Perl version
    php = { disabled = true; };               # PHP version
    haskell = { disabled = true; };           # Haskell version
    dart = { disabled = true; };              # Dart version
    kotlin = { disabled = true; };            # Kotlin version
    scala = { disabled = true; };             # Scala version
    dotnet = { disabled = true; };            # .NET version
    golang = { disabled = true; };            # Go version
    rust = { disabled = true; };              # Rust version
    ruby = { disabled = true; };              # Ruby version
  };

  # ============================================================================
  # STARSHIP ENVIRONMENT CONFIGURATION
  # ============================================================================

  environment.variables = {
    STARSHIP_CONFIG = "/etc/starship.toml";   # Point to system-wide config
  };

}