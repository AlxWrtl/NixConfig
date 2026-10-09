# Vendored: Flightdeck

- Upstream: https://github.com/scasella/claude-flightdeck
- Version: 0.3.2 (`.claude-plugin/plugin.json`), tag `v0.3.2` = commit `b8d6d26`
  (`b8d6d26cb639d688c91636fd84302eae6947d0ba`, read from the tarball with
  `git get-tar-commit-id`)
- Source: tag tarball (codeload.github.com/scasella/claude-flightdeck/tar.gz/refs/tags/v0.3.2),
  fetched 2026-10-09; the whole kept tree is identical to the tag (`diff -r` empty)
- Licence: MIT, Stephen Casella 2026 (`LICENSE`)

## What is kept

Byte-identical to upstream, no local edit: `.claude-plugin/plugin.json`,
`hooks/{core.ts,register.tsx,rail.tsx,elapsed.tsx,hooks.json}`,
`types/index.d.ts`, `tests/flightdeck.test.ts`, `tsconfig.json`, `LICENSE`,
`README.md`, `CHANGELOG.md`.

Left out: `docs/media/` (images), `.gitignore`, `.claude-plugin/marketplace.json`
(the mod loads through `CLAUDE_CODE_PLUGIN_DIRS`, not a marketplace),
`CONTRIBUTING.md`, `SECURITY.md`.

Local configuration lives outside this folder, under
`pluginConfigs.flightdeck.options` in `home/claude-code/settings.nix`:
`openOnStart = false`, so the pane opens only on `/flightdeck`, and
`statusLine = false`, so flightdeck does not draw a second status line under
the prompt next to the `status-bar` mod's.

## Audit (2026-10-09, v0.3.2)

- None of the M5 forbidden nouns of `checks/claude-mods.nix` (sound, host
  process, network, file system, dynamic import, notification popup), and no `eval`, in
  `hooks/`, `types/`, `tests/`; M5 re-scans every file at each check.
- Imports: `claude-code` and relative modules only; zero dependencies.
- `deny` appears only as permission-verdict data (the GATE tally, reading
  `verdict.decision === 'deny'`, `ran.deny`); no hooks file returns a
  refusal. `checks/claude-mods.nix` exempts the `deny` noun for this mod only;
  M5b strips the two tally spellings of `hooks/core.ts` and fails on any
  other `deny:` / `decision:` / `permissionDecision` / `{ deny }`.
- M5c pins the audited code: the sha256 of every file under `hooks/`,
  `types/`, `.claude-plugin/` is recorded in `fdPins`; any change is red.

## Update procedure

1. Download `refs/tags/v<version>` (codeload.github.com/scasella/claude-flightdeck/tar.gz/refs/tags/v<version>)
   into an empty scratch folder; record its commit (`git get-tar-commit-id`);
   read `CHANGELOG.md`.
2. Re-run the audit greps above on `hooks/ types/ tests/` (nouns listed in
   the `forbidden` list and the `refusalPatterns` of `checks/claude-mods.nix`).
3. Copy the kept files over this folder, unchanged; bump the version and
   commit here.
4. `diff -r` against the scratch copy (excluding the left-out files) must be empty.
5. Only after re-auditing, refresh the sha256 table `fdPins` in
   `checks/claude-mods.nix` (`shasum -a 256` of each file under `hooks/`,
   `types/`, `.claude-plugin/`), and its tag/commit comment; if a tally
   spelling moved, update `fdDataSpellings` there.
6. `claude plugin validate --strict home/claude-code/mods/flightdeck`,
   `claude plugin test home/claude-code/mods/flightdeck`, then `nix flake check`.
7. If `plugin.json` `userConfig` renamed `openOnStart` or `statusLine`,
   update `settings.nix`.
