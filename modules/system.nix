{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{

  nix = {
    enable = true;
    package = pkgs.nixVersions.latest;

    settings = {
      # Modern features
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
        "fetch-closure"
      ];

      # Security (CVE-2025-46415, CVE-2025-46416, etc.)
      trusted-users = [
        "root"
        "@admin"
      ];
      allowed-users = [
        "@wheel"
        "alx"
      ];
      sandbox = true;
      require-sigs = true;

      # Performance
      max-jobs = "auto";
      cores = 0;
      builders-use-substitutes = true;

      # Binary cache
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
      ];

      extra-trusted-substituters = [ ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      # Network
      fallback = false;
      connect-timeout = 10;
      http-connections = 25;
      download-attempts = 3;
      log-lines = 25;

      # Store management
      min-free = 1000000000; # 1GB
      max-free = 5000000000; # 5GB
      tarball-ttl = 3600 * 24 * 7; # 7 days
      eval-cache = true;
    };

    # Automatic maintenance
    optimise.automatic = true;
    gc = {
      automatic = true;
      interval = {
        Weekday = 7;
        Hour = 10;
        Minute = 0;
      };
      options = "--delete-older-than 60d --max-freed 10G";
    };
  };

  nixpkgs.config = {
    allowUnfree = lib.mkDefault true;
    allowBroken = false;
    allowInsecure = false;
    permittedInsecurePackages = [ ];
  };

  environment.variables = {
    # Editors
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";

    # XDG Base Directory
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_CACHE_HOME = "$HOME/.cache";
    XDG_DATA_HOME = "$HOME/.local/share";

    # Security tools
    SOPS_AGE_KEY_FILE = "/Users/alx/.config/age/keys.txt";
    SECURITY_LOG_DIR = "/var/log/security";
    GNUPGHOME = "$HOME/.config/gnupg";
    AGE_DIR = "$HOME/.config/age";
  };

  system.primaryUser = "alx";

  security.pam.services.sudo_local.touchIdAuth = true;

  environment.systemPackages = [
    pkgs.vulnix
    pkgs.age
    pkgs.sops
    pkgs.nmap
    pkgs.htop
  ];

  environment.shellAliases = {
    vulnscan = "vulnix --system /var/run/current-system";
    vulnscan-json = "vulnix --system /var/run/current-system --json /tmp/vulnix-output.json";
    security-logs = "tail -f /var/log/security/*.log";
    check-perms = "ls -la /nix/store | head -20";
    check-security = "cat /var/log/security/vulnix-scan.log | tail -10";
  };

  # Uncomment when secrets are configured:
  # sops = {
  #   defaultSopsFile = ./secrets/secrets.yaml;
  #   age = {
  #     keyFile = "/Users/alx/.config/age/keys.txt";
  #     generateKey = false;
  #   };
  #   secrets = {
  #     github_token = {
  #       owner = "alx";
  #       mode = "0400";
  #     };
  #   };
  # };

}
