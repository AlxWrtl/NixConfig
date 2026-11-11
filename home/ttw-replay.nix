# Weekly TTW stale-step replay: replay.js runs ~/.claude/hooks/ttw-flags.js on
# every Skill(ttw) call of the transcripts in ~/.claude/projects (read-only)
# and scores the steps it names against an oracle; reports land in
# ~/.local/share/ttw-replay (<date>.json + .md, never overwritten). Tested
# offline by checks/ttw-replay.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  replay = pkgs.writeShellApplication {
    name = "ttw-replay";
    text = ''
      exec ${pkgs.nodejs}/bin/node ${./ttw-replay/replay.js} "$@"
    '';
  };
in
{
  # Weekday 1 = Monday (launchd.plist(5): 0 and 7 are Sunday). A missed
  # Monday 09:30 (asleep) runs at the next wake.
  launchd.agents.ttw-replay = {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe replay) ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 9;
          Minute = 30;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ttw-replay.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ttw-replay.log";
    };
  };
}
