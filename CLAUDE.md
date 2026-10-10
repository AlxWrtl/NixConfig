@AGENTS.md

## Claude only
- `nix flake check --no-build` fails inside the sandbox (read-only
  `~/.cache/nix`): run it with the sandbox off. Bare `nix flake check` is
  sandbox-excluded when it is the whole Bash call.
- Mods (`home/claude-code/mods/`): their code gate is `claude plugin validate
  --strict` + `claude plugin test` on the mod folder, run in the session (not
  in the flake). `validate` does not typecheck: a type error passes it, run
  `tsc` on a copy with the engine's types. Authoring: skill `plugin-authoring`.
- `compactWindow` / `contextFill` exist twice
  (`home/claude-code/mods/status-bar/hooks/format.ts`,
  `home/claude-code/mods/deck/hooks/core.ts`): change both.
- A new Claude hook needs a case in `checks/hook-wiring.nix`, and a canary
  for its deny/allow branch.
- Skills are Claude-only: a new skill file goes into
  `home/claude-code/skills-manifest.nix` in the same edit.
- `model` in `home/claude-code/settings.nix` is never forced, but it re-seeds
  the live value whenever `/model` has removed the key: keep it equal to the
  intended default.
- Rules with `paths:` are not re-injected after `/compact`. Observed by
  probe, undocumented: they fire only for files under the current project
  root, and an unknown frontmatter key (`globs:`) is ignored without error.
- Read-only diagnostics inherit the sandbox and report it as a property of
  their target (`claude mcp list`, `mdutil`, `rtk`): confirm outside the
  sandbox. A nested `claude` cannot use Bash; not fixable through settings.
- Repo tools: `apex-tier --base master` (tier of the real diff),
  `apex-health --repo .` (APEX drift, no model call), `trello` (test writes
  on the Tech & Pit board only).
- Vault: `~/Vaults/AlxVault/02-Projets/nix-darwin/` — hub `nix-darwin.md`,
  then `sessions/` by date (the hub's session list is not kept up to date).
- Settled, do not re-propose: sandbox residual risk accepted (2026-09-27);
  mods rejected 2026-10-07 (rebuild guard, refusal log, third-party mods
  without auditable code); behavioural model-run APEX eval and scope ladder
  removed (the schliff `eval-suite.json` stays).
