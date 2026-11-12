@AGENTS.md

## Claude only
- `nix flake check --no-build` fails inside the sandbox (read-only
  `~/.cache/nix`): run it with the sandbox off.
- Decisions taken: sandbox residual risk accepted (2026-09-27);
  mods rejected 2026-10-07 (rebuild guard, refusal log, third-party mods
  without auditable code); behavioural model-run TTW eval and scope ladder
  removed (the schliff `eval-suite.json` stays).
