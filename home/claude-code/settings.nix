# Claude Code settings and statusline script
{ homeDirectory }:
let
  # Absolute path to node — /bin/sh can't find nix-installed node in PATH
  node = "/run/current-system/sw/bin/node";
in
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
      CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
    };

    model = "opus";
    voiceEnabled = true;
    skipDangerousModePermissionPrompt = true;

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

    includeGitInstructions = false;

    sandbox = {
      enabled = true;
      filesystem = {
        denyWrite = [
          "/etc"
          "/System"
          "/Library"
          "${homeDirectory}/.ssh/id_*"
          "${homeDirectory}/.ssh/config"
          "${homeDirectory}/.aws"
          "${homeDirectory}/.gnupg"
          "${homeDirectory}/.config/secrets"
        ];
        denyRead = [
          "${homeDirectory}/.aws/credentials"
          "${homeDirectory}/.gnupg/private-keys-v1.d"
        ];
      };
      network = {
        # All domains allowed (web analysis, design, docs, APIs)
        allowedDomains = [ "*" ];
      };
    };

    permissions = {
      defaultMode = "acceptEdits";
      allow = [
        "Read(*)"
        # Package managers
        "Bash(pnpm *)"
        "Bash(npm run *)"
        "Bash(dev-browser *)"
        "Bash(npx dev-browser *)"
        "Bash(npx @21st-dev/magic@*)"
        "Bash(npx ccusage@*)"
        "Bash(npx prettier *)"
        "Bash(npx tsc *)"
        "Bash(bunx *)"
        "Bash(node *)"
        # Git — safe operations (granular, not blanket)
        "Bash(git status *)"
        "Bash(git diff *)"
        "Bash(git log *)"
        "Bash(git branch *)"
        "Bash(git show *)"
        "Bash(git stash *)"
        "Bash(git fetch *)"
        "Bash(git pull *)"
        "Bash(git add *)"
        "Bash(git checkout -b *)"
        "Bash(git switch *)"
        "Bash(git commit *)"
        "Bash(git push)"
        "Bash(git push -u *)"
        "Bash(git push origin *)"
        "Bash(git merge *)"
        "Bash(git rebase *)"
        "Bash(git cherry-pick *)"
        "Bash(git tag *)"
        "Bash(git remote *)"
        "Bash(git rev-parse *)"
        "Bash(git ls-files *)"
        "Bash(git blame *)"
        "Bash(git shortlog *)"
        # GitHub CLI
        "Bash(gh pr *)"
        "Bash(gh issue *)"
        "Bash(gh repo *)"
        "Bash(gh run *)"
        "Bash(gh api *)"
        "Bash(gh auth *)"
        # Nix
        "Bash(darwin-rebuild *)"
        "Bash(nix *)"
        "Bash(nixfmt *)"
        # File operations (read-only + safe)
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
        # RTK
        "Bash(rtk *)"
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
        # Shell bypass — prevent permission/hook circumvention
        "Bash(bash -c *)"
        "Bash(bash -i *)"
        "Bash(sh -c *)"
        "Bash(sh -i *)"
        "Bash(zsh -c *)"
        "Bash(zsh -i *)"
        "Bash(python -c *)"
        "Bash(python3 -c *)"
        "Bash(node -e *)"
        "Bash(node --eval *)"
        "Bash(ruby -e *)"
        "Bash(perl -e *)"
        "Bash(perl -E *)"
        "Bash(eval *)"
        # Git destructive ops
        "Bash(git push --force *)"
        "Bash(git push -f *)"
        "Bash(git push --force-with-lease *)"
        "Bash(git reset --hard *)"
        "Bash(git clean -fdx *)"
        "Bash(git clean -fxd *)"
        "Bash(git checkout -- .)"
        # Filesystem destructive
        "Bash(rm -rf /*)"
        "Bash(sudo *)"
        "Bash(chmod 777 *)"
        # Secrets — absolute paths via Nix interpolation
        "Read(${homeDirectory}/.ssh/**)"
        "Read(${homeDirectory}/.aws/**)"
        "Read(${homeDirectory}/.gnupg/**)"
        "Read(${homeDirectory}/.config/secrets/**)"
        "Read(**/.env)"
        "Read(**/.env.*)"
        "Read(**/secrets/**)"
        # Network piping
        "Bash(curl * | sh)"
        "Bash(curl * | bash)"
        "Bash(wget * | sh)"
        "Bash(wget * | bash)"
        # WebSearch — allowed (needed for web analysis)
      ];
    };

    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/rtk-rewrite.sh";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/protect-main.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Bash";
          "if" = "Bash(git commit *)|Bash(git push *)|Bash(git merge *)|Bash(git rebase *)|Bash(git checkout *)";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/block-main-bash.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Edit|Write|Bash|Agent";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/governance-audit.js";
              timeout = 3;
              async = true;
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
              command = "${node} ~/.claude/hooks/format-typescript.js";
              timeout = 10;
              async = true;
            }
          ];
        }
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/circuit-breaker-reset.js";
              timeout = 3;
              async = true;
            }
          ];
        }
      ];
      PostToolUseFailure = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/circuit-breaker.js";
              timeout = 5;
            }
          ];
        }
      ];
      PreCompact = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/pre-compact-state.js";
              timeout = 10;
            }
          ];
        }
      ];
      PostCompact = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/post-compact-restore.js";
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
              command = "${node} ~/.claude/hooks/subagent-stop.js";
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
      Stop = [
        {
          hooks = [
            {
              type = "command";
              command = "printf '\\e[>4;0m'";
              timeout = 1;
            }
          ];
        }
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/quality-gate.js";
              timeout = 10;
            }
          ];
        }
      ];
      StopFailure = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/stop-failure.sh";
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
    magic = {
      type = "stdio";
      command = "npx";
      args = [
        "-y"
        "@21st-dev/magic@0.1.0"
      ];
      env = {
        API_KEY = "__SECRET_21ST_DEV__";
      };
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
        MONTHLY_COST=$(npx -y ccusage@18.0.10 monthly --json 2>/dev/null | jq -r '.totals.totalCost // 0' | xargs printf "\$%.2f")
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
