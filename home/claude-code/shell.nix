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
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    CLAUDE_CODE_EFFORT_LEVEL = "high";
    CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "90";
    npm_config_prefer_pnpm = "true";
    npm_config_user_agent = "pnpm";
  };
}
