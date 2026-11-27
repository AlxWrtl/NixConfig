# Colima dev VM `default`, replacing Docker Desktop's runtime: dev containers
# (Preliz `preliz-pg`, …). It holds the active Docker context `colima`, as
# Docker Desktop's `desktop-linux` did.
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
in
{
  services.colima = {
    enable = true;
    # The only active profile, so `docker` targets it by default. Own
    # containers only, so Colima's default $HOME mount stays (same exposure as
    # Docker Desktop). No k3s, no ~/.ssh/config entry. `setDockerHost` stays
    # false: the Docker context selects the VM, an exported DOCKER_HOST would
    # override it.
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
