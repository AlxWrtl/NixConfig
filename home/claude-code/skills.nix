# Skill definitions
let
  # Shared template blocks for DRY skill authoring
  contract = { expects, produces, sideEffects ? "none" }: ''

    ## Input/Output Contract
    - **Expects:** ${expects}
    - **Produces:** ${produces}
    - **Side effects:** ${sideEffects}
  '';

  scope = { useWhen, notFor }: ''

    ## Scope
    - **Use this skill when:** ${useWhen}
    - **Do NOT use for:** ${notFor}
  '';

  handoffs = items: ''

    ## Handoffs
'' + builtins.concatStringsSep "\n" (map (i: "    - ${i}") items) + "\n";
in
{
  # =========================================================================
  # APEX Workflow — Orchestrator + 16 Step Files
  # Progressive disclosure: each step is loaded conditionally by flag/task, not
  # read linearly. Splitting keeps the context window lean (a public good), it is
  # NOT about "recency". Effort is set per-step, not globally.
  # =========================================================================

  skillApex = ''
    ---
    name: apex
    description: "Universal task workflow (APEX methodology) — EVERY task that modifies files routes through APEX, any size or type: feature, endpoint, module, dashboard, fix, bug, refactor, config. The internal mode gate adapts (economy inline for trivial, full analyze → plan → execute → validate otherwise). Fable plans and verifies, Opus executes. Not for pure questions or research with zero file modification."
    ---

    # APEX: Systematic Implementation Workflow

    A structured multi-step workflow: analyze → plan → execute → validate.
    - Read each step's file ONLY when you reach it AND its flag is active.
    - Skip steps whose flags are off, because loading them wastes context.
    - Consult `steps/ROUTING.md` for every transition so routing stays in one place.
    - Unless `-e`, act as COORDINATOR per `steps/ORCHESTRATION.md`: spawn each
      phase as a fresh subagent and keep only its summary, so context stays clean.
    - Model routing (ORCHESTRATION.md): Fable orchestrates and verifies, Opus
      implements — every spawn passes an explicit `model`, never inherit.

    ## Effort per step

    Effort is per-step, not global. High: 01-analyze, 02-plan, 05-examine. Low:
    branch, save, 03-execute, run-tests, finish. Medium: the rest. Each step file
    restates its effort at the top.

    ## Available Flags

    | Flag | Disable | Description |
    |------|---------|-------------|
    | -a | -A | Auto — skip confirmations |
    | -x | -X | Examine — adversarial review |
    | -s | -S | Save — persist outputs |
    | -t | -T | Test — create + run tests |
    | -e | -E | Economy — no subagents |
    | -b | -B | Branch — git branch |
    | -pr | -PR | PR — commit + PR (implies -b) |
    | -k | -K | Tasks — dependency breakdown |
    | -m | -M | Teams — parallel exec (implies -k) |
    | -v | -V | Verify — research plan online |
    | -o | -O | Obsidian — load vault notes |
    | -n | -N | Note — session note at end |
    | -i | | Interactive — flag menu |
    | -r | | Resume — continue previous |

    ## Common Usage

    ```
    /apex add feature              # Basic
    /apex -a -t -pr add endpoint   # Auto + tests + PR
    /apex -e simple fix            # Economy (save tokens)
    ```

    ## Execution

    Execute `steps/step-00-init.md` now: read the file and follow it.

    Verify any nix-config changes this workflow produces with:

    ```bash
    nix-instantiate --parse file.nix && sudo darwin-rebuild switch --flake .#alex-mbp
    ```

    ${contract {
      expects = "task description with optional flags. Example: /apex -a -x implement user auth";
      produces = "complete implementation through progressive steps: init → analyze → plan → execute → validate (+ optional: tests, examine, resolve, finish).";
      sideEffects = "modifies source files, optionally creates tests, commits, creates PRs.";
    }}
    ${scope {
      useWhen = "EVERY task that modifies files, in any project, any size — the mode gate adapts (economy inline for trivial, debugger-as-implementer for bugs, full orchestration otherwise).";
      notFor = "Pure questions or research with zero file modification → answer directly, no workflow.";
    }}

    ## Error handling

    - If a step fails (blocked task, red build/tests): stop, surface the raw error
      and failing criteria, never fabricate success or push past red checks.
    - If a prerequisite is missing (no git repo, no test framework): warn and fall
      back (manual verification / skip the gated step), do not silently swallow.
    - Unknown flag → reject it and print the valid flag list.

    ## Idempotency, deps & compatibility

    - **Idempotent**: safe to re-run; `-r` resumes from the last incomplete step,
      and git branch/commit steps are no-ops when already applied.
    - **Requires git** for branch/PR steps; needs node or python only when the
      target project does. Alternatively runs read-only if absent.
    - **Namespaced** under `apex/`: step files and `.claude/output/apex/` outputs;
      no global names leak.
    - **Compatibility**: minimum version is any model supporting the `effort` param.

    ${handoffs [
      "Diagnosis stays INSIDE apex — execute phase spawns the debugger agent (model: opus)."
      "If scope is unclear → run /discuss first, then return to apex."
      "After tests fail repeatedly → debugger agent (model: opus) inside the execute phase."
      "After finish on L/XL changes → code-reviewer agent (model: fable) for the final pass."
    ]}
  '';

  # --- Step 00: Init ---
  apexStep00Init = ''
    # Step 00: Initialize
    <!-- effort: medium -->

    YOU ARE THE COORDINATOR, not an executor. Do NOT do the analysis or coding
    yourself. Unless `-e` (economy) is set, you spawn each phase as a fresh
    subagent and keep only its summary — read [ORCHESTRATION.md](ORCHESTRATION.md)
    now and follow it for every phase. Under `-e`, run phases inline as before.

    Privileged commands: `sudo` and `darwin-rebuild` go to the "Run yourself"
    list (long or password-interactive). Sandbox-blocked commands (`git push`
    over SSH, docker, local DB): retry ONCE with dangerouslyDisableSandbox —
    the permission box lets the user approve or refuse. Never weaken the
    sandbox config itself. See the classification rule in ORCHESTRATION.md.

    ## Parse Flags

    Extract flags from $ARGUMENTS. Default: all flags OFF.
    - If `-pr` is set, auto-enable `-b` (branch)
    - If `-m` is set, auto-enable `-k` (tasks)
    - Uppercase flag disables (e.g., `-A` disables auto)

    ## Session model guard (run FIRST — the 1000% rule)

    The coordinator MUST run on Fable 5 — Fable writes the detailed briefs and
    Fable verifies. Check the session model (system context states it). If the
    session is NOT on Fable: STOP and tell the user to run `/model fable`, then
    re-invoke apex. Sole approved fallback when Fable is unavailable on the
    plan: `opus[1m]` — state the substitution explicitly, never substitute
    silently.

    ## Mode Gate (run BEFORE anything else — NEVER redirect out of APEX)

    Every task runs through APEX. The gate picks the MODE, not whether:
    - **Trivial** — one sentence, ≤ ~2 files, < ~20 lines: auto-enable `-e`
      (economy). Fable still writes the precise brief and still verifies the
      real diff before finishing — the verify duty NEVER drops.
    - **Diagnosis** — bug / error / crash / broken: analyze phase reproduces
      the error first; execute phase spawns the debugger agent (`model: opus`)
      as implementer. Stays inside APEX.
    - **Pure research / no file change**: analyze phase only (Explore fan-out),
      report findings, skip execute/validate.
    - **Standard / complex**: full orchestration per ORCHESTRATION.md.

    State the chosen mode in the init summary and record it in state below.

    ## Force external memory (unless economy)

    If NOT `-e`: enable `-s` automatically. Fresh-context-per-phase relies on the
    on-disk summary chain to survive compaction and `-r` resume, so saving is not
    optional here — run [step-00b-save.md](step-00b-save.md) even if `-s` was not
    passed. This is the other half of the orchestration mechanism.

    ## Initialize State

    Record the following:
    - **Task**: the user's request (everything after flags)
    - **Flags**: which flags are active
    - **Working directory**: current project path
    - **Git status**: current branch, clean/dirty, uncommitted changes

    ## Present Summary

    Display a compact summary:
    ```
    APEX initialized
    Task: {description}
    Flags: {active flags}
    Branch: {current branch}
    Status: {clean/dirty}
    ```

    ## Conditional Sub-Steps

    Execute these in order, ONLY if the corresponding flag is active:

    1. If `-i` (interactive): Read [step-00b-interactive.md](step-00b-interactive.md) and execute it.
    2. If `-b` or `-pr`: Read [step-00b-branch.md](step-00b-branch.md) and execute it.
    3. If `-e` (economy): Read [step-00b-economy.md](step-00b-economy.md) and execute it.
    4. If `-s` (save): Read [step-00b-save.md](step-00b-save.md) and execute it.
    5. If `-r` (resume): Look for saved state in `.claude/output/apex/` and restore context. Skip to the last incomplete step.
       If `-o` was active AND resumed step is >= 02 AND `-s` was set: re-read `.claude/output/apex/{task-id}/01b-obsidian-context.md` to restore vault context.
       If `-o` was active but `-s` was not: warn the user that Obsidian context was lost and offer to re-run step-01b.

    Note: `-o` and `-n` are NOT init-time sub-steps.
    - `-o` fires at end of step-01-analyze (loads vault BEFORE planning).
    - `-n` fires at terminal steps (04/05/06/08/09) to write a session note.

    ## Next Step

    Read [step-01-analyze.md](step-01-analyze.md) and execute it.
  '';

  # --- Step 00b: Interactive ---
  apexStep00bInteractive = ''
    # Step 00b: Interactive Configuration

    Present all available flags to the user as a toggle menu.
    Use AskUserQuestion to let them enable/disable each flag.

    Display current flag state and let user toggle:
    ```
    Current flags:
    [ ] -a  Auto (skip confirmations)
    [ ] -x  Examine (adversarial review)
    [ ] -s  Save (persist outputs)
    [ ] -t  Test (create + run tests)
    [ ] -e  Economy (no subagents)
    [ ] -b  Branch (create git branch)
    [ ] -pr Pull Request (commit + PR)
    [ ] -k  Tasks (task breakdown)
    [ ] -m  Teams (parallel execution)
    [ ] -o  Obsidian context (load vault)
    [ ] -n  Obsidian note (create session note)
    ```

    After user confirms, update the active flags and return to step-00-init flow.
  '';

  # --- Step 00b: Branch ---
  apexStep00bBranch = ''
    # Step 00b: Branch Setup

    1. Check current branch. If already on a feature branch, use it.
    2. If on main/master, create a new branch:
       - Name format: `feat/{task-id}` where task-id is a short slug from the task description
       - `git checkout -b feat/{task-id}`
    3. Confirm branch is ready.

    Return to step-00-init flow.
  '';

  # --- Step 00b: Economy ---
  apexStep00bEconomy = ''
    # Step 00b: Economy Mode Override

    ECONOMY MODE ACTIVE. These 6 rules override ALL subsequent steps:

    1. **No subagents.** Never use the Agent tool. Use Glob, Grep, Read directly.
    2. **No parallel exploration.** Explore sequentially, one file at a time.
    3. **Minimal scope.** Read only files directly relevant to the task.
    4. **Skip optional steps.** If examine (-x) is also set, do a self-review checklist instead of launching review agents.
    5. **No TodoWrite.** Track progress mentally, don't create formal todo lists.
    6. **Concise outputs.** Shorter summaries, no detailed analysis documents.

    These rules save ~70% tokens. Apply them to every subsequent step.

    Return to step-00-init flow.
  '';

  # --- Step 00b: Save ---
  apexStep00bSave = ''
    # Step 00b: Save Mode Setup

    Create output directory for this task:
    ```
    .claude/output/apex/{task-id}/
    ```

    Where `{task-id}` is a zero-padded sequential number + short slug (e.g., `01-user-auth`).

    Create initial context file:
    ```
    .claude/output/apex/{task-id}/00-context.md
    ```

    With content:
    ```markdown
    # APEX: {task description}
    Date: {current date}
    Flags: {active flags}
    Branch: {branch name}

    ## Progress
    | Step | Status | Notes |
    |------|--------|-------|
    | 00-init | complete | |
    | 01-analyze | pending | |
    | 02-plan | pending | |
    | 03-execute | pending | |
    | 04-validate | pending | |
    ```

    After each step completes, update this progress table.

    Return to step-00-init flow.
  '';

  # --- Step 01: Analyze ---
  apexStep01Analyze = ''
    # Step 01: Analyze
    <!-- effort: high -->

    YOU ARE AN EXPLORER, not a planner. Do NOT plan or implement yet.
    Your only job is to deeply understand the codebase and the task.

    ## Who runs this (per ORCHESTRATION.md)

    - **Economy (`-e`)**: the coordinator runs this inline, no subagents.
    - **Default**: the COORDINATOR does the parallel Explore fan-out itself
      (a phase agent cannot spawn — depth=1), collects the bounded Explore
      summaries, then either synthesizes directly or spawns one analyzer agent
      with those summaries as input. Return the analyze phase summary schema.

    ## Strategy

    Evaluate task complexity across 4 dimensions:
    - **Scope**: how many files/modules affected?
    - **Libraries**: unfamiliar dependencies?
    - **Patterns**: existing conventions to follow?
    - **Uncertainty**: unclear requirements?

    ### If economy mode is active:
    Use Glob and Grep directly. Read only the most relevant files. No agents.

    ### If economy mode is NOT active (coordinator-orchestrated):
    The coordinator launches parallel Explore agents, count scaled to scope:
    - 1-2 files: 1-2 agents
    - 3-5 files: 3-5 agents
    - 6+ files: 5-10 agents

    Each agent explores a different aspect:
    - File structure and conventions
    - Existing patterns and utilities
    - Related components and dependencies
    - Test patterns (if -t flag active)

    **Each agent must return a condensed, distilled summary (~1-2k tokens):
    files, conventions, risks — NOT raw file dumps.** Their bounded summary is
    what enters your context; do not paste full file contents back.

    ## Output

    Document your findings:
    - **Requirements**: what exactly needs to be built
    - **Affected files**: list of files to create/modify
    - **Conventions**: patterns to follow (naming, structure, imports)
    - **Dependencies**: libraries, utilities, types to use
    - **Risks**: potential issues or unknowns

    ## Conflicts & Constraints (REQUIRED — confront task vs codebase)

    This is what makes step-01 analysis, not just exploration. You MUST fill every
    bullet. Write "none found" only after actually looking — never leave blank:
    - **Constraining patterns**: existing conventions/architecture that constrain
      HOW this must be built (e.g. "all DB access goes through repo layer X").
    - **Divergences**: where the task as asked would break or contradict an
      existing pattern — name the file/pattern and the conflict.
    - **Decisions needed from user**: ambiguities that change the design and that
      you cannot resolve from the codebase. If any exist and `-a` is NOT set,
      surface them before planning.
    - **Out-of-scope temptations**: nearby things that look broken but are NOT
      this task — list them so the plan does not creep into them.

    ## If save mode (-s):
    Write findings to `.claude/output/apex/{task-id}/01-analyze.md`

    ## Next Step

    If obsidian mode (-o) is active:
      Read [step-01b-obsidian-context.md](step-01b-obsidian-context.md) and execute it.
    Else:
      Read [step-02-plan.md](step-02-plan.md) and execute it.
  '';

  # --- Step 01b: Obsidian Context Load ---
  apexStep01bObsidianContext = ''
    # Step 01b: Obsidian Context Load

    YOU ARE A CONTEXT GATHERER, not a planner. Do NOT plan or implement yet.
    Your job is to load project knowledge from the Obsidian vault so APEX stays aligned
    with what the user already knows/decided about this project.

    ## Vault

    Root: `~/Documents/AlxVault`

    ## Process

    1. **Load global conventions** — Read `00-Meta/CLAUDE.md` (if exists) for vault-wide rules.

    2. **Detect project name** in this priority order:
       a. Explicit hint in task description: `project X`, `projet X`, or `--project X`.
       b. Current working directory basename, lowercased and kebab-cased.
       Keep both the normalized slug (for folder/file matching) and the original display casing.
       Example: `/Users/alx/.config/nix-darwin` → slug `nix-darwin`.

    3. **Find the project note** (case-insensitive match):
       - `Glob` `02-Projets/*/*.md`, filter where folder-name matches slug (case-insensitive)
         OR file stem matches slug.
       - 0 matches → report "no project note found for '{slug}'" and suggest creating it via `-n` at the end. Skip to step-02.
       - 1 match → use it.
       - 2+ matches → use `AskUserQuestion` to let the user pick; do NOT silently pick a "closest match".

    4. **Read the project note** — extract:
       - Current goals / status
       - Architecture decisions already made
       - Open questions / known issues
       - Links to sub-notes (decisions, sessions, etc.)

    5. **Scan recent sessions** — `Glob` pattern: `02-Projets/[project]/sessions/*.md`
       - Read the 3 most recent session notes (by filename date `YYYY-MM-DD`)
       - Extract: decisions, next steps, blockers, context that informs the current task

    6. **Scan decisions** (if folder exists) — `Glob` pattern: `02-Projets/[project]/decisions/*.md`
       - Read titles + summaries only (do NOT modify files in `decisions/`)

    ## Output — Context Report

    Produce a compact report:

    ```
    ## Obsidian Context — {project}

    ### Project note: [[02-Projets/{project}/{project}]]
    {1-3 line summary of current project state}

    ### Recent sessions
    - [[02-Projets/{project}/sessions/YYYY-MM-DD - title]] — {key takeaway}
    - [[02-Projets/{project}/sessions/YYYY-MM-DD - title]] — {key takeaway}

    ### Relevant decisions
    - [[02-Projets/{project}/decisions/slug]] — {one-liner}

    ### Implications for current task
    - {how this context changes/informs the plan}
    - {constraints or prior choices to respect}
    - {any conflict between the task and prior decisions — flag it}
    ```

    ## Rules

    - Read-only. Do NOT write to the vault in this step (that's step-09b).
    - Never modify `decisions/` files.
    - If no project note exists, say so and suggest creating one via `-n` flag at the end.
    - Use full-path wikilinks always: `[[02-Projets/Project/Project]]`.

    ## If save mode (-s):
    Target file: `.claude/output/apex/{task-id}/01b-obsidian-context.md`.
    - If file absent → `Write` with the full context report.
    - If file present → `Edit` to append `\n\n## Run {ISO-timestamp}\n\n{report}`.

    ## Merge into Analysis

    Feed the "Implications for current task" section into the Step 01 findings so the
    subsequent plan (Step 02) reflects the vault knowledge.

    ## Next Step

    Read [step-02-plan.md](step-02-plan.md) and execute it.
  '';

  # --- Step 02: Plan ---
  apexStep02Plan = ''
    # Step 02: Plan

    YOU ARE A PLANNER, not an implementer. Do NOT write any code yet.

    Per ORCHESTRATION.md: unless `-e`, the coordinator spawns this as a fresh
    planner agent whose input is the analyze phase summary (not the raw
    transcript). Return the plan phase summary schema and persist the plan.

    ## ULTRA THINK

    Before writing the plan, mentally simulate the entire implementation:
    - Walk through every file you'll create or modify
    - Consider the order of changes (what depends on what)
    - Identify where things could go wrong
    - Think about edge cases the user didn't mention

    ## Create Implementation Plan

    Produce a structured plan with:

    1. **Tasks** — numbered, ordered by dependency:
       ```
       T1: Create types/interfaces in types.ts
       T2: Add database migration
       T3: Implement API endpoint (depends on T1, T2)
       T4: Create UI component (depends on T1)
       T5: Wire up route (depends on T3, T4)
       ```

    2. **Acceptance Criteria** — specific, verifiable conditions:
       ```
       AC1: User can create a new item via the form
       AC2: Validation errors display inline
       AC3: Success redirects to the list page
       ```

    3. **Testing Strategy** (if -t flag active):
       ```
       - Unit tests for validation logic
       - Integration test for API endpoint
       - Component test for form submission
       ```

    4. **Risks & Mitigations**

    ## Create TodoWrite Checklist

    Convert tasks into a TodoWrite checklist. Only ONE todo can be in_progress at a time.

    ## If tasks mode (-k) or teams mode (-m):
    Read [step-02b-tasks.md](step-02b-tasks.md) and execute it before proceeding.

    ## User Approval

    If auto mode (-a) is NOT active:
    - Present the complete plan
    - Ask the user if they want to modify anything
    - Wait for approval before proceeding

    If auto mode (-a) IS active:
    - Display the plan briefly
    - Proceed automatically

    ## Next Step

    Consult [ROUTING.md](ROUTING.md): if `-v` go to 02c-verify, else apply the
    EXECUTE selector (`-m` → 03-execute-teams, else → 03-execute).
  '';

  # --- Step 02c: Verify Plan ---
  apexStep02cVerify = ''
    # Step 02c: Verify Plan

    YOU ARE A RESEARCHER, not an implementer. Do NOT write any code yet.
    Your job is to verify that the plan from step-02 is based on correct, up-to-date information.

    ## Process

    For each major technical decision in the plan, verify it against current reality:

    1. **APIs & Libraries**: WebSearch for the latest docs of any library/framework used.
       - Is the API still current? Has it been deprecated?
       - Are there newer/better alternatives?
       - Check version compatibility.

    2. **Patterns & Best Practices**: WebSearch for current recommended patterns.
       - Is the proposed pattern still the recommended approach?
       - Has the framework/tool introduced a better way since your training cutoff?
       - Check official docs, not just blog posts.

    3. **Configuration & Syntax**: If touching config files (nix, tsconfig, eslint, etc.):
       - WebFetch the official documentation page
       - Verify option names, types, and default values
       - Check if options have been renamed, removed, or deprecated

    4. **Security**: If the plan involves auth, crypto, or sensitive data:
       - Verify the recommended approach hasn't changed
       - Check for known CVEs in proposed dependencies

    ## How to Research

    - Use WebSearch for broad questions ("nextjs 15 best practices server actions 2026")
    - Use WebFetch for specific doc pages (official docs URLs)
    - Launch parallel research agents if multiple topics need verification (unless economy mode)
    - Focus on OFFICIAL sources: framework docs, GitHub repos, RFCs — not Medium articles

    ## Output

    For each item verified, report:
    ```
    ✅ {item} — confirmed correct ({source})
    ⚠️ {item} — outdated, recommended: {new approach} ({source})
    ❌ {item} — wrong/deprecated, must change: {correction} ({source})
    ```

    ## If issues found:
    Update the plan and TodoWrite checklist to reflect corrections.
    If not in auto mode (-a), present changes for user approval.

    ## If save mode (-s):
    Write verification results to `.claude/output/apex/{task-id}/02c-verify.md`

    ## Next Step

    Consult [ROUTING.md](ROUTING.md) → apply the EXECUTE selector
    (`-m` → 03-execute-teams, else → 03-execute).
  '';

  # --- Step 02b: Tasks ---
  apexStep02bTasks = ''
    # Step 02b: Task Decomposition

    Break the plan into individual task files with a dependency graph.

    For each task, create a structured entry:
    ```
    Task: T{n} — {name}
    Files: {files to create/modify}
    Depends: {T1, T2, ...} or none
    Agent: {suggested agent type}
    Instructions: {specific implementation details}
    Verify: {how to verify this task is done}
    ```

    Order tasks by dependency — tasks with no dependencies first.
    Group independent tasks into waves for parallel execution.

    ```
    Wave 1: T1, T2 (no deps — can run in parallel)
    Wave 2: T3, T4 (depend on wave 1)
    Wave 3: T5 (depends on wave 2)
    ```

    Return to step-02-plan flow.
  '';

  # --- Step 03: Execute ---
  apexStep03Execute = ''
    # Step 03: Execute
    <!-- effort: low — mechanical; the thinking happened in 01/02 -->

    YOU ARE AN IMPLEMENTER following a plan, not a designer.
    Do NOT deviate from the plan. Do NOT add features that weren't planned.

    Per ORCHESTRATION.md: unless `-e`, your input is the plan phase summary +
    the persisted plan path. With `-m` (teams) the coordinator spawns the
    implementer agents per wave directly (see step-03-execute-teams). Return the
    execute phase summary schema.

    Before the first edit, re-check the "Conflicts & Constraints" from step-01:
    if implementation reveals a conflict that was missed, STOP and revise the
    plan — do not silently work around it.

    ## Process

    Work through the TodoWrite checklist one task at a time:

    1. Mark the current todo as `in_progress`
    2. Read the target file (if modifying an existing file)
    3. Implement the changes for this task
    4. Verify the change works (no syntax errors, imports resolve)
    5. Mark the todo as `completed`
    6. Move to the next todo

    ## Rules

    - ONE todo in_progress at a time
    - Follow the conventions identified in Step 01
    - Reuse existing utilities and patterns — don't reinvent
    - If you encounter something unexpected, note it but stay on plan
    - If a task is blocked, skip it and note the blocker

    ## If save mode (-s):
    Update progress in `.claude/output/apex/{task-id}/00-context.md`

    ## Next Step

    Read [step-04-validate.md](step-04-validate.md) and execute it.
  '';

  # --- Step 03: Execute Teams ---
  apexStep03ExecuteTeams = ''
    # Step 03: Execute (Teams Mode)

    YOU ARE A TEAM LEAD coordinating parallel implementation.

    ## Agent Teams Execution

    Using the wave structure from step-02b-tasks:

    1. For each wave, spawn implementer subagents in parallel using the Agent tool
    2. Each agent gets:
       - The specific task(s) assigned to them
       - Full context from step-01 analysis
       - The conventions to follow
    3. Wait for all agents in a wave to complete before starting the next wave
    4. After each wave, verify integration between the pieces

    ## Coordination Rules

    - Each agent works on separate files — no conflicts
    - If an agent encounters a blocker, it reports back
    - After all waves complete, do a quick integration check

    ## Next Step

    Read [step-04-validate.md](step-04-validate.md) and execute it.
  '';

  # --- Step 04: Validate ---
  apexStep04Validate = ''
    # Step 04: Validate

    YOU ARE A VALIDATOR, not an implementer. Do NOT add new features.

    Per ORCHESTRATION.md: unless `-e`, the coordinator spawns this as a fresh
    validator agent whose input is the plan + execute phase summaries. Return the
    validate phase summary schema.

    ## Verification Checklist

    1. **Acceptance Criteria**: go through each AC from the plan.
       For each one, verify it is actually implemented. Check the code.

    2. **Build Check**: run only the SAFE checks (see ORCHESTRATION.md):
       - TypeScript: typecheck (`pnpm typecheck` or `npx tsc --noEmit`)
       - Lint: `pnpm lint` or equivalent
       - Build: `pnpm build` or equivalent
       - Nix: `nix-instantiate --parse` (safe). Do NOT run `darwin-rebuild
         build`/`switch` — those are privileged; mark such ACs **deferred to
         user** and add the command to the "Run yourself" list.

    3. **Integration Check**: verify that:
       - All imports resolve
       - No circular dependencies introduced
       - Types are consistent across boundaries

    4. **Quick Smoke Test**: if there's a dev server, verify it starts without errors

    ## If any AC is not met:
    Go back and fix it. Do not proceed until all ACs pass.

    ## If save mode (-s):
    Update progress in context file.

    ## Next Step

    Apply the shared terminal router in [ROUTING.md](ROUTING.md) (this is
    04-validate → rule 1 `-t` is in play).
  '';

  # --- Step 05: Examine ---
  apexStep05Examine = ''
    # Step 05: Examine

    YOU ARE A SKEPTICAL REVIEWER, not a defender of this code.
    Your job is to find problems, not to validate the implementation.

    ## Adversarial Code Review

    Launch 3 parallel code-reviewer agents, each with a different focus:

    ### Agent 1: Security Review
    - Authentication/authorization gaps
    - Input validation missing
    - Data exposure in responses
    - SQL injection, XSS, CSRF risks
    - Secrets or credentials in code

    ### Agent 2: Logic Review
    - Race conditions
    - Null/undefined edge cases
    - Error handling gaps
    - Off-by-one errors
    - State management issues
    - Missing error boundaries

    ### Agent 3: Clean Code Review
    - Naming consistency
    - Dead code
    - Unnecessary complexity
    - Missing type safety
    - Convention violations (from step-01 analysis)

    ### If economy mode (-e):
    Do NOT launch agents. Instead, go through each review dimension yourself
    as a self-review checklist. Be thorough but use no subagents.

    ## Collect Findings

    Aggregate all findings and sort by severity:
    - **Critical**: security vulnerabilities, data loss risks
    - **Important**: logic bugs, error handling gaps
    - **Minor**: naming, style, minor improvements

    ## Next Step

    Apply the shared terminal router in [ROUTING.md](ROUTING.md): Critical/Important
    findings trigger rule 3 (→ 06-resolve); otherwise fall through to pr/note/COMPLETE.
  '';

  # --- Step 06: Resolve ---
  apexStep06Resolve = ''
    # Step 06: Resolve

    YOU ARE A RESOLVER. Fix the findings from the examination step.

    ## Process

    ### If auto mode (-a):
    Automatically fix all Critical and Important findings.
    Skip Minor findings unless they're trivial to fix.

    ### If NOT auto mode:
    Present findings to the user grouped by severity.
    For each finding, ask:
    - **Fix**: apply the fix
    - **Skip**: acknowledge but don't fix
    - **Discuss**: need more context

    ## After Fixing

    Re-run any build/lint checks to ensure fixes didn't break anything.

    ## If save mode (-s):
    Write resolution summary to output file.

    ## Next Step

    Apply the shared terminal router in [ROUTING.md](ROUTING.md) (resolve done →
    rules 2/3 skipped; falls through to pr/note/COMPLETE).
  '';

  # --- Step 07: Tests ---
  apexStep07Tests = ''
    # Step 07: Tests

    YOU ARE A TEST ENGINEER, not an implementer.

    ## Analyze Test Patterns

    Before writing any tests:
    1. Find existing test files in the project (Glob for `**/*.test.*`, `**/*.spec.*`, `**/__tests__/**`)
    2. Read 2-3 existing tests to understand:
       - Test framework (Jest, Vitest, Playwright, etc.)
       - Naming conventions
       - Setup/teardown patterns
       - Assertion style
       - Mock patterns

    ## Create Tests

    Based on the acceptance criteria from step-02:
    1. Write unit tests for pure logic/utilities
    2. Write integration tests for API endpoints/data flow
    3. Write component tests for UI (if applicable)

    Follow the EXISTING test patterns exactly. Don't introduce new testing paradigms.

    ## Rules

    - Each test should be independent
    - Use descriptive test names that explain the behavior
    - Test edge cases, not just happy paths
    - Mock external dependencies, not internal ones

    ## Next Step

    Read [step-08-run-tests.md](step-08-run-tests.md) and execute it.
  '';

  # --- Step 08: Run Tests ---
  apexStep08RunTests = ''
    # Step 08: Run Tests

    ## Test Loop

    Execute the test runner and iterate until all tests pass.

    ```
    Attempt 1/10:
    1. Run the test command (pnpm test, npm test, vitest, etc.)
    2. If all pass → proceed to next step
    3. If failures:
       a. Read the error output carefully
       b. Identify the root cause (test bug vs implementation bug)
       c. Fix the issue
       d. Go to attempt N+1
    ```

    **Maximum 10 attempts.** If tests still fail after 10 attempts:
    - Present the remaining failures to the user
    - Ask for guidance
    - Do NOT loop forever

    ## Next Step

    Apply the shared terminal router in [ROUTING.md](ROUTING.md), skipping rule 1
    (`-t` already consumed).
  '';

  # --- Step 09: Finish ---
  apexStep09Finish = ''
    # Step 09: Finish

    ## If teams were used (-m):
    Ensure all team agents have completed and shut down cleanly.

    ## Git Operations

    1. **Stage changes**: `git add` all modified/created files
    2. **Commit**: use conventional commit format
       - `feat: {description}` for new features
       - `fix: {description}` for bug fixes
       - Include a body with key changes if the diff is large
    3. **Push**: `git push -u origin {branch-name}`

    ## Create Pull Request

    Use `gh pr create` with:
    - **Title**: conventional format matching the commit
    - **Body**: structured with:
      - ## Summary (what was done)
      - ## Changes (bullet list of key changes)
      - ## Testing (how it was tested)
      - ## Acceptance Criteria (checklist from plan)

    ## If NOT auto mode:
    Show the PR title and body for approval before creating.

    ## COMPLETE

    Present final summary:
    ```
    APEX Complete
    Branch: {branch}
    Commit: {hash}
    PR: {url}
    Steps completed: {list}
    ```

    ## Next Step — Obsidian Note

    # INVARIANT: when both -pr and -n are set, steps 04/05/06/08 route to step-09
    # FIRST (pr takes precedence), so this tail is the ONLY path to step-09b in that case.
    # Do not remove this check without restoring -n branches in predecessors.
    If note mode (-n) is active:
      Read [step-09b-obsidian-note.md](step-09b-obsidian-note.md) and execute it.
  '';

  # --- Step 09b: Obsidian Session Note ---
  apexStep09bObsidianNote = ''
    # Step 09b: Obsidian Session Note

    YOU ARE A SCRIBE. Create a session note in the Obsidian vault capturing what was done,
    decisions taken, and next steps — following the Alx vault conventions.

    ## Vault

    Root: `~/Documents/AlxVault`

    ## Process

    ### 1. Resolve project

    - Reuse the project name (both slug and display form) detected in step-01b if `-o` was active.
    - Otherwise detect in this order:
      a. Explicit hint in task description (`project X`, `projet X`, `--project X`).
      b. cwd basename, normalized to kebab-case lowercase slug.
    - `Glob` `02-Projets/*/` (case-insensitive compare) to confirm the folder exists.
    - If 0 folders match:
      - In auto mode (-a): create `02-Projets/{display-name}/` and a minimal `{display-name}.md` stub.
      - Otherwise: `AskUserQuestion` — pick an existing project from the list, or confirm creation of a new one.
    - If 2+ folders match (casing variants or aliases): `AskUserQuestion` to pick; do NOT silently pick the first.

    ### 2. Build the filename

    Format: `YYYY-MM-DD - {slug}.md`
    - `YYYY-MM-DD` — today's date (absolute, not relative)
    - `{slug}` — short kebab-case summary of the task (max ~50 chars)

    Target path: `02-Projets/{project}/sessions/{filename}`

    ### 3. Avoid duplicates

    `Glob` `02-Projets/{project}/sessions/{date}*.md`. For each match, extract the slug
    (portion after ` - ` and before `.md`) and compare to the current slug:

    - **Exact slug match** → `Edit` the existing note: append a new section
      `## Mise a jour {HH:MM}` with the new content. Do NOT overwrite previous sections.
    - **Different slug** → `Write` the new file at `02-Projets/{project}/sessions/{filename}`.
    - **Race (target path already exists after Write check)** → suffix the slug with
      `-2`, `-3`, ... until the path is unique, then `Write`.
    - NEVER `Write` to an existing path without the suffix-disambiguation check.

    ### 4. Write the note

    Template (respect Alx conventions strictly):

    ```markdown
    ---
    date: {YYYY-MM-DD}
    type: session
    project: "[[02-Projets/{project}/{project}|{project}]]"
    tags:
      - session
      - apex
      - {project-slug}   # kebab-case, lowercase, ASCII only — safe for YAML
    aliases:
      - "{YYYY-MM-DD} {Short subject}"
    ---
    [[02-Projets/{project}/{project}|{project}]]

    # {YYYY-MM-DD} - {Short subject}

    ## Contexte
    {1-3 lines: why this session happened, what triggered it}

    ## Ce qui a ete fait
    - {bullet 1}
    - {bullet 2}
    - {...}

    ## Fichiers modifies
    - `path/to/file.ext` — {one-line reason}
    - `path/to/other.ext` — {one-line reason}

    ## Decisions
    - **{Decision title}** — {rationale}
      - Alternatives ecartees : {option B} parce que {raison}

    ## Prochaines etapes
    - [ ] {next action 1}
    - [ ] {next action 2}

    ## Liens
    - Branche : `{branch-name}`
    - Commit : `{hash}` (si -pr ou commit cree)
    - PR : {url} (si -pr)
    - Notes liees :
      - [[02-Projets/{project}/sessions/YYYY-MM-DD - previous|session precedente]] (si pertinent)
      - [[02-Projets/{project}/decisions/slug|decision]] (si une decision formelle a ete prise)
    ```

    ### 5. Rules to respect (Obsidian 2026 conventions)

    - **Typed frontmatter** — uses Obsidian Properties UI format:
      - `date:` as YAML date (typed), `type: session` for Bases filtering
      - `project:` as a **link property** `"[[full-path|alias]]"` so Bases can query sessions by project
      - `tags:` as a YAML **list** (one per line with `  - `), NEVER prefixed with `#` inside YAML (invalidates the tag)
      - `aliases:` as a list for alternate search names
    - **Absolute wikilinks with alias pipe** — `[[02-Projets/Preliz/Preliz|Preliz]]` (robust + readable). Absolute paths prevent ambiguity when generating programmatically; alias keeps display clean.
    - **Project-note wikilink on first line after frontmatter** — maintains Alx convention for quick navigation
    - **No orphan links** — Grep to verify every `[[...]]` target exists OR clearly flag as `(a creer)`
    - **French content** — the vault is in French per Alx conventions
    - **Do NOT modify `decisions/` files** — only link to them
    - **Do NOT restructure `01-Inbox/` content**

    References (cite only if user asks why):
    - Obsidian Properties: https://help.obsidian.md/properties
    - Obsidian YAML: https://help.obsidian.md/Advanced+topics/YAML+front+matter

    ### 6. Update the project note (optional, auto only)

    If in auto mode (-a), append a line to `02-Projets/{project}/{project}.md` under a
    `## Sessions` section (create the section if missing) with the new wikilink:

    ```markdown
    - [[02-Projets/{project}/sessions/YYYY-MM-DD - slug]] — {one-liner}
    ```

    If the note is already up-to-date or the section structure differs, skip this step
    rather than forcing a structure the user didn't set up.

    ## If save mode (-s):
    Also copy the note content to `.claude/output/apex/{task-id}/09b-obsidian-note.md`
    (local mirror for traceability).

    ## Output

    Report:
    ```
    Obsidian session note created
    Path: 02-Projets/{project}/sessions/{filename}
    Wikilink: [[02-Projets/{project}/sessions/{filename-without-ext}]]
    ```

    ## Next Step

    **COMPLETE.** This is a terminal step — no further chaining.
  '';

  # -------------------------
  # Feature Workflow Skill
  # -------------------------
  skillFeatureWorkflow = ''
    ---
    name: feature-workflow
    description: Feature development methodology — discuss→plan→verify cycle. Referenced by code-reviewer and the /discuss + /verify-feature commands.
    globs: ["**/.claude/output/feature/**", "**/.claude/output/CONTEXT-*"]
    effort: high
    ---

    # Feature Development Methodology

    ## When to Use What

    | Complexity | Files | Approach | Command |
    |-----------|-------|----------|---------|
    | S (trivial) | < 5 | Single agent directly | quick-fix or specialist agent |
    | M (medium) | 5-15 | Discuss → plan → execute | /discuss → /apex |
    | L (large) | 15+ | Full chain (5 phases) | feature-chain.sh or /apex -m |
    | XL (epic) | 30+ | Split into L milestones | Chain per milestone |

    ## The 5-Phase Cycle

    ```
    DISCUSS → PLAN → REVIEW → EXECUTE → VERIFY
      (why)   (what)  (check)   (do)     (prove)
    ```

    1. **DISCUSS** — classify, surface gray areas, capture decisions → CONTEXT.md
    2. **PLAN** — research patterns, create atomic task XMLs in waves → PLAN.md
    3. **REVIEW** — two-pass (spec compliance + plan quality) → PLAN-REVIEW.md
    4. **EXECUTE** — wave-by-wave, atomic commits, integration checks → EXECUTION.md
    5. **VERIFY** — 6 layers (build, boundaries, spec, security, design, UAT) → VERIFY.md

    ## Task XML Format

    ```xml
    <task id="T1" wave="1" agent="backend-expert">
      <n>Short descriptive name</n>
      <files>path/to/file.ts (CREATE|MODIFY)</files>
      <depends>none</depends>
      <action>Precise instructions with SKILL.md refs</action>
      <verify>pnpm typecheck && pnpm lint --max-warnings 0</verify>
      <done>Success criteria</done>
      <rollback>How to undo</rollback>
    </task>
    ```

    ## Wave Ordering
    1. Schema + migrations + shared types
    2. Server logic (queries, actions, validation)
    3. UI components + hooks
    4. Route integration + wiring
    5. Polish (a11y, mobile, edge cases)

    ## Common Pitfalls
    1. Skipping DISCUSS for L features → rework when assumptions wrong
    2. Not reading project SKILL.md → agents repeat known mistakes
    3. Executing without review → circular deps or missing tasks
    4. Manual commits during chain → breaks atomic tracking

    ${contract {
      expects = "feature description + complexity assessment (S/M/L/XL). Optional: existing project CLAUDE.md.";
      produces = "CONTEXT.md (DISCUSS), PLAN.md + task XMLs (PLAN), PLAN-REVIEW.md (REVIEW), EXECUTION.md (EXECUTE), VERIFY.md (VERIFY).";
      sideEffects = "creates .claude/output/feature/{slug}/ directory with phase artifacts.";
    }}
    ${scope {
      useWhen = "M/L/XL features needing structured planning (5+ files, multi-agent, or >1 day work)";
      notFor = "Quick fixes (<20 lines), pure debugging, single-file edits, or anything classified S complexity";
    }}
    ${handoffs [
      "If task is S complexity → route directly to quick-fix or relevant specialist agent instead"
      "After DISCUSS phase → hand off to the Plan agent (or /apex step 02) for PLAN creation"
      "After PLAN phase → hand off to code-reviewer for two-pass REVIEW before EXECUTE"
      "After EXECUTE phase → hand off to code-reviewer for VERIFY (6-layer check)"
      "If XL epic → split into L milestones first, run full cycle per milestone"
    ]}
  '';

  # --- Eval suite: scored by `uvx schliff` (triggers/quality/edges) ---
  apexEvalSuite = ''
    {
      "triggers": [
        {"prompt": "implement this using apex methodology", "should_trigger": true},
        {"prompt": "use the apex framework for this feature", "should_trigger": true},
        {"prompt": "/apex add authentication to the app", "should_trigger": true},
        {"prompt": "run apex with -a flag to auto-implement the payment module", "should_trigger": true},
        {"prompt": "apex -s to save the output for the new dashboard feature", "should_trigger": true},
        {"prompt": "apex -x -t -pr build the export endpoint", "should_trigger": true},
        {"prompt": "fix this bug in the login form", "should_trigger": false},
        {"prompt": "what does this function do?", "should_trigger": false},
        {"prompt": "run the tests and tell me what fails", "should_trigger": false},
        {"prompt": "review this PR for code quality", "should_trigger": false},
        {"prompt": "explain how the caching layer works", "should_trigger": false},
        {"prompt": "rename a single variable in utils.ts", "should_trigger": false}
      ],
      "test_cases": [
        {
          "name": "step-00-initialize",
          "prompt": "Start apex for adding a new user settings page. We are at step 00.",
          "assertions": [
            {"type": "contains", "value": "git status", "description": "Step 00 must check git status before starting"},
            {"type": "contains", "value": "Flags", "description": "Step 00 must parse and record active flags"},
            {"type": "excludes", "value": "implement", "description": "Step 00 must not start implementing — only initialize"},
            {"type": "pattern", "value": "00|[Ii]nitializ", "description": "Must explicitly reference step 00 initialization"}
          ]
        },
        {
          "name": "complexity-gate-trivial",
          "prompt": "apex -a rename the variable x to userId in one function in utils.ts",
          "assertions": [
            {"type": "pattern", "value": "[Gg]ate|[Tt]rivial|[Oo]verkill|one sentence", "description": "Must apply the complexity gate before any work"},
            {"type": "pattern", "value": "quick.fix|[Dd]irect", "description": "Must redirect a one-line rename out of APEX to quick-fix"},
            {"type": "excludes", "value": "step-02-plan", "description": "Must not proceed into planning for a trivial task"}
          ]
        },
        {
          "name": "complexity-gate-debug",
          "prompt": "apex -a the login button is broken and throws an error on click",
          "assertions": [
            {"type": "pattern", "value": "[Gg]ate|[Dd]iagnos|[Dd]ebug", "description": "Must detect a diagnosis task at the complexity gate"},
            {"type": "pattern", "value": "/debug|debug", "description": "Must redirect bug/diagnosis tasks to /debug"}
          ]
        },
        {
          "name": "step-01-conflict-analysis",
          "prompt": "apex analyze adding a direct DB call in the controller for a new report feature. We are at step 01.",
          "assertions": [
            {"type": "pattern", "value": "[Cc]onflict|[Cc]onstraint", "description": "Step 01 must produce the Conflicts & Constraints section"},
            {"type": "pattern", "value": "[Dd]iverg|[Pp]attern", "description": "Must flag where the task diverges from existing patterns"},
            {"type": "pattern", "value": "[Dd]ecision|[Ss]cope", "description": "Must surface decisions needed and out-of-scope temptations"},
            {"type": "excludes", "value": "raw file dump", "description": "Subagents must return bounded summaries, not raw dumps"}
          ]
        },
        {
          "name": "full-execution-flow",
          "prompt": "Execute all apex steps (-a flag) for adding email notifications. Run every step.",
          "assertions": [
            {"type": "contains", "value": "00", "description": "Must execute step 00 Initialize"},
            {"type": "contains", "value": "01", "description": "Must execute step 01 Analyze"},
            {"type": "contains", "value": "03", "description": "Must execute step 03 Execute"},
            {"type": "contains", "value": "Finish", "description": "Must reach the Finish step"},
            {"type": "pattern", "value": "[Aa]nalyze|[Pp]lan|[Ee]xecute|[Vv]alidate", "description": "Must name each major phase in sequence"}
          ]
        },
        {
          "name": "apex-auto-flag",
          "prompt": "apex -a implement the CSV export feature",
          "assertions": [
            {"type": "contains", "value": "auto", "description": "Must acknowledge -a flag enables auto mode"},
            {"type": "pattern", "value": "[Ss]tep\\s*0[0-9]", "description": "Must reference step numbers during execution"},
            {"type": "excludes", "value": "wait for approval", "description": "Auto mode must not pause for manual approval at each step"}
          ]
        },
        {
          "name": "apex-examine-flag",
          "prompt": "apex -x build a token refresh endpoint then review it for security issues",
          "assertions": [
            {"type": "contains", "value": "05", "description": "Examine flag (-x) routes to step 05, not 06"},
            {"type": "pattern", "value": "[Ee]xamine|[Ss]ecurity|[Ll]ogic|[Cc]lean", "description": "Must run the three adversarial review focuses in step 05"},
            {"type": "excludes", "value": "step 00", "description": "Examine must not restart from step 00"}
          ]
        },
        {
          "name": "per-step-effort",
          "prompt": "Which apex steps use high reasoning effort and which use low?",
          "assertions": [
            {"type": "pattern", "value": "[Hh]igh.*0?1|[Aa]nalyze.*high", "description": "Analysis/plan/examine steps must use high effort"},
            {"type": "pattern", "value": "[Ll]ow.*03|[Mm]echanical", "description": "Mechanical steps (execute/branch/finish) must use low effort"},
            {"type": "excludes", "value": "effort: high", "description": "Effort must be per-step, not a single global frontmatter value"}
          ]
        }
      ],
      "edge_cases": [
        {
          "name": "trivial-task-overkill",
          "category": "minimal",
          "prompt": "apex -a add a missing semicolon in index.ts",
          "expected_behavior": "Complexity gate flags APEX as overkill and redirects to quick-fix or a direct edit.",
          "assertions": [
            {"type": "pattern", "value": "[Oo]verkill|[Tt]rivial|[Gg]ate|quick.fix", "description": "Must flag APEX as inappropriate for a one-char change"},
            {"type": "pattern", "value": "[Rr]ecommend|[Ss]uggest|[Dd]irect", "description": "Must recommend a lighter-weight path"}
          ]
        },
        {
          "name": "diagnosis-task",
          "category": "redirect",
          "prompt": "apex why is the app crashing on startup?",
          "expected_behavior": "Complexity gate detects a diagnosis task and redirects to /debug instead of running the workflow.",
          "assertions": [
            {"type": "pattern", "value": "[Dd]iagnos|[Dd]ebug|crash", "description": "Must detect diagnosis and redirect to /debug"}
          ]
        },
        {
          "name": "missing-conventions",
          "category": "missing",
          "prompt": "apex -a implement OAuth but this project has no documented conventions",
          "expected_behavior": "Analyze step documents the absence of conventions as a risk in Conflicts & Constraints and proceeds with explicit assumptions.",
          "assertions": [
            {"type": "pattern", "value": "[Cc]onvention|[Aa]ssumption|[Rr]isk", "description": "Must document missing conventions as a constraint/risk"},
            {"type": "pattern", "value": "[Pp]roceed|[Ww]arn", "description": "Must proceed with stated assumptions, not block"}
          ]
        },
        {
          "name": "task-conflicts-with-pattern",
          "category": "invalid",
          "prompt": "apex add a feature that bypasses the existing repository layer and queries the DB directly",
          "expected_behavior": "Step 01 Conflicts & Constraints flags the divergence from the repository pattern and surfaces it as a decision before planning.",
          "assertions": [
            {"type": "pattern", "value": "[Cc]onflict|[Dd]iverg|[Pp]attern", "description": "Must flag the divergence from the established pattern"},
            {"type": "pattern", "value": "[Dd]ecision|[Ss]urface|[Bb]efore planning", "description": "Must surface it as a decision before planning"}
          ]
        },
        {
          "name": "huge-codebase",
          "category": "scale",
          "prompt": "apex -a refactor the entire monorepo — 500+ files across 12 services",
          "expected_behavior": "Recommends scoping into milestones before running APEX per milestone.",
          "assertions": [
            {"type": "pattern", "value": "[Ss]cope|[Ss]plit|[Mm]ilestone|[Pp]hase|[Ss]ub-task", "description": "Must recommend breaking the refactor into milestones"}
          ]
        },
        {
          "name": "skip-planning-request",
          "category": "invalid",
          "prompt": "apex skip analyze and plan, go straight to execute",
          "expected_behavior": "Warns that executing without analysis/planning risks untested, convention-violating code and recommends the linear spine.",
          "assertions": [
            {"type": "pattern", "value": "[Ww]arn|[Rr]isk|[Ss]kip|[Ss]equen|[Ss]pine", "description": "Must warn about skipping analysis/planning"}
          ]
        },
        {
          "name": "no-test-framework",
          "category": "missing",
          "prompt": "apex -t implement a feature but there is no test framework configured",
          "expected_behavior": "Warns about the missing framework and recommends setup or manual verification fallback.",
          "assertions": [
            {"type": "pattern", "value": "[Nn]o test|[Mm]anual|[Ss]etup|[Ff]ramework|[Ww]arn", "description": "Must warn about missing test framework and propose alternatives"}
          ]
        },
        {
          "name": "malformed-flag",
          "category": "malformed",
          "prompt": "apex --unknownflag implement the feature",
          "expected_behavior": "Rejects the unknown flag and lists the valid flags.",
          "assertions": [
            {"type": "pattern", "value": "[Uu]nknown|[Ii]nvalid|[Ff]lag|[Uu]sage", "description": "Must reject the unknown flag"},
            {"type": "pattern", "value": "-a|-x|-s|-t", "description": "Must list valid flags"}
          ]
        }
      ]
    }
  '';

  # --- Routing: single source of truth for step transitions (R7) ---
  # Every step's "Next Step" defers here instead of duplicating if/else chains.
  apexRouting = ''
    # APEX Routing Table — single source of truth

    Every step's "Next Step" section says "consult ROUTING.md". Do NOT duplicate
    transition logic inside step files. This table is the only place that decides
    where to go next. Edit transitions HERE, nowhere else.

    ## Linear spine

    | From | Next (unconditional) |
    |------|----------------------|
    | 00-init | 01-analyze |
    | 01-analyze | 01b-obsidian IF `-o`, else 02-plan |
    | 01b-obsidian | 02-plan |
    | 02-plan | 02c-verify IF `-v`, else EXECUTE (see below) |
    | 02c-verify | EXECUTE (see below) |
    | EXECUTE | 04-validate |

    ## EXECUTE selector

    - `-m` (teams) active → 03-execute-teams
    - else → 03-execute

    ## Post-validate / post-tests / post-resolve — shared terminal router

    Steps 04-validate, 08-run-tests, 05-examine, 06-resolve all end by applying
    THIS ordered router. Take the FIRST matching rule:

    1. From 04-validate ONLY: IF `-t` (test) → 07-tests.
    2. IF `-x` (examine) AND examine not yet run → 05-examine.
    3. IF 05-examine produced Critical/Important findings AND resolve not yet run → 06-resolve.
    4. IF `-pr` (pull request) → 09-finish.   ← takes precedence over `-n`
    5. IF `-n` (note) → 09b-obsidian-note.
    6. Else → COMPLETE (present summary).

    ## 07-tests / 08-run-tests

    - 07-tests → 08-run-tests (always).
    - 08-run-tests → apply the shared terminal router above (skip rule 1).

    ## 09-finish

    - 09-finish → 09b-obsidian-note IF `-n`, else COMPLETE.

    ## INVARIANT

    When both `-pr` and `-n` are set, rule 4 (pr) fires before rule 5 (note), so
    09-finish is reached first; 09-finish's own tail is then the ONLY path to
    09b. Do not reorder rules 4/5 without updating 09-finish.
  '';

  # --- Orchestration: fresh-context-per-phase (subagent isolation) ---
  # The coordinator is the only spawner (subagents cannot nest, depth=1).
  apexOrchestration = ''
    # APEX Orchestration — fresh context per phase

    Goal: each phase (analyze, plan, execute, validate) runs in an ISOLATED
    subagent with a clean context, so the workflow never loses or pollutes
    context as it grows. The coordinator keeps only a chain of distilled
    summaries — never the raw work of each phase.

    ## Roles

    - **Coordinator** = the main `/apex` run. It is the ONLY agent allowed to
      spawn (subagents cannot spawn subagents — depth is capped at 1). It does
      NOT do the analysis/coding itself; it spawns a phase agent, receives its
      summary, verifies it, persists it, then spawns the next phase.
    - **Phase agent** = a fresh subagent (Agent tool) per phase. Receives a
      self-contained brief, works in its own window, returns ONLY a bounded
      summary (~1-2k tokens). Its raw context is discarded after it returns.

    ## Model routing — Fable commands, Opus executes, Fable verifies

    NEVER let a phase spawn inherit the session model — ALWAYS pass an explicit
    `model` parameter on every Agent call. Rationale: the session runs on Fable
    (orchestrator); an inherited spawn silently burns Fable quota on execution
    work that belongs to Opus.

    | Phase | Agent | model |
    |-------|-------|-------|
    | Analyze fan-out | Explore / codebase-navigator | haiku (agent default) |
    | Analyze synthesis | analyzer phase agent | `opus` |
    | Plan | plan phase agent | `fable` — the plan IS the orders |
    | Execute (incl. `-m` waves) | implementer agents | `opus` |
    | Run tests | test-runner | haiku (agent default) |
    | Validate + Examine (`-x`) | verifier phase agent | `fable` |

    Fable phase agents (plan, validate, examine) may hit the cyber/bio safety
    classifiers → automatic fallback to Opus 4.8. That is expected routing, not
    an error; do not retry in a loop.

    ## Verify loop (the Fable → Opus correction cycle)

    After EVERY execute wave, the validate/examine phase (Fable) must:
    1. Read the execute summary AND the actual diff (`git diff --stat` + the
       diff of touched files). Never trust the summary alone.
    2. Check each acceptance criterion from the plan against the real diff.
    3. Issues found → return a CORRECTIONS list in the phase summary: one line
       per issue — `file: problem → expected fix`.
    4. The coordinator (Fable) re-briefs an Opus implementer (`model: opus`)
       with a SHARPER brief each round — never resend the same brief twice.
       A correction brief must contain: root cause of the miss, exact files
       and lines, the expected end state, and the exact command(s) that must
       pass. Then re-run the verify phase on the new diff.
    5. Loop until every acceptance criterion is green. Max 3 correction rounds:
       still red after 3 → STOP, surface the remaining issues to the user
       verbatim with the failing output. Never weaken a check to make it pass,
       never declare success on partial green.

    ## When this applies

    - Active when NOT economy mode (`-e`). Under `-e`, phases run inline in the
      coordinator (no subagents) — that is economy's whole point.
    - Forces `-s` (save) ON: the chain of summaries is also persisted to disk so
      it survives compaction and enables `-r` resume. Fresh context + external
      memory are two halves of the same mechanism; do not enable one without the other.

    ## Fan-out lives in the COORDINATOR, not the phase

    Because a phase agent cannot itself spawn (depth=1), any parallel fan-out is
    done by the coordinator, which then hands the synthesis to the phase agent:
    - **Analyze**: coordinator spawns the parallel Explore agents, collects their
      bounded summaries, THEN spawns the analyzer agent with those summaries as
      input. The analyzer produces the Conflicts & Constraints synthesis.
    - **Execute (`-m` teams)**: coordinator spawns the implementer agents per wave
      directly; there is no separate "execute agent" wrapping them.

    ## Phase brief (what the coordinator passes IN)

    Every spawn must include, per Anthropic's worker-brief contract:
    1. **Objective** — the one job of this phase.
    2. **Output format** — the exact summary schema below (mandatory).
    3. **Context** — the task + the PRECEDING phase summaries (distilled), plus
       the on-disk plan path. Never the raw transcript.
    4. **Tools & boundaries** — which tools to use, what NOT to touch.

    ## Phase summary (what each phase returns OUT — fixed schema)

    ```
    PHASE: {analyze|plan|execute|validate}
    OBJECTIVE_MET: yes | partial | no
    DECISIONS: {key choices made}
    ARTIFACTS: {files touched / created, plan path, ACs}
    OPEN_RISKS: {anything the next phase must know}
    HANDOFF: {the single most important thing for the next phase}
    ```

    Target 1-2k tokens. Distilled, not raw. Over-compression loses subtle info
    whose importance only appears later — keep every decision and open risk.

    ## Completeness check (mitigates path dependency)

    Before spawning phase N+1, the coordinator verifies phase N's summary has all
    schema fields filled and OBJECTIVE_MET is yes/partial. If a field is empty or
    OBJECTIVE_MET is no → re-spawn the phase with a sharper brief, or stop and ask
    the user. An omission here propagates silently all the way to validate.

    ## Persistence

    Write each phase summary to `.claude/output/apex/{task-id}/NN-{phase}.md` as
    it completes. The coordinator's live context holds only the summaries; the
    disk copy is the source of truth for `-r` resume.

    ## Privileged commands — classify, then escalate or delegate

    Before running ANY command (coordinator or phase agent), classify it. This is
    generalist: do not special-case nix — judge by capability, not by task.

    - **Safe** — read-only, parse, test, edit a file in the repo, `git status/add`,
      `nix-instantiate --parse`, grep, build steps that do not touch the system:
      execute directly.
    - **Long or password-interactive** — `sudo`, `darwin-rebuild build`/`switch`,
      system package installs: DO NOT execute; add the exact command to a
      **"Run yourself" list** in the phase summary / final output (a 10-15 min
      build or a password prompt is better in the user's terminal).
    - **Sandbox-blocked** — `git push` over SSH, docker, local DB sockets, or any
      command that just failed with clear sandbox evidence (permission denied on
      allowed work, socket/auth failure): retry ONCE with
      `dangerouslyDisableSandbox: true`. The `ask` permission rule shows the user
      a confirmation box — they approve or refuse; a refusal is an answer, not an
      obstacle to work around. COORDINATOR ONLY: phase agents do not escalate;
      they surface the command in their summary and the coordinator decides.
      Never weaken the sandbox config itself and never touch secrets to make a
      command pass.
    - **In doubt** — ask the user, unless already durably authorized this session.

    Why: the confirmation box keeps the user in control while avoiding dead-end
    "Run yourself" lists for one-click approvals. Long builds stay delegated
    (the sandbox throttles them and they may need a password). Acceptance
    criteria that need a delegated command (e.g. "switch applied") are marked
    **deferred to user** in the validate summary, not failed.

    ## Cost note

    A 4-phase subagent chain costs materially more tokens than one continuous
    context (multi-agent ≈ up to ~15× a plain chat). That is the price of robust,
    pollution-free context. For small tasks the complexity gate (step-00) should
    have already redirected out of APEX.
  '';

  # -------------------------
  # Debug Skill
  # -------------------------
  skillDebug = ''
    ---
    name: debug
    description: "Systematic debugging workflow"
    disable-model-invocation: true
    context: fork
    effort: high
    ---

    # Debug: Systematic Problem Solving

    Flags: -a (auto), -s (save), -h (help)

    ## Steps

    ### 01 — Reproduce
    Confirm problem, document errors, capture logs.

    ### 02 — Isolate
    Narrow down root cause, check recent changes.

    ### 03 — Diagnose
    Add logging, trace execution, identify root cause.

    ### 04 — Fix
    Apply minimal fix, handle edge cases.

    ### 05 — Verify
    Run reproduction, test edge cases, run regression.

    ${contract {
      expects = "error description or failing test. Optionally: stack trace, logs, git commit range.";
      produces = "root cause analysis + minimal fix applied to source files.";
      sideEffects = "modifies source files (step 04-Fix), adds logging temporarily (step 03-Diagnose, removed after).";
    }}
    ${scope {
      useWhen = "Something is broken and needs systematic diagnosis — errors, crashes, unexpected behavior, flaky tests.";
      notFor = "Feature implementation, code review, refactoring, or infrastructure changes.";
    }}
    ${handoffs [
      "After step 04-Fix → hand off to test-runner to verify the fix with regression suite."
      "If root cause is an architectural issue → stop, report it, recommend /discuss."
      "If fix requires a large refactor (> 10 files) → hand off to feature-workflow for full planning cycle."
      "If the bug is in production only → gather logs/observability data before starting step 01."
    ]}
  '';

  # -------------------------
  # nix-darwin Skill
  # -------------------------
  skillNixDarwin = ''
    ---
    name: nix-darwin
    description: "nix-darwin + home-manager patterns for macOS. Use when editing *.nix files, or tasks involve module structure, system.defaults, launchd, or declarative macOS setup."
    globs: ["**/*.nix", "**/flake.lock"]
    ---

    # nix-darwin Patterns

    ## Module Structure (5 modules)
    ```
    flake.nix
    ├── hosts/alex-mbp/        (host identity)
    ├── modules/               (5 modules)
    │   ├── system.nix         Core: Nix + env + security + shell
    │   ├── packages.nix       CLI tools
    │   ├── services.nix       Background services (launchd)
    │   ├── ui.nix             Fonts + Dock + Finder + defaults
    │   └── brew.nix           GUI apps (Homebrew)
    └── home/                  (user config via home-manager)
        ├── default.nix
        ├── git.nix
        ├── zsh.nix
        ├── starship.nix
        └── direnv.nix
    ```

    ## Best Practices 2026
    - No `with pkgs;` — always explicit `pkgs.` prefix
    - 5-8 modules, single-responsibility
    - System/user separation: modules/ vs home/
    - home-manager native features over manual shell code
    - `nixfmt` formatter (not nixfmt-rfc-style)
    - Minimal comments, code is self-documenting
    - `lib.mkIf` / `lib.mkDefault` for conditional config
    - Always `git add` new files before rebuild (flakes requirement)
    - No `environment.etc` for user files — use `home.file`

    ## Common Patterns

    ### Adding config
    - CLI tools → `modules/packages.nix`
    - GUI apps → `modules/brew.nix` casks
    - Fonts → `modules/ui.nix` fonts.packages
    - Services → `modules/services.nix` launchd
    - User config → `home/*.nix`

    ### macOS defaults
    - Built-in: `system.defaults.dock.*`, `system.defaults.finder.*`
    - App-specific: `system.defaults.CustomUserPreferences`
    - Reference: https://nix-darwin.github.io/nix-darwin/manual/

    ### Verification
    ```bash
    nix-instantiate --parse file.nix  # syntax check
    rebuild                            # full build test
    darwin-rebuild rollback            # if broken
    ```

    ## Pitfalls
    1. Untracked files invisible to flakes → `git add` first
    2. `environment.etc` wrong for user files → use `home.file`
    3. Raw plist files → prefer `launchd.daemons`
    4. `with pkgs;` pollutes scope → use explicit `pkgs.` prefix

    ${contract {
      expects = ".nix file path or module description (what to add/change). Optionally: target module name.";
      produces = "nix module code (attribute set additions or new module file).";
      sideEffects = "modifies .nix files in modules/ or home/; may trigger darwin-rebuild on verification.";
    }}
    ${scope {
      useWhen = "Editing any *.nix file, flake.lock, adding packages/services/fonts/defaults, configuring home-manager, or any task involving declarative macOS setup";
      notFor = "Non-nix config changes (tsconfig, package.json, dotfiles managed outside home-manager), running arbitrary shell commands, or app-level TypeScript/JS code";
    }}
    ${handoffs [
      "If adding a GUI app → always use modules/brew.nix casks, not packages.nix"
      "If change affects user dotfiles (git, zsh, starship) → edit home/*.nix, not modules/"
      "After any nix edit → run nix-instantiate --parse then rebuild to verify before committing"
      "If flake input is missing → update flake.nix first, git add flake.nix, then rebuild"
    ]}
  '';

  # -------------------------
  # Claude Code Meta Skill
  # -------------------------
  skillClaudeCodeMeta = ''
    ---
    name: claude-code-meta
    description: "2026 best practices for Claude Code skill authoring, agent design, and hook patterns. Use when editing agents.nix, skills.nix, hooks.nix, claude-md.nix, or .claude/ config files."
    globs: ["**/.claude/agents/*.md", "**/.claude/skills/**/SKILL.md", "**/.claude/hooks/**"]
    ---

    # Claude Code Meta — Authoring Best Practices

    ## Agent Descriptions
    Pattern: `[What it does]. Use when [triggers].`
    - First sentence: capability (verb-first)
    - Second sentence: activation triggers (file patterns, keywords)
    - Estimated activation: 70-80% with good triggers

    ## Skill Triggering
    - `globs:` in frontmatter for file-based activation
    - `description:` with "Use when..." for keyword activation
    - Skills auto-load when matching files are in context

    ## Skill Injection via Agents
    - Global: add `skills: [skill-name]` in agent frontmatter
    - Project: override agents in `.claude/agents/` per repo
    - Generic: agents should run `ls .claude/skills/*/SKILL.md` before coding

    ## CLAUDE.md Rules
    - Global: `~/.claude/CLAUDE.md` (< 200 lines, always loaded)
    - Project: `.claude/CLAUDE.md` (per-repo, checked in)
    - Keep concise — every line costs context tokens

    ## Hook Types
    - `PreToolUse` / `PostToolUse`: gate or react to tool calls
    - `PreCompact`: backup before context compaction
    - `SessionStart`: display session info
    - `SubagentStop`: log agent results for analysis
    - Hooks: JS (node) or bash, with timeout

    ## File Layout
    ```
    ~/.claude/
    ├── CLAUDE.md              Global instructions
    ├── settings.json          Settings + hooks + permissions
    ├── agents/*.md            Agent definitions
    ├── commands/*.md           Slash commands
    ├── skills/*/SKILL.md      Skill files
    └── hooks/*.js|*.sh        Hook scripts
    ```

    ${contract {
      expects = "agent/skill/hook specification (name, purpose, triggers). Optionally: existing file to update.";
      produces = ".nix config code for agents.nix, skills.nix, hooks.nix, or claude-md.nix.";
      sideEffects = "modifies home/claude-code/*.nix files; changes take effect after darwin-rebuild.";
    }}
    ${scope {
      useWhen = "Editing agents.nix, skills.nix, hooks.nix, claude-md.nix, or any file under .claude/ (agents, skills, hooks, commands, CLAUDE.md)";
      notFor = "Application code, deployment config, database schemas, or anything outside the Claude Code meta-layer";
    }}
    ${handoffs [
      "If new skill covers a domain with existing agents → update matching agent's skills: frontmatter too"
      "If hook logic is complex (>50 lines) → extract to hooks/*.js and reference from settings.json"
      "After editing CLAUDE.md → verify line count stays under 200 to avoid context truncation"
      "If agent activation rate is low → use schliff skill to audit trigger quality before manual tuning"
    ]}
  '';

  # -------------------------
  # Obsidian Vault Skill (direct file access — no MCP)
  # -------------------------
  skillObsidian = ''
    ---
    name: obsidian
    description: "Read, search, and write notes in the Obsidian vault via native file tools (Read, Write, Edit, Grep, Glob). Use when the user mentions notes, vault, Obsidian, knowledge base, or wants to search/create/edit markdown notes."
    ---

    # Obsidian Vault (direct file access)

    Vault path: `~/Documents/AlxVault`

    No MCP server needed — use native tools directly on the vault files.

    ## Tool Mapping
    | Action | Tool | Example |
    |--------|------|---------|
    | Search notes | `Grep` | `Grep(pattern: "keyword", path: "~/Documents/AlxVault")` |
    | Read note | `Read` | `Read(file_path: "~/Documents/AlxVault/02-Projets/Preliz/Preliz.md")` |
    | List directory | `Glob` | `Glob(pattern: "**/*.md", path: "~/Documents/AlxVault/02-Projets/")` |
    | Create note | `Write` | `Write(file_path: "~/Documents/AlxVault/01-Inbox/new-note.md", content: "...")` |
    | Edit note | `Edit` | `Edit(file_path: "...", old_string: "...", new_string: "...")` |
    | Find by tag | `Grep` | `Grep(pattern: "tags:.*veille", path: "~/Documents/AlxVault")` |
    | Find by frontmatter | `Grep` | `Grep(pattern: "^date: 2026", path: "~/Documents/AlxVault", multiline: true)` |

    ## Vault Structure
    - `00-Meta/` — Templates, vault config
    - `01-Inbox/` — Quick capture, unsorted
    - `02-Projets/` — Active projects
    - `03-Areas/` — Ongoing areas of responsibility
    - `04-Resources/` — Reference material, veille-claude output

    ## Guidelines
    - Grep before creating to avoid duplicates
    - Use Edit for small changes, Write for new notes
    - Preserve existing frontmatter when editing
    - New notes: place in `01-Inbox/` unless the user specifies otherwise
    - Always confirm before deleting

    ## Conventions Alx

    ### Demarrage de session
    - Toujours lire `00-Meta/CLAUDE.md` en debut de session pour charger le contexte
    - Si un projet est mentionne, lire aussi `02-Projets/[projet]/[projet].md`

    ### Sessions
    - Nom du fichier : `YYYY-MM-DD - sujet-court.md` dans `02-Projets/[projet]/sessions/`
    - Frontmatter YAML type en tete (Properties UI) : `date`, `type: session`, `project: "[[...]]"` (link property), `tags:` en liste
    - Apres le frontmatter, premiere ligne = wikilink vers la note projet : `[[02-Projets/[projet]/[projet]|[projet]]]`
    - Ensuite le titre `# YYYY-MM-DD - Sujet court`
    - Contenu : ce qui a ete fait, decisions prises, prochaines etapes

    > Note : les runs APEX avec le flag `-n` ecrivent ces notes automatiquement via step-09b-obsidian-note.md — voir ce fichier pour le template complet (format 2026 Properties UI).

    ### Wikilinks
    - Toujours utiliser le chemin complet : `[[02-Projets/Preliz/Preliz]]`
    - Forme alias recommandee pour lisibilite : `[[02-Projets/Preliz/Preliz|Preliz]]`
    - Ne jamais creer de wikilink sans chemin complet (evite les noeuds orphelins dans le graph)

    ### Regles
    - Ne jamais modifier les fichiers dans `decisions/` sans demander
    - `01-Inbox/` = capture brute, ne pas restructurer sans accord
    - Toujours repondre en francais sauf pour le code

    ${contract {
      expects = "note path or search query. Optionally: frontmatter fields (tags, date, project link).";
      produces = "note content (Read/search), search results (Grep/Glob), or new/edited markdown note.";
      sideEffects = "may create or modify files in AlxVault/; decisions/ changes require explicit confirmation.";
    }}
    ${scope {
      useWhen = "Any request involving notes, vault, Obsidian, knowledge base, or searching/creating/editing markdown notes in AlxVault";
      notFor = "Code editing, deployment tasks, git operations, or any work outside the AlxVault directory";
    }}
    ${handoffs [
      "If note content involves a code decision → capture summary in vault then hand off to relevant specialist agent for implementation"
      "If user mentions a project name → read 02-Projets/[projet]/[projet].md before acting on vault tasks"
      "Before creating any note → Grep first to avoid duplicates; if found, Edit instead of Write"
      "After session ends → create session note in 02-Projets/[projet]/sessions/ with decisions + next steps"
    ]}
  '';

  # -------------------------
  # Schliff — SKILL.md quality linter
  # -------------------------
  skillSchliff = ''
    ---
    name: schliff
    description: "Analyze and score SKILL.md quality using Schliff linter. Use when tasks mention skill quality, skill audit, skill score, or skill optimization."
    effort: low
    ---

    # Schliff — Skill Quality Linter

    Static analyzer for SKILL.md files. 7-dimension scoring (S→F grade).

    ## Commands
    - `uvx schliff score <path>` — score a single skill
    - `uvx schliff doctor <dir>` — scan all skills in a directory
    - `uvx schliff verify <path> --min-score 75` — CI gate (exit 1 if below threshold)
    - `uvx schliff diff <path>` — show what changed since last score

    ## Scoring Dimensions
    | Dimension | Weight | Measures |
    |-----------|--------|----------|
    | Structure | 15% | Frontmatter, headers, examples |
    | Triggers | 20% | Activation accuracy, false positive risk |
    | Quality | 20% | Assertion depth, feature coverage |
    | Edges | 15% | Edge cases, invalid inputs, scale |
    | Efficiency | 10% | Filler words, signal-to-noise |
    | Composability | 10% | Scope boundaries, error behavior |
    | Clarity | 5% | Contradiction detection |

    ## Workflow
    1. Run `uvx schliff doctor ~/.claude/skills/` to audit all skills
    2. Fix skills scoring below B (< 75)
    3. Re-score to verify improvement
    4. Use `uvx schliff verify --min-score 75` in CI/pre-commit

    ## Grade Scale
    S (95+) | A (85+) | B (75+) | C (60+) | D (45+) | E (30+) | F (<30)

    ${contract {
      expects = "SKILL.md path (score/verify) or directory path (doctor).";
      produces = "score report with dimension breakdown (Structure/Triggers/Quality/Edges/Efficiency/Composability/Clarity) and letter grade.";
    }}
    ${scope {
      useWhen = "evaluating SKILL.md quality, auditing skill files, setting CI gates for skill scores, or improving skill structure.";
      notFor = "runtime testing, code quality checks, linting application code, or validating non-SKILL.md files.";
    }}
    ${handoffs [
      "If score < 60 → run /schliff:auto first to apply structural fixes before re-scoring"
      "After scoring → use autoresearch to optimize if score plateaus and manual iteration isn't converging"
      "If skill has missing scope/handoffs → add those sections before re-scoring (boosts Composability dimension)"
    ]}
  '';

  # -------------------------
  # Autoresearch — Autonomous experiment loop
  # -------------------------
  skillAutoresearch = ''
    ---
    name: autoresearch
    description: "Set up and run an autonomous experiment loop for any optimization target. Use when asked to run autoresearch, optimize X in a loop, set up autoresearch for X, or start experiments."
    effort: high
    ---

    # Autoresearch

    Autonomous experiment loop: try ideas, keep what works, discard what doesn't.

    ## Setup
    1. Ask (or infer): **Goal**, **Command**, **Metric** (+ direction), **Files in scope**, **Constraints**
    2. `git checkout -b autoresearch/<goal>-<date>`
    3. Read source files deeply before writing anything
    4. `mkdir -p experiments` then write `autoresearch.md`, `autoresearch.sh`, `experiments/worklog.md`
    5. Initialize → run baseline → log result → start looping

    ## Core Files
    - `autoresearch.md` — Session context (goal, metrics, files, constraints, what's been tried)
    - `autoresearch.sh` — Benchmark script, outputs `METRIC name=number` lines
    - `autoresearch.jsonl` — State: config headers + result lines (source of truth)
    - `autoresearch-dashboard.md` — Regenerated after each run (table of all experiments)
    - `experiments/worklog.md` — Narrative log, survives context compactions

    ## JSONL Protocol
    Config header (first line):
    ```json
    {"type":"config","name":"<name>","metricName":"<metric>","metricUnit":"<unit>","bestDirection":"lower|higher"}
    ```
    Result lines:
    ```json
    {"run":1,"commit":"abc1234","metric":42.3,"metrics":{},"status":"keep|discard|crash","description":"baseline","timestamp":1234567890,"segment":0}
    ```

    ## Loop Rules
    - **LOOP FOREVER.** Never ask "should I continue?"
    - Primary metric improved → `keep`. Worse/equal → `discard`
    - Simpler is better. Removing code for equal perf = keep
    - Don't thrash — if same idea fails twice, try structurally different
    - On keep: `git add -A && git commit`. On discard: `git checkout -- . && git clean -fd`
    - **Never** `git clean -fdx` (deletes JSONL state)
    - Regenerate dashboard after every run
    - Update `experiments/worklog.md` after every run
    - Think longer when stuck — re-read source, study profiling data

    ## Resuming
    If `autoresearch.md` exists: read it + JSONL + worklog + git log, continue looping

    ## Ideas Backlog
    Append promising but deferred ideas to `autoresearch.ideas.md`

    ${contract {
      expects = "goal + benchmark command + metric name/direction (lower/higher). Optionally: files in scope, constraints.";
      produces = "optimized code committed across N runs + experiment log in autoresearch.jsonl + dashboard in autoresearch-dashboard.md.";
      sideEffects = "creates git branch autoresearch/{goal}-{date}, writes autoresearch.md/jsonl/sh, modifies source files per experiment.";
    }}
    ${scope {
      useWhen = "autonomous optimization with a measurable numeric metric, iterative experiment loops, benchmarking with a clear goal and direction (lower/higher).";
      notFor = "one-off tasks, subjective quality improvements, tasks without a measurable metric, or manual step-by-step workflows.";
    }}
    ${handoffs [
      "If optimization target is a skill file → use schliff for structural scoring first, then autoresearch to push score past plateau"
      "After experiment loop completes → hand off to code-reviewer for review of accumulated commits"
      "If no benchmark command exists yet → stop and ask for one before looping"
    ]}
  '';

  # -------------------------
  # Testing Patterns Skill
  # -------------------------
  skillTestingPatterns = ''
    ---
    name: testing-patterns
    description: "Testing methodology and patterns. Use when writing tests, designing test strategy, or tasks mention test, spec, coverage, TDD, or testing patterns."
    globs: ["**/*.test.*", "**/*.spec.*", "**/__tests__/**"]
    effort: high
    ---

    # Testing Patterns

    Systematic testing methodology for TypeScript/JS projects.

    ## Trophy Model (preferred over pyramid)
    ```
    ┌──────────────┐
    │   E2E (few)  │  Critical user flows only
    ├──────────────┤
    │ Integration  │  ← Most tests here
    │   (many)     │  Components + services together
    ├──────────────┤
    │  Unit (some) │  Pure logic, utils, transforms
    ├──────────────┤
    │ Static (all) │  TypeScript + ESLint
    └──────────────┘
    ```

    ## AAA Pattern (Arrange-Act-Assert)
    Every test follows this structure:
    ```typescript
    test("descriptive name of behavior", () => {
      // Arrange — set up test data and dependencies
      const input = createTestInput();

      // Act — execute the thing being tested
      const result = processInput(input);

      // Assert — verify the expected outcome
      expect(result).toMatchObject({ status: "success" });
    });
    ```

    ## Test Naming
    - Format: `describe("ModuleName")` → `test("should [behavior] when [condition]")`
    - Test the behavior, not the implementation
    - One assertion concept per test (multiple expects OK if same concept)

    ## What to Test
    - **Always:** business logic, data transforms, validation, error paths
    - **Usually:** API handlers, hooks with side effects, state machines
    - **Rarely:** UI layout, CSS, simple pass-through components
    - **Never:** third-party library internals, trivial getters/setters

    ## Mocking Rules
    - Mock at boundaries: network, filesystem, time, randomness
    - Never mock the thing being tested
    - Prefer real implementations over mocks when feasible
    - If a mock is complex, the design might need refactoring

    ## Coverage Strategy
    - Target: 80% line coverage on business logic, not vanity 100%
    - Focus on branch coverage over line coverage
    - Uncovered code should be a deliberate decision, not oversight

    ## Vitest Patterns
    ```typescript
    import { describe, test, expect, vi, beforeEach } from "vitest";

    // Time mocking
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-01-01"));

    // Module mocking
    vi.mock("./dependency", () => ({ fetchData: vi.fn() }));

    // Snapshot (use sparingly)
    expect(result).toMatchSnapshot();

    // Error testing
    expect(() => riskyOperation()).toThrow(/expected error/);
    await expect(asyncRisky()).rejects.toThrow();
    ```

    ${contract {
      expects = "module/function to test, or test strategy request. Optionally: existing test files.";
      produces = "test files following AAA pattern, Trophy model placement, and project conventions.";
      sideEffects = "creates/modifies test files. May update test config if needed.";
    }}
    ${scope {
      useWhen = "writing new tests, improving test coverage, designing test strategy, or reviewing test quality.";
      notFor = "debugging production issues (use debug skill), implementing features, or code review.";
    }}
    ${handoffs [
      "After writing tests → hand off to test-runner agent to execute and verify"
      "If tests reveal a bug → hand off to debugger agent for root-cause analysis"
      "If testing requires architectural changes → stop, report, recommend /discuss"
      "For test quality scoring → use schliff on test-related skills"
    ]}
  '';

  # -------------------------
  # Codebase Audit Skill
  # -------------------------
  skillCodebaseAudit = ''
    ---
    name: codebase-audit
    description: "Audit codebase health: dead code, unused deps, doc gaps, file bloat. Use when tasks mention audit, cleanup, inventory, drift, tech debt, or codebase health."
    effort: high
    ---

    # Codebase Audit

    Systematic 8-step audit producing a CODEBASE-STATUS.md report.

    ## Audit Steps

    ### 01 — Dead Exports
    Find exported functions/types never imported elsewhere.
    ```bash
    grep -r "export " src/ | # extract names
    # cross-reference with imports across codebase
    ```

    ### 02 — Unused Dependencies
    ```bash
    pnpm ls --depth 0  # installed deps
    # grep each dep name in src/ — missing = unused
    ```

    ### 03 — Orphan Files
    Files not imported by any other file and not an entrypoint.
    Check: `src/**/*.ts` not referenced in any import statement.

    ### 04 — Config Drift
    Compare tsconfig, eslint, prettier configs against project CLAUDE.md conventions.
    Flag mismatches (e.g., strict mode off when CLAUDE.md says strict).

    ### 05 — Doc Gaps
    - README mentions features that no longer exist
    - CLAUDE.md references files/paths that moved
    - Missing JSDoc on public API functions

    ### 06 — File Bloat
    Files over 300 lines — candidates for splitting.
    Functions over 50 lines — candidates for extraction.

    ### 07 — Test Coverage Gaps
    Source files with no corresponding test file.
    ```bash
    # for each src/foo.ts, check if src/foo.test.ts or __tests__/foo.test.ts exists
    ```

    ### 08 — Security Surface
    - Hardcoded URLs, IPs, ports
    - TODO/FIXME/HACK comments (count and categorize)
    - Dependencies with known vulnerabilities (`pnpm audit`)

    ## Output: CODEBASE-STATUS.md
    ```markdown
    # Codebase Status — YYYY-MM-DD

    ## Summary
    | Metric | Count | Status |
    |--------|-------|--------|
    | Dead exports | N | OK/WARN |
    | Unused deps | N | OK/WARN |
    | Orphan files | N | OK/WARN |
    | Config drift | N | OK/WARN |
    | Doc gaps | N | OK/WARN |
    | Bloated files | N | OK/WARN |
    | Untested files | N | OK/WARN |
    | Security items | N | OK/WARN |

    ## Details
    [per-step findings with file paths and recommendations]

    ## Recommended Actions
    [prioritized list of cleanup tasks]
    ```

    ${contract {
      expects = "project directory (defaults to cwd). Optionally: specific steps to run.";
      produces = "CODEBASE-STATUS.md with findings and recommendations.";
    }}
    ${scope {
      useWhen = "periodic health checks, pre-refactor assessment, tech debt inventory, or onboarding to understand codebase state.";
      notFor = "implementing fixes (hand off to relevant agent), security penetration testing (use security-auditor), or performance profiling (use /optimize).";
    }}
    ${handoffs [
      "Dead exports/orphan files → hand off to quick-fix agent for removal"
      "Config drift → hand off to nix-expert or relevant specialist"
      "Test coverage gaps → hand off with testing-patterns skill for test creation"
      "Security items → hand off to security-auditor for deep analysis"
      "Bloated files → run /discuss to produce a decomposition plan"
    ]}
  '';

  skillCaveman = ''
    ---
    name: caveman
    description: "Compress Claude output tokens ~75%. Terse prose, full technical accuracy. Activate: /caveman. Deactivate: stop caveman."
    ---

    # Caveman — Token Compression

    When active, respond in compressed caveman-style prose.
    Level: full (default).

    ## Rules

    - Drop articles (a, an, the) unless ambiguous without
    - Drop filler: "I'll", "Let me", "Sure", "Happy to", "Based on", "In order to"
    - Use fragments over full sentences
    - Prefer verbs: "Fix X" not "I will fix X"
    - Technical terms, code, file paths, URLs, commands → preserve EXACTLY
    - Error messages → preserve verbatim
    - Code blocks → never compress
    - Multi-step sequences where ambiguity risks misread → use full sentences

    ## Safety carve-outs (resume full prose)

    - Security warnings
    - Irreversible action confirmations (delete, push, deploy)
    - User confused or repeating question

    ## Intensity levels

    - /caveman lite — drop filler, keep readable sentences
    - /caveman full — fragments, no articles, minimal words (DEFAULT)
    - /caveman ultra — absolute minimum, telegraph style
    - stop caveman — resume normal prose

    ## Activation

    Trigger: /caveman or /caveman full or "talk like caveman" or "less tokens"
    Deactivate: "stop caveman" or "normal mode"
  '';

  skillCavemem = ''
    ---
    name: cavemem
    description: "Compress CLAUDE.md and memory files into caveman format to reduce input tokens. Preserves all technical content. Trigger: /cavemem compress <filepath>"
    ---

    # Cavemem — Memory Compression

    Compress natural language memory files (CLAUDE.md, rules, preferences) into
    caveman format. Reduces input tokens on every session load.

    ## What to compress
    - Natural language prose and explanations
    - Redundant phrasing, filler words, connectives

    ## What to NEVER touch
    - Code blocks (inline or fenced)
    - File paths, URLs, commands
    - Headings and structure
    - Dates, version numbers, technical terms
    - Any .ts .js .nix .json .yaml .sh .sql file — NEVER modify

    ## Process
    1. Read target file
    2. Compress prose to caveman style (full level)
    3. Write compressed version to original path
    4. Save human-readable backup as <filename>.original.md
    5. Report: original words → compressed words, % saved

    ## Trigger
    /cavemem compress <filepath>
    or "compress memory file <filepath>"
  '';

  # =========================================================================
  # Trello — CLI via REST API v1 (curl). Replaces the removed MCP server.
  # Declarative, zero npx daemon. Secrets read at runtime from ~/.config/secrets.
  # =========================================================================
  skillTrello = ''
    ---
    name: trello
    description: "Pilot Trello from the shell via the REST API v1 (curl). Use when the user mentions Trello, a board, list, card, or kanban and wants to read or create/move cards. Replaces the former MCP server — there are no native Trello MCP tools."
    ---

    # Trello — CLI (REST API v1)

    Drive Trello with `curl` + `jq`. No MCP server, no npx. Auth via a personal
    API key + token read at runtime from `~/.config/secrets` (never hardcode,
    never echo the values).

    ## Auth — load credentials first (every session that touches Trello)

    ```bash
    TRELLO_KEY=$(cat "$HOME/.config/secrets/trello-api-key")
    TRELLO_TOKEN=$(cat "$HOME/.config/secrets/trello-token")
    AUTH="key=$TRELLO_KEY&token=$TRELLO_TOKEN"
    ```

    If either file is missing, stop and tell the user to create it — do NOT
    proceed with empty credentials.

    ## Read operations

    ```bash
    # List my boards (id  name)
    curl -s "https://api.trello.com/1/members/me/boards?fields=name,id&$AUTH" \
      | jq -r '.[] | "\(.id)  \(.name)"'

    # List lists of a board (id  name)
    curl -s "https://api.trello.com/1/boards/<BOARD_ID>/lists?fields=name,id&$AUTH" \
      | jq -r '.[] | "\(.id)  \(.name)"'

    # List cards of a list (id  name)
    curl -s "https://api.trello.com/1/lists/<LIST_ID>/cards?fields=name,id&$AUTH" \
      | jq -r '.[] | "\(.id)  \(.name)"'
    ```

    ## Write operations

    ```bash
    # Create a card in a list
    curl -s -X POST "https://api.trello.com/1/cards?$AUTH" \
      --data-urlencode "idList=<LIST_ID>" \
      --data-urlencode "name=Card title" \
      --data-urlencode "desc=Card description" \
      | jq -r '"created: \(.id)  \(.shortUrl)"'

    # Move a card to another list
    curl -s -X PUT "https://api.trello.com/1/cards/<CARD_ID>?$AUTH" \
      --data-urlencode "idList=<DEST_LIST_ID>" >/dev/null

    # Comment on a card
    curl -s -X POST "https://api.trello.com/1/cards/<CARD_ID>/actions/comments?$AUTH" \
      --data-urlencode "text=Comment body" >/dev/null
    ```

    ## Name → ID resolution

    The API works on IDs, not names. Resolve in order: board name → BOARD_ID →
    list name → LIST_ID, then act. When the user gives a name, list first and
    match (case-insensitive) before any write. Ask if the match is ambiguous.

    ## Constraints
    - Rate limits: 300 req/10s per key, 100 req/10s per token. Batch loops →
      add a short sleep and retry on HTTP 429 with backoff.
    - Never print the key/token. Confirm before any write (create/move/comment).
    - This is a write-capable integration: treat create/move/delete as
      outward-facing actions — confirm first unless told to proceed.
${contract {
  expects = "a Trello intent (read board/list/cards, or create/move/comment on a card), names or IDs";
  produces = "the requested data (ids + names) or the result of a create/move/comment action";
  sideEffects = "network calls to api.trello.com; writes create/modify Trello cards";
}}${scope {
  useWhen = "the user wants to read or modify Trello boards/lists/cards from the shell";
  notFor = "non-Trello task trackers, or bulk migrations (use the API directly with proper backoff).";
}}${handoffs [
  "If credentials are missing → ask the user to populate ~/.config/secrets/trello-{api-key,token}."
  "For complex automations → write a dedicated script rather than ad-hoc curl."
]}  '';
}
