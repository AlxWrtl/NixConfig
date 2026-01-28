# Documentation strings for Claude Code
{
  claudeMdText = ''
    # Claude Code — Global Guardrails

    ## Non-negotiables (EN)
    - Be extremely concise (incl. commit messages). Sacrifice grammar for brevity.
    - Read before write. Propose a short plan before any edits.
    - Ask before: write/delete, chmod, sudo, installs, network calls, or large refactors.
    - Never touch secrets: ~/.ssh, ~/.aws, ~/.gnupg, **/.env*, secrets/, *token*, *key*, *cert*.
    - No git add/commit/push unless explicitly asked.
    - Keep diffs minimal. Prefer small, reversible changes.
    - Prefer targeted tests; run full suite only when requested or clearly required.

    ## Official docs + senior standards (GLOBAL)
    - Source of truth: repo docs OR official vendor docs only.
    - If version/spec unclear: STOP + ask me.
    - No WebSearch. WebFetch only if allowed by allowlist.
    - Every code change: Doc ref + Code ref + Verify step.

    ## Style (FR)
    - Réponses courtes et actionnables.
    - Si tu hésites : 2–3 hypothèses max, puis la plus probable.
    - Quand tu modifies du code : quoi / pourquoi / comment vérifier (3 bullets).

    ## Plans
    - End each plan with unresolved questions (if any). Ultra concise.
  '';

  autoRoutingText = ''
    # Auto-Routing + Model Selection

    ## Agent Selection
    - Use most specialized agent for task
    - quick-fix / code-reviewer for small changes
    - nix-expert for *.nix / darwin-rebuild / flakes
    - If unsure: codebase-navigator first, then delegate

    ## Model Selection (Cost Optimization - Claude 4.5)
    ### Haiku 4.5 ($1/$5) - Fast + Cheap
    - Model: claude-haiku-4-5-20251001
    - Agents: quick-fix, code-reviewer, database-expert, performance-expert, codebase-navigator, nix-expert, git-ship
    - Use for: Simple tasks, typos, quick reviews, navigation
    - Extended thinking: Disable (cache efficiency)

    ### Sonnet 4.5 ($3/$15) - Production Quality [DEFAULT]
    - Model: claude-sonnet-4-5-20250929
    - Agents: frontend-expert, backend-expert, devops-expert, ai-ml-expert, architecture-expert
    - Use for: Complex features, refactoring, architecture
    - Extended thinking: Enable for coding/complex tasks

    ### Opus 4.5 ($5/$25) - High Intelligence, More Accessible
    - Model: claude-opus-4-5-20251101
    - Use for: Maximum capability tasks, effort parameter support
    - Reserved for: Explicit requests, critical decisions only

    **Cost savings: 60-70% via intelligent routing**
    **Note**: MCP auto mode enabled by default (v2.1.7+)
  '';
}
