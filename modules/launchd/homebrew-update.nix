{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # ============================================================================
  # AUTOMATIC HOMEBREW UPDATES
  # ============================================================================
  # Update Homebrew metadata 2x/week with catch-up (saves 47MB on each rebuild)

  launchd.user.agents.homebrew-update = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Check last update time (catch-up if Mac was off)
          last_update_file="$HOME/.cache/homebrew-last-update"
          current_time=$(date +%s)

          # If no last update file, create it and run update
          if [ ! -f "$last_update_file" ]; then
            /opt/homebrew/bin/brew update && \
            echo "$current_time" > "$last_update_file" && \
            echo "$(date): Homebrew updated (first run)" >> ~/.cache/homebrew-update.log
            exit 0
          fi

          # Check if last update was more than 3 days ago (catch-up threshold)
          last_update=$(cat "$last_update_file")
          time_diff=$((current_time - last_update))
          three_days=$((3 * 24 * 60 * 60))

          if [ "$time_diff" -gt "$three_days" ]; then
            /opt/homebrew/bin/brew update && \
            echo "$current_time" > "$last_update_file" && \
            echo "$(date): Homebrew updated (catch-up after $((time_diff / 86400)) days)" >> ~/.cache/homebrew-update.log
          else
            echo "$(date): Homebrew update skipped (last update $((time_diff / 86400)) days ago)" >> ~/.cache/homebrew-update.log
          fi
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 2;
          Hour = 9;
          Minute = 0;
        } # Tuesday at 9:00 AM
        {
          Weekday = 4;
          Hour = 9;
          Minute = 0;
        } # Thursday at 9:00 AM
      ];
      StandardOutPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/homebrew-update.log";
      StandardErrorPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/homebrew-update-error.log";
      RunAtLoad = true; # Run on login to catch-up missed updates
    };
  };
}
