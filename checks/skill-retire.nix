# Retirement of the pre-rename skill dir ~/.claude/skills/apex (apex -> ttw,
# phase 1, plan D3).
#
# Why an entry at all: claudeCodeDesymlinkSkills turns every */SKILL.md into a
# REAL file, and home-manager's cleanup only removes links into its own
# generations. So after the switch to skills/ttw, skills/apex/SKILL.md stays
# behind as a regular file and Claude Code lists the skill twice. The entry
# removes it, and only it: the dir must be a real dir holding nothing but a
# regular SKILL.md whose frontmatter names apex or ttw, with skills/ttw/SKILL.md
# in place. Anything else is the user's and is kept, with a warning.
#
# The entry is EVALUATED from home/claude-code/activation.nix (lib.hm.dag
# stubbed) and RUN under `bash -eu -o pipefail` — the shell home-manager
# concatenates every entry into — followed by a sentinel echo: a bare `exit`
# in the entry kills every later activation step, and only the missing
# sentinel shows it.
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  inherit (pkgs) lib;

  entryName = "claudeCodeRetireApexSkill";

  # home-manager's DAG constructors, reduced to the fields this check reads.
  hmLib = lib // {
    hm.dag = {
      entryAfter = after: data: {
        inherit after data;
        before = [ ];
      };
      entryBefore = before: data: {
        inherit before data;
        after = [ ];
      };
      entryAnywhere = data: {
        inherit data;
        after = [ ];
        before = [ ];
      };
    };
  };

  # Every argument activation.nix takes, stubbed: only `entryName` and
  # claudeCodeDirs are forced, and neither interpolates these.
  activation = import ../home/claude-code/activation.nix {
    inherit pkgs;
    lib = hmLib;
    scraplingShimPkg = "/nix/store/00000000000000000000000000000000-stub";
    modsSrc = "/nonexistent/mods-stub";
    modNames = [ ];
  };

  entry =
    activation.${entryName}
      or (throw "skill-retire: home/claude-code/activation.nix has no `${entryName}` entry. Plan D3: lib.hm.dag.entryAfter [ \"claudeCodeDesymlinkSkills\" ] — remove ~/.claude/skills/apex once SKILL.md is the only thing in it, a regular file named apex or ttw, and skills/ttw/SKILL.md is a regular file; warn and keep it otherwise; skip under DRY_RUN.");

  orderOk = builtins.elem "claudeCodeDesymlinkSkills" (entry.after or [ ]);

  dirsText = activation.claudeCodeDirs.data;
  dirsMakeApex = lib.hasInfix "/.claude/skills/apex" dirsText;
  dirsMakeTtw =
    lib.hasInfix "mkdir -p \"$HOME/.claude/skills/ttw\"" dirsText
    && lib.hasInfix "mkdir -p \"$HOME/.claude/skills/ttw/steps\"" dirsText;

  # The entry as home-manager runs it: alone in the shell, then the next step.
  runnable = pkgs.writeText "retire-apex-skill.sh" (entry.data + "\necho __SENTINEL__\n");
  # Canary: the content guard dropped. A `find` that lists nothing makes every
  # dir look like SKILL.md alone, so a dir holding a user file is retired.
  # Shadowed by a function, not by editing the text: D3 names `find` as the
  # listing, and the entry must call it by name for this canary to reach it.
  noGuard = pkgs.writeText "retire-apex-skill-noguard.sh" (
    "find() { :; }\n" + entry.data + "\necho __SENTINEL__\n"
  );

  binPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
  ];

  cases = [
    "removed-apex-named"
    "removed-ttw-named"
    "extra-file-kept"
    "extra-dotfile-kept"
    "symlink-dir-kept"
    "symlink-skill-kept"
    "name-other-kept"
    "ttw-missing-kept"
    "dry-run-kept"
    "absent-noop"
    "idempotent"
  ];

  problems =
    lib.optional (!orderOk)
      "`${entryName}` must be lib.hm.dag.entryAfter [ \"claudeCodeDesymlinkSkills\" ] (has after = ${
        builtins.toJSON (entry.after or null)
      }): before the desymlink pass skills/ttw/SKILL.md is still a link and the guard refuses every run"
    ++ lib.optional dirsMakeApex "claudeCodeDirs still names ~/.claude/skills/apex: it would recreate the dir this entry retires"
    ++ lib.optional (
      !dirsMakeTtw
    ) "claudeCodeDirs does not mkdir ~/.claude/skills/ttw and ~/.claude/skills/ttw/steps";

  runner = ''
    set -u
    root="$TMPDIR/skill-retire"
    logs="$root/logs"
    rm -rf "$root"
    mkdir -p "$logs"
    BASHBIN=${pkgs.bash}/bin/bash
    ACTPATH=${binPath}

    # $1 file, $2 frontmatter name.
    mk_skill() {
      mkdir -p "''${1%/*}"
      printf -- '---\nname: %s\ndescription: probe\n---\nbody\n' "$2" > "$1"
    }
    # $1 case: a fresh HOME with skills/ttw installed as desymlink leaves it.
    home_for() {
      H="$root/$1"
      S="$H/.claude/skills"
      A="$S/apex"
      mkdir -p "$S"
      mk_skill "$S/ttw/SKILL.md" ttw
      mkdir -p "$S/ttw/steps"
      printf 'step\n' > "$S/ttw/steps/step-00-init.md"
      cp -R "$S/ttw" "$root/$1.ttw-before"
    }
    # The apex dir the switch leaves: SKILL.md alone, a regular file.
    apex_leftover() { mk_skill "$A/SKILL.md" "$1"; }

    # $1 script, then env assignments. Leaves $rc and $log.
    retire() {
      log="$logs/$c.$tag.log"
      rc=0
      s="$1"
      shift
      env -i HOME="$H" PATH="$ACTPATH" "$@" "$BASHBIN" -eu -o pipefail "$s" > "$log" 2>&1 || rc=$?
    }
    ran_through() {
      [ "$rc" -eq 0 ] || { why="exit $rc: the entry kills the activation shell"; return 1; }
      [ "$(tail -n 1 "$log")" = __SENTINEL__ ] || { why="the sentinel after the entry never ran: a bare exit, or the entry ate the shell"; return 1; }
    }
    ttw_intact() {
      diff -r "$root/$c.ttw-before" "$S/ttw" > /dev/null 2>&1 || { why="skills/ttw was touched"; return 1; }
    }
    apex_gone() {
      [ ! -e "$A" ] && [ ! -L "$A" ] || { why="skills/apex still there: $(ls -la "$A" 2>&1 | tr '\n' ' ')"; kind=kept; return 1; }
    }
    # $1 file under the apex dir that must survive, $2 its saved copy.
    kept() {
      [ -e "$1" ] || [ -L "$1" ] || { why="$1 removed, but it was not the leftover alone"; kind=deleted; return 1; }
      [ -z "''${2-}" ] || cmp -s "$1" "$2" || { why="$1 rewritten"; kind=deleted; return 1; }
    }
    warned() {
      grep -q 'skills/apex' "$log" || { why="kept skills/apex without a warning naming it"; return 1; }
    }

    # $1 case, $2 script. 0 pass, 1 fail ($why, $kind).
    probe() {
      c="$1"
      why=""
      kind=""
      home_for "$c"
      case "$c" in
        removed-apex-named)
          apex_leftover apex
          retire "$2"; ran_through && apex_gone && ttw_intact ;;
        removed-ttw-named)
          apex_leftover ttw
          retire "$2"; ran_through && apex_gone && ttw_intact ;;
        extra-file-kept)
          apex_leftover apex
          printf 'mine\n' > "$A/notes.md"
          cp "$A/SKILL.md" "$root/$c.skill"
          # kept first: the canary's deletion may also abort the entry, and
          # the deletion is the reason it must be read as.
          retire "$2"; kept "$A/SKILL.md" "$root/$c.skill" && kept "$A/notes.md" && ran_through && warned && ttw_intact ;;
        # A dotfile is invisible to a `*` glob, not to the listing D3 asks for.
        extra-dotfile-kept)
          apex_leftover apex
          printf 'mine\n' > "$A/.keep"
          retire "$2"; ran_through && kept "$A/SKILL.md" && kept "$A/.keep" && warned && ttw_intact ;;
        # skills/apex is the user's link to a dir elsewhere: neither the link
        # nor what it points at is removed.
        symlink-dir-kept)
          mk_skill "$root/$c.elsewhere/SKILL.md" apex
          ln -s "$root/$c.elsewhere" "$A"
          retire "$2"; ran_through && [ -L "$A" ] && kept "$root/$c.elsewhere/SKILL.md" && warned && ttw_intact \
            || { [ -n "$why" ] || { why="the skills/apex link was removed"; kind=deleted; }; return 1; } ;;
        # A SKILL.md that is still a link was never desymlinked: not the leftover.
        symlink-skill-kept)
          mk_skill "$root/$c.target.md" apex
          mkdir -p "$A"
          ln -s "$root/$c.target.md" "$A/SKILL.md"
          retire "$2"; ran_through && kept "$A/SKILL.md" && kept "$root/$c.target.md" && warned && ttw_intact ;;
        # Frontmatter anchored: apex-legacy is another skill.
        name-other-kept)
          apex_leftover apex-legacy
          retire "$2"; ran_through && kept "$A/SKILL.md" && warned && ttw_intact ;;
        # No installed ttw: removing apex would leave no skill at all.
        ttw-missing-kept)
          rm -rf "$S/ttw" "$root/$c.ttw-before"
          apex_leftover apex
          retire "$2"; ran_through && kept "$A/SKILL.md" && warned \
            && { [ ! -e "$S/ttw" ] || { why="skills/ttw created"; return 1; }; } ;;
        dry-run-kept)
          apex_leftover apex
          retire "$2" DRY_RUN=1; ran_through && kept "$A/SKILL.md" && ttw_intact ;;
        absent-noop)
          retire "$2"; ran_through && apex_gone && ttw_intact ;;
        idempotent)
          apex_leftover apex
          tag=first retire "$2"; ran_through && apex_gone || return 1
          retire "$2"; ran_through && apex_gone && ttw_intact ;;
        *)
          why="no such case"; return 2 ;;
      esac
    }

    tag=real
    nfailed=0
    for c0 in ${lib.concatStringsSep " " cases}; do
      tag=real
      if ! probe "$c0" ${runnable}; then
        echo "skill-retire: FAILED — $c0: $why" >&2
        cat "$logs/$c0.real.log" >&2 2> /dev/null || true
        nfailed=$((nfailed + 1))
      fi
    done
    [ "$nfailed" -eq 0 ] || { echo "skill-retire: $nfailed of ${toString (builtins.length cases)} case(s) failed against ${entryName}" >&2; exit 1; }

    # The canary: with the content guard gone the user's dir is retired.
    rm -rf "$root/extra-file-kept" "$root/extra-file-kept.ttw-before"
    tag=canary
    if probe extra-file-kept ${noGuard}; then
      echo "skill-retire: canary survived — extra-file-kept still passes with \`find\` listing nothing, so the case does not test the content guard (or the entry lists the dir without calling find by name)" >&2
      exit 1
    fi
    [ "$kind" = deleted ] || { echo "skill-retire: canary turned extra-file-kept red for the wrong reason ($why)" >&2; exit 1; }
    echo "skill-retire: canary killed by extra-file-kept ($why)"
    echo "skill-retire: ${toString (builtins.length cases)} case(s) green against ${entryName}, 1/1 canary killed"
    touch $out
  '';
in
pkgs.runCommand "skill-retire-check" { } (
  if problems != [ ] then
    throw ("skill-retire:\n  - " + lib.concatStringsSep "\n  - " problems)
  else
    runner
)
