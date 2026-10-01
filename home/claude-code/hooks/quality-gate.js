#!/usr/bin/env node
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input); // malformed -> throw -> exit 0
    if (!data || typeof data !== "object") { process.exit(0); return; }
    // Loop guard: a Stop already blocked once re-runs with stop_hook_active;
    // blocking again would spin the session.
    if (data.stop_hook_active) { process.exit(0); return; }
    // The repository is the one the session says it is in, not whatever
    // directory the host launched the hook from.
    if (typeof data.cwd === "string" && data.cwd !== "") process.chdir(data.cwd);
    // Only check if we are in a git repo with changes
    const diff = execSync("git diff --name-only HEAD 2>/dev/null || true", { encoding: "utf8", timeout: 3000 }).trim();
    if (!diff) { process.exit(0); return; }
    // git prints names relative to the worktree root, not to cwd.
    const root = execSync("git rev-parse --show-toplevel 2>/dev/null || true", { encoding: "utf8", timeout: 3000 }).trim();
    if (!root) { process.exit(0); return; }
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
        const content = fs.readFileSync(path.join(root, file), "utf8");
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
