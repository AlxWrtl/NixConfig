# Hook scripts for Claude Code
# All command hooks: read JSON from stdin, exit 0 (allow) or exit 2 + stderr (block)
# In Nix '' strings: escape single quotes as ''' (two apostrophes + the quote)
{
  hookProtectMain = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const { execSync } = require("child_process");
      const fs = require("fs");
      // Guard: skip if not in a git repo
      if (!fs.existsSync(".git") && !fs.existsSync("../.git")) process.exit(0);
      try {
        const branch = execSync("git branch --show-current", { encoding: "utf8" }).trim();
        if (branch === "main" || branch === "master") {
          const msg = "Cannot edit on main/master. Create feature branch first.";
          process.stdout.write(JSON.stringify({ hookSpecificOutput: { permissionDecisionReason: msg } }));
          process.exit(2);
        }
      } catch (e) { process.exit(0); }
      process.exit(0);
    });
  '';

  hookFormatTypescript = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const { execSync } = require("child_process");
      const exts = [".ts", ".tsx", ".js", ".jsx", ".css", ".json"];
      try {
        const data = JSON.parse(input);
        const file = (data.tool_input && data.tool_input.file_path) || "";
        if (file && exts.some(ext => file.endsWith(ext))) {
          execSync("which prettier", { stdio: "pipe" });
          execSync("prettier --write " + JSON.stringify(file), { stdio: "pipe" });
        }
      } catch (e) { process.exit(0); }
      process.exit(0);
    });
  '';

  hookBlockMainBash = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const { execSync } = require("child_process");
      const fs = require("fs");
      // Guard: skip if not in a git repo
      if (!fs.existsSync(".git") && !fs.existsSync("../.git")) process.exit(0);
      try {
        const data = JSON.parse(input);
        const cmd = (data.tool_input && data.tool_input.command) || "";
        if (!/git\s+(commit|push|merge|rebase)/.test(cmd)) process.exit(0);
        const branch = execSync("git branch --show-current", { encoding: "utf8" }).trim();
        if (branch === "main" || branch === "master") {
          const msg = "Cannot commit/push on main/master. Create a feature branch first.";
          process.stdout.write(JSON.stringify({ hookSpecificOutput: { permissionDecisionReason: msg } }));
          process.exit(2);
        }
      } catch (e) { process.exit(0); }
      process.exit(0);
    });
  '';

  hookPreCompactBackup = ''
    #!/usr/bin/env bash
    set -euo pipefail
    BACKUP_DIR="$HOME/.claude/backups"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    TRANSCRIPT="$BACKUP_DIR/session-$TIMESTAMP.jsonl"
    if [ -n "''${CLAUDE_TRANSCRIPT_PATH:-}" ] && [ -f "$CLAUDE_TRANSCRIPT_PATH" ]; then
      cp "$CLAUDE_TRANSCRIPT_PATH" "$TRANSCRIPT"
    fi
  '';

  hookSessionStart = ''
    #!/usr/bin/env bash
    # Guard: graceful handling outside git repos
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Not a git repo"
      exit 0
    fi
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
    MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "branch: $BRANCH | last: $LAST_COMMIT | modified: $MODIFIED files"
  '';

  hookSubagentStop = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const fs = require("fs");
      const path = require("path");
      try {
        const data = JSON.parse(input);
        const logDir = path.join(process.env.HOME, ".claude/output");
        fs.mkdirSync(logDir, { recursive: true });
        const entry = {
          ts: new Date().toISOString(),
          agent: data.agent_type || data.agent_name || "unknown",
          duration_ms: data.duration_ms || 0,
          summary: (data.task_description || "").slice(0, 200)
        };
        fs.appendFileSync(path.join(logDir, "agent-log.jsonl"), JSON.stringify(entry) + "\n");
      } catch (e) { process.exit(0); }
      process.exit(0);
    });
  '';

  hookTaskCompleted = ''
    #!/usr/bin/env bash
    osascript -e '''display notification "Task completed" with title "Claude Code"''' 2>/dev/null || true
  '';

  hookNotification = ''
    #!/usr/bin/env bash
    osascript -e '''display notification "Attention requise" with title "Claude Code" sound name "Tink"''' 2>/dev/null || true
  '';

  hookCompactContext = ''
    #!/usr/bin/env bash
    echo "Post-compact context: Shell=zsh+starship+nix-darwin | PM=pnpm | Rebuild=sudo darwin-rebuild switch --flake .#alex-mbp | Protected branches: main/master | Commits: EN imperative, type prefix | Read CLAUDE.md + skills before coding"
  '';

  hookFileChanged = ''
    #!/usr/bin/env bash
    # React to file changes (flake.lock, .envrc, package.json)
    INPUT=$(cat)
    FILE=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
    case "$FILE" in
      */flake.lock)
        echo "flake.lock changed — run: nix flake update or rebuild"
        ;;
      */.envrc)
        direnv allow 2>/dev/null || true
        echo "direnv reloaded"
        ;;
      */package.json|*/pnpm-lock.yaml)
        echo "deps changed — run: pnpm install"
        ;;
    esac
  '';

  hookStopFailure = ''
    #!/usr/bin/env bash
    # Alert on rate limits or API failures
    INPUT=$(cat)
    if echo "$INPUT" | grep -qi "rate.limit\|429\|overloaded"; then
      osascript -e '''display notification "Rate limit hit — pause recommended" with title "Claude Code" sound name "Basso"''' 2>/dev/null || true
    fi
  '';
}
