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
    - Route: `/apex -a "$ARGUMENTS"`
    - Reason: "Detected feature implementation"
    - Only `-a` is passed: apex's mode gate already resolves `-b -s -t -pr`
      by default, and `-a` is never auto-enabled — so it is the one flag
      this route still has to state.

    **DEBUG** (fix|bug|error|broken|failing|crash|why):
    - Route: `Task(subagent_type=debugger)` with the full task description
    - Reason: "Detected debugging task"
    - Note: the debug skill is user-invocable only (disable-model-invocation) —
      never route to `/debug` from here, use the debugger agent.

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
    → Execute: /apex -a "create health check"

    Input: "fix database timeout"
    → Routed to debugger agent because detected "fix" keyword
    → Execute: Task(subagent_type=debugger, prompt="fix database timeout")

    Input: "refactor all imports"
    → Routed to /ralph-loop because detected "refactor all" pattern
    → Execute: /ralph-loop "refactor all imports" --max-iterations 20

    Input: "where is auth logic"
    → Routed to codebase-navigator because detected "where" keyword
    → Execute: Task with codebase-navigator agent
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
  # Trello → APEX → double output trace (Trello comment/move + Obsidian note)
  # -------------------------
  cmdCard = ''
    ---
    tools: Bash, Read, Write, Edit, Grep, Glob, Skill, Task, AskUserQuestion
    description: "Run a Trello card through APEX, then write the result back to Trello and Obsidian."
    argument-hint: "<id|url|titre> [flags apex]"
    ---

    # Card: $ARGUMENTS

    ```
    DONE_LIST = "Done"    # destination list on success — adapt to the board
    ```

    Read `~/.claude/skills/trello/SKILL.md` first: it owns the auth mechanics and
    every write endpoint used here. This command adds only read endpoints of the
    same REST API v1.

    ## 0. Auth (verbatim from the trello skill)

    ```bash
    TRELLO_KEY=$(cat "$HOME/.config/secrets/trello-api-key")
    TRELLO_TOKEN=$(cat "$HOME/.config/secrets/trello-token")
    AUTH="key=$TRELLO_KEY&token=$TRELLO_TOKEN"
    ```

    Missing file, or any response containing `invalid key` / `invalid token` /
    `unauthorized permission requested`: STOP. Apply the skill's rule — ask the
    user to (re)populate `~/.config/secrets/trello-api-key` and
    `~/.config/secrets/trello-token` with a freshly generated key + token, then
    re-run. Never continue with empty or rejected credentials, never print them.

    ## 1. Resolve `<ref>` (every token of $ARGUMENTS up to the first flag)

    `<ref>` is NOT the first token: it is ALL tokens until the first one starting
    with `-`, joined by spaces. Card titles are multi-word, and stopping at token
    one would search for `Fix` instead of `Fix the login redirect`.

    Three forms, tested in this order:

    1. **Short id** — `<ref>` is a single token of 8 alphanumeric chars
       (`^[a-zA-Z0-9]{8}$`) → try it as CARD_ID. It is only a candidate: an
       8-character one-word title matches the same shape. If the load in step 2
       returns 404, do not stop — fall through to form 3 and search that same
       token as a title.
    2. **URL** — contains `trello.com/c/` → the id is the segment right after
       `/c/`, e.g. `https://trello.com/c/aB3dEf9h/12-title` → `aB3dEf9h`.
    3. **Otherwise: title search**

       ```bash
       curl -s "https://api.trello.com/1/search?modelTypes=cards&cards_limit=10&$AUTH" \
         --data-urlencode "query=<TITLE>" -G \
         | jq -r '.cards[] | "\(.id)  \(.name)  \(.shortUrl)"'
       ```

       - 0 hit → STOP, say the card was not found. Do NOT create anything.
       - 1 hit → that card.
       - 2+ hits → list the candidates (id, name, shortUrl) and `AskUserQuestion`.
         NEVER guess, never pick the first.

    ## 2. Load the card (read-only)

    ```bash
    curl -s "https://api.trello.com/1/cards/$CARD_ID?fields=name,desc,idList,idBoard,shortUrl&labels=all&$AUTH"
    curl -s "https://api.trello.com/1/cards/$CARD_ID/checklists?$AUTH"
    curl -s "https://api.trello.com/1/cards/$CARD_ID/actions?filter=commentCard&limit=10&$AUTH"
    ```

    Resolve the list and board display names from `idList` / `idBoard`
    (`GET /1/boards/<BOARD_ID>/lists?fields=name,id` — skill endpoint).

    If the card cannot be loaded (404, empty body, auth error): STOP and say so.
    Do not continue without a card — there is no task to run. The one exception is
    the 404 of a form-1 candidate id, which falls back to the title search of
    step 1 form 3; if that search also fails, STOP.

    ## 3. APEX brief

    Invoke the `apex` skill with a brief built from the card:

    - **Task** = card name + description, quoted VERBATIM. The card IS the spec:
      its text is an admissible premise source, not a paraphrase to reinterpret.
    - **Acceptance criteria candidates** = the checklist items (each unchecked
      item is a candidate AC; state which ones you adopted).
    - **Context** = the last 10 comments (author + date + text).
    - **Reference** = card id, shortUrl, board and list names.
    - **Flags**: the flags typed after `<ref>` in $ARGUMENTS are a FLOOR (forced
      ON). Every other flag is left to the APEX Mode Gate — impose no flag set,
      do not pre-decide the mode.
    - **`-o`, `-n` and `-pr` are constitutive of `/card`**: always add them to the
      floor, whatever the mode. `-o` and `-n` close the vault continuity loop (load
      context before planning, write the session note at the end); `-pr` is what
      makes a card run finishable — section 4 only fires on a PR, so without it
      the success condition is unreachable and the write-back never happens.

    The session note written by `-n` (step-09b) MUST additionally contain:

    - the card reference — id + full URL — in the `## Liens` section;
    - a `## Reste` section listing what was NOT done: unadopted checklist items,
      deferred ACs, open questions. Empty is allowed only if truly nothing remains,
      and then write `- rien`.

    ## 4. On a SUCCESSFUL run only (PR created)

    Two writes, in this order:

    1. **Trello comment** (skill endpoint):

       ```bash
       curl -s -X POST "https://api.trello.com/1/cards/$CARD_ID/actions/comments?$AUTH" \
         --data-urlencode "text=<SUMMARY>" >/dev/null
       ```

       `<SUMMARY>` = 3-5 lines: what was implemented, how it was verified, then
       the PR URL on its own last line.

    2. **Move to DONE_LIST** — resolve the name to an id first, then move
       (both skill endpoints):

       ```bash
       DEST=$(curl -s "https://api.trello.com/1/boards/$BOARD_ID/lists?fields=name,id&$AUTH" \
         | jq -r --arg n "$DONE_LIST" '.[] | select(.name == $n) | .id')
       curl -s -X PUT "https://api.trello.com/1/cards/$CARD_ID?$AUTH" \
         --data-urlencode "idList=$DEST" >/dev/null
       ```

       No list matches `DONE_LIST` → keep the comment, skip the move, and report
       the mismatch with the board's actual list names.

    3. **Obsidian** — the standard `-n` note, enriched as described in step 3.

    ## 5. Guardrails

    - NO Trello write before a successful end of run. The comment and the move are
      the last actions, never optimistic, never partial-progress reporting.
    - Failed, blocked or aborted run → ZERO Trello write. Say it explicitly:
      "no Trello write — run did not complete", plus what blocked it. The Obsidian
      note may still be written (it is a trace, not a status claim) and must then
      record the failure in `## Reste`.
    - Card not found or auth rejected → stop at that point, per sections 0 and 1.
    - Never delete a card, never edit its name or description.
    - Test writes (throwaway cards, command validation, dry runs) go to the
      no-stakes board **Tech & Pit** — never to the target board. Reading is fine
      anywhere; only test WRITES are restricted. (User rule, 2026-08-14.)
  '';

  # ── Feature methodology commands ──

  commandDiscuss = ''
    Capture implementation decisions before planning a feature.
    Run this BEFORE any planning step (/apex, Plan agent, feature-chain.sh).
    Produces a CONTEXT.md that all subsequent agents reference.

    ## Input

    Feature description: $ARGUMENTS

    ## Step 1 — Classify

    Read project CLAUDE.md for domain map, then determine:
    - **Domains:** Which parts of the codebase are touched?
    - **Users:** Which user types affected? Primary device/context?
    - **Complexity:** S (< 5 files, 1 agent) / M (5-15 files, 2-3 agents) / L (15+ files, /apex -m waves)
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
    - M → "Run /apex referencing this context (plan step reads CONTEXT-*.md)"
    - L → "Run /apex -m (teams) or feature-chain.sh referencing this context"
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

}
