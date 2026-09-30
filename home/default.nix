{
  pkgs,
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
    ./codex.nix
  ];

  home = {
    username = "alx";
    homeDirectory = "/Users/alx";
    stateVersion = "24.11";

    packages = [
      pkgs.gh-dash
      pkgs.gitleaks
      pkgs.pre-commit
      pkgs.watch
      pkgs.tldr
    ];

    sessionPath = [
      "$HOME/.npm-global/bin"
    ];
  };

  programs.home-manager.enable = true;

  xdg.enable = true;

  fonts.fontconfig.enable = true;

  # Silence builtins.derivation options.json warning (home-manager #7935)
  manual.manpages.enable = false;
}
