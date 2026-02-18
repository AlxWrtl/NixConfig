# Skill definitions (APEX, Debug, Continuous Learning)
{
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
  # Feature Workflow Skill (NEW)
  # -------------------------
  skillFeatureWorkflow = ''
    ---
    description: Feature development methodology — discuss→plan→verify cycle. Referenced by architecture-expert, team-lead, code-reviewer.
    globs: ["**/.claude/output/feature/**", "**/.claude/output/CONTEXT-*"]
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
}
