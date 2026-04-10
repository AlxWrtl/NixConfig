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
    cct = "claude --agent team-lead";
    ccl = "claude -c";
    # Skill analysis tools
    schliff = "uvx schliff";
    schliff-all = "uvx schliff doctor --skill-dirs ~/.claude/skills/ -v";
  };

  sessionVars = { };
}
