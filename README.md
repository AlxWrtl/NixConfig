# Nix-Darwin Configuration

> Declarative macOS system configuration using Nix flakes

[![Nix](https://img.shields.io/badge/Nix-flakes-blue)]() [![macOS](https://img.shields.io/badge/macOS-aarch64--darwin-lightgrey)]()

Single host: `alex-mbp` (aarch64-darwin). Everything below is declared in this
repo — system settings, CLI tools, GUI apps, fonts, shell, editor, and the
Claude Code setup.

## Clean Install

```bash
# 1. Prerequisites (git + clone access)
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh
gh auth login                    # authenticate with GitHub

# 2. Clone and run bootstrap (handles everything else)
git clone https://github.com/AlxWrtl/NixConfig.git ~/.config/nix-darwin
cd ~/.config/nix-darwin
./bootstrap.sh
```

`bootstrap.sh` runs twelve checkpointed steps and skips whatever is already
done, so it is safe to re-run after an interruption. Once a run completes,
later runs skip the app configs restore unless you pass `./bootstrap.sh --restore`:

| # | Step | Notes |
|---|------|-------|
| 1 | Xcode Command Line Tools | |
| 2 | Nix package manager | Determinate Systems installer |
| 3 | Homebrew | |
| 4 | 1Password | pauses — you retrieve SSH keys + git-crypt key from the vault |
| 5 | SSH key permissions | `chmod 700 ~/.ssh`, `600` on the private key |
| 6 | GitHub CLI authentication | `gh auth login` |
| 7 | Decrypt secrets | `git-crypt unlock` |
| 8 | App Store login | pauses — sign in for `masApps` |
| 9 | `darwin-rebuild switch` | the actual build |
| 10 | Switch git remote to SSH | |
| 11 | VS Code extensions | `vscode-install-extensions` |
| 12 | Restore app configs | Plex, Logitech, Raycast, Ice, Finder sidebar, Wi-Fi/BT |

Steps 4 and 8 block on a manual action; the rest are unattended. App logins
(Discord, Figma, Teams, …) stay manual — see the checklist below.

<details>
<summary>Manual step-by-step (if you prefer)</summary>

```bash
# 1. Xcode Command Line Tools
xcode-select --install

# 2. Install Homebrew + GitHub CLI
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh
gh auth login

# 3. Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh

# 4. Clone
git clone https://github.com/AlxWrtl/NixConfig.git ~/.config/nix-darwin
cd ~/.config/nix-darwin

# 5. Install 1Password and retrieve keys
brew install --cask 1password
# Open 1Password → login → save SSH keys to ~/.ssh/ and git-crypt key to ~/git-crypt-key

# 6. Decrypt secrets
nix-shell -p git-crypt --run "git-crypt unlock ~/git-crypt-key"
rm ~/git-crypt-key

# 7. Login to App Store (for masApps)

# 8. Build & apply
sudo darwin-rebuild switch --flake .#alex-mbp

# 9. Post-install
git remote set-url origin git@github.com:AlxWrtl/NixConfig.git
~/.local/bin/vscode-install-extensions
```
</details>

## Structure

```
flake.nix                        # inputs, checks, darwinConfigurations, devShell
├── hosts/alex-mbp/              # Host identity
│   ├── default.nix
│   └── configuration.nix
├── modules/                     # System modules
│   ├── system.nix               # Nix settings, env, firewall, shell
│   ├── packages.nix             # CLI tools + shell aliases
│   ├── services.nix             # launchd agents & daemons
│   ├── ui.nix                   # Fonts, Dock, Finder, macOS defaults, wallpaper
│   └── brew.nix                 # taps, brews, casks, masApps
├── home/                        # User config (home-manager)
│   ├── default.nix              # User packages & imports
│   ├── git.nix                  # Git + SSH signing
│   ├── ssh.nix                  # SSH hosts
│   ├── zsh.nix                  # Shell (zsh + fzf + zoxide + autosuggest + highlighting)
│   ├── starship.nix             # Prompt
│   ├── direnv.nix               # Directory environments
│   ├── ghostty.nix              # Terminal (Catppuccin, quick terminal)
│   ├── vscode.nix               # VS Code settings, keybindings, extensions
│   ├── claude-code.nix          # Claude Code entrypoint — imports claude-code/
│   ├── claude-code/             # settings, hooks, agents, skills, commands, rules…
│   │                            #   incl. skills-manifest.nix (Claude skills)
│   │                            #   and mods/ (task-board, apex-band, status-bar) via mods.nix
│   ├── codex.nix                # Codex CLI entrypoint — imports codex/
│   └── codex/                   # hooks.json generator, activation, hook & merge scripts
├── checks/                      # Flake checks (see Quality Gates)
│   ├── agent-instructions.nix
│   ├── apex-consistency.nix
│   ├── apex-plan-provenance.nix
│   ├── apex-tier.nix
│   ├── audit-apex-needles.py    # Advisory, not a flake check — needle shapes
│   ├── claude-config.nix
│   ├── claude-mods.nix
│   ├── codex-config.nix
│   ├── hook-wiring.nix
│   ├── js-lint.nix
│   ├── readme-consistency.nix
│   └── trello-cli.nix
├── backups/                     # 🔒 Encrypted app config exports (backup-apps.sh)
├── wallpapers/                  # Desktop wallpaper
├── secrets.nix                  # 🔒 Encrypted (git-crypt) — emails, IPs, usernames
├── bootstrap.sh                 # Fresh-machine install
├── backup-apps.sh               # Export app configs into backups/
└── .gitattributes               # git-crypt filter rules
```

`flake.nix` inputs: `nixpkgs` (unstable), `nix-darwin`, `home-manager` (master),
and `determinate` for the Nix daemon.

## Secrets

Sensitive values live in `secrets.nix`, encrypted by
[git-crypt](https://github.com/AGWA/git-crypt). The `backups/` tree is
encrypted by the same filter — app exports contain Wi-Fi networks and
the Bluetooth device list.

- **Locally**: readable, transparent workflow
- **On GitHub**: encrypted binary
- **Key backup**: 1Password → "git-crypt nix-darwin key"

```bash
git-crypt status                 # Check encryption status
git-crypt lock                   # Re-encrypt (rarely needed)
git-crypt unlock <key-file>      # Decrypt after clone
```

Filter rules live in `.gitattributes`:

```
secrets.nix  filter=git-crypt diff=git-crypt
backups/**   filter=git-crypt diff=git-crypt
```

## Commands

```bash
rebuild                          # alias: sudo darwin-rebuild switch --flake .#alex-mbp
nix flake check                  # Run all quality gates (see below)
nix flake update                 # Update inputs
nix develop                      # Dev shell: vulnix, nix-tree, nixfmt, nil
darwin-rebuild rollback          # Rollback to previous generation
darwin-rebuild switch --flake .#alex-mbp --show-trace -v  # Debug
```

## Option Docs

`nix-options` (`home/claude-code/scripts/nix-options.sh`, packaged by `home/claude-code/nix-options.nix`) evaluates the options of the flake.lock-pinned nix-darwin, home-manager and determinate modules. "Declared in" maps to GitHub at the lock rev. Inside the Claude sandbox it falls back to a read-only store. Override with `NIX_OPTIONS_FLAKE`, `--flake` or `--host`.

```bash
nix-options show system.defaults.dock.autohide
nix-options show programs.git.settings
nix-options search dock
nix-options --json show system.defaults.dock.autohide
```

## Quality Gates

`nix flake check` runs every check below. They are the reason a broken module,
a drifted Claude Code config or a stale README fails before it reaches the
system.

| Check | What it enforces |
|-------|------------------|
| `format-check` | `nixfmt --check` over every tracked `*.nix` (find walk, no per-directory list) |
| `system-config` | The whole `alex-mbp` darwin configuration actually builds |
| `agent-instructions` | The shared instruction trunk actually reaches both rendered outputs: every shared section body present in `CLAUDE.md` and `AGENTS.md`, each heading exactly once, headings equal the declared trunk-plus-delta list in order, no mechanism Codex lacks named to Codex or smuggled through the trunk, the nix Docs Gate divergence pinned as Codex-inline only, each output under 100 lines, `Project Map` gone from both |
| `apex-consistency` | The APEX skill keeps its critical clauses, flag casing, subagent isolation, and step-file references |
| `apex-plan-provenance` | Every premise in an APEX plan carries `[M]` or `[I]` as its first token: the clause still stands in step-02-plan, and the line detector is run against two inline fixtures — one correctly tagged, one identical but for a stripped tag — so a detector that stopped detecting fails instead of passing. Presence is not truth: it proves the tag is THERE, never that it is earned; falsifying a tag is the examine reviewer's job and the Fable premises pass |
| `apex-tier` | The built `apex-tier` classifier against throwaway git repos: a `matcher` added under `hooks.Notification` is direct, an entry added inside a `deny = [ ... ]` list is high, a `permissionDecision` branch in `hooks/x.js` is high, a 40-line README change is standard, a new `.env.example` is high. Canary M1 (the permission regex replaced by one that never matches) must turn the deny-list case away from high, proving that assertion rests on the permission class |
| `claude-config` | Claude Code invariants: JSON parses, sandbox denies `~/.ssh` and secrets, agents declare a model, haiku only on read-only agents, rules declare paths |
| `claude-mods` | Claude Code mods (`home/claude-code/mods.nix`), offline structure only: `names` equal the folders under `home/claude-code/mods/` both ways, each `plugin.json` parses and names its folder, each `hooks.json` names one existing module, no `.js` there, no sound / host process / network / file write / dynamic import / toast in any source and no `deny` in a hooks module, settings `env.CLAUDE_CODE_PLUGIN_DIRS` equal to the `~/.claude/mods/<name>` folders, activation copying them with the DRY_RUN skip and the engine's types excluded. Canaries: the scan must flag `$.audio.speak`, the filter a `.js` name, the comparison an extra name. `claude plugin validate --strict` and `claude plugin test` on each mod folder are the code gate and run in the session (`claude` is not in the build sandbox) |
| `codex-config` | Codex hook invariants: every `command` in the generated `hooks.json` names a script the module installs, both scripts pass `node --check`, hook order and matcher, registered timeouts above each script's own watchdog |
| `hook-wiring` | Claude Code hook wiring, from the evaluated module rather than from text: every hook file `home/claude-code.nix` installs is named by a `command` in `home/claude-code/settings.nix` and every such command names a file that exists, both senses reported apart; `additionalContext` emitted only inside `hookSpecificOutput`, the one shape the reference documents; the `hookEventName` a hook writes equal to the event registering it. Each direction is guarded by a corpus-non-empty assertion first, because an extractor that stops matching would otherwise be green forever. The branch guards are also RUN against fixture repos, each under the timeout its registration gives the host: `protect-main.js` and `block-main-bash.js` must deny on malformed input and on a missing or hung git and stay silent off a protected branch, `format-typescript.js` must hand a `$(…)` file path to prettier unexpanded and must not call `prettier --write` when `--find-config-path` finds no prettier config, `research-model.js` must deny an Explore or codebase-navigator spawn whose model is not `haiku` (absent included) and stay silent on haiku, on other agent types and on malformed input. Canary mutants, which must turn their case red by a missed deny or a PWNED file and not by a crash, cover these branches only: malformed JSON, a missing git and the time budget in `protect-main.js`; malformed JSON, a broken git in the cwd or in a `cd` target, and the linear executor scan on a newline flood in `block-main-bash.js`; each of the two argv calls and the prettier-config gate in `format-typescript.js`; the absent-model branch and the agent-type set in `research-model.js`. The other cases are graded without a mutant |
| `js-lint` | ESLint (`pkgs.eslint`, eslint:recommended rebuilt from `builtinRules`, node globals) over every tracked `.js`: the Claude hooks in `home/claude-code/hooks/` and the Codex scripts; asserts the file count and that a canary with an unused variable turns it red |
| `readme-consistency` | This file against the repo: the APEX flag table vs the skill, `/apex` examples typing only live flags, every `.nix` in `modules/` `home/` `checks/` `hosts/` present in the Structure tree, every check listed above, no dangling path, no alias documented that no attrset declares, no hard count |
| `trello-cli` | The `trello` wrapper (`home/claude-code/trello.nix`). Text: `skillTrello` and `cmdCard` call only bare `trello …`, with no curl, no command substitution, no `AUTH=` and no secret `cat`; both keep the Tech & Pit test-write rule, the skill its contract/scope/handoffs sections, `/card` its stop/no-write branches and its comment-before-move order. Settings: `Bash(trello *)` allowed, no `Bash(curl *)`, trello absent from `excludedCommands`, `allowRead` keeps both secret files, `autoMode.environment` has `$defaults` first plus the Trello line. Runtime: the built wrapper runs against a stub curl in 17 cases — key and token never in argv, URL or output (inherited `SHELLOPTS=xtrace` and secret-echoing success bodies included), the OAuth header arrives on stdin, ids validated before any call, secrets with embedded whitespace rejected, 401 and network errors exit 1. Canaries C1 (secret moved into the URL), C2 (id validation disabled) and C3 (`set +o xtrace` dropped) must each be killed by their target case |

Run them before every commit that touches `.nix` files — `format-check` in
particular fails on formatting alone.

`readme-consistency` compares this document against live sources rather than
against a copy of its own expectations: a check holding its own copy of the
truth rots at the same rate as the thing it checks. It deliberately does not
require the modules inside `home/claude-code/` to be listed individually —
that directory is documented as one unit.

## Maintenance / Cleanup

Reclaim disk space by garbage-collecting old generations and deduplicating the
Nix store, then prune Homebrew caches.

```bash
sudo nix-collect-garbage -d      # Delete all old generations (system + user)
nix-store --optimise             # Hard-link identical files in the store
brew autoremove                  # Remove unused brew dependencies
brew cleanup -s --prune=all      # Purge all download caches and old versions
```

> **Note:** if `sudo nix-collect-garbage -d` warns `$HOME is not owned by you`
> and falls back to root's profile (leaving user generations behind), run the
> user sweep without sudo as well: `nix-collect-garbage -d`.

## What's Managed

Each row points at the module that owns it — that file is the authoritative
list, deliberately not duplicated here.

| Layer | Tool | Contents |
|-------|------|----------|
| CLI tools | Nix (`modules/packages.nix`) | eza, bat, fd, ripgrep, fzf, atuin, zoxide, btop, jq/yq, git-crypt, gh, nodejs, pnpm, bun, python3, uv, ruff, sqlite, postgresql, redis, nixd/nil/nixfmt … |
| GUI apps | Homebrew casks (`modules/brew.nix`) | 1Password, Arc, Ghostty, VS Code, Zed, Docker, Raycast, Obsidian, Figma, Jellyfin, Tailscale … apps without an auto-updater are marked `greedy` |
| Formulae & taps | Homebrew (`modules/brew.nix`) | cloudflared, ffmpeg, displayplacer, mas, postgresql@16, trash, `rtk-ai/tap/rtk` |
| App Store | mas (`modules/brew.nix`) | DaisyDisk, Trello, iWork (Keynote/Numbers/Pages), Microsoft Office, Affinity Photo & Publisher |
| Fonts | Nix (`modules/ui.nix`) | Nerd Fonts (JetBrains Mono, Meslo LG, Hack, Fira Code, Sauce Code Pro), Cascadia Code, Inconsolata, Noto (+ CJK, emoji) |
| macOS defaults | Nix (`modules/ui.nix`) | Dock, Finder, trackpad, clock, screensaver, Window Manager, wallpaper |
| Services | Nix (`modules/services.nix`) | weekly flake update, throttled brew update, power tuning (`pmset`), network/TCP tuning |
| System | Nix (`modules/system.nix`) | Nix daemon settings, binary caches, env vars, application firewall |
| Terminal | home-manager (`home/ghostty.nix`) | Catppuccin Macchiato, quick terminal, keybindings |
| Editor | home-manager (`home/vscode.nix`) | Settings, keybindings, extension list |
| Shell | home-manager (`home/zsh.nix`) | zsh + fzf + zoxide + autosuggestions + syntax highlighting + aliases |
| Git | home-manager (`home/git.nix`) | SSH signing, rebase-on-pull, fsck |
| SSH | home-manager (`home/ssh.nix`) | Host configs (Tailscale) |
| Claude Code | home-manager (`home/claude-code/`) | settings, hooks, agents, skills, commands, rules, mods, shell aliases |
| Codex CLI | home-manager (`home/codex/`) | `hooks.json` + hook scripts (store symlinks), `config.toml` merge, hook-trust verification |
| Secrets | git-crypt (`secrets.nix`, `backups/`) | Git email, SSH hosts, app config exports |

**Claude Code mods.** `home/claude-code/mods.nix` lists the mods under
`home/claude-code/mods/` (TypeScript plugins of function hooks, no
dependency, no sound). Activation copies them into `~/.claude/mods` as real
writable files — that folder is nix-owned, a hand-placed mod there is deleted
on the next rebuild — and `env.CLAUDE_CODE_PLUGIN_DIRS` loads them.
`task-board`: `/task-board` opens a "Tâches" pane listing background shells
and subagents with their duration and state (en cours / fini / échoué); a
subagent's still running shells turn échoué when it is killed, fails, or
leaves the agent list (a teammate's: only when it leaves the list), since
their notification would never reach the main loop; a shell also closes on its
subagent's own notification row and on a TaskStop.
`apex-band`: a band above the prompt shows the live APEX run of the working
directory (title, mode, current step, branch, baseline) and nothing
otherwise.
`status-bar`: replaces the command status line. Drawn on the hint line under
the prompt, it shows the model, folder, git branch, the last response's tokens
in/out, the context bar with its percentage, and the 5h and 7d quota bars with
their percentage and reset countdown: one row when it fits the width, else
two, with the engine's own hint line still beneath. Read-only: the branch is
read from `.git/HEAD`, no process is spawned. Run yourself after a rebuild, in
a new session: `/task-board`, a background `sleep 5` going from en cours to
fini, a failing background command shown échoué, the band present during an
APEX run and absent elsewhere, the status bar under the prompt on one row and
on two in a narrow window.

## Codex Hooks — Trusting Them After a Rebuild

Codex records hook trust **per hook and by position**, inside
`~/.codex/config.toml`, as a `[hooks.state."<file>:<event>:<group>:<hook>"]`
table carrying a hash of the hook's content. A hook it has not been told to
trust is **skipped in silence** — no error, no log, no protection, while the
configuration still looks correct. That is why `~/.codex/config.toml` is
merged in place and never regenerated, and why `home/codex/hooks.nix` requires
new hooks to be appended only at the END of an event's list.

Nothing outside Codex can grant that trust, and no Codex command reports it
(`codex doctor` has no hook check). So the sequence after any change to the
hooks is manual, and short:

1. `sudo darwin-rebuild switch --flake .#alex-mbp` — activation merges
   `config.toml`, links `hooks.json`, then runs `codex-verify-hook-trust`.
2. The verifier warns on **both** hooks. That is expected on a first rebuild
   and after any hook edit; a silent pass there would mean the check failed to
   notice, not that you are protected.
3. Open Codex, run `/hooks`, review each hook and trust it.
4. Record the reviewed baseline by hand: `codex-verify-hook-trust -a`. It
   writes the hash under `~/.local/state/`, outside the agent's writable set,
   so nothing running inside a session can forge its own clean bill of health.
   Activation never passes `-a`: the review it records is a human act.

After that, rebuilds are silent until the hooks' content changes — then the
warning returns and step 3 has to happen again.

The verifier never claims a hook IS trusted at runtime; it can only report
that one is un-approved or stale. Its silence is not proof of protection.

## Post Clean Install Checklist

- [ ] SSH keys restored (`~/.ssh/id_ed25519*`)
- [ ] VS Code extensions installed (`~/.local/bin/vscode-install-extensions`)
- [ ] Default browser set (Arc)
- [ ] 1Password logged in + browser extension
- [ ] iCloud signed in (Desktop & Documents sync)
- [ ] Arc signed in (sync spaces)
- [ ] App logins: Discord, WhatsApp, Spark, Teams, Figma
- [ ] Raycast settings imported (if backed up)
- [ ] `nix flake check` green

## APEX

APEX is the implementation workflow for Claude Code, declared in
`home/claude-code/skills.nix` and guarded by `checks/apex-consistency.nix`.
Every task that **modifies files** goes through it; a pure question does not.

Each phase runs as a fresh subagent and returns only a bounded summary, so the
coordinator never accumulates raw context. Phase summaries are persisted to
`.claude/output/apex/{task-id}/`.

### Mode Gate

The gate picks the depth, never whether to run. Each mode carries a default
flag set, applied to every flag you did not type. The tier (Direct, Standard,
High-stakes) is decided on the diff, not on the brief: `apex-tier`
(`home/claude-code/apex-tier.nix`) reads its size, its paths and the
indentation ancestry of each changed line.

| Mode | Default flags | Notes |
|------|---------------|-------|
| Direct | `-pr` | ≤ 4 files, ≤ 30 changed lines, no sensitive surface |
| Diagnosis | `-x -pr -o -n` | bug/crash — reproduce first, debugger agent implements, ships as a PR |
| Standard | `-t -pr -o -n` | full orchestration |
| High-stakes | `-t -x -pr -o -n -e` | irreversible / security / architecture / prod — one examine reviewer, then Codex `-e` as read-only detector whose findings are triaged by evidence; Fable only as fallback when no usable external verdict (BLOCKED or `-E`), or under `-p` |
| Pure research | none | analyze only, no branch |

### Flags

Lowercase forces ON, **uppercase forces OFF** (`-PR` cancels an automatic
`-pr`). Typed flags beat mode defaults.

| Enable | Disable | Description |
|--------|---------|-------------|
| `-q` | `-Q` | Clarify — ambiguities become up to 3 targeted questions before planning |
| `-x` | `-X` | Examine — adversarial, checklist-driven review |
| `-t` | `-T` | Test — create and run tests |
| `-f` | `-F` | Test-first — a separate agent writes failing tests from the ACs; read-only for the implementer |
| `-2` | | Divergence — second independent implementation of the core logic, behavioural diff |
| `-p` | `-P` | Premises — force/forbid the independent premises pass |
| `-e` | `-E` | External verify — one cross-vendor read-only pass (Codex/GPT) over the same diff; default in high-stakes |
| `-pr` | `-PR` | Pull request — commit + PR |
| `-k` | `-K` | Tasks — dependency breakdown into parallel waves |
| `-v` | `-V` | Verify — research the plan online; must trace a query or say why none |
| `-o` | `-O` | Obsidian — load vault context before planning |
| `-n` | `-N` | Note — session note at the end, then reindex the knowledge graph |

`-q`, `-f`, `-2`, `-p`, `-k` and `-v` are never auto-enabled — each is
expensive, and none belongs on a typo fix. `-e` is auto-enabled only in
High-stakes (`-E` cancels it); elsewhere it must be typed.

### Invariants

Not flags, nothing to disable:

- **Branch first** — on `main`/`master`, a branch is cut before the first edit.
- **Save** — every phase summary is written to disk, which is what lets a run
  survive compaction and be resumed.

### Pipeline

`init → analyze → plan → execute → validate` (+ optional: tests, examine,
resolve, finish, note). Validate runs the machine gate first — parse, lint,
typecheck, tests — because a compiler finds compiler bugs for free.

### How it actually runs

The skill is only one third of the system. It describes what should happen;
on its own it is prose the model may or may not follow. Two other layers
declared in this repo decide what actually happens.

| Layer | Where | Can it be ignored? |
|-------|-------|--------------------|
| Skill | `home/claude-code/skills.nix` | Yes — it is context the model reads |
| Hooks | bodies in `home/claude-code/hooks/`, wired by `home/claude-code/hooks.nix` into `home/claude-code/settings.nix` | No — the harness executes them |
| Checks | `checks/` via `nix flake check` | No — they block the merge |
| Server ruleset | GitHub `protect-master` on this repo's default branch | No — GitHub refuses the push |

The lifecycle of one request, in order:

1. **Session opens** — `SessionStart` prints the branch and last commit.
2. **You type** — `UserPromptSubmit` injects the routing line naming the
   modes and their default flags. This is context, not enforcement.
3. **The model tries to edit** — `PreToolUse` on `Edit|Write` and `Bash`
   refuses until the APEX skill has been invoked for that request, and
   re-arms on your next message. This is enforcement.
4. **The model tries to commit** — the same event refuses the git verbs that
   put code on `main`/`master`: the ones that author a commit, and the ones
   that move the branch ref onto an arbitrary object; a push whose
   destination names `main`/`master` is refused from any branch. It is a
   list, not a seal — `pull`, `worktree add` and a refspec written straight
   onto the local branch are outside it. Master moves through pull requests
   only.
   GitHub enforces it: the `protect-master` ruleset (no bypass actors)
   requires a pull request and refuses force-push and deletion on this repo's
   default branch. It requires a pull request, not a review: zero approvals
   and no required checks, so an agent holding `gh` could open and merge one,
   and the admin token can edit the ruleset itself — which is why
   `gh pr merge` and mutating `gh api` calls sit behind `ask`. The hook and
   the `deny`/`ask` rules in `home/claude-code/settings.nix` are textual
   guardrails in front of it, not the barrier.
5. **APEX runs** its chain, each phase in a subagent with a fresh context,
   phase summaries persisted under `.claude/output/apex/`.
6. **`-o` reads the vault** before planning, through one of two MCP servers,
   never both on the same question: `enquire` for what the vault *wrote*
   (notes, wikilinks, backlinks, semantic search), `graphify` for what it
   *implies* (entities and relations extracted across note contents, links no
   wikilink materialises).
7. **`-n` writes** the session note into the vault.
8. **Session ends** — `SessionEnd` fires
   `home/claude-code/scripts/graphify-reindex.sh`, which extracts the new
   notes into the knowledge graph that feeds the *next* session's `-o`.

Step 8 is the design lesson worth keeping. The reindex used to be a sentence
inside the skill, so it only ran when the model remembered; notes were
written and never indexed. Moving it to a hook made it unconditional. **A
rule that must be impossible to violate belongs in a hook, not in prose** —
instruction files are context, hooks are execution.

The third layer closes the loop on the first two: `checks/apex-consistency.nix`
asserts that the skill still refers only to parts of itself that exist, that
it has not lost the clauses it must never lose, and that the mode table and
the injected routing line still agree. Both had drifted silently before it
existed — exactly as this README did.

### Rules are measured, not argued

A clause in the skill is prose the model reads. `apex-consistency` asserts it
is still present. Neither shows it changes behaviour — a rule can read well,
pass review, and do nothing.

So a rule that governs every future run earns its place by flipping a
mechanical predicate in a paired probe: K distinct tasks, each played in two
arms, identical but for the rule. The predicate is declared before any run,
in a rubric that also lists what may not be written afterwards.

| Rule | Control | Treatment | Verdict |
|------|---------|-----------|---------|
| `Files:` is a boundary | 3/6 edited outside the list | 0/6 | kept |
| Baseline read before the first edit | 0/2 ran the gate | 2/2 | kept |
| Scope ladder | 8/8 already correct | 8/8 | **removed** |

The ladder was five rungs interrogating anything a plan proposed to build. It
read well and survived review. Across three benches and 40 paired runs it
never changed an outcome once, and it was removed rather than kept on the
argument that it surely helps somewhere.

Two of those three benches were thrown away as invalid: one leaked the answer
through the working directory, the other measured a failure mode the models do
not have — the control arm found every existing helper without being told to.
A fourth, aimed at fresh-context isolation, failed its own pre-declared gate
before a single arm ran: zero defects in eight implementations, so there was
nothing for either arm to find. Budget for the probe being wrong before the
rule is.

Fresh context per phase therefore stands as **unmeasured, not validated** —
kept because context hygiene is arithmetic rather than a claim, and because
independent review has repeatedly caught in this repo what self-review missed.

The same discipline was then turned on `apex-consistency` itself, and it did
not survive either. A mutation harness was built to answer "does each invariant
go red when what it guards disappears?" — and the check is a substring test,
so deleting a needle turns it red *always* (33/33, a tautology) while keeping
the needle means the invariant can never fire at all (0/33, every red traced to
a neighbour). **A substring test cannot verify that a rule survived, only that
its own needle did.** The harness was deleted rather than shipped looking
useful; `nix flake check` already turns red on a vanished needle unaided.

What is decidable without building anything is the SHAPE of the needle:

```
"Max 3 correction rounds"   deleting the rule deletes the needle  -> red
"Scope ladder"              deleting the rungs leaves the heading -> green
```

The second is the September failure verbatim — the ladder invariant stayed
green after all five rungs were deleted, and had looked healthy for weeks.
`checks/audit-apex-needles.py` sorts every needle into SENTENCE / SHORT /
HEADING so the question takes one command. It is advisory, needs a reader, and
is deliberately not wired into `nix flake check`: a heuristic that blocks a
merge only teaches people to route around it.

`checks/scrapling-shim-fuzz.sh` is where the `--ai-targeted` guarantee is
actually tested, and it exists because enumeration failed. The flag was first
enforced by a PreToolUse hook that read the raw command line as text and had to
predict what the shell would do with quotes, `$(...)`, `eval` and variable
indirection. It passed 26 hand-written cases, then 30, then 44, and still had
seven real defects — twice, a round of fixes reopened something the previous
round had closed. The mind that writes a matcher enumerates the shapes it
already handles.

A shim on PATH replaced it: it is executed by the shell, so it receives the
parsed argument vector and predicts nothing. That closes the shell-composition
class entirely — but not argv itself. Review then found three more, all in the
shim's own argument handling: `extract -- get` hid the subcommand behind the
end-of-options marker, and scanning the whole argv for `--help` or an existing
flag meant a token Click consumes as an option VALUE (`-s --help`,
`-s --ai-targeted`) suppressed injection. The fix is positional: look only at
the slot after the subcommand, and inject unconditionally, since the flag is
idempotent.

The harness generates shell compositions around a real call, swaps the binary
for a recorder, and asserts the flag arrived **immediately after the subcommand
token** — presence alone scored `-s --ai-targeted` as a pass, and an assertion
indexed by number would later have failed a *correct* shim once `--` could
precede `extract` too. It refuses to run unless it can install the shim under
test and a tripwire proves it can still detect a missing flag: the first
version reported 48 passed and exit 0 for `/nonexistent/path/scrapling`,
because `cp` failed unchecked and PATH fell through to the live system. It was
grading the machine while claiming to grade its argument. Confirm it can fail —
comment out the injection and 56 passing becomes 52 failing.

`checks/vault-autocommit-bench.sh` covers the git half of the vault snapshot:
28 cases on throwaway repos under `TMPDIR`, never the real vault, with the
auto-commit block lifted verbatim out of the script so the bench cannot drift
from it. Four of the cases are failure paths, because the block's whole job is
to never abort the backup — a guard that only works on the happy path turns
"one uncommitted note" into "no backup at all". Mutation-tested: remove the
fast-forward and 20 passing becomes 16, failing on exactly the four
assertions that depend on it.

Sections 7 and 8 cover the per-project grouping: the vault is written by
sessions on different projects, and one commit must never carry two of them.
Four mutations, each keeping the shell grammar valid so the failures mean
something: drop the project pattern and 28 passing becomes 22; take `-z` off
`ls-files` and it becomes 25, on the three accented-filename assertions alone;
restore the plain `git add -A` and the anti-mixing assertion is the one that
fires. That last mutation exists because the first three left it unfalsified —
they made the block SKIP the projects rather than merge them, so an assertion
that had never once failed was being reported as passing.

Its first run reported 12 failures that were all its own: the fixtures
inherited the real git config, which signs commits with an SSH key the sandbox
cannot read, so no fixture commit could ever succeed. Fixtures now disable
signing — and the first mutation attempt was equally useless, breaking the
block's shell syntax rather than removing one behaviour, which fails everything
and proves nothing.

There is no hook left to bench. One survived a while as a backstop for the
routes the shim cannot see, then review measured it: it caught four of eighteen
such routes, and it denied `grep "uv/tools/scrapling"` on this repository's own
source — so touching the subject blocked the edit. A guard that stops its owner
and not the thing it names is worse than none, and every attempt to sharpen it
had produced a new defect. It was deleted rather than sharpened again.

What that leaves is stated in the skill instead of implied by a mechanism: the
shim covers what runs as `scrapling` on PATH, and a full path, `uvx`,
`uv tool run`, `scrapling shell -c` or the Python API reach the tool with no
sanitizing at all. Naming the perimeter is worth more than a guard that gives
the wrong impression of one.

`checks/null-result-gate-probe.sh` grades the null-result gate on both
polarities at once — the shapes that must make it speak, and the shapes that
must leave it silent, including every input it cannot read — and its
`--mutants` mode rebuilds the hook three ways to prove the harness still goes
red on a declared set of cases rather than on everything.

`checks/require-apex-probe.sh` does the same for the require-apex gate's Bash
door, in a throwaway git repo it builds: inline `python3 -c` / `node -e` /
`ruby -e` code and interpreter heredocs that call a write API, `perl -0pi`, and
scripts outside the repo that write and name it must be denied; read-only
calls, in-repo scripts, a helper merely named `cp`, oversized or missing
scripts and a `cd` into temp must pass, and a plain `ls` must not spawn git at
all. Script paths are resolved through every `cd` before them and through the
hook's environment, `codex exec` is denied when the session cwd, its `-C` or
its `cd`s name a repo unless an unwidened `-s read-only` lets it pass (the one
exemption, a `cd` into an existing non-repo temp dir with no `-C` and no
danger flag, fails closed on anything it cannot establish), commands past the
256 K cap are denied unread, and 64 KB adversarial shapes must finish fast.
Its `--mutants` mode grades every mutant on its declared red set, and the hook
as it stood before these rules goes red on it.

### Usage

```
/apex add feature                    # Mode Gate picks the depth
/apex -q migrate the schema          # Ask before planning
/apex -t -pr add endpoint            # Tests + PR
/apex -x -v upgrade the auth flow    # Adversarial review + online verification
/apex -PR fix the typo               # Cancel the automatic PR
```

### Related commands

| Command | Description |
|---------|-------------|
| `/auto <task>` | Route to the best workflow |
| `/discuss <feature>` | Capture decisions before planning |
| `/card` | Run a Trello card through APEX, write the result back |
| `/context-prime` | Map the project: entrypoints, structure, build, tests |
| `/tdd <feature>` | TDD loop: red → green → refactor |
| `/optimize` | Profile first, then targeted performance fixes |
| `/verify-feature` | 6-layer quality verification on the current branch |

## Shell Aliases

Aliases come from four modules. System-wide ones are `environment.shellAliases`;
user ones are `programs.zsh.shellAliases`.

```bash
# modules/packages.nix
rebuild          # sudo darwin-rebuild switch --flake .#alex-mbp
serve / py       # python3 -m http.server / python3
dc / dcu / dcd   # docker-compose (+ up / down)

# modules/system.nix
vulnscan-json    # vulnix scan to /tmp/vulnix-output.json
check-perms      # inspect /nix/store permissions

# home/zsh.nix
ls la ll lla lld # eza variants
tree / treeall   # eza --tree (treeall includes dotfiles)
g gs ga gc gp    # git / status / add / commit / push
gl gd gco gb     # git pull / diff / checkout / branch
vulnscan         # vulnix --system /var/run/current-system
secrets encrypt  # sops / age
clr vim top      # clear / nvim / htop

# home/claude-code/shell.nix
cc ccl ccr       # claude / -c / --resume
cca ccw ccb      # claude --agent / --worktree / --bare
ccn ccv ccro     # cd to this repo + claude / --version / read-only plan mode
schliff          # uvx schliff (skill quality linter)
```

`bat`, `fd` and `ripgrep` are installed but **not** aliased over `cat`, `find`
or `grep` — call them by name.

## Troubleshooting

```bash
exec $SHELL                      # Reload shell
fc-cache -f -v                   # Rebuild font cache
sudo chown -R $(whoami) ~/.config/nix-darwin  # Fix permissions
darwin-rebuild switch --flake .#alex-mbp --show-trace -v  # Debug build
nix flake check --show-trace     # Find which gate is failing
```

## Credits

Built with [nix-darwin](https://github.com/LnL7/nix-darwin), [home-manager](https://github.com/nix-community/home-manager), [Nix](https://nixos.org/), [Homebrew](https://brew.sh/), [git-crypt](https://github.com/AGWA/git-crypt).

## License

MIT
