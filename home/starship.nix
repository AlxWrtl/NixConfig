{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      command_timeout = 500;
      scan_timeout = 30;

      format = "$directory$git_branch$git_status$git_state$line_break$character";
      right_format = "$status$cmd_duration$jobs\${custom.python_smart}$nodejs$java$nix_shell";

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

      line_break.disabled = false;

      character = {
        success_symbol = "[➜](bold #d75f87)";
        error_symbol = "[➜](bold #ff0000)";
        vimcmd_symbol = "[❮](bold #d75f87)";
        vimcmd_replace_one_symbol = "[▶](bold #d75f87)";
        vimcmd_replace_symbol = "[▶](bold #d75f87)";
        vimcmd_visual_symbol = "[V](bold #d75f87)";
      };

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
  };
}
