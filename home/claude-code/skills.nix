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
