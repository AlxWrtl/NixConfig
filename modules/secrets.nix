{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ============================================================================
  # SOPS SECRETS MANAGEMENT
  # ============================================================================
  # Secure secrets storage with age encryption
  # Documentation: https://github.com/Mic92/sops-nix

  # NOTE: First-time setup required:
  # 1. Generate age key: age-keygen -o ~/.config/age/keys.txt
  # 2. Create secrets file: sops secrets/secrets.yaml
  # 3. Configure .sops.yaml in repo root

  # Uncomment when secrets are configured:
  # sops = {
  #   defaultSopsFile = ./secrets/secrets.yaml;
  #   age = {
  #     keyFile = "/Users/alx/.config/age/keys.txt";
  #     generateKey = false;  # Manual key management
  #   };
  #
  #   # Example secrets (uncomment and customize)
  #   secrets = {
  #     github_token = {
  #       owner = "alx";
  #       mode = "0400";
  #     };
  #     ssh_private_key = {
  #       owner = "alx";
  #       path = "/Users/alx/.ssh/id_ed25519_sops";
  #       mode = "0400";
  #     };
  #   };
  # };

  # Environment variables for SOPS
  environment.variables = {
    SOPS_AGE_KEY_FILE = "/Users/alx/.config/age/keys.txt";
  };
}
