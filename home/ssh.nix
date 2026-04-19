{
  config,
  pkgs,
  lib,
  ...
}:

let
  secrets = import ../secrets.nix;
in

{
  home.file.".ssh/known_hosts_github" = {
    text = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl\n";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    includes = [
      "${config.home.homeDirectory}/.colima/ssh_config"
    ];

    matchBlocks = {
      "*" = {
        userKnownHostsFile = "~/.ssh/known_hosts ~/.ssh/known_hosts_github";
      };

      "github.com" = {
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
      };

      rog = {
        hostname = secrets.ssh.rog.hostname;
        user = secrets.ssh.rog.user;
        port = secrets.ssh.rog.port;
        serverAliveInterval = 60;
        serverAliveCountMax = 10;
        extraOptions = {
          TCPKeepAlive = "yes";
        };
      };

      ubuntu = {
        hostname = secrets.ssh.ubuntu.hostname;
        user = secrets.ssh.ubuntu.user;
        port = secrets.ssh.ubuntu.port;
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
        serverAliveInterval = 60;
        serverAliveCountMax = 10;
        extraOptions = {
          TCPKeepAlive = "yes";
        };
      };
    };
  };
}
