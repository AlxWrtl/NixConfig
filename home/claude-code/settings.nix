# Claude Code settings and statusline script
{
  settingsJson = builtins.toJSON {
    env = {
      npm_config_prefer_pnpm = "true";
      npm_config_user_agent = "pnpm";
      BASH_DEFAULT_TIMEOUT_MS = "300000";
      BASH_MAX_TIMEOUT_MS = "600000";
    };

    model = "sonnet";

    autoSave = true;
    skipPermissions = false;

    ui = {
      theme = "dark";
      compactMode = false;
      showTokens = true;
      showCost = true;
      animations = true;
    };

    notifications = {
      enabled = true;
      channel = "terminal_bell";
      showProgress = true;
    };

    performance = {
      parallelTools = true;
      cacheEnabled = true;
      compactHistory = true;
      compactFrequency = 30;
    };

    attribution = {
      commit = "";
      pr = "";
    };

    includeCoAuthoredBy = false;

    statusLine = {
      type = "command";
      command = "$HOME/.claude/statusline.sh";
    };

    enabledPlugins = {
    };

    alwaysThinkingEnabled = false;

    betaHeaders = {
      "context-management-2025-06-27" = true;
      "advanced-tool-use-2025-11-20" = true;
    };

    permissions = {
      defaultMode = "acceptEdits";
      allow = [
        "Read(~/.claude/**)"
        "Read(~/.config/**)"
        "Read(.**)"
      ];
      deny = [
        "Websearch"
        "WebSearch"
      ];
    };

    continuousLearningV2 = {
      enabled = true;
      extraction = {
        enabled = true;
        minChangesBeforeExtraction = 3;
        confidenceThreshold = 0.7;
      };
      promotion = {
        enabled = true;
        usageThresholdForSkill = 5;
        autoGenerateSkills = true;
      };
      application = {
        autoSuggest = true;
        relevanceThreshold = 0.8;
        maxSuggestions = 3;
      };
    };

    apex = {
      defaultFlags = {
        auto = false;
        save = true;
        examine = false;
        test = false;
      };
      outputDir = ".claude/output/apex";
    };

    ralphWiggum = {
      defaultMaxIterations = 20;
      sandbox = true;
      autoSave = true;
    };

    hooks = {
      PreToolUse = [
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = "node ~/.claude/hooks/protect-main.js";
              timeout = 10;
            }
          ];
        }
      ];
      PostToolUse = [
        {
          matcher = "Edit|Write.*\\.tsx?$";
          hooks = [
            {
              type = "command";
              command = "node ~/.claude/hooks/format-typescript.js";
              timeout = 10;
            }
          ];
        }
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
      MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "sonnet"')
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
      MODEL="sonnet"
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

    # Output: 🤖 Model | 📁 Dir | ⎇ Branch | 📊 Tokens | 🧠 Context | 💰 Session | 📅 Month
    OUT="''${RED}🤖 $MODEL''${RESET} | ''${ORANGE}📁 $CWD''${RESET}"
    [ -n "$GIT_BRANCH" ] && OUT="$OUT | ''${YELLOW}⎇ $GIT_BRANCH''${RESET}"
    OUT="$OUT | ''${GREEN}📊 $TOKENS_IN_FMT/$TOKENS_OUT_FMT''${RESET}"
    OUT="$OUT | ''${CYAN}🧠 $CONTEXT_PCT%''${RESET}"
    OUT="$OUT | ''${BLUE}💰 $COST_TOTAL''${RESET}"
    OUT="$OUT | ''${MAGENTA}📅 $MONTHLY_COST''${RESET}"

    echo -e "$OUT"
  '';
}
