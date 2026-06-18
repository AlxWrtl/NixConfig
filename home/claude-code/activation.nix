# Home Manager activation scripts
{ pkgs, lib }:
{
  claudeCodeDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail
    mkdir -p "$HOME/.claude"
    mkdir -p "$HOME/.claude/agents"
    mkdir -p "$HOME/.claude/commands"
    mkdir -p "$HOME/.claude/hooks"
    mkdir -p "$HOME/.claude/plugins"
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
      # Nix-managed keys always win: statusLine, permissions, hooks, env, sandbox
      if [ -f "$TARGET" ] && [ ! -L "$TARGET" ]; then
        TMP=$(mktemp)
        BASE_SL=$(jq -c '.statusLine' "$BASE")
        BASE_PERMS=$(jq -c '.permissions' "$BASE")
        BASE_HOOKS=$(jq -c '.hooks' "$BASE")
        BASE_ENV=$(jq -c '.env' "$BASE")
        BASE_SANDBOX=$(jq -c '.sandbox' "$BASE")
        jq -s '.[0] * .[1]' "$BASE" "$TARGET" \
          | jq --argjson sl "$BASE_SL" --argjson p "$BASE_PERMS" --argjson h "$BASE_HOOKS" --argjson e "$BASE_ENV" --argjson sb "$BASE_SANDBOX" \
            '.statusLine = $sl | .permissions = $p | .hooks = $h | .env = $e | .sandbox = $sb' \
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
      SECRET_21ST="$HOME/.config/secrets/21st-dev-api-key"

      command -v jq >/dev/null 2>&1 || exit 0
      [ -f "$MCP_BASE" ] || exit 0

      # Create a minimal root config if Claude Code hasn't written one yet.
      [ -f "$TARGET" ] || echo '{}' > "$TARGET"

      # Temp file next to TARGET (same filesystem → atomic `mv`).
      TMP="$TARGET.mcp-merge.tmp"
      trap 'rm -f "$TMP"' EXIT
      MCP_DATA=$(cat "$MCP_BASE")

      # Inject secrets at runtime via jq (safe for special chars in keys)
      if [ -f "$SECRET_21ST" ]; then
        API_KEY=$(cat "$SECRET_21ST")
        MCP_DATA=$(echo "$MCP_DATA" | jq --arg key "$API_KEY" 'walk(if . == "__SECRET_21ST_DEV__" then $key else . end)')
      fi

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
  # Install enquire-mcp CLI globally + pre-cache embedding model (once)
  # -------------------------
  # Global install (not npx -y) so the ~120 MB ONNX model cache lives in a stable
  # node_modules and isn't re-downloaded on every server restart. The settings.nix
  # `enquire` MCP entry points at $HOME/.npm-global/bin/enquire-mcp.
  # Bump ENQUIRE_VERSION to upgrade; delete the marker to force reinstall.
  # Subshell-wrapped: a bare `exit 0` would abort the whole activation chain.
  claudeCodeEnquire = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    (
      ENQUIRE_VERSION="3.9.1"
      MARKER="$HOME/.claude/.enquire-installed-$ENQUIRE_VERSION"

      # Skip if this exact version already installed
      if [ -f "$MARKER" ]; then
        exit 0
      fi

      echo "Installing enquire-mcp@$ENQUIRE_VERSION (global)..."
      export PATH="${pkgs.nodejs_22}/bin:$PATH"

      NPM_GLOBAL="$HOME/.npm-global"
      mkdir -p "$NPM_GLOBAL"
      export npm_config_prefix="$NPM_GLOBAL"
      export PATH="$NPM_GLOBAL/bin:$PATH"

      npm install -g "@oomkapwn/enquire-mcp@$ENQUIRE_VERSION" 2>&1 \
        || { echo "enquire-mcp install failed"; exit 0; }

      # Pre-download the multilingual embedding model so the first search
      # doesn't block on a 120 MB Hugging Face fetch.
      "$NPM_GLOBAL/bin/enquire-mcp" install-model multilingual 2>&1 \
        || { echo "enquire-mcp model pre-download failed (will lazy-load)"; }

      # Drop stale markers from older versions
      rm -f "$HOME/.claude"/.enquire-installed-* 2>/dev/null || true
      touch "$MARKER"
      echo "✓ enquire-mcp@$ENQUIRE_VERSION installed"
    ) || true
  '';
}
