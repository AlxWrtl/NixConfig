# Global CLAUDE.md content (< 100 lines — every line costs context in EVERY session)
{
  claudeMdGlobal = ''
    @RTK.md

    Always respond in caveman full mode: terse prose, no filler, fragments over sentences,
    no articles unless ambiguous. Preserve all code, paths, commands, errors verbatim.
    Deactivate only for: security warnings, irreversible action confirmations.

    # Claude Code — Global Guardrails

    ## Non-negotiables
    - Repo file edits: proceed (acceptEdits + hooks gate them). Ask before: sudo,
      chmod, installs, deletes outside repo, large refactors, anything irreversible.
    - Git: branch FIRST — `git checkout -b <type>/<desc>` BEFORE coding; never
      commit on main/master (hooks deny it), master via PR only. End-of-run
      commit+PR is pre-authorized by the apex `-pr` default; any other
      add/commit/push still needs an explicit ask.
    - Keep diffs minimal. Small, reversible changes.

    ## Identity
    - macOS with nix-darwin + flakes + home-manager (M1)
    - Package manager: pnpm (never npm or yarn).

    ## Project Map (nix-darwin)
    modules/system.nix    — Core nix, env, security, shell
    modules/packages.nix  — CLI tools
    modules/services.nix  — Background services (launchd)
    modules/ui.nix        — Fonts, Dock, Finder, system.defaults
    modules/brew.nix      — GUI apps (Homebrew)
    home/*.nix            — User config via home-manager
    home/claude-code/     — Claude Code declarative config

    ## Model Allocation
    Défaut = opus 5 (workhorse full-loop: coordonne + plan + code + auto-verif
    fresh-context), 1M ctx. Effort-tiering DANS opus 5 avant de switcher modèle
    (switch = taxe subagent ~15×): low mécanique, high/max plan+verif. Subagents:
    JAMAIS inherit — model explicite. Mécanique/explo/tests: haiku | Volumineux
    gros contexte: sonnet-5 | Impl/debug: opus 5.
    Fable = vérificateur INDÉPENDANT read-only, rationné haut-enjeu (irréversible/
    sécu/archi/prod): lit diff réel + ACs → PASS ou fix-list bornée, ne code
    JAMAIS. Quota 5h/7j rare → garder pour le diff critique. Opus 5 ≈ fable (bat
    7 bench/12, moitié prix, meilleur auto-verif); edge fable réel = cyber
    offensif/exploit + bio autonome. Fable invoqué → classifier cyber/bio peut
    fallback Opus 4.8. /effort max = frontier only.

    ## Verify Checklist
    - commit: English, imperative, type prefix (feat/fix/chore/refactor)
    - nix / TS specifics: `~/.claude/rules/` — loaded on opening a matching file.

    ## Tool Selection (forbidden → required)
    - `echo >` / heredoc → Write tool | `curl` for docs → WebFetch tool
    - Multi-line script → write to scratchpad, run the file. Never `node -e` /
      `python3 -c` inline: operators in the body break the permission matcher.

    ## Delegation
    - Pattern répété N>=4 séquentiel mêmes fichiers → ralph-loop. Sous-tâches
      indépendantes fichiers disjoints → /fork background. Combinables:
      fork par module, ralph dedans.
    - Review routine qualité → /code-review natif (subagent background, hors
      contexte). Agent code-reviewer = spec compliance + sécu critique pre-merge.

    ## Execution Discipline (all models)
    - Act on established facts. Never re-derive or re-litigate decisions.
      Source of truth: repo docs OR official vendor docs only.
    - After a fix: re-run the EXACT failing command. Green = done, state it plainly.
      Same error twice → STOP retrying, question the assumption, change approach.
    - Blocked after 3 attempts → report findings + what was tried. Never fake success,
      never weaken a test/check to make it pass.
    - Lead with outcome: first sentence = result. Show evidence, not assertions —
      paste the exact test/command output that proves it.
    - Scope lock: fix what was asked. Adjacent problems → mention, don't touch.

    ## Style (FR)
    - Quand tu modifies du code : quoi / pourquoi / comment verifier (3 bullets).
  '';
}
