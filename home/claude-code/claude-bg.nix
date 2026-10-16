# claude-bg — tend background Claude Code sessions (`claude respawn <id>`,
# `claude logs <id>`, `claude daemon status`) from the main session, packaged
# as a real binary on PATH.
#
# Why a wrapper: sandboxed, these talk to the background daemon and fail
# (measured 2026-10-16): `claude respawn` → "background service exited before
# it became reachable (exit code 1, nothing on stderr)", `claude logs` →
# ECONNREFUSED on /tmp/cc-daemon-501/*/control.sock. So they must run
# unsandboxed. Why not `claude respawn *` in sandbox.excludedCommands: check
# A14d forbids any `claude` entry there, `respawn --all` revives every job at
# once, and `claude` takes ~20 flags that widen a session
# (--dangerously-skip-permissions, --permission-mode, --settings, --add-dir…):
# a deny-list over them is unbounded. The wrapper is the allow-list: claude
# only ever gets `respawn <id>`, `logs <id>` or `daemon status`. Only
# `claude-bg *` is excluded.
#
# The id must be the 8-hex short id (^[0123456789abcdef]{8}$, as in ~/.claude/jobs) for
# both respawn and logs: respawn also takes `--all`, and logs also takes a
# name matched as a fuzzy substring — neither is an allow-list.
#
# claude is called by absolute path (substituted for @claude@). The wrapper
# adds no env: it inherits the session's own, and a VAR= / env prefix on the
# call is denied by hooks/lone-excluded-bash.js. inheritPath stays true: the
# script uses bash builtins only, so PATH cannot substitute anything it calls.
# mkClaudeBg is exported so checks/claude-bg.nix can build the same script
# against a stub claude (and its canary mutants).
{ pkgs }:
let
  mkClaudeBg =
    {
      claude ? "/opt/homebrew/bin/claude",
      text ? builtins.readFile ./scripts/claude-bg.sh,
    }:
    pkgs.writeShellApplication {
      name = "claude-bg";
      runtimeInputs = [ ];
      text = builtins.replaceStrings [ "@claude@" ] [ claude ] text;
    };
in
{
  claudeBgPkg = mkClaudeBg { };
  inherit mkClaudeBg;
}
