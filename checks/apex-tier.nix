# Runtime check for apex-tier (home/claude-code/apex-tier.nix): the BUILT
# classifier runs against throwaway git repos and must return the expected tier.
#
#   F1  `matcher = "permission_prompt|elicitation_dialog";` added in a new
#       group under hooks.Notification            -> direct
#   F2  entry added mid `deny = [ ... ]`          -> high (permission)
#   F3  hooks/x.js gains a permissionDecision     -> high (hook-decision)
#   F4  40 lines appended to README.md            -> standard (size only)
#   F5  new untracked `.env.example`              -> high (secret-path)
#   F6  hooks/guard.js: only the `if (...)` above an unchanged
#       `permissionDecision: "deny"` changes        -> high (hook-decision)
#   F7  new untracked `config/apikey.json`        -> high (secret-path)
#   F8  scripts/purge.sql gains `DELETE FROM users;` -> high (destructive)
#   F9  hooks/notification.sh: one osascript text change, the file holds no
#       decision statement                        -> direct (no over-escalation)
#
# Canary M1: a copy of the script with PERM_RE replaced by a regex that never
# matches (`x^`) runs F2 and must NOT say high. If it still does, F2's "high"
# comes from something other than the permission class and the F2 assertion
# proves nothing, so the check fails. A build-time guard fails too if the sed
# anchor is gone (the mutant would equal the source).
#
# Offline: git only, HOME and system git config isolated in $TMPDIR.
{ pkgs }:

let
  tier = (import ../home/claude-code/apex-tier.nix { inherit pkgs; }).apexTierPkg;
  script = ../home/claude-code/scripts/apex-tier.sh;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.git
    pkgs.gawk
    pkgs.gnugrep
    pkgs.coreutils
    pkgs.gnused
    pkgs.bash
  ];

  settingsBase = pkgs.writeText "settings-base.nix" ''
    {
      settings = {
        permissions = {
          allow = [
            "Bash(ls *)"
          ];
          deny = [
            "Bash(rm *)"
            "Bash(sudo *)"
          ];
        };
        hooks = {
          Notification = [
            {
              matcher = "idle_prompt";
              hooks = [ { type = "command"; command = "notify"; } ];
            }
          ];
        };
      };
    }
  '';

  settingsF1 = pkgs.writeText "settings-f1.nix" ''
    {
      settings = {
        permissions = {
          allow = [
            "Bash(ls *)"
          ];
          deny = [
            "Bash(rm *)"
            "Bash(sudo *)"
          ];
        };
        hooks = {
          Notification = [
            {
              matcher = "idle_prompt";
              hooks = [ { type = "command"; command = "notify"; } ];
            }
            {
              matcher = "permission_prompt|elicitation_dialog";
              hooks = [ { type = "command"; command = "notify"; } ];
            }
          ];
        };
      };
    }
  '';

  settingsF2 = pkgs.writeText "settings-f2.nix" ''
    {
      settings = {
        permissions = {
          allow = [
            "Bash(ls *)"
          ];
          deny = [
            "Bash(rm *)"
            "Bash(curl *)"
            "Bash(sudo *)"
          ];
        };
        hooks = {
          Notification = [
            {
              matcher = "idle_prompt";
              hooks = [ { type = "command"; command = "notify"; } ];
            }
          ];
        };
      };
    }
  '';

  hookBase = pkgs.writeText "x-base.js" ''
    const d = JSON.parse(input);
    if (d.ok) {
      process.exit(0);
    }
  '';

  guardBase = pkgs.writeText "guard-base.js" ''
    const d = JSON.parse(input);
    if (d.cmd.includes("rm")) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: { permissionDecision: "deny" } }));
    }
  '';

  guardF6 = pkgs.writeText "guard-f6.js" ''
    const d = JSON.parse(input);
    if (d.cmd.includes("rm") && !d.dryRun) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: { permissionDecision: "deny" } }));
    }
  '';

  notifyBase = pkgs.writeText "notification-base.sh" ''
    #!/bin/sh
    osascript -e 'display notification "Claude needs you" with title "Claude"'
  '';

  notifyF9 = pkgs.writeText "notification-f9.sh" ''
    #!/bin/sh
    osascript -e 'display notification "Claude is waiting for you" with title "Claude"'
  '';

  hookF3 = pkgs.writeText "x-f3.js" ''
    const d = JSON.parse(input);
    if (d.ok) {
      process.exit(0);
    }
    if (d.bad) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: { permissionDecision: "deny" } }));
    }
  '';
