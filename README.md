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
done, so it is safe to re-run after an interruption:

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
│   └── claude-code/             # settings, hooks, agents, skills, commands, rules…
├── checks/                      # Flake checks (see Quality Gates)
│   ├── apex-consistency.nix
│   ├── claude-config.nix
│   └── readme-consistency.nix
├── backups/                     # 🔒 Encrypted app config exports (backup-apps.sh)
├── wallpapers/                  # Desktop wallpaper
├── secrets.nix                  # 🔒 Encrypted (git-crypt) — emails, IPs, usernames
├── bootstrap.sh                 # Fresh-machine install
├── backup-apps.sh               # Export app configs into backups/
├── Nix-Darwin-Doc.md            # Generated nix-darwin option reference
└── .gitattributes               # git-crypt filter rules
```

`flake.nix` inputs: `nixpkgs` (unstable), `nix-darwin`, `home-manager` (master),
and `determinate` for the Nix daemon.

## Secrets

Sensitive values live in `secrets.nix`, encrypted by
[git-crypt](https://github.com/AGWA/git-crypt). The `backups/` tree is
encrypted by the same filter — app exports contain Wi-Fi networks and
Bluetooth pairings.

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

## Quality Gates

`nix flake check` runs every check below. They are the reason a broken module,
a drifted Claude Code config or a stale README fails before it reaches the
system.

| Check | What it enforces |
|-------|------------------|
| `format-check` | `nixfmt --check` over `flake.nix`, `modules/`, `home/`, `home/claude-code/`, `hosts/`, `checks/` |
| `system-config` | The whole `alex-mbp` darwin configuration actually builds |
| `apex-consistency` | The APEX skill keeps its critical clauses, flag casing, subagent isolation, and step-file references |
| `claude-config` | Claude Code invariants: JSON parses, sandbox denies `~/.ssh` and secrets, agents declare a model, rules declare paths |
| `readme-consistency` | This file against the repo: the APEX flag table vs the skill, `/apex` examples typing only live flags, every `.nix` in `modules/` `home/` `checks/` `hosts/` present in the Structure tree, every check listed above, no dangling path, no alias documented that no attrset declares, no hard count |

Run them before every commit that touches `.nix` files — `format-check` in
particular fails on formatting alone.

`readme-consistency` compares this document against live sources rather than
against a copy of its own expectations: a check holding its own copy of the
truth rots at the same rate as the thing it checks. It deliberately does not
require the eleven modules inside `home/claude-code/` to be listed
individually — that directory is documented as one unit.

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
| Claude Code | home-manager (`home/claude-code/`) | settings, hooks, agents, skills, commands, rules, shell aliases |
| Secrets | git-crypt (`secrets.nix`, `backups/`) | Git email, SSH hosts, app config exports |

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
flag set, applied to every flag you did not type.

| Mode | Default flags | Notes |
|------|---------------|-------|
| Diagnosis | `-x -o -n` | bug/crash — reproduce first, debugger agent implements. No PR |
| Standard | `-t -pr -o -n` | full orchestration |
| High-stakes | `-t -x -pr -o -n` | irreversible / security / architecture / prod — adds the adversarial pass and an independent read-only verify on the real diff |
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
| `-pr` | `-PR` | Pull request — commit + PR |
| `-k` | `-K` | Tasks — dependency breakdown into parallel waves |
| `-v` | `-V` | Verify — research the plan online; must trace a query or say why none |
| `-o` | `-O` | Obsidian — load vault context before planning |
| `-n` | `-N` | Note — session note at the end, then reindex the knowledge graph |

`-q`, `-f`, `-2`, `-p`, `-k` and `-v` are never auto-enabled — each is
expensive, and none belongs on a typo fix.

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
| Hooks | `home/claude-code/hooks.nix`, wired in `home/claude-code/settings.nix` | No — the harness executes them |
| Checks | `checks/` via `nix flake check` | No — they block the merge |

The lifecycle of one request, in order:

1. **Session opens** — `SessionStart` prints the branch and last commit.
2. **You type** — `UserPromptSubmit` injects the routing line naming the
   modes and their default flags. This is context, not enforcement.
3. **The model tries to edit** — `PreToolUse` on `Edit|Write` and `Bash`
   refuses until the APEX skill has been invoked for that request, and
   re-arms on your next message. This is enforcement.
4. **The model tries to commit** — the same event refuses any write to
   `main`/`master`. Master moves through pull requests only.
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
| `/ralph-loop` | Start a Ralph Wiggum loop in the current session |
| `/cancel-ralph` | Cancel the active Ralph loop |

## Shell Aliases

Aliases come from four modules. System-wide ones are `environment.shellAliases`;
user ones are `programs.zsh.shellAliases`.

```bash
# modules/packages.nix
rebuild          # sudo darwin-rebuild switch --flake .#alex-mbp
serve / py / ipy # python3 -m http.server / python3 / ipython
dc / dcu / dcd   # docker-compose (+ up / down)

# modules/system.nix
vulnscan-json    # vulnix scan to /tmp/vulnix-output.json
security-logs    # tail -f /var/log/security/*.log
check-perms      # inspect /nix/store permissions
check-security   # tail the vulnix scan log

# home/zsh.nix
ls la ll lla lld # eza variants
tree / treeall   # eza --tree (treeall includes dotfiles)
g gs ga gc gp    # git / status / add / commit / push
gl gd gco gb     # git pull / diff / checkout / branch
hm hms hmb       # home-manager / switch / build
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
