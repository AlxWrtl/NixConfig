{
  config,
  pkgs,
  lib,
  ...
}:

let
  claudeDir = ".claude";

  # Import modular definitions
  settings = import ./claude-code/settings.nix;
  commands = import ./claude-code/commands.nix;
  skills = import ./claude-code/skills.nix;
  hooks = import ./claude-code/hooks.nix;
  agents = import ./claude-code/agents.nix;
  shell = import ./claude-code/shell.nix;
  claudeMd = import ./claude-code/claude-md.nix;
  activationScripts = import ./claude-code/activation.nix { inherit pkgs lib; };

  inherit (claudeMd) claudeMdGlobal;
  inherit (settings) settingsJson statuslineScript;
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
    ;
  inherit (hooks)
    hookProtectMain
    hookFormatTypescript
    hookBlockMainBash
    hookPreCompactBackup
    hookSessionStart
    hookSubagentStop
    hookTaskCompleted
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

    # Feature workflow skill
    "${claudeDir}/skills/feature-workflow/SKILL.md".text = skillFeatureWorkflow;

    # Feature chain script
    "${claudeDir}/feature-chain.sh" = {
      text = featureChainScript;
      executable = true;
    };

    # Agents (10)
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

    # Skills
    "${claudeDir}/skills/apex/SKILL.md".text = skillApex;
    "${claudeDir}/skills/debug/SKILL.md".text = skillDebug;
    "${claudeDir}/skills/nix-darwin/SKILL.md".text = skillNixDarwin;
    "${claudeDir}/skills/claude-code-meta/SKILL.md".text = skillClaudeCodeMeta;

    # Continuous Learning V2
    "${claudeDir}/skills/continuous-learning-v2/SKILL.md".text = skillContinuousLearning;

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

    # Statusline script
    "${claudeDir}/statusline.sh" = {
      text = statuslineScript;
      executable = true;
    };
  };

  # Activation scripts
  home.activation = activationScripts;
}
