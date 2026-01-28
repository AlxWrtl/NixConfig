{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # ============================================================================
  # AUTOMATIC FLAKE UPDATES
  # ============================================================================
  # Keep system packages and Nix version current

  launchd.user.agents.nix-flake-update = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          cd ${inputs.self} && \
          ${pkgs.nix}/bin/nix flake update && \
          echo "Flake updated automatically: $(date)" >> ~/.cache/nix-flake-update.log
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 14;
          Minute = 0;
        } # Weekly on Monday at 2:00 PM
      ];
      StandardOutPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/nix-flake-update.log";
      StandardErrorPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/nix-flake-update-error.log";
      RunAtLoad = false; # Don't run immediately on system boot
    };
  };
}
