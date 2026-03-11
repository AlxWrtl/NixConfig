# Claude Code shell aliases and environment variables
{
  aliases = {
    cc = "claude";
    cca = "claude --agent";
    ccr = "claude --resume";
    ccd = "claude --dangerously-skip-permissions";
    ccn = "cd ~/.config/nix-darwin && claude";
    ccv = "claude --version";
    ccro = "claude --plan-mode --read-only";
  };

  sessionVars = {
    CLAUDE_CONFIG_DIR = "$HOME/.claude";
  };
}
