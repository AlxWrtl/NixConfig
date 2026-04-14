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
    ./ssh.nix
    ./starship.nix
    ./direnv.nix
    ./ghostty.nix
    ./vscode.nix
    ./claude-code.nix
    ./veille-claude.nix
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

  # Silence builtins.derivation options.json warning (home-manager #7935)
  manual.manpages.enable = false;
}
