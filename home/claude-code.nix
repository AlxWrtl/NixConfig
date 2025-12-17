{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Target dir managed by this module
  claudeDir = ".claude";

  # -------------------------
  # Global docs / settings
  # -------------------------
  claudeMdText = ''
    # Claude Code — Global Guardrails

    ## Non-negotiables (EN)
    - Be extremely concise (incl. commit messages). Sacrifice grammar for brevity.
    - Read before write. Propose a short plan before any edits.
    - Ask before: write/delete, chmod, sudo, installs, network calls, or large refactors.
    - Never touch secrets: ~/.ssh, ~/.aws, ~/.gnupg, **/.env*, secrets/, *token*, *key*, *cert*.
    - No git add/commit/push unless explicitly asked.
    - Keep diffs minimal. Prefer small, reversible changes.
    - Prefer targeted tests; run full suite only when requested or clearly required.

    ## Official docs + senior standards (GLOBAL)
    - Source of truth: repo docs OR official vendor docs only.
    - If version/spec unclear: STOP + ask me.
    - No WebSearch. WebFetch only if allowed by allowlist.
    - Every code change: Doc ref + Code ref + Verify step.

    ## Style (FR)
    - Réponses courtes et actionnables.
    - Si tu hésites : 2–3 hypothèses max, puis la plus probable.
    - Quand tu modifies du code : quoi / pourquoi / comment vérifier (3 bullets).

    ## Plans
    - End each plan with unresolved questions (if any). Ultra concise.
  '';

  autoRoutingText = ''
    # Auto-Routing (Minimal)

    - Use the most specialized agent for the task.
    - Prefer quick-fix / code-reviewer for small changes.
    - Prefer nix-expert for any *.nix / darwin-rebuild / flakes.
    - If unsure: use codebase-navigator first, then delegate.
  '';

  webGuardScript = ''
    #!/usr/bin/env python3
    import json, sys
    from urllib.parse import urlparse
    from pathlib import Path

    REPO_ALLOWLIST = Path.cwd() / ".claude" / "official-sources.txt"
    GLOBAL_ALLOWLIST = Path.home() / ".claude" / "official-sources.txt"

    def load_rules():
      path = REPO_ALLOWLIST if REPO_ALLOWLIST.exists() else GLOBAL_ALLOWLIST
      if not path.exists():
        return set(), set(), set(), str(path)

      domains, gh_repos, npm_pkgs = set(), set(), set()
      for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
          continue
        line = line.lower()

        if line.startswith("github:"):
          gh_repos.add(line.split("github:", 1)[1].strip("/"))
          continue
        if line.startswith("npm:"):
          npm_pkgs.add(line.split("npm:", 1)[1].strip("/"))
          continue

        # default: domain
        domains.add(line.strip("/"))
      return domains, gh_repos, npm_pkgs, str(path)

    def emit(decision, reason):
      print(json.dumps({
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": decision,
          "permissionDecisionReason": reason,
        }
      }))
      sys.exit(0)

    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}

    if tool == "WebSearch":
      emit("deny", "WebSearch disabled. Use WebFetch with an explicit official-doc URL.")

    if tool != "WebFetch":
      sys.exit(0)

    domains, gh_repos, npm_pkgs, allow_path = load_rules()

    url = tool_input.get("url") or tool_input.get("href") or ""
    p = urlparse(url)
    host = (p.hostname or "").lower()
    path = (p.path or "").strip("/")

    if not host:
      emit("deny", "WebFetch blocked: missing/invalid URL.")

    # 1) Plain domain allowlist (incl. subdomains)
    if any(host == d or host.endswith("." + d) for d in domains):
      emit("allow", f"WebFetch allowed: {host} (from {allow_path})")

    # 2) GitHub strict allow (only specific repos)
    if host == "github.com":
      parts = path.split("/")
      if len(parts) >= 2 and f"{parts[0]}/{parts[1]}".lower() in gh_repos:
        emit("allow", f"WebFetch allowed: github.com/{parts[0]}/{parts[1]} (from {allow_path})")
      emit("deny", f"WebFetch blocked: github.com/{path} not allowlisted (edit {allow_path})")

    # 3) NPM strict allow (only specific packages)
    if host in ("www.npmjs.com", "npmjs.com"):
      parts = path.split("/")
      # /package/<name>
      if len(parts) >= 2 and parts[0] == "package" and parts[1].lower() in npm_pkgs:
        emit("allow", f"WebFetch allowed: npm:{parts[1]} (from {allow_path})")
      emit("deny", f"WebFetch blocked: npm path not allowlisted (edit {allow_path})")

    emit("deny", f"WebFetch blocked: {host} not in allowlist (edit {allow_path})")
  '';

  settingsJson = builtins.toJSON {
    env = {
      npm_config_prefer_pnpm = "true";
      npm_config_user_agent = "pnpm";
      BASH_DEFAULT_TIMEOUT_MS = "300000";
      BASH_MAX_TIMEOUT_MS = "600000";
    };

    model = "sonnet";

    # Keep your tool surface explicit
    allowedTools = [
      "bash"
      "read"
      "write"
      "edit"
      "multiedit"
      "glob"
      "grep"
      "task"
      "websearch"
      "webfetch"
      "notebookedit"
    ];

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
    };

    statusLine = {
      type = "command";
      command = "pnpm dlx ccusage@latest statusline --mode both";
      padding = 0;
    };

    enabledPlugins = {
    };

    alwaysThinkingEnabled = true;

    permissions = {
      deny = [
        "websearch"
        "WebSearch"
      ];
    };

    hooks = {
      PreToolUse = [
        {
          matcher = "WebFetch|WebSearch|webfetch|websearch";
          hooks = [
            {
              type = "command";
              command = "python3 $HOME/.claude/hooks/web_guard.py";
              timeout = 10;
            }
          ];
        }
      ];
    };
  };

  # -------------------------
  # Commands (EN, compact)
  # -------------------------
  cmdTdd = ''
    ---
    allowed-tools: ["bash","read","edit","write","grep","glob","multiedit"]
    description: "TDD loop: write failing test, minimal fix, refactor, verify."
    argument-hint: "<feature>"
    ---

    # TDD: $ARGUMENTS

    1) Identify existing test patterns + target module.
    2) Write a failing test (RED).
    3) Implement the smallest change (GREEN).
    4) Refactor for clarity (still GREEN).
    5) Run targeted tests, then full suite if needed.
    6) Summarize: what changed + how to verify.
  '';

  cmdOptimize = ''
    ---
    allowed-tools: ["bash","read","edit","grep","glob","webfetch","websearch"]
    description: "Profile first, then apply targeted performance fixes."
    argument-hint: "<target>"
    ---

    # Optimize: $ARGUMENTS

    1) Measure current performance (metrics + reproduction steps).
    2) Identify bottleneck (CPU / IO / DB / render / bundle).
    3) Apply 1–2 targeted fixes.
    4) Re-measure and report delta.
    5) Add a regression guard (test, benchmark, or budget).
  '';

  cmdContextPrime = ''
    ---
    allowed-tools: ["read","grep","glob"]
    description: "Quickly map the project: entrypoints, structure, build, tests."
    argument-hint: ""
    ---

    # Context Prime

    - Read repo CLAUDE.md / README.
    - Identify entrypoints, build, test commands.
    - Map key folders and ownership (src/, app/, packages/).
    - Output: short map + next suggested actions.
  '';

  # -------------------------
  # Agents (EN, compact, non-redundant)
  # -------------------------
  agentFrontend = ''
    ---
    name: frontend-expert
    model: claude-sonnet-4-5-20250929
    max_tokens: 3000
    context_limit: 12000
    description: "Frontend work (React/Vue/Angular/TS/CSS). Small diffs, modern patterns."
    tools: ["Read","Write","Edit","Grep","Glob","Bash","WebSearch","WebFetch"]
    ---

    # Frontend Expert

    ## Auto-trigger
    - Files: .jsx .tsx .vue .html .css .scss
    - Keywords: ui, ux, component, react, vue, angular, tailwind, styling, responsive

    ## Output expectations
    - Provide a short plan, then minimal code changes.
    - Prefer accessibility + performance (Core Web Vitals).
    - If a change impacts UX, propose a quick before/after summary.

    ## Guardrails
    - No big refactors unless requested.
    - Follow repo conventions (lint, formatting, structure).
  '';

  agentBackend = ''
    ---
    name: backend-expert
    model: claude-sonnet-4-5-20250929
    max_tokens: 3500
    context_limit: 12000
    description: "Backend/API work (Node/Python). Safe changes, security-first."
    tools: ["Read","Write","Edit","Grep","Glob","Bash","WebSearch","WebFetch"]
    ---

    # Backend Expert

    ## Auto-trigger
    - Files: .py .ts .js .sql .prisma Dockerfile docker-compose.yml
    - Keywords: api, endpoint, auth, database, migration, middleware

    ## Output expectations
    - Keep interfaces stable. Document any breaking changes.
    - Validate inputs. Prefer explicit error handling.
    - Include a quick verify checklist (curl / tests).

    ## Guardrails
    - No auth/security shortcuts.
    - No schema refactors unless requested.
  '';

  agentDatabase = ''
    ---
    name: database-expert
    model: claude-haiku-4-5-20251001
    max_tokens: 2200
    context_limit: 8000
    description: "DB tuning, schema, indexes, queries. Prefer explain/analyze-driven fixes."
    tools: ["Read","Write","Edit","Grep","Bash","WebSearch","WebFetch"]
    ---

    # Database Expert

    ## Auto-trigger
    - Files: .sql migrations/ prisma.schema
    - Keywords: query, index, slow, migration, schema, explain

    ## Output expectations
    - Suggest indexes only with a clear query pattern.
    - Prefer safe migrations (reversible when possible).
    - Provide exact commands to validate (EXPLAIN, tests).

    ## Guardrails
    - Avoid invasive schema rewrites unless asked.
  '';

  agentDevops = ''
    ---
    name: devops-expert
    model: claude-sonnet-4-5-20250929
    max_tokens: 3500
    context_limit: 10000
    description: "CI/CD, Docker, infra changes. Secure + reproducible."
    tools: ["Read","Write","Edit","Grep","Bash","WebSearch","WebFetch"]
    ---

    # DevOps Expert

    ## Auto-trigger
    - Files: .yml .yaml Dockerfile docker-compose.yml .tf
    - Keywords: ci, pipeline, deploy, docker, k8s, terraform

    ## Output expectations
    - Prefer reproducible builds + least privilege.
    - Include rollback/verification steps.
    - Avoid “magic” scripts; keep it explicit.

    ## Guardrails
    - No destructive actions unless requested.
    - No secret exposure in logs or configs.
  '';

  agentAiMl = ''
    ---
    name: ai-ml-expert
    model: claude-sonnet-4-5-20250929
    max_tokens: 4000
    context_limit: 15000
    description: "ML/AI work: training, inference, eval, MLOps. Evidence-driven."
    tools: ["Read","Write","Edit","Grep","Bash","WebSearch","WebFetch"]
    ---

    # AI/ML Expert

    ## Auto-trigger
    - Files: notebooks/, .ipynb, model code, .pt/.onnx/.safetensors
    - Keywords: training, inference, embeddings, evaluation, drift, mlops

    ## Output expectations
    - Start with metrics/eval plan.
    - Prefer simple baselines before complex pipelines.
    - Provide reproducible commands/scripts.

    ## Guardrails
    - Avoid unverifiable claims; tie changes to metrics.
  '';

  agentArch = ''
    ---
    name: architecture-expert
    model: claude-sonnet-4-5-20250929
    max_tokens: 4500
    context_limit: 20000
    description: "System design & architecture. Focus on tradeoffs + small steps."
    tools: ["Read","Grep","Glob"]
    ---

    # Architecture Expert

    ## Auto-trigger
    - Keywords: architecture, refactor, scalability, patterns, system design

    ## Output expectations
    - Present 2–3 options with tradeoffs.
    - Recommend a smallest viable step (incremental migration).
    - Identify risks + rollback strategy.

    ## Guardrails
    - No sweeping rewrites unless requested.
  '';

  agentPerf = ''
    ---
    name: performance-expert
    model: claude-haiku-4-5-20251001
    max_tokens: 2200
    context_limit: 8000
    description: "Performance debugging: measure → fix → measure."
    tools: ["Read","Edit","Grep","Bash","WebSearch","WebFetch"]
    ---

    # Performance Expert

    ## Auto-trigger
    - Keywords: slow, perf, latency, bottleneck, memory, timeout

    ## Output expectations
    - Ask for reproduction steps if missing.
    - Propose profiling first, then 1–2 targeted fixes.
    - Report expected impact + how to verify.

    ## Guardrails
    - No speculative micro-optimizations without measurement.
  '';

  agentNavigator = ''
    ---
    name: codebase-navigator
    model: claude-haiku-4-5-20251001
    max_tokens: 1600
    context_limit: 6000
    description: "Locate files, patterns, and entrypoints quickly."
    tools: ["Grep","Glob","Read","WebSearch","WebFetch"]
    ---

    # Codebase Navigator

    ## Auto-trigger
    - Keywords: where is, locate, find, structure, entrypoint, how does it work

    ## Output expectations
    - Output: (1) likely file paths, (2) why, (3) next command(s) to confirm.
    - Keep it short and navigational.

    ## Guardrails
    - Don’t propose big changes; just map and explain.
  '';

  agentReviewer = ''
    ---
    name: code-reviewer
    model: claude-haiku-4-5-20251001
    max_tokens: 1800
    context_limit: 5000
    description: "Code review: bugs, quality, security, minimal actionable feedback."
    tools: ["Read","Grep","WebSearch","WebFetch"]
    ---

    # Code Reviewer

    ## Auto-trigger
    - Keywords: bug, error, review, security, quality
    - Before commit / after modifications

    ## Output expectations
    - List issues by severity (high/med/low).
    - Provide concrete fixes or diffs suggestions.
    - Call out security pitfalls explicitly.

    ## Guardrails
    - No architecture redesign unless requested.
  '';

  agentQuickFix = ''
    ---
    name: quick-fix
    model: claude-haiku-4-5-20251001
    max_tokens: 900
    context_limit: 3000
    description: "Tiny changes only (< ~5 lines): typos, small edits, quick fixes."
    tools: ["Read","Edit","Grep","Bash"]
    ---

    # Quick Fix

    ## Auto-trigger
    - Keywords: fix, typo, quick, small change
    - Very small diffs

    ## Output expectations
    - One change at a time.
    - Minimal explanation unless asked.

    ## Guardrails
    - Don’t expand scope.
  '';

  agentNix = ''
    ---
    name: nix-expert
    model: claude-haiku-4-5-20251001
    max_tokens: 1500
    context_limit: 4000
    description: "Handle nix-darwin / flakes / *.nix. Small diffs, safe rebuild."
    tools: ["Read","Edit","Bash"]
    ---

    # Nix Expert

    ## Auto-trigger
    - Files: *.nix, flake.nix, modules/
    - Keywords: nix, nix-darwin, home-manager, darwin-rebuild, flake

    ## Approach
    - Prefer small, composable modules.
    - Avoid large refactors unless requested.
    - Explain: What / Why / How to verify.

    ## Verification
    - Provide the exact command(s) to run (darwin-rebuild switch).
    - If risk exists, propose a rollback step.
  '';

