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
    apexStep00Init
    apexStep00bInteractive
    apexStep00bBranch
    apexStep00bEconomy
    apexStep00bSave
    apexStep01Analyze
    apexStep01bObsidianContext
    apexStep02Plan
    apexStep02cVerify
    apexStep02bTasks
    apexStep03Execute
    apexStep03ExecuteTeams
    apexStep04Validate
    apexStep05Examine
    apexStep06Resolve
    apexStep07Tests
    apexStep08RunTests
    apexStep09Finish
    apexStep09bObsidianNote
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
    skillCaveman
    skillCavemem
    ;
  inherit (hooks)
    hookRtkRewrite
    hookProtectMain
    hookFormatTypescript
    hookBlockMainBash
    hookPreCompactBackup
    hookSessionStart
    hookSubagentStop
    hookTaskCompleted
    hookNotification
    hookCompactContext
    hookStopFailure
    hookCircuitBreaker
    hookCircuitBreakerReset
    hookPreCompactState
    hookPostCompactRestore
    hookQualityGate
    hookGovernanceAudit
    hookCorrectionCapture
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

  # npm global prefix (nix store is immutable, npm install -g needs a writable prefix)
  home.sessionPath = [ "$HOME/.npm-global/bin" ];

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
    "${claudeDir}/skills/feature-workflow/SKILL.md" = {
      text = skillFeatureWorkflow;
      force = true;
    };

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

    "${claudeDir}/skills/apex/SKILL.md" = {
      text = skillApex;
      force = true;
    };
    "${claudeDir}/skills/apex/steps/step-00-init.md".text = apexStep00Init;
    "${claudeDir}/skills/apex/steps/step-00b-interactive.md".text = apexStep00bInteractive;
    "${claudeDir}/skills/apex/steps/step-00b-branch.md".text = apexStep00bBranch;
    "${claudeDir}/skills/apex/steps/step-00b-economy.md".text = apexStep00bEconomy;
    "${claudeDir}/skills/apex/steps/step-00b-save.md".text = apexStep00bSave;
    "${claudeDir}/skills/apex/steps/step-01-analyze.md".text = apexStep01Analyze;
    "${claudeDir}/skills/apex/steps/step-01b-obsidian-context.md".text = apexStep01bObsidianContext;
    "${claudeDir}/skills/apex/steps/step-02-plan.md".text = apexStep02Plan;
    "${claudeDir}/skills/apex/steps/step-02c-verify.md".text = apexStep02cVerify;
    "${claudeDir}/skills/apex/steps/step-02b-tasks.md".text = apexStep02bTasks;
    "${claudeDir}/skills/apex/steps/step-03-execute.md".text = apexStep03Execute;
    "${claudeDir}/skills/apex/steps/step-03-execute-teams.md".text = apexStep03ExecuteTeams;
    "${claudeDir}/skills/apex/steps/step-04-validate.md".text = apexStep04Validate;
    "${claudeDir}/skills/apex/steps/step-05-examine.md".text = apexStep05Examine;
    "${claudeDir}/skills/apex/steps/step-06-resolve.md".text = apexStep06Resolve;
    "${claudeDir}/skills/apex/steps/step-07-tests.md".text = apexStep07Tests;
    "${claudeDir}/skills/apex/steps/step-08-run-tests.md".text = apexStep08RunTests;
    "${claudeDir}/skills/apex/steps/step-09-finish.md".text = apexStep09Finish;
    "${claudeDir}/skills/apex/steps/step-09b-obsidian-note.md".text = apexStep09bObsidianNote;
    "${claudeDir}/skills/debug/SKILL.md" = {
      text = skillDebug;
      force = true;
    };
    "${claudeDir}/skills/nix-darwin/SKILL.md" = {
      text = skillNixDarwin;
      force = true;
    };
    "${claudeDir}/skills/claude-code-meta/SKILL.md" = {
      text = skillClaudeCodeMeta;
      force = true;
    };
    "${claudeDir}/skills/obsidian/SKILL.md" = {
      text = skillObsidian;
      force = true;
    };
    "${claudeDir}/skills/schliff/SKILL.md" = {
      text = skillSchliff;
      force = true;
    };
    "${claudeDir}/skills/autoresearch/SKILL.md" = {
      text = skillAutoresearch;
      force = true;
    };
    "${claudeDir}/skills/continuous-learning-v2/SKILL.md" = {
      text = skillContinuousLearning;
      force = true;
    };
    "${claudeDir}/skills/testing-patterns/SKILL.md" = {
      text = skillTestingPatterns;
      force = true;
    };
    "${claudeDir}/skills/codebase-audit/SKILL.md" = {
      text = skillCodebaseAudit;
      force = true;
    };
    "${claudeDir}/skills/caveman/SKILL.md" = {
      text = skillCaveman;
      force = true;
    };
    "${claudeDir}/skills/cavemem/SKILL.md" = {
      text = skillCavemem;
      force = true;
    };

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
    "${claudeDir}/hooks/stop-failure.sh" = {
      text = hookStopFailure;
      executable = true;
    };
    "${claudeDir}/hooks/circuit-breaker.js" = {
      text = hookCircuitBreaker;
      executable = true;
    };
    "${claudeDir}/hooks/circuit-breaker-reset.js" = {
      text = hookCircuitBreakerReset;
      executable = true;
    };
    "${claudeDir}/hooks/pre-compact-state.js" = {
      text = hookPreCompactState;
      executable = true;
    };
    "${claudeDir}/hooks/post-compact-restore.js" = {
      text = hookPostCompactRestore;
      executable = true;
    };
    "${claudeDir}/hooks/quality-gate.js" = {
      text = hookQualityGate;
      executable = true;
    };
    "${claudeDir}/hooks/governance-audit.js" = {
      text = hookGovernanceAudit;
      executable = true;
    };
    "${claudeDir}/hooks/rtk-rewrite.sh" = {
      text = hookRtkRewrite;
      executable = true;
    };
    "${claudeDir}/hooks/correction-capture.js" = {
      text = hookCorrectionCapture;
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
