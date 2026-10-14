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
      # rustup only: Firefox `mach bootstrap` drives its own toolchains through it.
      # No nixpkgs cargo/rustc beside it (binary clash).
      pkgs.rustup
    ];

    sessionPath = [
      "$HOME/.cargo/bin"
    ];
  };

  programs.home-manager.enable = true;

  xdg.enable = true;

  fonts.fontconfig.enable = true;

  # Silence builtins.derivation options.json warning (home-manager #7935)
  manual.manpages.enable = false;
}
