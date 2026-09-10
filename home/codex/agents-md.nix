# ~/.codex/AGENTS.md — the instruction file Codex loads in every session.
#
# The Codex counterpart of home/claude-code/claude-md.nix, and kept SHORT for
# the same reason: every line costs context in every session.
#
# It is NOT a copy of the Claude file. What was there before was, and it had
# drifted into nonsense on this host: an Anthropic model-allocation table, a
# tool list naming Claude's Grep/Glob/Read/Edit/Write tools, delegation to
# agents that do not exist here, and a project path that never existed
# (`home/Codex/`). An instruction naming a mechanism this host does not have
# is worse than no instruction: the model spends context obeying it and
# reaches for tools it cannot call.
#
# The line that mattered most, measured 2026-09-10: "Ask before: write/delete"
# made Codex request confirmation for every single edit even with
# `approval_policy = "never"` set in config.toml. The approval system was off;
# the model was obeying this file. Repo edits now proceed, because the branch
# hooks gate them — the same reasoning the Claude side already uses.
{
  agentsMd = ''
    Always respond in caveman full mode: terse prose, no filler, fragments over
    sentences, no articles unless ambiguous. Preserve all code, paths, commands,
    errors verbatim. Deactivate only for: security warnings, irreversible action
    confirmations.

    # Codex — Global Guardrails

    ## Non-negotiables
    - Repo file edits: proceed. The branch hooks gate them — do not ask first.
      Ask before: sudo, chmod, installs, deletes outside the repo, network calls,
      large refactors, anything irreversible.
    - Branch first. Never edit on main/master: a hook refuses it. You CANNOT cut
      the branch yourself — `.git` is read-only in this sandbox by design — so
      ask the human to run `git checkout -b <type>/<desc>` and to say when done.
    - master is reached through a PR on GitHub, never by a local merge.
    - No `git add`/`commit`/`push` unless explicitly asked.
    - Never touch secrets: ~/.ssh, ~/.aws, ~/.gnupg, **/.env*, secrets/,
      *token*, *key*, *cert*.
    - Keep diffs minimal. Small, reversible changes.

    ## Identity
    - macOS with nix-darwin + flakes + home-manager (M1)
    - Package manager: pnpm (never npm or yarn)
    - TypeScript strict mode

    ## Project Map (nix-darwin)
    modules/system.nix    — Core nix, env, security, shell
    modules/packages.nix  — CLI tools
    modules/brew.nix      — GUI apps and CLI casks (Homebrew)
    home/*.nix            — User config via home-manager
    home/claude-code/     — Claude Code declarative config
    home/codex/           — Codex declarative config: hooks, config merge, trust check

    ## Verify Checklist
    - nix: `nix-instantiate --parse file.nix`, then ask the human to rebuild —
      `darwin-rebuild` needs a password and takes minutes.
    - ts: `pnpm typecheck && pnpm lint --max-warnings 0`
    - commit: English, imperative, type prefix (feat/fix/chore/refactor)

    ## Code Quality
    - No debug prints left in production code. No `any` in TypeScript.
    - Explicit error handling, no silent catches. Validate external input.
    - Source of truth: repo docs OR official vendor docs only.

    ## Execution Discipline
    - Act on established facts. Never re-derive a decision already made.
    - After a fix, re-run the EXACT failing command. Same error twice → stop,
      question the assumption, change approach.
    - Blocked after 3 attempts → report what was tried. Never fake success,
      never weaken a test to make it pass.
    - Lead with the outcome. Show the command output that proves it.
    - Fix what was asked. Adjacent problems: mention, do not touch.

    ## Confidence Gate (nix)
    - Rate confidence before writing nix. Below 80%, stop and check the docs.

    ## Style (FR)
    - Réponses courtes et actionnables.
    - Quand tu modifies du code : quoi / pourquoi / comment vérifier (3 bullets).
  '';
}