in
{
  # -------------------------
  # Zsh convenience
  # -------------------------
  programs.zsh.shellAliases = {
    cc = "claude";
    ccd = "claude /doctor";
    ccv = "claude --version";
    ccro = "claude --plan-mode --read-only";
  };

  programs.zsh.sessionVariables = {
    CLAUDE_CONFIG_DIR = "$HOME/.claude";
    npm_config_prefer_pnpm = "true";
    npm_config_user_agent = "pnpm";
  };

  # -------------------------
  # Write ~/.claude content declaratively
  # -------------------------
  home.file = {
    "${claudeDir}/settings.json" = {
      text = settingsJson;
    };

    "${claudeDir}/CLAUDE.md" = {
      text = claudeMdText;
    };

    "${claudeDir}/auto-routing.md" = {
      text = autoRoutingText;
    };

    # Commands
    "${claudeDir}/commands/tdd.md" = {
      text = cmdTdd;
    };
    "${claudeDir}/commands/optimize.md" = {
      text = cmdOptimize;
    };
    "${claudeDir}/commands/context-prime.md" = {
      text = cmdContextPrime;
    };

    # Agents
    "${claudeDir}/agents/frontend-expert.md" = {
      text = agentFrontend;
    };
    "${claudeDir}/agents/backend-expert.md" = {
      text = agentBackend;
    };
    "${claudeDir}/agents/database-expert.md" = {
      text = agentDatabase;
    };
    "${claudeDir}/agents/devops-expert.md" = {
      text = agentDevops;
    };
    "${claudeDir}/agents/ai-ml-expert.md" = {
      text = agentAiMl;
    };
    "${claudeDir}/agents/architecture-expert.md" = {
      text = agentArch;
    };
    "${claudeDir}/agents/performance-expert.md" = {
      text = agentPerf;
    };
    "${claudeDir}/agents/codebase-navigator.md" = {
      text = agentNavigator;
    };
    "${claudeDir}/agents/code-reviewer.md" = {
      text = agentReviewer;
    };
    "${claudeDir}/agents/quick-fix.md" = {
      text = agentQuickFix;
    };
    "${claudeDir}/agents/nix-expert.md" = {
      text = agentNix;
    };
    "${claudeDir}/hooks/web_guard.py" = {
      text = webGuardScript;
      executable = true;
    };

    "${claudeDir}/official-sources.txt" = {
      text = ''
        # Fallback global allowlist (keep small)
        react.dev
        typescriptlang.org
        nodejs.org
        developers.cloudflare.com
      '';
    };
  };

  # -------------------------
  # Ensure ~/.claude is private (dir perms)
  # -------------------------
  home.activation.claudeCodeDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail
    mkdir -p "$HOME/.claude" "$HOME/.claude/agents" "$HOME/.claude/commands" "$HOME/.claude/hooks"
  '';

  home.activation.claudeCodePerms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    set -euo pipefail
    chmod 700 "$HOME/.claude" "$HOME/.claude/agents" "$HOME/.claude/commands" "$HOME/.claude/hooks"
  '';
}
