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
      # Commands that run OUTSIDE the sandbox → normal permission prompt (ask)
      # instead of being hard-blocked with "operation not permitted".
      # Lets Claude run `sudo darwin-rebuild ...` with a confirmation box,
      # so the user no longer has to retype it with a leading `!`.
      excludedCommands = [
        "sudo *"
        "darwin-rebuild *"
      ];
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
      # `ask` forces a confirmation box for matching commands, overriding
      # skipDangerousModePermissionPrompt and acceptEdits. Precedence: deny > ask > allow.
      # Every sudo prompts for Yes/No; everything else stays auto-approved.
      ask = [
        "Bash(sudo *)"
      ];
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
        # Note: merge/push to master/main is NOT hard-denied — the block-main-bash
        # hook turns those into a confirmation box (ask) so the user approves
        # in-place. commit/rebase on master stay denied by that hook.
        "Bash(git reset --hard *)"
        "Bash(git clean -fdx *)"
        "Bash(git clean -fxd *)"
        "Bash(git checkout -- .)"
        # Filesystem destructive
        "Bash(rm -rf /*)"
        # Note: `sudo` intentionally NOT denied — Claude may invoke it but each
        # call requires interactive confirmation (not in allow-list either).
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
    playwright = {
      type = "stdio";
      command = "npx";
      args = [
        "-y"
        "@playwright/mcp@latest"
      ];
    };
  };

  statuslineScript = ''
    #!/usr/bin/env bash
    # Statusline: model, dir, branch, tokens, context bar, 5h + 7d rate-limit bars.
    # Rate-limit data comes straight from Claude Code's JSON (rate_limits.*), the
    # same source as the official usage screen — no ccusage, no transcript parsing.

    INPUT=$(cat)

    # Colors — use $'...' so bash expands \033 at assignment time. This avoids
    # printf "%b", which mangles the UTF-8 bytes of █/░ under a UTF-8 locale.
    RED=$'\033[91m'
    ORANGE=$'\033[38;5;208m'
    YELLOW=$'\033[93m'
    GREEN=$'\033[92m'
    CYAN=$'\033[96m'
    BLUE=$'\033[94m'
    GREY=$'\033[90m'
    RESET=$'\033[0m'

    # Glyphs built from explicit UTF-8 bytes via printf, so no literal multibyte
    # char lives in the source (avoids byte truncation through the nix/CC pipeline).
    FULL_CH=$(printf '\xe2\x96\x88')        # █ U+2588 full block
    EMPTY_CH=$(printf '\xe2\x96\x91')       # ░ U+2591 light shade

    # Render a 10-cell progress bar: filled colored by threshold (green<60,
    # orange<85, red>=85), empty in neutral grey so it stays visible.
    make_bar() {
      local pct=$1
      [ -z "$pct" ] && pct=0
      pct=''${pct%.*}                       # strip decimals
      [ "$pct" -gt 100 ] 2>/dev/null && pct=100
      [ "$pct" -lt 0 ] 2>/dev/null && pct=0
      local filled=$((pct / 10))
      local empty=$((10 - filled))
      local color=$GREEN
      [ "$pct" -ge 60 ] && color=$ORANGE
      [ "$pct" -ge 85 ] && color=$RED
      local full="" rest=""
      local i
      for ((i=0; i<filled; i++)); do full="$full$FULL_CH"; done
      for ((i=0; i<empty;  i++)); do rest="$rest$EMPTY_CH"; done
      printf '%s%s%s%s%s' "$color" "$full" "$GREY" "$rest" "$RESET"
    }

    if command -v jq >/dev/null 2>&1; then
      MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "opus"' | sed -E 's/ *\(.*\)//')
      CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."' | xargs basename)
      TOKENS_IN=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0')
      TOKENS_OUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0')
      CONTEXT_PCT=$(echo "$INPUT" | jq -r '(.context_window.used_percentage // 0) | round')

      WORKSPACE_DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."')
      GIT_BRANCH=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || echo "")

      # Rate limits straight from Claude Code JSON (Pro/Max only; absent before the
      # first API call). used_percentage = quota consumed; resets_at = unix epoch.
      NOW=$(date +%s)
      H5_PCT=$(echo "$INPUT" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | round')
      H5_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty')
      D7_PCT=$(echo "$INPUT" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | round')
      D7_RESET=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty')
    else
      MODEL="opus"
      CWD=$(basename "$(pwd)")
      GIT_BRANCH=$(git branch --show-current 2>/dev/null)
      TOKENS_IN="0"; TOKENS_OUT="0"; CONTEXT_PCT="0"
      H5_PCT=""; H5_RESET=""; D7_PCT=""; D7_RESET=""
    fi

    TOKENS_IN_FMT=$(printf "%'d" $TOKENS_IN 2>/dev/null || echo $TOKENS_IN)
    TOKENS_OUT_FMT=$(printf "%'d" $TOKENS_OUT 2>/dev/null || echo $TOKENS_OUT)

    CTX_BAR=$(make_bar "$CONTEXT_PCT")

    # Time until an epoch reset: "42min" when under an hour, else "H.MMh" where the
    # digits after the dot are literal minutes (00-59), e.g. 5h07 -> "5.07h".
    fmt_reset() {
      local s=$(( $1 - NOW )); [ $s -lt 0 ] && s=0
      local mins=$(( s / 60 ))
      if [ $mins -lt 60 ]; then
        printf '%dmin' "$mins"
      else
        printf '%d.%02dh' $(( mins / 60 )) $(( mins % 60 ))
      fi
    }

    # Visible width of a string, ignoring ANSI color codes (strips ESC[...m).
    vis_width() {
      local stripped
      stripped=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')
      printf '%s' "''${#stripped}"
    }

    # Group 1 — session info; Group 2 — context + quota bars.
    G1="''${RED}🤖 $MODEL''${RESET} | ''${ORANGE}📁 $CWD''${RESET}"
    [ -n "$GIT_BRANCH" ] && G1="$G1 | ''${YELLOW}⎇ $GIT_BRANCH''${RESET}"
    G1="$G1 | ''${GREEN}📊 $TOKENS_IN_FMT/$TOKENS_OUT_FMT''${RESET}"

    G2="🧠 $CTX_BAR ''${CYAN}$CONTEXT_PCT%''${RESET}"
    [ -n "$H5_PCT" ] && G2="$G2 | ⏳ $(make_bar "$H5_PCT") ''${CYAN}$H5_PCT% · $(fmt_reset "$H5_RESET")''${RESET}"
    [ -n "$D7_PCT" ] && G2="$G2 | 📆 $(make_bar "$D7_PCT") ''${CYAN}$D7_PCT% · $(fmt_reset "$D7_RESET")''${RESET}"

    # Single line if it fits the terminal width (COLUMNS, set by Claude Code
    # v2.1.153+); otherwise wrap onto two lines. Emoji count as width 2, so add
    # a small margin. Fall back to one line when COLUMNS is unknown.
    ONE="$G1 | $G2"
    COLS=''${COLUMNS:-0}
    if [ "$COLS" -gt 0 ] && [ "$(vis_width "$ONE")" -ge $((COLS - 8)) ]; then
      OUT="$G1"$'\n'"$G2"
    else
      OUT="$ONE"
    fi

    printf '%s\n' "$OUT"
  '';
}
