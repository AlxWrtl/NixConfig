# Self-hosted GitHub Actions runner `browser-macos` for the private repo
# AlxWrtl/browser, guarded by checks/github-runner.nix.
#
# Hand-written rather than `services.github-runners`: that module asserts
# `nix.enable`, which is false under Determinate Nix.
#
# The daemon runs as root only to read the PAT (root:wheel 0400) and trade it
# for a single-use just-in-time runner config: the PAT reaches curl on stdin
# (`--config -`), never through an argv or the environment. Runner.Listener
# runs as `_github-runner` through sudo, so job code never sees the PAT. sudo
# resets the environment, hence the explicit /usr/bin/env assignments.
#
# Root never creates, chowns or chmods anything inside a `_github-runner`
# dir: activation touches only the dirs themselves (`-h`), whose parents are
# root-owned 0755; everything below them is created or wiped as the runner.
#
# TCC charges a launchd job to the first binary launchd runs (/bin/sh by
# default), so jobs needing Full Disk Access start through a compiled launcher
# at a fixed root-owned path, to which the user grants Full Disk Access by
# hand; it execs `.d/start`, a link to the generated start script. Root-only
# (0700, no ACL): any user running it, DYLD_INSERT_LIBRARIES included, would
# act with its Full Disk Access.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  name = "browser-macos";
  svc = "github-runner-${name}";
  account = "_github-runner";
  root = "/var/lib/github-runners";
  stateDir = "${root}/${name}";
  logDir = "/var/log/github-runners/${name}";
  # /var links to /private/var: actions/checkout keys its credentials on the
  # workspace path in an includeIf gitdir, which git matches on the real path.
  workDir = "/private${root}/_work/${name}";
  cacheDir = "${root}/_cache/${name}";
  rustupHome = "${cacheDir}/rustup";
  cargoHome = "${stateDir}/.cargo";
  tokenFile = "${root}/${name}.token";
  patSrc =
    config.users.users.${config.system.primaryUser}.home + "/.config/secrets/github-runner-browser-pat";
  package = pkgs.github-runner;
  find = "${pkgs.findutils}/bin/find";
  jq = "${pkgs.jq}/bin/jq";
  libexec = "/usr/local/libexec";
  launcherPath = "${libexec}/${svc}";
  launcherDir = "${launcherPath}.d";
  startLink = "${launcherDir}/start";
  # No store path inside: its bytes, hence its cdhash and the Full Disk Access
  # grant, survive every rebuild that only changes the start script.
  launcherSrc = pkgs.writeText "${svc}-launcher.c" ''
    #include <errno.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <unistd.h>

    #define START "${startLink}"

    int main(void)
    {
      char *const argv[] = { (char *)START, NULL };

      /* The start script is bash: these would make it source a file first. */
      unsetenv("BASH_ENV");
      unsetenv("ENV");
      for (;;) {
        /* At boot /nix/store is mounted late: the link dangles until it is. */
        while (access(START, X_OK) != 0)
          sleep(1);
        execv(START, argv);
        if (errno != ENOENT) {
          perror(START);
          return 1;
        }
        sleep(1);
      }
    }
  '';
  launcher = pkgs.runCommandCC "${svc}-launcher" { } ''
    mkdir -p $out/bin
    $CC -O2 -Wall -Werror -o $out/bin/${svc} ${launcherSrc}
  '';
  launcherBin = "${launcher}/bin/${svc}";
