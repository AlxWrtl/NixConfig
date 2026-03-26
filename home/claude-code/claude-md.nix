# Global CLAUDE.md content (< 80 lines)
{
  claudeMdGlobal = ''
    # Claude Code — Global Guardrails

    ## Non-negotiables
    - Be extremely concise. Sacrifice grammar for brevity.
    - Read before write. Short plan before any edits.
    - Ask before: write/delete, chmod, sudo, installs, network calls, large refactors.
    - Never touch secrets: ~/.ssh, ~/.aws, ~/.gnupg, **/.env*, secrets/, *token*, *key*, *cert*.
    - No git add/commit/push unless explicitly asked.
    - Keep diffs minimal. Small, reversible changes.

    ## Identity
    - macOS with nix-darwin + flakes + home-manager (M1)
    - Package manager: pnpm (never npm or yarn)
    - TypeScript strict mode
    - WCAG AA accessibility minimum

    ## Project Map (nix-darwin)
    modules/system.nix    — Core nix, env, security, shell
    modules/packages.nix  — CLI tools
    modules/services.nix  — Background services (launchd)
    modules/ui.nix        — Fonts, Dock, Finder, system.defaults
    modules/brew.nix      — GUI apps (Homebrew)
    home/*.nix            — User config via home-manager
    home/claude-code/     — Claude Code declarative config

    ## Model Allocation
    Architecture/planning/review: opus | Implementation: sonnet | Exploration/tests: haiku

    ## Verify Checklist
    - nix: `nix-instantiate --parse file.nix && sudo darwin-rebuild switch --flake .#alex-mbp`
    - ts: `pnpm typecheck && pnpm lint --max-warnings 0`
    - git: never commit on main/master, one concern per commit
    - commit: English, imperative, type prefix (feat/fix/chore/refactor)

    ## Code Quality
    - No console.log in production (proper logging).
    - No `any` types in TypeScript.
    - Explicit error handling (no silent catches).
    - Input validation on all external data.
    - Source of truth: repo docs OR official vendor docs only.

    ## Delegation
    - Specialist agents in ~/.claude/agents/. Delegate to matching agent.
    - Read project skills before coding (auto-injected via agent frontmatter).
    - Multi-domain or > 5 files → @team-lead. Repeated pattern (N >= 4) → ralph-loop.

    ## When Compacting
    - Preserve: modified files, test results, design decisions, next steps, error patterns.
    - Discard: file contents already committed, redundant exploration.

    ## Style (FR)
    - Reponses courtes et actionnables.
    - Quand tu modifies du code : quoi / pourquoi / comment verifier (3 bullets).
  '';
}
