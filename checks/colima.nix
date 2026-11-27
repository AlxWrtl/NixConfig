# Guard for the Colima dev VM (home/colima.nix), on the REAL config.
#
# Evaluation-time check: a `runCommand … exit 1` would not run under
# `--no-build`, so the failures are computed here and `throw`n when non-empty.
# `default` holds Preliz's local DB container (`pnpm localdb:start`).
#
# 1. Exactly the `default` profile exists: another VM costs RAM and could take
#    the Docker context.
# 2. `default` is active and a service, so `docker` reaches it at login without
#    `--context`; its launchd agent really passes `--activate=true`.
#    `setDockerHost` false: no exported DOCKER_HOST. `sshConfig` false: colima
#    would write ~/.ssh/config. `autoActivate` true: colima keeps the context.
#    No k3s.
# 3. No leftover launchd agent of a removed VM (`colima-ci`,
#    `colima-ci-watchdog`, `arc-wake-watchdog`).
# 4. No profile's colima.yaml is a home.file symlink: `colima start` rewrites
#    it and fails on a read-only store path (an activation copies it instead).
{
  pkgs,
  hm,
}:

let
  inherit (pkgs) lib;

  colima = hm.services.colima;
  profileNames = builtins.attrNames colima.profiles;

  dev = colima.profiles.default or null;
  devSettings = if dev == null then { } else dev.settings;
  devAgent = hm.launchd.agents.colima-default.config or null;
  devAgentArgs = if devAgent == null then [ ] else devAgent.ProgramArguments or [ ];

  goneAgents = [
    "colima-ci"
    "colima-ci-watchdog"
    "arc-wake-watchdog"
  ];

  failures =
    lib.optional (
      profileNames != [ "default" ]
    ) "profiles are ${builtins.toJSON profileNames}, expected exactly [ \"default\" ]"
    ++ lib.optional (dev == null) "no `default` profile"
    ++ lib.optionals (dev != null) (
      lib.optional (
        dev.isActive != true
      ) "default.isActive must be true (docker must reach the dev VM without --context)"
      ++ lib.optional (
        dev.isService != true
      ) "default.isService must be true (the dev VM must start at login)"
      ++ lib.optional (dev.setDockerHost != false) "default.setDockerHost must be false"
      ++ lib.optional (
        (devSettings.sshConfig or null) != false
      ) "default settings.sshConfig must be false (colima would write ~/.ssh/config)"
      ++ lib.optional (
        (devSettings.autoActivate or null) != true
      ) "default settings.autoActivate must be true (colima keeps the Docker context)"
      ++ lib.optional (
        (devSettings.kubernetes.enabled or false) == true
      ) "default settings.kubernetes.enabled must not be true"
    )
    ++ lib.optional (devAgent == null) "launchd agent colima-default is missing"
    ++ lib.optional (
      devAgent != null && !(builtins.elem "--activate=true" devAgentArgs)
    ) "launchd agent colima-default lacks --activate=true in ProgramArguments"
    ++ map (a: "launchd agent ${a} must not exist (its VM is removed)") (
      builtins.filter (a: hm.launchd.agents ? ${a}) goneAgents
    )
    ++ map (p: "${p} colima.yaml is a home.file symlink: colima start cannot rewrite it") (
      builtins.filter (
        p: (hm.home.file."${colima.colimaHomeDir}/${p}/colima.yaml".enable or false)
      ) profileNames
    );
in
if failures != [ ] then
  throw ("colima:\n  - " + builtins.concatStringsSep "\n  - " failures)
else
  pkgs.runCommand "check-colima" { } "touch $out"
