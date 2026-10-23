{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  claudeDir = ".claude";

  # Import modular definitions
  settings = import ./claude-code/settings.nix { homeDirectory = config.home.homeDirectory; };
  commands = import ./claude-code/commands.nix;
  skillsManifest = import ./claude-code/skills-manifest.nix;
  graphifyReindex = import ./claude-code/graphify-reindex.nix { inherit pkgs; };
  vaultSnapshot = import ./claude-code/vault-snapshot.nix { inherit pkgs; };
  hooks = import ./claude-code/hooks.nix {
    inherit (graphifyReindex) graphifyReindexPkg;
    inherit (vaultSnapshot) vaultSnapshotPkg;
    inherit (settings) alxVaultPath;
  };
  agents = import ./claude-code/agents.nix;
  shell = import ./claude-code/shell.nix;
  claudeMd = import ./claude-code/claude-md.nix;
  rules = import ./claude-code/rules.nix;
  libdocs = import ./claude-code/libdocs.nix { inherit pkgs; };
  trello = import ./claude-code/trello.nix { inherit pkgs; };
  preprodCurl = import ./claude-code/preprod-curl.nix { inherit pkgs; };
  nixOptions = import ./claude-code/nix-options.nix { inherit pkgs; };
  scraplingShim = import ./claude-code/scrapling-shim.nix { inherit pkgs; };
  apexVerifyExternal = import ./claude-code/apex-verify-external.nix { inherit pkgs; };
  apexTier = import ./claude-code/apex-tier.nix { inherit pkgs; };
  apexHealth = import ./claude-code/apex-health.nix { inherit pkgs; };
  apexBoard = import ./claude-code/apex-board.nix { inherit pkgs; };
  claudeDispatch = import ./claude-code/claude-dispatch.nix { inherit pkgs; };
  agentPane = import ./claude-code/agent-pane.nix { inherit pkgs; };
  activationScripts = import ./claude-code/activation.nix {
    inherit pkgs lib;
    inherit (scraplingShim) scraplingShimPkg;
    modsSrc = ./claude-code/mods;
    modNames = (import ./claude-code/mods.nix).names;
  };

  inherit (claudeMd) claudeMdGlobal;
  inherit (rules) ruleNix ruleTypescript ruleReact;
  inherit (libdocs) libdocsPkg;
  inherit (trello) trelloPkg;
  inherit (preprodCurl) preprodCurlPkg;
  inherit (nixOptions) nixOptionsPkg;
  inherit (apexVerifyExternal) apexVerifyExternalPkg;
  inherit (apexTier) apexTierPkg;
  inherit (apexHealth) apexHealthPkg;
  inherit (apexBoard) apexBoardPkg;
  inherit (claudeDispatch) claudeDispatchPkg;
  inherit (agentPane) agentPanePkg;
  inherit (graphifyReindex) graphifyReindexPkg;
  inherit (vaultSnapshot) vaultSnapshotPkg;
  inherit (settings)
    settingsJson
    mcpServersJson
    keybindingsJson
    ;
  inherit (commands)
    cmdTdd
    cmdOptimize
    cmdContextPrime
    cmdAuto
    cmdCard
    commandDiscuss
    commandVerifyFeature
    featureChainScript
    ;
  inherit (hooks)
    hookProtectMain
    hookRequireApex
    hookApexFlags
    hookFormatTypescript
    hookBlockMainBash
    hookSessionStart
    hookGraphifyReindex
    hookVaultSnapshot
    hookApexReminder
    hookSubagentStop
    hookCompactContext
    hookStopFailure
    hookCircuitBreaker
    hookCircuitBreakerReset
    hookApexPrRecord
    hookQualityGate
    hookGovernanceAudit
    hookCorrectionBudget
    hookCorrectionGrant
    hookResearchModel
    hookLoneExcludedBash
    hookWorktreeInUse
    hookSandboxEscapeEvidence
    hookReactDocsGate
    hookNullResultGate
    hookInstagramWatch
    hookApexAcsProof
    ;
  hookWorktreeEnvSync = hooks.hookWorktreeEnvSync {
    jqBin = "${pkgs.jq}/bin/jq";
    gitBin = "${pkgs.git}/bin/git";
  };
  # Per-session state of an abduco session (dispatched agents), for
  # apex-board and the deck to read: see the header of the hook.
  hookSessionState = builtins.readFile ./claude-code/hooks/session-state.js;
  inherit (agents)
    agentFrontend
    agentBackend
    agentNavigator
    agentReviewer
    agentQuickFix
    agentNix
    agentGitShip
    agentTestRunner
    agentSecurityAuditor
    agentDebugger
    ;
  inherit (shell) aliases sessionVars;
  # Every skill file, derived from the manifest rather than typed out.
  #
  # `force` is COMPUTED, not stored: see the header of skills-manifest.nix.
  # It must stay true for every SKILL.md: claudeCodeDesymlinkSkills replaces
  # only `*/SKILL.md` with real copies, so home-manager has to be allowed to
  # clobber them. apex/eval-suite.json is NOT desymlinked; its `force` is not
  # required, kept as-is and harmless. A file under steps/ never carries it.
  skillFiles = builtins.listToAttrs (
    builtins.concatMap (
      skill:
      map (file: {
        name = "${claudeDir}/skills/${skill.name}/${file.path}";
        value = {
          inherit (file) text;
          force = baseNameOf file.path == "SKILL.md" || file.path == "eval-suite.json";
        };
      }) skill.files
    ) skillsManifest.manifest
  );

  # ui-expert skill: Emil Kowalski's UI/motion skills (emil-skills flake input,
  # pinned by commit), linked verbatim under the router SKILL.md that
  # skills-manifest.nix ships; no upstream file is rewritten. write-swift is
  # left out. Plain directory links, no `recursive`: desymlink only copies
  # `skills/*/SKILL.md` (activation.nix), one level deep, and Claude Code
  # discovers skills only at `skills/<name>/SKILL.md`
  # (https://code.claude.com/docs/en/skills), so the nested SKILL.md files are
  # neither rewritten nor loaded as separate skills: the router reads them.
  # The `*.backup` purge (find without -L) does not enter the links either.
  # pathExists turns a name missing upstream (bump, typo) into an eval error:
  # a dangling link would only fail the build, never `flake check --no-build`.
  uiExpertSkills = [
    "emil-design-eng"
    "animate"
    "animate-expo"
    "review-animations"
    "improve-animations"
    "find-animation-opportunities"
    "animation-performance"
    "animation-vocabulary"
    "apple-design"
    "pick-ui-library"
    "prototype"
    "mobile-native"
    "break-ui"
    "ask-sonner"
  ];
  uiExpertLinks =
    let
      link =
        rel:
        let
          src = "${inputs.emil-skills}/${rel}";
        in
        {
          source =
            if builtins.pathExists src then
              src
            else
              throw "ui-expert: ${rel} missing from the emil-skills input";
        };
    in
    builtins.listToAttrs (
      map (name: {
        name = "${claudeDir}/skills/ui-expert/${name}";
        value = link "skills/${name}";
      }) uiExpertSkills
    )
    // {
      "${claudeDir}/skills/ui-expert/LICENSE" = link "LICENSE";
      "${claudeDir}/skills/ui-expert/performance-cheatsheet.md" = link "performance-cheatsheet.md";
    };

  # Write ~/.claude content declaratively
  claudeHomeFiles = skillFiles // {
    # Settings base (read-only reference, merged by activation script)
    "${claudeDir}/settings-base.json" = {
      text = settingsJson;
    };

    # MCP servers base (merged into .claude.json by activation script)
    "${claudeDir}/mcp-servers-base.json" = {
      text = mcpServersJson;
    };

    # Keybindings (symlink store, comme les commands/agents : le CLI ne fait que
    # LIRE ce fichier au démarrage, et son écriture de template est en flag "wx"
    # → EEXIST géré, jamais d'écrasement). Modif = édition de settings.nix.
    "${claudeDir}/keybindings.json" = {
      text = keybindingsJson;
    };

    "${claudeDir}/CLAUDE.md" = {
      text = claudeMdGlobal;
    };

    # design-md skill library: one directory link to the pinned flake input
    # (~70 brands × DESIGN.md). Not in the manifest: it is data, not skill
    # text, and a single link keeps the desymlink loop (`*/SKILL.md`) and the
    # `*.backup` purge (find does not follow links) off it.
    "${claudeDir}/skills/design-md/library".source = "${inputs.awesome-design-md}/design-md";

    # /watch skill (claude-video, flake input pinned by commit). Third-party
    # code linked verbatim, outside skills-manifest.nix: the manifest takes no
    # argument and cannot see `inputs`, and the directory link keeps no
    # hand-made file list to drift. SKILL.md is its own entry with `force`:
    # desymlink turns it into a real copy, as for every manifest SKILL.md.
    # One upstream line changed: `allowed-tools: Bash` would pre-approve every
    # Bash call in the turn that reads attacker-controlled captions and
    # transcripts; narrowed to Read, Bash goes through the normal permission
    # path. The throw catches an upstream bump that moves the line.
    "${claudeDir}/skills/watch/SKILL.md" = {
      text =
        let
          upstream = builtins.readFile "${inputs.claude-video}/skills/watch/SKILL.md";
          granted = "allowed-tools: Bash, Read, AskUserQuestion\n";
        in
        if lib.hasInfix granted upstream then
          builtins.replaceStrings [ granted ] [ "allowed-tools: Read, AskUserQuestion\n" ] upstream
        else
          throw "watch SKILL.md: upstream allowed-tools line changed; re-audit it";
      force = true;
    };
    "${claudeDir}/skills/watch/scripts".source = "${inputs.claude-video}/skills/watch/scripts";

    # security-audit skill (Cloudflare, flake input pinned by commit): attack-class
    # library + six-phase audit workflow, linked verbatim. Upstream SKILL.md carries
    # no `allowed-tools`. `recursive`: real directories with linked leaves, so
    # desymlink can replace SKILL.md with a copy (a directory link would make it
    # `rm` inside the store); `force` lets home-manager clobber that copy.
    "${claudeDir}/skills/security-audit" = {
      source = "${inputs.cloudflare-security-audit}/skills/security-audit";
      recursive = true;
      force = true;
    };

    # brag skill (latent-spaces, flake input pinned by commit): launch video from
    # the project; bundles slim.md (brag-slim, picked on Opus 5.5), music/sfx
    # assets and a local librosa script. No `allowed-tools`, hooks or MCP.
    # `recursive` + `force` for the same desymlink reason as security-audit.
    "${claudeDir}/skills/brag" = {
      source = "${inputs.brag}/skills/brag";
      recursive = true;
      force = true;
    };

    # Rules (path-scoped, loaded on demand when a matching file is read)
    "${claudeDir}/rules/nix.md".text = ruleNix;
    "${claudeDir}/rules/typescript.md".text = ruleTypescript;
    "${claudeDir}/rules/react.md".text = ruleReact;

    # Commands
    "${claudeDir}/commands/tdd.md".text = cmdTdd;
    "${claudeDir}/commands/optimize.md".text = cmdOptimize;
    "${claudeDir}/commands/context-prime.md".text = cmdContextPrime;
    "${claudeDir}/commands/auto.md".text = cmdAuto;
    "${claudeDir}/commands/card.md".text = cmdCard;

    # Feature methodology commands
    "${claudeDir}/commands/discuss.md".text = commandDiscuss;
    "${claudeDir}/commands/verify-feature.md".text = commandVerifyFeature;

    # Skills come from skillFiles above, derived from skills-manifest.nix.

    # Feature chain script
    "${claudeDir}/feature-chain.sh" = {
      text = featureChainScript;
      executable = true;
    };

    # Agents (10)
    "${claudeDir}/agents/frontend-expert.md".text = agentFrontend;
    "${claudeDir}/agents/backend-expert.md".text = agentBackend;
    "${claudeDir}/agents/codebase-navigator.md".text = agentNavigator;
    "${claudeDir}/agents/code-reviewer.md".text = agentReviewer;
    "${claudeDir}/agents/quick-fix.md".text = agentQuickFix;
    "${claudeDir}/agents/nix-expert.md".text = agentNix;
    "${claudeDir}/agents/git-ship.md".text = agentGitShip;
    "${claudeDir}/agents/test-runner.md".text = agentTestRunner;
    "${claudeDir}/agents/security-auditor.md".text = agentSecurityAuditor;
    "${claudeDir}/agents/debugger.md".text = agentDebugger;

    # Hooks
    "${claudeDir}/hooks/protect-main.js" = {
      text = hookProtectMain;
      executable = true;
    };
    "${claudeDir}/hooks/require-apex.js" = {
      text = hookRequireApex;
      executable = true;
    };
    "${claudeDir}/hooks/apex-flags.js" = {
      text = hookApexFlags;
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
    "${claudeDir}/hooks/session-start.sh" = {
      text = hookSessionStart;
      executable = true;
    };
    "${claudeDir}/hooks/graphify-reindex.sh" = {
      text = hookGraphifyReindex;
      executable = true;
    };
    "${claudeDir}/hooks/vault-snapshot.sh" = {
      text = hookVaultSnapshot;
      executable = true;
    };
    "${claudeDir}/hooks/apex-reminder.sh" = {
      text = hookApexReminder;
      executable = true;
    };
    "${claudeDir}/hooks/subagent-stop.js" = {
      text = hookSubagentStop;
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
    "${claudeDir}/hooks/apex-pr-record.js" = {
      text = hookApexPrRecord;
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
    "${claudeDir}/hooks/correction-budget.js" = {
      text = hookCorrectionBudget;
      executable = true;
    };
    "${claudeDir}/hooks/correction-grant.js" = {
      text = hookCorrectionGrant;
      executable = true;
    };
    "${claudeDir}/hooks/research-model.js" = {
      text = hookResearchModel;
      executable = true;
    };
    "${claudeDir}/hooks/lone-excluded-bash.js" = {
      text = hookLoneExcludedBash;
      executable = true;
    };
    "${claudeDir}/hooks/worktree-in-use.js" = {
      text = hookWorktreeInUse;
      executable = true;
    };
    "${claudeDir}/hooks/sandbox-escape-evidence.js" = {
      text = hookSandboxEscapeEvidence;
      executable = true;
    };
    "${claudeDir}/hooks/react-docs-gate.js" = {
      text = hookReactDocsGate;
      executable = true;
    };
    "${claudeDir}/hooks/null-result-gate.js" = {
      text = hookNullResultGate;
      executable = true;
    };
    "${claudeDir}/hooks/worktree-env-sync.sh" = {
      text = hookWorktreeEnvSync;
      executable = true;
    };
    "${claudeDir}/hooks/session-state.js" = {
      text = hookSessionState;
      executable = true;
    };
    "${claudeDir}/hooks/instagram-watch.js" = {
      text = hookInstagramWatch;
      executable = true;
    };
    "${claudeDir}/hooks/apex-metrics-probe.py" = {
      text = hookApexAcsProof;
      executable = true;
    };
  };
in
{
  # Shell integration
  programs.zsh.shellAliases = aliases;
  programs.zsh.sessionVariables = sessionVars;

  # One-shot apex-health report, 1.5 weeks after the #235 effort/reviewer change:
  # writes the before/after verdict into the vault Inbox. launchd repeats a
  # Month/Day interval every year, so a marker file makes it run once.
  launchd.agents.apex-health-report = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "apex-health-report" ''
          marker="$HOME/.cache/apex-health-report.done"
          [ -e "$marker" ] && exit 0
          out="${settings.alxVaultPath}/01-Inbox/2026-10-21 - apex-health.md"
          {
            echo "# apex-health — $(date '+%F %H:%M')"
            echo
            echo '```'
            for repo in "$HOME/.config/nix-darwin" "$HOME/projects/Preliz"; do
              [ -d "$repo/.git" ] || continue
              echo "== $repo"
              ${apexHealthPkg}/bin/apex-health --repo "$repo"
              echo "exit=$?"
            done
            echo '```'
          } > "$out" 2>&1 && mkdir -p "$HOME/.cache" && touch "$marker"
        ''}"
      ];
      StartCalendarInterval = [
        {
          Month = 10;
          Day = 21;
          Hour = 9;
          Minute = 7;
        }
      ];
    };
  };

  home = {
    # npm global prefix (nix store is immutable, npm install -g needs a writable prefix)
    # ~/.local/bin = uv tool bin dir (`uv tool install` drops graphify/graphify-mcp there)
    sessionPath = [
      "$HOME/.npm-global/bin"
      "$HOME/.local/bin"
    ];

    # uiExpertLinks merged here, not in claudeHomeFiles: same set, and it
    # spares nixfmt re-indenting that whole attrset.
    file = claudeHomeFiles // uiExpertLinks;

    # `libdocs` + `nix-options` + `trello` + `preprod-curl` +
    # `graphify-reindex` + `claude-dispatch` + `agent-pane` on PATH — usable by
    # Claude, by APEX and its subagents, and by the user in a plain terminal.
    # `abduco` too, from the same pkgs as the claude-dispatch wrapper and
    # agent-pane (same default socket dir), so `abduco -a <name>` attaches to
    # a dispatched session, and `agent-pane` run in the top pane shows the
    # one last picked with `agent-pane pick <name>`.
    # home.packages is a list: this merges with the other home modules.
    packages = [
      libdocsPkg
      trelloPkg
      preprodCurlPkg
      nixOptionsPkg
      apexVerifyExternalPkg
      apexTierPkg
      apexHealthPkg
      apexBoardPkg
      claudeDispatchPkg
      pkgs.abduco
      agentPanePkg
      graphifyReindexPkg
      vaultSnapshotPkg
    ];

    # Activation scripts
    activation = activationScripts;
  };
}
