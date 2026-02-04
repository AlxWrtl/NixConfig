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
    ./claude-code.nix
  ];

  home.username = "alx";
  home.homeDirectory = "/Users/alx";
  home.stateVersion = "24.11";

  home.sessionVariables.CLAUDE_CONFIG_DIR = "$HOME/.claude";

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