in
pkgs.runCommand "apex-tier-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR" GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  # Canary M1: PERM_RE replaced by a regex that never matches.
  sed "s/^PERM_RE=.*/PERM_RE='x^'/" ${script} > "$TMPDIR/mutant.sh"
  if ! grep -qx "PERM_RE='x^'" "$TMPDIR/mutant.sh" || [ "$(grep -c '^PERM_RE=' "$TMPDIR/mutant.sh")" != 1 ]; then
    echo "apex-tier: canary anchor '^PERM_RE=' gone from the script — the mutant equals the source"
    exit 1
  fi

  # fixture NAME: a fresh repo on master with the base files, then branch feat/x.
  fixture() {
    R="$TMPDIR/$1"
    mkdir -p "$R/hooks"
    cd "$R"
    git init -q -b master --template=
    cp ${settingsBase} settings.nix
    cp ${hookBase} hooks/x.js
    cp ${guardBase} hooks/guard.js
    cp ${notifyBase} hooks/notification.sh
    printf 'readme\n' > README.md
    chmod u+w settings.nix hooks/x.js hooks/guard.js hooks/notification.sh
    git add -A
    git commit -qm init
    git checkout -qb feat/x
  }

  # expect LABEL WANT_TIER WANT_REASON(or -) CMD...: runs CMD in the current repo.
  expect() {
    label="$1"; want="$2"; reason="$3"; shift 3
    res="$("$@" --base master)" || { echo "apex-tier: $label FAILED — classifier exited non-zero: $res"; exit 1; }
    got="$(printf '%s\n' "$res" | sed -n 's/^tier=\([a-z]*\) .*/\1/p')"
    if [ "$got" != "$want" ]; then
      echo "apex-tier: $label FAILED — expected tier=$want, got: $res"
      exit 1
    fi
    if [ "$reason" != - ] && ! printf '%s\n' "$res" | grep -qF "$reason"; then
      echo "apex-tier: $label FAILED — tier=$want but reason '$reason' missing: $res"
      exit 1
    fi
    echo "apex-tier: $label OK — $res"
  }

  fixture f1
  cp ${settingsF1} settings.nix
  expect "F1 Notification matcher" direct - ${tier}/bin/apex-tier

  fixture f2
  cp ${settingsF2} settings.nix
  expect "F2 deny-list entry" high permission@settings.nix ${tier}/bin/apex-tier

  fixture f3
  cp ${hookF3} hooks/x.js
  expect "F3 hook permissionDecision" high hook-decision@hooks/x.js ${tier}/bin/apex-tier

  fixture f4
  for i in $(seq 1 40); do printf 'line %s\n' "$i"; done >> README.md
  expect "F4 README +40 lines" standard - ${tier}/bin/apex-tier

  fixture f5
  printf 'FOO=bar\n' > .env.example
  expect "F5 new .env.example" high secret-path ${tier}/bin/apex-tier

  fixture f6
  cp ${guardF6} hooks/guard.js
  expect "F6 guard condition above unchanged deny" high hook-decision@hooks/guard.js ${tier}/bin/apex-tier

  fixture f7
  mkdir -p config
  printf '{}\n' > config/apikey.json
  expect "F7 new config/apikey.json" high secret-path@config/apikey.json ${tier}/bin/apex-tier

  fixture f8
  mkdir -p scripts
  printf 'DELETE FROM users;\n' > scripts/purge.sql
  expect "F8 DELETE FROM in purge.sql" high destructive@scripts/purge.sql ${tier}/bin/apex-tier

  fixture f9
  cp ${notifyF9} hooks/notification.sh
  expect "F9 notifier text change" direct - ${tier}/bin/apex-tier

  # M1 on F2: must not be high.
  fixture m1
  cp ${settingsF2} settings.nix
  m1="$(bash -euo pipefail "$TMPDIR/mutant.sh" --base master)" || {
    echo "apex-tier: canary M1 crashed instead of classifying: $m1"
    exit 1
  }
  case "$m1" in
  tier=high*)
    echo "apex-tier: canary M1 SURVIVED — PERM_RE neutralised and F2 is still high ($m1); the F2 assertion does not prove the permission class"
    exit 1
    ;;
  esac
  echo "apex-tier: canary M1 killed — F2 without PERM_RE: $m1"

  echo "apex-tier: 9 fixtures, 1 canary — OK"
  touch $out
''
