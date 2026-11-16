# Runtime check for ttw-tier (home/claude-code/ttw-tier.nix): the BUILT
# classifier runs against throwaway git repos and must return the expected tier.
#
#   A1  the package's bin holds exactly ttw-tier, executable (the pre-rename
#       alias is gone). Same for ttw-verify-external, built here because no
#       other flake check builds it: its bin holds exactly ttw-verify-external.
#   A2  self-name: usage and --help name ttw-tier / ttw-verify-external.
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
# Comments and Markdown prose (a `# ` line is not code; .md prose outside a
# fenced block is not scanned, except agent instruction files):
#   AC1  `sandbox = {` comment replaced by 3 `# ` lines saying deny/rm/allow,
#        README gains `sandbox.autoAllowBashIfSandboxed` + `pnpm run deploy`
#                                                 -> direct
#   AC2  top-level `# deny = [ "x" ]` added        -> direct
#   AC3  comment line removed inside `deny = [`   -> direct
#   AC4  `"Bash(curl *)"` added next to a comment inside deny -> high (permission)
#   AC5  `"Bash(curl *)" # why` added inside deny -> high (permission)
#   AC6  `# "Bash(curl *)"` uncommented inside deny -> high (permission)
#   AC6b active deny rule commented out           -> high (permission)
#   AC7  scripts/clean.sh gains `rm -rf build`    -> high (destructive)
#   AC8  scripts/clean.sh gains only a `# ` comment saying rm -rf / deploy
#                                                 -> direct
#   AC9  new docs/notes.md prose naming sandbox.allow, rm -rf, deploy -> direct
#   AC9b the same prose in AGENTS.md, .claude/rules/x.md, skills/x/SKILL.md
#        (agent instructions stay fully scanned)  -> high (permission)
#   AC10 README gains a fenced ```sh block with `rm -rf build` -> high (destructive)
#   AC11 new lib/x.nix holding only a `# deny: ...` comment -> direct;
#        new lib/y.nix with `deny = [ "x" ];`     -> high (permission)
#   AC12 a nix '' string gains `#!/bin/sh` and `#define DEPLOY_DIR "x"`
#        (`#` without a space stays code)         -> high (destructive)
#   AC12b new scripts/run.sh whose shebang is `#!/usr/bin/env deploy`
#                                                 -> high (destructive)
#   AC13a a `# ` line inside a nix '' string closes it, sets
#        permissions.deny, reopens a string       -> high (permission)
#   AC13b a `# ` line inside a multi-line '...' shell string closes it and
#        runs rm -rf (balanced quotes)            -> high (destructive)
#   AC14a ````md fence holding ``` then rm -rf    -> high (destructive)
#   AC14b ```sh fence holding ~~~ then rm -rf     -> high (destructive)
#
# Canary M1: a copy of the script with PERM_RE replaced by a regex that never
# matches (`x^`) runs F2 and must NOT say high. If it still does, F2's "high"
# comes from something other than the permission class and the F2 assertion
# proves nothing, so the check fails. A build-time guard fails too if the sed
# anchor is gone (the mutant would equal the source).
# Canary M2: HASH_COMMENT_RE neutralised (`x^`), AC1's settings.nix change
# alone must say high: AC1's "direct" comes from the comment rule.
# Canary M3: MD_EXT_RE neutralised (`x^`), AC9 must say high: AC9's "direct"
# comes from the Markdown rule. Both carry the same sed-anchor guard as M1.
# Canary M4: STRING_END_RE neutralised (`x^`), AC13a must NOT say high:
# AC13a's high comes from the string-terminator rule. Same sed-anchor guard.
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

  # AC1 / M2 base: a `sandbox = {` block holding one comment.
  settingsSandbox = pkgs.writeText "settings-sandbox.nix" ''
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
        sandbox = {
          # sandbox settings
          enabled = true;
        };
      };
    }
  '';

  # AC3 / AC4 / AC6 / AC6b base: comments inside `deny = [`.
  settingsComment = pkgs.writeText "settings-comment.nix" ''
    {
      settings = {
        permissions = {
          allow = [
            "Bash(ls *)"
          ];
          deny = [
            # blocked commands
            "Bash(rm *)"
            # "Bash(curl *)"
            "Bash(sudo *)"
          ];
        };
      };
    }
  '';

  # AC12 base: a nix indented string holding a shell script.
  settingsScript = pkgs.writeText "settings-script.nix" ''
    {
      settings = {
        statusLine = {
          command = '''
            echo status
          ''';
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
  # Canary M2: the comment rule neutralised.
  sed "s/^HASH_COMMENT_RE=.*/HASH_COMMENT_RE='x^'/" ${script} > "$TMPDIR/mutant-m2.sh"
  if ! grep -qx "HASH_COMMENT_RE='x^'" "$TMPDIR/mutant-m2.sh" || [ "$(grep -c '^HASH_COMMENT_RE=' "$TMPDIR/mutant-m2.sh")" != 1 ]; then
    echo "ttw-tier: canary anchor '^HASH_COMMENT_RE=' gone from the script — the mutant equals the source"
    exit 1
  fi
  # Canary M3: the Markdown rule neutralised.
  sed "s/^MD_EXT_RE=.*/MD_EXT_RE='x^'/" ${script} > "$TMPDIR/mutant-m3.sh"
  if ! grep -qx "MD_EXT_RE='x^'" "$TMPDIR/mutant-m3.sh" || [ "$(grep -c '^MD_EXT_RE=' "$TMPDIR/mutant-m3.sh")" != 1 ]; then
    echo "ttw-tier: canary anchor '^MD_EXT_RE=' gone from the script — the mutant equals the source"
    exit 1
  fi
  # Canary M4: the string-terminator rule neutralised.
  sed "s/^STRING_END_RE=.*/STRING_END_RE='x^'/" ${script} > "$TMPDIR/mutant-m4.sh"
  if ! grep -qx "STRING_END_RE='x^'" "$TMPDIR/mutant-m4.sh" || [ "$(grep -c '^STRING_END_RE=' "$TMPDIR/mutant-m4.sh")" != 1 ]; then
    echo "ttw-tier: canary anchor '^STRING_END_RE=' gone from the script — the mutant equals the source"
    exit 1
  fi

  # A1 check_bin PKG NAME: bin/NAME executable and the only entry of bin/.
  check_bin() {
    pkg="$1"; name="$2"
    [ -x "$pkg/bin/$name" ] || { echo "ttw-tier: A1 FAILED — $pkg/bin/$name is missing or not executable"; exit 1; }
    bins="$(ls -A "$pkg/bin" | tr '\n' ' ')"
    [ "$bins" = "$name " ] || { echo "ttw-tier: A1 FAILED — $pkg/bin holds '$bins', want exactly '$name'"; exit 1; }
    echo "ttw-tier: A1 bin is exactly $name OK"
  }
  check_bin ${tier} ttw-tier
  check_bin ${vext} ttw-verify-external

  # A2: the usage line and --help name the binary.
  rc=0
  ${tier}/bin/ttw-tier --no-such-flag > "$TMPDIR/usage.out" 2>&1 || rc=$?
  if [ "$rc" != 2 ] || ! grep -qF 'usage: ttw-tier' "$TMPDIR/usage.out"; then
    echo "ttw-tier: A2 FAILED — 'ttw-tier --no-such-flag' exited $rc (want 2) and/or its text does not name ttw-tier:"
    cat "$TMPDIR/usage.out"
    exit 1
  fi
  echo "ttw-tier: A2 usage names ttw-tier OK"
  rc=0
  ${vext}/bin/ttw-verify-external --help > "$TMPDIR/help.out" 2>&1 || rc=$?
  if [ "$rc" != 0 ] || ! grep -qF 'ttw-verify-external --acs <FILE>' "$TMPDIR/help.out"; then
    echo "ttw-tier: A2 FAILED — 'ttw-verify-external --help' exited $rc (want 0) and/or its text does not name ttw-verify-external:"
    cat "$TMPDIR/help.out"
    exit 1
  fi
  echo "ttw-tier: A2 --help names ttw-verify-external OK"

  # fixture NAME [BASE_SETTINGS]: a fresh repo on master with the base files
  # (settings.nix from BASE_SETTINGS, default settingsBase), then branch feat/x.
  fixture() {
    R="$TMPDIR/$1"
    mkdir -p "$R/hooks" "$R/scripts"
    cd "$R"
    git init -q -b master --template=
    cp "''${2:-${settingsBase}}" settings.nix
    cp ${hookBase} hooks/x.js
    cp ${guardBase} hooks/guard.js
    cp ${notifyBase} hooks/notification.sh
    printf 'readme\n' > README.md
    printf '#!/bin/sh\necho clean\n' > scripts/clean.sh
    chmod u+w settings.nix hooks/x.js hooks/guard.js hooks/notification.sh
    git add -A
    git commit -qm init
    git checkout -qb feat/x
  }

  # edit FILE MODE NEEDLE TEXT: line edit keyed on a literal substring.
  #   set     NEEDLE replaced by TEXT inside each matching line
  #   after   TEXT inserted after each matching line, at its indentation
  #   before  TEXT inserted before each matching line, at its indentation
  #   del     each matching line dropped (TEXT ignored)
  # Fails the build if the file is unchanged: a no-op edit would let a
  # "direct" assertion pass on an empty diff.
  edit() {
    awk -v m="$2" -v n="$3" -v t="$4" '
      function ind(s) { match(s, /^[ ]*/); return substr(s, 1, RLENGTH) }
      !index($0, n) { print; next }
      m == "del" { next }
      m == "set" { i = index($0, n); print substr($0, 1, i - 1) t substr($0, i + length(n)); next }
      m == "before" { print ind($0) t; print; next }
      m == "after" { print; print ind($0) t; next }
      { print "edit: unknown mode " m > "/dev/stderr"; exit 1 }
    ' "$1" > "$1.new"
    if cmp -s "$1" "$1.new"; then
      echo "ttw-tier: fixture edit '$2 $3' changed nothing in $1"
      exit 1
    fi
    mv "$1.new" "$1"
  }

  # AC1's settings.nix change (also M2's input).
  ac1_settings() {
    edit settings.nix set '# sandbox settings' '# deny: outbound network'
    edit settings.nix after '# deny: outbound network' '# rm -rf stays blocked'
    edit settings.nix after '# rm -rf stays blocked' '# allow: writes to build only'
  }

  # AC9's prose (also M3's input).
  prose='the sandbox.allow list; never rm -rf; deploy'

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

  fixture ac1 ${settingsSandbox}
  ac1_settings
  printf '%s\n' 'Set `sandbox.autoAllowBashIfSandboxed` before `pnpm run deploy`.' >> README.md
  expect "AC1 sandbox comments + README prose" direct - ${tier}/bin/ttw-tier

  fixture ac2
  { printf '%s\n' '# deny = [ "x" ]'; cat settings.nix; } > settings.nix.new
  mv settings.nix.new settings.nix
  expect "AC2 top-level deny comment" direct - ${tier}/bin/ttw-tier

  fixture ac3 ${settingsComment}
  edit settings.nix del '# blocked commands' ""
  expect "AC3 comment removed inside deny" direct - ${tier}/bin/ttw-tier

  fixture ac4 ${settingsComment}
  edit settings.nix after '# blocked commands' '"Bash(curl *)"'
  expect "AC4 deny entry next to a comment" high permission@settings.nix ${tier}/bin/ttw-tier

  fixture ac5
  edit settings.nix after '"Bash(rm *)"' '"Bash(curl *)" # why'
  expect "AC5 deny entry with trailing comment" high permission@settings.nix ${tier}/bin/ttw-tier

  fixture ac6 ${settingsComment}
  edit settings.nix set '# "Bash(curl *)"' '"Bash(curl *)"'
  expect "AC6 deny entry uncommented" high permission@settings.nix ${tier}/bin/ttw-tier

  fixture ac6b ${settingsComment}
  edit settings.nix set '"Bash(sudo *)"' '# "Bash(sudo *)"'
  expect "AC6b deny entry commented out" high permission@settings.nix ${tier}/bin/ttw-tier

  fixture ac7
  printf 'rm -rf build\n' >> scripts/clean.sh
  expect "AC7 rm -rf code line" high destructive@scripts/clean.sh ${tier}/bin/ttw-tier

  fixture ac8
  printf '# never rm -rf here, no deploy\n' >> scripts/clean.sh
  expect "AC8 shell comment naming rm -rf" direct - ${tier}/bin/ttw-tier

  fixture ac9
  mkdir -p docs
  printf '%s\n' "$prose" > docs/notes.md
  expect "AC9 docs prose" direct - ${tier}/bin/ttw-tier

  fixture ac9b-agents
  printf '%s\n' "$prose" > AGENTS.md
  expect "AC9b AGENTS.md prose" high permission@AGENTS.md ${tier}/bin/ttw-tier

  fixture ac9b-rules
  mkdir -p .claude/rules
  printf '%s\n' "$prose" > .claude/rules/x.md
  expect "AC9b .claude/rules prose" high permission@.claude/rules/x.md ${tier}/bin/ttw-tier

  fixture ac9b-skill
  mkdir -p skills/x
  printf '%s\n' "$prose" > skills/x/SKILL.md
  expect "AC9b SKILL.md prose" high permission@skills/x/SKILL.md ${tier}/bin/ttw-tier

  fixture ac10
  printf '\n```sh\nrm -rf build\n```\n' >> README.md
  expect "AC10 README fenced rm -rf" high destructive@README.md ${tier}/bin/ttw-tier

  fixture ac11-comment
  mkdir -p lib
  printf '# deny: everything\n' > lib/x.nix
  expect "AC11 new nix file, comment only" direct - ${tier}/bin/ttw-tier

  fixture ac11-code
  mkdir -p lib
  printf 'deny = [ "x" ];\n' > lib/y.nix
  expect "AC11 new nix file, deny code" high permission@lib/y.nix ${tier}/bin/ttw-tier

  fixture ac12 ${settingsScript}
  edit settings.nix before 'echo status' '#!/bin/sh'
  edit settings.nix before 'echo status' '#define DEPLOY_DIR "x"'
  expect "AC12 hash without space stays code" high destructive@settings.nix ${tier}/bin/ttw-tier

  fixture ac12b
  printf '%s\n' '#!/usr/bin/env deploy' 'echo run' > scripts/run.sh
  expect "AC12b shebang carrying the match" high destructive@scripts/run.sh ${tier}/bin/ttw-tier

  # AC13a's settings.nix change (also M4's input): a `# ` line inside a nix
  # ''' string that closes it, sets permissions.deny, then reopens a string.
  ac13a_settings() {
    edit settings.nix after 'echo status' "# note '''; permissions.deny = [ ]; x = '''"
  }

  fixture ac13a ${settingsScript}
  ac13a_settings
  expect "AC13a hash line closing a nix string" high permission@settings.nix ${tier}/bin/ttw-tier

  fixture ac13b
  printf '%s\n' "msg='hello" "# x'; rm -rf \"\$HOME/tmpdir\"; z='" "bye'" > scripts/msg.sh
  expect "AC13b hash line closing a shell string" high destructive@scripts/msg.sh ${tier}/bin/ttw-tier

  fixture ac14a
  mkdir -p docs
  printf '%s\n' 'Intro' '````md' '```' 'rm -rf build' '````' 'End' > docs/guide.md
  expect "AC14a shorter fence inside a 4-backtick fence" high destructive@docs/guide.md ${tier}/bin/ttw-tier

  fixture ac14b
  mkdir -p docs
  printf '%s\n' 'Intro' '```sh' '~~~' 'rm -rf build' '```' 'End' > docs/guide.md
  expect "AC14b tilde line inside a backtick fence" high destructive@docs/guide.md ${tier}/bin/ttw-tier

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

  # M2 on AC1's settings.nix change: must say high (permission).
  fixture m2 ${settingsSandbox}
  ac1_settings
  m2="$(bash -euo pipefail "$TMPDIR/mutant-m2.sh" --base master)" || {
    echo "ttw-tier: canary M2 crashed instead of classifying: $m2"
    exit 1
  }
  case "$m2" in
  tier=high*permission@settings.nix*) ;;
  *)
    echo "ttw-tier: canary M2 SURVIVED — HASH_COMMENT_RE neutralised and AC1's settings change is not high ($m2); AC1's direct does not prove the comment rule"
    exit 1
    ;;
  esac
  echo "ttw-tier: canary M2 killed — AC1 settings without HASH_COMMENT_RE: $m2"

  # M3 on AC9: must say high.
  fixture m3
  mkdir -p docs
  printf '%s\n' "$prose" > docs/notes.md
  m3="$(bash -euo pipefail "$TMPDIR/mutant-m3.sh" --base master)" || {
    echo "ttw-tier: canary M3 crashed instead of classifying: $m3"
    exit 1
  }
  case "$m3" in
  tier=high*@docs/notes.md*) ;;
  *)
    echo "ttw-tier: canary M3 SURVIVED — MD_EXT_RE neutralised and AC9 is not high ($m3); AC9's direct does not prove the Markdown rule"
    exit 1
    ;;
  esac
  echo "ttw-tier: canary M3 killed — AC9 without MD_EXT_RE: $m3"

  # M4 on AC13a's settings.nix change: must not be high.
  fixture m4 ${settingsScript}
  ac13a_settings
  m4="$(bash -euo pipefail "$TMPDIR/mutant-m4.sh" --base master)" || {
    echo "ttw-tier: canary M4 crashed instead of classifying: $m4"
    exit 1
  }
  case "$m4" in
  tier=high*)
    echo "ttw-tier: canary M4 SURVIVED — STRING_END_RE neutralised and AC13a is still high ($m4); AC13a's high does not prove the string-terminator rule"
    exit 1
    ;;
  esac
  echo "ttw-tier: canary M4 killed — AC13a without STRING_END_RE: $m4"

  echo "ttw-tier: 33 fixtures, 2 aliases, 4 canaries — OK"
  touch $out
''
