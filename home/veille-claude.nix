# ~/.config/nix-darwin/home/veille-claude.nix
# Veille technologique — runs alx-claude-radar locally via claude --print
{ pkgs, lib, ... }:

let
  radarRepo = "/Users/alx/projects/alx-claude-radar";

  veille-claude = pkgs.writeShellScriptBin "veille-claude" ''
    set -euo pipefail

    MODE="''${1:-daily}"
    RADAR_DIR="${radarRepo}"
    TODAY_ISO=$(date '+%Y-%m-%d')
    REPORTS_DIR="''${VEILLE_REPORTS_DIR:-$HOME/veille}"
    OBSIDIAN_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/AlxVault/04-Resources/veille-claude"

    mkdir -p "$REPORTS_DIR"

    echo "veille-claude [$MODE] -- $(date '+%d %B %Y')"

    if [ ! -d "$RADAR_DIR" ]; then
      echo "Radar repo not found at $RADAR_DIR"
      echo "Run: gh repo clone AlxWrtl/alx-claude-radar ~/projects/alx-claude-radar"
      exit 1
    fi

    cd "$RADAR_DIR"

    # Ensure deps are installed
    if [ ! -d "node_modules" ]; then
      echo "Installing dependencies..."
      pnpm install --frozen-lockfile
    fi

    # Set provider to claude-cli (uses claude --print, no API key needed)
    export LLM_PROVIDER="claude-cli"
    export GITHUB_TOKEN=$(gh auth token)

    # Telegram notifications
    if [ -f "$HOME/.config/secrets/telegram-bot-token" ]; then
      export TELEGRAM_BOT_TOKEN=$(cat "$HOME/.config/secrets/telegram-bot-token")
      export TELEGRAM_CHAT_ID=$(cat "$HOME/.config/secrets/telegram-chat-id")
    fi

    case "$MODE" in
      daily)
        echo "Running daily digest..."
        pnpm start
        ;;
      compare)
        echo "Running config comparison..."
        pnpm compare
        ;;
      full)
        echo "Running monthly digest..."
        pnpm monthly
        echo "Running config comparison..."
        pnpm compare
        ;;
      *)
        echo "Mode inconnu: $MODE"
        echo "   Usage: veille-claude [daily|compare|full] [--obsidian]"
        exit 1
        ;;
    esac

    # Copy results to reports dir
    if [ -d "digests/$TODAY_ISO" ]; then
      cp -r "digests/$TODAY_ISO" "$REPORTS_DIR/"
      echo "Saved to $REPORTS_DIR/$TODAY_ISO/"

      # Obsidian copy (always on, FR only, with wikilinks)
      mkdir -p "$OBSIDIAN_DIR"

      # Copy each FR report with frontmatter + wikilinks
      for f in "digests/$TODAY_ISO"/*.md; do
        [ -f "$f" ] || continue
        BASENAME=$(basename "$f" .md)
        case "$BASENAME" in *-en) continue ;; esac
        NOTE_NAME="''${TODAY_ISO}-''${BASENAME}"

        {
          echo "---"
          echo "tags: [veille, claude-code, $MODE]"
          echo "date: $TODAY_ISO"
          echo "---"
          echo ""
          cat "$f"
          echo ""
          echo "---"
          echo "## Voir aussi"
          echo ""
          echo "- [[''${TODAY_ISO}-veille|Index du jour]]"
          for sib in "digests/$TODAY_ISO"/*.md; do
            [ -f "$sib" ] || continue
            S=$(basename "$sib" .md)
            case "$S" in *-en) continue ;; esac
            [ "$S" = "$BASENAME" ] && continue
            echo "- [[''${TODAY_ISO}-''${S}]]"
          done
        } > "$OBSIDIAN_DIR/''${NOTE_NAME}.md"
      done

      # Daily MOC (Map of Content)
      {
        echo "---"
        echo "tags: [veille, claude-code, moc]"
        echo "date: $TODAY_ISO"
        echo "---"
        echo ""
        echo "# Veille Claude Code — $TODAY_ISO"
        echo ""
        for f in "digests/$TODAY_ISO"/*.md; do
          [ -f "$f" ] || continue
          SIB=$(basename "$f" .md)
          case "$SIB" in *-en) continue ;; esac
          echo "- [[''${TODAY_ISO}-''${SIB}]]"
        done
      } > "$OBSIDIAN_DIR/''${TODAY_ISO}-veille.md"

      echo "Obsidian: $OBSIDIAN_DIR"
    else
      echo "No digests found for $TODAY_ISO"
    fi

    osascript -e "display notification \"Veille $MODE terminee\" with title \"veille-claude\" sound name \"Tink\"" 2>/dev/null || true
  '';

in
{
  home.packages = [ veille-claude ];

  launchd.agents = {

    # Mon/Wed/Fri 9:00 — daily digest (local, claude --print)
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
