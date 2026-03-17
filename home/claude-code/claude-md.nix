# Global CLAUDE.md content (< 100 lines)
{
  claudeMdGlobal = ''
    # Claude Code — Global Guardrails

    ## Non-negotiables (EN)
    - Be extremely concise (incl. commit messages). Sacrifice grammar for brevity.
    - Read before write. Propose a short plan before any edits.
    - Ask before: write/delete, chmod, sudo, installs, network calls, or large refactors.
    - Never touch secrets: ~/.ssh, ~/.aws, ~/.gnupg, **/.env*, secrets/, *token*, *key*, *cert*.
    - No git add/commit/push unless explicitly asked.
    - Keep diffs minimal. Prefer small, reversible changes.
    - Prefer targeted tests; run full suite only when requested or clearly required.

    ## Identity
    - macOS with nix-darwin declarative configuration
    - Package manager: pnpm (never npm or yarn)
    - TypeScript strict mode by default
    - All code must be accessible (WCAG AA minimum)

    ## Official docs + senior standards (GLOBAL)
    - Source of truth: repo docs OR official vendor docs only.
    - If version/spec unclear: STOP + ask me.
    - No WebSearch. WebFetch only if allowed by allowlist.
    - Every code change: Doc ref + Code ref + Verify step.

    ## Workflow Rules
    - ALWAYS run verification commands before marking work as done.
    - ALWAYS check for existing utilities/components before creating new ones.
    - One concern per commit.
    - Commit messages: English, imperative, type prefix (feat/fix/chore/refactor).

    ## Code Quality
    - No console.log in production code (use proper logging).
    - No `any` types in TypeScript.
    - Explicit error handling (no silent catches).
    - Input validation on all external data.

    ## When Compacting
    - Preserve: modified files list, test results, design decisions, next steps.
    - Preserve: error patterns encountered and their solutions.
    - Discard: file contents already committed, redundant exploration.

    ## Agents & Skills
    - Specialist agents in ~/.claude/agents/. Delegate when task matches.
    - Project skills in .claude/skills/*/SKILL.md. Read matching skills before coding.

    ## Agent Auto-Routing

    Before starting ANY task, silently assess complexity using this decision tree.
    Do NOT explain your routing decision unless asked. Just act.

    ### Decision tree
    ```
    Task received
    │
    ├─ Typo / rename / single-line fix?
    │   └─ @quick-fix (Haiku)
    │
    ├─ Git commit/push only?
    │   └─ @git-ship (Haiku)
    │
    ├─ "Where is X" / "how does Y work" / exploration?
    │   └─ @codebase-navigator (Haiku) → then specialist if needed
    │
    ├─ Nix config change?
    │   └─ @nix-expert (Sonnet)
    │
    ├─ Review / audit / pre-merge?
    │   └─ @code-reviewer (Opus)
    │
    ├─ Slow / latency / bottleneck / bundle size?
    │   └─ @performance-expert (Haiku)
    │
    ├─ Single domain, ≤ 3 files, clear scope?
    │   ├─ UI/component/style → @frontend-expert (Sonnet)
    │   └─ API/DB/auth/server → @backend-expert (Sonnet)
    │
    ├─ Touches frontend AND backend (e.g. new feature end-to-end)?
    │   └─ @team-lead (Opus) — delegates to specialists
    │
    ├─ > 5 files OR multiple domains OR uncertain scope?
    │   └─ @team-lead (Opus)
    │
    ├─ Same pattern repeated across N files (N ≥ 4)?
    │   └─ ralph-loop
    │
    └─ Architecture decision / major refactor?
        └─ @architecture-expert (Opus) for design
           then @team-lead for execution
    ```

    ### Hard rules
    - Always run @codebase-navigator BEFORE implementation if scope is unclear.
    - After implementation: each agent runs its own verification (typecheck + lint).
    - Never implement directly when @team-lead is the right call.
    - APEX (/apex) only when team-lead itself needs orchestration (rare, costly).

    ## Style (FR)
    - Réponses courtes et actionnables.
    - Si tu hésites : 2–3 hypothèses max, puis la plus probable.
    - Quand tu modifies du code : quoi / pourquoi / comment vérifier (3 bullets).

    ## Plans
    - End each plan with unresolved questions (if any). Ultra concise.
  '';
}
