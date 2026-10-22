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
    # The agent screen's top pane, wherever it is typed (the board opens one only when none runs):
    # the slot of the board that picked last (its slot dir's mtime moves on each pick's mv), the
    # global pane when no board ever picked. `command ls`: the alias text is parsed again, so the
    # `ls` alias (eza, whose -t takes a field) would apply and leave the slot empty.
    ap = "_ap_slot=$(command ls -t \"\${XDG_STATE_HOME:-$HOME/.local/state}/agent-pane/slots\" 2>/dev/null | head -n 1); agent-pane \${_ap_slot:+--slot \"$_ap_slot\"}";
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
