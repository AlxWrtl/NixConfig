{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  systemConstants = import ../constants.nix;
  mkMaintenanceDaemon = import ../launchd-helpers.nix;
in

{
  # ============================================================================
  # SYSTEM PERFORMANCE OPTIMIZATION
  # ============================================================================

  # === Advanced Power Management ===
  # Configure optimal power settings for battery life and performance
  launchd.daemons.power-optimization = lib.mkIf config.nix-darwin.enableOptimizations (
    mkMaintenanceDaemon {
      name = "power-optimization";
      runAtLoad = true;
      script = ''
        # -- Sleep Timings --
        /usr/bin/pmset -a displaysleep ${toString systemConstants.displaySleepMinutes}
        /usr/bin/pmset -a sleep ${toString systemConstants.systemSleepMinutes}

        # -- Sleep Behavior (no deep sleep) --
        /usr/bin/pmset -a hibernatemode 3               # Normal sleep (RAM powered + safe disk copy)
        /usr/bin/pmset -a standby 0                     # Disable standby (prevents deep sleep)
        /usr/bin/pmset -a autopoweroff 0                # Disable auto power off (prevents deep sleep)
        /usr/bin/pmset -a standbydelay 0                # No standby delay
        /usr/bin/pmset -a autopoweroffdelay 0           # No auto power off delay
        /usr/bin/pmset -a destroyfvkeyonstandby 0       # Keep FileVault key in RAM (avoid forced hibernate)

        # -- Power Saving Options --
        /usr/bin/pmset -a powernap 0                    # Disable Power Nap (saves battery)
        /usr/bin/pmset -a ttyskeepawake 0               # Allow sleep even with SSH sessions
        /usr/bin/pmset -a reducebright 1                # Reduce brightness before sleep
        /usr/bin/pmset -a halfdim 1                     # Dim screen before sleep

        # -- Logging --
        echo "Power optimization applied: $(date)" >> /var/log/power-optimization.log
      '';
    }
  );

  # === Network Performance Tuning ===
  # Optimize TCP/IP stack for better network performance and throughput
  launchd.daemons.network-optimization = lib.mkIf config.nix-darwin.enableOptimizations (
    mkMaintenanceDaemon {
      name = "network-optimization";
      runAtLoad = true;
      script = ''
        # === Network performance tuning ===

        ## -- TCP Optimizations --
        /usr/sbin/sysctl -w net.inet.tcp.delayed_ack=2                  # Smart TCP ACK (moins de paquets inutiles)
        /usr/sbin/sysctl -w net.inet.tcp.sendspace=131072              # Buffer d'envoi TCP : 128KB
        /usr/sbin/sysctl -w net.inet.tcp.recvspace=131072              # Buffer de réception TCP : 128KB
        /usr/sbin/sysctl -w net.inet.tcp.slowstart_flightsize=${toString systemConstants.tcpSlowStartFlightSize}
        /usr/sbin/sysctl -w net.inet.tcp.local_slowstart_flightsize=${toString systemConstants.tcpSlowStartFlightSize}

        ## -- Sockets & Filesystem --
        /usr/sbin/sysctl -w kern.maxfiles=${toString systemConstants.maxOpenFiles}
        /usr/sbin/sysctl -w kern.maxfilesperproc=${toString systemConstants.maxFilesPerProc}
        /usr/sbin/sysctl -w kern.ipc.somaxconn=1024                   # Connexions TCP entrantes en attente

        ## -- Logging --
        echo "Network optimization applied: $(date)" >> /var/log/network-optimization.log
      '';
    }
  );
}
