# Runtime check for ttw-tier (home/claude-code/ttw-tier.nix): the BUILT
# classifier runs against throwaway git repos and must return the expected tier.
#
#   A1  apex -> ttw, phase 2: the package ships bin/ttw-tier AND bin/apex-tier,
#       the old name a symlink to ttw-tier in the same output (a session
#       started before the switch still finds it; dropped in phase 4). F2
#       runs once more through the alias. Same for ttw-verify-external, built
#       here because no other flake check builds it: bin/apex-verify-external
#       -> ttw-verify-external, `--help` identical from both names.
#   A2  self-name: usage and --help name ttw-tier / ttw-verify-external, never
#       the apex-* name.
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
#   F10 4 new untracked 1-line files a..d.txt     -> direct (files > 4 boundary)
#   F11 5 new untracked 1-line files a..e.txt     -> standard (files > 4)
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
  tier = (import ../home/claude-code/ttw-tier.nix { inherit pkgs; }).ttwTierPkg;
  vext = (import ../home/claude-code/ttw-verify-external.nix { inherit pkgs; }).ttwVerifyExternalPkg;
  script = ../home/claude-code/scripts/ttw-tier.sh;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.git
    pkgs.gawk
    pkgs.gnugrep
    pkgs.coreutils
    pkgs.diffutils
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
pkgs.runCommand "ttw-tier-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR" GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  # Canary M1: PERM_RE replaced by a regex that never matches.
  sed "s/^PERM_RE=.*/PERM_RE='x^'/" ${script} > "$TMPDIR/mutant.sh"
  if ! grep -qx "PERM_RE='x^'" "$TMPDIR/mutant.sh" || [ "$(grep -c '^PERM_RE=' "$TMPDIR/mutant.sh")" != 1 ]; then
    echo "ttw-tier: canary anchor '^PERM_RE=' gone from the script — the mutant equals the source"
    exit 1
  fi

  # A1 check_alias PKG NEW OLD: bin/NEW executable; bin/OLD a symlink whose
  # target is NEW in the same bin dir (`NEW` or `PKG/bin/NEW`), both resolving
  # to one file. A copy, a wrapper or a link straight into another store path
  # is a second binary that can drift from the first.
  check_alias() {
    pkg="$1"; new="$2"; old="$3"
    [ -x "$pkg/bin/$new" ] || { echo "ttw-tier: A1 FAILED — $pkg/bin/$new is missing or not executable"; exit 1; }
    [ -L "$pkg/bin/$old" ] || { echo "ttw-tier: A1 FAILED — $pkg/bin/$old is not a symlink (the pre-rename alias of $new, kept until phase 4)"; exit 1; }
    tgt="$(readlink "$pkg/bin/$old")"
    case "$tgt" in
    "$new" | "$pkg/bin/$new") ;;
    *)
      echo "ttw-tier: A1 FAILED — $pkg/bin/$old points at '$tgt', not at $new in the same package"
      exit 1
      ;;
    esac
    [ "$(readlink -f "$pkg/bin/$old")" = "$(readlink -f "$pkg/bin/$new")" ] \
      || { echo "ttw-tier: A1 FAILED — $old and $new do not resolve to the same file"; exit 1; }
    echo "ttw-tier: A1 $old -> $new OK"
  }
  check_alias ${tier} ttw-tier apex-tier
  check_alias ${vext} ttw-verify-external apex-verify-external

  # A2: the usage line names the new binary, from either name.
  for n in ttw-tier apex-tier; do
    rc=0
    ${tier}/bin/$n --no-such-flag > "$TMPDIR/usage-$n.out" 2>&1 || rc=$?
    if [ "$rc" != 2 ] || ! grep -qF 'usage: ttw-tier' "$TMPDIR/usage-$n.out" || grep -qF 'apex-tier' "$TMPDIR/usage-$n.out"; then
      echo "ttw-tier: A2 FAILED — '$n --no-such-flag' exited $rc (want 2) and/or its text does not name ttw-tier alone:"
      cat "$TMPDIR/usage-$n.out"
      exit 1
    fi
  done
  echo "ttw-tier: A2 usage names ttw-tier OK"
  for n in ttw-verify-external apex-verify-external; do
    rc=0
    ${vext}/bin/$n --help > "$TMPDIR/help-$n.out" 2>&1 || rc=$?
    if [ "$rc" != 0 ] || ! grep -qF 'ttw-verify-external --acs <FILE>' "$TMPDIR/help-$n.out" || grep -qF 'apex-verify-external' "$TMPDIR/help-$n.out"; then
      echo "ttw-tier: A2 FAILED — '$n --help' exited $rc (want 0) and/or its text does not name ttw-verify-external alone:"
      cat "$TMPDIR/help-$n.out"
      exit 1
    fi
  done
  cmp -s "$TMPDIR/help-ttw-verify-external.out" "$TMPDIR/help-apex-verify-external.out" \
    || { echo "ttw-tier: A2 FAILED — --help differs between ttw-verify-external and its apex-verify-external alias"; exit 1; }
  echo "ttw-tier: A2 --help names ttw-verify-external OK"

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
    res="$("$@" --base master)" || { echo "ttw-tier: $label FAILED — classifier exited non-zero: $res"; exit 1; }
    got="$(printf '%s\n' "$res" | sed -n 's/^tier=\([a-z]*\) .*/\1/p')"
    if [ "$got" != "$want" ]; then
      echo "ttw-tier: $label FAILED — expected tier=$want, got: $res"
      exit 1
    fi
    if [ "$reason" != - ] && ! printf '%s\n' "$res" | grep -qF "$reason"; then
      echo "ttw-tier: $label FAILED — tier=$want but reason '$reason' missing: $res"
      exit 1
    fi
    echo "ttw-tier: $label OK — $res"
  }

  fixture f1
  cp ${settingsF1} settings.nix
  expect "F1 Notification matcher" direct - ${tier}/bin/ttw-tier

  fixture f2
  cp ${settingsF2} settings.nix
  expect "F2 deny-list entry" high permission@settings.nix ${tier}/bin/ttw-tier
  expect "F2 through the apex-tier alias (A1)" high permission@settings.nix ${tier}/bin/apex-tier

  fixture f3
  cp ${hookF3} hooks/x.js
  expect "F3 hook permissionDecision" high hook-decision@hooks/x.js ${tier}/bin/ttw-tier

  fixture f4
  for i in $(seq 1 40); do printf 'line %s\n' "$i"; done >> README.md
  expect "F4 README +40 lines" standard - ${tier}/bin/ttw-tier

  fixture f5
  printf 'FOO=bar\n' > .env.example
  expect "F5 new .env.example" high secret-path ${tier}/bin/ttw-tier

  fixture f6
  cp ${guardF6} hooks/guard.js
  expect "F6 guard condition above unchanged deny" high hook-decision@hooks/guard.js ${tier}/bin/ttw-tier

  fixture f7
  mkdir -p config
  printf '{}\n' > config/apikey.json
  expect "F7 new config/apikey.json" high secret-path@config/apikey.json ${tier}/bin/ttw-tier

  fixture f8
  mkdir -p scripts
  printf 'DELETE FROM users;\n' > scripts/purge.sql
  expect "F8 DELETE FROM in purge.sql" high destructive@scripts/purge.sql ${tier}/bin/ttw-tier

  fixture f9
  cp ${notifyF9} hooks/notification.sh
  expect "F9 notifier text change" direct - ${tier}/bin/ttw-tier

  fixture f10
  for n in a b c d; do printf 'x\n' > "$n.txt"; done
  expect "F10 4 new files" direct - ${tier}/bin/ttw-tier

  fixture f11
  for n in a b c d e; do printf 'x\n' > "$n.txt"; done
  expect "F11 5 new files" standard - ${tier}/bin/ttw-tier

  # M1 on F2: must not be high.
  fixture m1
  cp ${settingsF2} settings.nix
  m1="$(bash -euo pipefail "$TMPDIR/mutant.sh" --base master)" || {
    echo "ttw-tier: canary M1 crashed instead of classifying: $m1"
    exit 1
  }
  case "$m1" in
  tier=high*)
    echo "ttw-tier: canary M1 SURVIVED — PERM_RE neutralised and F2 is still high ($m1); the F2 assertion does not prove the permission class"
    exit 1
    ;;
  esac
  echo "ttw-tier: canary M1 killed — F2 without PERM_RE: $m1"

  echo "ttw-tier: 11 fixtures, 2 aliases, 1 canary — OK"
  touch $out
''
