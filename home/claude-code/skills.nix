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
  skillApex = ''
    ---
    name: apex
    description: "Systematic implementation using APEX methodology"
    effort: high
    ---

    # APEX: Systematic Implementation

    Flags: -a (auto), -s (save), -e (examine), -t (test), -h (help)

    ## Interaction Mode
    After each step, present a summary of what was done and what comes next.
    Wait for user approval before proceeding to the next step.
    If the user says "continue" or "ok", proceed. If they give feedback, adapt.
    With -a flag: skip approval, run all steps autonomously.

    ## Steps

    ### 00 — Initialize
    Set up task context, check git status, create output dir.

    ### 01 — Analyze
    Read files, identify patterns, document requirements.

    ### 02 — Plan
    Propose approaches, break down tasks, identify risks.

    ### 03 — Prepare
    Create branch, install deps, create stubs.

    ### 04 — Execute
    Implement solution following plan.

    ### 05 — Test
    Run tests, verify implementation.

    ### 06 — Examine
    Deep review: security, performance, maintainability.

    ### 07 — Polish
    Clean up code, refine, improve naming.

    ### 08 — Document
    Update docs, README, CHANGELOG.

    ### 09 — Finish
    Final verification, commit, summarize.

    ${contract {
      expects = "task description + complexity classification (M/L). Optional: existing CLAUDE.md and project context.";
      produces = "implementation across 9 steps (initialize → analyze → plan → prepare → execute → test → examine → polish → finish).";
      sideEffects = "modifies source files, creates tests, updates docs, commits on each kept step.";
    }}
    ${scope {
      useWhen = "Implementing a well-defined M/L feature, module, or task that benefits from structured 9-step execution.";
      notFor = "Quick fixes, one-liners, debugging, exploratory research, or code review.";
    }}
    ${handoffs [
      "If task is broken and needs diagnosis → use debug skill instead."
      "If scope is unclear → run feature-workflow DISCUSS phase first."
      "After step 05-Test fails repeatedly → hand off to debug skill for root-cause analysis."
      "After step 09-Finish on L/XL changes → hand off to code-reviewer agent."
    ]}
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

    Vault path: `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/AlxVault`

    No MCP server needed — use native tools directly on the vault files.

    ## Tool Mapping
    | Action | Tool | Example |
    |--------|------|---------|
    | Search notes | `Grep` | `Grep(pattern: "keyword", path: "~/Library/Mobile Documents/.../AlxVault")` |
    | Read note | `Read` | `Read(file_path: ".../AlxVault/02-Projets/Preliz/Preliz.md")` |
    | List directory | `Glob` | `Glob(pattern: "**/*.md", path: ".../AlxVault/02-Projets/")` |
    | Create note | `Write` | `Write(file_path: ".../AlxVault/01-Inbox/new-note.md", content: "...")` |
    | Edit note | `Edit` | `Edit(file_path: "...", old_string: "...", new_string: "...")` |
    | Find by tag | `Grep` | `Grep(pattern: "tags:.*veille", path: ".../AlxVault")` |
    | Find by frontmatter | `Grep` | `Grep(pattern: "^date: 2026", path: ".../AlxVault", multiline: true)` |

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
    - La note doit TOUJOURS commencer par `[[02-Projets/[projet]/[projet]]]` en premiere ligne
    - Ensuite le titre `# YYYY-MM-DD - Sujet court`
    - Contenu : ce qui a ete fait, decisions prises, prochaines etapes

    ### Wikilinks
    - Toujours utiliser le chemin complet : `[[02-Projets/Preliz/Preliz]]`
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
