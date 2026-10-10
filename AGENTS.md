# nix-darwin — project notes

Host `alex-mbp` (Apple Silicon): flake + nix-darwin + home-manager. Structure,
checks and commands live in `README.md`; this file holds only the traps.

## Gate
- `nix flake check --no-build` before every commit touching `.nix`;
  `format-check` fails on formatting alone, run `nixfmt` on edited files first.
- The flake ignores untracked files: `git add` a new file before checking,
  or it does not exist for the check.
- A green check proves nothing until it can fail: break it once (canary)
  before citing it, a lazy stub or an empty list passes everything.

## Apply
- `sudo darwin-rebuild switch --flake .#alex-mbp` is run by the user
  (password). Switch from `master` after the merge: switching from an older
  branch silently reverts the PRs merged since.
- Removing a Brewfile entry UNINSTALLS it (`--zap`), App Store apps included.
- A failing cask stops activation before home-manager runs.

## Edit
- Agent config is generated: edit `home/claude-code/*.nix`, never the files
  under `~/.claude` or `~/.codex`, which activation rewrites. The live
  `settings.json` is a merge; the keys nix forces are listed in
  `home/claude-code/activation.nix`.
- The global instruction text shared by both agents lives in
  `home/claude-code/agent-instructions.nix`; per-agent deltas are spliced in.
- `master` is protected: change it through a PR only.
