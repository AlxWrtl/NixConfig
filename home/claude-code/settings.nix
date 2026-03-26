# Claude Code settings and statusline script
{ homeDirectory }:
{
  settingsJson = builtins.toJSON {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    language = "french";
    effortLevel = "high";
    showTurnDuration = true;

    env = {
      npm_config_prefer_pnpm = "true";
      npm_config_user_agent = "pnpm";
      BASH_DEFAULT_TIMEOUT_MS = "300000";
      BASH_MAX_TIMEOUT_MS = "600000";
      CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
      CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "90";
      CLAUDE_STREAM_IDLE_TIMEOUT_MS = "600000";
      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1";
    };

    model = "opus";

    attribution = {
      commit = "";
      pr = "";
    };

    includeCoAuthoredBy = false;

    statusLine = {
      type = "command";
      command = "$HOME/.claude/statusline.sh";
    };

    alwaysThinkingEnabled = false;

    permissions = {
      defaultMode = "acceptEdits";
      allow = [
        "Read(*)"
        # Package managers (npx covers prettier)
        "Bash(pnpm *)"
        "Bash(npm run *)"
        "Bash(npx *)"
        "Bash(bunx *)"
        "Bash(node *)"
        # Git + GitHub (single wildcard covers all subcommands)
        "Bash(git *)"
        "Bash(gh *)"
        # Nix
        "Bash(darwin-rebuild *)"
        "Bash(nix *)"
        "Bash(nixfmt *)"
        # File operations
        "Bash(ls *)"
        "Bash(cat *)"
        "Bash(find *)"
        "Bash(grep *)"
        "Bash(head *)"
        "Bash(tail *)"
        "Bash(wc *)"
        "Bash(echo *)"
        "Bash(which *)"
        "Bash(env *)"
        "Bash(pwd)"
        "Bash(mkdir *)"
        "Bash(cp *)"
        "Bash(mv *)"
        # Tools
        "Bash(jq *)"
        "Bash(fd *)"
        "Bash(rg *)"
        "Bash(bat *)"
        "Bash(eza *)"
        # WebFetch allowlist
        "WebFetch(domain:github.com)"
        "WebFetch(domain:raw.githubusercontent.com)"
        "WebFetch(domain:nix-darwin.github.io)"
        "WebFetch(domain:nixos.org)"
        "WebFetch(domain:search.nixos.org)"
        "WebFetch(domain:*.npmjs.org)"
        "WebFetch(domain:docs.anthropic.com)"
        "WebFetch(domain:code.claude.com)"
      ];
      deny = [
        "Agent(Explore)"
        "Websearch"
        "WebSearch"
        "Bash(rm -rf /*)"
        "Bash(sudo rm *)"
        "Bash(chmod 777 *)"
        "Read(.env)"
        "Read(.env.*)"
        "Read(secrets/**)"
        "Bash(curl * | sh)"
        "Bash(wget * | sh)"
      ];
    };

    hooks = {
      PreToolUse = [
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = "node ~/.claude/hooks/protect-main.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "node ~/.claude/hooks/block-main-bash.js";
              timeout = 5;
            }
          ];
        }
      ];
      PostToolUse = [
        {
          matcher = "Write|Edit";
          hooks = [
            {
              type = "command";
              command = "node ~/.claude/hooks/format-typescript.js";
              timeout = 10;
            }
          ];
        }
      ];
      PreCompact = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/pre-compact-backup.sh";
              timeout = 5;
            }
          ];
        }
      ];
      Notification = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/notification.sh";
              timeout = 3;
            }
          ];
        }
      ];
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/session-start.sh";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "compact";
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/compact-context.sh";
              timeout = 3;
            }
          ];
        }
      ];
      SubagentStop = [
        {
          hooks = [
            {
              type = "command";
              command = "node ~/.claude/hooks/subagent-stop.js";
              timeout = 5;
            }
          ];
        }
      ];
      TaskCompleted = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/task-completed.sh";
              timeout = 3;
            }
          ];
        }
      ];
    };
  };

  # MCP servers merged into ~/.claude/.claude.json by activation script
  # Secrets (API keys) are injected at runtime by claudeCodeMcpMerge, not here
  mcpServersJson = builtins.toJSON {
    gsap-master = {
      type = "stdio";
      command = "npx";
      args = [ "bruzethegreat-gsap-master-mcp-server@latest" ];
      env = { };
    };
    chrome-devtools = {
      type = "stdio";
      command = "npx";
      args = [ "chrome-devtools-mcp@latest" ];
      env = { };
    };
    magic = {
      type = "stdio";
      command = "npx";
      args = [
        "-y"
        "@21st-dev/magic@latest"
      ];
      env = {
        API_KEY = "__SECRET_21ST_DEV__";
      };
    };
    nanobanana = {
      command = "uvx";
      args = [ "nanobanana-mcp-server@latest" ];
      env = {
        GEMINI_API_KEY = "__SECRET_GEMINI_API_KEY__";
      };
    };
    obsidian = {
      type = "stdio";
      command = "npx";
      args = [
        "-y"
        "@bitbonsai/mcpvault@latest"
        "${homeDirectory}/Library/Mobile Documents/com~apple~CloudDocs/Documents/AlxVault"
      ];
    };
  };

  statuslineScript = ''
    #!/usr/bin/env bash
    # Statusline with session and monthly costs (cached)

    INPUT=$(cat)
    CACHE_FILE="/tmp/ccusage-monthly-cache.txt"
    CACHE_MAX_AGE=300  # 5 minutes

    if command -v jq >/dev/null 2>&1; then
      # Parse Claude Code JSON
      MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "opus"')
      CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."' | xargs basename)
      TOKENS_IN=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0')
      TOKENS_OUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0')
      CONTEXT_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0')
      COST_TOTAL=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0' | xargs printf "\$%.2f")

      # Git branch from workspace dir
      WORKSPACE_DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."')
      GIT_BRANCH=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || echo "")

      # Monthly cost (cached for performance)
      MONTHLY_COST=""
      NOW=$(date +%s)

      if [ -f "$CACHE_FILE" ]; then
        CACHE_AGE=$((NOW - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
        if [ $CACHE_AGE -lt $CACHE_MAX_AGE ]; then
          MONTHLY_COST=$(cat "$CACHE_FILE")
        fi
      fi

      if [ -z "$MONTHLY_COST" ]; then
        MONTHLY_COST=$(npx -y ccusage@latest monthly --json 2>/dev/null | jq -r '.totals.totalCost // 0' | xargs printf "\$%.2f")
        echo "$MONTHLY_COST" > "$CACHE_FILE" 2>/dev/null || true
      fi
    else
      MODEL="opus"
      CWD=$(basename "$(pwd)")
      GIT_BRANCH=$(git branch --show-current 2>/dev/null)
      TOKENS_IN="0"
      TOKENS_OUT="0"
      CONTEXT_PCT="0"
      COST_TOTAL="\$0.00"
      MONTHLY_COST="\$0.00"
    fi

    # Colors
    RED='\033[91m'
    ORANGE='\033[38;5;208m'
    YELLOW='\033[93m'
    GREEN='\033[92m'
    CYAN='\033[96m'
    BLUE='\033[94m'
    MAGENTA='\033[95m'
    RESET='\033[0m'

    # Format numbers with thousands separator
    TOKENS_IN_FMT=$(printf "%'d" $TOKENS_IN 2>/dev/null || echo $TOKENS_IN)
    TOKENS_OUT_FMT=$(printf "%'d" $TOKENS_OUT 2>/dev/null || echo $TOKENS_OUT)

    # Output: Model | Dir | Branch | Tokens | Context | Session | Month
    OUT="''${RED}🤖 $MODEL''${RESET} | ''${ORANGE}📁 $CWD''${RESET}"
    [ -n "$GIT_BRANCH" ] && OUT="$OUT | ''${YELLOW}⎇ $GIT_BRANCH''${RESET}"
    OUT="$OUT | ''${GREEN}📊 $TOKENS_IN_FMT/$TOKENS_OUT_FMT''${RESET}"
    OUT="$OUT | ''${CYAN}🧠 $CONTEXT_PCT%''${RESET}"
    OUT="$OUT | ''${BLUE}💰 $COST_TOTAL''${RESET}"
    OUT="$OUT | ''${MAGENTA}📅 $MONTHLY_COST''${RESET}"

    echo -e "$OUT"
  '';
}
