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

    matchBlocks = {
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
