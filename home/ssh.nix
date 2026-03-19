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
  programs.ssh = {
    enable = true;

    includes = [
      "${config.home.homeDirectory}/.colima/ssh_config"
    ];

    knownHosts = {
      github = {
        hostNames = [ "github.com" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
    };

    matchBlocks = {
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
    };
  };
}
