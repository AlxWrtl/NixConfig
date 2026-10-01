# Non-regression check for the `trello` CLI wrapper (home/claude-code/trello.nix).
#
# The wrapper exists so that Trello calls stop looking like "read a secret,
# then send it out" to the auto-mode classifier. That only holds while:
#   - the key + token never reach curl's argv, the URL, stdout or stderr;
#   - ids are validated before any secret read or network call;
#   - the skill and /card drive Trello through bare `trello …` calls only;
#   - settings allow `Bash(trello *)` and nothing broader.
#
# Three layers, all offline:
#   A. eval-time text asserts on skillTrello / cmdCard;
#   B. eval-time asserts on settings.json;
#   C. runtime suite: the BUILT binary runs against a stub curl that records
#      argv + stdin per call (r01-r17).
# Canaries: three mutants of the script go through the same suite and must FAIL
# at the expected case, for the expected reason — C1 moves the secrets into the
# URL (killed by r06 "secret in argv"), C2 disables id validation (killed by
# r07 "curl called"), C3 drops `set +o xtrace` (killed by r15 "secret in
# stdout/stderr"). A canary that survives, or dies elsewhere, fails the
# check: it proves the suite can go red. An eval-time guard fails if a canary
# anchor is gone from the script (the mutant would equal the source).
{ pkgs }:

