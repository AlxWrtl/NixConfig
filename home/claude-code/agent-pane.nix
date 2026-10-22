# agent-pane — the switchable top pane of the agent screen (one Ghostty
# window: top = one agent session, bottom = apex-board). Run `agent-pane` in
# the top pane; `agent-pane pick <name>` switches the abduco session it
# shows (a click in the board or the deck will call it).
#
# Why a pane that detaches and reattaches and not one abduco client per
# agent: abduco keeps a session alive without a client, and SIGTERM to a
# client detaches it (abduco(1) SIGNALS), so one terminal can move between
# sessions while every dispatched agent keeps running. Why a selection file
# and not a signal to the pane: `pick` runs from anywhere (board, deck,
# shell) without knowing the pane's pid, and a missing pane just leaves the
# file for the next one.
#
# abduco is called by absolute path (substituted for @abduco@), from the same
# pkgs as claude-dispatch (same default socket dir); osascript too (@osascript@,
# macOS's own /usr/bin/osascript: `--here` asks Ghostty for its terminal id,
# the check substitutes a stub). inheritPath = false: the
# script needs only coreutils, jq and flock (the pane's lock, read by
# `alive`), and the attached client spawns nothing.
# mkAgentPane is exported so checks/agent-pane.nix can build the same script
# against a stub abduco (and its canary mutants).
{ pkgs }:
let
  mkAgentPane =
    {
      abduco ? "${pkgs.abduco}/bin/abduco",
      osascript ? "/usr/bin/osascript",
      text ? builtins.readFile ./scripts/agent-pane.sh,
    }:
    pkgs.writeShellApplication {
      name = "agent-pane";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
        pkgs.flock
      ];
      inheritPath = false;
      text = builtins.replaceStrings [ "@abduco@" "@osascript@" ] [ abduco osascript ] text;
    };
in
{
  agentPanePkg = mkAgentPane { };
  inherit mkAgentPane;
}
