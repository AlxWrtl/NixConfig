# Guard for the Colima VMs (home/colima.nix), on the REAL config.
#
# Evaluation-time check: a `runCommand … exit 1` would not run under
# `--no-build`, so the failures are computed here and `throw`n when non-empty.
# Each invariant keeps a CI job from reaching the Mac or the Docker context:
#
# 1. Exactly the `ci` and `default` profiles exist. A third VM would cost RAM
#    and could take the Docker context.
# 2. `isActive`/`setDockerHost` false: `--activate=true` would steal the dev
#    VM's context (`colima`) at every login. `isService` true: the VM must
#    start by itself, or the runners never come up.
# 3. `mounts = null`: a host mount lets CI code (third-party for forks) read
#    $HOME. `sshConfig = false`: colima would write ~/.ssh/config.
#    `autoActivate = false`: same context theft, from colima's own side.
#    `kubernetes.enabled`: ARC lives in k3s.
# 4. The provision script carries the ARC version, one HelmChart per label, and
#    no public repo (a fork's pull request would run on this Mac).
# 5. The launchd agent really passes `--activate=false`: the settings above are
#    worthless if the generated command line says otherwise.
# 6. `default` (dev VM, replaces Docker Desktop): active and a service, so
#    `docker` reaches it at login without `--context`; its agent passes
#    `--activate=true`. `setDockerHost` false: DOCKER_HOST would override
#    `--context colima-ci`. No k3s, no ~/.ssh/config entry.
# 7. No profile's colima.yaml is a home.file symlink: `colima start` rewrites
#    it and fails on a read-only store path (an activation copies it instead).
# 8. `arc-wake-watchdog` polls at most every 10 s: after a sleep, a listener
#    keeps a dead long-poll for ~1 min and a job offered to it is lost.
# 9. `preliz-mac` scales to 4 runners: 2 DB shards + gitleaks + osv-scanner
#    (Gate, Static, E2E moved to GitHub-hosted runners, Preliz #769). Peak
#    measured 2026-11-24 (CI 45385722107 attempt 5 + Security 45385721612,
#    `free -m` in the VM every 5 s): 5523 MiB used, k3s included. `ci` memory
#    is at least that + 30 %, rounded up (no swap in the VM: less risks an OOM
#    kill), cpu at least 4 (6.1 cores peak for ~30 s of 8 min); `ci` + `default`
#    stay <= 12 GB so the host keeps 4 of its 16. Not measured: brasserie-mac,
#    portfolio-mac and Preliz backup.yml (nightly); whether they overlap the
#    DB shards is unknown.
# 10. `colima-ci-watchdog` restarts the `ci` VM when it stays down. On
#    2026-11-24, after a reboot, the VM was Stopped while the launchd job
#    `colima-ci` stayed `running`: it never exited, so KeepAlive could not
#    relaunch it, and CI jobs queued 27 min and more. The watchdog polls
#    `colima status ci` (StartInterval 30..300 s) with the `colima-ci` agent's
#    own EnvironmentVariables (same PATH and COLIMA_HOME, reused, not copied),
#    and kickstarts `org.nix-community.home.colima-ci` with `-k` (kill the
#    stuck job first). Its script is inline (`bash -c <text>`), never a
#    writeShellScript: `nix flake check --no-build` writes no new .drv, so a
#    script not built yet cannot be read at eval time ("path … .drv is not
#    valid", measured 2026-11-25). The text is plain ProgramArguments[2].
#    Its behaviour (grace, stale stamp, kickstart) is graded by the manual
#    checks/colima-ci-watchdog-probe.sh, run outside the sandbox.
{
  pkgs,
  hm,
}:

