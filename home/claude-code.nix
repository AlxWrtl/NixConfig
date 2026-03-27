{
  config,
  pkgs,
  lib,
  ...
}:

let
  claudeDir = ".claude";

  # Import modular definitions
  settings = import ./claude-code/settings.nix { homeDirectory = config.home.homeDirectory; };
  commands = import ./claude-code/commands.nix;
  skills = import ./claude-code/skills.nix;
  hooks = import ./claude-code/hooks.nix;
  agents = import ./claude-code/agents.nix;
  shell = import ./claude-code/shell.nix;
  claudeMd = import ./claude-code/claude-md.nix;
  activationScripts = import ./claude-code/activation.nix { inherit pkgs lib; };

  inherit (claudeMd) claudeMdGlobal;
  inherit (settings) settingsJson statuslineScript mcpServersJson;
  inherit (commands)
    cmdTdd
    cmdOptimize
    cmdContextPrime
    cmdAuto
    cmdRalphLoop
    cmdCancelRalph
    cmdInitMemoryBank
    commandDiscuss
    commandVerifyFeature
    featureChainScript
    ;
  inherit (skills)
    skillApex
    skillDebug
    skillContinuousLearning
    skillFeatureWorkflow
    skillNixDarwin
    skillClaudeCodeMeta
    skillObsidian
    skillSchliff
    skillAutoresearch
    skillTestingPatterns
    skillCodebaseAudit
    ;
  inherit (hooks)
    hookProtectMain
    hookFormatTypescript
    hookBlockMainBash
    hookPreCompactBackup
    hookSessionStart
    hookSubagentStop
    hookTaskCompleted
    hookNotification
    hookCompactContext
    hookFileChanged
    hookStopFailure
    ;
  inherit (agents)
    agentFrontend
    agentBackend
    agentArch
    agentPerf
    agentNavigator
    agentReviewer
    agentQuickFix
    agentNix
    agentGitShip
    agentTeamLead
    agentTestRunner
    agentSecurityAuditor
    agentDebugger
    ;
  inherit (shell) aliases sessionVars;
in
{
  # Shell integration
  programs.zsh.shellAliases = aliases;
  programs.zsh.sessionVariables = sessionVars;

  # Write ~/.claude content declaratively
  home.file = {
    # Settings base (read-only reference, merged by activation script)
    "${claudeDir}/settings-base.json" = {
      text = settingsJson;
    };

    # MCP servers base (merged into .claude.json by activation script)
    "${claudeDir}/mcp-servers-base.json" = {
      text = mcpServersJson;
    };

    "${claudeDir}/CLAUDE.md" = {
      text = claudeMdGlobal;
    };

    # Commands
    "${claudeDir}/commands/tdd.md".text = cmdTdd;
    "${claudeDir}/commands/optimize.md".text = cmdOptimize;
    "${claudeDir}/commands/context-prime.md".text = cmdContextPrime;
    "${claudeDir}/commands/auto.md".text = cmdAuto;
    "${claudeDir}/commands/init-memory-bank.md".text = cmdInitMemoryBank;
    "${claudeDir}/commands/ralph-loop.md".text = cmdRalphLoop;
    "${claudeDir}/commands/cancel-ralph.md".text = cmdCancelRalph;

    # Feature methodology commands
    "${claudeDir}/commands/discuss.md".text = commandDiscuss;
    "${claudeDir}/commands/verify-feature.md".text = commandVerifyFeature;

    # Skills (force = true: desymlink activation script replaces these with real copies)
    "${claudeDir}/skills/feature-workflow/SKILL.md" = { text = skillFeatureWorkflow; force = true; };

    # Feature chain script
    "${claudeDir}/feature-chain.sh" = {
      text = featureChainScript;
      executable = true;
    };

    # Agents (13)
    "${claudeDir}/agents/frontend-expert.md".text = agentFrontend;
    "${claudeDir}/agents/backend-expert.md".text = agentBackend;
    "${claudeDir}/agents/architecture-expert.md".text = agentArch;
    "${claudeDir}/agents/performance-expert.md".text = agentPerf;
    "${claudeDir}/agents/codebase-navigator.md".text = agentNavigator;
    "${claudeDir}/agents/code-reviewer.md".text = agentReviewer;
    "${claudeDir}/agents/quick-fix.md".text = agentQuickFix;
    "${claudeDir}/agents/nix-expert.md".text = agentNix;
    "${claudeDir}/agents/git-ship.md".text = agentGitShip;
    "${claudeDir}/agents/team-lead.md".text = agentTeamLead;
    "${claudeDir}/agents/test-runner.md".text = agentTestRunner;
    "${claudeDir}/agents/security-auditor.md".text = agentSecurityAuditor;
    "${claudeDir}/agents/debugger.md".text = agentDebugger;

    "${claudeDir}/skills/apex/SKILL.md" = { text = skillApex; force = true; };
    "${claudeDir}/skills/debug/SKILL.md" = { text = skillDebug; force = true; };
    "${claudeDir}/skills/nix-darwin/SKILL.md" = { text = skillNixDarwin; force = true; };
    "${claudeDir}/skills/claude-code-meta/SKILL.md" = { text = skillClaudeCodeMeta; force = true; };
    "${claudeDir}/skills/obsidian/SKILL.md" = { text = skillObsidian; force = true; };
    "${claudeDir}/skills/schliff/SKILL.md" = { text = skillSchliff; force = true; };
    "${claudeDir}/skills/autoresearch/SKILL.md" = { text = skillAutoresearch; force = true; };
    "${claudeDir}/skills/continuous-learning-v2/SKILL.md" = { text = skillContinuousLearning; force = true; };
    "${claudeDir}/skills/testing-patterns/SKILL.md" = { text = skillTestingPatterns; force = true; };
    "${claudeDir}/skills/codebase-audit/SKILL.md" = { text = skillCodebaseAudit; force = true; };

    # Hooks
    "${claudeDir}/hooks/protect-main.js" = {
      text = hookProtectMain;
      executable = true;
    };
    "${claudeDir}/hooks/format-typescript.js" = {
      text = hookFormatTypescript;
      executable = true;
    };
    "${claudeDir}/hooks/block-main-bash.js" = {
      text = hookBlockMainBash;
      executable = true;
    };
    "${claudeDir}/hooks/pre-compact-backup.sh" = {
      text = hookPreCompactBackup;
      executable = true;
    };
    "${claudeDir}/hooks/session-start.sh" = {
      text = hookSessionStart;
      executable = true;
    };
    "${claudeDir}/hooks/subagent-stop.js" = {
      text = hookSubagentStop;
      executable = true;
    };
    "${claudeDir}/hooks/task-completed.sh" = {
      text = hookTaskCompleted;
      executable = true;
    };
    "${claudeDir}/hooks/notification.sh" = {
      text = hookNotification;
      executable = true;
    };
    "${claudeDir}/hooks/compact-context.sh" = {
      text = hookCompactContext;
      executable = true;
    };
    "${claudeDir}/hooks/file-changed.sh" = {
      text = hookFileChanged;
      executable = true;
    };
    "${claudeDir}/hooks/stop-failure.sh" = {
      text = hookStopFailure;
      executable = true;
    };

    # Statusline script
    "${claudeDir}/statusline.sh" = {
      text = statuslineScript;
      executable = true;
    };
  };

  # Activation scripts
  home.activation = activationScripts;
}
