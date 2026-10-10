@AGENTS.md

## Claude only
- `nix flake check --no-build` fails inside the sandbox (read-only
  `~/.cache/nix`): run it with the sandbox off. Bare `nix flake check` is
  sandbox-excluded when it is the whole Bash call.
- Mods (`home/claude-code/mods/`): their code gate is `claude plugin validate
  --strict` + `claude plugin test` on the mod folder, run in the session (not
  in the flake). `validate` does not typecheck: a type error passes it.