let
  inherit (pkgs) lib;

  colima = hm.services.colima;
  ci = colima.profiles.ci or null;

  arcVersion = "0.15.0";
  labels = [
    "preliz-mac"
    "brasserie-mac"
    "portfolio-mac"
  ];
  publicRepos = [ "NixConfig" ];
  # Item 9: VM peak measured 2026-11-24; ceil(peak × 1.3 / 1024) in GB.
  measuredPeakMiB = 5523;
  ciMinMemoryGB = (measuredPeakMiB * 13 + 10239) / 10240;

  settings = if ci == null then { } else ci.settings;
  script =
    if ci == null || (settings.provision or [ ]) == [ ] then
      ""
    else
      (builtins.head settings.provision).script;
  agent = hm.launchd.agents.colima-ci.config or null;
  agentArgs = if agent == null then [ ] else agent.ProgramArguments or [ ];
  wakeAgent = hm.launchd.agents.arc-wake-watchdog.config or { };

  # Item 10: the script is inline, `[ <…>/bin/bash "-c" <text> ]`. A
  # writeShellScript's text cannot be read under `nix flake check --no-build`:
  # neither its .drv nor (by IFD) its output exists for a script not built yet
  # (measured 2026-11-25). Plain eval of ProgramArguments[2], no store read.
  ciLabel = "org.nix-community.home.colima-ci";
  # One needle for verb, flag, domain and label: separate ones would accept
  # `kickstart -k gui/<uid>/<other label>` beside a stray mention of ciLabel.
  ciVmWatchdogKick = ''/bin/launchctl kickstart -k gui/"$(id -u)"/${ciLabel}'';
  ciVmWatchdog = hm.launchd.agents.colima-ci-watchdog or null;
  ciVmWatchdogConfig = if ciVmWatchdog == null then { } else ciVmWatchdog.config or { };
  ciVmWatchdogArgs = ciVmWatchdogConfig.ProgramArguments or [ ];
  ciVmWatchdogShape = builtins.isList ciVmWatchdogArgs && builtins.length ciVmWatchdogArgs == 3;
  ciVmWatchdogArg = n: if ciVmWatchdogShape then builtins.elemAt ciVmWatchdogArgs n else null;
  ciVmWatchdogBash = ciVmWatchdogArg 0;
  ciVmWatchdogBashOk =
    builtins.isString ciVmWatchdogBash && lib.hasSuffix "/bin/bash" ciVmWatchdogBash;
  ciVmWatchdogDashC = ciVmWatchdogArg 1 == "-c";
  ciVmWatchdogText =
    if ciVmWatchdogBashOk && ciVmWatchdogDashC && builtins.isString (ciVmWatchdogArg 2) then
      ciVmWatchdogArg 2
    else
      "";
  # `org.nix-community.home.colima-ci-watchdog` contains the target label:
  # drop the longer labels so only the real target can satisfy the needle.
  ciVmWatchdogTextNoSuffix =
    builtins.replaceStrings [ "${ciLabel}-" "colima status ci-" ] [ "" "" ]
      ciVmWatchdogText;
  ciVmWatchdogInterval = ciVmWatchdogConfig.StartInterval or null;
  ciAgentEnv = if agent == null then null else agent.EnvironmentVariables or null;

  dev = colima.profiles.default or null;
  devSettings = if dev == null then { } else dev.settings;
  devAgent = hm.launchd.agents.colima-default.config or null;
  devAgentArgs = if devAgent == null then [ ] else devAgent.ProgramArguments or [ ];

  prelizDocs = builtins.filter (lib.hasInfix ''"name":"preliz-mac"'') (
    lib.splitString "\n---\n" script
  );

  failures =
    lib.optional
      (
        builtins.attrNames colima.profiles != [
          "ci"
          "default"
        ]
      )
      "profiles are ${builtins.toJSON (builtins.attrNames colima.profiles)}, expected exactly [ \"ci\" \"default\" ]"
    ++ lib.optionals (ci != null) (
      lib.optional (
        ci.isActive != false
      ) "ci.isActive must be false (would steal the dev VM's Docker context)"
      ++ lib.optional (ci.setDockerHost != false) "ci.setDockerHost must be false"
      ++ lib.optional (ci.isService != true) "ci.isService must be true (the VM must start at login)"
      ++ lib.optional (
        (settings.mounts or 1) != null
      ) "settings.mounts must be null (a host mount lets CI code read $HOME)"
      ++ lib.optional (
        (settings.sshConfig or null) != false
      ) "settings.sshConfig must be false (colima would write ~/.ssh/config)"
      ++ lib.optional (
        (settings.autoActivate or null) != false
      ) "settings.autoActivate must be false (would steal the Docker context)"
      ++ lib.optional (
        (settings.kubernetes.enabled or null) != true
      ) "settings.kubernetes.enabled must be true (ARC runs in k3s)"
      ++ lib.optional (
        !(lib.hasInfix ''"version":"${arcVersion}"'' script)
      ) "provision script lacks the ARC version ${arcVersion}"
      ++ map (l: "provision script lacks a HelmChart named ${l}") (
        builtins.filter (l: !(lib.hasInfix ''"name":"${l}"'' script)) labels
      )
      ++ map (
        r: "provision script names the public repo ${r}: a fork's pull request would run on this Mac"
      ) (builtins.filter (r: lib.hasInfix r script) publicRepos)
    )
    ++ lib.optional (
      !(builtins.any (lib.hasInfix ''\"maxRunners\":4,'') prelizDocs)
    ) "preliz-mac must scale to maxRunners 4 (Preliz runs 4 parallel jobs)"
    ++
      lib.optional ((settings.memory or 0) < ciMinMemoryGB)
        "ci memory must be >= ${toString ciMinMemoryGB} GB (measured peak ${toString measuredPeakMiB} MiB + 30 %, 2026-11-24, no swap in the VM)"
    ++ lib.optional (
      (settings.cpu or 0) < 4
    ) "ci cpu must be >= 4 (DB shards + Security, measured 2026-11-24)"
    ++ lib.optional (
      (settings.memory or 0) + (devSettings.memory or 0) > 12
    ) "ci + default memory must be <= 12 GB (the host keeps 4 of its 16 GB)"
    ++ lib.optional (ci == null) "no `ci` profile"
    ++ lib.optional (agent == null) "launchd agent colima-ci is missing"
    ++ lib.optional (
      agent != null && !(builtins.elem "--activate=false" agentArgs)
    ) "launchd agent colima-ci lacks --activate=false in ProgramArguments"
    ++ lib.optionals (dev != null) (
      lib.optional (
        dev.isActive != true
      ) "default.isActive must be true (docker must reach the dev VM without --context)"
      ++ lib.optional (
        dev.setDockerHost != false
      ) "default.setDockerHost must be false (DOCKER_HOST would override --context colima-ci)"
      ++ lib.optional (
        dev.isService != true
      ) "default.isService must be true (the dev VM must start at login)"
      ++ lib.optional (
        (devSettings.kubernetes.enabled or false) == true
      ) "default settings.kubernetes.enabled must not be true (k3s belongs to ci)"
      ++ lib.optional (
        (devSettings.sshConfig or null) != false
      ) "default settings.sshConfig must be false (colima would write ~/.ssh/config)"
    )
    ++ lib.optional (dev == null) "no `default` profile"
    ++ map (p: "${p} colima.yaml is a home.file symlink: colima start cannot rewrite it") (
      builtins.filter (p: (hm.home.file."${colima.colimaHomeDir}/${p}/colima.yaml".enable or false)) (
        builtins.attrNames colima.profiles
      )
    )
    ++
      lib.optional ((wakeAgent.StartInterval or 999) > 10)
        "launchd agent arc-wake-watchdog missing or slower than 10 s: a job offered to a dead listener session after a wake is lost"
    ++
      lib.optional (ciVmWatchdog == null)
        "launchd agent colima-ci-watchdog is missing: a Stopped ci VM under a still-running colima-ci job is never restarted (KeepAlive needs an exit, 2026-11-24)"
    ++ lib.optionals (ciVmWatchdog != null) (
      lib.optional (
        (ciVmWatchdog.enable or false) != true
      ) "launchd agent colima-ci-watchdog must be enabled"
      ++ lib.optional (
        !(builtins.isInt ciVmWatchdogInterval && ciVmWatchdogInterval >= 30 && ciVmWatchdogInterval <= 300)
      ) "launchd agent colima-ci-watchdog StartInterval must be an integer in 30..300 s"
      ++ lib.optional (
        !(lib.hasPrefix "${hm.home.homeDirectory}/Library/Logs/" (
          ciVmWatchdogConfig.StandardErrorPath or ""
        ))
      ) "launchd agent colima-ci-watchdog StandardErrorPath must be under ~/Library/Logs/"
      ++
        lib.optional
          (
            ciAgentEnv == null
            || ciAgentEnv == { }
            || (ciVmWatchdogConfig.EnvironmentVariables or null) != ciAgentEnv
          )
          "launchd agent colima-ci-watchdog EnvironmentVariables must equal colima-ci's (its colima PATH and COLIMA_HOME)"
      ++
        lib.optional (!ciVmWatchdogShape)
          "launchd agent colima-ci-watchdog ProgramArguments must be exactly [ <bash> \"-c\" <script> ] (the inline script is what this check reads)"
      ++ lib.optional (
        ciVmWatchdogShape && !ciVmWatchdogBashOk
      ) "launchd agent colima-ci-watchdog ProgramArguments[0] must end in /bin/bash"
      ++ lib.optional (
        ciVmWatchdogShape && !ciVmWatchdogDashC
      ) "launchd agent colima-ci-watchdog ProgramArguments[1] must be \"-c\""
      ++ lib.optional (
        ciVmWatchdogShape && !(builtins.isString (ciVmWatchdogArg 2))
      ) "launchd agent colima-ci-watchdog ProgramArguments[2] must be the script text"
      ++ lib.optional (
        !(lib.hasInfix "colima status ci" ciVmWatchdogTextNoSuffix)
      ) "colima-ci-watchdog script must poll `colima status ci`"
      ++
        lib.optional (!(lib.hasInfix ciVmWatchdogKick ciVmWatchdogTextNoSuffix))
          "colima-ci-watchdog script must run exactly `${ciVmWatchdogKick}` (-k kills the stuck colima-ci job first; the label must be colima-ci's)"
    )
    ++ lib.optional (devAgent == null) "launchd agent colima-default is missing"
    ++ lib.optional (
      devAgent != null && !(builtins.elem "--activate=true" devAgentArgs)
    ) "launchd agent colima-default lacks --activate=true in ProgramArguments";
in
if failures != [ ] then
  throw ("colima-ci:\n  - " + builtins.concatStringsSep "\n  - " failures)
else
  pkgs.runCommand "check-colima-ci" { } "touch $out"
