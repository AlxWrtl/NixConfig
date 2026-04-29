# Hook scripts for Claude Code
# All command hooks: read JSON from stdin, exit 0 + JSON stdout
# permissionDecision: "allow" | "deny" | "ask"
# In Nix '' strings: escape single quotes as ''' (two apostrophes + the quote)
{
  hookProtectMain = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const { execSync } = require("child_process");
      const path = require("path");
      const fs = require("fs");
      try { execSync("git rev-parse --is-inside-work-tree", { stdio: "pipe" }); } catch { process.exit(0); }
      try {
        const branch = execSync("git branch --show-current", { encoding: "utf8" }).trim();
        if (branch !== "main" && branch !== "master") process.exit(0);
        let filePath;
        try {
          const data = JSON.parse(input);
          filePath = data && data.tool_input && data.tool_input.file_path;
        } catch { process.exit(0); }
        if (!filePath) process.exit(0);
        let toplevel;
        try { toplevel = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim(); } catch { process.exit(0); }
        let realTop = toplevel;
        try { realTop = fs.realpathSync(toplevel); } catch {}
        const resolved = path.resolve(filePath);
        let realResolved = resolved;
        try { realResolved = fs.realpathSync(resolved); } catch {}
        if (!realResolved.startsWith(realTop + path.sep)) process.exit(0);
        const reason = "BLOCKED: on " + branch + ". Run: git checkout -b <type>/<desc> (e.g. feat/auth-redirect, fix/nav-crash) then retry.";
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: reason
          }
        }));
      } catch (e) {}
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
      try { execSync("git rev-parse --is-inside-work-tree", { stdio: "pipe" }); } catch { process.exit(0); }
      try {
        const data = JSON.parse(input);
        const cmd = (data.tool_input && data.tool_input.command) || "";
        if (!/git\s+(commit|push|merge|rebase)/.test(cmd)) process.exit(0);
        const branch = execSync("git branch --show-current", { encoding: "utf8" }).trim();
        if (branch === "main" || branch === "master") {
          const reason = "BLOCKED: on " + branch + ". Run: git checkout -b <type>/<desc> (e.g. feat/auth-redirect, fix/nav-crash) then retry.";
          process.stdout.write(JSON.stringify({
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              permissionDecision: "deny",
              permissionDecisionReason: reason
            }
          }));
        }
      } catch (e) {}
      process.exit(0);
    });
  '';

  # Save working state before compaction so it can be restored
  hookPreCompactState = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    const { execSync } = require("child_process");
    const stateFile = path.join(process.env.HOME, ".claude/compact-state.json");
    try {
      const state = { ts: new Date().toISOString() };
      // Capture modified files
      try {
        state.modifiedFiles = execSync("git diff --name-only 2>/dev/null || true", { encoding: "utf8" }).trim().split("\n").filter(Boolean);
        state.stagedFiles = execSync("git diff --cached --name-only 2>/dev/null || true", { encoding: "utf8" }).trim().split("\n").filter(Boolean);
        state.branch = execSync("git branch --show-current 2>/dev/null || true", { encoding: "utf8" }).trim();
      } catch { state.modifiedFiles = []; state.stagedFiles = []; state.branch = ""; }
      // Capture active plan/context if exists
      try {
        const planDir = ".claude/output";
        if (fs.existsSync(planDir)) {
          const plans = fs.readdirSync(planDir).filter(f => f.endsWith(".md")).slice(-3);
          state.activePlans = plans;
        }
      } catch {}
      // Capture circuit breaker state
      const cbFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
      try { state.circuitBreaker = JSON.parse(fs.readFileSync(cbFile, "utf8")); } catch {}
      fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
    } catch {}
    process.exit(0);
  '';

  # Restore state after compaction via additionalContext
  hookPostCompactRestore = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const stateFile = path.join(process.env.HOME, ".claude/compact-state.json");
      try {
        const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
        // Skip if state is stale (>1 hour)
        const age = Date.now() - new Date(state.ts).getTime();
        if (age > 3600000) { process.exit(0); return; }
        const parts = [];
        if (state.branch) parts.push("Branch: " + state.branch);
        if (state.modifiedFiles && state.modifiedFiles.length > 0)
          parts.push("Modified files: " + state.modifiedFiles.join(", "));
        if (state.stagedFiles && state.stagedFiles.length > 0)
          parts.push("Staged files: " + state.stagedFiles.join(", "));
        if (state.activePlans && state.activePlans.length > 0)
          parts.push("Active plans in .claude/output/: " + state.activePlans.join(", "));
        if (state.circuitBreaker && state.circuitBreaker.totalTrips > 0)
          parts.push("Circuit breaker trips: " + state.circuitBreaker.totalTrips);
        if (parts.length > 0) {
          const ctx = "POST-COMPACT STATE RESTORE:\n" + parts.join("\n");
          process.stdout.write(JSON.stringify({ hookSpecificOutput: { additionalContext: ctx } }));
        }
      } catch {}
      process.exit(0);
    });
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

  # Quality gate — scan recent changes for anti-patterns on Stop
  hookQualityGate = ''
    #!/usr/bin/env node
    const { execSync } = require("child_process");
    const fs = require("fs");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      try {
        // Only check if we are in a git repo with changes
        const diff = execSync("git diff --name-only HEAD 2>/dev/null || true", { encoding: "utf8" }).trim();
        if (!diff) { process.exit(0); return; }
        const files = diff.split("\n").filter(f => /\.(ts|tsx|js|jsx)$/.test(f));
        if (files.length === 0) { process.exit(0); return; }
        const patterns = [
          { re: /console\.log\(/g, msg: "console.log in production code" },
          { re: /:\s*any\b/g, msg: "TypeScript 'any' type" },
          { re: /\balert\s*\(/g, msg: "alert() call" },
          { re: /\bconfirm\s*\(/g, msg: "confirm() call" },
          { re: /\/\/\s*TODO\b/gi, msg: "TODO comment" },
          { re: /\/\/\s*HACK\b/gi, msg: "HACK comment" },
          { re: /\/\/\s*FIXME\b/gi, msg: "FIXME comment" },
        ];
        const issues = [];
        for (const file of files) {
          try {
            const content = fs.readFileSync(file, "utf8");
            const lines = content.split("\n");
            for (const p of patterns) {
              for (let i = 0; i < lines.length; i++) {
                if (p.re.test(lines[i])) {
                  issues.push(file + ":" + (i+1) + " — " + p.msg);
                }
                p.re.lastIndex = 0;
              }
            }
          } catch {}
        }
        if (issues.length > 0) {
          const ctx = "QUALITY GATE — " + issues.length + " issue(s) in changed files:\n" + issues.slice(0, 10).join("\n");
          // Advisory only — exit 0 with additionalContext (Stop does not support it, use stderr info)
          process.stderr.write(ctx);
          process.exit(2);
        }
      } catch {}
      process.exit(0);
    });
  '';

  # Governance audit log — append-only log of significant tool calls
  hookGovernanceAudit = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      try {
        const data = JSON.parse(input);
        const logDir = path.join(process.env.HOME, ".claude/audit");
        fs.mkdirSync(logDir, { recursive: true });
        const entry = {
          ts: new Date().toISOString(),
          tool: data.tool_name || "unknown",
          target: "",
          session: data.session_id || ""
        };
        const ti = data.tool_input || {};
        if (ti.file_path) entry.target = ti.file_path;
        else if (ti.command) entry.target = ti.command.slice(0, 200);
        else if (ti.prompt) entry.target = "agent: " + (ti.prompt || "").slice(0, 100);
        fs.appendFileSync(
          path.join(logDir, "audit.jsonl"),
          JSON.stringify(entry) + "\n"
        );
      } catch {}
      process.exit(0);
    });
  '';

  hookCircuitBreaker = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const stateFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
      let state = { consecutiveFailures: 0, totalTrips: 0, lastTool: "", lastError: "" };
      try { state = JSON.parse(fs.readFileSync(stateFile, "utf8")); } catch {}
      try {
        const data = JSON.parse(input);
        state.consecutiveFailures++;
        state.lastTool = data.tool_name || "unknown";
        state.lastError = (data.error || "").slice(0, 200);
        let ctx = "";
        if (state.consecutiveFailures >= 5) {
          state.totalTrips++;
          state.consecutiveFailures = 0;
          ctx = "CIRCUIT BREAKER TRIPPED (" + state.totalTrips + " total). STOP retrying the same approach. Step back, re-read the code, and try a structurally different solution.";
        } else if (state.consecutiveFailures >= 3) {
          ctx = "WARNING: " + state.consecutiveFailures + " consecutive tool failures on " + state.lastTool + ". Consider a different approach before continuing.";
        }
        fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
        if (ctx) {
          process.stdout.write(JSON.stringify({ hookSpecificOutput: { additionalContext: ctx } }));
        }
      } catch {}
      process.exit(0);
    });
  '';

  hookCircuitBreakerReset = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const stateFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
      try {
        const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
        if (state.consecutiveFailures > 0) {
          state.consecutiveFailures = 0;
          fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
        }
      } catch {}
      process.exit(0);
    });
  '';

  hookStopFailure = ''
    #!/usr/bin/env bash
    # Alert on rate limits or API failures
    INPUT=$(cat)
    if echo "$INPUT" | grep -qi "rate.limit\|429\|overloaded"; then
      osascript -e '''display notification "Rate limit hit — pause recommended" with title "Claude Code" sound name "Basso"''' 2>/dev/null || true
    fi
  '';

  # RTK transparent rewrite hook — intercepts Bash tool calls
  # Rewrites command to rtk <command> if rtk is available
  # Claude never sees the rewrite, just gets compressed output
  hookRtkRewrite = ''
    #!/usr/bin/env bash
    INPUT=$(cat)
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

    # Only act on Bash tool calls
    if [ "$TOOL_NAME" != "Bash" ]; then
      echo "$INPUT"
      exit 0
    fi

    # Check rtk available
    if ! command -v rtk >/dev/null 2>&1; then
      echo "$INPUT"
      exit 0
    fi

    # Rewrite high-verbosity commands
    if echo "$COMMAND" | grep -qE "^(git |pnpm |npm |npx |wrangler |tsc |eslint |node |darwin-rebuild |nix build|nix flake)"; then
      NEW_CMD="rtk $COMMAND"
      echo "$INPUT" | jq --arg cmd "$NEW_CMD" '.tool_input.command = $cmd'
      exit 0
    fi

    echo "$INPUT"
  '';
}
