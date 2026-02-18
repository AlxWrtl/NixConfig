{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  displaySleepMinutes = 25;
  systemSleepMinutes = 45;
  tcpSlowStartFlightSize = 16;
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
in

{

  launchd.user.agents.nix-flake-update = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          cd ${inputs.self} && \
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

  launchd.user.agents.homebrew-update = lib.mkIf config.homebrew.enable {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          last_update_file="$HOME/.cache/homebrew-last-update"
          current_time=$(date +%s)

          if [ ! -f "$last_update_file" ]; then
            /opt/homebrew/bin/brew update && \
            echo "$current_time" > "$last_update_file" && \
            echo "$(date): Homebrew updated (first run)" >> ~/.cache/homebrew-update.log
            exit 0
          fi

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
        }
        {
          Weekday = 4;
          Hour = 9;
          Minute = 0;
        }
      ];
      StandardOutPath = "${
        config.users.users.${config.system.primaryUser}.home
      }/.cache/homebrew-update.log";
      StandardErrorPath = "${
        config.users.users.${config.system.primaryUser}.home
      }/.cache/homebrew-update-error.log";
      RunAtLoad = true;
    };
  };

  launchd.daemons.power-optimization = mkMaintenanceDaemon {
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

  launchd.daemons.network-optimization = mkMaintenanceDaemon {
    name = "network-optimization";
    runAtLoad = true;
    script = ''
      # TCP optimizations
      /usr/sbin/sysctl -w net.inet.tcp.delayed_ack=2
      /usr/sbin/sysctl -w net.inet.tcp.sendspace=131072
      /usr/sbin/sysctl -w net.inet.tcp.recvspace=131072
      /usr/sbin/sysctl -w net.inet.tcp.slowstart_flightsize=${toString tcpSlowStartFlightSize}
      /usr/sbin/sysctl -w net.inet.tcp.local_slowstart_flightsize=${toString tcpSlowStartFlightSize}

      # Sockets & filesystem
      /usr/sbin/sysctl -w kern.maxfiles=${toString maxOpenFiles}
      /usr/sbin/sysctl -w kern.maxfilesperproc=${toString maxFilesPerProc}
      /usr/sbin/sysctl -w kern.ipc.somaxconn=1024

      echo "Network optimization applied: $(date)" >> /var/log/network-optimization.log
    '';
  };
}
