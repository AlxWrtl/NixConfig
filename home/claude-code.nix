{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Target dir managed by this module
  claudeDir = ".claude";

  # Import modular definitions
  docs = import ./claude-code/docs.nix;
  settings = import ./claude-code/settings.nix;
  commands = import ./claude-code/commands.nix;
  skills = import ./claude-code/skills.nix;
  hooks = import ./claude-code/hooks.nix;
  agents = import ./claude-code/agents.nix;
  activationScripts = import ./claude-code/activation.nix { inherit pkgs lib; };

  # Merge all definitions
  inherit (docs) claudeMdText autoRoutingText;
  inherit (settings) settingsJson statuslineScript;
  inherit (commands)
    cmdTdd
    cmdOptimize
    cmdContextPrime
    cmdAuto
    cmdRalphLoop
    cmdCancelRalph
    cmdInitMemoryBank
    ;
  inherit (skills)
    skillApex
    apexStep00
    apexStep01
    apexStep02
    apexStep03
    apexStep04
    apexStep05
    apexStep06
    apexStep07
    apexStep08
    apexStep09
    skillDebug
    debugStep01
    debugStep02
    debugStep03
    debugStep04
    debugStep05
    skillContinuousLearning
    ;
  inherit (hooks) hookProtectMain hookFormatTypescript;
  inherit (agents)
    agentFrontend
    agentBackend
    agentDatabase
    agentDevops
    agentAiMl
    agentArch
    agentPerf
    agentNavigator
    agentReviewer
    agentQuickFix
    agentNix
    agentGitShip
    ;
in
{
  # -------------------------
  # Zsh convenience
  # -------------------------
  programs.zsh.shellAliases = {
    cc = "claude";
    ccd = "claude /doctor";
    ccv = "claude --version";
    ccro = "claude --plan-mode --read-only";
  };

  programs.zsh.sessionVariables = {
    CLAUDE_CONFIG_DIR = "$HOME/.claude";
    npm_config_prefer_pnpm = "true";
    npm_config_user_agent = "pnpm";
  };

  # -------------------------
  # Write ~/.claude content declaratively
  # -------------------------
  home.file = {
    # Settings base (read-only reference)
    "${claudeDir}/settings-base.json" = {
      text = settingsJson;
    };

    "${claudeDir}/CLAUDE.md" = {
      text = claudeMdText;
    };

    "${claudeDir}/auto-routing.md" = {
      text = autoRoutingText;
    };

    # Commands
    "${claudeDir}/commands/tdd.md" = {
      text = cmdTdd;
    };
    "${claudeDir}/commands/optimize.md" = {
      text = cmdOptimize;
    };
    "${claudeDir}/commands/context-prime.md" = {
      text = cmdContextPrime;
    };
    "${claudeDir}/commands/auto.md" = {
      text = cmdAuto;
    };
    "${claudeDir}/commands/init-memory-bank.md" = {
      text = cmdInitMemoryBank;
    };
    "${claudeDir}/commands/ralph-loop.md" = {
      text = cmdRalphLoop;
    };
    "${claudeDir}/commands/cancel-ralph.md" = {
      text = cmdCancelRalph;
    };

    # Agents
    "${claudeDir}/agents/frontend-expert.md" = {
      text = agentFrontend;
    };
    "${claudeDir}/agents/backend-expert.md" = {
      text = agentBackend;
    };
    "${claudeDir}/agents/database-expert.md" = {
      text = agentDatabase;
    };
    "${claudeDir}/agents/devops-expert.md" = {
      text = agentDevops;
    };
    "${claudeDir}/agents/ai-ml-expert.md" = {
      text = agentAiMl;
    };
    "${claudeDir}/agents/architecture-expert.md" = {
      text = agentArch;
    };
    "${claudeDir}/agents/performance-expert.md" = {
      text = agentPerf;
    };
    "${claudeDir}/agents/codebase-navigator.md" = {
      text = agentNavigator;
    };
    "${claudeDir}/agents/code-reviewer.md" = {
      text = agentReviewer;
    };
    "${claudeDir}/agents/quick-fix.md" = {
      text = agentQuickFix;
    };
    "${claudeDir}/agents/nix-expert.md" = {
      text = agentNix;
    };
    "${claudeDir}/agents/git-ship.md" = {
      text = agentGitShip;
    };

    # APEX Skill
    "${claudeDir}/skills/apex/SKILL.md" = {
      text = skillApex;
    };
    "${claudeDir}/skills/apex/steps/00-init.md" = {
      text = apexStep00;
    };
    "${claudeDir}/skills/apex/steps/01-analyze.md" = {
      text = apexStep01;
    };
    "${claudeDir}/skills/apex/steps/02-plan.md" = {
      text = apexStep02;
    };
    "${claudeDir}/skills/apex/steps/03-prepare.md" = {
      text = apexStep03;
    };
    "${claudeDir}/skills/apex/steps/04-execute.md" = {
      text = apexStep04;
    };
    "${claudeDir}/skills/apex/steps/05-test.md" = {
      text = apexStep05;
    };
    "${claudeDir}/skills/apex/steps/06-examine.md" = {
      text = apexStep06;
    };
    "${claudeDir}/skills/apex/steps/07-polish.md" = {
      text = apexStep07;
    };
    "${claudeDir}/skills/apex/steps/08-document.md" = {
      text = apexStep08;
    };
    "${claudeDir}/skills/apex/steps/09-finish.md" = {
      text = apexStep09;
    };

    # Debug Skill
    "${claudeDir}/skills/debug/SKILL.md" = {
      text = skillDebug;
    };
    "${claudeDir}/skills/debug/steps/01-reproduce.md" = {
      text = debugStep01;
    };
    "${claudeDir}/skills/debug/steps/02-isolate.md" = {
      text = debugStep02;
    };
    "${claudeDir}/skills/debug/steps/03-diagnose.md" = {
      text = debugStep03;
    };
    "${claudeDir}/skills/debug/steps/04-fix.md" = {
      text = debugStep04;
    };
    "${claudeDir}/skills/debug/steps/05-verify.md" = {
      text = debugStep05;
    };

    # Continuous Learning V2
    "${claudeDir}/skills/continuous-learning-v2/SKILL.md" = {
      text = skillContinuousLearning;
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

    # Statusline script
    "${claudeDir}/statusline.sh" = {
      text = statuslineScript;
      executable = true;
    };
  };

  # Import activation scripts
  home.activation = activationScripts;
}
