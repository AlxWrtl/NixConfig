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

    settings = {
      "*" = {
        UserKnownHostsFile = "~/.ssh/known_hosts ~/.ssh/known_hosts_github";
      };

      "github.com" = {
        IdentityFile = "~/.ssh/id_ed25519";
        IdentitiesOnly = true;
      };

      ubuntu = {
        HostName = secrets.ssh.ubuntu.hostname;
        User = secrets.ssh.ubuntu.user;
        Port = secrets.ssh.ubuntu.port;
        ServerAliveInterval = 60;
        ServerAliveCountMax = 10;
        TCPKeepAlive = true;
      };
    };
  };
}
