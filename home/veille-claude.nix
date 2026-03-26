# ~/.config/nix-darwin/home/veille-claude.nix
# Veille technologique — triggers GitHub Actions + pulls results locally
{ pkgs, lib, ... }:

let
  veille-claude = pkgs.writeShellScriptBin "veille-claude" ''
    set -euo pipefail

    MODE="''${1:-daily}"
    OBSIDIAN_FLAG="''${2:-}"
    REPO="AlxWrtl/alx-claude-radar"
    TODAY_ISO=$(date '+%Y-%m-%d')
    REPORTS_DIR="''${VEILLE_REPORTS_DIR:-$HOME/veille}"
    OBSIDIAN_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/AlxVault/04-Resources/veille-claude"

    mkdir -p "$REPORTS_DIR"

    echo "veille-claude [$MODE] -- $(date '+%d %B %Y')"

    case "$MODE" in
      daily)
        WORKFLOW="daily-digest.yml"
        ;;
      compare)
        WORKFLOW="config-compare.yml"
        ;;
      full)
        echo "Triggering monthly digest..."
        gh workflow run monthly-digest.yml --repo "$REPO"
        echo "Triggering config comparison..."
        gh workflow run config-compare.yml --repo "$REPO"
        echo "Waiting for workflows (60s)..."
        sleep 60
        LATEST_RUN=$(gh run list --repo "$REPO" --workflow=monthly-digest.yml --limit 1 --json databaseId -q '.[0].databaseId')
        if [ -n "$LATEST_RUN" ]; then
          gh run watch "$LATEST_RUN" --repo "$REPO" --exit-status || true
          CLONE_DIR=$(mktemp -d)
          gh repo clone "$REPO" "$CLONE_DIR" -- --depth 1 --single-branch 2>/dev/null
          if [ -d "$CLONE_DIR/digests/$TODAY_ISO" ]; then
            cp -r "$CLONE_DIR/digests/$TODAY_ISO" "$REPORTS_DIR/''${TODAY_ISO}-full"
            echo "Saved to $REPORTS_DIR/''${TODAY_ISO}-full"
          fi
          rm -rf "$CLONE_DIR"
        fi
        osascript -e 'display notification "Veille full terminee" with title "veille-claude" sound name "Tink"' 2>/dev/null || true
        exit 0
        ;;
      *)
        echo "Mode inconnu: $MODE"
        echo "   Usage: veille-claude [daily|compare|full] [--obsidian]"
        exit 1
        ;;
    esac

    echo "Triggering $WORKFLOW..."
    gh workflow run "$WORKFLOW" --repo "$REPO"

    echo "Waiting for workflow start (10s)..."
    sleep 10

    RUN_ID=$(gh run list --repo "$REPO" --workflow="$WORKFLOW" --limit 1 --json databaseId -q '.[0].databaseId')

    if [ -z "$RUN_ID" ]; then
      echo "Could not find workflow run"
      exit 1
    fi

    gh run watch "$RUN_ID" --repo "$REPO" --exit-status

    echo "Pulling latest digests..."
    CLONE_DIR=$(mktemp -d)
    gh repo clone "$REPO" "$CLONE_DIR" -- --depth 1 --single-branch 2>/dev/null

    if [ -d "$CLONE_DIR/digests/$TODAY_ISO" ]; then
      cp -r "$CLONE_DIR/digests/$TODAY_ISO" "$REPORTS_DIR/"
      echo "Saved to $REPORTS_DIR/$TODAY_ISO/"

      if [ "$OBSIDIAN_FLAG" = "--obsidian" ] || [ "''${VEILLE_OBSIDIAN:-}" = "1" ]; then
        mkdir -p "$OBSIDIAN_DIR"
        for f in "$REPORTS_DIR/$TODAY_ISO"/*.md; do
          [ -f "$f" ] || continue
          BASENAME=$(basename "$f" .md)
          {
            echo "---"
            echo "tags: [veille, claude-code, $MODE]"
            echo "date: $TODAY_ISO"
            echo "---"
            echo ""
            cat "$f"
          } > "$OBSIDIAN_DIR/''${TODAY_ISO}-''${BASENAME}.md"
        done
        echo "Copie dans Obsidian vault: $OBSIDIAN_DIR"
      fi
    else
      echo "No digests found for $TODAY_ISO in repo"
    fi

    rm -rf "$CLONE_DIR"
    osascript -e "display notification \"Veille $MODE terminee\" with title \"veille-claude\" sound name \"Tink\"" 2>/dev/null || true
  '';

in
{
  home.packages = [ veille-claude ];

  launchd.agents = {

    # Mon/Wed/Fri 9:00 — daily digest
    veille-daily = {
      enable = true;
      config = {
        Label = "com.alx.veille-daily";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-l"
          "-c"
          "veille-claude daily"
        ];
        StartCalendarInterval = [
          { Weekday = 1; Hour = 9; Minute = 0; }
          { Weekday = 3; Hour = 9; Minute = 0; }
          { Weekday = 5; Hour = 9; Minute = 0; }
        ];
        StandardOutPath = "/tmp/veille-daily.log";
        StandardErrorPath = "/tmp/veille-daily-err.log";
      };
    };

    # 1st and 15th at 10:00 — config comparison
    veille-compare = {
      enable = true;
      config = {
        Label = "com.alx.veille-compare";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-l"
          "-c"
          "veille-claude compare"
        ];
        StartCalendarInterval = [
          { Day = 1; Hour = 10; Minute = 0; }
          { Day = 15; Hour = 10; Minute = 0; }
        ];
        StandardOutPath = "/tmp/veille-compare.log";
        StandardErrorPath = "/tmp/veille-compare-err.log";
      };
    };

    # 1st of month at 8:00 — full (monthly + compare)
    veille-full = {
      enable = true;
      config = {
        Label = "com.alx.veille-full";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-l"
          "-c"
          "veille-claude full"
        ];
        StartCalendarInterval = [
          { Day = 1; Hour = 8; Minute = 0; }
        ];
        StandardOutPath = "/tmp/veille-full.log";
        StandardErrorPath = "/tmp/veille-full-err.log";
      };
    };

  };
}
