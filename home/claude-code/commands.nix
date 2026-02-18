# Command definitions for Claude Code
{
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

  cmdAuto = ''
    ---
    tools: Skill, Task
    description: "Intelligent workflow routing based on task analysis"
    argument-hint: "<task description>"
    ---

    # Auto: $ARGUMENTS

    ## Decision Logic

    Analyze request and route to best workflow/agent:

    **APEX** (create|add|implement|build|new|feature):
    - Route: `/apex -a -s -t "$ARGUMENTS"`
    - Reason: "Detected feature implementation"

    **DEBUG** (fix|bug|error|broken|failing|crash|why):
    - Route: `/debug -a "$ARGUMENTS"`
    - Reason: "Detected debugging task"

    **RALPH** (refactor all|update every|migrate|batch|standardize):
    - Route: `/ralph-loop "$ARGUMENTS" --max-iterations 20 --completion-promise "DONE"`
    - Reason: "Detected batch operation"

    **AGENT** (where|how does|explain|quick|review):
    - Route: `Task(subagent_type=codebase-navigator)` or specialized agent
    - Reason: "Detected exploration/navigation task"

    ## Steps

    1) Parse $ARGUMENTS for keywords
    2) Match decision matrix (priority: RALPH > DEBUG > APEX > AGENT)
    3) Output: "Routed to [workflow] because [reason]"
    4) Execute with optimal flags

    ## Examples

    Input: "create health check"
    → Routed to /apex because detected "create" keyword
    → Execute: /apex -a -s -t "create health check"

    Input: "fix database timeout"
    → Routed to /debug because detected "fix" keyword
    → Execute: /debug -a "fix database timeout"

    Input: "refactor all imports"
    → Routed to /ralph-loop because detected "refactor all" pattern
    → Execute: /ralph-loop "refactor all imports" --max-iterations 20

    Input: "where is auth logic"
    → Routed to codebase-navigator because detected "where" keyword
    → Execute: Task with codebase-navigator agent
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
  # ── Feature methodology commands (NEW) ──

  commandDiscuss = ''
    Capture implementation decisions before planning a feature.
    Run this BEFORE asking team-lead or architecture-expert to plan.
    Produces a CONTEXT.md that all subsequent agents reference.

    ## Input

    Feature description: $ARGUMENTS

    ## Step 1 — Classify

    Read project CLAUDE.md for domain map, then determine:
    - **Domains:** Which parts of the codebase are touched?
    - **Users:** Which user types affected? Primary device/context?
    - **Complexity:** S (< 5 files, 1 agent) / M (5-15 files, 2-3 agents) / L (15+ files, team-lead waves)
    - **Risk level:** Security-sensitive? Schema migration? Breaking API change? Public-facing?
    - **Existing patterns:** Grep for 2-3 files that solve a similar problem already

    ## Step 2 — Gray Areas

    Based on feature type, surface decisions needed:

    **UI features:** layout approach, interactions, empty states, loading states, responsive breakpoints, which existing primitives to use
    **API features:** response format, error codes, rate limiting, auth level, validation schema shapes
    **Data features:** new tables vs new columns, migration strategy, backward compat, seed data, indexes
    **Real-time features:** transport mechanism, reconnection strategy, offline behavior, optimistic updates
    **Cross-cutting:** shared types to create/modify, new hooks, route registration

    For each gray area: **state the decision, rationale, and project constraint that drove it.**

    ## Step 3 — Anti-Pattern Check

    Read project boundary rules (CLAUDE.md, boundaries, SKILL.md files), then verify:
    - Will planned changes violate any architectural constraints?
    - Will all protected endpoints have auth guards?
    - Will all new code respect runtime constraints?
    - Will design system rules be followed?

    Run any project-specific boundary check commands if they exist.

    ## Step 4 — Dependencies & Execution Order

    List prerequisites:
    1. Schema changes needed first?
    2. New shared types/schemas?
    3. Existing components to modify?
    4. New components/routes to create?
    5. Route registration or config changes?

    ## Step 5 — Risk Mitigation

    For each identified risk:
    - **What could go wrong** (concrete scenario)
    - **Blast radius** (which users/features affected)
    - **Rollback plan** (git revert? migration down? feature flag?)

    ## Output

    Save to `.claude/output/CONTEXT-{slug}.md`:
    ```markdown
    # Feature Context: {name}
    Date: {ISO date}
    ## 1. Classification
    ## 2. Decisions (per gray area)
    ## 3. Anti-Pattern Check (pass/fail)
    ## 4. Dependencies (execution order)
    ## 5. Risks & Rollback
    ## 6. Open Questions (needs user input)
    ## 7. Recommended Next Step
    ```

    Recommended next step based on complexity:
    - S → "Run directly with {agent}: {exact prompt}"
    - M → "Ask architecture-expert to plan from this context"
    - L → "Launch team-lead referencing this context"
  '';

  commandVerifyFeature = ''
    Run 6-layer quality verification on the current feature branch.
    Reads CONTEXT-*.md if available for spec compliance checking.
    Adapts checks to project conventions found in CLAUDE.md and SKILL.md.

    ## Layer 1 — Build
    ```bash
    pnpm typecheck
    pnpm lint --max-warnings 0
    pnpm build
    ```
    Stop and report if any step fails.

    ## Layer 2 — Boundary Violations
    Read project boundary rules from CLAUDE.md and any boundaries command/file.
    Run ALL defined boundary grep checks.
    Report: violations per category (0 = clean).

    ## Layer 3 — Spec Compliance
    If `.claude/output/CONTEXT-*.md` exists for this feature:
    - Read the decisions section
    - Compare against `git diff main --name-only` changed files
    - Score each decision: ✅ implemented / ❌ missing / ⚠️ partial
    If no CONTEXT file: skip this layer, note "no spec to verify against."

    ## Layer 4 — Security
    Check ALL changed files from `git diff main --name-only`:
    - Protected loaders/actions: have auth guards? (read project auth SKILL.md for pattern)
    - Mutations: validate input? (read project validation SKILL.md)
    - No hardcoded secrets: `rg -n "sk-|pk_|secret.*=.*['\"]" <changed-dirs>`
    Report: pass/fail per check with file:line references.

    ## Layer 5 — Design System
    Read project design SKILL.md, then check ALL changed UI files:
    - Design tokens respected (no hardcoded values)
    - CSS framework syntax correct
    - UI primitives used (no raw HTML when wrappers exist)
    - Typography/spacing conventions followed
    Report: violations with file:line references.

    ## Layer 6 — UAT Scenarios
    Generate 3-5 human-testable scenarios based on changed files:
    ```
    ### Scenario N: {name}
    **Role:** {primary user type}
    **Device:** {primary device}
    **Steps:**
    1. Navigate to {route}
    2. {action}
    3. Expect: {visible result}
    **Edge cases:** empty state, error state, slow network
    ```

    ## Final Report
    ```
    ## Verification Report — Branch: {name} — Date: {date}
    1. Build: ✅/❌
    2. Boundaries: {N} violations
    3. Spec Compliance: {X}/{Y} ✅ (or skipped)
    4. Security: {N} issues
    5. Design System: {N} violations
    6. UAT: {N} scenarios generated
    ### Verdict: SHIP / FIX_REQUIRED / BLOCKED
    ### Issues (if any, by severity)
    ```
  '';

  featureChainScript = ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Feature Development Chain — 5 sequential phases, fresh context each
    # Usage:
    #   bash ~/.claude/feature-chain.sh "Add read receipts"
    #   bash ~/.claude/feature-chain.sh "Add CSV export" --skip-discuss
    #   bash ~/.claude/feature-chain.sh "Feature" --plan-only
    #   bash ~/.claude/feature-chain.sh "Feature" --start-phase 4

    FEATURE="''${1:?Usage: bash ~/.claude/feature-chain.sh \"Feature description\" [--flags]}"
    SLUG=$(echo "$FEATURE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 50)
    shift || true

    SKIP_DISCUSS=false
    PLAN_ONLY=false
    START_PHASE=1
    MODEL_OVERRIDE=""

    while [[ $# -gt 0 ]]; do
      case $1 in
        --skip-discuss) SKIP_DISCUSS=true; START_PHASE=$((START_PHASE > 2 ? START_PHASE : 2)); shift ;;
        --plan-only) PLAN_ONLY=true; shift ;;
        --start-phase) START_PHASE="$2"; shift 2 ;;
        --model) MODEL_OVERRIDE="--model $2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
      esac
    done

    OUTDIR=".claude/output/feature/$SLUG"
    mkdir -p "$OUTDIR"

    echo "[$(date +%Y%m%d-%H%M%S)] Feature chain: $FEATURE"
    echo "Output: $OUTDIR | Start: phase $START_PHASE | Plan only: $PLAN_ONLY"

    RULES="RULES: NEVER pause or ask questions. Make best judgment and document uncertainties. If stuck > 2 attempts, skip it, note under SKIPPED, move on. Use Write tool to save output. Be thorough. Read project CLAUDE.md and relevant SKILL.md files before starting."

    # ── PHASE 1: DISCUSS ──
    if [[ $START_PHASE -le 1 ]] && [[ "$SKIP_DISCUSS" == "false" ]]; then
      echo "[$(date +%H:%M:%S)] Phase 1/5: Discuss..."
      claude -p $MODEL_OVERRIDE --dangerously-skip-permissions --max-turns 15 --verbose "$RULES

    Phase 1: context capture. FEATURE: $FEATURE

    Read CLAUDE.md for domain map. Classify (domains, users, complexity S/M/L, risk).
    Surface gray areas per type (UI/API/data/real-time). Run anti-pattern checks per project rules.
    Find 2-3 existing patterns via grep. List dependencies in execution order. Identify risks with rollback.

    Save to $OUTDIR/01-CONTEXT.md. End with: DISCUSS_DONE"
      echo "[$(date +%H:%M:%S)] Phase 1 done."
    fi

    # ── PHASE 2: PLAN ──
    if [[ $START_PHASE -le 2 ]]; then
      echo "[$(date +%H:%M:%S)] Phase 2/5: Plan..."
      CTX=""; [[ -f "$OUTDIR/01-CONTEXT.md" ]] && CTX="First read $OUTDIR/01-CONTEXT.md."
      claude -p $MODEL_OVERRIDE --dangerously-skip-permissions --max-turns 20 --verbose "$RULES

    Phase 2: planning. FEATURE: $FEATURE. $CTX

    Read CLAUDE.md + relevant SKILL.md files. Grep for similar implementations.
    Create atomic task plan in XML: <task id wave agent><n><files><depends><action><verify><done><rollback></task>
    Waves: 1=schema/types 2=server 3=UI 4=integration 5=polish. Max 20 tasks. Branch: feat/$SLUG.

    Save to $OUTDIR/02-PLAN.md. End with: PLAN_DONE"
      echo "[$(date +%H:%M:%S)] Phase 2 done."
    fi

    # ── PHASE 3: REVIEW ──
    if [[ $START_PHASE -le 3 ]]; then
      echo "[$(date +%H:%M:%S)] Phase 3/5: Plan review..."
      claude -p $MODEL_OVERRIDE --dangerously-skip-permissions --max-turns 10 --verbose "$RULES

    Phase 3: plan review. Read $OUTDIR/01-CONTEXT.md (if exists) and $OUTDIR/02-PLAN.md.

    Pass 1 (spec): all CONTEXT decisions covered? Auth guards? User considerations? Boundaries?
    Pass 2 (quality): deps correct? Verify steps sufficient? Agent assignment? Missing tasks? Wave order?

    Save to $OUTDIR/03-PLAN-REVIEW.md. Verdict: APPROVED/NEEDS_AMENDMENTS. End with: REVIEW_DONE"
      echo "[$(date +%H:%M:%S)] Phase 3 done."
      [[ "$PLAN_ONLY" == "true" ]] && echo "=== PLAN COMPLETE ===" && exit 0
    fi

    # ── PHASE 4: EXECUTE ──
    if [[ $START_PHASE -le 4 ]]; then
      echo "[$(date +%H:%M:%S)] Phase 4/5: Execute..."
      claude -p $MODEL_OVERRIDE --dangerously-skip-permissions --max-turns 50 --verbose "$RULES

    Phase 4: execution. Read $OUTDIR/01-CONTEXT.md, $OUTDIR/02-PLAN.md, $OUTDIR/03-PLAN-REVIEW.md.

    1. git checkout -b feat/$SLUG
    2. Execute waves in order. Per task: read SKILL.md refs, implement, run <verify>, atomic commit.
    3. Integration check after each wave: pnpm typecheck && pnpm lint --max-warnings 0
    4. If task fails 3x: SKIP, document under BLOCKED.

    Save to $OUTDIR/04-EXECUTION.md with per-task status + commit SHAs. End with: EXECUTE_DONE"
      echo "[$(date +%H:%M:%S)] Phase 4 done."
    fi

    # ── PHASE 5: VERIFY ──
    if [[ $START_PHASE -le 5 ]]; then
      echo "[$(date +%H:%M:%S)] Phase 5/5: Verify..."
      claude -p $MODEL_OVERRIDE --dangerously-skip-permissions --max-turns 15 --verbose "$RULES

    Phase 5: verification. Read $OUTDIR/01-CONTEXT.md, $OUTDIR/02-PLAN.md, $OUTDIR/04-EXECUTION.md.

    6-layer check:
    1. Build: pnpm typecheck && pnpm lint --max-warnings 0 && pnpm build
    2. Boundaries: run ALL project boundary checks (from CLAUDE.md / boundaries files)
    3. Spec compliance: CONTEXT decisions vs implementation (score each)
    4. Security: auth guards, input validation, no secrets
    5. Design system: read project design SKILL.md, check all changed UI files
    6. UAT: 3-5 testable scenarios per user role

    Verdict: SHIP / FIX_REQUIRED / BLOCKED. If FIX_REQUIRED: include fix plan as task XMLs.

    Save to $OUTDIR/05-VERIFY.md. End with: VERIFY_DONE"
      echo "[$(date +%H:%M:%S)] Phase 5 done."
    fi

    echo ""
    echo "=== FEATURE CHAIN COMPLETE ==="
    echo "Results: $OUTDIR/"
  '';

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

}
