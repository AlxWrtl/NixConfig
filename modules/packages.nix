{
  config,
  pkgs,
  lib,
  ...
}:

{
  config = lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.starship
        pkgs.zsh-autosuggestions
        pkgs.zsh-fast-syntax-highlighting
        pkgs.eza
        pkgs.bat
        pkgs.fd
        pkgs.ripgrep
        pkgs.tree
        pkgs.zoxide
        pkgs.fzf
        pkgs.atuin
        pkgs.rsync
        pkgs.btop
        pkgs.fastfetch
        pkgs.git
        pkgs.git-lfs
        pkgs.gh
        pkgs.nixd
        pkgs.nil
        pkgs.nixfmt
        pkgs.nix-tree
        pkgs.nix-index
        pkgs.vulnix
        pkgs.nodejs_20
        pkgs.pnpm
        pkgs.bun
        pkgs.nodePackages."@angular/cli"
        pkgs.nodePackages.typescript
        pkgs.nodePackages.eslint
        pkgs.nodePackages.prettier
        pkgs.sqlite
        pkgs.postgresql
        pkgs.curl
        pkgs.wget
        pkgs.httpie
        pkgs.jq
        pkgs.yq
        pkgs.redis
        pkgs.age
        pkgs.sops
        pkgs.libwebp
      ];

      environment.variables = {
        NODE_ENV = "development";
      };

      environment.shellAliases = {
        # Python
        serve = "python3 -m http.server";
        py = "python3";
        ipy = "ipython";

        # Nix
        nix-shell = "nix-shell --run zsh";
        rebuild = "sudo darwin-rebuild switch --flake .";

        # Docker
        dc = "docker-compose";
        dcu = "docker-compose up";
        dcd = "docker-compose down";
      };

    }

    {
      environment.systemPackages = [
        pkgs.python3
        pkgs.uv
        pkgs.ruff
      ];
    }
  ];
}
