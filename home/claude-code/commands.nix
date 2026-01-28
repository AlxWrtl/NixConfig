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
