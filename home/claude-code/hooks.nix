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

  # Turns the APEX routing rule from advice into enforcement. The
  # UserPromptSubmit reminder is text: it is read and then skipped. Measured on
  # 2026-08-08 — 6 file-modifying tasks in one session, APEX invoked on 2.
  #
  # Fires at most ONCE per session: after APEX runs, its Skill call is in the
  # transcript and every later edit passes. That is what keeps the cost of a
  # hard deny acceptable.
  #
  # FAIL-OPEN on any error, unlike protect-main and block-main-bash. This is a
  # workflow hook, not a safety one: a missed APEX costs little, a session
  # where no edit can land costs a lot.
  hookRequireApex = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const fs = require("fs");
      const path = require("path");
      const { execSync } = require("child_process");
      try {
        const data = JSON.parse(input);

        // Plan mode never writes.
        if (data.permission_mode === "plan") process.exit(0);

        const filePath = data.tool_input && data.tool_input.file_path;
        if (!filePath) process.exit(0);
        const resolved = path.resolve(filePath);

        // Memory writes are not project work.
        if (/\/\.claude\/projects\/[^/]+\/memory\//.test(resolved)) process.exit(0);

        // Outside any git repo — scratchpad, /tmp, $TMPDIR. Not project work.
        try {
          execSync("git rev-parse --is-inside-work-tree", {
            cwd: path.dirname(resolved), stdio: "pipe"
          });
        } catch { process.exit(0); }

        // Match the structured Skill call, never the word "apex": a
        // conversation that merely discusses APEX would match a bare grep.
        const t = data.transcript_path;
        if (!t || !fs.existsSync(t)) process.exit(0);
        const body = fs.readFileSync(t, "utf8");
        if (body.indexOf("\"name\":\"Skill\",\"input\":{\"skill\":\"apex\"") !== -1) process.exit(0);

        const reason = "BLOCKED: this edit modifies a project file and APEX has not run "
          + "in this session. Invoke the apex skill first — nothing to type: the Mode Gate "
          + "routes a trivial change to economy on its own. "
          + "Fires once per session; every edit after APEX starts passes.";
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

  # Rewrites APEX's flags before it starts, from risk signals in the task text.
  #
  # The mode gate picks flags from prose, before anything is known about the
  # change — and a typed flag wins over the mode default. Measured on
  # 2026-08-08: `-e` was typed on 3 of 3 invocations, under-powering 2 of them
  # (a 45-rule rewrite and a blocking hook both ran in economy).
  #
  # Rule: a typed flag is a FLOOR, never a ceiling. A risk signal can only
  # raise the tier. `-e` is the one flag that lowers depth, so it is the one
  # flag stripped. Uppercase disables the user typed on purpose are preserved.
  #
  # False positives are the intended failure direction: a task that merely
  # mentions "settings" runs more thoroughly than needed. Cheap. The reverse
  # is not.
  #
  # FAIL-OPEN: any error leaves the call untouched.
  hookApexFlags = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      try {
        const data = JSON.parse(input);
        const ti = data.tool_input || {};
        if (ti.skill !== "apex") process.exit(0);

        const args = typeof ti.args === "string" ? ti.args : "";
        // `nix`, `flake` and `rebuild` were in STANDARD and had to go: in a
        // nix-darwin config repo every task names a .nix file, so they matched
        // everything and made the trivial tier unreachable. Measured against
        // the real briefs of 2026-08-08 — a two-line CLAUDE.md edit escalated
        // to -b -s -t -pr purely because the path contained "claude-md.nix".
        // A signal that fires on every task is not a signal.
        const HIGH = /(hook|settings|permission|sandbox|deny|secret|credential)/i;
        const STANDARD = /(supprime|delete|remove|\brm\b|migration|\bmaster\b|\bmain\b|\bprod\b)/i;

        let target;
        // Branch and save left the flag surface: both are mode invariants now,
        // so the tiers only carry what is still a real flag.
        if (HIGH.test(args)) target = ["-t", "-x", "-pr"];
        else if (STANDARD.test(args)) target = ["-t", "-pr"];
        else process.exit(0);

        // Leading tokens that look like flags; everything after is the task.
        const parts = args.trim().split(/\s+/);
        let i = 0;
        while (i < parts.length && /^-[a-zA-Z0-9]+$/.test(parts[i])) i++;
        const typed = parts.slice(0, i);
        const rest = parts.slice(i).join(" ");

        // Drop -e: it is the only flag that lowers depth.
        const kept = typed.filter(f => f !== "-e");

        // Add what is missing, but never override an explicit uppercase OFF.
        for (const f of target) {
          const off = "-" + f.slice(1).toUpperCase();
          if (kept.indexOf(f) === -1 && kept.indexOf(off) === -1) kept.push(f);
        }

        const next = (kept.join(" ") + " " + rest).trim();
        if (next === args.trim()) process.exit(0);

        process.stdout.write(JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: { skill: ti.skill, args: next }
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
      const path = require("path");
      const os = require("os");
      try {
        const data = JSON.parse(input);
        const cmd = (data.tool_input && data.tool_input.command) || "";
        // Branch-per-change workflow: create a branch BEFORE editing code, then
        // push that branch — never master/main. commit/push/merge/rebase while on
        // master/main are all hard-denied. Bringing code to master = a manual PR
        // step by the user on GitHub, never a Claude action.
        // Global options may sit between `git` and the verb, so `git -C <dir>
        // commit` must match too — the narrower /git\s+(commit|...)/ let every
        // `git -C ... commit` through, on master included.
        //
        // The verb has to be the FIRST word after those options, not merely
        // somewhere after `git`: a looser form read `git stash push` as a push
        // and denied it on master. Any subcommand whose second word is a
        // watched verb has the same shape (`git remote add`, `git bundle
        // create`, ...).
        //
        // Alternation order is load-bearing: `-C <path>` and `-c <k=v>` take a
        // separate argument, so they must be tried BEFORE the generic option
        // branch — that branch would otherwise consume `-C` alone and leave the
        // path sitting where the verb is expected, reopening the `git -C <dir>
        // commit` hole.
        if (!/\bgit(\s+(-[Cc]\s+\S+|--?[A-Za-z][\w-]*(=\S+)?))*\s+(commit|push|merge|rebase)\b/.test(cmd)) process.exit(0);
        // Check the branch of the repo the COMMAND targets, not the session cwd.
        // `git -C <dir>` and a leading `cd <dir> &&` both retarget it; reading
        // the session cwd blocked legitimate commits in another repo, and let
        // `cd /elsewhere && git commit` through when the cwd was not a repo.
        // Unresolvable target falls back to cwd, so ambiguity fails closed.
        let dir = process.cwd();
        const viaC = cmd.match(/git\s+-C\s+("[^"]+"|'[^']+'|[^\s;&|]+)/);
        const viaCd = cmd.match(/(?:^|&&|;|\|\|)\s*cd\s+("[^"]+"|'[^']+'|[^\s;&|]+)/);
        const raw = (viaC && viaC[1]) || (viaCd && viaCd[1]);
        if (raw) {
          let p = raw.replace(/^["']/, "").replace(/["']$/, "");
          if (p === "~" || p.startsWith("~/")) p = path.join(os.homedir(), p.slice(1));
          const candidate = path.resolve(process.cwd(), p);
          try {
            execSync("git rev-parse --is-inside-work-tree",
              { cwd: candidate, stdio: "pipe" });
            dir = candidate;
          } catch {}
        }
        try {
          execSync("git rev-parse --is-inside-work-tree", { cwd: dir, stdio: "pipe" });
        } catch { process.exit(0); }
        const branch = execSync("git branch --show-current",
          { cwd: dir, encoding: "utf8" }).trim();
        if (branch === "main" || branch === "master") {
          const reason = "BLOCKED: on " + branch + ". Create a branch first: git checkout -b <type>/<desc> (e.g. feat/auth-redirect). Merge to master happens via PR on GitHub.";
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

  # UserPromptSubmit: stdout is injected into the turn's context. Kept to one
  # short line because this cost is paid on EVERY prompt. Unconditional by
  # design: keyword-matching the prompt would miss exactly the ambiguous cases
  # where the reminder matters most, and a false negative is the failure mode
  # that actually hurts (the rule silently not firing).
  hookApexReminder = ''
    #!/usr/bin/env bash
    echo "Routage: fichier modifié → /apex. Modes: trivial=éco | diagnosis=-x | standard=-t -pr | haut-enjeu=-t -x -pr (branch+save = invariants). Options: -q clarif | -f tests-first | -2 divergence | -p prémisses | -k découpage | -v recherche | -o vault | -n note. Majuscule désactive. Question sans modification → réponse directe."
    exit 0
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
        const files = diff.split("\n")
          .filter(f => /\.(ts|tsx|js|jsx)$/.test(f))
          // CLI scripts legitimately use console.log (progress output and
          // machine-readable results parsed by test harnesses). ESLint already
          // ignores scripts/** — keep the quality gate consistent.
          .filter(f => !/(^|\/)scripts\//.test(f))
          // Generated declaration files (wrangler types → worker-configuration.d.ts,
          // worker-secrets.d.ts) carry vendor console.log/any — not our code.
          .filter(f => !/\.d\.ts$/.test(f));
        if (files.length === 0) { process.exit(0); return; }
        // Blocking anti-patterns only (CLAUDE.md non-negotiables). TODO/HACK/FIXME
        // are legitimate work markers — do NOT block the Stop on them.
        const patterns = [
          { re: /console\.log\(/g, msg: "console.log in production code" },
          { re: /:\s*any\b/g, msg: "TypeScript 'any' type" },
          { re: /\balert\s*\(/g, msg: "alert() call" },
          { re: /\bconfirm\s*\(/g, msg: "confirm() call" },
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
          // exit 2 BLOCKS the Stop and feeds stderr back to the model so it fixes
          // the anti-patterns before finishing (Stop hooks have no additionalContext).
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

  # Complements the native `rtk hook claude`: the native hook only rewrites
  # rtk's built-in command list, NOT commands covered by custom filters.toml
  # entries (verified 2026-07). This rewrites the nix commands our user-global
  # filters handle. Disjoint from the native list — no double-rewrite possible.
  hookRtkNixRewrite = ''
    #!/usr/bin/env bash
    INPUT=$(cat)
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

    [ "$TOOL_NAME" = "Bash" ] || exit 0
    command -v rtk >/dev/null 2>&1 || exit 0

    # Simple commands only (compound/for/pipe lines won't match) — never double-wrap
    if echo "$COMMAND" | grep -qE '^(nix-instantiate|nixfmt) '; then
      echo "$INPUT" | jq '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = "rtk " + .command)}}'
    fi
    exit 0
  '';
}
