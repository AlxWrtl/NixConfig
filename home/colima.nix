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
  defaultYaml = "${config.services.colima.colimaHomeDir}/default/colima.yaml";
  arcVersion = "0.15.0";
  charts = "oci://ghcr.io/actions/actions-runner-controller-charts";
  # release name (= `runs-on:` label) → repository
  scaleSets = {
    preliz-mac = "Preliz";
    browser-mac = "browser";
    brasserie-mac = "brasserie-les-ecrivains";
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
          maxRunners = 3;
        };
      }
    ) scaleSets
  );
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
        # 6 of the M1's 8 cores, 8 of its 16 GB: room freed by Docker Desktop's
        # removal; `default` takes 2 + 2. A colima.yaml change needs a VM
        # restart (the launchd plist does not change). `colima restart ci` and
        # `colima start ci` fail on this read-only yaml: run `colima stop ci`,
        # then `launchctl kickstart -k gui/$UID/org.nix-community.home.colima-ci`.
        cpu = 6;
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

  # `colima start default` rewrites its colima.yaml and fails on the module's
  # read-only store symlink: install a writable copy instead, reset each switch.
  home.file.${defaultYaml}.enable = false;
  home.activation.colimaDefaultYaml = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    target="$HOME/${defaultYaml}"
    if [ -L "$target" ]; then run rm -f "$target"; fi
    run mkdir -p "$(dirname "$target")"
    run cp ${
      (pkgs.formats.yaml { }).generate "colima.yaml" config.services.colima.profiles.default.settings
    } "$target"
    run chmod u+w "$target"
  '';
}
