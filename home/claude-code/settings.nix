# Claude Code settings and statusline script
{ homeDirectory }:
let
  # Absolute path to node — /bin/sh can't find nix-installed node in PATH
  node = "/run/current-system/sw/bin/node";

  # Obsidian vault — shared constant, reusable by other modules.
  # Real on-disk location (NOT the iCloud~md~obsidian mirror path).
  alxVaultPath = "${homeDirectory}/Vaults/AlxVault";
in
{
  settingsJson = builtins.toJSON {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    language = "french";
    # xhigh = reco officielle coding/agentic (max: rendements décroissants).
    # Force-overridden par le merge activation — la valeur live suit le nix.
    effortLevel = "xhigh";
    showTurnDuration = true;

    env = {
      npm_config_prefer_pnpm = "true";
      npm_config_user_agent = "pnpm";
      BASH_DEFAULT_TIMEOUT_MS = "300000";
      BASH_MAX_TIMEOUT_MS = "600000";
      CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "90";
      CLAUDE_STREAM_IDLE_TIMEOUT_MS = "600000";
      CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
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
    skipDangerousModePermissionPrompt = true;

    attribution = {
      commit = "";
      pr = "";
    };

    includeCoAuthoredBy = false;

    statusLine = {
      type = "command";
      command = "$HOME/.claude/statusline.sh";
    };

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
      # nix flake check: sandboxed it hits EPERM on the daemon socket
      # (/nix/var/nix/daemon-socket/socket) and on ~/.cache/nix sqlite.
      # Excluding the one command, NOT allowUnixSockets: the user is in
      # trusted-users (@admin), so an open daemon socket would hand every
      # sandboxed command a root-equivalent channel.
      # Bare form ONLY, never "nix flake check *": an argument can name a remote
      # flake or `--override-input`, i.e. arbitrary nix code evaluated
      # unsandboxed by a trusted user.
      excludedCommands = [
        "sudo *"
        "darwin-rebuild *"
        "codex *"
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
          # Ancrés sur $HOME : non préfixé, un chemin des settings user se
          # résout sous ~/.claude (docs: settings-reference
          # #sandbox-path-prefixes). Mesuré en « **/.env » : ouvrir
          # ~/projects/Preliz/.env depuis le sandbox (`dd … count=0`) passait.
          "${homeDirectory}/**/.env"
          "${homeDirectory}/**/.env.*"
          "${homeDirectory}/**/secrets"
        ];
        # Ré-ouvre la clé PUBLIQUE, que le denyRead sur ~/.ssh emportait aussi.
        # git signe les commits en SSH (`gpg.format=ssh`, signingkey
        # ~/.ssh/id_ed25519.pub) : sans ça, TOUT commit échoue dans le sandbox
        # avec « Couldn't load public key ». Régression introduite par la PR
        # #101 et constatée au premier commit suivant. Une clé publique est
        # publique — la privée, elle, reste refusée.
        # Trello : le skill et /trello lisent la clé et le token par `cat` en
        # Bash (skills.nix, commands.nix). `${homeDirectory}/**/secrets`
        # ci-dessus et `Read(~/.config/secrets/**)` (fusionné au sandbox)
        # les bloquent ; la règle au chemin le plus étroit l'emporte (docs:
        # sandboxing), donc ces deux FICHIERS seuls sont ré-ouverts — le reste
        # du répertoire reste refusé.
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
        # re-opens a denyWrite path. The vault itself stays Bash-unwritable
        # (outside cwd): session notes go through the Write tool, as before.
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
        # Mach IPC registration, a unix socket dir, and process signalling. The
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
        allowWrite = [
          "${homeDirectory}/GraphVault"
          "${homeDirectory}/Library/Application Support/rtk"
          "${homeDirectory}/.codex"
        ];
      };
      network = {
        # All domains allowed (web analysis, design, docs, APIs)
        allowedDomains = [ "*" ];
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
      "verify-feature" = "user-invocable-only";
    };

    # Contexte du classifieur auto mode (https://code.claude.com/docs/en/auto-mode-config).
    # Lu en scope utilisateur uniquement, jamais depuis .claude/settings*.json.
    # "$defaults" en tête : sans lui, la liste REMPLACE les règles intégrées.
    autoMode = {
      environment = [
        "$defaults"
        "Organization: personal nix-darwin config repo AlxWrtl/NixConfig (github.com), cloned at ~/.config/nix-darwin; primary use: personal macOS system configuration."
        "Source control: master is protected server-side by the GitHub ruleset protect-master (PR required, force-push and deletion refused, no bypass); the agent works on feature branches it creates itself."
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
        # Nix option docs at the flake.lock rev: read-only eval, sandboxed, own read-only-store fallback. Never in excludedCommands.
        "Bash(nix-options *)"
        # External cross-vendor verifier (APEX `-e`). Wrapper around a
        # read-only `codex exec` subprocess: it reviews, it never edits.
        "Bash(apex-verify-external *)"
        # Knowledge-graph refresh wrapper (no args; writes only to ~/GraphVault
        # — see sandbox allowWrite). Fired in background by APEX steps 01b/09b.
        "Bash(graphify-reindex)"
        # vault-snapshot writes only to ~/GraphVault/vault-snapshot.log and to
        # the AlxWrtl/attic release assets; it never touches the vault itself.
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
        "Read(**/.env)"
        "Read(**/.env.*)"
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
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/protect-main.js";
              timeout = 5;
            }
          ];
        }
        {
          # Rewrites APEX flags from risk signals before the skill starts.
          # A typed flag is a floor, never a ceiling: nothing typed is stripped;
          # on a HIGH risk signal the missing depth flags and -e are added
          # (-E cancels -e).
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
      PreCompact = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/pre-compact-state.js";
              timeout = 10;
            }
          ];
        }
      ];
      PostCompact = [
        {
          hooks = [
            {
              type = "command";
              command = "${node} ~/.claude/hooks/post-compact-restore.js";
              timeout = 5;
            }
          ];
        }
      ];
      Notification = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/notification.sh";
              timeout = 3;
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
      TaskCompleted = [
        {
          hooks = [
            {
              type = "command";
              command = "bash ~/.claude/hooks/task-completed.sh";
              timeout = 3;
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

  statuslineScript = ''
    #!/usr/bin/env bash
    # Statusline: model, dir, branch, tokens, context bar, 5h + 7d rate-limit bars.
    # Rate-limit data comes straight from Claude Code's JSON (rate_limits.*), the
    # same source as the official usage screen — no ccusage, no transcript parsing.

    INPUT=$(cat)

    # Colors — use $'...' so bash expands \033 at assignment time. This avoids
    # printf "%b", which mangles the UTF-8 bytes of █/░ under a UTF-8 locale.
    RED=$'\033[91m'
    ORANGE=$'\033[38;5;208m'
    YELLOW=$'\033[93m'
    GREEN=$'\033[92m'
    CYAN=$'\033[96m'
    BLUE=$'\033[94m'
    GREY=$'\033[90m'
    RESET=$'\033[0m'

    # Glyphs built from explicit UTF-8 bytes via printf, so no literal multibyte
    # char lives in the source (avoids byte truncation through the nix/CC pipeline).
    FULL_CH=$(printf '\xe2\x96\x88')        # █ U+2588 full block
    EMPTY_CH=$(printf '\xe2\x96\x91')       # ░ U+2591 light shade

    # Render a 10-cell progress bar: filled colored by threshold (green<60,
    # orange<85, red>=85), empty in neutral grey so it stays visible.
    make_bar() {
      local pct=$1
      [ -z "$pct" ] && pct=0
      pct=''${pct%.*}                       # strip decimals
      [ "$pct" -gt 100 ] 2>/dev/null && pct=100
      [ "$pct" -lt 0 ] 2>/dev/null && pct=0
      local filled=$((pct / 10))
      local empty=$((10 - filled))
      local color=$GREEN
      [ "$pct" -ge 60 ] && color=$ORANGE
      [ "$pct" -ge 85 ] && color=$RED
      local full="" rest=""
      local i
      for ((i=0; i<filled; i++)); do full="$full$FULL_CH"; done
      for ((i=0; i<empty;  i++)); do rest="$rest$EMPTY_CH"; done
      printf '%s%s%s%s%s' "$color" "$full" "$GREY" "$rest" "$RESET"
    }

    if command -v jq >/dev/null 2>&1; then
      MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "opus"' | sed -E 's/ *\(.*\)//')
      TOKENS_IN=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0')
      TOKENS_OUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0')
      CONTEXT_PCT=$(echo "$INPUT" | jq -r '(.context_window.used_percentage // 0) | round')

      WORKSPACE_DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."')
      # Strip trailing slashes before taking the basename, else "/" and "/a/b/"
      # both yield "". Nothing left (the root itself) falls back to "/".
      CWD=''${WORKSPACE_DIR%"''${WORKSPACE_DIR##*[!/]}"}
      CWD=''${CWD##*/}
      CWD=''${CWD:-/}
      GIT_BRANCH=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || echo "")

      # Rate limits straight from Claude Code JSON (Pro/Max only; absent before the
      # first API call). used_percentage = quota consumed; resets_at = unix epoch.
      NOW=$(date +%s)
      H5_PCT=$(echo "$INPUT" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | round')
      H5_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty')
      D7_PCT=$(echo "$INPUT" | jq -r '(.rate_limits.seven_day.used_percentage // empty) | round')
      D7_RESET=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty')
    else
      MODEL="opus"
      CWD=$(basename "$(pwd)")
      GIT_BRANCH=$(git branch --show-current 2>/dev/null)
      TOKENS_IN="0"; TOKENS_OUT="0"; CONTEXT_PCT="0"
      H5_PCT=""; H5_RESET=""; D7_PCT=""; D7_RESET=""
    fi

    TOKENS_IN_FMT=$(printf "%'d" $TOKENS_IN 2>/dev/null || echo $TOKENS_IN)
    TOKENS_OUT_FMT=$(printf "%'d" $TOKENS_OUT 2>/dev/null || echo $TOKENS_OUT)

    CTX_BAR=$(make_bar "$CONTEXT_PCT")

    # Time until an epoch reset:
    #   < 1h   -> "42min"
    #   < 24h  -> "H.MMh" where digits after the dot are literal minutes (00-59), e.g. "5.07h"
    #   >= 24h -> "Xj Yh" days + remaining whole hours, e.g. 120h52min -> "5j 0h"
    fmt_reset() {
      local s=$(( $1 - NOW )); [ $s -lt 0 ] && s=0
      local mins=$(( s / 60 ))
      if [ $mins -lt 60 ]; then
        printf '%dmin' "$mins"
      elif [ $mins -lt 1440 ]; then
        printf '%d.%02dh' $(( mins / 60 )) $(( mins % 60 ))
      else
        printf '%dj %dh' $(( mins / 1440 )) $(( (mins % 1440) / 60 ))
      fi
    }

    # Visible width of a string, ignoring ANSI color codes (strips ESC[...m).
    vis_width() {
      local stripped
      stripped=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')
      printf '%s' "''${#stripped}"
    }

    # Group 1 — session info; Group 2 — context + quota bars.
    G1="''${RED}🤖 $MODEL''${RESET} | ''${ORANGE}📁 $CWD''${RESET}"
    [ -n "$GIT_BRANCH" ] && G1="$G1 | ''${YELLOW}⎇ $GIT_BRANCH''${RESET}"
    G1="$G1 | ''${GREEN}📊 $TOKENS_IN_FMT/$TOKENS_OUT_FMT''${RESET}"

    G2="🧠 $CTX_BAR ''${CYAN}$CONTEXT_PCT%''${RESET}"
    [ -n "$H5_PCT" ] && G2="$G2 | ⏳ $(make_bar "$H5_PCT") ''${CYAN}$H5_PCT% · $(fmt_reset "$H5_RESET")''${RESET}"
    [ -n "$D7_PCT" ] && G2="$G2 | 📆 $(make_bar "$D7_PCT") ''${CYAN}$D7_PCT% · $(fmt_reset "$D7_RESET")''${RESET}"

    # Single line if it fits the terminal width (COLUMNS, set by Claude Code
    # v2.1.153+); otherwise wrap onto two lines. Emoji count as width 2, so add
    # a small margin. Fall back to one line when COLUMNS is unknown.
    ONE="$G1 | $G2"
    COLS=''${COLUMNS:-0}
    if [ "$COLS" -gt 0 ] && [ "$(vis_width "$ONE")" -ge $((COLS - 8)) ]; then
      OUT="$G1"$'\n'"$G2"
    else
      OUT="$ONE"
    fi

    printf '%s\n' "$OUT"
  '';
}
