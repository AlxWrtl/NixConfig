# Claude Code settings
{ homeDirectory }:
let
  # Absolute path to node — /bin/sh can't find nix-installed node in PATH
  node = "/run/current-system/sw/bin/node";

  # Obsidian vault — shared constant, reusable by other modules.
  # Real on-disk location (NOT the iCloud~md~obsidian mirror path).
  alxVaultPath = "${homeDirectory}/Vaults/AlxVault";

  # Claude Code mods: names and the absolute folders the engine loads.
  mods = import ./mods.nix;
in
{
  inherit alxVaultPath;

  settingsJson = builtins.toJSON {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    language = "french";
    # high, pas xhigh : sur Opus 5.5 les niveaux sont recalibrés (medium >= high
    # d'Opus 5). Banc du 2026-10-10, 3 PR réelles rejouées par /apex complet :
    # qualité égale sur les 3, xhigh = +25-45 % de coût sur 2 d'entre elles.
    # /effort xhigh reste dispo à la demande.
    # Force-overridden par le merge activation — la valeur live suit le nix.
    effortLevel = "high";
    showTurnDuration = true;

    env = {
      npm_config_prefer_pnpm = "true";
      npm_config_user_agent = "pnpm";
      BASH_DEFAULT_TIMEOUT_MS = "300000";
      BASH_MAX_TIMEOUT_MS = "600000";
      # Compaction vers ~400k au lieu de ~900k (opus[1m]) : chaque message relit
      # tout le contexte. Variable dédiée en tokens, prime sur /autocompact,
      # --autocompact et autoCompactWindow ; l'ancien CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
      # est un % DE cette fenêtre, retiré pour ne pas se cumuler. 2026-10-10,
      # https://code.claude.com/docs/en/model-config#set-the-auto-compact-window
      CLAUDE_CODE_AUTO_COMPACT_WINDOW = "400000";
      CLAUDE_STREAM_IDLE_TIMEOUT_MS = "600000";
      CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
      # Tab title stays the folder name (zsh.nix), not the topic of the moment.
      # Also skips the session-title request and OSC 7501 status reports.
      CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "1";
      # Garde les outils Chrome, retire la section Chrome du prompt système et
      # la skill /claude-in-chrome : Chrome sert à agir, jamais à lire. 2026-10-10,
      # https://code.claude.com/docs/en/env-vars
      CLAUDE_CODE_DISABLE_CFC_PROMPT = "1";
      # Every mod named in mods.nix, copied to ~/.claude/mods by activation.
      CLAUDE_CODE_PLUGIN_DIRS = mods.pluginDirs homeDirectory;
      # Astro telemetry writes ~/Library/Preferences/astro: 1 EPERM in 30 d,
      # telemetry only. Off rather than opening ~/Library/Preferences.
      ASTRO_TELEMETRY_DISABLED = "1";
      # /watch (claude-video): WhisperX's Hugging Face and torch-hub caches
      # live beside its venv, so one allowWrite entry (sandbox below) covers
      # them; ~/.cache/huggingface and ~/.cache/torch stay closed. env is
      # session-wide: an unsandboxed HF/torch.hub consumer Claude starts
      # (hook, MCP server, excluded command) would load from this
      # sandbox-writable dir. None exists today; one added later must not.
      HF_HOME = "${homeDirectory}/.cache/watch/huggingface";
      TORCH_HOME = "${homeDirectory}/.cache/watch/torch";
      # Node 22 fetch ignores HTTP(S)_PROXY: sandboxed it dies ENOTFOUND; with
      # this flag it goes through the sandbox proxy, 200 (probe 2026-10-22).
      # Inert outside the sandbox (no proxy var there); NO_PROXY keeps
      # localhost direct.
      NODE_USE_ENV_PROXY = "1";
    };

    # Défaut déclaratif : Opus 5.5 = workhorse full-loop. L'alias `opus` suit le
    # dernier Opus ; le suffixe `[1m]` sélectionne le contexte 1M. Valeur
    # alignée sur ce que /model écrit dans le live (alias, pas un identifiant
    # daté). Fable n'est plus coordinateur — il est spawné en vérificateur
    # read-only sur diff haut-enjeu seulement, voir apex ORCHESTRATION.md.
    # NON force-overridden dans la 2e passe jq, MAIS cette valeur re-seed le
    # live quand la clé y est absente (le CLI la retire quand /model écrit son
    # choix dans ~/.claude.json) — d'où l'obligation de la garder alignée sur
    # le défaut voulu, sinon le rebuild fait régresser le modèle.
    model = "opus[1m]";
    # Chaîne de repli si Opus 5.5 est indisponible/surchargé : essayée dans
    # l'ordre, uniquement en cas d'échec de requête. N'affecte pas le défaut.
    fallbackModel = [
      "claude-opus-5"
      "claude-opus-4-8"
      "claude-sonnet-5"
    ];
    # Dictée vocale. Remplace l'ancienne clé plate `voiceEnabled` (legacy, encore
    # lue par le binaire mais supprimée du live par la passe jq d'activation pour
    # éviter deux sources de vérité). NON force-overridden : `mode` reste un choix
    # de session modifiable par le CLI, et le deep merge `.[0] * .[1]` fait
    # remonter dans le live toute sous-clé de la base absente côté live.
    voice = {
      enabled = true;
      mode = "hold";
      autoSubmit = false; # franglais : relecture avant envoi
    };
    # Background agents/daemon off (`claude agents`, --bg, /background): a
    # daemon-hosted session loses the mic (anthropics/claude-code#86217);
    # sessions run under abduco instead (claude-dispatch). Seeded, not forced.
    disableAgentView = true;
    skipDangerousModePermissionPrompt = true;
    # Every interactive session (abduco ones included) registers its own
    # Remote Control session; `claude -p` is not covered. Seeded, not forced:
    # a /config choice survives rebuilds.
    remoteControlAtStartup = true;

    # Rings BEL instead of a desktop notification (Ghostty OSC): Ghostty shows
    # it as a 🔔 tab-title prefix + split border (bell-features, ghostty.nix),
    # so the session that finished or waits on a permission is visible. The
    # two flags below turn off push notifications to the user's devices
    # (waiting prompt/question, proactive agent push); the Claude app can show
    # them as macOS notifications, the suspected source of the "Claude Code —
    # <project> — Attention" popup (unconfirmed until after the switch).
    preferredNotifChannel = "terminal_bell";
    inputNeededNotifEnabled = false;
    agentPushNotifEnabled = false;

    attribution = {
      commit = "";
      pr = "";
    };

    includeCoAuthoredBy = false;

    # Thinking adaptatif actif par défaut (Opus 4.8+ : profondeur pilotée par
    # effortLevel). Force-overridden par le merge activation.
    alwaysThinkingEnabled = true;

    # Le style de sortie modifie le PROMPT SYSTÈME ; CLAUDE.md, lui, n'ajoute
    # qu'un message utilisateur après coup. C'est toute la différence : la
    # consigne « caveman full mode: terse prose, no filler » vit dans CLAUDE.md
    # et a été ignorée toute la session du 2026-09-05 — des réponses de
    # plusieurs écrans, sans que rien ne le signale.
    #
    # Concise mène par le résultat, coupe le préambule et la narration, et garde
    # court par défaut sans rien retirer au travail d'ingénierie. Il conserve
    # toujours EN ENTIER les rapports d'erreur, les avertissements de sécurité
    # et les confirmations d'action destructrice — raison de le préférer à un
    # style maison qui raccourcirait tout uniformément. Demander une explication
    # rend la réponse longue à nouveau.
    #
    # Requiert Claude Code >= 2.1.237. Ne s'applique QU'À la conversation
    # principale : un subagent tourne avec son propre prompt système.
    # Hors de la liste force-override du merge d'activation, donc un choix fait
    # en session via /config survit au rebuild — même logique que .model.
    # Prend effet au /clear ou à la session suivante, jamais immédiatement.
    outputStyle = "Concise";

    includeGitInstructions = false;

    sandbox = {
      enabled = true;
      # Commands that run OUTSIDE the sandbox, then through the normal permission
      # rules (allow / ask / auto classifier) instead of failing with
      # "operation not permitted". sudo/darwin-rebuild: `ask` still shows a box.
      # codex/gh/git push need the keychain or the ~/.ssh key the sandbox denies.
      # deny/ask below are TEXTUAL filtering (guardrail, not a barrier); the
      # server-side barrier is the GitHub ruleset `protect-master` (id 24043808).
      # git commit/pull/fetch: signing key + SSH remote, both denied inside.
      # An exclusion only applies when the Bash call is that command ALONE:
      # `cd … &&`, `$(…)`, heredoc or redirection keep the call sandboxed.
      # hooks/lone-excluded-bash.js denies those shapes for git push/commit/
      # pull/fetch, gh and claude-dispatch before they run.
      # nix flake check: sandboxed it hits EPERM on the daemon socket
      # (/nix/var/nix/daemon-socket/socket) and on ~/.cache/nix sqlite.
      # Excluding the one command; the daemon socket is never in
      # allowUnixSockets (check A14b): the user is in trusted-users (@admin),
      # so an open daemon socket would hand every sandboxed command a
      # root-equivalent channel.
      # Bare form ONLY, never "nix flake check *": an argument can name a remote
      # flake or `--override-input`, i.e. arbitrary nix code evaluated
      # unsandboxed by a trusted user.
      excludedCommands = [
        "sudo *"
        "darwin-rebuild *"
        "codex *"
        # claude-dispatch: sandboxed `abduco -n` → EPERM on create-session
        # (its socket, measured 2026-10-20), and a sandboxed abduco server would
        # pass its Seatbelt profile to the session. Wrapper, never
        # "claude *"/"abduco *": claude takes ~20 flags that widen the
        # launched session (--dangerously-skip-permissions, --settings,
        # --add-dir, --mcp-config, --bare…); the wrapper fixes argv to
        # `abduco -n <name> claude --worktree <name> --name <name>`. Still
        # classifier-reviewed (auto mode).
        "claude-dispatch *"
        # codex plugin: commands/agents call `node "${CLAUDE_PLUGIN_ROOT}/…/
        # codex-companion.mjs" …`, substituted to the absolute path BEFORE the
        # Bash call (docs: plugins-reference#where-each-variable-resolves).
        # Measured: sandboxed → loggedIn false (auth.json denyRead, network);
        # unsandboxed → ready. Version pinned, no `*` before the arguments: a
        # `*/` or `../` there would let `node <any script>` (e.g. a fake one in
        # $TMPDIR) leave the sandbox; ~/.claude/plugins is denyWrite inside it.
        # Plugin update = new version dir → bump 1.0.6 here (A27 reminds).
        # `--cwd` = same rights as `codex *` already excluded. Closed below:
        # git config/hooks under /tmp (denyWrite, real barrier), `--prompt-file`
        # (reads any file unsandboxed, unused by the plugin) and a NODE_OPTIONS
        # preload scoped to the companion — plain `NODE_OPTIONS=… pnpm build`
        # stays allowed (permissions.deny, textual guardrails).
        "node \"${homeDirectory}/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs\" *"
        "gh *"
        "git push *"
        "git commit *"
        "git pull *"
        "git fetch *"
        "nix flake check"
        # nix build/eval + docker: user decision 2026-10-22 — the escape box
        # was always approved anyway. Risk accepted: as a trusted user,
        # nix build/eval with --option/--override-input/--expr is
        # root-equivalent; docker via colima = root in a VM mounting $HOME rw,
        # a full escape. nix shell/run/develop stay sandboxed (they run an
        # arbitrary command; A29). Inconsistent on purpose: flake check stays
        # bare-only, "nix flake check *" banned (A14b), though `nix eval *`
        # reaches the same remote-flake/--override-input code.
        "nix build *"
        "nix eval *"
        "docker *"
      ];
      filesystem = {
        denyWrite = [
          "/etc"
          "/System"
          "/Library"
          "${homeDirectory}/.ssh/id_*"
          "${homeDirectory}/.ssh/config"
          "${homeDirectory}/.aws"
          "${homeDirectory}/.gnupg"
          "${homeDirectory}/.config/secrets"
          # ~/.codex is in allowWrite below so the codex CLI can open its session
          # DB. These four are the parts of it that EXECUTE: hooks.json and
          # hooks/ hold commands codex runs, config.toml can declare more, and
          # AGENTS.md is instructions it obeys. Writable, they would turn one
          # injected shell command into code that runs on the user's next codex
          # session — so deny wins inside the allowed directory. auth.json stays
          # writable on purpose: the CLI refreshes its own token there, and
          # denying it would break re-auth for no attacker gain.
          "${homeDirectory}/.codex/hooks.json"
          "${homeDirectory}/.codex/hooks"
          "${homeDirectory}/.codex/config.toml"
          "${homeDirectory}/.codex/AGENTS.md"
          # git commit/push/fetch/pull run OUTSIDE the sandbox (excludedCommands)
          # and execute the repo's hooks and config (core.hooksPath, fsmonitor,
          # sshCommand…). A sandboxed write there = code run unsandboxed on the
          # next git call. Built-in protection covers only the cwd's .git; this
          # extends it to every repo under $HOME. Absolute on purpose: an
          # unprefixed path in user settings resolves under ~/.claude, and
          # denyWrite wildcards work on macOS only (docs: settings-reference
          # #sandbox-path-prefixes).
          "${homeDirectory}/**/.git/hooks"
          "${homeDirectory}/**/.git/config"
          # The vault .git is in allowWrite below. Writing `commondir` ALONE
          # redirects git to another dir's config, hence core.hooksPath:
          # probed 2026-10-14, `git config --show-origin core.hooksPath` then
          # read <evil>/config. The hooks/config denies above do not cover it.
          "${alxVaultPath}/.git/commondir"
          # $TMPDIR (/tmp/claude-<uid>, /private/tmp/claude-…) is writable from
          # the sandbox: a repo created there could get core.fsmonitor/hooksPath
          # or a hook, then run by an excluded git command or the codex
          # companion's `review --cwd`. Real barrier, not a textual guardrail.
          "/tmp/**/.git/config"
          "/tmp/**/.git/hooks"
          "/private/tmp/**/.git/config"
          "/private/tmp/**/.git/hooks"
          # Same for the GLOBAL config (core.sshCommand, core.hooksPath…), read
          # by every excluded git command. ~/.config/git is home-manager's
          # (programs.git) — written at activation, outside this sandbox.
          "${homeDirectory}/.gitconfig"
          "${homeDirectory}/.config/git"
          # ~/.cargo/registry and git are in allowWrite below; these are the
          # parts of ~/.cargo that run code or hold credentials: bin/ is on PATH
          # (home/default.nix:36), config* can set build.rustc-wrapper or
          # net.git-fetch-with-cli, env is sourced. Deny wins inside an allowed
          # dir; absent paths are fine.
          "${homeDirectory}/.cargo/bin"
          "${homeDirectory}/.cargo/config.toml"
          "${homeDirectory}/.cargo/config"
          "${homeDirectory}/.cargo/credentials.toml"
          "${homeDirectory}/.cargo/env"
        ];
        denyRead = [
          # Sans cette entrée, la clé privée était lisible depuis le sandbox :
          # `wc -c < ~/.ssh/id_ed25519` → 399. denyRead accepte un répertoire et
          # bloque son contenu récursivement (exemple officiel : `"denyRead": ["~/"]`).
          # Le denyWrite sur ~/.ssh/id_* reste : écriture ≠ exfiltration.
          "${homeDirectory}/.ssh"
          "${homeDirectory}/.aws/credentials"
          "${homeDirectory}/.gnupg/private-keys-v1.d"
          # NOTE: la clé publique est ré-ouverte plus bas via allowRead.
          # Ancré sur $HOME : non préfixé, un chemin des settings user se
          # résout sous ~/.claude (docs: settings-reference
          # #sandbox-path-prefixes). `.env` / `.env.*` ne sont plus refusés
          # au sandbox (décision utilisateur 2026-10-19) : l'agent de fond lance
          # le serveur de dev et les migrations, qui lisent `.env` sous le même
          # profil Seatbelt, et le code qu'il écrit tourne de toute façon avec
          # le secret. Voir aussi permissions.deny (plus de `Read(**/.env*)`).
          "${homeDirectory}/**/secrets"
        ];
        # Ré-ouvre la clé PUBLIQUE, que le denyRead sur ~/.ssh emportait aussi.
        # git signe les commits en SSH (`gpg.format=ssh`, signingkey
        # ~/.ssh/id_ed25519.pub) : sans ça, TOUT commit échoue dans le sandbox
        # avec « Couldn't load public key ». Régression introduite par la PR
        # #101 et constatée au premier commit suivant. Une clé publique est
        # publique — la privée, elle, reste refusée.
        # Trello : le wrapper `trello` (home/claude-code/trello.nix) lit la clé
        # et le token lui-même, dans un sous-processus sandboxé — ces deux
        # entrées sont ce qui le fait marcher. `${homeDirectory}/**/secrets`
        # ci-dessus et `Read(~/.config/secrets/**)` (fusionné au sandbox) les
        # bloquent ; la règle au chemin le plus étroit l'emporte (docs:
        # sandboxing), donc ces deux FICHIERS seuls sont ré-ouverts — le reste
        # du répertoire reste refusé. Le deny `Read(~/.config/secrets/**)`
        # bloque toujours le Read / `cat` de Claude lui-même : seul le wrapper
        # les lit, et il ne les affiche jamais.
        allowRead = [
          "${homeDirectory}/.ssh/id_ed25519.pub"
          "${homeDirectory}/.config/secrets/trello-api-key"
          "${homeDirectory}/.config/secrets/trello-token"
        ];
        # graphify-reindex (fired in BACKGROUND by APEX steps 01b/09b) writes
        # the knowledge graph to ~/GraphVault — outside the session cwd, so the
        # default sandbox write-set (cwd + tmp) would kill it with "operation
        # not permitted" and force a dangerouslyDisableSandbox box at the end
        # of every `-n` session. allowWrite EXTENDS the writable set; it never
        # re-opens a denyWrite path. The vault work tree stays Bash-unwritable
        # (outside cwd): session notes go through the Write tool, as before.
        # Its `.git` IS writable, so a sandboxed `git add`/`git status` in the
        # vault stops failing on `.git/index.lock`. Hooks and config stay
        # closed by the `**/.git/{hooks,config}` denyWrite above; commondir is
        # closed in denyWrite below.
        # rtk keeps its trust store, command history and tee logs under its
        # data dir. Inside the sandbox those writes fail, and rtk does NOT
        # error — it falls back to unfiltered pass-through, silently. Measured
        # on 2026-09-05, same command, same second, only the sandbox differing:
        #   rtk nix-instantiate --parse modules/packages.nix
        #   inside  -> 1045 bytes (raw)
        #   outside ->  211 bytes (filtered)
        # So every output filter was dead in-session while looking configured:
        # `rtk trust --list` showed the file trusted and `rtk hook check` showed
        # the rewrite. Only a byte count caught it.
        # Scope is the data dir alone — no credentials live there.
        # NOT here, deliberately: Chromium's profile dir for Scrapling's browser
        # rungs (`extract fetch` / `stealthy-fetch`). It was added on
        # 2026-09-08, rebuilt, and MEASURED to buy nothing. The path entry does
        # work — the Crashpad "Operation not permitted" line disappeared and the
        # profile dir got created — but the browser still aborts with no output
        # file on things a path allowlist cannot reach:
        #   bootstrap_check_in org.chromium.crashpad...: Permission denied (1100)
        #   process_singleton_posix.cc: Failed to create socket directory.
        #   exception while trying to kill process: Error: kill EPERM
        # Mach IPC registration, a unix socket dir, and process signalling.
        # allowMachLookup cannot fix the first: bootstrap_check_in is
        # mach-register, srt emits only mach-lookup (measured 2026-10-22). The
        # CLI offers no `--user-data-dir` to relocate the profile either, so
        # there is no lever. Reverted rather than kept: an allowlist entry that
        # widens the sandbox while implying a capability that does not exist is
        # worse than none. The browser rungs run with the sandbox disabled —
        # verified working, one confirmation box.
        # The codex CLI (APEX `-e`, external verifier) opens a session state DB
        # under $CODEX_HOME. With the sandbox as-is, the run aborts before it
        # reviews anything: `unable to open database file` on
        # ~/.codex/state_5.sqlite. No flag relocates it, so the path is the
        # only lever. As above, allowWrite EXTENDS the writable set only — it
        # grants no read it did not already have and re-opens nothing covered
        # by denyRead.
        # pnpm 12 honours `packageManager: pnpm@9.x` by installing that version
        # under ~/Library/pnpm/.tools (from package-manager-store) and
        # re-executing it: sandboxed, the switch dies on
        # ERR_PNPM_LOCKFILE_WRITE_FILE. Those two dirs whole — not bin/,
        # store/ or global/ (two file names below). Residual risk: a binary
        # planted in .tools runs on the next pnpm call that pins that version,
        # a terminal one included.
        # Its store operation lock is NOT under ~/Library/pnpm (#250 guessed wrong): a
        # deny-all-writes sandbox-exec replay (2026-10-14) showed pnpm chmods
        # /private/tmp/pnpm-store-operation-locks-<uid> and pnpm-dir-locks-<uid>.
        # Literal paths (uid 501), not a glob: an allowWrite glob compiles to an
        # anchored regex that does not cover the lock files inside.
        # With the lock open the switch still died on ERR_PNPM_LOCKFILE_WRITE_FILE:
        # a sandbox-exec replay (2026-10-14) showed the engine writes
        # global/v11/pnpm-lock.yaml through a `.tmp*` sibling and a rename.
        # Those two names only; the global/v11/<hash> package dirs, which the
        # bin/ shims run, stay closed. allowWrite wildcards work on macOS only
        # (docs: settings-reference #sandbox-path-prefixes).
        # Measured over 30 d / 1378 transcripts: ~/.cargo/registry/{index,cache}
        # 4 fatal; ~/.cache/uv 13 fatal; ~/.config/.wrangler/logs ~60 non-fatal
        # but counted as escape evidence.
        # Replay 2026-10-14 (deny-all sandbox-exec): cargo also writes its lock
        # and last-use DB at CARGO_HOME root (.package-cache,
        # .package-cache-mutate, .global-cache, .global-cache-journal); without
        # them it runs unlocked, no error. Literal files, nothing else at root
        # opened.
        # Residual a' (accepted by the user 2026-10-14): registry/src,
        # git/checkouts and the uv cache feed code cargo/uv build and run
        # OUTSIDE the sandbox in any project; a planted source runs on the next
        # terminal build resolving that version (same class as pnpm .tools).
        # git/db = bare repos with config/hooks; libgit2 (cargo default) runs
        # no hooks.
        # Rejected: ~/.cache whole (zsh_eval_cache_* sourced by every shell;
        # ~/.cache/nix read by the excluded `nix flake check`); ~/.cargo whole
        # (bin/, config); ~/.rustup (toolchains executed); ~/Library/Caches
        # (other apps' executable caches); ~/.local/bin and
        # ~/.local/share/uv/tools (uvx needs tools/.lock but scrapling/graphify
        # live there, so uvx stays an escape; `uv run --with` works sandboxed);
        # CARGO_HOME/UV_CACHE_DIR redirect (user chose real caches).
        # ~/.config/.wrangler/config (2026-10-18): the OAuth access token lives 1 h;
        # wrangler then spends the single-use refresh token and writes the new pair
        # to config/default.toml (or <profile>.enc, same dir). Sandboxed, that write
        # died EPERM after the refresh was spent: the pair was lost and the next
        # unsandboxed deploy got 400, forcing `wrangler login`. Residual risk
        # (accepted by the user 2026-10-18): a sandboxed command can overwrite the
        # Cloudflare OAuth pair (already readable); no code in that dir runs.
        # ~/.cache/watch (2026-10-22): the /watch skill's WhisperX venv
        # (setup.py:277) and, through HF_HOME/TORCH_HOME in env, its model
        # caches. Measured in a scratchpad test the same day: sandboxed, the
        # model download died EPERM on ~/.cache/huggingface; with the caches
        # writable, download, frames and transcription ran sandboxed.
        # Redirected, unlike CARGO_HOME/UV_CACHE_DIR: neither real cache
        # existed, and torch/hub keeps repo code torch.hub runs, so the real
        # path would be class c for any later unsandboxed torch user.
        # Residual (accepted by the user 2026-10-22): venv bin/ and hub code run
        # OUTSIDE the sandbox when setup.py is rerun unsandboxed. The one-time
        # install runs outside it anyway: the proxy truncated the torch-hub zip
        # and broke HF xet transfers.
        # Check A28 (checks/claude-config.nix) pins this.
        allowWrite = [
          "${homeDirectory}/GraphVault"
          "${homeDirectory}/Library/Application Support/rtk"
          "${homeDirectory}/.codex"
          "${homeDirectory}/Library/pnpm/.tools"
          "${homeDirectory}/Library/pnpm/package-manager-store"
          "/private/tmp/pnpm-store-operation-locks-501"
          "/private/tmp/pnpm-dir-locks-501"
          "${homeDirectory}/Library/pnpm/global/v11/pnpm-lock.yaml"
          "${homeDirectory}/Library/pnpm/global/v11/.tmp*"
          "${alxVaultPath}/.git"
          "${homeDirectory}/.config/.wrangler/logs"
          "${homeDirectory}/.config/.wrangler/config"
          "${homeDirectory}/.cargo/registry"
          "${homeDirectory}/.cargo/git"
          "${homeDirectory}/.cargo/.package-cache"
          "${homeDirectory}/.cargo/.package-cache-mutate"
          "${homeDirectory}/.cargo/.global-cache"
          "${homeDirectory}/.cargo/.global-cache-journal"
          "${homeDirectory}/.cache/uv"
          "${homeDirectory}/.cache/watch"
        ];
      };
      network = {
        # All domains allowed (web analysis, design, docs, APIs)
        allowedDomains = [ "*" ];
        # pgrep: sandboxed it fails "sysmond service not found" (2026-10-22).
        # Residual: pgrep -lf shows other processes' argv. /bin/ps stays an
        # escape (setuid exec denied).
        allowMachLookup = [ "com.apple.sysmond" ];
        # tsx 4.x CLI: its IPC server listen() dies EPERM on
        # /tmp/claude-501/tsx-501/<pid>.pipe; no env opt-out (`node --import
        # tsx` works). Exact dir under the sandbox TMPDIR only (A14b); needs a
        # post-switch probe.
        allowUnixSockets = [ "/private/tmp/claude-501/tsx-501" ];
      };
    };

    # Contrôle ce que le prompt système liste à CHAQUE tour. Le vocabulaire a
    # QUATRE valeurs, pas deux : `on` (nom + description, défaut quand la clé
    # est absente), `name-only` (nom seul), `user-invocable-only` (retiré du
    # listing, toujours tapable), `off` (désactivé).
    # Les 8 entrées ci-dessous sont mesurées : JAMAIS invoquées sur 214
    # démarrages, tout en occupant le listing à chaque tour.
    # `user-invocable-only` est délibéré : il sort l'entrée du listing que le
    # modèle voit, mais `/caveman`, `/tdd` et les autres restent tapables.
    # `off` a été écarté : il retire AUSSI l'entrée du menu slash, de Remote
    # Control et des listes de commandes de l'Agent SDK — la taper renvoie
    # alors une erreur.
    # ATTENTION : cinq des huit sont des fichiers COMMANDE sous
    # ~/.claude/commands/, pas des skills. Qu'ils soient couverts est un
    # comportement MESURÉ, pas un contrat documenté : la doc ne décrit la clé
    # que comme prenant des noms de skills, et la page « commands merged into
    # skills » ne dit nulle part que les deux se rejoignent ici. Vérifié sur le
    # binaire installé 2.1.268, lancé avec `--settings` : un fichier commande et
    # un vrai skill disparaissent du listing à l'identique. À re-vérifier après
    # chaque upgrade — rien ne le garantit.
    # Une VALEUR non reconnue est ignorée en silence : ni erreur, ni check qui
    # l'attrape. C'est la raison d'être de ce commentaire.
    skillOverrides = {
      auto = "user-invocable-only";
      caveman = "user-invocable-only";
      cavemem = "user-invocable-only";
      "context-prime" = "user-invocable-only";
      optimize = "user-invocable-only";
      schliff = "user-invocable-only";
      tdd = "user-invocable-only";
      # Overlaps the claude-security plugin's triggers: typed `/security-audit` only.
      "security-audit" = "user-invocable-only";
      "verify-feature" = "user-invocable-only";
      # `name-only` (2026-10-10) : skills intégrées ou maison rarement utiles
      # ici ; le nom reste listé donc invocable par le modèle, la description
      # (jusqu'à 1 536 caractères) sort du contexte de chaque tour. Les skills
      # de plugins (anthropic-skills:*, codex:*) ne sont pas couvertes : /plugin.
      "artifact-capabilities" = "name-only";
      "artifact-diagramming" = "name-only";
      autoresearch = "name-only";
      dataviz = "name-only";
      "design-md" = "name-only";
      "fewer-permission-prompts" = "name-only";
      init = "name-only";
      "keybindings-help" = "name-only";
      schedule = "name-only";
      "security-review" = "name-only";
      # Skills synchronisées depuis claude.ai (`anthropic-skills:*`), jamais
      # utilisées ici d'après /plugin (2026-10-11) : retirées du listing,
      # toujours tapables. Clé = nom simple, sans préfixe : sonde `claude -p
      # --settings` avec témoin, `morning` et `canvas-design` disparaissent du
      # listing, `docx` reste. Sans effet sur le compte claude.ai.
      "academic-pptx" = "user-invocable-only";
      "brand-guidelines" = "user-invocable-only";
      "built-in-browser" = "user-invocable-only";
      "canvas-design" = "user-invocable-only";
      "chrome-browser" = "user-invocable-only";
      "computer-use" = "user-invocable-only";
      "import-memory" = "user-invocable-only";
      morning = "user-invocable-only";
      "pptx-from-layouts" = "user-invocable-only";
    };

    # Contexte du classifieur auto mode (https://code.claude.com/docs/en/auto-mode-config).
    # Lu en scope utilisateur uniquement, jamais depuis .claude/settings*.json.
    # "$defaults" en tête : sans lui, la liste REMPLACE les règles intégrées.
    autoMode = {
      environment = [
        "$defaults"
        "Organization: personal nix-darwin config repo AlxWrtl/NixConfig (github.com), cloned at ~/.config/nix-darwin; primary use: personal macOS system configuration."
        "Source control: master is protected server-side by the GitHub ruleset protect-master (PR required, force-push and deletion refused, no bypass); the agent works on feature branches it creates itself."
        "Trello: api.trello.com is the user's own Trello account, reached only through the packaged `trello` CLI wrapper (reads ~/.config/secrets/trello-* itself, never prints them); reading boards and creating/moving/commenting cards there is trusted user-intended data flow."
      ];
      allow = [
        "$defaults"
        "Local branch housekeeping in ~/.config/nix-darwin (AlxWrtl/NixConfig): switching branches, and deleting LOCAL branches the agent created in this repo — including unmerged disposable/probe branches — and branches already merged. Never master; master is protected by protect-master."
      ];
    };

    # Plugin officiel OpenAI (/codex:review, /codex:adversarial-review,
    # /codex:rescue), installé en arrière-plan au démarrage d'une session,
    # scope user. Il passe par `node …/codex-companion.mjs` → `codex app-server`
    # (JSON-RPC, sandbox read-only, workspace-write au plus pour /codex:rescue
    # --write, approvalPolicy never, jamais danger-full-access). node n'est pas
    # exclu : tout tourne DANS le Seatbelt de Claude, où le sandbox propre de
    # Codex ne peut pas s'imbriquer — fonctionnement à mesurer après switch.
    # Pas de review gate Stop pour l'instant.
    # Maps : le deep merge d'activation ajoute ces clés sans écraser les
    # plugins activés via /plugin — pas de force-override, voulu (A26).
    extraKnownMarketplaces = {
      "openai-codex" = {
        source = {
          source = "github";
          repo = "openai/codex-plugin-cc";
        };
      };
    };
    enabledPlugins = {
      "codex@openai-codex" = true;
      # Anthropic's on-demand scanner (`/claude-security`), installed as
      # shipped: its license is proprietary, so no copy lives in this repo.
      # security-guidance is left off on purpose (hooks on every edit,
      # commit and Stop, LLM review rewakes outside the correction budget).
      "claude-security@claude-plugins-official" = true;
    };
    # Options of the mods' plugin.json userConfig, read from user settings
    # only (`pluginConfigs[<name>].options`). The deck mod opens only on
    # `/deck` and draws no status line by construction (no option); its
    # panel list is seeded here. Not force-overridden: the deep merge seeds
    # it, a /config change survives.
    pluginConfigs = {
      deck.options = {
        panels = "main,architect,agents,background,receipt,log";
      };
    };

    permissions = {
      # `auto` délègue chaque décision de permission à un classifieur de sûreté
      # au lieu de demander à l'utilisateur — il remplace un mode choisi
      # délibérément (`acceptEdits`), donc la frontière n'est plus la même.
      # Les garde-fous du repo ne disparaissent PAS avec lui : le gate APEX sur
      # Edit/Write (require-apex.js) et les hooks de branche (protect-main.js,
      # block-main-bash.js) sont de l'application, pas de la suggestion, et le
      # mode de permission ne les touche pas.
      defaultMode = "auto";
      # `ask` forces a confirmation box for matching commands, overriding
      # skipDangerousModePermissionPrompt and acceptEdits. Precedence: deny > ask > allow.
      # Box only for sudo (sudo git, sudo darwin-rebuild, …). A bare "Bash" rule
      # here fires on every out-of-sandbox command → box spammée, don't add it.
      ask = [
        "Bash(sudo *)"
        # User decision 2026-09-28: no ask on `gh pr merge` / mutating `gh api`
        # — the agent squash-merges its own green PRs. Server-side barrier for
        # master = GitHub ruleset `protect-master` (id 24043808). A19 pins this.
      ];
      allow = [
        "Read(*)"
        # Package managers
        "Bash(pnpm *)"
        "Bash(npm run *)"
        "Bash(dev-browser *)"
        "Bash(npx dev-browser *)"
        "Bash(npx -y @oomkapwn/enquire-mcp*)"
        "Bash(enquire-mcp *)"
        "Bash(npx ccusage@*)"
        "Bash(npx prettier *)"
        "Bash(npx tsc *)"
        "Bash(bunx *)"
        "Bash(node *)"
        # Library docs via the Context7 REST API. A narrow grant on purpose:
        # the wrapper exists so this rule is not `Bash(curl *)`.
        "Bash(libdocs *)"
        # Trello REST API via the packaged wrapper: it reads the secrets itself and
        # keeps them out of argv, URL and output. Narrow on purpose, never `Bash(curl *)`.
        "Bash(trello *)"
        # Nix option docs at the flake.lock rev: read-only eval, sandboxed, own read-only-store fallback. Never in excludedCommands.
        "Bash(nix-options *)"
        # External cross-vendor verifier (APEX `-e`). Wrapper around a
        # read-only `codex exec` subprocess: it reviews, it never edits.
        "Bash(apex-verify-external *)"
        # APEX tier classifier: read-only git diff/show/ls-files over the diff.
        "Bash(apex-tier *)"
        # Knowledge-graph refresh wrapper (no args; writes only to ~/GraphVault
        # — see sandbox allowWrite). Fired in background by APEX steps 01b/09b.
        "Bash(graphify-reindex)"
        # vault-snapshot auto-commits dirty notes onto `vault/<stamp>` in the
        # vault, then uploads the encrypted bundle to AlxWrtl/attic. Run as
        # sandboxed Bash it cannot write the vault .git/hooks: logs
        # skip=sandboxed, exits 0.
        "Bash(vault-snapshot)"
        # Git — safe operations (granular, not blanket)
        "Bash(git status *)"
        "Bash(git diff *)"
        "Bash(git log *)"
        "Bash(git branch *)"
        "Bash(git show *)"
        "Bash(git stash *)"
        "Bash(git fetch *)"
        "Bash(git pull *)"
        "Bash(git add *)"
        "Bash(git checkout -b *)"
        "Bash(git switch *)"
        "Bash(git commit *)"
        "Bash(git push)"
        "Bash(git push -u *)"
        "Bash(git push origin *)"
        "Bash(git merge *)"
        "Bash(git rebase *)"
        "Bash(git cherry-pick *)"
        "Bash(git tag *)"
        "Bash(git remote *)"
        "Bash(git rev-parse *)"
        "Bash(git ls-files *)"
        "Bash(git blame *)"
        "Bash(git shortlog *)"
        # GitHub CLI
        "Bash(gh pr *)"
        "Bash(gh issue *)"
        "Bash(gh repo *)"
        "Bash(gh run *)"
        "Bash(gh api *)"
        "Bash(gh auth *)"
        # Nix
        "Bash(darwin-rebuild *)"
        "Bash(nix *)"
        "Bash(nixfmt *)"
        # File operations (read-only + safe)
        "Bash(ls *)"
        "Bash(cat *)"
        "Bash(find *)"
        "Bash(grep *)"
        "Bash(head *)"
        "Bash(tail *)"
        "Bash(wc *)"
        "Bash(echo *)"
        "Bash(which *)"
        "Bash(env *)"
        "Bash(pwd)"
        "Bash(mkdir *)"
        "Bash(cp *)"
        "Bash(mv *)"
        # RTK
        "Bash(rtk *)"
        # Tools
        "Bash(jq *)"
        "Bash(fd *)"
        "Bash(rg *)"
        "Bash(bat *)"
        "Bash(eza *)"
        # WebFetch — every domain (research is never blocked; denyRead still guards secrets)
        "WebFetch"
      ];
      deny = [
        # Shell bypass — prevent permission/hook circumvention
        "Bash(bash -c *)"
        "Bash(bash -i *)"
        "Bash(sh -c *)"
        "Bash(sh -i *)"
        "Bash(zsh -c *)"
        "Bash(zsh -i *)"
        "Bash(python -c *)"
        "Bash(python3 -c *)"
        "Bash(node -e *)"
        "Bash(node --eval *)"
        "Bash(ruby -e *)"
        "Bash(perl -e *)"
        "Bash(perl -E *)"
        "Bash(eval *)"
        # Git destructive ops
        "Bash(git push --force *)"
        "Bash(git push -f *)"
        "Bash(git push --force-with-lease *)"
        # Force-push / master target placed after the remote, gh/codex escape
        # hatches. Textual filtering = guardrail, not a barrier; server-side
        # barrier = GitHub ruleset `protect-master` (id 24043808).
        "Bash(git push *--force*)"
        "Bash(git push * -f*)"
        "Bash(git push *+*)"
        "Bash(git push *:master*)"
        "Bash(git push *:main*)"
        "Bash(git push * master)"
        "Bash(git push * main)"
        # Remote-side program override = arbitrary command, run unsandboxed
        # (git push/fetch/pull are excludedCommands). `--exec` = push alias of
        # --receive-pack. Abbreviated prefixes: git accepts any unique prefix of
        # a long option. Measured (git 2.55): `--up`/`--rec` are ambiguous and
        # refused, but `--upl`, `--rece` and even `--e` (only push option in e)
        # run CMD.
        "Bash(git fetch *--upl*)"
        "Bash(git pull *--upl*)"
        "Bash(git push *--rece*)"
        "Bash(git push *--e*)"
        # Repo hooks/config execute on the next unsandboxed git call. Edit only:
        # Write(path) rules are never consulted (docs: permissions#read-and-edit)
        # and Edit denies are also merged into sandbox denyWrite.
        "Edit(**/.git/hooks/**)"
        "Edit(**/.git/config)"
        # correction-budget.js counter: Edit deny also lands in sandbox
        # denyWrite, so neither Edit/Write nor Bash can reset a run's rounds.
        "Edit(~/.claude/apex-correction-budget/**)"
        "Bash(gh repo delete*)"
        "Bash(gh auth token*)"
        "Bash(gh auth *--show-token*)"
        "Read(~/.codex/auth.json)"
        "Bash(codex *danger-full-access*)"
        "Bash(codex *dangerously*)"
        "Bash(codex *sandbox_mode*)"
        "Bash(codex *sandbox_permissions*)"
        "Bash(node *codex-companion.mjs*prompt-file*)"
        "Bash(*NODE_OPTIONS=*codex-companion.mjs*)"
        # Note: commit/push/merge/rebase while ON master/main are hard-DENIED by
        # the block-main-bash hook (permissionDecision "deny", not a confirmation
        # box). deny/ask are textual filtering (guardrail, not a barrier); the
        # server-side barrier is the GitHub ruleset `protect-master` (id 24043808).
        "Bash(git reset --hard *)"
        "Bash(git clean -fdx *)"
        "Bash(git clean -fxd *)"
        "Bash(git checkout -- .)"
        # Filesystem destructive
        "Bash(rm -rf /*)"
        # Note: `sudo` intentionally NOT denied — Claude may invoke it but each
        # call requires interactive confirmation (not in allow-list either).
        "Bash(chmod 777 *)"
        # Secrets — `~/` anchors on $HOME. NOT "Read(${homeDirectory}/…)": in a
        # rule, one leading slash is relative to the settings source (user
        # settings → ~/.claude), so it guarded ~/.claude/Users/alx/.ssh;
        # absolute needs `//` (docs: permissions#read-and-edit).
        "Read(~/.ssh/**)"
        "Read(~/.aws/**)"
        "Read(~/.gnupg/**)"
        "Read(~/.config/secrets/**)"
        # `.env` / `.env.*` ouverts au sandbox ET à l'outil Read (décision
        # utilisateur 2026-10-19) : l'agent de fond lance dev et migrations,
        # le hook SessionStart/EnterWorktree copie ces fichiers dans les worktrees. Un deny
        # Read serait fusionné au sandbox sous le cwd (`Read(**/.env)` = tout
        # .env sous le cwd, docs: permissions + sandboxing) ; un ask bloquerait
        # chaque run autonome sur une boîte (A19 : ask = sudo seul).
        "Read(**/secrets/**)"
        # Network piping
        "Bash(curl * | sh)"
        "Bash(curl * | bash)"
        "Bash(wget * | sh)"
        "Bash(wget * | bash)"
        # WebSearch — allowed (needed for web analysis)
      ];
    };

    hooks = {
      PreToolUse = [
        {
          matcher = "Edit|Write|NotebookEdit";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/protect-main.js";
              timeout = 5;
            }
          ];
        }
        {
          # Reports the context size (tokens, from the transcript tail) when
          # APEX starts. Context only: never rewrites the flags, never decides
          # a permission. The tier is decided on the diff by `apex-tier`.
          matcher = "Skill";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/apex-flags.js";
              timeout = 5;
            }
          ];
        }
        {
          # Bash is in the matcher because Edit/Write are not the only way to
          # write a file: `sed -i`, a heredoc and a plain redirection all do,
          # and bypass-permissions mode actively steers toward them. Guarding
          # only the Edit door left the main entrance open. The hook itself
          # decides whether a given command actually writes into the repo.
          matcher = "Edit|Write|NotebookEdit|Bash";
          hooks = [
            {
              type = "command";
              # Enforces the APEX routing rule that apex-reminder only suggests.
              # Fires at most once per TASK — once per real user turn, not once
              # per session; fail-open on any error.
              command = "${node} ~/.claude/hooks/require-apex.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Bash";
          # `if` uses permission-rule syntax (single rule, no `|` alternation —
          # a composite pattern silently never matches and the hook never runs).
          # The script itself narrows to commit/push/merge/rebase via regex.
          "if" = "Bash(git *)";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/block-main-bash.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Bash";
          # No `if`: it holds one rule, and both `git` and `gh` are needed.
          # Denies a sandbox-excluded command (git push/commit/pull/fetch, gh)
          # composed with anything that keeps the call sandboxed. Fail-open.
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/lone-excluded-bash.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Bash";
          # No `if`: it holds one rule, and both `git worktree remove` and
          # `rm -r` are watched. Denies removing a worktree a live process
          # still has as cwd. Fail-closed once a shape matched: the timeout
          # stays above the hook's own 3 s watchdog, or a host kill would
          # turn its deny into an allow.
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/worktree-in-use.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Bash";
          # Denies a dangerouslyDisableSandbox call that no sandbox error,
          # user ask or allowlisted command justifies. Fail-open.
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/sandbox-escape-evidence.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Edit|Write|Bash|Agent";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/governance-audit.js";
              timeout = 3;
              async = true;
            }
          ];
        }
        {
          matcher = "Agent|SendMessage|CronCreate|ScheduleWakeup";
          hooks = [
            {
              type = "command";
              # APEX correction-round budget: denies the 3rd marked round of a
              # run, spawned or re-briefed by SendMessage, and a CronCreate or
              # ScheduleWakeup prompt carrying the `apex: +1 tour` grant line
              # (it would come back as a user turn). NOT async — a deny must
              # land before the spawn.
              command = "${node} ~/.claude/hooks/correction-budget.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Agent";
          hooks = [
            {
              type = "command";
              # Research agents on haiku: denies an Explore or
              # codebase-navigator spawn whose model is not "haiku" (absent
              # included). NOT async — a deny must land before the spawn.
              # Fail-open on unreadable input.
              command = "${node} ~/.claude/hooks/research-model.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              # Injects the React/RR7 docs reminder on the first .tsx/.jsx write
              # of a session. Emits additionalContext only — never a permission
              # decision — so require-apex and protect-main still run. NOT async:
              # additionalContext must reach the model before the tool call.
              command = "${node} ~/.claude/hooks/react-docs-gate.js";
              timeout = 5;
            }
          ];
        }
      ];
      PostToolUse = [
        {
          matcher = "Write|Edit";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/format-typescript.js";
              timeout = 10;
              async = true;
            }
          ];
        }
        {
          # Matcher = liste de chaînes EXACTES séparées par `|`, pas une regex :
          # un motif qui n'a que [A-Za-z0-9_-], espace, `,` et `|` est comparé
          # littéralement. Ne JAMAIS y ajouter `.*` (bascule en regex, gain nul),
          # et un `mcp__serveur` seul ne matcherait AUCUN outil.
          # `browser_run_code_unsafe` exécute lui aussi du JS dans la page
          # (1166 occurrences dans les transcripts locaux) : même risque de nul
          # mal lu, donc même garde. Cet ensemble doit rester RIGOUREUSEMENT
          # égal à la constante `TOOLS` du hook — le probe compare les deux
          # sens.
          matcher = "mcp__claude-in-chrome__javascript_tool|mcp__playwright__browser_evaluate|mcp__playwright__browser_run_code_unsafe";
          hooks = [
            {
              type = "command";
              # Synchrone, contrairement à ses deux voisins : `async = true`
              # déporte la livraison de `additionalContext` au tour de
              # conversation SUIVANT, alors que ce garde doit parler pendant
              # que la sonde est encore le sujet.
              command = "${node} ~/.claude/hooks/null-result-gate.js";
              timeout = 5;
            }
          ];
        }
        {
          # Nom d'outil exact (liste littérale, cf. matcher ci-dessus). Après
          # EnterWorktree le cwd de l'entrée est déjà la racine du worktree
          # (docs: hooks) : le hook ci-dessous y copie les .env du checkout
          # principal. Synchrone, même timeout qu'au SessionStart (D3 de
          # hook-wiring) : le contexte doit arriver avant le tour suivant.
          # Pas de SubagentStart : son entrée n'a qu'agent_id/agent_type, pas
          # le cwd du worktree ; le `.worktreeinclude` du repo couvre ce cas.
          matcher = "EnterWorktree";
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/worktree-env-sync.sh";
              timeout = 5;
            }
          ];
        }
        {
          # Après un `gh pr merge` qui a fusionné : écrit pr.md dans le run
          # APEX de la branche (le board le passe en Terminé). Synchrone :
          # pr.md est sur disque avant le tour suivant. Timeout au-dessus des
          # 2 + 2 + 10 s internes (lecture, git, gh).
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/apex-pr-record.js";
              timeout = 15;
            }
          ];
        }
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/circuit-breaker-reset.js";
              timeout = 3;
              async = true;
            }
          ];
        }
      ];
      PostToolUseFailure = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/circuit-breaker.js";
              timeout = 5;
            }
          ];
        }
      ];
      UserPromptSubmit = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/apex-reminder.sh";
              timeout = 3;
            }
            {
              type = "command";
              # Correction-round grant: a prompt line `apex: +1 tour` gives
              # the spent run one more round. NOT async — the grant must be
              # on disk before the coordinator re-spawns.
              command = "${node} ~/.claude/hooks/correction-grant.js";
              timeout = 5;
            }
            # Session state of an abduco session (claude-dispatch): working.
            # Registered on the five lifecycle events below with one timeout,
            # above the hook's 3 s watchdog. A no-op outside abduco.
            {
              type = "command";
              command = "${node} ~/.claude/hooks/session-state.js";
              timeout = 5;
            }
            # Instagram post/reel/tv link → context asking for the watch skill.
            # Timeout above the hook's 3 s watchdog; fail-open.
            {
              type = "command";
              command = "${node} ~/.claude/hooks/instagram-watch.js";
              timeout = 5;
            }
          ];
        }
      ];
      # needs-you, for the session-state hook. No matcher: every
      # notification type means the session is waiting on a human.
      Notification = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/session-state.js";
              timeout = 5;
            }
          ];
        }
      ];
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/session-start.sh";
              timeout = 5;
            }
            {
              # Session ouverte dans un worktree (`--worktree`, agent de fond) :
              # copie les .env ignorés du checkout principal qui y manquent,
              # pour que le serveur de dev démarre sans copie à la main
              # (décision utilisateur 2026-10-19). Synchrone, timeout = celui
              # du PostToolUse EnterWorktree.
              type = "command";
              command = "bash ~/.claude/hooks/worktree-env-sync.sh";
              timeout = 5;
            }
            # session-state: idle (after a compaction, the state it had).
            {
              type = "command";
              command = "${node} ~/.claude/hooks/session-state.js";
              timeout = 5;
            }
          ];
        }
        {
          matcher = "compact";
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/compact-context.sh";
              timeout = 3;
            }
          ];
        }
      ];
      # Knowledge-graph refresh. No matcher on purpose: all five `reason` values
      # mean "the session stopped", and a malformed matcher silently never
      # matches (see the `if = "Bash(git *)"` comment above). `async` detaches
      # the reindex from Claude Code's lifecycle; `timeout` only bounds the
      # stdin read, the work itself has already left via nohup.
      SessionEnd = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/graphify-reindex.sh";
              timeout = 5;
              async = true;
            }
            # Encrypted off-machine backup. Since the vault left ~/Documents on
            # 2026-09-09 it is no longer replicated by iCloud, and there is no
            # Time Machine destination on this machine: this hook is the vault's
            # only off-machine copy, so it runs on every session end rather than
            # on demand. Detached like the reindex; a failure is logged to
            # ~/GraphVault/vault-snapshot.log, never surfaced as a hook error.
            {
              type = "command";
              command = "bash ~/.claude/hooks/vault-snapshot.sh";
              timeout = 5;
              async = true;
            }
            # session-state: done. Synchronous so the file lands before the
            # process exits; its `timeout` also lifts the 1.5 s SessionEnd
            # budget (hooks reference), as the two entries above already do.
            {
              type = "command";
              command = "${node} ~/.claude/hooks/session-state.js";
              timeout = 5;
            }
          ];
        }
      ];
      SubagentStop = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/subagent-stop.js";
              timeout = 5;
            }
          ];
        }
      ];
      Stop = [
        {
          hooks = [
            {
              type = "command";
              command = "printf '\\e[>4;0m'";
              timeout = 1;
            }
          ];
        }
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/quality-gate.js";
              timeout = 10;
            }
          ];
        }
        # session-state: waiting.
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/session-state.js";
              timeout = 5;
            }
          ];
        }
      ];
      StopFailure = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/stop-failure.sh";
              timeout = 3;
            }
          ];
        }
      ];
    };
  };

  # ~/.claude/keybindings.json — déployé en symlink par home.file (claude-code.nix).
  # Toute modification passe désormais par nix : le fichier live est un lien vers
  # le store (lecture seule), une édition à la main échoue bruyamment (EROFS) au
  # lieu d'être écrasée silencieusement au rebuild suivant.
  #
  # Rebind du push-to-talk vocal : la barre Espace (défaut) tape des espaces par
  # key-repeat pendant qu'on la maintient. Cmd+K est inutilisable ici (Ghostty le
  # consomme : `super+k = clear_screen`, vérifié via `ghostty +list-keybinds`) et
  # Cmd+M appartient à macOS (minimize) → Cmd+U, libre des deux côtés.
  #
  # Littéral JSON (et non builtins.toJSON) pour rester octet-pour-octet identique
  # au fichier que le CLI génère/attend, indentation comprise.
  keybindingsJson = ''
    {
      "bindings": [
        {
          "context": "Chat",
          "bindings": {
            "meta+u": "voice:pushToTalk"
          }
        }
      ]
    }
  '';

  # MCP servers merged into ~/.claude.json (HOME root) by claudeCodeMcpMerge;
  # no runtime secret injection since `magic` left (2026-08-16)
  #
  # `magic` (@21st-dev/magic) removed 2026-08-16: React UI component generation
  # that went unused, and it was the only server needing an API key. The key
  # file at ~/.config/secrets/21st-dev-api-key is left on disk — deleting a
  # secret is the user's call, not the config's.
  mcpServersJson = builtins.toJSON {
    playwright = {
      type = "stdio";
      command = "npx";
      args = [
        "-y"
        "@playwright/mcp@latest"
      ];
    };
    # enquire-mcp — hybrid retrieval (BM25 + local ONNX embeddings + BGE reranker)
    # over the Obsidian vault. MIT, runs fully local, zero recurring cost.
    # Installed GLOBALLY (not npx -y) by the claudeCodeEnquire activation script:
    # npx caches the ~120 MB ONNX model in an ephemeral ~/.npm/_npx/<hash> dir
    # that gets purged → re-download on every restart. A global install keeps the
    # model cache in a stable node_modules, so startup stays fast.
    # Flags enable the FULL hybrid pipeline:
    #   --persistent-index  SQLite FTS5 BM25 index (sub-100ms keyword search)
    #   --enable-reranker   BGE cross-encoder rerank on top of RRF fusion
    #   --use-hnsw          in-memory HNSW vector index (sub-10ms top-K)
    #   --watch             incrementally re-sync FTS5 + embed-db on vault edits
    # One-time index build (run after install / big vault changes):
    #   enquire-mcp setup --vault "<path>"
    # Health check:  enquire-mcp doctor --vault "<path>"
    #   (NB: doctor's "model cache" check is a false-negative — it looks in
    #    ~/.cache/huggingface but transformers.js caches in node_modules; the
    #    model loads fine regardless. See HNSW/FTS5 lines in `serve` output.)
    # Verify wired:  claude mcp list   (look for "enquire")
    enquire = {
      type = "stdio";
      command = "${homeDirectory}/.npm-global/bin/enquire-mcp";
      args = [
        "serve"
        "--vault"
        alxVaultPath
        "--persistent-index"
        "--enable-reranker"
        "--use-hnsw"
        "--watch"
      ];
    };
    # graphify-mcp — knowledge-graph view over a notes dir (entities + relations
    # + clusters), served from a pre-built JSON snapshot. Installed by the
    # claudeCodeGraphify activation script (`uv tool install "graphifyy[ollama]"`),
    # binaries land in ~/.local/bin.
    # The graph is NOT built by this server; produce it out-of-band:
    #   graphify extract <dir> --backend claude-cli --out <dir>
    #   graphify cluster-only <dir> --backend claude-cli
    # The snapshot path MUST be absolute and passed as an argument: serve.py
    # otherwise resolves "graphify-out/graph.json" against the process CWD, and
    # never reads CLAUDE_PROJECT_DIR — an MCP server spawned by Claude Code has
    # no useful CWD. If the file doesn't exist yet, serve.py starts in degraded
    # mode (empty graph) instead of crashing, so an unbuilt vault is harmless.
    # Verify wired:  claude mcp list   (look for "graphify")
    # Tools are exposed as mcp__graphify__*
    graphify = {
      type = "stdio";
      command = "${homeDirectory}/.local/bin/graphify-mcp";
      args = [ "${homeDirectory}/GraphVault/graphify-out/graph.json" ];
    };
  };
}
