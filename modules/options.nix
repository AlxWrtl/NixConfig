{ lib, ... }:

{
  # ============================================================================
  # MODULE OPTIONS DEFINITIONS
  # ============================================================================
  # Centralized option declarations for nix-darwin system configuration
  # These options can be set in any module to control feature enablement

  options.nix-darwin = {
    enablePython = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Python development stack (python3, uv, ruff)";
    };

    enableOptimizations = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable system optimizations (power management, network tuning)";
    };
  };
}
