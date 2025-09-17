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

  # === Claude Code Configuration Files ===
  # All configurations managed within nix-darwin structure

  # Default Claude configuration
  claudeConfig = pkgs.writeTextFile {
    name = "claude-config.json";
    text = builtins.toJSON {
      defaultModel = "claude-sonnet-4-20250514";
      allowedTools = ["bash" "edit" "read" "write" "glob" "grep" "task"];
      autoSave = true;
      notifications = {
        enabled = true;
        channel = "terminal_bell";
      };
      hooks = {
        preEdit = [];
        postEdit = ["prettier" "eslint"];
      };
      mcp = {
        enabled = true;
        servers = {};
      };
    };
  };

  # Sample TDD command
  tddCommand = pkgs.writeTextFile {
    name = "tdd.md";
    text = ''
      # Test-Driven Development Command

      Guide development using TDD principles:
      1. Write failing test first
      2. Write minimal code to pass
      3. Refactor while keeping tests green
      4. Repeat cycle

      Always run tests after each step.
    '';
  };

  # Context-prime command for comprehensive project understanding
  contextPrimeCommand = pkgs.writeTextFile {
    name = "context-prime.md";
    text = ''
      # Context Prime Command

      Load comprehensive project understanding:
      1. Read CLAUDE.md and project documentation
      2. Analyze directory structure and key files
      3. Understand tech stack and dependencies
      4. Review recent git history and changes
      5. Identify testing patterns and build processes

      Provides deep context for informed code assistance.
    '';
  };

  # MCP servers configuration
  mcpServersConfig = pkgs.writeTextFile {
    name = "mcp-servers.json";
    text = builtins.toJSON {
      mcpServers = {
        filesystem = {
          command = "npx";
          args = ["-y" "@modelcontextprotocol/server-filesystem" "/path/to/allowed/files"];
        };
        git = {
          command = "npx";
          args = ["-y" "@modelcontextprotocol/server-git" "--repository" "."];
        };
      };
    };
  };

  # Configuration setup script
  claudeConfigSetup = pkgs.writeShellScriptBin "claude-setup" ''
    # Create Claude configuration directories within nix-darwin structure
    CLAUDE_DIR="$HOME/.config/nix-darwin/claude"
    mkdir -p "$CLAUDE_DIR/commands"
    mkdir -p "$CLAUDE_DIR/hooks"
    mkdir -p "$CLAUDE_DIR/mcp"

    # Link configuration files from nix store
    ln -sf "${claudeConfig}" "$CLAUDE_DIR/config.json"
    ln -sf "${tddCommand}" "$CLAUDE_DIR/commands/tdd.md"
    ln -sf "${contextPrimeCommand}" "$CLAUDE_DIR/commands/context-prime.md"
    ln -sf "${mcpServersConfig}" "$CLAUDE_DIR/mcp/servers.json"

    echo "✅ Claude configuration linked to nix-darwin structure"
    echo "📁 Configuration directory: $CLAUDE_DIR"
    echo "🎉 Run 'claude-code doctor' to verify setup"
  '';

in {
  # Claude Code CLI integration with 2025 optimizations
  # Provides system-wide access to Anthropic's Claude Code CLI tool
  # Includes advanced configuration, MCP support, and productivity aliases
  # Requires global installation via pnpm for automatic updates

  # ============================================================================
  # SYSTEM PACKAGE INSTALLATION
  # ============================================================================

  environment.systemPackages = [
    claudeCodeWrapper                       # Install Claude Code wrapper globally
    claudeConfigSetup                       # Claude Code configuration setup utility
  ];

  # ============================================================================
  # CLAUDE CODE ACTIVATION HOOKS
  # ============================================================================

  # Run Claude setup on system activation
  system.activationScripts.claudeSetup = {
    text = ''
      # Ensure Claude configuration directory exists for all users
      echo "Setting up Claude Code configuration..."

      # Create Claude configuration within nix-darwin structure
      CLAUDE_DIR="$HOME/.config/nix-darwin/claude"
      mkdir -p "$CLAUDE_DIR/commands"
      mkdir -p "$CLAUDE_DIR/hooks"
      mkdir -p "$CLAUDE_DIR/mcp"

      # Link configuration files if they don't exist
      [ ! -L "$CLAUDE_DIR/config.json" ] && ln -sf "${claudeConfig}" "$CLAUDE_DIR/config.json"
      [ ! -L "$CLAUDE_DIR/commands/tdd.md" ] && ln -sf "${tddCommand}" "$CLAUDE_DIR/commands/tdd.md"
      [ ! -L "$CLAUDE_DIR/commands/context-prime.md" ] && ln -sf "${contextPrimeCommand}" "$CLAUDE_DIR/commands/context-prime.md"
      [ ! -L "$CLAUDE_DIR/mcp/servers.json" ] && ln -sf "${mcpServersConfig}" "$CLAUDE_DIR/mcp/servers.json"

      echo "Claude Code system configuration complete."
    '';
  };

  # ============================================================================
  # CLAUDE CODE ENVIRONMENT CONFIGURATION
  # ============================================================================

  environment.variables = {
    # === Claude Code CLI Settings ===
    # CLAUDE_API_KEY = "";                  # Set in shell profile or .env files
    CLAUDE_MODEL = "claude-sonnet-4-20250514";  # Latest Claude 4 Sonnet (2025)
    CLAUDE_MAX_TOKENS = "8192";            # Increased token limit for better context
    CLAUDE_CONFIG_DIR = "$HOME/.config/nix-darwin/claude"; # Configuration directory in nix folder

    # === 2025 Enhanced Features ===
    CLAUDE_NOTIFY_CHANNEL = "terminal_bell"; # Enable terminal notifications
    CLAUDE_ENABLE_MCP = "true";             # Enable Model Context Protocol
    CLAUDE_SESSION_AUTOSAVE = "true";       # Auto-save sessions for --resume
    CLAUDE_HOOKS_ENABLED = "true";          # Enable pre/post-edit hooks

    # === Performance Optimizations ===
    CLAUDE_PARALLEL_TOOLS = "true";         # Enable parallel tool execution
    CLAUDE_CACHE_ENABLED = "true";          # Enable local caching
    CLAUDE_PLAN_MODE_DEFAULT = "false";     # Start in execution mode (Shift+Tab for plan)

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

    # === Essential Operations ===
    cc-init = "claude-code /init";          # Initialize project with CLAUDE.md
    cc-help = "claude-code --help";         # Show help information
    cc-doctor = "claude-code doctor";       # Verify installation and config
    cc-version = "claude-code --version";   # Show version information

    # === Advanced Workflows ===
    cc-resume = "claude-code --resume";     # Resume last session
    cc-continue = "claude-code --continue"; # Continue previous conversation
    cc-plan = "claude-code --plan-mode";    # Start in plan mode

    # === Model Selection ===
    cc-opus = "claude-code --model claude-opus-4";    # Use Opus for complex tasks
    cc-sonnet = "claude-code --model claude-sonnet-4"; # Use Sonnet (default)
    cc-haiku = "claude-code --model claude-haiku";     # Use Haiku for simple tasks

    # === Multi-Directory Support ===
    cc-add = "claude-code --add-dir";       # Add directory to current session

    # === Debugging & Analysis ===
    cc-trace = "claude-code --trace";       # Enable detailed logging
    cc-safe = "claude-code --plan-mode --read-only"; # Safe research mode
  };
}