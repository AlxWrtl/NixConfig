# claude-dispatch — start one background Claude Code session (`claude --bg`)
# from the main session, packaged as a real binary on PATH.
#
# Why a wrapper and not `claude --bg *` in sandbox.excludedCommands: a
# sandboxed `claude --bg` fails with EPERM on mkdir ~/.claude/jobs (measured
# 2026-10-15, Claude Code's built-in protection, not from nix), so the launch
# must run unsandboxed. `claude` takes ~20 flags that widen the launched
# session (--dangerously-skip-permissions, --permission-mode, --settings,
# --add-dir, --mcp-config, --plugin-dir, --append-system-prompt, --bare…): a
# deny-list over them is unbounded. The wrapper is the allow-list: the only
# flags claude ever gets are `--bg --worktree <name> --name <name>`, the brief is one argv entry, no
# file is read, no flag is passed through. The wrapper adds no env: it
# inherits the session's own environment, and a VAR= / env prefix on the call
# is denied by hooks/lone-excluded-bash.js. Only `claude-dispatch *` is
# excluded. The brief reaches claude as `[claude-dispatch] <brief>`: the
# CLAUDE.md Delegation rule forbids a session started that way to dispatch.
#
# A one-word prompt equal to a claude subcommand (`purge`, `rm`, `stop`…) runs
# the subcommand, and `--` does not prevent it (claude --help 2.1.299): the
# script requires two non-blank words in the brief and rejects a leading `-`.
#
# claude is called by absolute path (substituted for @claude@). inheritPath
# stays true: the background session inherits the dispatching shell's PATH,
# and the script itself uses bash builtins only, so PATH cannot substitute
# anything it calls. mkClaudeDispatch is exported so checks/claude-dispatch.nix
# can build the same script against a stub claude (and its canary mutants).
{ pkgs }:
let
  mkClaudeDispatch =
    {
      claude ? "/opt/homebrew/bin/claude",
      text ? builtins.readFile ./scripts/claude-dispatch.sh,
    }:
    pkgs.writeShellApplication {
      name = "claude-dispatch";
      runtimeInputs = [ ];
      text = builtins.replaceStrings [ "@claude@" ] [ claude ] text;
    };
in
{
  claudeDispatchPkg = mkClaudeDispatch { };
  inherit mkClaudeDispatch;
}
