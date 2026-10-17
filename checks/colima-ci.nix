# Guard for the self-hosted CI runners (home/colima.nix), on the REAL config.
#
# Evaluation-time check: a `runCommand … exit 1` would not run under
# `--no-build`, so the failures are computed here and `throw`n when non-empty.
# Each invariant keeps a CI job from reaching the Mac or the Docker context:
#
# 1. Only the `ci` profile exists. The module's default profile would start a
#    second VM and, being active, take over the Docker context.
# 2. `isActive`/`setDockerHost` false: `--activate=true` would steal Docker
#    Desktop's context (`desktop-linux`) at every login. `isService` true: the
#    VM must start by itself, or the runners never come up.
# 3. `mounts = null`: a host mount lets CI code (third-party for forks) read
#    $HOME. `sshConfig = false`: colima would write ~/.ssh/config.
#    `autoActivate = false`: same context theft, from colima's own side.
#    `kubernetes.enabled`: ARC lives in k3s.
# 4. The provision script carries the ARC version, one HelmChart per label, and
#    no public repo (a fork's pull request would run on this Mac).
# 5. The launchd agent really passes `--activate=false`: the settings above are
#    worthless if the generated command line says otherwise.
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
    "browser-mac"
    "brasserie-mac"
  ];
  publicRepos = [ "NixConfig" ];

  settings = if ci == null then { } else ci.settings;
  script =
    if ci == null || (settings.provision or [ ]) == [ ] then
      ""
    else
      (builtins.head settings.provision).script;
  agent = hm.launchd.agents.colima-ci.config or null;
  agentArgs = if agent == null then [ ] else agent.ProgramArguments or [ ];

  failures =
    lib.optional (builtins.attrNames colima.profiles != [ "ci" ])
      "profiles are ${builtins.toJSON (builtins.attrNames colima.profiles)}, expected exactly [ \"ci\" ] (a default profile would take the Docker context)"
    ++ lib.optionals (ci != null) (
      lib.optional (
        ci.isActive != false
      ) "ci.isActive must be false (would steal Docker Desktop's context)"
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
    ++ lib.optional (ci == null) "no `ci` profile"
    ++ lib.optional (agent == null) "launchd agent colima-ci is missing"
    ++ lib.optional (
      agent != null && !(builtins.elem "--activate=false" agentArgs)
    ) "launchd agent colima-ci lacks --activate=false in ProgramArguments";
in
if failures != [ ] then
  throw ("colima-ci:\n  - " + builtins.concatStringsSep "\n  - " failures)
else
  pkgs.runCommand "check-colima-ci" { } "touch $out"
