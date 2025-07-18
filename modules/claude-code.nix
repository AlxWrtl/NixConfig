{ config, pkgs, lib, ... }:

let
  # ============================================================================
  # CLAUDE CODE CLI WRAPPER CONFIGURATION
  # ============================================================================

  # === Dynamic Path Resolution ===
  # Resolve PNPM home directory from environment or use default
  pnpmHome = config.environment.variables.PNPM_HOME or "$HOME/Library/pnpm";

  # === CLI Path Construction ===
  # Standard pnpm global package structure for Claude Code CLI
  cliPath = "${pnpmHome}/global/5/node_modules/@anthropic-ai/claude-code/cli.js";

  # === System Wrapper Script ===
  # Creates a system-wide wrapper that validates installation and executes CLI
  claudeCodeWrapper = pkgs.writeShellScriptBin "claude-code" ''
    # Validate Claude Code CLI installation
    if [ ! -f "${cliPath}" ]; then
      echo "❌ Claude Code CLI not found. Please install with: pnpm install -g @anthropic-ai/claude-code" >&2
      echo "📍 Expected location: ${cliPath}" >&2
      echo "🔧 Current PNPM_HOME: ${pnpmHome}" >&2
      exit 1
    fi

    # Execute Claude Code CLI with all arguments
    exec node "${cliPath}" "$@"
  '';

in {
  # Claude Code CLI integration
  # Provides system-wide access to Anthropic's Claude Code CLI tool
  # Requires global installation via pnpm for automatic updates

  # ============================================================================
  # SYSTEM PACKAGE INSTALLATION
  # ============================================================================

  environment.systemPackages = [
    claudeCodeWrapper                       # Install Claude Code wrapper globally
  ];

  # ============================================================================
  # CLAUDE CODE ENVIRONMENT CONFIGURATION
  # ============================================================================

  environment.variables = {
    # === Claude Code CLI Settings ===
    # CLAUDE_API_KEY = "";                  # Set in shell profile or .env files
    # CLAUDE_MODEL = "claude-3-sonnet";     # Default model preference
    # CLAUDE_MAX_TOKENS = "4096";           # Maximum response length

    # === Integration Settings ===
    # EDITOR = "code";                      # Preferred editor for Claude Code (set in system.nix)
    # PAGER = "less";                       # Pager for long outputs (set in system.nix)
  };

  # ============================================================================
  # SHELL INTEGRATION
  # ============================================================================

  environment.shellAliases = {
    # === Claude Code Shortcuts ===
    cc = "claude-code";                     # Quick access alias
    claude = "claude-code";                 # Alternative alias

    # === Common Claude Code Operations ===
    # cc-chat = "claude-code chat";         # Start interactive chat
    # cc-help = "claude-code --help";       # Show help information
    # cc-version = "claude-code --version"; # Show version information
  };
}