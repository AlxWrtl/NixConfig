# Self-hosted GitHub Actions runners for the private repos with a CI
# (Preliz plan « plan-ci-rapide-et-gratuite », Phase 2B, validated by Preliz
# PR #575). One Colima VM `ci` runs k3s; k3s auto-deploys ARC from the
# manifest the provision script writes, so a rebuilt VM reinstalls itself.
#
# ⚠️ The GitHub credentials are NOT here: they are a k8s secret the user
# creates by hand (`pre-defined-secret`, namespace `arc-runners`) for the
# GitHub App `arc-runners-alxwrtl` (no expiry): keys `github_app_id` (5365901),
# `github_app_installation_id` (172616492), `github_app_private_key` (.pem).
# It survives VM restarts, not `colima delete ci`. Listeners copy it once into
# their own `*-listener-config`: after changing it, run
# `kubectl -n arc-systems delete autoscalinglisteners --all` (ARC recreates them).
# ⚠️ No public repo here: a fork's pull request would run its code on this Mac.
{ lib, ... }:
let
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
    # Replaces the module's default profile: `ci` is the only VM, and it never
    # takes the Docker/Kubernetes context (Docker Desktop keeps `desktop-linux`).
    profiles.ci = {
      isService = true;
      isActive = false;
      setDockerHost = false;
      settings = {
        cpu = 4;
        memory = 7;
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
}
