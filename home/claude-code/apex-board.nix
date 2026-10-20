# apex-board — the APEX run board (kanban of `.claude/output/apex/<run-id>/`),
# packaged as a real binary on PATH.
#
# Serves a temp dir of links on 127.0.0.1 with apex-board/serve.py (python's
# SimpleHTTPRequestHandler behind a Host gate against DNS rebinding and a
# realpath gate against symlinks out of the root): the page (index.html +
# board.js, copied into the store below; test.js stays out) and the repo's
# runs, the correction budget and a meta.json. serve.py sits in the same store
# dir but is never copied into the served root. Read-only: GET and HEAD only.
#
# The page dir's store path replaces `@boardDir@` in the script; a missing
# placeholder throws at eval, so a renamed one cannot ship a board that points
# nowhere. writeShellApplication prepends `set -euo pipefail` and runs
# shellcheck at build time, so a regression in the script fails the rebuild.
{ pkgs }:
let
  boardDir = pkgs.runCommand "apex-board-page" { } ''
    mkdir -p $out
    cp ${./apex-board/index.html} $out/index.html
    cp ${./apex-board/board.js} $out/board.js
    cp ${./apex-board/serve.py} $out/serve.py
  '';

  script = builtins.readFile ./scripts/apex-board.sh;
  text = builtins.replaceStrings [ "@boardDir@" ] [ "${boardDir}" ] script;
in
{
  apexBoardPkg = pkgs.writeShellApplication {
    name = "apex-board";
    runtimeInputs = [
      pkgs.python3
      pkgs.coreutils
      pkgs.git
      pkgs.jq
    ];
    text =
      if text == script then
        throw "apex-board.nix: placeholder @boardDir@ not found in scripts/apex-board.sh"
      else
        text;
  };
}
