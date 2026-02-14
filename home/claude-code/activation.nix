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
    mkdir -p "$HOME/.claude/skills/apex/steps"
    mkdir -p "$HOME/.claude/skills/debug/steps"
    mkdir -p "$HOME/.claude/skills/continuous-learning-v2"
    mkdir -p "$HOME/.claude/skills/generated"
    mkdir -p "$HOME/.claude/backups"
  '';

  claudeCodePerms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
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
