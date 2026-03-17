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
    mkdir -p "$HOME/.claude/skills/debug"
    mkdir -p "$HOME/.claude/skills/continuous-learning-v2"
    mkdir -p "$HOME/.claude/skills/nix-darwin"
    mkdir -p "$HOME/.claude/skills/claude-code-meta"
    mkdir -p "$HOME/.claude/skills/generated"
    mkdir -p "$HOME/.claude/backups"
    mkdir -p "$HOME/.claude/output"
    mkdir -p "$HOME/.claude/agents-memory/frontend-expert"
    mkdir -p "$HOME/.claude/agents-memory/backend-expert"
    mkdir -p "$HOME/.claude/agents-memory/architecture-expert"
    mkdir -p "$HOME/.claude/agents-memory/performance-expert"
    mkdir -p "$HOME/.claude/agents-memory/codebase-navigator"
    mkdir -p "$HOME/.claude/agents-memory/code-reviewer"
    mkdir -p "$HOME/.claude/agents-memory/quick-fix"
    mkdir -p "$HOME/.claude/agents-memory/nix-expert"
    mkdir -p "$HOME/.claude/agents-memory/git-ship"
    mkdir -p "$HOME/.claude/agents-memory/team-lead"
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

  claudeCodePerms = lib.hm.dag.entryAfter [ "fixHmGcRoot" ] ''
    set -euo pipefail
    chmod 700 "$HOME/.claude"
    chmod 700 "$HOME/.claude/agents" "$HOME/.claude/commands" "$HOME/.claude/hooks" "$HOME/.claude/skills"
    chmod +x "$HOME/.claude/hooks"/*.js 2>/dev/null || true
    chmod +x "$HOME/.claude/hooks"/*.sh 2>/dev/null || true
  '';

  # -------------------------
  # Merge settings.json (intelligent merge)
  # -------------------------
  claudeCodeSettingsMerge = lib.hm.dag.entryAfter [ "claudeCodePerms" ] ''
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
    # Nix-managed keys always win: statusLine, permissions, hooks, env
    if [ -f "$TARGET" ] && [ ! -L "$TARGET" ]; then
      TMP=$(mktemp)
      BASE_SL=$(jq -c '.statusLine' "$BASE")
      BASE_PERMS=$(jq -c '.permissions' "$BASE")
      BASE_HOOKS=$(jq -c '.hooks' "$BASE")
      BASE_ENV=$(jq -c '.env' "$BASE")
      jq -s '.[0] * .[1]' "$BASE" "$TARGET" \
        | jq --argjson sl "$BASE_SL" --argjson p "$BASE_PERMS" --argjson h "$BASE_HOOKS" --argjson e "$BASE_ENV" \
          '.statusLine = $sl | .permissions = $p | .hooks = $h | .env = $e' \
        > "$TMP" && mv "$TMP" "$TARGET"
      chmod 600 "$TARGET"
    else
      # First install: copy base
      rm -f "$TARGET"
      cp "$BASE" "$TARGET"
      chmod 600 "$TARGET"
    fi
  '';

  # -------------------------
  # Merge MCP servers into ~/.claude/.claude.json
  # -------------------------
  claudeCodeMcpMerge = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
    set -euo pipefail
    MCP_BASE="$HOME/.claude/mcp-servers-base.json"
    TARGET="$HOME/.claude/.claude.json"
    SECRET_21ST="$HOME/.config/secrets/21st-dev-api-key"

    if ! command -v jq >/dev/null 2>&1; then
      exit 0
    fi

    if [ -f "$TARGET" ] && [ -f "$MCP_BASE" ]; then
      TMP=$(mktemp)
      MCP_DATA=$(cat "$MCP_BASE")

      # Inject secrets at runtime (replace placeholders with actual keys)
      if [ -f "$SECRET_21ST" ]; then
        API_KEY=$(cat "$SECRET_21ST")
        MCP_DATA=$(echo "$MCP_DATA" | sed "s/__SECRET_21ST_DEV__/$API_KEY/g")
      fi

      jq --argjson mcp "$MCP_DATA" '.mcpServers = $mcp' "$TARGET" > "$TMP" \
        && mv "$TMP" "$TARGET"
      chmod 600 "$TARGET"
    fi
  '';

  # -------------------------
  # Install Ralph Wiggum scripts
  # -------------------------
  claudeCodeRalphWiggum = lib.hm.dag.entryAfter [ "claudeCodeSettingsMerge" ] ''
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
  '';
}
