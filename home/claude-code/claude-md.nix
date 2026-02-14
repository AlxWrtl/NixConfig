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

    ## Tools
    - Format: prettier (auto-runs via hook on .ts/.tsx/.js/.jsx/.css/.json)
    - Lint: eslint (run manually: pnpm lint)
    - Types: pnpm tsc --noEmit
    - Build: pnpm build

    ## Style (FR)
    - Réponses courtes et actionnables.
    - Si tu hésites : 2–3 hypothèses max, puis la plus probable.
    - Quand tu modifies du code : quoi / pourquoi / comment vérifier (3 bullets).

    ## Plans
    - End each plan with unresolved questions (if any). Ultra concise.
  '';
}