let
  inherit (pkgs.lib)
    hasInfix
    hasPrefix
    attrByPath
    splitString
    ;

  skills = import ../home/claude-code/skills.nix;
  commands = import ../home/claude-code/commands.nix;
  # Same import as home/claude-code.nix and checks/claude-config.nix; the
  # home directory is only interpolated into path strings.
  settings = import ../home/claude-code/settings.nix { homeDirectory = "/Users/alx"; };
  trello = import ../home/claude-code/trello.nix { inherit pkgs; };

  source = builtins.readFile ../home/claude-code/scripts/trello.sh;

  # Occurrences of a literal needle: length delta, not a regex.
  count =
    needle: hay:
    (builtins.stringLength hay - builtins.stringLength (builtins.replaceStrings [ needle ] [ "" ] hay))
    / builtins.stringLength needle;

  # --- canaries -----------------------------------------------------------
  c1Anchor = "\"\${API}/\${path}\"";
  c1Mutant = "\"\${API}/\${path}?key=\${key}&token=\${token}\"";
  c2Anchor = "'^([0-9a-fA-F]{24}|[A-Za-z0-9]{8})$'";
  c2Mutant = "'.*'";
  c3Anchor = "\nset +o xtrace\n";
  c3Mutant = "\n";
  c1Text = builtins.replaceStrings [ c1Anchor ] [ c1Mutant ] source;
  c2Text = builtins.replaceStrings [ c2Anchor ] [ c2Mutant ] source;
  c3Text = builtins.replaceStrings [ c3Anchor ] [ c3Mutant ] source;

  # --- A. skill + /card text ------------------------------------------------
  forbidden = [
    "api.trello.com/1/"
    "curl -"
    "$("
    "AUTH="
    "key=$"
    "cat \"$HOME/.config/secrets"
  ];
  requiredBoth = [
    "trello card"
    "trello comment"
    "trello move"
    "Tech & Pit"
  ];
  requiredCard = requiredBoth ++ [
    "trello find-list"
    "trello search"
  ];
  # Rendered by the contract / scope / handoffs helpers of skills.nix.
  skillSections = [
    "\n## Input/Output Contract\n- **Expects:** "
    "\n## Scope\n- **Use this skill when:** "
    "\n## Handoffs\n- "
  ];
  # User rule (2026-08-14): test writes go to the throwaway board only.
  testWriteRule = [
    "Test writes (throwaway cards, command validation, dry runs) go to the"
    "no-stakes board **Tech & Pit**"
    "only test WRITES are restricted"
  ];
  # /card success destination + every no-write / stop branch.
  cardBranches = [
    "DONE_LIST"
    "0 hit (empty output) → STOP"
    "2+ hits → list the candidates"
    "NEVER guess"
    "ZERO Trello write"
    "no Trello write — run did not complete"
    "keep the comment, skip the move"
  ];
  hits = text: builtins.filter (n: hasInfix n text) forbidden;
  missing = req: text: builtins.filter (n: !(hasInfix n text)) req;
  # Offset of the first occurrence of a literal needle (escaped by
  # splitString); stringLength hay when absent.
  firstAt = needle: hay: builtins.stringLength (builtins.head (splitString needle hay));
  commentAt = firstAt "trello comment" commands.cmdCard;
  moveAt = firstAt "trello move" commands.cmdCard;

  # --- B. settings ------------------------------------------------------------
  parsed = builtins.tryEval (builtins.fromJSON settings.settingsJson);
  s = if parsed.success && builtins.isAttrs parsed.value then parsed.value else { };
  allow = attrByPath [ "permissions" "allow" ] [ ] s;
  excluded = attrByPath [ "sandbox" "excludedCommands" ] [ ] s;
  allowRead = attrByPath [ "sandbox" "filesystem" "allowRead" ] [ ] s;
  environment = attrByPath [ "autoMode" "environment" ] [ ] s;
  autoAllow = attrByPath [ "autoMode" "allow" ] [ ] s;

  assertions = [
    {
      name = "A1 skillTrello: no curl, secret read or command substitution";
      ok = hits skills.skillTrello == [ ];
      msg = "found " + builtins.toJSON (hits skills.skillTrello);
    }
    {
      name = "A2 cmdCard: no curl, secret read or command substitution";
      ok = hits commands.cmdCard == [ ];
      msg = "found " + builtins.toJSON (hits commands.cmdCard);
    }
    {
      name = "A3 skillTrello: drives the `trello` CLI";
      ok = missing requiredBoth skills.skillTrello == [ ];
      msg = "missing " + builtins.toJSON (missing requiredBoth skills.skillTrello);
    }
    {
      name = "A4 cmdCard: drives the `trello` CLI";
      ok = missing requiredCard commands.cmdCard == [ ];
      msg = "missing " + builtins.toJSON (missing requiredCard commands.cmdCard);
    }
    {
      name = "A5 skillTrello: contract / scope / handoffs sections rendered";
      ok = missing skillSections skills.skillTrello == [ ];
      msg = "missing " + builtins.toJSON (missing skillSections skills.skillTrello);
    }
    {
      name = "A6 skillTrello + cmdCard: test-write rule kept";
      ok =
        missing testWriteRule skills.skillTrello == [ ] && missing testWriteRule commands.cmdCard == [ ];
      msg =
        "skillTrello missing "
        + builtins.toJSON (missing testWriteRule skills.skillTrello)
        + ", cmdCard missing "
        + builtins.toJSON (missing testWriteRule commands.cmdCard);
    }
    {
      name = "A7 cmdCard: DONE_LIST and the stop / no-write branches";
      ok = missing cardBranches commands.cmdCard == [ ];
      msg = "missing " + builtins.toJSON (missing cardBranches commands.cmdCard);
    }
    {
      name = "A8 cmdCard: `trello comment` comes before `trello move`";
      ok =
        hasInfix "trello comment" commands.cmdCard
        && hasInfix "trello move" commands.cmdCard
        && commentAt < moveAt;
      msg = "first `trello comment` at ${toString commentAt}, first `trello move` at ${toString moveAt} — the comment is the first success write, the move the last";
    }
    {
      name = "B1 settings.json parses";
      ok = parsed.success && s != { };
      msg = "settingsJson did not parse — every B assert below would be vacuous";
    }
    {
      name = "B2 allow has Bash(trello *) and no Bash(curl …)";
      ok =
        builtins.elem "Bash(trello *)" allow && builtins.filter (r: hasPrefix "Bash(curl" r) allow == [ ];
      msg = "permissions.allow must hold `Bash(trello *)` and no `Bash(curl…)` rule — the wrapper exists so that curl is not granted";
    }
    {
      name = "B3 trello never excluded from the sandbox";
      ok = excluded != [ ] && builtins.filter (c: hasInfix "trello" c) excluded == [ ];
      msg = "sandbox.excludedCommands is empty (vacuous) or names trello — the wrapper must run sandboxed";
    }
    {
      name = "B4 allowRead re-opens both trello secret files";
      ok =
        builtins.elem "/Users/alx/.config/secrets/trello-api-key" allowRead
        && builtins.elem "/Users/alx/.config/secrets/trello-token" allowRead;
      msg = "sandbox.filesystem.allowRead lost a trello secret file — the sandboxed wrapper can no longer read it";
    }
    {
      name = "B5 autoMode.environment: $defaults first + api.trello.com via `trello`";
      ok =
        environment != [ ]
        && builtins.head environment == "$defaults"
        && builtins.any (e: hasInfix "api.trello.com" e && hasInfix "`trello`" e) environment;
      msg = "autoMode.environment must start with \"$defaults\" and name api.trello.com reached through the `trello` wrapper";
    }
    {
      name = "B6 no autoMode.allow line for trello";
      ok = builtins.filter (e: hasInfix "trello" e) autoAllow == [ ];
      msg = "autoMode.allow names trello — the plan grants it through `Bash(trello *)` only";
    }
    {
      name = "G1 canary anchors occur exactly once";
      ok = count c1Anchor source == 1 && count c2Anchor source == 1 && count c3Anchor source == 1;
      msg = "C1 anchor x${toString (count c1Anchor source)}, C2 anchor x${toString (count c2Anchor source)}, C3 anchor x${toString (count c3Anchor source)} in scripts/trello.sh — update the anchors with the script";
    }
    {
      name = "G2 canary mutants differ from the source";
      ok = c1Text != source && c2Text != source && c3Text != source;
      msg = "a canary mutant equals the source — it would test nothing";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;

  # --- C. runtime suite ---------------------------------------------------------
  # Stub curl: bash builtins only (the wrapper's PATH is curl + jq, nothing
  # else). Records argv (NUL-separated) and stdin per call in $STUB_DIR, answers
  # from fixtures keyed on the URL (last argument), then prints `\n<code>` like
  # `-w '\n%{http_code}'`. STUB_MODE=401 -> HTTP 401; STUB_MODE=net -> exit 6;
  # STUB_MODE=body -> HTTP 200 with $STUB_BODY.
  stubCurl = pkgs.writeShellScriptBin "curl" ''
    dir="''${STUB_DIR:?STUB_DIR unset}"
    n=0
    while [ -e "$dir/call$n.argv" ]; do n=$((n + 1)); done
    printf '%s\0' "$@" >"$dir/call$n.argv"
    input=""
    IFS= read -r -d "" input || true
    printf '%s' "$input" >"$dir/call$n.stdin"
    url="''${!#}"
    case "''${STUB_MODE:-}" in
    net)
      echo "curl: (6) Could not resolve host: api.trello.com" >&2
      exit 6
      ;;
    401)
      printf '%s\n401' "''${STUB_401_BODY:-invalid token}"
      exit 0
      ;;
    body)
      printf '%s\n200' "''${STUB_BODY:?STUB_BODY unset}"
      exit 0
      ;;
    esac
    code=200
    case "$url" in
    */members/me/boards\?*) body='[{"id":"b0b0b0b0b0b0b0b0b0b0b0b0","name":"Alpha"},{"id":"5a5a5a5a5a5a5a5a5a5a5a5a","name":"Tech & Pit"}]' ;;
    */boards/*/lists\?*) body='[{"id":"1111111111111111111111aa","name":"To Do"},{"id":"2222222222222222222222bb","name":"Done"}]' ;;
    */lists/*/cards\?*) body='[{"id":"c1c1c1c1c1c1c1c1c1c1c1c1","name":"First card","shortUrl":"https://trello.com/c/aB3dEf9h"}]' ;;
    */search) body='{"cards":[{"id":"c1c1c1c1c1c1c1c1c1c1c1c1","name":"Fix login","shortUrl":"https://trello.com/c/aB3dEf9h"}]}' ;;
    */checklists) body='[{"id":"ck","name":"AC","checkItems":[{"name":"item","state":"incomplete"}]}]' ;;
    */actions/comments) body='{"id":"acacacacacacacacacacacac"}' ;;
    */actions\?*) body='[{"date":"2026-09-30T10:00:00.000Z","memberCreator":{"fullName":"Alex"},"data":{"text":"first"}}]' ;;
    */cards/*) body='{"id":"c1c1c1c1c1c1c1c1c1c1c1c1","name":"Fix login","desc":"d","idList":"1111111111111111111111aa","idBoard":"b0b0b0b0b0b0b0b0b0b0b0b0","shortUrl":"https://trello.com/c/aB3dEf9h"}' ;;
    */cards) body='{"id":"d1d1d1d1d1d1d1d1d1d1d1d1","shortUrl":"https://trello.com/c/Zz9Yy8Xx"}' ;;
    *)
      code=404
      body='The requested resource was not found.'
      ;;
    esac
    printf '%s\n%s' "$body" "$code"
  '';

  real = trello.mkTrello { curl = stubCurl; };
  c1 = trello.mkTrello {
    curl = stubCurl;
    text = c1Text;
  };
  c2 = trello.mkTrello {
    curl = stubCurl;
    text = c2Text;
  };
  c3 = trello.mkTrello {
    curl = stubCurl;
    text = c3Text;
  };

  # suite <trello binary> <work dir> — prints PASS rNN per case; first failure
  # prints `FAIL rNN: <reason>` (exact line, matched by the canary gate) and
  # exits 1.
  suite = pkgs.writeShellScript "trello-cli-suite" ''
    set -u
    bin="$1"
    work="$2"
    KEY=k7Qm2Xv9Lp4Rt8Wz1Nc6Hb3Jd5Fg0Sa
    TOKEN=T0kEn9a8B7c6D5e4F3g2H1i0J9k8L7m6N5o4P3q2R1s0T9u8V7w6X5y4Z3a2B1c0
    BOARD=b0b0b0b0b0b0b0b0b0b0b0b0
    CARD=aB3dEf9h
    LIST=1111111111111111111111aa
    DONE=2222222222222222222222bb
    T=$'\t'
    mkdir -p "$work/ok/.config/secrets" "$work/none" "$work/bad/.config/secrets"
    printf '%s\n' "$KEY" >"$work/ok/.config/secrets/trello-api-key"
    printf '%s\n' "$TOKEN" >"$work/ok/.config/secrets/trello-token"
    printf '%s\n' 'abc"def' >"$work/bad/.config/secrets/trello-api-key"
    printf '%s\n' "$TOKEN" >"$work/bad/.config/secrets/trello-token"
    mkdir -p "$work/sp/.config/secrets" "$work/pad/.config/secrets"
    printf '%s\n' 'abc def' >"$work/sp/.config/secrets/trello-api-key"
    printf '%s\n' "$TOKEN" >"$work/sp/.config/secrets/trello-token"
    printf ' \t%s \r\n\n' "$KEY" >"$work/pad/.config/secrets/trello-api-key"
    printf '\n%s\t\n' "$TOKEN" >"$work/pad/.config/secrets/trello-token"
    seq=0
    case=""
    last=""
    rc=0

    fail() {
      echo "FAIL $case: $*"
      echo "--- stdout"
      cat "$last/out" 2>/dev/null
      echo "--- stderr"
      cat "$last/err" 2>/dev/null
      exit 1
    }
    # t <home> <args...> — stdin from $IN, stub mode from $MODE, success body
    # from $BODY; XTRACE=1 runs the binary with SHELLOPTS=xtrace (readonly in
    # bash, hence `env`).
    t() {
      local home="$1"
      local -a pre=()
      shift
      seq=$((seq + 1))
      last="$work/run$seq"
      mkdir -p "$last"
      [ -z "''${XTRACE:-}" ] || pre=(env SHELLOPTS=xtrace)
      HOME="$work/$home" STUB_DIR="$last" STUB_MODE="''${MODE:-}" STUB_401_BODY="''${BODY401:-}" STUB_BODY="''${BODY:-}" \
        "''${pre[@]}" "$bin" "$@" >"$last/out" 2>"$last/err" <"''${IN:-/dev/null}"
      rc=$?
    }
    calls() {
      local n=0
      while [ -e "$last/call$n.argv" ]; do n=$((n + 1)); done
      echo "$n"
    }
    expect_rc() { [ "$rc" = "$1" ] || fail "exit $rc, expected $1"; }
    expect_calls() {
      local c
      c=$(calls)
      if [ "$1" = 0 ] && [ "$c" != 0 ]; then fail "curl called"; fi
      [ "$c" = "$1" ] || fail "$c curl calls, expected $1"
    }
    # No secret in any argv of this run.
    argv_clean() {
      local f
      for f in "$last"/call*.argv; do
        [ -e "$f" ] || continue
        if grep -qaF -e "$KEY" -e "$TOKEN" "$f"; then fail "secret in argv"; fi
      done
    }
    out_clean() {
      if grep -qaF -e "$KEY" -e "$TOKEN" "$last/out" "$last/err"; then fail "secret in stdout/stderr"; fi
    }
    # argv_has <call#> <exact element>
    argv_has() {
      local -a av
      local a
      mapfile -d "" -t av <"$last/call$1.argv"
      for a in "''${av[@]}"; do [ "$a" = "$2" ] && return 0; done
      return 1
    }
    argv_get() {
      local -a av
      mapfile -d "" -t av <"$last/call$1.argv"
      printf '%s' "''${av[$2]}"
    }
    argv_last() {
      local -a av
      mapfile -d "" -t av <"$last/call$1.argv"
      printf '%s' "''${av[-1]}"
    }
    err_has() { grep -qF -- "$1" "$last/err" || fail "stderr lacks '$1'"; }
    out_is() { [ "$(cat "$last/out")" = "$1" ] || fail "stdout is '$(cat "$last/out")', expected '$1'"; }
    pass() { echo "PASS $case"; }

    case=r01
    t ok
    expect_calls 0
    expect_rc 2
    grep -qF "Usage:" "$last/err" || fail "no usage on stderr"
    pass

    case=r02
    t ok --help
    expect_calls 0
    expect_rc 0
    grep -qF "Usage:" "$last/out" || fail "no usage on stdout"
    pass

    case=r03
    t ok bogus
    expect_calls 0
    expect_rc 2
    pass

    case=r04
    t none boards
    expect_calls 0
    expect_rc 1
    err_has "trello-api-key"
    pass

    case=r05
    t bad boards
    expect_calls 0
    expect_rc 1
    err_has "malformed"
    out_clean
    pass

    case=r06
    t ok boards
    argv_clean
    expect_rc 0
    expect_calls 1
    [ "$(argv_get 0 0)" = "-q" ] || fail "argv[0] is '$(argv_get 0 0)', expected -q"
    argv_has 0 -K || fail "no -K in argv"
    k=0
    mapfile -d "" -t av <"$last/call0.argv"
    for i in "''${!av[@]}"; do
      if [ "''${av[$i]}" = -K ] && [ "''${av[$((i + 1))]:-}" = - ]; then k=1; fi
    done
    [ "$k" = 1 ] || fail "no '-K -' in argv"
    argv_has 0 -w || fail "no -w in argv"
    argv_has 0 'https://api.trello.com/1/members/me/boards?fields=id,name&filter=open' || fail "boards URL"
    grep -qF "oauth_consumer_key=\\\"$KEY\\\"" "$last/call0.stdin" || fail "key not in the stdin header"
    grep -qF "oauth_token=\\\"$TOKEN\\\"" "$last/call0.stdin" || fail "token not in the stdin header"
    grep -qF 'header = "Authorization: OAuth ' "$last/call0.stdin" || fail "no Authorization header line on stdin"
    out_clean
    out_is "$BOARD''${T}Alpha
    5a5a5a5a5a5a5a5a5a5a5a5a''${T}Tech & Pit"
    # Other list-like subcommands: same TSV contract, same secret hygiene.
    t ok lists "$BOARD"
    argv_clean
    expect_rc 0
    out_is "$LIST''${T}To Do
    $DONE''${T}Done"
    t ok cards "$LIST"
    argv_clean
    expect_rc 0
    out_is "c1c1c1c1c1c1c1c1c1c1c1c1''${T}First card''${T}https://trello.com/c/aB3dEf9h"
    t ok search fix login
    argv_clean
    expect_rc 0
    argv_has 0 "query=fix login" || fail "search query not passed as --url-query"
    argv_has 0 "modelTypes=cards" || fail "search modelTypes"
    out_is "c1c1c1c1c1c1c1c1c1c1c1c1''${T}Fix login''${T}https://trello.com/c/aB3dEf9h"
    out_clean
    pass

    case=r07
    # Word-split on purpose; -f keeps `a?b` from globbing.
    set -f
    for args in "card ../x" "card a?b" "lists ../x" "move $CARD ../x" "cards a?b" "comment ../x hi"; do
      # shellcheck disable=SC2086
      t ok $args
      expect_calls 0
      expect_rc 2
    done
    set +f
    t ok card ""
    expect_calls 0
    expect_rc 2
    pass

    case=r08
    MODE=401 BODY401="invalid token $KEY" t ok boards
    expect_rc 1
    err_has "HTTP 401"
    err_has "invalid token"
    err_has "trello-token"
    err_has "[redacted]"
    out_clean
    pass

    case=r09
    MODE=net t ok boards
    expect_rc 1
    err_has "network error"
    out_clean
    pass

    case=r10
    printf 'a\nb\n' >"$work/comment.in"
    IN="$work/comment.in" t ok comment "$CARD" -
    argv_clean
    expect_rc 0
    expect_calls 1
    argv_has 0 "text=a
    b" || fail "comment text is not 'a<LF>b'"
    argv_has 0 POST || fail "comment is not a POST"
    [ "$(argv_last 0)" = "https://api.trello.com/1/cards/$CARD/actions/comments" ] || fail "comment URL is '$(argv_last 0)'"
    out_is "commented $CARD (acacacacacacacacacacacac)"
    out_clean
    pass

    case=r11
    t ok comment "$CARD"
    expect_calls 0
    expect_rc 2
    t ok comment "$CARD" -
    expect_calls 0
    expect_rc 2
    pass

    case=r12
    t ok find-list "$BOARD" done
    argv_clean
    expect_rc 0
    out_is "$DONE"
    t ok find-list "$BOARD" Nope
    expect_rc 1
    err_has "To Do"
    err_has "Done"
    pass

    case=r13
    t ok card "$CARD"
    argv_clean
    expect_rc 0
    expect_calls 3
    jq -e '(keys == ["card", "checklists", "comments"]) and .card.idBoard == "b0b0b0b0b0b0b0b0b0b0b0b0" and .checklists[0].name == "AC" and .comments[0].author == "Alex" and .comments[0].text == "first" and .comments[0].date == "2026-09-30T10:00:00.000Z"' "$last/out" >/dev/null || fail "card JSON shape"
    out_clean
    pass

    case=r14
    printf 'line1\nline2\n' >"$work/desc.in"
    IN="$work/desc.in" t ok create "$LIST" "My card" -
    argv_clean
    expect_rc 0
    argv_has 0 POST || fail "create is not a POST"
    argv_has 0 "idList=$LIST" || fail "create idList"
    argv_has 0 "name=My card" || fail "create name"
    argv_has 0 "desc=line1
    line2" || fail "create desc"
    [ "$(argv_last 0)" = "https://api.trello.com/1/cards" ] || fail "create URL is '$(argv_last 0)'"
    out_is "d1d1d1d1d1d1d1d1d1d1d1d1''${T}https://trello.com/c/Zz9Yy8Xx"
    t ok move "$CARD" "$DONE"
    argv_clean
    expect_rc 0
    argv_has 0 PUT || fail "move is not a PUT"
    argv_has 0 "idList=$DONE" || fail "move idList"
    [ "$(argv_last 0)" = "https://api.trello.com/1/cards/$CARD" ] || fail "move URL is '$(argv_last 0)'"
    out_is "moved $CARD -> $DONE"
    out_clean
    pass

    case=r15
    # Inherited SHELLOPTS=xtrace: bash would trace every secret assignment.
    XTRACE=1 t ok boards
    expect_rc 0
    expect_calls 1
    out_clean
    pass

    case=r16
    # A success body that echoes the secrets (e.g. a board named after them).
    MODE=body BODY="[{\"id\":\"$BOARD\",\"name\":\"n $TOKEN $KEY\"}]" t ok boards
    expect_rc 0
    out_clean
    out_is "$BOARD''${T}n [redacted] [redacted]"
    pass

    case=r17
    # Embedded whitespace is malformed; surrounding whitespace is trimmed.
    t sp boards
    expect_calls 0
    expect_rc 1
    err_has "malformed"
    t pad boards
    expect_rc 0
    expect_calls 1
    grep -qF "oauth_consumer_key=\\\"$KEY\\\", oauth_token=\\\"$TOKEN\\\"" "$last/call0.stdin" || fail "padded secrets not trimmed in the header"
    out_clean
    pass

    echo "suite: 17 cases"
  '';

  fail = msg: throw "trello-cli: ${msg}";
