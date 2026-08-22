# Claude Code settings and statusline script
{ homeDirectory }:
let
  # Absolute path to node — /bin/sh can't find nix-installed node in PATH
  node = "/run/current-system/sw/bin/node";

  # Obsidian vault — shared constant, reusable by other modules.
  # Real on-disk location (NOT the iCloud~md~obsidian mirror path).
  alxVaultPath = "/Users/alx/Documents/AlxVault";
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

    # Défaut déclaratif : Opus 5 = workhorse full-loop (1M natif, pas de suffixe
    # [1m]). Fable n'est plus coordinateur — il est spawné en vérificateur
    # read-only sur diff haut-enjeu seulement, voir apex ORCHESTRATION.md.
    # NON force-overridden dans la 2e passe jq, MAIS cette valeur re-seed le
    # live quand la clé y est absente (le CLI la retire quand /model écrit son
    # choix dans ~/.claude.json) — d'où l'obligation de la garder alignée sur
    # le défaut voulu, sinon le rebuild fait régresser le modèle.
    model = "claude-opus-5";
    # Chaîne de repli si Opus 5 est indisponible/surchargé : essayée dans
    # l'ordre, uniquement en cas d'échec de requête. N'affecte pas le défaut.
    fallbackModel = [
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

    includeGitInstructions = false;

    sandbox = {
      enabled = true;
      # Commands that run OUTSIDE the sandbox → normal permission prompt (ask)
      # instead of being hard-blocked with "operation not permitted".
      # Lets Claude run `sudo darwin-rebuild ...` with a confirmation box,
      # so the user no longer has to retype it with a leading `!`.
      excludedCommands = [
        "sudo *"
        "darwin-rebuild *"
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
          "**/.env"
          "**/.env.*"
          "**/secrets"
        ];
        # Ré-ouvre la clé PUBLIQUE, que le denyRead sur ~/.ssh emportait aussi.
        # git signe les commits en SSH (`gpg.format=ssh`, signingkey
        # ~/.ssh/id_ed25519.pub) : sans ça, TOUT commit échoue dans le sandbox
        # avec « Couldn't load public key ». Régression introduite par la PR
        # #101 et constatée au premier commit suivant. Une clé publique est
        # publique — la privée, elle, reste refusée.
        allowRead = [ "${homeDirectory}/.ssh/id_ed25519.pub" ];
        # graphify-reindex (fired in BACKGROUND by APEX steps 01b/09b) writes
        # the knowledge graph to ~/GraphVault — outside the session cwd, so the
        # default sandbox write-set (cwd + tmp) would kill it with "operation
        # not permitted" and force a dangerouslyDisableSandbox box at the end
        # of every `-n` session. allowWrite EXTENDS the writable set; it never
        # re-opens a denyWrite path. The vault itself stays Bash-unwritable
        # (outside cwd): session notes go through the Write tool, as before.
        allowWrite = [ "${homeDirectory}/GraphVault" ];
      };
      network = {
        # All domains allowed (web analysis, design, docs, APIs)
        allowedDomains = [ "*" ];
      };
    };

    permissions = {
      defaultMode = "acceptEdits";
      # `ask` forces a confirmation box for matching commands, overriding
      # skipDangerousModePermissionPrompt and acceptEdits. Precedence: deny > ask > allow.
      # Box only for sudo (sudo git, sudo darwin-rebuild, …). A bare "Bash" rule
      # here fires on every out-of-sandbox command → box spammée, don't add it.
      ask = [
        "Bash(sudo *)"
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
        # Knowledge-graph refresh wrapper (no args; writes only to ~/GraphVault
        # — see sandbox allowWrite). Fired in background by APEX steps 01b/09b.
        "Bash(graphify-reindex)"
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
        # WebFetch allowlist
        "WebFetch(domain:github.com)"
        "WebFetch(domain:raw.githubusercontent.com)"
        "WebFetch(domain:nix-darwin.github.io)"
        "WebFetch(domain:nixos.org)"
        "WebFetch(domain:search.nixos.org)"
        "WebFetch(domain:*.npmjs.org)"
        "WebFetch(domain:docs.anthropic.com)"
        "WebFetch(domain:code.claude.com)"
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
        # Note: merge/push to master/main is NOT hard-denied — the block-main-bash
        # hook turns those into a confirmation box (ask) so the user approves
        # in-place. commit/rebase on master stay denied by that hook.
        "Bash(git reset --hard *)"
        "Bash(git clean -fdx *)"
        "Bash(git clean -fxd *)"
        "Bash(git checkout -- .)"
        # Filesystem destructive
        "Bash(rm -rf /*)"
        # Note: `sudo` intentionally NOT denied — Claude may invoke it but each
        # call requires interactive confirmation (not in allow-list either).
        "Bash(chmod 777 *)"
        # Secrets — absolute paths via Nix interpolation
        "Read(${homeDirectory}/.ssh/**)"
        "Read(${homeDirectory}/.aws/**)"
        "Read(${homeDirectory}/.gnupg/**)"
        "Read(${homeDirectory}/.config/secrets/**)"
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
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              # rtk >= 0.43: hook natif du binaire (remplace l'ancien script
              # rtk-rewrite.sh). Chemin absolu — les hooks tournent sous /bin/sh
              # sans le PATH homebrew.
              command = "/opt/homebrew/bin/rtk hook claude";
              timeout = 5;
            }
            {
              type = "command";
              # Réécrit les commandes couvertes par filters.toml (nix) que le
              # hook natif ignore — listes disjointes, pas de double-wrap.
              command = "bash ~/.claude/hooks/rtk-nix-rewrite.sh";
              timeout = 5;
            }
          ];
        }
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
          # A typed flag is a floor, never a ceiling: -e is stripped when the
          # task text carries a risk signal, missing depth flags are added.
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

  # MCP servers merged into ~/.claude/.claude.json by activation script
  # Secrets (API keys) are injected at runtime by claudeCodeMcpMerge, not here
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
      CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."' | xargs basename)
      TOKENS_IN=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0')
      TOKENS_OUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0')
      CONTEXT_PCT=$(echo "$INPUT" | jq -r '(.context_window.used_percentage // 0) | round')

      WORKSPACE_DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."')
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
