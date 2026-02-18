{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # ============================================================================
  # HOST CONFIGURATION IMPORTS
  # ============================================================================

  imports = [
    # === Host-Specific Configuration ===
    ./configuration.nix # Core host settings (networking, users, platform)
  ];
}
