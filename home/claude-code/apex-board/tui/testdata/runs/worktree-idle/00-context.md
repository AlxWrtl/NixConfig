# APEX: open .env to the sandbox + global worktree env-file sync hook
Date: 2026-10-19
Tier: High-stakes (sandbox denyRead/allowRead keys; new hook)
Flags: -t -f -x -pr -o -n -e
Branch: feat/worktree-env-sync (trunk: master)
Files: home/claude-code/settings.nix, home/claude-code/hooks.nix, home/claude-code/hooks/worktree-env-sync.sh (new), checks/hook-wiring.nix, README.md
Est-lines: ~120
Baseline: nix flake check --no-build -> pending

## Task
1. Remove `${homeDirectory}/**/.env` and `**/.env.*` from sandbox.filesystem.denyRead
   (settings.nix:261-262) and the now-useless allowRead `.env.example` / `.env.template`
   (settings.nix:291-292). KEEP permissions.deny `Read(**/.env)` / `Read(**/.env.*)`.
2. Global hook: when hook input `cwd` is a linked git worktree, copy from the main
   checkout the gitignored files `.env`, `.env.*`, `.dev.vars` that are absent in the
   worktree. Never overwrite.

## Unproven premises (plan must source or probe)
- hook commands run outside the Bash sandbox
- PostToolUse matcher `EnterWorktree` fires

## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 01-analyze | skipped | files known |
| 01b-obsidian | pending | |
| 02-plan | pending | |
| 03-execute | pending | |
| 04-validate | pending | |

## Tokens
Context growth, not billed tokens.

| phase | agent | model | tokens |
|-------|-------|-------|--------|

coordinator context: 113989→
