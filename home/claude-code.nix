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
    # Auto-Routing + Model Selection

    ## Agent Selection
    - Use most specialized agent for task
    - quick-fix / code-reviewer for small changes
    - nix-expert for *.nix / darwin-rebuild / flakes
    - If unsure: codebase-navigator first, then delegate

    ## Model Selection (Cost Optimization - Claude 4.5)
    ### Haiku 4.5 ($1/$5) - Fast + Cheap
    - Model: claude-haiku-4-5-20251001
    - Agents: quick-fix, code-reviewer, database-expert, performance-expert, codebase-navigator, nix-expert, git-ship
    - Use for: Simple tasks, typos, quick reviews, navigation
    - Extended thinking: Disable (cache efficiency)

    ### Sonnet 4.5 ($3/$15) - Production Quality [DEFAULT]
    - Model: claude-sonnet-4-5-20250929
    - Agents: frontend-expert, backend-expert, devops-expert, ai-ml-expert, architecture-expert
    - Use for: Complex features, refactoring, architecture
    - Extended thinking: Enable for coding/complex tasks

    ### Opus 4.5 ($5/$25) - High Intelligence, More Accessible
    - Model: claude-opus-4-5-20251101
    - Use for: Maximum capability tasks, effort parameter support
    - Reserved for: Explicit requests, critical decisions only

    **Cost savings: 60-70% via intelligent routing**
    **Note**: MCP auto mode enabled by default (v2.1.7+)
  '';

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
      command = "npx ccstatusline@latest";
    };

    enabledPlugins = {
    };

    alwaysThinkingEnabled = true;

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
    tools: Bash, Read, Edit, Write, Grep, Glob, MultiEdit
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
    tools: Bash, Read, Edit, Grep, Glob, WebFetch
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
    tools: Read, Grep, Glob
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
  # APEX Skill
  # -------------------------
  skillApex = ''
    ---
    name: apex
    description: "Systematic implementation using APEX methodology"
    ---

    # APEX: Systematic Implementation

    Flags: -a (auto), -s (save), -e (examine), -t (test), -h (help)

    Steps: 00-init → 01-analyze → 02-plan → 03-prepare → 04-execute → 05-test → 06-examine → 07-polish → 08-document → 09-finish

    Load step files from ~/.claude/skills/apex/steps/
  '';

  apexStep00 = ''
    # APEX Step 0: Initialize
    Set up task context, check git status, create output dir.
  '';

  apexStep01 = ''
    # APEX Step 1: Analyze
    Read files, identify patterns, document requirements.
  '';

  apexStep02 = ''
    # APEX Step 2: Plan
    Propose approaches, break down tasks, identify risks.
  '';

  apexStep03 = ''
    # APEX Step 3: Prepare
    Create branch, install deps, create stubs.
  '';

  apexStep04 = ''
    # APEX Step 4: Execute
    Implement solution following plan.
  '';

  apexStep05 = ''
    # APEX Step 5: Test
    Run tests, verify implementation.
  '';

  apexStep06 = ''
    # APEX Step 6: Examine
    Deep review: security, performance, maintainability.
  '';

  apexStep07 = ''
    # APEX Step 7: Polish
    Clean up code, refine, improve naming.
  '';

  apexStep08 = ''
    # APEX Step 8: Document
    Update docs, README, CHANGELOG.
  '';

  apexStep09 = ''
    # APEX Step 9: Finish
    Final verification, commit, summarize.
  '';

  # -------------------------
  # Debug Skill
  # -------------------------
  skillDebug = ''
    ---
    name: debug
    description: "Systematic debugging workflow"
    ---

    # Debug: Systematic Problem Solving

    Flags: -a (auto), -s (save), -h (help)

    Steps: 01-reproduce → 02-isolate → 03-diagnose → 04-fix → 05-verify

    Load step files from ~/.claude/skills/debug/steps/
  '';

  debugStep01 = ''
    # Debug Step 1: Reproduce
    Confirm problem, document errors, capture logs.
  '';

  debugStep02 = ''
    # Debug Step 2: Isolate
    Narrow down root cause, check recent changes.
  '';

  debugStep03 = ''
    # Debug Step 3: Diagnose
    Add logging, trace execution, identify root cause.
  '';

  debugStep04 = ''
    # Debug Step 4: Fix
    Apply minimal fix, handle edge cases.
  '';

  debugStep05 = ''
    # Debug Step 5: Verify
    Run reproduction, test edge cases, run regression.
  '';

  # -------------------------
  # Continuous Learning V2
  # -------------------------
  skillContinuousLearning = ''
    ---
    name: continuous-learning-v2
    description: "Extract and promote patterns to skills automatically"
    enabled: true
    ---

    # Continuous Learning V2

    Auto-extract patterns from interactions.

    Extraction: min 3 changes, 0.7 confidence
    Promotion: usage threshold 5, auto-generate
    Application: auto-suggest, relevance 0.8, max 3

    Generated skills → ~/.claude/skills/generated/
  '';

  # -------------------------
  # Ralph Wiggum Commands (Modified for direct paths)
  # -------------------------
  cmdRalphLoop = ''
    ---
    description: "Start Ralph Wiggum loop in current session"
    argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
    allowed-tools: ["Bash(~/.claude/scripts/setup-ralph-loop.sh:*)"]
    hide-from-slash-command-tool: "true"
    ---

    # Ralph Loop Command

    Execute the setup script to initialize the Ralph loop:

    ```!
    ~/.claude/scripts/setup-ralph-loop.sh $ARGUMENTS
    ```

    Please work on the task. When you try to exit, the Ralph loop will feed the SAME PROMPT back to you for the next iteration. You'll see your previous work in files and git history, allowing you to iterate and improve.

    CRITICAL RULE: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop, even if you think you're stuck or should exit for other reasons. The loop is designed to continue until genuine completion.
  '';

  cmdCancelRalph = ''
    ---
    description: "Cancel active Ralph loop"
    ---

    # Cancel Ralph Loop

    Removes the Ralph loop state file:

    ```!
    rm -f .claude/ralph-loop.local.md && echo "✓ Ralph loop cancelled"
    ```
  '';

  # -------------------------
  # Memory Bank Command
  # -------------------------
  cmdInitMemoryBank = ''
    ---
    tools: Write, Bash
    description: "Initialize Memory Bank structure in current project"
    argument-hint: ""
    ---

    # Init Memory Bank

    Create .claude/memory structure:

    1) mkdir -p .claude/memory
    2) Create files:
       - project-info.md
       - coding-standards.md
       - team-conventions.md
       - architecture-decisions.md
       - common-commands.md
       - dependencies.md
       - recent-changes.md

    3) Create .claude/CLAUDE.md with quick reference

    Progressive disclosure: load files when needed.
  '';

  # -------------------------
  # Hooks
  # -------------------------
  hookProtectMain = ''
    #!/usr/bin/env node

    module.exports = async (context) => {
      const { exec } = require('child_process');
      const util = require('util');
      const execPromise = util.promisify(exec);

      try {
        const { stdout } = await execPromise('git branch --show-current');
        const currentBranch = stdout.trim();

        if (currentBranch === 'main' || currentBranch === 'master') {
          return {
            block: true,
            message: "Cannot edit on main/master. Create feature branch first."
          };
        }
      } catch (error) {
        return {};
      }

      return {};
    };
  '';

  hookFormatTypescript = ''
    #!/usr/bin/env node

    module.exports = async (context) => {
      const { file } = context;
      const { execSync } = require('child_process');
      const path = require('path');

      if (file && (file.endsWith('.ts') || file.endsWith('.tsx'))) {
        try {
          execSync('which prettier', { stdio: 'pipe' });
          execSync('prettier --write ' + file, { stdio: 'inherit' });
          console.log('✓ Formatted ' + path.basename(file));
        } catch (error) {
          // Prettier not available, skip
        }
      }

      return {};
    };
  '';

  # -------------------------
  # Agents (EN, compact, non-redundant)
  # -------------------------
  agentFrontend = ''
    ---
    name: frontend-expert
    model: sonnet
    description: "Frontend work (React/Vue/Angular/TS/CSS). Small diffs, modern patterns."
    tools: Read, Write, Edit, Grep, Glob, Bash, WebFetch
    permissionMode: default
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
    - Extended thinking enabled for complex component logic.
  '';

  agentBackend = ''
    ---
    name: backend-expert
    model: sonnet
    description: "Backend/API work (Node/Python). Safe changes, security-first."
    tools: Read, Write, Edit, Grep, Glob, Bash, WebFetch
    permissionMode: default
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
    - Extended thinking enabled for complex logic/security.
  '';

  agentDatabase = ''
    ---
    name: database-expert
    model: haiku
    description: "DB tuning, schema, indexes, queries. Prefer explain/analyze-driven fixes."
    tools: Read, Write, Edit, Grep, Bash, WebFetch
    permissionMode: default
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
    model: sonnet
    description: "CI/CD, Docker, infra changes. Secure + reproducible."
    tools: Read, Write, Edit, Grep, Bash, WebFetch
    permissionMode: default
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
    model: sonnet
    description: "ML/AI work: training, inference, eval, MLOps. Evidence-driven."
    tools: Read, Write, Edit, Grep, Bash, WebFetch
    permissionMode: default
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
    model: sonnet
    description: "System design & architecture. Focus on tradeoffs + small steps."
    tools: Read, Grep, Glob, WebFetch
    permissionMode: default
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
    model: haiku
    description: "Performance debugging: measure → fix → measure."
    tools: Read, Edit, Grep, Bash, WebFetch
    permissionMode: default
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
    model: haiku
    description: "Locate files, patterns, and entrypoints quickly."
    tools: Grep, Glob, Read, WebFetch
    permissionMode: default
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
    model: haiku
    description: "Code review: bugs, quality, security, minimal actionable feedback."
    tools: Read, Grep, WebFetch, Write, Edit
    permissionMode: acceptEdits
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
    - Extended thinking disabled for fast reviews.
  '';

  agentQuickFix = ''
    ---
    name: quick-fix
    model: haiku
    description: "Tiny changes only (< ~5 lines): typos, small edits, quick fixes."
    tools: Read, Edit, Grep, Bash
    permissionMode: acceptEdits
    ---

    # Quick Fix

    ## Auto-trigger
    - Keywords: fix, typo, quick, small change
    - Very small diffs

    ## Output expectations
    - One change at a time.
    - Minimal explanation unless asked.

    ## Guardrails
    - Don't expand scope.
    - Extended thinking disabled for speed + cache efficiency.
  '';

  agentNix = ''
    ---
    name: nix-expert
    model: haiku
    description: "Handle nix-darwin / flakes / *.nix. Small diffs, safe rebuild."
    tools: Read, Edit, Bash, WebFetch
    permissionMode: acceptEdits
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

  agentGitShip = ''
    ---
    name: git-ship
    model: haiku
    description: "Commit+push. English msgs. Minimal tokens, explicit changes."
    tools: Bash, Read
    permissionMode: default
    ---

    # Git Ship

    EN only. Ultra concise. Explicit WHAT changed.
    NEVER mention the assistant or authorship.
    Extended thinking disabled for speed.

    Banned in commit msg:
    - "I", "we", "my", "our"
    - "Claude", "AI", "assistant", "ChatGPT"
    - "commit by", "generated", "as requested"

    Style:
    - Impersonal changelog tone.
    - Prefer verbs: Add/Fix/Refactor/Update/Remove.
    - No self-reference, no attribution.

    Format:
    - Title: <type>: <what changed> (<=72)
    - Body: 2-5 bullets, start with "-"

    Steps:
    1) Run:
      - git status --porcelain
      - git diff --stat
      - git diff --cached --stat
      - git diff --name-only
    2) If no changes: say "No changes."
    3) If unstaged exists: ask "Stage all (git add -A)? yes/no"
    4) Propose commit msg (type: feat|fix|chore|refactor|perf|test|docs|ci|build).
      - Before finalizing: ensure no banned words; rewrite if needed.
    5) Only if user says "commit": git commit -m "<title>" -m "<bullets>"
    6) Only if user says "push":
      - if no upstream: git push -u origin HEAD
      - else: git push
    7) End: short SHA + branch.
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
    # Settings base (read-only reference)
    "${claudeDir}/settings-base.json" = {
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
    "${claudeDir}/commands/init-memory-bank.md" = {
      text = cmdInitMemoryBank;
    };
    "${claudeDir}/commands/ralph-loop.md" = {
      text = cmdRalphLoop;
    };
    "${claudeDir}/commands/cancel-ralph.md" = {
      text = cmdCancelRalph;
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
    "${claudeDir}/agents/git-ship.md" = {
      text = agentGitShip;
    };

    # APEX Skill
    "${claudeDir}/skills/apex/SKILL.md" = {
      text = skillApex;
    };
    "${claudeDir}/skills/apex/steps/00-init.md" = {
      text = apexStep00;
    };
    "${claudeDir}/skills/apex/steps/01-analyze.md" = {
      text = apexStep01;
    };
    "${claudeDir}/skills/apex/steps/02-plan.md" = {
      text = apexStep02;
    };
    "${claudeDir}/skills/apex/steps/03-prepare.md" = {
      text = apexStep03;
    };
    "${claudeDir}/skills/apex/steps/04-execute.md" = {
      text = apexStep04;
    };
    "${claudeDir}/skills/apex/steps/05-test.md" = {
      text = apexStep05;
    };
    "${claudeDir}/skills/apex/steps/06-examine.md" = {
      text = apexStep06;
    };
    "${claudeDir}/skills/apex/steps/07-polish.md" = {
      text = apexStep07;
    };
    "${claudeDir}/skills/apex/steps/08-document.md" = {
      text = apexStep08;
    };
    "${claudeDir}/skills/apex/steps/09-finish.md" = {
      text = apexStep09;
    };

    # Debug Skill
    "${claudeDir}/skills/debug/SKILL.md" = {
      text = skillDebug;
    };
    "${claudeDir}/skills/debug/steps/01-reproduce.md" = {
      text = debugStep01;
    };
    "${claudeDir}/skills/debug/steps/02-isolate.md" = {
      text = debugStep02;
    };
    "${claudeDir}/skills/debug/steps/03-diagnose.md" = {
      text = debugStep03;
    };
    "${claudeDir}/skills/debug/steps/04-fix.md" = {
      text = debugStep04;
    };
    "${claudeDir}/skills/debug/steps/05-verify.md" = {
      text = debugStep05;
    };

    # Continuous Learning V2
    "${claudeDir}/skills/continuous-learning-v2/SKILL.md" = {
      text = skillContinuousLearning;
    };

    # Hooks
    "${claudeDir}/hooks/protect-main.js" = {
      text = hookProtectMain;
      executable = true;
    };
    "${claudeDir}/hooks/format-typescript.js" = {
      text = hookFormatTypescript;
      executable = true;
    };
  };

  # -------------------------
  # Ensure ~/.claude is private (dir perms)
  # -------------------------
  home.activation.claudeCodeDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail
    mkdir -p "$HOME/.claude"
    mkdir -p "$HOME/.claude/agents"
    mkdir -p "$HOME/.claude/commands"
    mkdir -p "$HOME/.claude/hooks"
    mkdir -p "$HOME/.claude/plugins"
    mkdir -p "$HOME/.claude/scripts"
    mkdir -p "$HOME/.claude/skills/apex/steps"
    mkdir -p "$HOME/.claude/skills/debug/steps"
    mkdir -p "$HOME/.claude/skills/continuous-learning-v2"
    mkdir -p "$HOME/.claude/skills/generated"
  '';

  home.activation.claudeCodePerms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    set -euo pipefail
    chmod 700 "$HOME/.claude"
    chmod 700 "$HOME/.claude/agents" "$HOME/.claude/commands" "$HOME/.claude/hooks" "$HOME/.claude/skills"
    chmod +x "$HOME/.claude/hooks"/*.js 2>/dev/null || true
  '';

  # -------------------------
  # Merge settings.json (intelligent merge)
  # -------------------------
  home.activation.claudeCodeSettingsMerge = lib.hm.dag.entryAfter [ "claudeCodePerms" ] ''
    set -euo pipefail
    BASE="$HOME/.claude/settings-base.json"
    TARGET="$HOME/.claude/settings.json"

    # If jq not available, fallback to copy
    if ! command -v jq >/dev/null 2>&1; then
      if [ ! -f "$TARGET" ]; then
        cp "$BASE" "$TARGET"
        chmod 600 "$TARGET"
      fi
      exit 0
    fi

    # Intelligent merge: base provides defaults, existing preserves user changes
    # Exception: statusLine from base always wins (managed by nix)
    if [ -f "$TARGET" ] && [ ! -L "$TARGET" ]; then
      # Merge: base * existing, then override statusLine from base
      TMP=$(mktemp)
      BASE_STATUSLINE=$(jq -c '.statusLine' "$BASE")
      jq -s '.[0] * .[1]' "$BASE" "$TARGET" | jq --argjson sl "$BASE_STATUSLINE" '.statusLine = $sl' > "$TMP" && mv "$TMP" "$TARGET"
      chmod 600 "$TARGET"
    else
      # First install: copy base
      rm -f "$TARGET"
      cp "$BASE" "$TARGET"
      chmod 600 "$TARGET"
    fi
  '';

  # -------------------------
  # Install Ralph Wiggum scripts
  # -------------------------
  home.activation.claudeCodeRalphWiggum = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    RALPH_DIR="$HOME/.claude/plugins/ralph-wiggum"
    INSTALL_MARKER="$RALPH_DIR/.installed"

    # Skip if already installed (marker exists)
    if [ -f "$INSTALL_MARKER" ]; then
      # Update symlinks for scripts only
      if [ -d "$RALPH_DIR" ]; then
        mkdir -p "$HOME/.claude/scripts"
        ln -sf "$RALPH_DIR/scripts/setup-ralph-loop.sh" "$HOME/.claude/scripts/setup-ralph-loop.sh"
        chmod +x "$HOME/.claude/scripts/setup-ralph-loop.sh"
      fi
      exit 0
    fi

    echo "Installing Ralph Wiggum scripts..."
    export PATH="${pkgs.curl}/bin:${pkgs.unzip}/bin:$PATH"

    # Download plugin from GitHub
    mkdir -p "$RALPH_DIR"
    TMP_DIR=$(mktemp -d)

    cd "$TMP_DIR"
    curl -sL https://github.com/anthropics/claude-code/archive/refs/heads/main.zip -o repo.zip
    unzip -q repo.zip

    # Copy ALL files including hidden ones
    shopt -s dotglob
    cp -R claude-code-main/plugins/ralph-wiggum/* "$RALPH_DIR/"

    # Create install marker
    touch "$INSTALL_MARKER"

    # Symlink scripts only (commands managed by nix)
    mkdir -p "$HOME/.claude/scripts"
    ln -sf "$RALPH_DIR/scripts/setup-ralph-loop.sh" "$HOME/.claude/scripts/setup-ralph-loop.sh"
    chmod +x "$HOME/.claude/scripts/setup-ralph-loop.sh"

    # Cleanup
    cd - > /dev/null
    rm -rf "$TMP_DIR"

    echo "✓ Ralph Wiggum scripts installed"
  '';

}
