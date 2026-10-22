# Claude Code shell aliases and environment variables
{
  aliases = {
    cc = "claude";
    cca = "claude --agent";
    ccr = "claude --resume";
    ccd = "claude --dangerously-skip-permissions";
    ccdl = "claude --dangerously-skip-permissions -c";
    ccn = "cd ~/.config/nix-darwin && claude";
    ccv = "claude --version";
    ccro = "claude --plan-mode --read-only";
    ccw = "claude --worktree";
    ccb = "claude --bare";
    ccrc = "claude --remote-control";
    ccl = "claude -c";
    # Makes the terminal it is typed in an agent pane: its slot is that Ghostty terminal's id
    # (`--here`), the one the board finds when this pane is clicked during a placement, so no
    # slot is looked up here. Ghostty unreachable: the global pane, said in its header.
    ap = "agent-pane --here";
    # The terminal APEX board (`ab` is Apache's benchmark, /usr/sbin/ab).
    bd = "apex-board --tui";
    # Skill analysis tools
    schliff = "uvx schliff";
    schliff-all = "uvx schliff doctor --skill-dirs ~/.claude/skills/ -v";
  };

  sessionVars = {
    RTK_AGENT = "claude";
  };
}
