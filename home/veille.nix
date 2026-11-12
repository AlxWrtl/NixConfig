# TTW watch, two launchd agents.
# Daily (`veille-ttw`): fetch.py reads HN, Reddit, GitHub releases and arXiv, a
# tool-less Haiku sorts the candidates, results land in
# ~/.local/share/veille-ttw (bruts/, tris/, inbox.md). Parsers are tested
# offline by checks/veille.nix.
# Weekly (`veille-hebdo`): weekly.sh sends the inbox URLs not yet judged
# (seed ledger-seed.tsv + ledger.tsv) to an Opus restricted to per-domain
# WebFetch, with the repo/vault context on stdin; retained entries land in the
# vault (veille/hebdo/<week>.md), every verdict in ledger.tsv. Tested offline by
# checks/veille-hebdo.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  veille = pkgs.writeShellApplication {
    name = "veille-ttw";
    runtimeInputs = [
      pkgs.python3
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.gnused
    ];
    runtimeEnv = {
      # Interpolated, not bare paths: each file is copied to its own store path.
      VEILLE_FETCH = "${./veille/fetch.py}";
      VEILLE_PROMPT = "${./veille/filter-prompt.md}";
    };
    text = builtins.readFile ./veille/daily.sh;
  };
  hebdo = pkgs.writeShellApplication {
    name = "veille-hebdo";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.gawk
      pkgs.findutils
      pkgs.jq
      pkgs.gh
      # gh pr list without -R resolves the repo from the git remotes.
      pkgs.git
    ];
    runtimeEnv = {
      VEILLE_HEBDO_PROMPT = "${./veille/weekly-prompt.md}";
      VEILLE_HEBDO_SCHEMA = "${./veille/weekly-schema.json}";
      VEILLE_SEED = "${./veille/ledger-seed.tsv}";
    };
    text = builtins.readFile ./veille/weekly.sh;
  };
in
{
  # launchd has no shell PATH: the script carries its own, and calls claude by
  # its Homebrew path (VEILLE_CLAUDE overrides it in tests). A missed 08:30 (asleep) runs at the next wake.
  launchd.agents.veille-ttw = {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe veille) ];
      StartCalendarInterval = [
        {
          Hour = 8;
          Minute = 30;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/veille-ttw.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/veille-ttw.log";
    };
  };

  # Weekday 1 = Monday, after ttw-replay (09:30) so its report is in the
  # context. No notification: the vault note is the output.
  launchd.agents.veille-hebdo = {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe hebdo) ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 10;
          Minute = 0;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/veille-hebdo.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/veille-hebdo.log";
    };
  };
}
