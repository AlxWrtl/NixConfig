# Daily TTW watch: fetch.py reads HN, Reddit, GitHub releases and arXiv, a
# tool-less Haiku sorts the candidates, results land in
# ~/.local/share/veille-ttw (bruts/, tris/, inbox.md). Parsers are tested
# offline by checks/veille.nix.
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
}
