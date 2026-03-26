# Skill definitions
{
  skillApex = ''
    ---
    name: apex
    description: "Systematic implementation using APEX methodology"
    disable-model-invocation: true
    context: fork
    ---

    # APEX: Systematic Implementation

    Flags: -a (auto), -s (save), -e (examine), -t (test), -h (help)

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
  '';

  # -------------------------
  # Feature Workflow Skill
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
    disable-model-invocation: true
    context: fork
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
  '';

  # -------------------------
  # Schliff — SKILL.md quality linter
  # -------------------------
  skillSchliff = ''
    ---
    name: schliff
    description: "Analyze and score SKILL.md quality using Schliff linter. Use when tasks mention skill quality, skill audit, skill score, or skill optimization."
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
  '';

  # -------------------------
  # Autoresearch — Autonomous experiment loop
  # -------------------------
  skillAutoresearch = ''
    ---
    name: autoresearch
    description: "Set up and run an autonomous experiment loop for any optimization target. Use when asked to run autoresearch, optimize X in a loop, set up autoresearch for X, or start experiments."
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
  '';
}
