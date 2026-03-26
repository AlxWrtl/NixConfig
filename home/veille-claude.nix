# ~/.config/nix-darwin/home/veille-claude.nix
# Veille technologique Claude Code — commande `veille-claude`
{ pkgs, lib, ... }:

let
  veilleRepo = "/Users/alx/projects/Claude Code Tech Watch";

  veille-claude = pkgs.writeShellScriptBin "veille-claude" ''
        set -euo pipefail

        MODE="''${1:-weekly}"
        TODAY=$(date '+%d %B %Y')
        TODAY_ISO=$(date '+%Y-%m-%d')
        WEEK_AGO=$(date -v-7d '+%d %B %Y')
        REPORTS_DIR="''${VEILLE_REPORTS_DIR:-$HOME/veille}"
        PROMPT_DIR="${veilleRepo}/prompts"
        OUTPUT="$REPORTS_DIR/''${TODAY_ISO}-''${MODE}.md"

        mkdir -p "$REPORTS_DIR"

        echo "🔍 veille-claude [''${MODE}] — ''${TODAY}"
        echo "📄 Output : ''${OUTPUT}"
        echo ""

        PROMPT_FILE="''${PROMPT_DIR}/''${MODE}.md"
        if [[ ! -f "''${PROMPT_FILE}" ]]; then
          echo "❌ Prompt introuvable : ''${PROMPT_FILE}"
          echo "   Modes disponibles : weekly | compare | mcp | full"
          exit 1
        fi

        PROMPT=$(sed \
          -e "s/{{TODAY}}/''${TODAY}/g" \
          -e "s/{{TODAY_ISO}}/''${TODAY_ISO}/g" \
          -e "s/{{WEEK_AGO}}/''${WEEK_AGO}/g" \
          "''${PROMPT_FILE}")

    echo "''${PROMPT}" | claude --model claude-opus-4-5 --print > "''${OUTPUT}"

        echo ""
        echo "✅ ''${OUTPUT}"
        echo ""
        cat "''${OUTPUT}"
  '';

in
{
  home.packages = [ veille-claude ];

  launchd.agents = {

    # Lundi 9h00 — nouveautés de la semaine
    veille-weekly = {
      enable = true;
      config = {
        Label = "com.alx.veille-weekly";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-l"
          "-c"
          "veille-claude weekly"
        ];
        StartCalendarInterval = [
          {
            Weekday = 1;
            Hour = 9;
            Minute = 0;
          }
        ];
        StandardOutPath = "/tmp/veille-weekly.log";
        StandardErrorPath = "/tmp/veille-weekly-err.log";
      };
    };

    # Lundi 9h30 — nouveaux MCP pertinents
    veille-mcp = {
      enable = true;
      config = {
        Label = "com.alx.veille-mcp";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-l"
          "-c"
          "veille-claude mcp"
        ];
        StartCalendarInterval = [
          {
            Weekday = 1;
            Hour = 9;
            Minute = 30;
          }
        ];
        StandardOutPath = "/tmp/veille-mcp.log";
        StandardErrorPath = "/tmp/veille-mcp-err.log";
      };
    };

    # 1er et 15 du mois à 10h — ma config vs état de l'art
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
          {
            Day = 1;
            Hour = 10;
            Minute = 0;
          }
          {
            Day = 15;
            Hour = 10;
            Minute = 0;
          }
        ];
        StandardOutPath = "/tmp/veille-compare.log";
        StandardErrorPath = "/tmp/veille-compare-err.log";
      };
    };

    # 1er du mois à 8h — veille mensuelle complète + roadmap
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
          {
            Day = 1;
            Hour = 8;
            Minute = 0;
          }
        ];
        StandardOutPath = "/tmp/veille-full.log";
        StandardErrorPath = "/tmp/veille-full-err.log";
      };
    };

  };
}
