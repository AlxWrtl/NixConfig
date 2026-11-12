# Offline check for the weekly veille step (home/veille/weekly.sh), no network.
# weekly.sh runs with `bash -euo pipefail` (writeShellApplication's options),
# from inside the repo copy, against stub claude/gh (fixtures/hebdo/stub-*),
# in a scratch HOME holding repo/ (CLAUDE.md + .claude/output/ttw/*/00-context.md,
# no .git), vault/, veille/ (inbox.md = 20 real lines mapped by the seed + 18
# synthetic *.example lines) and replay/; HEBDO_WEEK=2026-W47.
#
#   H0  shellcheck -s bash weekly.sh is clean
#   H1  run 1 (fixtures/hebdo/out-run1.json): hebdo/2026-W47.md opens on a
#       front matter holding `semaine: 2026-W47` and renders exactly the 3
#       valid `retenue` URLs (incl. one with every field at its cap, title
#       whole); the écartée / invérifiable URLs are nowhere in the vault, and
#       in ledger.tsv as url⇥verdict⇥2026-W47⇥note (5 lines)
#   H2  entries carrying `[[`, `![`, `<`, `](`, a literal backslash-n, `|`, a
#       javascript: source_primaire, an unknown verdict, a field one char over
#       its cap (titre 120, verification 400, lien_ttw 300, raison 200), a URL
#       never sent (unknown host, or a seed URL) are absent from vault and
#       ledger; backticks are stripped, the entry kept; log line
#       `hebdo: 3 retenue(s), 1 écartée(s), 1 invérifiable(s), 14 rejetée(s), 13 reportée(s)`
#   H7  claude argv: --safe-mode, --model opus, --setting-sources then an
#       empty arg, --permission-prompts none, --tools WebFetch (the only bare
#       WebFetch); every --allowedTools value is WebFetch(domain:<host>),
#       arxiv.org among them; no Read/Bash/Write/Edit/Glob/Grep/WebSearch
#       word, no inbox line, no candidate URL in argv; claude cwd outside the
#       repo and the vault
#   H8  find/stat (mode, size, mtime in ns)/sha256 snapshot of the scratch
#       HOME, minus vault/veille/hebdo and veille/ledger.tsv, identical across
#       run 1; gh argv is exactly
#       `pr list --state merged --json number,title --limit 100`, cwd = repo
#   H5  run 2 the same week (2 lines appended to inbox.md, out-run2.json):
#       2026-W47-2.md holds the new retained URL, 2026-W47.md unchanged,
#       ledger.tsv only appended
#   H6  in runs 1 and 2, every inbox line whose normalised URL (spaces and
#       <> removed) is in seed ∪ ledger is absent from claude stdin, every
#       other inbox line is present verbatim (the ledger-known line carries
#       KNOWNTOKEN and writes its URL as <…>)
#   H3  claude fails (rc 3, is_error), after run 2 and on a fresh HOME:
#       exit != 0, HOME byte-identical (diff -r, so no new directory either),
#       `claude rc=3 subtype=error_during_execution` on stderr
#   H4  gh fails: exit != 0, claude never called, HOME byte-identical
#   H10 claude result without structured_output, or a CLAUDE.md without the
#       `- Settled, do not re-propose:` anchor: exit != 0, HOME byte-identical
#   H9  home/veille/ledger-seed.tsv: 20 lines of 4 tab fields, 3 pr / 7 piste /
#       10 écartée, unique URLs, each byte-equal to the URL of a fixture inbox
#       line; a run whose inbox URLs are all in seed ∪ ledger (one written as
#       <…>) exits 0, never calls claude, writes nothing
#   H11 HEBDO_VAULT, VEILLE_DIR, HEBDO_REPLAY unset: the hebdo file lands under
#       ~/Vaults/AlxVault/02-Projets/nix-darwin/veille/hebdo/, the ledger
#       under ~/.local/share/veille-ttw/
#
# Canaries, each on a copy of weekly.sh whose anchor line must occur exactly
# once (guard: the mutant differs from the source and lacks the anchor):
#   K1  the forbidden-char test turned into `if false; then` must fail H2 on
#       wiki.example
#   K2  the known-URL filter turned into `if false; then` must fail H6 with a
#       known inbox line sent to claude
#   K3  the `--setting-sources '' \` line deleted must fail H7 on
#       --setting-sources
{ pkgs }:

