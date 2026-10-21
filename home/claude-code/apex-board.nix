# apex-board — the APEX run board (kanban of `.claude/output/apex/<run-id>/`),
# packaged as a real binary on PATH.
#
# Serves a temp dir of links on 127.0.0.1 with apex-board/serve.py (python's
# SimpleHTTPRequestHandler behind a Host gate against DNS rebinding and a
# realpath gate against symlinks out of the root): the page (index.html +
# board.js, copied into the store below; test.js and parity.js stay out) and
# the repo's runs, the correction budget and a meta.json. serve.py sits in the
# same store dir but is never copied into the served root. Read-only: GET and
# HEAD only.
#
# `apex-board --tui` execs the Go program built below from apex-board/tui/
# (Bubble Tea, a port of board.js's rules): the same board drawn in the
# terminal, no server, no node. `go test` runs in its checkPhase; the byte
# parity with board.js is checks/apex-board.nix's job (node is not here).
# Its Agents tab lists the dispatched sessions (session-state files and
# abduco's list); Enter runs `agent-pane pick <name>`, `x` or the card's ×
# `agent-pane stop <name>` once confirmed (a second `x`/×), `n` or its
# « + nouvel agent » `claude-dispatch --blank agent-HHMMSS` in the board's
# repo then a pick, `c` on a closed agent `abduco -n <name> claude --continue`
# in its worktree then a pick, `N` a generic agent in `~/agents/<name>`;
# pick, alive and the split carry `--slot <board tty>` so each board drives
# its own agent-pane; the Runs tab also reads the agents' runs (worktrees
# and ~/agents, links refused); the binaries are baked in by path (-X
# ldflags; claude at claude-dispatch's /opt/homebrew path), never looked up
# on PATH. abduco comes from the same pkgs as
# claude-dispatch (same socket dir); agent-pane.nix and claude-dispatch.nix
# are imported here as in home/claude-code.nix (pure: same derivations).
#
# The page dir's and the binary's store paths replace `@boardDir@` and
# `@tuiBin@` in the script; a missing placeholder throws at eval, so a renamed
# one cannot ship a board that points nowhere. writeShellApplication prepends
# `set -euo pipefail` and runs shellcheck at build time, so a regression in
# the script fails the rebuild.
{ pkgs }:
let
  agentPane = import ./agent-pane.nix { inherit pkgs; };
  dispatch = import ./claude-dispatch.nix { inherit pkgs; };

  boardDir = pkgs.runCommand "apex-board-page" { } ''
    mkdir -p $out
    cp ${./apex-board/index.html} $out/index.html
    cp ${./apex-board/board.js} $out/board.js
    cp ${./apex-board/serve.py} $out/serve.py
  '';

  # testdata/ keeps its relative links (escapes out of a run dir) in the
  # store src: the disk tests read them as links.
  tui = pkgs.buildGoModule {
    pname = "apex-board-tui";
    version = "0";
    src = ./apex-board/tui;
    vendorHash = "sha256-qpcRouxzBsHE/fSMvwAeuYYq8mRIAzPpsiVfE77z8Y8=";
    ldflags = [
      "-s"
      "-w"
      "-X main.abducoBin=${pkgs.abduco}/bin/abduco"
      "-X main.agentPaneBin=${agentPane.agentPanePkg}/bin/agent-pane"
      "-X main.dispatchBin=${dispatch.claudeDispatchPkg}/bin/claude-dispatch"
      "-X main.claudeBin=/opt/homebrew/bin/claude"
    ];
    postInstall = ''
      mv $out/bin/tui $out/bin/apex-board-tui
    '';
    meta.mainProgram = "apex-board-tui";
  };
  tuiBin = "${tui}/bin/apex-board-tui";

  script = builtins.readFile ./scripts/apex-board.sh;
  missing = builtins.filter (p: !pkgs.lib.hasInfix p script) [
    "@boardDir@"
    "@tuiBin@"
  ];
  text = builtins.replaceStrings [ "@boardDir@" "@tuiBin@" ] [ "${boardDir}" tuiBin ] script;
in
{
  inherit tui;
  apexBoardPkg = pkgs.writeShellApplication {
    name = "apex-board";
    runtimeInputs = [
      pkgs.python3
      pkgs.coreutils
      pkgs.git
      pkgs.jq
    ];
    text =
      if missing != [ ] then
        throw "apex-board.nix: placeholder ${builtins.head missing} not found in scripts/apex-board.sh"
      else
        text;
  };
}
