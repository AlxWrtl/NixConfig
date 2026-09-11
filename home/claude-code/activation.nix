# Home Manager activation scripts
{
  pkgs,
  lib,
  scraplingShimPkg,
}:
{
  claudeCodeDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail
    mkdir -p "$HOME/.claude"
    mkdir -p "$HOME/.claude/agents"
    mkdir -p "$HOME/.claude/commands"
    mkdir -p "$HOME/.claude/hooks"
    mkdir -p "$HOME/.claude/plugins"
    mkdir -p "$HOME/.claude/rules"
    mkdir -p "$HOME/.claude/scripts"
    mkdir -p "$HOME/.claude/skills/apex"
    mkdir -p "$HOME/.claude/skills/apex/steps"
    mkdir -p "$HOME/.claude/skills/debug"
    mkdir -p "$HOME/.claude/skills/nix-darwin"
    mkdir -p "$HOME/.claude/skills/claude-code-meta"
    mkdir -p "$HOME/.claude/skills/testing-patterns"
    mkdir -p "$HOME/.claude/skills/codebase-audit"
    mkdir -p "$HOME/.claude/skills/caveman"
    mkdir -p "$HOME/.claude/skills/cavemem"
    mkdir -p "$HOME/.claude/skills/trello"
    mkdir -p "$HOME/.claude/backups"
    mkdir -p "$HOME/.claude/output"
    mkdir -p "$HOME/.claude/audit"
  '';

  # Remove read-only backups before linkGeneration to avoid interactive mv prompts
  claudeCodePreLink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    rm -f "$HOME/.claude/skills"/*/SKILL.md.backup
    # keybindings.json est passé sous nix : la version manuelle pré-existante est
    # déplacée en .backup par home-manager (backupFileExtension = "backup") au
    # premier rebuild. On la purge ici pour ne pas accumuler, et pour éviter le
    # "Existing file ... would be clobbered by backing up" si elle reste.
    rm -f "$HOME/.claude/keybindings.json.backup"
  '';

  # Fix HM GC root when nix-store --add-root fails under sudo
  fixHmGcRoot = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    GC_ROOT="$HOME/.local/state/home-manager/gcroots/current-home"
    CURRENT=$(readlink -f "$GC_ROOT" 2>/dev/null || true)
    if [ "$CURRENT" != "$newGenPath" ] && [ -n "$newGenPath" ]; then
      mkdir -p "$(dirname "$GC_ROOT")"
      ln -sfn "$newGenPath" "$GC_ROOT"
    fi
  '';

  # Replace nix-store symlinks in skills/ with real copies
  # Reason: schliff doctor does realpath() + relative_to(scan_root)
  # and silently skips symlinks that resolve outside ~/.claude/skills/
  claudeCodeDesymlinkSkills = lib.hm.dag.entryAfter [ "fixHmGcRoot" ] ''
    set -euo pipefail
    for f in "$HOME/.claude/skills"/*/SKILL.md; do
      # Remove stale backups (read-only from nix store) to avoid mv prompts
      rm -f "''${f}.backup"
      [ -L "$f" ] || continue
      target=$(readlink "$f")
      cp "$target" "$f.tmp"
      rm "$f"
      mv "$f.tmp" "$f"
      chmod 644 "$f"
    done
  '';

  claudeCodePerms = lib.hm.dag.entryAfter [ "claudeCodeDesymlinkSkills" ] ''
    set -euo pipefail
    chmod 700 "$HOME/.claude"
    chmod 700 "$HOME/.claude/agents" "$HOME/.claude/commands" "$HOME/.claude/hooks" "$HOME/.claude/skills"
  '';

  # -------------------------
  # Merge settings.json (intelligent merge)
  # -------------------------
  # Subshell-wrapped: see claudeCodeDevBrowser note — a bare `exit 0` would
  # abort the whole activation chain.
  claudeCodeSettingsMerge = lib.hm.dag.entryAfter [ "claudeCodePerms" ] ''
    (
      set -euo pipefail
      BASE="$HOME/.claude/settings-base.json"
      TARGET="$HOME/.claude/settings.json"

      # If jq not available, fallback to copy
      if ! command -v jq >/dev/null 2>&1; then
        if [ ! -f "$TARGET" ]; then
          cp "$BASE" "$TARGET"
          chmod 600 "$TARGET"
        fi
        exit 0
      fi

      # Intelligent merge: base provides defaults, existing preserves user changes
      # Nix-managed keys always win: statusLine, permissions, hooks, env, sandbox,
      # effortLevel, alwaysThinkingEnabled, skillOverrides. NEVER force .model:
      # /model and /fast are deliberate session choices that must survive rebuilds.
      # `.skillOverrides` est dans la liste par nécessité : sans force-override,
      # il n'arriverait que par le deep merge `.[0] * .[1]`, où le live gagne sur
      # toute clé qu'il détient déjà — la valeur nix serait ignorée en silence dès
      # la première écriture par autre chose. Ce repo s'est déjà fait avoir par
      # exactement cette forme sur `.model`.
      # Ce que le force-override NE règle PAS : `skillOverrides` est fusionné par
      # objet entre scopes, le scope projet battant le scope utilisateur, et un
      # basculement manuel dans le sélecteur `/skills` écrit
      # `.claude/settings.local.json` — fichier IGNORÉ PAR GIT ici
      # (`.gitignore:2:.claude/`, tout le répertoire). Une entrée en scope local
      # bat donc le scope utilisateur nix-managé, force-override compris, et ne
      # produit AUCUN diff : `git status` reste propre, la dérive contre la
      # source nix est silencieuse. C'est pire que tracké, pas plus doux : rien
      # ne la fait remonter. Connu, accepté, hors périmètre.
      # `.voice` n'est PAS force-overridden : le deep merge `.[0] * .[1]` est
      # récursif, donc toute sous-clé présente dans la base et absente du live
      # (ex. autoSubmit) est injectée, tandis qu'un `mode` changé en session
      # survit — même logique que .model.
      if [ -f "$TARGET" ] && [ ! -L "$TARGET" ]; then
        TMP=$(mktemp)
        BASE_SL=$(jq -c '.statusLine' "$BASE")
        BASE_PERMS=$(jq -c '.permissions' "$BASE")
        BASE_HOOKS=$(jq -c '.hooks' "$BASE")
        BASE_ENV=$(jq -c '.env' "$BASE")
        BASE_SANDBOX=$(jq -c '.sandbox' "$BASE")
        BASE_EFFORT=$(jq -c '.effortLevel' "$BASE")
        BASE_THINK=$(jq -c '.alwaysThinkingEnabled' "$BASE")
        BASE_SKILLOV=$(jq -c '.skillOverrides' "$BASE")
        jq -s '.[0] * .[1]' "$BASE" "$TARGET" \
          | jq --argjson sl "$BASE_SL" --argjson p "$BASE_PERMS" --argjson h "$BASE_HOOKS" --argjson e "$BASE_ENV" --argjson sb "$BASE_SANDBOX" --argjson ef "$BASE_EFFORT" --argjson th "$BASE_THINK" --argjson so "$BASE_SKILLOV" \
            '.statusLine = $sl | .permissions = $p | .hooks = $h | .env = $e | .sandbox = $sb | .effortLevel = $ef | .alwaysThinkingEnabled = $th | .skillOverrides = $so
             # legacy: `voiceEnabled` (clé plate) est encore lue par le binaire
             # mais remplacée par le bloc `voice`. Supprimée du live pour ne pas
             # garder deux sources de vérité qui peuvent diverger.
             | del(.voiceEnabled)' \
          > "$TMP" && mv "$TMP" "$TARGET"
        chmod 600 "$TARGET"
      else
        # First install: copy base
        rm -f "$TARGET"
        cp "$BASE" "$TARGET"
        chmod 600 "$TARGET"
      fi
    ) || true
  '';

  # -------------------------
  # Merge MCP servers (user scope) into ~/.claude.json
  # -------------------------
  # IMPORTANT: Claude Code (>=2.x) reads user-scope MCP servers from
  # ~/.claude.json (HOME root), NOT ~/.claude/.claude.json. Writing to the
  # latter is silently ignored (`claude mcp list` shows nothing). Verified
  # with `claude mcp add --scope user` → "File modified: ~/.claude.json".
  # The jq `.mcpServers = $mcp` assignment replaces only that key and
  # preserves every other key in the (large) root config file.
  # Subshell-wrapped: see claudeCodeDevBrowser note — a bare `exit 0` would
  # abort the whole activation chain. (This entry sits LAST in DAG order, so
  # it was the silent victim: claudeCodeDevBrowser's `exit 0` killed the run
  # before this ever executed.)
  claudeCodeMcpMerge = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    (
      set -euo pipefail
      MCP_BASE="$HOME/.claude/mcp-servers-base.json"
      TARGET="$HOME/.claude.json"

      command -v jq >/dev/null 2>&1 || exit 0
      [ -f "$MCP_BASE" ] || exit 0

      # Create a minimal root config if Claude Code hasn't written one yet.
      [ -f "$TARGET" ] || echo '{}' > "$TARGET"

      # Temp file next to TARGET (same filesystem → atomic `mv`).
      TMP="$TARGET.mcp-merge.tmp"
      trap 'rm -f "$TMP"' EXIT
      MCP_DATA=$(cat "$MCP_BASE")

      # No runtime secret injection: since `magic` was removed (2026-08-16) no
      # MCP server carries a `__SECRET_*__` placeholder. Restore the jq `walk`
      # step here if one ever does again.

      jq --argjson mcp "$MCP_DATA" '.mcpServers = $mcp' "$TARGET" > "$TMP" \
        && mv "$TMP" "$TARGET"
      chmod 600 "$TARGET"
      echo "✓ MCP merge → $TARGET ($(jq -c '.mcpServers | keys' "$TARGET"))"
    ) || true
  '';

  # -------------------------
  # Generate config-snapshot.json dynamically from installed files
  # -------------------------
  claudeCodeConfigSnapshot = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    set -euo pipefail
    SNAPSHOT="$HOME/.claude/config-snapshot.json"
    GEN_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Discover installed components from actual files
    AGENTS=$(ls "$HOME/.claude/agents/"*.md 2>/dev/null | xargs -I{} basename {} .md | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)
    SKILLS=$(ls -d "$HOME/.claude/skills/"*/SKILL.md 2>/dev/null | xargs -I{} dirname {} | xargs -I{} basename {} | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)
    COMMANDS=$(ls "$HOME/.claude/commands/"*.md 2>/dev/null | xargs -I{} basename {} .md | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)
    HOOKS=$(ls "$HOME/.claude/hooks/"*.{js,sh} 2>/dev/null | xargs -I{} basename {} | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)

    ${pkgs.jq}/bin/jq -n \
      --arg date "$GEN_DATE" \
      --argjson agents "$AGENTS" \
      --argjson skills "$SKILLS" \
      --argjson commands "$COMMANDS" \
      --argjson hooks "$HOOKS" \
      '{
        generatedAt: $date,
        agents: $agents,
        skills: $skills,
        commands: $commands,
        hooks: $hooks
      }' > "$SNAPSHOT"
    chmod 600 "$SNAPSHOT"
  '';

  # -------------------------
  # Install Ralph Wiggum scripts
  # -------------------------
  # Subshell-wrapped: see claudeCodeDevBrowser note — a bare `exit 0` would
  # abort the whole activation chain.
  claudeCodeRalphWiggum = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    (
      RALPH_DIR="$HOME/.claude/plugins/ralph-wiggum"
      INSTALL_MARKER="$RALPH_DIR/.installed"

      # Skip if already installed (marker exists)
      if [ -f "$INSTALL_MARKER" ]; then
        # Update symlinks for scripts only
        if [ -d "$RALPH_DIR" ]; then
          mkdir -p "$HOME/.claude/scripts"
          ln -sf "$RALPH_DIR/scripts/setup-ralph-loop.sh" "$HOME/.claude/scripts/setup-ralph-loop.sh"
          chmod +x "$HOME/.claude/scripts/setup-ralph-loop.sh"
        fi
        exit 0
      fi

      echo "Installing Ralph Wiggum scripts..."
      export PATH="${pkgs.curl}/bin:${pkgs.unzip}/bin:$PATH"

      # Download plugin from GitHub
      mkdir -p "$RALPH_DIR"
      TMP_DIR=$(mktemp -d)

      cd "$TMP_DIR"
      curl -sL https://github.com/anthropics/claude-code/archive/refs/heads/main.zip -o repo.zip
      unzip -q repo.zip

      # Copy ALL files including hidden ones
      shopt -s dotglob
      cp -R claude-code-main/plugins/ralph-wiggum/* "$RALPH_DIR/"

      # Create install marker
      touch "$INSTALL_MARKER"

      # Symlink scripts only (commands managed by nix)
      mkdir -p "$HOME/.claude/scripts"
      ln -sf "$RALPH_DIR/scripts/setup-ralph-loop.sh" "$HOME/.claude/scripts/setup-ralph-loop.sh"
      chmod +x "$HOME/.claude/scripts/setup-ralph-loop.sh"

      # Cleanup
      cd - > /dev/null
      rm -rf "$TMP_DIR"

      echo "✓ Ralph Wiggum scripts installed"
    ) || true
  '';

  # -------------------------
  # Install dev-browser CLI (once)
  # -------------------------
  # NOTE: the body runs inside a ( … ) subshell. Home Manager concatenates all
  # activation entries into ONE shell with `set -eu`, so a bare `exit 0` here
  # would terminate the ENTIRE activation and silently skip every later DAG
  # entry (this is exactly what broke claudeCodeMcpMerge for ~2 months). The
  # subshell scopes `exit` so only this block returns, not the whole run.
  claudeCodeDevBrowser = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    (
      MARKER="$HOME/.claude/.dev-browser-installed"

      # Skip if already installed
      if [ -f "$MARKER" ]; then
        exit 0
      fi

      echo "Installing dev-browser..."
      export PATH="${pkgs.nodejs_22}/bin:$PATH"

      # npm global prefix → ~/.npm-global (nix store is immutable)
      NPM_GLOBAL="$HOME/.npm-global"
      mkdir -p "$NPM_GLOBAL"
      export npm_config_prefix="$NPM_GLOBAL"
      export PATH="$NPM_GLOBAL/bin:$PATH"

      npm install -g dev-browser@0.2.7 2>&1 || { echo "dev-browser install failed"; exit 0; }
      "$NPM_GLOBAL/bin/dev-browser" install 2>&1 || { echo "dev-browser playwright install failed"; exit 0; }

      touch "$MARKER"
      echo "✓ dev-browser installed"
    ) || true
  '';

  # -------------------------
  # Install enquire-mcp CLI globally + pre-cache embedding model (idempotent)
  # -------------------------
  # Global install (not npx -y) so the ~120 MB ONNX model cache lives in a stable
  # node_modules and isn't re-downloaded on every server restart. The settings.nix
  # `enquire` MCP entry points at $HOME/.npm-global/bin/enquire-mcp.
  #
  # The --use-hnsw flag needs the optional NATIVE dep `hnswlib-node` (compiled
  # build/Release/addon.node); without it HNSW silently falls back to brute-force
  # ("HNSW build failed; falling back ...").
  #
  # NON-DESTRUCTIVE by design: this runs under `sudo darwin-rebuild`, where the
  # network is restricted (HuggingFace / npm prebuild fetches fail). A blind
  # `npm install -g` would REMOVE the working install and then fail to recompile
  # hnswlib offline, leaving HNSW broken. So we only install pieces that are
  # actually MISSING, and only stamp the marker once every piece is present —
  # a half-done state simply retries on the next rebuild (or run the steps by
  # hand outside sudo, where the network works).
  # Subshell-wrapped: a bare `exit 0` would abort the whole activation chain.
  claudeCodeEnquire = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    (
      ENQUIRE_VERSION="3.9.1"
      MARKER="$HOME/.claude/.enquire-installed-$ENQUIRE_VERSION-hnsw"

      # Already fully set up → nothing to do.
      [ -f "$MARKER" ] && exit 0

      export PATH="${pkgs.nodejs_22}/bin:$PATH"
      NPM_GLOBAL="$HOME/.npm-global"
      mkdir -p "$NPM_GLOBAL"
      export npm_config_prefix="$NPM_GLOBAL"
      export PATH="$NPM_GLOBAL/bin:$PATH"

      BIN="$NPM_GLOBAL/bin/enquire-mcp"
      PKG_DIR="$NPM_GLOBAL/lib/node_modules/@oomkapwn/enquire-mcp"
      ADDON="$PKG_DIR/node_modules/hnswlib-node/build/Release/addon.node"
      MODEL_CACHE="$PKG_DIR/node_modules/@huggingface/transformers/.cache/Xenova"

      # 1. Install the CLI only if the binary is missing / wrong version.
      if [ "$("$BIN" --version 2>/dev/null)" != "$ENQUIRE_VERSION" ]; then
        echo "Installing enquire-mcp@$ENQUIRE_VERSION (global, with HNSW)..."
        npm install -g --include=optional "@oomkapwn/enquire-mcp@$ENQUIRE_VERSION" 2>&1 \
          || { echo "enquire-mcp install failed (will retry next rebuild)"; exit 0; }
      fi

      # 2. Compile the HNSW native addon only if absent.
      if [ ! -e "$ADDON" ]; then
        ( cd "$PKG_DIR" && npm install hnswlib-node@^3 --include=optional 2>&1 ) \
          || echo "hnswlib-node install failed (HNSW falls back to brute-force; retry outside sudo)"
      fi

      # 3. Pre-download the embedding model only if not already cached.
      if [ ! -d "$MODEL_CACHE/paraphrase-multilingual-MiniLM-L12-v2" ]; then
        "$BIN" install-model multilingual 2>&1 \
          || echo "model pre-download failed (lazy-loads on first search; retry outside sudo)"
      fi

      # Stamp the marker ONLY when every piece is in place; otherwise retry next time.
      if [ -x "$BIN" ] && [ -e "$ADDON" ] \
         && [ -d "$MODEL_CACHE/paraphrase-multilingual-MiniLM-L12-v2" ]; then
        rm -f "$HOME/.claude"/.enquire-installed-* 2>/dev/null || true
        touch "$MARKER"
        echo "✓ enquire-mcp@$ENQUIRE_VERSION installed (HNSW ready)"
      else
        echo "⚠ enquire-mcp not fully set up yet (binary/HNSW/model missing) — will retry"
      fi
    ) || true
  '';

  # -------------------------
  # Install graphify (uv tool) — knowledge-graph MCP server (idempotent)
  # -------------------------
  # `uv tool install` puts graphify + graphify-mcp in ~/.local/bin (added to
  # home.sessionPath). The settings.nix `graphify` MCP entry points at
  # $HOME/.local/bin/graphify-mcp.
  #
  # The extras are MANDATORY, not cosmetic (each verified by running the binary):
  #   [mcp]    → the `mcp` module. WITHOUT IT THE SERVER NEVER STARTS: serve.py
  #              dies at `from mcp.server.stdio import stdio_server`
  #              (ModuleNotFoundError) and `claude mcp list` reports
  #              "graphify: ✘ Failed to connect — CONNECTION_CLOSED".
  #              [ollama] does NOT provide it — it is a separate extra.
  #   [leiden] → community detection, i.e. the actual functional deliverable.
  #   [ollama] → the `openai` module, kept to preserve the local-backend option.
  #
  # MARKER NAMING: the marker encodes the version AND the extra set. A
  # version-only marker (the original bug) makes this block skip on a machine
  # that already installed the same version with a narrower extra set, so the
  # fix could never apply. Same reason claudeCodeEnquire suffixes its marker
  # with `-hnsw`. The `.graphify-installed-*` wildcard cleanup below removes
  # the stale un-suffixed marker too.
  #
  # NON-DESTRUCTIVE by design, same rule as claudeCodeEnquire above: this runs
  # under `sudo darwin-rebuild`, where the network is restricted. `uv tool
  # install --force` would DELETE the working install and then fail to re-fetch
  # the wheels offline, leaving the user with no graphify at all. So: never
  # --force, install only when the binary is genuinely missing or on the wrong
  # version, and stamp the marker only once everything checks out — a partial
  # state just retries on the next rebuild (or fix it by hand outside sudo,
  # where the network works).
  # Subshell-wrapped: a bare `exit 0` would abort the whole activation chain.
  claudeCodeGraphify = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    (
      GRAPHIFY_VERSION="0.9.48"
      GRAPHIFY_EXTRAS="mcp,ollama,leiden"
      MARKER="$HOME/.claude/.graphify-installed-$GRAPHIFY_VERSION-mcp"

      # Already fully set up → nothing to do.
      [ -f "$MARKER" ] && exit 0

      export PATH="${pkgs.uv}/bin:$HOME/.local/bin:$PATH"

      BIN="$HOME/.local/bin/graphify"
      MCP_BIN="$HOME/.local/bin/graphify-mcp"
      TOOL_DIR="$HOME/.local/share/uv/tools/graphifyy"

      # `graphify --version` prints "graphify <semver>" → keep the last field.
      CURRENT_RAW="$("$BIN" --version 2>/dev/null || true)"
      CURRENT="''${CURRENT_RAW##* }"

      # 1. Install only if the binary is missing / wrong version. No --force.
      if [ "$CURRENT" != "$GRAPHIFY_VERSION" ]; then
        echo "Installing graphifyy[$GRAPHIFY_EXTRAS]==$GRAPHIFY_VERSION (uv tool)..."
        uv tool install "graphifyy[$GRAPHIFY_EXTRAS]==$GRAPHIFY_VERSION" 2>&1 \
          || { echo "graphify install failed (will retry next rebuild; run outside sudo for network)"; exit 0; }
        CURRENT_RAW="$("$BIN" --version 2>/dev/null || true)"
        CURRENT="''${CURRENT_RAW##* }"
      fi

      # 2. Probe the extras offline in the tool venv, naming the exact culprit.
      #    [mcp] → `mcp` (its absence is what broke production: the server
      #    aborted at import time and Claude saw CONNECTION_CLOSED).
      #    [ollama] → `openai`.  [leiden] → `graspologic` (checked on the real
      #    install: the extra resolves to graspologic, not leidenalg/igraph).
      EXTRAS_OK=1
      MISSING_EXTRAS=""
      if ! ls -d "$TOOL_DIR"/lib/python*/site-packages/mcp >/dev/null 2>&1; then
        EXTRAS_OK=0
        MISSING_EXTRAS="$MISSING_EXTRAS [mcp](module 'mcp')"
      fi
      if ! ls -d "$TOOL_DIR"/lib/python*/site-packages/openai >/dev/null 2>&1; then
        EXTRAS_OK=0
        MISSING_EXTRAS="$MISSING_EXTRAS [ollama](module 'openai')"
      fi
      if ! ls -d "$TOOL_DIR"/lib/python*/site-packages/graspologic >/dev/null 2>&1; then
        EXTRAS_OK=0
        MISSING_EXTRAS="$MISSING_EXTRAS [leiden](module 'graspologic')"
      fi
      if [ "$EXTRAS_OK" = "0" ]; then
        echo "⚠ graphify missing extra(s):$MISSING_EXTRAS — run outside sudo:"
        echo "    uv tool install --force \"graphifyy[$GRAPHIFY_EXTRAS]==$GRAPHIFY_VERSION\""
      fi

      # Stamp the marker ONLY when every piece is in place; otherwise retry next time.
      if [ -x "$BIN" ] && [ -x "$MCP_BIN" ] \
         && [ "$CURRENT" = "$GRAPHIFY_VERSION" ] && [ "$EXTRAS_OK" = "1" ]; then
        # Wildcard: also erases the legacy un-suffixed marker from the
        # version-only naming scheme.
        rm -f "$HOME/.claude"/.graphify-installed-* 2>/dev/null || true
        touch "$MARKER"
        echo "✓ graphify@$GRAPHIFY_VERSION installed (extras: $GRAPHIFY_EXTRAS)"
      else
        echo "⚠ graphify not fully set up yet (binary/version/extras) — will retry"
      fi
    ) || true
  '';

  # Scrapling — web scraping CLI, pinned. Same shape as claudeCodeGraphify:
  # subshell-wrapped (`( … ) || true`) because home-manager concatenates every
  # activation entry into ONE `set -eu` shell, so a bare `exit` here would kill
  # every later DAG entry.
  # `[shell]`, not `[all]`: `[all]` = `[ai,shell]` and `ai`'s only unique dep is
  # `mcp>=2.0.0` — dead weight, the MCP server is deliberately not installed.
  # `[shell]` already carries the fetchers, markdownify (required for .md
  # output) and IPython.
  claudeCodeScrapling = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    (
      SCRAPLING_VERSION="0.4.15"
      SCRAPLING_EXTRAS="shell"
      # Marker carries the extras AND the browser step, not just the version:
      # a version-only marker turns any later capability fix into a no-op.
      MARKER="$HOME/.claude/.scrapling-installed-$SCRAPLING_VERSION-shell-browsers"

      # Drop the MCP entrypoint. BEFORE the marker check, on purpose.
      # `uv tool install` creates EVERY [project.scripts] entry regardless of
      # extras, so `scrapling-mcp` lands on PATH even with only [shell] —
      # verified after the first rebuild: the binary existed and `--help`
      # worked while the `mcp` package was absent from the tool venv, so the
      # server would die at import. This install is deliberately MCP-less.
      # Placed AFTER the guard first, this line never ran: the marker was
      # already stamped, so the entry exited above it and the fix was inert.
      # Caught by checking the live binary rather than trusting the diff.
      # Cheap and idempotent, so it belongs before the guard, where it also
      # self-heals if uv recreates the entrypoint outside a rebuild.
      rm -f "$HOME/.local/bin/scrapling-mcp" 2>/dev/null || true

      # Put the SHIM on PATH in place of uv's own symlink, so that every
      # `scrapling extract <sub>` gets --ai-targeted no matter how the call is
      # written. BEFORE the marker guard, and unconditional, for two reasons:
      # `uv tool install` recreates its symlink on every reinstall and would
      # silently take the name back, and the marker is stamped on first success
      # so anything below the guard never runs again (that is exactly how the
      # scrapling-mcp removal above sat inert for a whole rebuild).
      # ~/.local/bin is position 2 in PATH, ahead of the nix profile dirs, which
      # is why home.packages cannot be used for this.
      mkdir -p "$HOME/.local/bin"
      ln -sfn "${scraplingShimPkg}/bin/scrapling" "$HOME/.local/bin/scrapling"

      # Already fully set up → nothing to do.
      [ -f "$MARKER" ] && exit 0

      export PATH="${pkgs.uv}/bin:$HOME/.local/bin:$PATH"

      # Probe the REAL binary, never the shim: the shim refuses to run when the
      # real one is missing, so probing through it would report "no version" for
      # two different reasons and the retry logic could not tell them apart.
      BIN="$HOME/.local/share/uv/tools/scrapling/bin/scrapling"

      # The exact shape of `scrapling --version` is not contractual, so derive
      # the version defensively: keep the last whitespace-separated field, then
      # require it to look like a version. No probe → "not ready", never stamp.
      probe_version() {
        RAW="$("$BIN" --version 2>/dev/null || true)"
        CURRENT="''${RAW##* }"
        case "$CURRENT" in
          [0-9]*.[0-9]*) : ;;
          *) CURRENT="" ;;
        esac
      }

      # 1. Install only if the binary is missing / wrong version. No --force.
      probe_version
      if [ "$CURRENT" != "$SCRAPLING_VERSION" ]; then
        echo "Installing scrapling[$SCRAPLING_EXTRAS]==$SCRAPLING_VERSION (uv tool)..."
        uv tool install "scrapling[$SCRAPLING_EXTRAS]==$SCRAPLING_VERSION" 2>&1 \
          || { echo "scrapling install failed (will retry next rebuild; run outside sudo for network)"; exit 0; }
        # uv just recreated its own ~/.local/bin/scrapling symlink and took the
        # name back from the shim. Re-link, or the guarantee lasts exactly until
        # the first install.
        rm -f "$HOME/.local/bin/scrapling-mcp" 2>/dev/null || true
        ln -sfn "${scraplingShimPkg}/bin/scrapling" "$HOME/.local/bin/scrapling"
        probe_version
      fi

      # 2. Fetch the browser stack (Playwright/Camoufox + deps). This is a heavy,
      #    network-bound download and it commonly fails under `sudo
      #    darwin-rebuild` where the network is unavailable to the activation
      #    shell — non-blocking by construction, exactly like graphify's install.
      BROWSERS_OK=0
      if [ -x "$BIN" ]; then
        if "$BIN" install 2>&1; then
          BROWSERS_OK=1
        else
          echo "⚠ scrapling install (browsers) failed — run outside sudo:"
          echo "    scrapling install"
        fi
      fi

      # Stamp the marker ONLY when binary + version + browsers + SHIM all check
      # out; a partial state just retries on the next rebuild. The shim is part
      # of the condition on purpose: stamping while ~/.local/bin/scrapling still
      # points at uv's binary would record "done" for an install whose flag
      # guarantee is not actually in place.
      SHIM_OK=0
      [ "$(readlink "$HOME/.local/bin/scrapling" 2>/dev/null)" = "${scraplingShimPkg}/bin/scrapling" ] && SHIM_OK=1
      if [ -x "$BIN" ] && [ "$CURRENT" = "$SCRAPLING_VERSION" ] && [ "$BROWSERS_OK" = "1" ] && [ "$SHIM_OK" = "1" ]; then
        rm -f "$HOME/.claude"/.scrapling-installed-* 2>/dev/null || true
        touch "$MARKER"
        echo "✓ scrapling@$SCRAPLING_VERSION installed (extras: $SCRAPLING_EXTRAS, browsers ready, shim on PATH)"
      else
        echo "⚠ scrapling not fully set up yet (binary/version/browsers/shim) — will retry"
      fi
    ) || true
  '';
}