let
  src = ../home/veille;
  week = "2026-W47";
  k1 = ''if [[ "$champ" == *[][\<\>\\\|]* ]]; then'';
  k2 = ''if [ -n "''${connues[$u]+x}" ]; then'';
  k3 = "--setting-sources '' \\";
  esc = pkgs.lib.escapeShellArg;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.gawk
    pkgs.findutils
    pkgs.diffutils
    pkgs.bash
    pkgs.jq
    pkgs.git
    pkgs.shellcheck
  ];
in
pkgs.runCommand "veille-hebdo-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR/nohome"
  mkdir -p "$HOME"

  fail() {
    echo "veille-hebdo: $1"
    for f in "$TMPDIR"/*.out "$TMPDIR"/*.err; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done
    exit 1
  }

  cp -r ${src} "$TMPDIR/veille"
  chmod -R u+w "$TMPDIR/veille"
  dir="$TMPDIR/veille"
  fx="$dir/fixtures/hebdo"
  weekly="$dir/weekly.sh"

  [ -f "$weekly" ] || fail "H0 home/veille/weekly.sh missing"
  shellcheck -s bash "$weekly" > "$TMPDIR/h0.out" 2>&1 || fail "H0 shellcheck weekly.sh not clean"
  echo "veille-hebdo: H0 shellcheck weekly.sh OK"
  [ -f "$dir/ledger-seed.tsv" ] || fail "H9 home/veille/ledger-seed.tsv missing"

  printf '#!%s\nexec bash %s "$@"\n' "$(command -v bash)" "$fx/stub-claude.sh" > "$TMPDIR/claude"
  printf '#!%s\nexec bash %s "$@"\n' "$(command -v bash)" "$fx/stub-gh.sh" > "$TMPDIR/gh"
  chmod +x "$TMPDIR/claude" "$TMPDIR/gh"

  setup() { # $1 name: scratch HOME at $TMPDIR/$1/home, stub logs in $TMPDIR/$1/{log,ghlog}
    local h="$TMPDIR/$1/home"
    mkdir -p "$h/repo/.claude/output/ttw/2026-11-10-exemple" "$h/vault/sessions" "$h/vault/veille" "$h/veille" "$h/replay" "$TMPDIR/$1/log" "$TMPDIR/$1/ghlog"
    cp "$fx/claude-md.md" "$h/repo/CLAUDE.md"
    cp "$fx/ttw-00-context.md" "$h/repo/.claude/output/ttw/2026-11-10-exemple/00-context.md"
    printf '# nix-darwin\n\nHub du projet.\n' > "$h/vault/nix-darwin.md"
    printf '# Session 2026-11-10\n\nRien à signaler.\n' > "$h/vault/sessions/2026-11-10.md"
    printf '# Rejeu TTW 2026-11-09\n\n3 runs rejoués, 0 dérive.\n' > "$h/replay/2026-11-09.md"
    cp "$fx/inbox.md" "$h/veille/inbox.md"
  }
  clone() { # $1 from, $2 to: same HOME content, empty stub logs
    cp -a "$TMPDIR/$1" "$TMPDIR/$2"
    rm -rf "$TMPDIR/$2/log" "$TMPDIR/$2/ghlog"
    mkdir -p "$TMPDIR/$2/log" "$TMPDIR/$2/ghlog"
  }
  hebdo() { # $1 script, $2 name, $3 stub result, $4 STUB_FAIL, $5 STUB_GH_FAIL, $6 run tag; sets rc
    local h="$TMPDIR/$2/home"
    rc=0
    (cd "$h/repo" && env HOME="$h" STUB_LOG="$TMPDIR/$2/log" STUB_GH_LOG="$TMPDIR/$2/ghlog" \
      STUB_RESULT="$3" STUB_FAIL="$4" STUB_GH_FAIL="$5" \
      VEILLE_CLAUDE="$TMPDIR/claude" VEILLE_GH="$TMPDIR/gh" \
      VEILLE_DIR="$h/veille" HEBDO_VAULT="$h/vault" HEBDO_REPO="$h/repo" HEBDO_REPLAY="$h/replay" \
      HEBDO_WEEK=${week} VEILLE_HEBDO_PROMPT="$dir/weekly-prompt.md" \
      VEILLE_HEBDO_SCHEMA="$dir/weekly-schema.json" VEILLE_SEED="$dir/ledger-seed.tsv" \
      bash -euo pipefail "$1") > "$TMPDIR/$6.out" 2> "$TMPDIR/$6.err" || rc=$?
  }
  snap() { # $1 HOME: one line per path, minus hebdo/ and ledger.tsv; dirs by mode only
    (cd "$1" && find . \( -path ./vault/veille/hebdo -o -path ./veille/ledger.tsv \) -prune -o -print | LC_ALL=C sort |
      while IFS= read -r p; do
        if [ -d "$p" ]; then
          printf 'd %s %s\n' "$(stat -c %a "$p")" "$p"
        else
          printf 'f %s %s %s\n' "$(stat -c '%a %s %.9Y' "$p")" "$(sha256sum < "$p" | cut -c1-64)" "$p"
        fi
      done)
  }
  ledger_has() { # $1 ledger, $2 url, $3 verdict: exactly one url⇥verdict⇥week⇥note line
    [ "$(awk -F '\t' -v u="$2" -v v="$3" -v w=${week} 'NF == 4 && $1 == u && $2 == v && $3 == w' "$1" | wc -l)" = 1 ]
  }
  known_urls() { # $1 HOME: seed ∪ ledger URLs, one per line
    cut -f1 "$dir/ledger-seed.tsv"
    if [ -f "$1/veille/ledger.tsv" ]; then cut -f1 "$1/veille/ledger.tsv"; fi
  }

  check_h1() { # $1 HOME after run 1
    local f="$1/vault/veille/hebdo/${week}.md" l="$1/veille/ledger.tsv"
    [ -f "$f" ] || { echo "H1 no vault/veille/hebdo/${week}.md"; return 1; }
    [ "$(sed -n 1p "$f")" = --- ] || { echo "H1 hebdo file does not open on a front matter"; return 1; }
    sed -n '2,/^---$/p' "$f" > "$TMPDIR/h1-fm"
    grep -qxF 'semaine: ${week}' "$TMPDIR/h1-fm" || { echo "H1 front matter lacks 'semaine: ${week}'"; return 1; }
    { grep -oE 'https?://[a-z0-9.-]+\.example/[a-z]*' "$f" || true; } | LC_ALL=C sort -u > "$TMPDIR/h1-urls"
    printf '%s\n' https://cap-ok.example/a https://keep.example/a https://keep.example/b > "$TMPDIR/h1-want"
    cmp -s "$TMPDIR/h1-want" "$TMPDIR/h1-urls" || { echo "H1 hebdo URLs are not exactly the 3 valid retenue entries: $(tr '\n' ' ' < "$TMPDIR/h1-urls")"; return 1; }
    grep -qF "$(printf 'a%.0s' $(seq 120))" "$f" || { echo "H1 the 120-char title is not rendered whole"; return 1; }
    for n in drop.example unsure.example; do
      if grep -rqF "$n" "$1/vault"; then echo "H1 non-retained entry in the vault: $n"; return 1; fi
    done
    [ -f "$l" ] || { echo "H1 no veille/ledger.tsv"; return 1; }
    ledger_has "$l" https://keep.example/a retenue || { echo "H1 ledger lacks keep.example/a retenue ${week}"; return 1; }
    ledger_has "$l" https://keep.example/b retenue || { echo "H1 ledger lacks keep.example/b retenue ${week}"; return 1; }
    ledger_has "$l" https://cap-ok.example/a retenue || { echo "H1 ledger lacks cap-ok.example/a retenue ${week}"; return 1; }
    ledger_has "$l" https://drop.example/a écartée || { echo "H1 ledger lacks drop.example/a écartée ${week}"; return 1; }
    ledger_has "$l" https://unsure.example/a invérifiable || { echo "H1 ledger lacks unsure.example/a invérifiable ${week}"; return 1; }
    [ "$(wc -l < "$l")" = 5 ] || { echo "H1 ledger has $(wc -l < "$l") lines, want 5"; return 1; }
  }
  check_h2() { # $1 HOME after run 1, $2 run tag
    local f="$1/vault/veille/hebdo/${week}.md" l="$1/veille/ledger.tsv"
    for n in wiki.example img.example lt.example link.example nl.example pipe.example js.example verdict.example \
      cap-titre.example cap-verif.example cap-lien.example cap-raison.example ghost.example arxiv.org/abs/2611.08768v1; do
      if grep -rqF "$n" "$1/vault" || grep -qF "$n" "$l"; then
        echo "H2 rejected entry kept: $n"
        return 1
      fi
    done
    grep -qF 'Le flag utile' "$f" || { echo "H2 backtick title not rendered with backticks stripped"; return 1; }
    if grep -rqF '`flag`' "$1/vault" || grep -qF '`' "$l"; then
      echo "H2 backticks kept in vault or ledger"
      return 1
    fi
    grep -qF 'hebdo: 3 retenue(s), 1 écartée(s), 1 invérifiable(s), 14 rejetée(s), 13 reportée(s)' "$TMPDIR/$2.out" || { echo "H2 log counters wrong"; return 1; }
  }
  check_h6() { # $1 claude stdin, $2 inbox.md, $3 known URLs file
    [ -f "$1" ] || { echo "H6 claude not called"; return 1; }
    while IFS= read -r line; do
      u="''${line##*—}"
      u="''${u//[[:space:]<>]/}"
      if grep -qxF -- "$u" "$3"; then
        if grep -qF -- "$line" "$1"; then
          echo "H6 known inbox line sent to claude: $u"
          return 1
        fi
      elif ! grep -qF -- "$line" "$1"; then
        echo "H6 new inbox line missing from claude stdin: $u"
        return 1
      fi
    done < "$2"
    if grep -qF KNOWNTOKEN "$1"; then
      echo "H6 known inbox line sent to claude: KNOWNTOKEN"
      return 1
    fi
  }
  check_h7() { # $1 name (stub logs + HOME)
    local a="$TMPDIR/$1/log/args" h="$TMPDIR/$1/home"
    [ -f "$a" ] || { echo "H7 claude not called"; return 1; }
    pair() { awk -v x="$1" -v y="$2" 'p == x && $0 == y { f = 1 } { p = $0 } END { exit !f }' "$a"; }
    pair --setting-sources "" || { echo "H7 no --setting-sources followed by an empty arg"; return 1; }
    grep -qxF -- --safe-mode "$a" || { echo "H7 no --safe-mode"; return 1; }
    pair --model opus || { echo "H7 no --model opus"; return 1; }
    pair --permission-prompts none || { echo "H7 no --permission-prompts none"; return 1; }
    pair --tools WebFetch || { echo "H7 no --tools WebFetch"; return 1; }
    [ "$(grep -cxF WebFetch "$a")" = 1 ] || { echo "H7 bare WebFetch outside --tools"; return 1; }
    awk 'p == "--allowedTools" { print } { p = $0 }' "$a" > "$TMPDIR/$1-allowed"
    [ -s "$TMPDIR/$1-allowed" ] || { echo "H7 no --allowedTools"; return 1; }
    if grep -vxE 'WebFetch\(domain:[a-z0-9.-]+\)' "$TMPDIR/$1-allowed"; then
      echo "H7 --allowedTools value is not WebFetch(domain:<host>)"
      return 1
    fi
    grep -qxF 'WebFetch(domain:arxiv.org)' "$TMPDIR/$1-allowed" || { echo "H7 arxiv.org not allowed"; return 1; }
    if grep -wE 'Read|Bash|Write|Edit|Glob|Grep|WebSearch' "$a"; then
      echo "H7 forbidden tool name in argv"
      return 1
    fi
    if grep -F -f "$h/veille/inbox.md" "$a"; then
      echo "H7 inbox line in argv"
      return 1
    fi
    if grep -F '.example/' "$a"; then
      echo "H7 candidate URL in argv"
      return 1
    fi
    cwd="$(cat "$TMPDIR/$1/log/cwd")"
    for d in "$(realpath "$h/repo")" "$(realpath "$h/vault")"; do
      case "$cwd/" in "$d"/*)
        echo "H7 claude cwd $cwd inside $d"
        return 1
        ;;
      esac
    done
  }

  # Run 1 — H1, H2, H7, H8
  setup main
  m="$TMPDIR/main/home"
  snap "$m" > "$TMPDIR/h8-before"
  hebdo "$weekly" main "$fx/out-run1.json" "" "" run1
  [ "$rc" = 0 ] || fail "H1 run 1 exit $rc, want 0"
  msg=$(check_h1 "$m") || fail "$msg"
  echo "veille-hebdo: H1 run 1 renders the valid retenue entries, ledger holds all verdicts OK"
  msg=$(check_h2 "$m" run1) || fail "$msg"
  echo "veille-hebdo: H2 malformed entries rejected, backticks stripped OK — $(grep -F 'hebdo: ' "$TMPDIR/run1.out")"
  msg=$(check_h7 main) || fail "$msg"
  echo "veille-hebdo: H7 claude argv and cwd OK"
  snap "$m" > "$TMPDIR/h8-after"
  diff "$TMPDIR/h8-before" "$TMPDIR/h8-after" > "$TMPDIR/h8.out" || fail "H8 run 1 changed something besides hebdo/ and ledger.tsv"
  printf '%s\n' pr list --state merged --json number,title --limit 100 > "$TMPDIR/h8-gh-want"
  cmp -s "$TMPDIR/h8-gh-want" "$TMPDIR/main/ghlog/args" || fail "H8 gh argv is not 'pr list --state merged --json number,title --limit 100'"
  [ "$(cat "$TMPDIR/main/ghlog/cwd")" = "$(realpath "$m/repo")" ] || fail "H8 gh not run in the repo"
  echo "veille-hebdo: H8 only hebdo/ and ledger.tsv change, gh argv exact OK"
  cut -f1 "$dir/ledger-seed.tsv" > "$TMPDIR/h6-seed"
  msg=$(check_h6 "$TMPDIR/main/log/stdin" "$m/veille/inbox.md" "$TMPDIR/h6-seed") || fail "$msg (run 1)"

  # Run 2 — H5, H6
  cat "$fx/inbox-run2-add.md" >> "$m/veille/inbox.md"
  clone main k2
  cp "$m/vault/veille/hebdo/${week}.md" "$TMPDIR/h5-keep.md"
  cp "$m/veille/ledger.tsv" "$TMPDIR/h5-ledger.keep"
  known_urls "$m" > "$TMPDIR/h6-known2"
  rm -f "$TMPDIR/main/log/stdin" "$TMPDIR/main/log/args"
  hebdo "$weekly" main "$fx/out-run2.json" "" "" run2
  [ "$rc" = 0 ] || fail "H5 run 2 exit $rc, want 0"
  cmp -s "$TMPDIR/h5-keep.md" "$m/vault/veille/hebdo/${week}.md" || fail "H5 hebdo/${week}.md changed by run 2"
  [ -f "$m/vault/veille/hebdo/${week}-2.md" ] || fail "H5 run 2 wrote no hebdo/${week}-2.md"
  grep -qF https://second.example/a "$m/vault/veille/hebdo/${week}-2.md" || fail "H5 ${week}-2.md lacks the run 2 retained URL"
  if grep -qF keep.example "$m/vault/veille/hebdo/${week}-2.md"; then fail "H5 ${week}-2.md repeats run 1 entries"; fi
  head -n 5 "$m/veille/ledger.tsv" | cmp -s "$TMPDIR/h5-ledger.keep" - || fail "H5 ledger.tsv rewritten instead of appended"
  ledger_has "$m/veille/ledger.tsv" https://second.example/a retenue || fail "H5 ledger lacks second.example/a"
  echo "veille-hebdo: H5 second run same week lands in ${week}-2.md OK"
  msg=$(check_h6 "$TMPDIR/main/log/stdin" "$m/veille/inbox.md" "$TMPDIR/h6-known2") || fail "$msg (run 2)"
  echo "veille-hebdo: H6 known URLs filtered, new inbox lines sent OK"

  # Failures leave HOME byte-identical — H3, H4, H10
  clone main h3
  cp -a "$TMPDIR/h3/home" "$TMPDIR/h3.before"
  hebdo "$weekly" h3 "$fx/out-run2.json" 1 "" h3
  [ "$rc" != 0 ] || fail "H3 run with a failing claude exit 0"
  diff -r "$TMPDIR/h3.before" "$TMPDIR/h3/home" > "$TMPDIR/h3-diff.out" || fail "H3 failed run modified HOME"
  grep -qF 'claude rc=3 subtype=error_during_execution' "$TMPDIR/h3.err" || fail "H3 claude failure not logged with rc + subtype"
  setup h3fresh
  cp -a "$TMPDIR/h3fresh/home" "$TMPDIR/h3fresh.before"
  hebdo "$weekly" h3fresh "$fx/out-run1.json" 1 "" h3fresh
  [ "$rc" != 0 ] || fail "H3 run with a failing claude exit 0 (fresh HOME)"
  diff -r "$TMPDIR/h3fresh.before" "$TMPDIR/h3fresh/home" > "$TMPDIR/h3fresh-diff.out" || fail "H3 failed run modified a fresh HOME"
  echo "veille-hebdo: H3 failing claude leaves HOME untouched OK"

  clone main h4
  cp -a "$TMPDIR/h4/home" "$TMPDIR/h4.before"
  hebdo "$weekly" h4 "$fx/out-run2.json" "" 1 h4
  [ "$rc" != 0 ] || fail "H4 run with a failing gh exit 0"
  [ ! -e "$TMPDIR/h4/log/args" ] || fail "H4 claude called after gh failed"
  diff -r "$TMPDIR/h4.before" "$TMPDIR/h4/home" > "$TMPDIR/h4-diff.out" || fail "H4 failed run modified HOME"
  echo "veille-hebdo: H4 failing gh, claude never called, HOME untouched OK"

  clone main h10a
  cp -a "$TMPDIR/h10a/home" "$TMPDIR/h10a.before"
  hebdo "$weekly" h10a "$fx/out-nostruct.json" "" "" h10a
  [ "$rc" != 0 ] || fail "H10 result without structured_output exit 0"
  diff -r "$TMPDIR/h10a.before" "$TMPDIR/h10a/home" > "$TMPDIR/h10a-diff.out" || fail "H10 result without structured_output modified HOME"
  clone main h10b
  cp "$fx/claude-md-no-settled.md" "$TMPDIR/h10b/home/repo/CLAUDE.md"
  cp -a "$TMPDIR/h10b/home" "$TMPDIR/h10b.before"
  hebdo "$weekly" h10b "$fx/out-run2.json" "" "" h10b
  [ "$rc" != 0 ] || fail "H10 CLAUDE.md without the Settled anchor exit 0"
  diff -r "$TMPDIR/h10b.before" "$TMPDIR/h10b/home" > "$TMPDIR/h10b-diff.out" || fail "H10 CLAUDE.md without the Settled anchor modified HOME"
  echo "veille-hebdo: H10 no structured_output / no Settled anchor fail closed OK"

  # Seed — H9
  seed="$dir/ledger-seed.tsv"
  [ -f "$seed" ] || fail "H9 home/veille/ledger-seed.tsv missing"
  [ "$(wc -l < "$seed")" = 20 ] || fail "H9 seed has $(wc -l < "$seed") lines, want 20"
  [ -z "$(awk -F '\t' 'NF != 4' "$seed")" ] || fail "H9 seed line without 4 tab-separated fields"
  [ "$(cut -f2 "$seed" | grep -cxF pr)" = 3 ] || fail "H9 seed pr count != 3"
  [ "$(cut -f2 "$seed" | grep -cxF piste)" = 7 ] || fail "H9 seed piste count != 7"
  [ "$(cut -f2 "$seed" | grep -cxF écartée)" = 10 ] || fail "H9 seed écartée count != 10"
  [ -z "$(cut -f1 "$seed" | LC_ALL=C sort | uniq -d)" ] || fail "H9 seed URL listed twice"
  sed 's/.* — //' "$fx/inbox.md" > "$TMPDIR/h9-inbox-urls"
  while IFS= read -r u; do
    grep -qxF -- "$u" "$TMPDIR/h9-inbox-urls" || fail "H9 seed URL not byte-equal to a fixture inbox URL: $u"
  done < "$TMPDIR/h6-seed"
  setup h9
  h9="$TMPDIR/h9/home"
  grep -F -f "$TMPDIR/h6-seed" "$fx/inbox.md" > "$h9/veille/inbox.md"
  [ "$(wc -l < "$h9/veille/inbox.md")" = 20 ] || fail "H9 fixture inbox does not hold the 20 seed lines"
  printf '%s\n' '- [2026-11-05] Ancienne — déjà jugée — blog — <https://old.example/a>' >> "$h9/veille/inbox.md"
  printf 'https://old.example/a\técartée\t2026-W46\thors sujet\n' > "$h9/veille/ledger.tsv"
  cp -a "$h9" "$TMPDIR/h9.before"
  hebdo "$weekly" h9 "$fx/out-run1.json" "" "" h9
  [ "$rc" = 0 ] || fail "H9 run with nothing new exit $rc, want 0"
  [ ! -e "$TMPDIR/h9/log/args" ] || fail "H9 claude called with no candidate"
  diff -r "$TMPDIR/h9.before" "$h9" > "$TMPDIR/h9-diff.out" || fail "H9 run with no candidate wrote something"
  echo "veille-hebdo: H9 seed 3 pr / 7 piste / 10 écartée, nothing new = no claude, no write OK"

  # Defaults — H11
  h11="$TMPDIR/h11/home"
  mkdir -p "$h11/.local/share/veille-ttw" "$h11/Vaults/AlxVault/02-Projets/nix-darwin" "$h11/repo" "$TMPDIR/h11/log" "$TMPDIR/h11/ghlog"
  cp "$fx/inbox.md" "$h11/.local/share/veille-ttw/inbox.md"
  cp "$fx/claude-md.md" "$h11/repo/CLAUDE.md"
  printf '# nix-darwin\n' > "$h11/Vaults/AlxVault/02-Projets/nix-darwin/nix-darwin.md"
  rc=0
  (cd "$h11/repo" && env -u HEBDO_VAULT -u VEILLE_DIR -u HEBDO_REPLAY HOME="$h11" \
    STUB_LOG="$TMPDIR/h11/log" STUB_GH_LOG="$TMPDIR/h11/ghlog" STUB_RESULT="$fx/out-run1.json" \
    VEILLE_CLAUDE="$TMPDIR/claude" VEILLE_GH="$TMPDIR/gh" HEBDO_REPO="$h11/repo" HEBDO_WEEK=${week} \
    VEILLE_HEBDO_PROMPT="$dir/weekly-prompt.md" VEILLE_HEBDO_SCHEMA="$dir/weekly-schema.json" VEILLE_SEED="$seed" \
    bash -euo pipefail "$weekly") > "$TMPDIR/h11.out" 2> "$TMPDIR/h11.err" || rc=$?
  [ "$rc" = 0 ] || fail "H11 default run exit $rc"
  [ -f "$h11/Vaults/AlxVault/02-Projets/nix-darwin/veille/hebdo/${week}.md" ] || fail "H11 hebdo file not under ~/Vaults/AlxVault/02-Projets/nix-darwin/veille/hebdo/"
  [ -f "$h11/.local/share/veille-ttw/ledger.tsv" ] || fail "H11 ledger not under ~/.local/share/veille-ttw/"
  echo "veille-hebdo: H11 default vault and VEILLE_DIR OK"

  # Canaries
  mutate() { # $1 anchor, $2 replacement ("" = delete the line), $3 mutant path
    if [ -z "$2" ]; then
      grep -vF -- "$1" "$weekly" > "$3" || true
    else
      A="$1" R="$2" awk '{ i = index($0, ENVIRON["A"]); if (i) $0 = substr($0, 1, i - 1) ENVIRON["R"] substr($0, i + length(ENVIRON["A"])) } 1' "$weekly" > "$3"
    fi
    if [ "$(grep -cF -- "$1" "$weekly")" != 1 ] || grep -qF -- "$1" "$3" || cmp -s "$weekly" "$3"; then
      fail "canary anchor '$1' not exactly once in weekly.sh — the mutant equals the source"
    fi
  }

  mutate ${esc k1} 'if false; then' "$TMPDIR/weekly-k1.sh"
  setup k1
  hebdo "$TMPDIR/weekly-k1.sh" k1 "$fx/out-run1.json" "" "" k1
  [ "$rc" = 0 ] || fail "canary K1 killed by the wrong reason — mutant run exit $rc"
  rc=0
  msg=$(check_h2 "$TMPDIR/k1/home" k1) || rc=$?
  [ "$rc" != 0 ] || fail "canary K1 SURVIVED — H2 passes without the forbidden-char test"
  [ "$msg" = "H2 rejected entry kept: wiki.example" ] || fail "canary K1 killed by the wrong reason: $msg"
  echo "veille-hebdo: canary K1 killed — $msg"

  mutate ${esc k2} 'if false; then' "$TMPDIR/weekly-k2.sh"
  hebdo "$TMPDIR/weekly-k2.sh" k2 "$fx/out-run2.json" "" "" k2
  [ "$rc" = 0 ] || fail "canary K2 killed by the wrong reason — mutant run exit $rc"
  rc=0
  msg=$(check_h6 "$TMPDIR/k2/log/stdin" "$TMPDIR/k2/home/veille/inbox.md" "$TMPDIR/h6-known2") || rc=$?
  [ "$rc" != 0 ] || fail "canary K2 SURVIVED — H6 passes without the known-URL filter"
  case "$msg" in "H6 known inbox line sent to claude: "*) ;; *) fail "canary K2 killed by the wrong reason: $msg" ;; esac
  echo "veille-hebdo: canary K2 killed — $msg"

  mutate ${esc k3} "" "$TMPDIR/weekly-k3.sh"
  setup k3
  hebdo "$TMPDIR/weekly-k3.sh" k3 "$fx/out-run1.json" "" "" k3
  [ "$rc" = 0 ] || fail "canary K3 killed by the wrong reason — mutant run exit $rc"
  rc=0
  msg=$(check_h7 k3) || rc=$?
  [ "$rc" != 0 ] || fail "canary K3 SURVIVED — H7 passes without --setting-sources '''"
  [ "$msg" = "H7 no --setting-sources followed by an empty arg" ] || fail "canary K3 killed by the wrong reason: $msg"
  echo "veille-hebdo: canary K3 killed — $msg"

  echo "veille-hebdo: 12 cases, 3 canaries — OK"
  touch $out
''
