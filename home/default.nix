{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./zsh.nix
    ./git.nix
    ./starship.nix
    ./direnv.nix
    ./claude-code.nix
  ];

  home.username = "alx";
  home.homeDirectory = "/Users/alx";
  home.stateVersion = "24.11";

  home.packages = [
    pkgs.gh-dash
    pkgs.gitleaks
    pkgs.pre-commit
    pkgs.tree
    pkgs.watch
    pkgs.tldr
  ];

  programs.home-manager.enable = true;

  xdg.enable = true;

  fonts.fontconfig.enable = true;
}
