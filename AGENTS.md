# nix-darwin — project notes

Host `alex-mbp` (Apple Silicon): flake + nix-darwin + home-manager. Remote
`AlxWrtl/NixConfig`. Structure, every check and the commands live in
`README.md` (the map; a copy here would drift). This file holds the traps.

## Gate
- No CI: the gate is local. `nix flake check --no-build` before every commit
  touching `.nix`; `format-check` fails on formatting alone, run `nixfmt` on
  edited files first.
- The flake ignores untracked files: `git add` a new file before checking,
  or it does not exist for the check.
- A green check proves nothing until it can fail: break it once (canary)
  before citing it. An empty list, `hasInfix ""` or a lazy `runCommand`
  stub that never forces its `throw` passes everything.
- README is checked by `readme-consistency`: a new check needs its Quality
  Gates row, a new `.nix` directly under `modules/`, `home/`, `checks/` or
  `hosts/alex-mbp/` its Structure entry, and no hard counts anywhere.
- Codex hooks are guarded by `checks/codex-config.nix`.
- Manual probes, outside the flake: `checks/*-probe.sh`, `*-fuzz.sh`,
  `*-bench.sh`. Probes that `git init` must run outside the sandbox.
- `secrets.nix` and `backups/` are git-crypt: in a clone or worktree without
  the key, `secrets.nix` fails `format-check` and the eval.

## Apply
- `sudo darwin-rebuild switch --flake .#alex-mbp` is run by the user
  (password). Switch from `master` after the merge: switching from an older
  branch silently reverts the PRs merged since. To see what a switch would
  change: `darwin-rebuild build --flake .#alex-mbp` then
  `nix store diff-closures /run/current-system ./result`.
- Removing a Brewfile entry UNINSTALLS it (`--zap`), App Store apps included.
- A failing cask stops activation before home-manager runs: a cask with a
  dead URL gets `brew pin --cask <name>` and a comment in `modules/brew.nix`;
  `brew unpin --cask <name>` and drop the comment once fixed upstream. Never
  remove the entry.
- `mas list` empty makes `brew bundle` reinstall every App Store app: check
  Spotlight on `/System/Volumes/Data`, not `/`.
- Mondays 14:00, launchd runs `nix flake update` in this checkout and leaves
  an uncommitted `flake.lock`: the next switch applies it. Ship it through
  its own PR, or `git restore flake.lock`.
- A green rebuild can be inert: re-read the live file it was meant to change.

## Edit
- Agent config is generated: edit `home/claude-code/*.nix` and `home/codex/`,
  never the files under `~/.claude` or `~/.codex`, which activation rewrites.
  The live `settings.json` is a merge; the keys nix forces are listed in
  `home/claude-code/activation.nix`.
- The global instruction text shared by both agents lives in
  `home/claude-code/agent-instructions.nix`; per-agent deltas are spliced in.
- Indented strings `''…''` lose their minimal common indent: one shifted
  line rewrites every line of that string, build green. Before accepting a
  reformat, compare the evaluated attributes, not the source.
- `~/.codex/config.toml` is merged, never generated: it holds the hook trust
  table. New Codex hooks go at the END of an event's list (trust is by
  position); trusting them after a rebuild is manual (README).
- home-manager activation is one `set -eu` shell: a bare `exit` kills every
  later step. Do not wrap in `( … ) || true` (errexit goes inert inside);
  capture the rc (`set +e` … `rc=$?` … `set -e`) as `activation.nix` does.
- `writeShellApplication` runs ShellCheck at build. `GROUPS` is a bash
  special variable (assignment silently ignored); `printf | grep -q` under
  `pipefail` can return 141 (SIGPIPE) once the output outgrows the pipe.
- Security hooks fail closed on their own watchdog, but a hook the host
  kills fails open: keep the registered timeout above the watchdog.
  Workflow hooks fail open. Text matching of a command line is a safety
  net, never a barrier.
- `master` is protected by a GitHub ruleset: change it through a PR only.

## Docs
- nix-darwin / home-manager options: `nix-options show <opt>` or
  `nix-options search <regex>` (pinned by `flake.lock`; `darwin-option` is
  broken with flakes).
- Library APIs: `libdocs`, else the vendor's docs. Never from memory.
