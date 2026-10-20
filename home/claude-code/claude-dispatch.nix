# claude-dispatch — start one Claude Code session in a detached abduco session
# (`abduco -n <name> claude …`) from the main session, packaged as a real
# binary on PATH.
#
# Why abduco and not `claude --bg`: a session hosted by Claude's background
# daemon loses the microphone, voice dictation fails there
# (anthropics/claude-code#86217), while claude under abduco, started from
# Ghostty, records, also after detach/reattach (user probe 2026-10-20). The
# daemon is turned off (`disableAgentView`, settings.nix). Attach to a
# dispatched session with `abduco -a <name>`.
#
# Why a wrapper and not `abduco *` / `claude *` in sandbox.excludedCommands:
# a sandboxed abduco cannot create its session (EPERM on the socket,
# measured 2026-10-20), and an abduco server started inside the sandbox would
# hand its Seatbelt profile to the session, so the launch must run
# unsandboxed. `claude` takes ~20 flags that widen the launched session
# (--dangerously-skip-permissions, --permission-mode, --settings, --add-dir,
# --mcp-config, --plugin-dir, --append-system-prompt, --bare…), and abduco
# runs any command: a deny-list over them is unbounded. The wrapper is the
# allow-list: abduco gets only `-n <name>`, claude only
# `--worktree <name> --name <name>`, the brief is one argv entry, no file is
# read, no flag is passed through. The wrapper adds no env: it inherits the
# session's own environment, and a VAR= / env prefix on the call is denied by
# hooks/lone-excluded-bash.js. It removes one variable: CLAUDE_CODE_CHILD_SESSION,
# set in every Bash call of a Claude session; claude 2.1.305 turns transcript
# saving off in a session that inherits it, so `/resume` could not find the
# dispatched session. Only `claude-dispatch *` is excluded. The brief
# reaches claude as `[claude-dispatch] <brief>`: the CLAUDE.md Delegation rule
# forbids a session started that way to dispatch.
#
# A one-word prompt equal to a claude subcommand (`purge`, `rm`, `stop`…) runs
# the subcommand, and `--` does not prevent it (claude --help 2.1.299): the
# script requires two non-blank words in the brief and rejects a leading `-`.
#
# abduco and claude are called by absolute path (substituted for @abduco@ and
# @claude@). inheritPath stays true: the session inherits the dispatching
# shell's PATH, and the script itself uses bash builtins only, so PATH cannot
# substitute anything it calls. mkClaudeDispatch is exported so
# checks/claude-dispatch.nix can build the same script against a stub abduco
# and a stub claude (and its canary mutants).
{ pkgs }:
let
  mkClaudeDispatch =
    {
      abduco ? "${pkgs.abduco}/bin/abduco",
      claude ? "/opt/homebrew/bin/claude",
      text ? builtins.readFile ./scripts/claude-dispatch.sh,
    }:
    pkgs.writeShellApplication {
      name = "claude-dispatch";
      runtimeInputs = [ ];
      text = builtins.replaceStrings [ "@abduco@" "@claude@" ] [ abduco claude ] text;
    };
in
{
  claudeDispatchPkg = mkClaudeDispatch { };
  inherit mkClaudeDispatch;
}
