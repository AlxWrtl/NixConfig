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

    Auto-extract patterns from interactions.

    Extraction: min 3 changes, 0.7 confidence
    Promotion: usage threshold 5, auto-generate
    Application: auto-suggest, relevance 0.8, max 3

    Generated skills → ~/.claude/skills/generated/
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
  # Obsidian Vault Skill (mcpvault)
  # -------------------------
  skillObsidian = ''
    ---
    name: obsidian
    description: "Read, search, and write notes in the Obsidian vault via mcpvault MCP server. Use when the user mentions notes, vault, Obsidian, knowledge base, or wants to search/create/edit markdown notes."
    ---

    # Obsidian Vault (mcpvault)

    MCP server: `obsidian` — connects to AlxVault via @bitbonsai/mcpvault.

    ## Available Tools
    | Tool | Purpose |
    |------|---------|
    | `search_notes` | Search by content or frontmatter (BM25 ranking) |
    | `read_note` | Read a note with parsed frontmatter |
    | `read_multiple_notes` | Batch read (max 10 files) |
    | `write_note` | Create/overwrite a note with optional frontmatter |
    | `patch_note` | Replace exact string in a note (no full rewrite) |
    | `list_directory` | List files/dirs in vault |
    | `get_frontmatter` | Extract frontmatter only |
    | `update_frontmatter` | Update frontmatter without changing content |
    | `manage_tags` | Add/remove/list tags |
    | `get_notes_info` | Metadata without full content |
    | `get_vault_stats` | High-level vault statistics |
    | `move_note` | Move/rename a note |
    | `delete_note` | Delete (requires confirmation) |

    ## Vault Structure
    - `00-Meta/` — Templates, vault config
    - `01-Inbox/` — Quick capture, unsorted
    - `02-Projets/` — Active projects
    - `03-Areas/` — Ongoing areas of responsibility
    - `04-Resources/` — Reference material

    ## Guidelines
    - Prefer `search_notes` before creating to avoid duplicates
    - Use `patch_note` for small edits, `write_note` for new notes
    - Respect existing frontmatter — use `update_frontmatter` to modify
    - New notes: place in `01-Inbox/` unless the user specifies otherwise
    - Always confirm before `delete_note`

    ## Conventions Alx

    ### Démarrage de session
    - Toujours lire `00-Meta/CLAUDE.md` en début de session pour charger le contexte
    - Si un projet est mentionné, lire aussi `02-Projets/[projet]/[projet].md`

    ### Sessions
    - Nom du fichier : `YYYY-MM-DD - sujet-court.md` dans `02-Projets/[projet]/sessions/`
    - La note doit TOUJOURS commencer par `[[02-Projets/[projet]/[projet]]]` en première ligne
    - Ensuite le titre `# YYYY-MM-DD - Sujet court`
    - Contenu : ce qui a été fait, décisions prises, prochaines étapes
    - Exemple : `02-Projets/Preliz/sessions/2026-03-23 - Audit vault Obsidian.md`

    ### Wikilinks
    - Toujours utiliser le chemin complet : `[[02-Projets/Preliz/Preliz]]`
    - Ne jamais créer de wikilink sans chemin complet (évite les nœuds orphelins dans le graph)

    ### Règles
    - Ne jamais modifier les fichiers dans `decisions/` sans demander
    - `01-Inbox/` = capture brute, ne pas restructurer sans accord
    - Toujours répondre en français sauf pour le code
  '';
}
