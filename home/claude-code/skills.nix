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
  # Progressive step loading: each step is read on-demand for recency bias.
  # =========================================================================

  skillApex = ''
    ---
    name: apex
    description: "Systematic implementation using APEX methodology"
    effort: high
    ---

    # APEX: Systematic Implementation Workflow

    You are about to execute a structured, multi-step implementation workflow.
    Each step is a separate file that you will read and execute one at a time.
    This keeps instructions fresh in your context for maximum attention.

    ## Available Flags

    | Enable | Disable | Description |
    |--------|---------|-------------|
    | -a | -A | Auto — skip confirmations |
    | -x | -X | Examine — adversarial code review |
    | -s | -S | Save — persist outputs to files |
    | -t | -T | Test — create and run tests |
    | -e | -E | Economy — no subagents, direct tools only |
    | -b | -B | Branch — create git branch |
    | -pr | -PR | Pull request — commit + PR (implies -b) |
    | -k | -K | Tasks — task breakdown with dependency graph |
    | -m | -M | Teams — Agent Teams parallel execution (implies -k) |
    | -v | -V | Verify — research plan online before executing |
    | -o | -O | Obsidian context — load vault project notes before planning |
    | -n | -N | Note — create Obsidian session note at the end |
    | -i | | Interactive — configure flags via menu |
    | -r | | Resume — continue previous task |

    ## Common Usage

    ```
    /apex add feature                    # Basic
    /apex -a -s implement auth           # Autonomous + save
    /apex -a -x -s fix bug              # Full autonomous with review
    /apex -a -t -pr add endpoint        # Auto + tests + PR
    /apex -e simple fix                  # Economy mode (save tokens)
    /apex -a -o -n add feature           # With Obsidian context load + session note
    /apex -a -x -t -pr -o -n feature   # Everything enabled
    ```

    ## Execution

    Read [steps/step-00-init.md](steps/step-00-init.md) and execute it now.

    ${contract {
      expects = "task description with optional flags. Example: /apex -a -x implement user auth";
      produces = "complete implementation through progressive steps: init → analyze → plan → execute → validate (+ optional: tests, examine, resolve, finish).";
      sideEffects = "modifies source files, optionally creates tests, commits, creates PRs.";
    }}
    ${scope {
      useWhen = "Implementing features, modules, or tasks that benefit from structured multi-step execution with quality gates.";
      notFor = "Quick fixes (<20 lines) → use quick-fix. Debugging → use /debug. Research → use Explore agent.";
    }}
    ${handoffs [
      "If task is broken and needs diagnosis → use debug skill instead."
      "If scope is unclear → run /discuss first."
      "After tests fail repeatedly → hand off to debugger agent."
      "After finish on L/XL changes → hand off to code-reviewer agent."
    ]}
  '';

  # --- Step 00: Init ---
  apexStep00Init = ''
    # Step 00: Initialize

    YOU ARE AN INITIALIZER, not an executor. Do NOT start implementing yet.

    ## Parse Flags

    Extract flags from $ARGUMENTS. Default: all flags OFF.
    - If `-pr` is set, auto-enable `-b` (branch)
    - If `-m` is set, auto-enable `-k` (tasks)
    - Uppercase flag disables (e.g., `-A` disables auto)

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

    YOU ARE AN EXPLORER, not a planner. Do NOT plan or implement yet.
    Your only job is to deeply understand the codebase and the task.

    ## Strategy

    Evaluate task complexity across 4 dimensions:
    - **Scope**: how many files/modules affected?
    - **Libraries**: unfamiliar dependencies?
    - **Patterns**: existing conventions to follow?
    - **Uncertainty**: unclear requirements?

    ### If economy mode is active:
    Use Glob and Grep directly. Read only the most relevant files. No agents.

    ### If economy mode is NOT active:
    Launch parallel Explore agents based on complexity:
    - Simple (1-2 files): 1-2 agents
    - Medium (3-5 files): 3-5 agents
    - Complex (6+ files): 5-10 agents

    Each agent should explore a different aspect:
    - File structure and conventions
    - Existing patterns and utilities
    - Related components and dependencies
    - Test patterns (if -t flag active)

    ## Output

    Document your findings:
    - **Requirements**: what exactly needs to be built
    - **Affected files**: list of files to create/modify
    - **Conventions**: patterns to follow (naming, structure, imports)
    - **Dependencies**: libraries, utilities, types to use
    - **Risks**: potential issues or unknowns

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

    If verify mode (-v) is active:
      Read [step-02c-verify.md](step-02c-verify.md) and execute it.
    Else if teams mode (-m) is active:
      Read [step-03-execute-teams.md](step-03-execute-teams.md) and execute it.
    Else:
      Read [step-03-execute.md](step-03-execute.md) and execute it.
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

    If teams mode (-m) is active:
      Read [step-03-execute-teams.md](step-03-execute-teams.md) and execute it.
    Else:
      Read [step-03-execute.md](step-03-execute.md) and execute it.
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

    YOU ARE AN IMPLEMENTER following a plan, not a designer.
    Do NOT deviate from the plan. Do NOT add features that weren't planned.

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

    ## Verification Checklist

    1. **Acceptance Criteria**: go through each AC from the plan.
       For each one, verify it is actually implemented. Check the code.

    2. **Build Check**: if applicable, run:
       - TypeScript: typecheck (`pnpm typecheck` or `npx tsc --noEmit`)
       - Lint: `pnpm lint` or equivalent
       - Build: `pnpm build` or equivalent

    3. **Integration Check**: verify that:
       - All imports resolve
       - No circular dependencies introduced
       - Types are consistent across boundaries

    4. **Quick Smoke Test**: if there's a dev server, verify it starts without errors

    ## If any AC is not met:
    Go back and fix it. Do not proceed until all ACs pass.

    ## If save mode (-s):
    Update progress in context file.

    ## Next Step — Conditional

    Choose the next step based on active flags:

    1. If `-t` (test) is active: Read [step-07-tests.md](step-07-tests.md) and execute it.
    2. Else if `-x` (examine) is active: Read [step-05-examine.md](step-05-examine.md) and execute it.
    3. Else if `-pr` (pull request) is active: Read [step-09-finish.md](step-09-finish.md) and execute it.
    4. Else if `-n` (note) is active: Read [step-09b-obsidian-note.md](step-09b-obsidian-note.md) and execute it.
    5. Else: **COMPLETE.** Present a summary of what was implemented.
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

    If there are Critical or Important findings:
      Read [step-06-resolve.md](step-06-resolve.md) and execute it.
    Else if `-pr` (pull request) is active:
      Read [step-09-finish.md](step-09-finish.md) and execute it.
    Else if `-n` (note) is active:
      Read [step-09b-obsidian-note.md](step-09b-obsidian-note.md) and execute it.
    Else:
      **COMPLETE.** Present the review summary.
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

    If `-pr` (pull request) is active:
      Read [step-09-finish.md](step-09-finish.md) and execute it.
    Else if `-n` (note) is active:
      Read [step-09b-obsidian-note.md](step-09b-obsidian-note.md) and execute it.
    Else:
      **COMPLETE.** Present the resolution summary.
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

    ## Next Step — Conditional

    1. If `-x` (examine) is active: Read [step-05-examine.md](step-05-examine.md) and execute it.
    2. Else if `-pr` (pull request) is active: Read [step-09-finish.md](step-09-finish.md) and execute it.
    3. Else if `-n` (note) is active: Read [step-09b-obsidian-note.md](step-09b-obsidian-note.md) and execute it.
    4. Else: **COMPLETE.** Present test results summary.
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
    description: Feature development methodology — discuss→plan→verify cycle. Referenced by architecture-expert, team-lead, code-reviewer.
    globs: ["**/.claude/output/feature/**", "**/.claude/output/CONTEXT-*"]
    effort: high
    ---

    # Feature Development Methodology

    ## When to Use What

    | Complexity | Files | Approach | Command |
    |-----------|-------|----------|---------|
    | S (trivial) | < 5 | Single agent directly | quick-fix or specialist agent |
    | M (medium) | 5-15 | Discuss → agent plan → execute | /discuss → architecture-expert |
    | L (large) | 15+ | Full chain (5 phases) | feature-chain.sh |
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
      "After DISCUSS phase → hand off to architecture-expert for PLAN creation"
      "After PLAN phase → hand off to code-reviewer for two-pass REVIEW before EXECUTE"
      "After EXECUTE phase → hand off to code-reviewer for VERIFY (6-layer check)"
      "If XL epic → split into L milestones first, run full cycle per milestone"
    ]}
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
      "If root cause is an architectural issue → escalate to architecture-expert."
      "If fix requires a large refactor (> 10 files) → hand off to feature-workflow for full planning cycle."
      "If the bug is in production only → gather logs/observability data before starting step 01."
    ]}
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

    Automatically extract reusable patterns from interactions and promote them to skills.

    ## Instinct Format
    Each extracted pattern is an "instinct":
    ```yaml
    title: Short descriptive name
    category: architecture | workflow | testing | nix | debugging | style
    evidence:
      - "session X: did Y because Z"
      - "session X: same pattern applied to W"
    confidence: 0-100 (based on repetition + outcome)
    examples:
      - "When X, always do Y"
    counter_examples:
      - "Except when Z, then do W instead"
    ```

    ## Extraction Rules
    - Minimum 3 occurrences of same pattern across sessions
    - Confidence >= 70 to record as instinct
    - Only extract patterns that are NOT already in CLAUDE.md or existing skills
    - Focus on: recurring decisions, repeated fix patterns, project-specific conventions

    ## Promotion Pipeline
    1. **Record**: Save instinct to `~/.claude/generated/instincts.jsonl`
    2. **Cluster**: When 3+ instincts share the same category/topic → candidate for skill
    3. **Generate**: Auto-create skill file in `~/.claude/skills/generated/{topic}/SKILL.md`
       - Include: description, frontmatter with globs, all evidence
       - Mark as `status: draft` until manually reviewed
    4. **Validate**: Usage threshold >= 5 applied references → promote to `status: active`

    ## Application Rules
    - Max 3 suggestions per session (avoid noise)
    - Relevance threshold 0.8 (only suggest when highly relevant)
    - Never suggest instincts that contradict CLAUDE.md rules
    - Prefer suggesting existing skills before creating new ones

    ## Review Trigger
    When instincts.jsonl exceeds 20 entries, suggest a review:
    - Prune low-confidence entries (< 50)
    - Merge overlapping instincts
    - Promote mature clusters to skills

    ## Output
    - Instincts: `~/.claude/generated/instincts.jsonl`
    - Generated skills: `~/.claude/skills/generated/`

    ${contract {
      expects = "session patterns (automatic from conversation history) or explicit pattern description from user.";
      produces = "instincts.jsonl entries (record), generated SKILL.md drafts (promote).";
      sideEffects = "writes to ~/.claude/generated/instincts.jsonl and ~/.claude/skills/generated/{topic}/SKILL.md.";
    }}
    ${scope {
      useWhen = "Extracting recurring patterns from sessions, clustering instincts by category, or promoting mature instinct clusters to generated skills.";
      notFor = "Direct code changes, feature implementation, bug fixes, or writing new skills manually.";
    }}
    ${handoffs [
      "When an instinct cluster reaches promotion threshold → use schliff to validate the generated skill quality before activating."
      "If a generated skill contradicts CLAUDE.md → flag for manual review, do not promote automatically."
      "After promoting a skill to active → update the skills.nix file via the nix-darwin skill workflow."
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
    globs: ["**/claude-code/*.nix", "**/.claude/**/*.md"]
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
      "If testing requires architectural changes → escalate to architecture-expert"
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
      notFor = "implementing fixes (hand off to relevant agent), security penetration testing (use security-auditor), or performance profiling (use performance-expert).";
    }}
    ${handoffs [
      "Dead exports/orphan files → hand off to quick-fix agent for removal"
      "Config drift → hand off to nix-expert or relevant specialist"
      "Test coverage gaps → hand off with testing-patterns skill for test creation"
      "Security items → hand off to security-auditor for deep analysis"
      "Bloated files → hand off to architecture-expert for decomposition plan"
    ]}
  '';
}
