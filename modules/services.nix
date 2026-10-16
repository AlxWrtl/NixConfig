{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Single source of truth for power settings (overrides power.sleep)
  displaySleepMinutes = 25;
  systemSleepMinutes = 45;
  maxOpenFiles = 65536;
  maxFilesPerProc = 32768;
  mkMaintenanceDaemon =
    {
      name,
      script,
      runAtLoad ? false,
    }:
    {
      serviceConfig = {
        ProgramArguments = [
          "/bin/sh"
          "-c"
          script
        ];
        StandardOutPath = "/var/log/${name}.log";
        StandardErrorPath = "/var/log/${name}-error.log";
        RunAtLoad = runAtLoad;
        UserName = "root";
      };
    };
  nixFlakeUpdateAgent = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          FLAKE_DIR="$HOME/.config/nix-darwin"
          if [ ! -d "$FLAKE_DIR" ]; then
            echo "Flake dir not found: $FLAKE_DIR" >> ~/.cache/nix-flake-update-error.log
            exit 1
          fi
          cd "$FLAKE_DIR" && \
          ${pkgs.nix}/bin/nix flake update && \
          echo "Flake updated (no auto-rebuild): $(date)" >> ~/.cache/nix-flake-update.log && \
          echo "⚠️  Run 'rebuild' to apply changes"
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 14;
          Minute = 0;
        }
      ];
      StandardOutPath = "${
        config.users.users.${config.system.primaryUser}.home
      }/.cache/nix-flake-update.log";
      StandardErrorPath = "${
        config.users.users.${config.system.primaryUser}.home
      }/.cache/nix-flake-update-error.log";
      RunAtLoad = false;
    };
  };
  powerOptimizationDaemon = mkMaintenanceDaemon {
    name = "power-optimization";
    runAtLoad = true;
    script = ''
      # Sleep timings
      /usr/bin/pmset -a displaysleep ${toString displaySleepMinutes}
      /usr/bin/pmset -a sleep ${toString systemSleepMinutes}

      # Sleep behavior (no deep sleep)
      /usr/bin/pmset -a hibernatemode 3
      /usr/bin/pmset -a standby 0
      /usr/bin/pmset -a autopoweroff 0
      /usr/bin/pmset -a standbydelay 0
      /usr/bin/pmset -a autopoweroffdelay 0
      /usr/bin/pmset -a destroyfvkeyonstandby 0

      # Power saving
      /usr/bin/pmset -a powernap 0
      /usr/bin/pmset -a ttyskeepawake 0
      /usr/bin/pmset -a reducebright 1
      /usr/bin/pmset -a halfdim 1

      echo "Power optimization applied: $(date)" >> /var/log/power-optimization.log
    '';
  };
  networkOptimizationDaemon = mkMaintenanceDaemon {
    name = "network-optimization";
    runAtLoad = true;
    script = ''
      # Open-file limits (dev file watchers)
      /usr/sbin/sysctl -w kern.maxfiles=${toString maxOpenFiles}
      /usr/sbin/sysctl -w kern.maxfilesperproc=${toString maxFilesPerProc}

      echo "Network optimization applied: $(date)" >> /var/log/network-optimization.log
    '';
  };
in

{

  launchd = {
    user.agents = {
      nix-flake-update = nixFlakeUpdateAgent;
    };
    daemons = {
      power-optimization = powerOptimizationDaemon;
      network-optimization = networkOptimizationDaemon;
    };
  };
}
