# Two Colima VMs, replacing Docker Desktop's runtime:
# - `ci`: self-hosted GitHub Actions runners for the private repos with a CI
#   (Preliz plan « plan-ci-rapide-et-gratuite », Phase 2B, validated by Preliz
#   PR #575). It runs k3s; k3s auto-deploys ARC from the manifest the provision
#   script writes, so a rebuilt VM reinstalls itself. Never active, no mounts.
# - `default`: dev containers (Preliz `preliz-pg`, …). It holds the active
#   Docker context `colima`, as Docker Desktop's `desktop-linux` did.
#
# ⚠️ The GitHub credentials are NOT here: they are a k8s secret the user
# creates by hand (`pre-defined-secret`, namespace `arc-runners`) for the
# GitHub App `arc-runners-alxwrtl` (no expiry): keys `github_app_id` (5365901),
# `github_app_installation_id` (172616492), `github_app_private_key` (.pem).
# It survives VM restarts, not `colima delete ci`. Listeners copy it once into
# their own `*-listener-config`: after changing it, run
# `kubectl -n arc-systems delete autoscalinglisteners --all` (ARC recreates them).
# ⚠️ No public repo here: a fork's pull request would run its code on this Mac.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  profileYaml = name: "${config.services.colima.colimaHomeDir}/${name}/colima.yaml";
  # the profiles the module would link a yaml for
  yamlProfiles = lib.filterAttrs (_: p: p.settings != { }) config.services.colima.profiles;
  arcVersion = "0.15.0";
  charts = "oci://ghcr.io/actions/actions-runner-controller-charts";
  # release name (= `runs-on:` label) → repository
  scaleSets = {
    preliz-mac = "Preliz";
    brasserie-mac = "brasserie-les-ecrivains";
    portfolio-mac = "portfolio";
  };
  helmChart = name: spec: {
    apiVersion = "helm.cattle.io/v1";
    kind = "HelmChart";
    metadata = {
      inherit name;
      namespace = "kube-system";
    };
    spec = {
      version = arcVersion;
      createNamespace = true;
    }
    // spec;
  };
  # JSON is YAML: one document per chart, no indentation to get wrong.
  manifest = lib.concatMapStringsSep "\n---\n" builtins.toJSON (
    [
      (helmChart "arc" {
        chart = "${charts}/gha-runner-scale-set-controller";
        targetNamespace = "arc-systems";
      })
    ]
    ++ lib.mapAttrsToList (
      name: repo:
      helmChart name {
        chart = "${charts}/gha-runner-scale-set";
        targetNamespace = "arc-runners";
        valuesContent = builtins.toJSON {
          githubConfigUrl = "https://github.com/AlxWrtl/${repo}";
          githubConfigSecret = "pre-defined-secret";
          minRunners = 0;
          # Preliz runs 4 parallel jobs (DB tests split in 2, 2026-11-23).
          maxRunners = if name == "preliz-mac" then 4 else 3;
        };
      }
    ) scaleSets
  );
  # colima-ci-watchdog's script (see the agent below).
  ciWatchdogScript = ''
    state="$HOME/.cache/colima-ci-watchdog"
    timeout 60 colima status ci >/dev/null 2>&1
    src=$?
    if [ "$src" -eq 0 ]; then
      rm -f "$state"
      exit 0
    fi
    # content = first-down epoch; mtime = last tick that saw the VM down
    now=$(date +%s)
    first=$(cat "$state" 2>/dev/null)
    case "$first" in
      "" | *[!0-9]*) first="" ;;
      *) first=$((10#$first)) ;;
    esac
    seen=$(stat -c %Y "$state" 2>/dev/null) || seen=0
    if [ -z "$first" ] || [ "$first" -gt "$now" ] || [ $((now - seen)) -gt 180 ]; then
      mkdir -p "$HOME/.cache" && printf '%s\n' "$now" > "$state"
      exit 0
    fi
    if [ $((now - first)) -lt 300 ]; then
      touch "$state" || echo "$(date '+%F %T') cannot touch $state" >&2
      exit 0
    fi
    since=$(date -d "@$first" '+%F %T' 2>/dev/null) || since="epoch $first"
    echo "$(date '+%F %T') ci VM down since $since (status rc=$src), restarting colima-ci" >&2
    /bin/launchctl kickstart -k gui/"$(id -u)"/org.nix-community.home.colima-ci
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "$(date '+%F %T') kickstart failed (exit $rc)" >&2
    fi
    if ! { mkdir -p "$HOME/.cache" && printf '%s\n' "$(date +%s)" > "$state"; }; then
      echo "$(date '+%F %T') cannot re-arm $state" >&2
    fi
    exit "$rc"
  '';
in
{
  services.colima = {
    enable = true;
    # Dev VM: the only active profile, so `docker` targets it by default. Own
    # containers only, never CI code, so Colima's default $HOME mount stays
    # (same exposure as Docker Desktop). No k3s, no ~/.ssh/config entry.
    # `setDockerHost` stays false: an exported DOCKER_HOST would override
    # `--context colima-ci`.
    profiles.default = {
      isService = true;
      isActive = true;
      setDockerHost = false;
      settings = {
        cpu = 2;
        memory = 2;
        disk = 20;
        arch = "aarch64";
        runtime = "docker";
        vmType = "vz";
        mountType = "virtiofs";
        sshConfig = false;
        autoActivate = true;
        kubernetes.enabled = false;
        # timesyncd's default 34 min poll lets the VM clock drift ~100 ms.
        provision = [
          {
            mode = "system";
            script = ''
              mkdir -p /etc/systemd/timesyncd.conf.d
              printf '[Time]\nPollIntervalMaxSec=64\n' > /etc/systemd/timesyncd.conf.d/poll.conf
              systemctl restart systemd-timesyncd
            '';
          }
        ];
      };
    };
    # CI VM: never takes the Docker/Kubernetes context (`default` holds it).
    profiles.ci = {
      isService = true;
      isActive = false;
      setDockerHost = false;
      settings = {
        # Only 2 DB shards + Security run here since Preliz #769: measured peak
        # 5523 MiB, + 30 % → 8 GB, 4 vCPUs (checks/colima-ci.nix 9); `default`
        # takes 2 + 2, the host keeps 6 GB. A colima.yaml change needs a VM
        # restart (the launchd plist does not change).
        cpu = 4;
        memory = 8;
        disk = 30;
        arch = "aarch64";
        runtime = "docker";
        vmType = "vz";
        mountType = "virtiofs";
        # No host directory in the VM: CI jobs run third-party code. `null` is
        # what `colima start --mount none` saves (measured on `ci-test`).
        mounts = null;
        sshConfig = false;
        autoActivate = false;
        kubernetes = {
          enabled = true;
          version = "v1.35.0+k3s1";
          k3sArgs = [ "--disable=traefik" ];
        };
        provision = [
          {
            mode = "system";
            script = ''
              mkdir -p /var/lib/rancher/k3s/server/manifests
              cat > /var/lib/rancher/k3s/server/manifests/arc.yaml <<'EOF'
              ${manifest}
              EOF
            '';
          }
        ];
      };
    };
  };

  # After a sleep, a listener keeps its dead long-poll for ~1 min and a job
  # offered meanwhile is lost: a new session never sees it, only a re-run does
  # (Preliz PR #701, 2026-11-04). On each wake, recreate the listeners at once.
  # A failed kubectl (VM not up yet) records nothing, so the next tick retries.
  launchd.agents.arc-wake-watchdog = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.writeShellScript "arc-wake-watchdog" ''
          state="$HOME/.cache/arc-wake-watchdog"
          wake=$(/usr/sbin/sysctl -n kern.waketime) || exit 0
          [ "$wake" = "$(cat "$state" 2>/dev/null)" ] && exit 0
          ${pkgs.kubectl}/bin/kubectl --context colima-ci --request-timeout=20s \
            -n arc-systems delete autoscalinglisteners --all || exit 0
          mkdir -p "$HOME/.cache" && printf '%s' "$wake" > "$state"
        ''}"
      ];
      StartInterval = 10;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/arc-wake-watchdog.log";
    };
  };

  # After the 2026-11-24 reboot the `ci` VM was Stopped while the launchd job
  # `colima-ci` stayed `running`: it never exited, so KeepAlive (which needs an
  # exit) could not relaunch it and CI jobs queued for 27 min and more. Every
  # minute, poll the VM; once it has been down 5 min (a start takes ~1 min, do
  # not kill it), `kickstart -k` the job, then wait 5 min again before the next;
  # a stamp older than 3 ticks (reboot, sleep) restarts the grace.
  # A deliberate `colima stop ci` is undone within ~5 min: for maintenance,
  # stop the watchdog too (`launchctl bootout
  # gui/$UID/org.nix-community.home.colima-ci-watchdog`). Jobs already queued
  # while the VM was down do not restart by themselves (listener "assigned
  # job=0"): `gh run cancel`, then `gh run rerun --failed`. Guarded by
  # checks/colima-ci.nix 10. Unlike arc-wake-watchdog, the script is inline
  # (`bash -c`): that check reads its text at eval time, and
  # `nix flake check --no-build` cannot read a not-yet-built writeShellScript.
  launchd.agents.colima-ci-watchdog = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        ciWatchdogScript
      ];
      EnvironmentVariables = config.launchd.agents.colima-ci.config.EnvironmentVariables;
      StartInterval = 60;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/colima-ci-watchdog.log";
    };
  };

  # `colima start <profile>` rewrites its colima.yaml and fails on the module's
  # read-only store symlink: install writable copies instead, reset each switch.
  home.file = lib.mapAttrs' (
    name: _: lib.nameValuePair (profileYaml name) { enable = false; }
  ) yamlProfiles;
  home.activation.colimaYaml = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    lib.concatStrings (
      lib.mapAttrsToList (name: profile: ''
        target="$HOME/${profileYaml name}"
        if [ -L "$target" ]; then run rm -f "$target"; fi
        run mkdir -p "$(dirname "$target")"
        run cp ${(pkgs.formats.yaml { }).generate "colima.yaml" profile.settings} "$target"
        run chmod u+w "$target"
      '') yamlProfiles
    )
  );
}