in
pkgs.runCommand "trello-cli-check" { nativeBuildInputs = [ pkgs.jq ]; } (
  if failures != [ ] then
    fail (
      "${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    ''
      # inheritPath = false: the wrapper's PATH must not end with the caller's.
      grep -q '^export PATH=' ${real}/bin/trello || { echo "trello-cli: no PATH line in the wrapper"; exit 1; }
      if grep '^export PATH=' ${real}/bin/trello | grep -qF '$PATH'; then
        echo "trello-cli: the wrapper inherits the caller's PATH (inheritPath must be false)"
        exit 1
      fi

      ${suite} ${real}/bin/trello "$TMPDIR/real" >real.log 2>&1 || {
        cat real.log
        echo "trello-cli: suite FAILED on the real binary"
        exit 1
      }
      cat real.log
      for r in r01 r02 r03 r04 r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17; do
        grep -qx "PASS $r" real.log || { echo "trello-cli: case $r did not run"; exit 1; }
      done

      canary() {
        if ${suite} "$2" "$TMPDIR/$1" >"$1.log" 2>&1; then
          cat "$1.log"
          echo "trello-cli: canary $1 SURVIVED — the suite cannot see its fault"
          exit 1
        fi
        grep -qxF "$3" "$1.log" || {
          cat "$1.log"
          echo "trello-cli: canary $1 killed for the wrong reason (expected: $3)"
          exit 1
        }
        echo "trello-cli: canary $1 killed — $3"
      }
      canary C1 ${c1}/bin/trello "FAIL r06: secret in argv"
      canary C2 ${c2}/bin/trello "FAIL r07: curl called"
      canary C3 ${c3}/bin/trello "FAIL r15: secret in stdout/stderr"

      echo "trello-cli: ${toString (builtins.length assertions)} invariants, 17 runtime cases, 3 canaries — OK"
      touch $out
    ''
)
