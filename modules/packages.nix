{ pkgs, ... }:

{
  environment.systemPackages = [
    # Shell & prompt
    pkgs.starship
    pkgs.zsh-autosuggestions
    pkgs.zsh-fast-syntax-highlighting

    # File tools
    pkgs.eza
    pkgs.bat
    pkgs.fd
    pkgs.ripgrep
    pkgs.tree
    pkgs.zoxide
    pkgs.fzf

    # System monitoring
    pkgs.atuin
    pkgs.rsync
    pkgs.btop
    pkgs.fastfetch

    # Git
    pkgs.git
    pkgs.git-crypt
    pkgs.git-lfs
    pkgs.gh

    # Nix tooling
    pkgs.nixd
    pkgs.nil
    pkgs.nixfmt
    pkgs.nix-tree
    pkgs.nix-index
    pkgs.vulnix

    # Node.js
    pkgs.nodejs_22
    pkgs.pnpm
    pkgs.bun
    pkgs.typescript
    pkgs.eslint
    pkgs.prettier

    # Python
    pkgs.python3
    pkgs.uv
    pkgs.ruff

    # Databases
    pkgs.sqlite
    pkgs.postgresql
    pkgs.redis

    # Network & data
    pkgs.curl
    pkgs.wget
    pkgs.httpie
    pkgs.jq
    pkgs.yq

    # Security
    pkgs.age
    pkgs.sops

    # Media
    pkgs.libwebp
    pkgs.sox
  ];

  environment.shellAliases = {
    # Python
    serve = "python3 -m http.server";
    py = "python3";
    ipy = "ipython";

    # Nix
    nix-shell = "nix-shell --run zsh";
    rebuild = "sudo darwin-rebuild switch --flake .#alex-mbp";

    # Docker
    dc = "docker-compose";
    dcu = "docker-compose up";
    dcd = "docker-compose down";
  };
}