in
{
  users.users.${account} = {
    uid = 533;
    gid = 533;
    home = root;
    createHome = false;
    shell = "/bin/bash";
    description = "GitHub Runner service user";
  };
  users.groups.${account} = {
    gid = 533;
    description = "GitHub Runner service user group";
  };
  users.knownUsers = [ account ];
  users.knownGroups = [ account ];

  # Runs after the users/groups slots and before the daemons are (re)loaded.
  system.activationScripts.launchd.text = lib.mkBefore ''
    # ${svc} BEGIN
    echo >&2 "setting up GitHub runner ${name}..."
    /bin/mkdir -p ${root}/_cache ${root}/_work /var/log/github-runners
    /usr/sbin/chown root:wheel ${root} ${root}/_cache ${root}/_work /var/log/github-runners
    /bin/chmod 0755 ${root} ${root}/_cache ${root}/_work /var/log/github-runners
    /bin/mkdir -p ${stateDir} ${workDir} ${cacheDir}
    /usr/sbin/chown -h ${account}:${account} ${stateDir} ${workDir} ${cacheDir}
    /bin/chmod -h 0700 ${stateDir} ${workDir} ${cacheDir}
    /bin/mkdir -p ${logDir}
    /usr/sbin/chown root:admin ${logDir}
    /bin/chmod 0750 ${logDir}
    if [ -s ${lib.escapeShellArg patSrc} ]; then
      if ! /usr/bin/cmp -s ${lib.escapeShellArg patSrc} ${tokenFile}; then
        /usr/bin/install -m 0400 -o root -g wheel ${lib.escapeShellArg patSrc} ${tokenFile}.tmp
        /bin/mv -f ${tokenFile}.tmp ${tokenFile}
      fi
      /usr/sbin/chown root:wheel ${tokenFile}
      /bin/chmod 0400 ${tokenFile}
    else
      echo >&2 "warning: ${patSrc} is missing or empty: the GitHub runner ${name} stays stopped until it is filled"
    fi
    /bin/mkdir -p ${libexec} ${launcherDir}
    /usr/sbin/chown -h root:wheel ${libexec} ${launcherDir}
    /bin/chmod -h 0755 ${libexec} ${launcherDir}
    if ! /usr/bin/cmp -s ${launcherBin} ${launcherPath}; then
      /usr/bin/install -m 0700 -o root -g wheel ${launcherBin} ${launcherPath}.tmp
      /bin/mv -f ${launcherPath}.tmp ${launcherPath}
      echo >&2 "warning: ${launcherPath} changed: grant Full Disk Access to ${launcherPath} again (System Settings > Privacy & Security)"
    fi
    /usr/sbin/chown -h root:wheel ${launcherPath}
    /bin/chmod -h 0700 ${launcherPath}
    /bin/chmod -N ${launcherPath}
    /bin/ln -sfn ${config.launchd.daemons.${svc}.command} ${startLink}
    # ${svc} END
  '';

  launchd.daemons.${svc} = {
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnutar
      pkgs.gzip
      pkgs.rustup
    ]
    ++ [
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];

    script = ''
      if [ ! -s ${tokenFile} ]; then
        echo "${svc}: ${tokenFile} is missing or empty, not starting" >&2
        exit 78
      fi

      # Nothing a previous job left behind outlives it: its crontab, then every
      # process of the runner user (repeated: a forking process can respawn).
      /usr/bin/crontab -r -u ${account} 2>/dev/null
      for _ in 1 2 3 4 5; do
        /usr/bin/pkill -KILL -u ${account}
        rc=$?
        [ "$rc" -le 1 ] || exit 1
        [ "$rc" -eq 1 ] && break
        sleep 1
      done
      if [ "$rc" -ne 1 ]; then
        echo "${svc}: processes of ${account} survive pkill, not starting" >&2
        exit 1
      fi

      # Ephemeral: every start begins from an empty work dir and runner root,
      # wiped as the runner user so root never walks a tree a job could shape.
      # Flags, ACLs and modes a job set would make the delete skip entries.
      /usr/bin/sudo -u ${account} /usr/bin/chflags -R nouchg,nouappnd ${workDir} ${stateDir}
      /usr/bin/sudo -u ${account} /bin/chmod -R -N ${workDir} ${stateDir}
      /usr/bin/sudo -u ${account} /bin/chmod -R u+rwx ${workDir} ${stateDir}
      /usr/bin/sudo -u ${account} ${find} ${workDir} ${stateDir} -mindepth 1 -delete
      if [ -n "$(${find} ${workDir} ${stateDir} -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        echo "${svc}: ${workDir} or ${stateDir} is not empty after the wipe, not starting" >&2
        exit 1
      fi
      /usr/bin/sudo -u ${account} /bin/mkdir -p ${rustupHome}

      # Single-use just-in-time runner config: one job, then the runner is
      # gone. Retried for a network that is not up yet at boot.
      token=$(<${tokenFile})
      body=$(${jq} -cn \
        --arg name "${name}-$(/bin/hostname -s)-$(/bin/date +%s)" \
        --arg work ${workDir} \
        '{name: $name, runner_group_id: 1, labels: ["${name}"], work_folder: $work}')
      jit=
      for attempt in 1 2 3 4 5; do
        response=$(printf 'header = "Authorization: Bearer %s"\n' "$token" \
          | /usr/bin/curl -fsS --config - \
            -H 'Accept: application/vnd.github+json' \
            -H 'X-GitHub-Api-Version: 2022-11-28' \
            --data "$body" \
            https://api.github.com/repos/AlxWrtl/browser/actions/runners/generate-jitconfig) \
          && jit=$(printf '%s' "$response" | ${jq} -er .encoded_jit_config) \
          && break
        echo "${svc}: generate-jitconfig attempt $attempt/5 failed" >&2
        [ "$attempt" -eq 5 ] || sleep 30
      done
      unset token response
      [ -n "$jit" ] || exit 1

      exec /usr/bin/sudo -u ${account} /usr/bin/env \
        HOME=${stateDir} \
        RUNNER_ROOT=${stateDir} \
        RUSTUP_HOME=${rustupHome} \
        CARGO_HOME=${cargoHome} \
        PATH="$PATH" \
        ${package}/bin/Runner.Listener run --startuptype service --jitconfig "$jit"
    '';

    serviceConfig = {
      ProgramArguments = lib.mkForce [ launcherPath ];
      # Activation reloads a daemon only when its plist changes: this names
      # the start script in it, so a new script restarts the runner.
      EnvironmentVariables.GITHUB_RUNNER_START = "${config.launchd.daemons.${svc}.command}";
      # launchd ORs KeepAlive keys: `Crashed = false` would respawn every
      # non-crash exit, exit 78 included. Only exit 0 (job done) restarts.
      KeepAlive = {
        SuccessfulExit = true;
      };
      RunAtLoad = true;
      ThrottleInterval = 30;
      ProcessType = "Interactive";
      WorkingDirectory = stateDir;
      StandardOutPath = "${logDir}/launchd-stdout.log";
      StandardErrorPath = "${logDir}/launchd-stderr.log";
      WatchPaths = [ tokenFile ];
    };
  };
}
