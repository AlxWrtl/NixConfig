# Non-regression check for the `preprod-curl` wrapper
# (home/claude-code/preprod-curl.nix, script home/claude-code/scripts/preprod-curl.sh).
#
# The wrapper reaches the Preliz preprod (Cloudflare Access) with a service
# token and, on request, a better-auth session. That only holds while:
#   - the host is fixed and the PATH validated before any secret read;
#   - the Access id/secret travel on curl's stdin config only (`-K -`), the
#     sign-in email + password in a process-substitution fd only, never in argv;
#   - `--as` takes an account slug, validated before any secret read; it signs
#     in as agent-<account>@preliz.com with the password of the file
#     preliz-preprod-<account>-password (whole file, trimmed);
#   - redirects are never followed (an Access header would follow them);
#   - stdout/stderr are scrubbed (Set-Cookie, id, secret, passwords, jar);
#   - settings grant `Bash(preprod-curl *)`, box the writes, open the Access
#     token files and ONE glob preliz-preprod-*-password (one path component),
#     nothing else under ~/.config/secrets.
#
# Two layers, all offline:
#   B. eval-time asserts on settings.json (B1-B8);
#   C. runtime suite: the BUILT binary runs against a stub curl that records
#      argv, stdin and every `@/dev/fd/N` payload per call (p01-p16), plus the
#      PATH line of the built wrapper (p17).
# Canaries: eleven mutants of the script (C1-C11) go through the same suite and
# must FAIL at the expected case, for the expected reason. An eval-time guard
# (G1) fails if a canary anchor is not in the script exactly once.
{ pkgs }:

let
  inherit (pkgs.lib)
    hasInfix
    hasPrefix
    attrByPath
    ;

  settings = import ../home/claude-code/settings.nix { homeDirectory = "/Users/alx"; };
  preprod = import ../home/claude-code/preprod-curl.nix { inherit pkgs; };

  source = builtins.readFile ../home/claude-code/scripts/preprod-curl.sh;

  host = "https://preliz-preprod.alxwrtl.workers.dev";
  # Fake values: the stub hands them out, the suite looks for them.
  cfAuth = "eyJhbGciOiJSUzI1NiJ9.cfAuthPayloadXyz.sigCfAuth123";
  session = "SessTok9x8y7z6.SignedPart42";

  # Occurrences of a literal needle: length delta, not a regex.
  count =
    needle: hay:
    (builtins.stringLength hay - builtins.stringLength (builtins.replaceStrings [ needle ] [ "" ] hay))
    / builtins.stringLength needle;

  # --- canaries -----------------------------------------------------------
  # Each anchor must occur exactly once in scripts/preprod-curl.sh (G1).
  canaries = [
    {
      id = "C1";
      # secret moved into argv
      subs = [
        {
          from = "curl -q -K -";
          to = "curl -q -H \"CF-Access-Client-Secret: $CF_SECRET\" -K -";
        }
      ];
      kill = "FAIL p06: secret in argv";
    }
    {
      id = "C2";
      # PATH validation disabled: regex accepts anything, `..` check inert
      subs = [
        {
          from = "readonly PATH_RE='^/[A-Za-z0-9/._~%?&=+,:-]*$'";
          to = "readonly PATH_RE='.*'";
        }
        {
          from = "*..*";
          to = "*..NEVER..*";
        }
      ];
      kill = "FAIL p03: curl called";
    }
    {
      id = "C3";
      # inherited SHELLOPTS=xtrace traces the secrets
      subs = [
        {
          from = "\nset +o xtrace\n";
          to = "\n";
        }
      ];
      kill = "FAIL p09: secret in stdout/stderr";
    }
    {
      id = "C4";
      # secret shape check disabled
      subs = [
        {
          from = "readonly SECRET_RE='^(cfast_[A-Za-z0-9_-]{48}|[0-9a-fA-F]{64})$'";
          to = "readonly SECRET_RE='.*'";
        }
      ];
      kill = "FAIL p05: curl called";
    }
    {
      id = "C5";
      # host dropped from the URL
      subs = [
        {
          from = "\"$HOST$path\"";
          to = "\"$path\"";
        }
      ];
      kill = "FAIL p06: wrong URL";
    }
    {
      id = "C6";
      # scrub turned into a pass-through; the real body becomes dead code
      subs = [
        {
          from = "\nscrub() {\n";
          to = "\nscrub() {\n  cat\n}\n# shellcheck disable=SC2317,SC2329\nscrub_disabled() {\n";
        }
      ];
      kill = "FAIL p08: secret in stdout/stderr";
    }
    {
      id = "C7";
      # redirects followed
      subs = [
        {
          from = "--max-redirs 0";
          to = "-L";
        }
      ];
      kill = "FAIL p06: redirect following";
    }
    {
      id = "C8";
      # sign-in body (password) moved into argv
      subs = [
        {
          from = "--data-binary @<(signin_json)";
          to = "--data \"$(signin_json)\"";
        }
      ];
      kill = "FAIL p10: password in argv";
    }
    {
      id = "C9";
      # account slug check off: `--as` reaches the secret dir unvalidated
      subs = [
        {
          from = "readonly ACCOUNT_RE='^[abcdefghijklmnopqrstuvwxyz0123456789][abcdefghijklmnopqrstuvwxyz0123456789_-]{0,31}$'";
          to = "readonly ACCOUNT_RE='.*'";
        }
      ];
      kill = "FAIL p12: curl called";
    }
    {
      id = "C10";
      # email convention broken: the `agent-` prefix dropped
      subs = [
        {
          from = "email=\"agent-$as@$EMAIL_DOMAIN\"";
          to = "email=\"$as@$EMAIL_DOMAIN\"";
        }
      ];
      kill = "FAIL p10: sign-in email is not agent-<account>@preliz.com";
    }
    {
      id = "C11";
      # multi-line password file accepted: only its first line is sent
      subs = [
        {
          from = "  [[ $password != *[$'\\n\\r']* ]] || die 1 \"$SECRETS/preliz-preprod-$as-password holds more than one line — keep the password only\"\n";
          to = "";
        }
      ];
      kill = "FAIL p12: multi-line password file not refused";
    }
  ];
  mutate = c: builtins.replaceStrings (map (s: s.from) c.subs) (map (s: s.to) c.subs) source;
  badAnchors = builtins.concatMap (
    c:
    map (s: "${c.id} `${s.from}` x${toString (count s.from source)}") (
      builtins.filter (s: count s.from source != 1) c.subs
    )
  ) canaries;
  sameMutants = map (c: c.id) (builtins.filter (c: mutate c == source) canaries);

  # --- B. settings ------------------------------------------------------------
  parsed = builtins.tryEval (builtins.fromJSON settings.settingsJson);
  s = if parsed.success && builtins.isAttrs parsed.value then parsed.value else { };
  allow = attrByPath [ "permissions" "allow" ] [ ] s;
  ask = attrByPath [ "permissions" "ask" ] [ ] s;
  excluded = attrByPath [ "sandbox" "excludedCommands" ] [ ] s;
  allowRead = attrByPath [ "sandbox" "filesystem" "allowRead" ] [ ] s;
  environment = attrByPath [ "autoMode" "environment" ] [ ] s;
  autoAllow = attrByPath [ "autoMode" "allow" ] [ ] s;

  secretDir = "/Users/alx/.config/secrets/";
  # The account passwords: one glob, `*` within one path component.
  passwordGlob = secretDir + "preliz-preprod-*-password";
  preprodSecrets = [
    (secretDir + "cf-access-client-id")
    (secretDir + "cf-access-client-secret")
    passwordGlob
  ];
  allowedSecretReads = preprodSecrets ++ [
    (secretDir + "trello-api-key")
    (secretDir + "trello-token")
    (secretDir + "scaleway-tem-access-key")
    (secretDir + "scaleway-tem-secret-key")
  ];
  secretReads = builtins.filter (e: builtins.isString e && hasInfix ".config/secrets" e) allowRead;
  strayReads = builtins.filter (e: !(builtins.elem e allowedSecretReads)) secretReads;
  missingReads = builtins.filter (f: !(builtins.elem f allowRead)) preprodSecrets;
  secretGlobs = builtins.filter (
    e: hasInfix "*" e || hasInfix "?" e || hasInfix "[" e || hasInfix "{" e
  ) secretReads;
  # A glob may not leave its path component: no `**`, nothing after secrets/
  # holding a `/`, and nothing above secrets/ but the literal prefix.
  wideGlobs = builtins.filter (
    e: !(hasPrefix secretDir e) || hasInfix "**" e || hasInfix "/" (pkgs.lib.removePrefix secretDir e)
  ) secretGlobs;
  preprodAsk = builtins.filter (e: builtins.isString e && hasInfix "preprod" e) ask;
  expectedPreprodAsk = [
    "Bash(preprod-curl patch *)"
    "Bash(preprod-curl post *)"
    "Bash(preprod-curl put *)"
  ];

  assertions = [
    {
      name = "B1 settings.json parses";
      ok = parsed.success && s != { };
      msg = "settingsJson did not parse — every B assert below would be vacuous";
    }
    {
      name = "B2 allow has Bash(preprod-curl *) and no Bash(curl …)";
      ok =
        builtins.elem "Bash(preprod-curl *)" allow
        && builtins.filter (r: builtins.isString r && hasPrefix "Bash(curl" r) allow == [ ];
      msg = "permissions.allow must hold `Bash(preprod-curl *)` and no `Bash(curl…)` rule — the wrapper exists so that curl is not granted";
    }
    {
      name = "B3 preprod-curl never excluded from the sandbox";
      ok = excluded != [ ] && builtins.filter (c: hasInfix "preprod-curl" c) excluded == [ ];
      msg = "sandbox.excludedCommands is empty (vacuous) or names preprod-curl — the wrapper must run sandboxed";
    }
    {
      name = "B4 allowRead opens the Access token files and the preliz-preprod-*-password glob, nothing else under .config/secrets";
      ok = missingReads == [ ] && strayReads == [ ];
      msg =
        "missing "
        + builtins.toJSON missingReads
        + ", not allowed "
        + builtins.toJSON strayReads
        + " — exactly: trello-api-key, trello-token, cf-access-client-id/secret, scaleway-tem-access/secret-key (exact files) and ONE glob preliz-preprod-*-password; no directory, no other glob";
    }
    {
      name = "B8 the only glob under .config/secrets is preliz-preprod-*-password, inside one path component";
      ok = secretGlobs == [ passwordGlob ] && wideGlobs == [ ];
      msg =
        "globs under .config/secrets are "
        + builtins.toJSON secretGlobs
        + ", expected exactly "
        + builtins.toJSON [ passwordGlob ]
        + "; crossing a path component: "
        + builtins.toJSON wideGlobs;
    }
    {
      name = "B5 autoMode.environment: $defaults first + preprod host via `preprod-curl`";
      ok =
        environment != [ ]
        && builtins.head environment == "$defaults"
        && builtins.any (
          e: hasInfix "preliz-preprod.alxwrtl.workers.dev" e && hasInfix "`preprod-curl`" e
        ) environment;
      msg = "autoMode.environment must start with \"$defaults\" and name preliz-preprod.alxwrtl.workers.dev reached through the `preprod-curl` wrapper";
    }
    {
      # Not bare "preprod": the Preliz deploy line (`pnpm run deploy`,
      # preprod) is a separate, pre-existing grant.
      name = "B6 no autoMode.allow line for preprod-curl or the preprod host";
      ok =
        builtins.filter (
          e: hasInfix "preprod-curl" e || hasInfix "preliz-preprod.alxwrtl.workers.dev" e
        ) autoAllow == [ ];
      msg = "autoMode.allow names preprod-curl or preliz-preprod.alxwrtl.workers.dev — the plan grants it through `Bash(preprod-curl *)` only";
    }
    {
      name = "B7 ask boxes the preprod writes (user decision 2026-10-23)";
      ok = builtins.sort builtins.lessThan preprodAsk == expectedPreprodAsk;
      msg =
        "permissions.ask preprod entries are "
        + builtins.toJSON preprodAsk
        + ", expected exactly "
        + builtins.toJSON expectedPreprodAsk;
    }
    {
      name = "G1 canary anchors occur exactly once";
      ok = badAnchors == [ ];
      msg =
        builtins.concatStringsSep ", " badAnchors
        + " in scripts/preprod-curl.sh — update the anchors with the script";
    }
    {
      name = "G2 canary mutants differ from the source";
      ok = sameMutants == [ ];
      msg = "mutant(s) " + builtins.toJSON sameMutants + " equal the source — they would test nothing";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;

  # --- C. runtime suite ---------------------------------------------------------
  # Stub curl. Records per call: argv (NUL-separated), stdin (the -K - config),
  # the content of every `@/dev/fd/N` argument (concatenated in callN.data).
  # Honours -o/--output, -D/--dump-header (file or -), -w/--write-out
  # (%{http_code} %{response_code} %{redirect_url} %{url_effective}
  # %{content_type}, backslash escapes), -c/--cookie-jar (Netscape jar, keeps
  # the -c or -b file's other cookies, adds CF_Authorization, plus the session
  # cookie on a successful sign-in). Response headers carry
  # `set-cookie: CF_Authorization=…` on every non-302 answer.
  # STUB_MODE: net -> exit 6; access302 -> 302 to *.cloudflareaccess.com;
  # signin401 -> sign-in answers 401 INVALID_EMAIL_OR_PASSWORD;
  # body -> non-sign-in calls answer STUB_CODE (200) with STUB_BODY.
  stubCurl = pkgs.writeShellScriptBin "curl" ''
    set +o xtrace
    dir="''${STUB_DIR:?STUB_DIR unset}"
    n=0
    while [ -e "$dir/call$n.argv" ]; do n=$((n + 1)); done
    printf '%s\0' "$@" >"$dir/call$n.argv"
    input=""
    IFS= read -r -d "" input || true
    printf '%s' "$input" >"$dir/call$n.stdin"
    url="''${!#}"
    args=("$@")
    out="" hdr="" wfmt="" cjar="" bjar=""
    for ((i = 0; i < ''${#args[@]}; i++)); do
      a="''${args[i]}"
      nxt="''${args[i + 1]:-}"
      case "$a" in
      -o | --output) out="$nxt" ;;
      -D | --dump-header) hdr="$nxt" ;;
      -w | --write-out) wfmt="$nxt" ;;
      -c | --cookie-jar) cjar="$nxt" ;;
      -b | --cookie) bjar="$nxt" ;;
      esac
      case "$a" in
      *@/dev/fd/*)
        p="''${a#*@}"
        p="''${p%%;*}"
        payload=""
        IFS= read -r -d "" payload <"$p" || true
        printf '%s' "$payload" >>"$dir/call$n.data"
        ;;
      esac
    done
    CR=$'\r'
    TAB=$'\t'
    signin=0
    case "$url" in */api/auth/sign-in/email) signin=1 ;; esac
    code=200
    body='{"ok":true}'
    loc=""
    ctype="application/json"
    case "''${STUB_MODE:-}" in
    net)
      echo "curl: (6) Could not resolve host: preliz-preprod.alxwrtl.workers.dev" >&2
      [ -z "$wfmt" ] || printf '%b' "''${wfmt//%\{http_code\}/000}"
      exit 6
      ;;
    access302)
      code=302
      body=""
      loc="https://alxwrtl.cloudflareaccess.com/cdn-cgi/access/login/preliz-preprod.alxwrtl.workers.dev?kid=abc"
      ;;
    signin401)
      if [ "$signin" = 1 ]; then
        code=401
        body='{"code":"INVALID_EMAIL_OR_PASSWORD","message":"Invalid email or password"}'
      fi
      ;;
    body)
      if [ "$signin" = 0 ]; then
        code="''${STUB_CODE:-200}"
        body="''${STUB_BODY?STUB_BODY unset}"
      fi
      ;;
    esac
    signok=0
    if [ "$signin" = 1 ] && [ "$code" = 200 ]; then
      signok=1
      body='{"redirect":false,"token":"${session}","user":{"email":"agent-agent@preliz.com"}}'
    fi
    status="HTTP/2 $code$CR"$'\n'
    if [ -n "$loc" ]; then
      status+="location: $loc$CR"$'\n'
    else
      status+="content-type: $ctype$CR"$'\n'
      status+="set-cookie: CF_Authorization=${cfAuth}; Domain=preliz-preprod.alxwrtl.workers.dev; Path=/; Expires=Fri, 01 Jan 2100 00:00:00 GMT; Secure; HttpOnly; SameSite=None$CR"$'\n'
      if [ "$signok" = 1 ]; then
        status+="set-cookie: __Secure-better-auth.session_token=${session}; Max-Age=604800; Path=/; HttpOnly; Secure; SameSite=Lax$CR"$'\n'
      fi
    fi
    status+="$CR"$'\n'
    if [ -n "$cjar" ]; then
      src=""
      if [ -f "$cjar" ]; then
        src="$cjar"
      elif [ -n "$bjar" ] && [ -f "$bjar" ]; then
        src="$bjar"
      fi
      keep=""
      if [ -n "$src" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in
          "" | "# "*) continue ;;
          *"''${TAB}CF_Authorization''${TAB}"*) continue ;;
          esac
          if [ "$signok" = 1 ]; then
            case "$line" in *"session_token''${TAB}"*) continue ;; esac
          fi
          keep+="$line"$'\n'
        done <"$src"
      fi
      if [ -z "$loc" ]; then
        keep+="#HttpOnly_preliz-preprod.alxwrtl.workers.dev''${TAB}FALSE''${TAB}/''${TAB}TRUE''${TAB}4102444800''${TAB}CF_Authorization''${TAB}${cfAuth}"$'\n'
      fi
      if [ "$signok" = 1 ]; then
        keep+="#HttpOnly_preliz-preprod.alxwrtl.workers.dev''${TAB}FALSE''${TAB}/''${TAB}TRUE''${TAB}4102444800''${TAB}__Secure-better-auth.session_token''${TAB}${session}"$'\n'
      fi
      printf '# Netscape HTTP Cookie File\n\n%s' "$keep" >"$cjar"
    fi
    if [ "$hdr" = - ]; then
      printf '%s' "$status"
    elif [ -n "$hdr" ]; then
      printf '%s' "$status" >"$hdr"
    fi
    if [ -n "$out" ] && [ "$out" != - ]; then
      printf '%s' "$body" >"$out"
    else
      printf '%s' "$body"
    fi
    if [ -n "$wfmt" ]; then
      w="''${wfmt//%\{http_code\}/$code}"
      w="''${w//%\{response_code\}/$code}"
      w="''${w//%\{redirect_url\}/$loc}"
      w="''${w//%\{url_effective\}/$url}"
      w="''${w//%\{content_type\}/$ctype}"
      printf '%b' "$w"
    fi
    exit 0
  '';

  real = preprod.mkPreprodCurl { curl = stubCurl; };
  mutants = map (
    c:
    c
    // {
      bin = preprod.mkPreprodCurl {
        curl = stubCurl;
        text = mutate c;
      };
    }
  ) canaries;

  # suite <preprod-curl binary> <work dir> — prints PASS pNN per case; first
  # failure prints `FAIL pNN: <reason>` (exact line, matched by the canary
  # gate) and exits 1.
  suite = pkgs.writeShellScript "preprod-curl-suite" ''
    set -u
    bin="$1"
    work="$2"
    HOST="${host}"
    ID=Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4z.access
    ID37=Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy.access
    SECRET=cfast_Zq9_xW-8vU7tS6rR5qP4oN3mM2lL1kK0jJ9iI8hH7gG6fF5e
    HEX=0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0
    # `"` and `\` so the raw and JSON-escaped forms differ (both scrubbed).
    AGENT_PW='Ag-Pa55"w\o/rd!s3cret'
    AGENT_PW_JSON='Ag-Pa55\"w\\o/rd!s3cret'
    CFAUTH='${cfAuth}'
    SESSION='${session}'
    # home <name> <id> <secret> — fixture HOME with the Access token files,
    # the `agent` password file (padded, CRLF, trailing blank line) and a
    # decoy `agent.bad` password file only an unvalidated slug can reach.
    home() {
      local d="$work/$1/.config/secrets"
      mkdir -p "$d" "$work/$1/projects/Preliz/.playwright-mcp"
      printf '%s\n' "$2" >"$d/cf-access-client-id"
      printf '%s\n' "$3" >"$d/cf-access-client-secret"
      printf ' \t%s \r\n\n' "$AGENT_PW" >"$d/preliz-preprod-agent-password"
      printf ' \t%s \r\n\n' "$AGENT_PW" >"$d/preliz-preprod-agent.bad-password"
    }
    home ok "$ID" "$SECRET"
    home badid "$ID37" "$SECRET"
    home shortsec "$ID" cfast_short
    home label "$ID" "CF-Access-Client-Secret:$SECRET"
    home hex "$ID" "$HEX"
    home pw0 "$ID" "$SECRET"
    : >"$work/pw0/.config/secrets/preliz-preprod-agent-password"
    home pwblank "$ID" "$SECRET"
    printf ' \r\n\n' >"$work/pwblank/.config/secrets/preliz-preprod-agent-password"
    home pwmulti "$ID" "$SECRET"
    printf 'pw-a1\nsecond-b2\n' >"$work/pwmulti/.config/secrets/preliz-preprod-agent-password"
    home pwdir "$ID" "$SECRET"
    rm "$work/pwdir/.config/secrets/preliz-preprod-agent-password"
    mkdir "$work/pwdir/.config/secrets/preliz-preprod-agent-password"
    mkdir -p "$work/none" "$work/tmp"
    printf ' \t%s \r\n\n' "$ID" >"$work/hex/.config/secrets/cf-access-client-id"
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
    # t <home> <args...> — stdin from $IN, stub mode from $MODE, body/code
    # from $BODY/$CODE, TMPDIR from $TMPD; XTRACE=1 runs the binary with
    # SHELLOPTS=xtrace (readonly in bash, hence `env`).
    t() {
      local home="$1"
      local -a pre=()
      shift
      seq=$((seq + 1))
      last="$work/run$seq"
      mkdir -p "$last"
      [ -z "''${XTRACE:-}" ] || pre=(env SHELLOPTS=xtrace)
      HOME="$work/$home" TMPDIR="''${TMPD:-$work/tmp}" STUB_DIR="$last" STUB_MODE="''${MODE:-}" \
        STUB_BODY="''${BODY:-}" STUB_CODE="''${CODE:-200}" \
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
    # argv_lacks <reason> <needle...> — no needle in any argv of this run.
    argv_lacks() {
      local f reason="$1"
      shift
      for f in "$last"/call*.argv; do
        [ -e "$f" ] || continue
        local n
        for n in "$@"; do
          if grep -qaF -- "$n" "$f"; then fail "$reason"; fi
        done
      done
    }
    argv_clean() { argv_lacks "secret in argv" "$ID" "$SECRET" "$HEX"; }
    out_clean() {
      local n
      for n in "$ID" "$SECRET" "$HEX" "$AGENT_PW" "$AGENT_PW_JSON" "$CFAUTH" "$SESSION"; do
        if grep -qaF -- "$n" "$last/out" "$last/err"; then fail "secret in stdout/stderr"; fi
      done
    }
    # argv_has <call#> <exact element>
    argv_has() {
      local -a av
      local a
      mapfile -d "" -t av <"$last/call$1.argv"
      for a in "''${av[@]}"; do [ "$a" = "$2" ] && return 0; done
      return 1
    }
    # argv_pair <call#> <element> <next element>
    argv_pair() {
      local -a av
      local i
      mapfile -d "" -t av <"$last/call$1.argv"
      for i in "''${!av[@]}"; do
        if [ "''${av[$i]}" = "$2" ] && [ "''${av[$((i + 1))]:-}" = "$3" ]; then return 0; fi
      done
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
    # sent <call#> <text> — text in that call's argv or stdin config.
    sent() { grep -qaF -- "$2" "$last/call$1.argv" "$last/call$1.stdin"; }
    err_has() { grep -qF -- "$1" "$last/err" || fail "stderr lacks '$1'"; }
    out_has() { grep -qF -- "$1" "$last/out" || fail "stdout lacks '$1'"; }
    pass() { echo "PASS $case"; }

    case=p01
    t none
    expect_calls 0
    expect_rc 2
    grep -qF "Usage:" "$last/err" || fail "no usage on stderr"
    pass

    case=p02
    t none --help
    expect_calls 0
    expect_rc 0
    grep -qF "Usage:" "$last/out" || fail "no usage on stdout"
    pass

    case=p03
    printf -v long '%*s' 2048 ""
    long="/''${long// /a}"
    for p in "https://x" "//e.com" "/a/../b" "/x@e" "/x y" "/x#f" "/%2E%2e/" "rel" "/{a}" '/x\y' \
      "/a%2Fb" "/a%5c" "/a%2e" "/%zz" "/a%4" "$long" ""; do
      t ok get "$p"
      expect_calls 0
      expect_rc 2
    done
    # Validated before any secret read: no secret files, still exit 2.
    t none get "/a/../b"
    expect_calls 0
    expect_rc 2
    pass

    case=p04
    t none get /api/health
    expect_calls 0
    expect_rc 1
    err_has "missing or unreadable"
    err_has "cf-access-client-id"
    pass

    case=p05
    t badid get /api/health
    expect_calls 0
    expect_rc 1
    err_has "cf-access-client-id"
    out_clean
    t shortsec get /api/health
    expect_calls 0
    expect_rc 1
    err_has "cf-access-client-secret"
    if grep -qaF cfast_short "$last/out" "$last/err"; then fail "secret in stdout/stderr"; fi
    t label get /api/health
    expect_calls 0
    expect_rc 1
    err_has "cf-access-client-secret"
    grep -qi "label" "$last/err" || fail "no pasted-label hint"
    out_clean
    # 64-hex secret accepted; padded id trimmed.
    t hex get /api/health
    expect_rc 0
    expect_calls 1
    pass

    case=p06
    t ok get /api/health
    argv_clean
    expect_calls 1
    expect_rc 0
    [ "$(argv_get 0 0)" = "-q" ] || fail "argv[0] is '$(argv_get 0 0)', expected -q"
    argv_pair 0 -K - || fail "no '-K -' in argv"
    [ "$(argv_last 0)" = "$HOST/api/health" ] || fail "wrong URL"
    for a in -L --location --location-trusted; do
      if argv_has 0 "$a"; then fail "redirect following"; fi
    done
    argv_pair 0 --max-redirs 0 || fail "redirect following"
    argv_pair 0 --proto =https || fail "no '--proto =https'"
    argv_has 0 -g || fail "no -g"
    argv_has 0 -D || fail "no -D"
    argv_has 0 -w || fail "no -w"
    grep -qxF "header = \"CF-Access-Client-Id: $ID\"" "$last/call0.stdin" || fail "id header not on stdin"
    grep -qxF "header = \"CF-Access-Client-Secret: $SECRET\"" "$last/call0.stdin" || fail "secret header not on stdin"
    out_clean
    [ "$(cat "$last/out")" = '{"ok":true}' ] || fail "stdout is not the body"
    # Encoded query accepted, passed verbatim.
    t ok get '/api/x?q=a%20b&n=1,2:3'
    argv_clean
    expect_rc 0
    [ "$(argv_last 0)" = "$HOST/api/x?q=a%20b&n=1,2:3" ] || fail "wrong URL"
    pass

    case=p07
    MODE=access302 t ok get /api/health
    expect_calls 1
    expect_rc 1
    err_has "Access rejected"
    out_clean
    pass

    case=p08
    MODE=body BODY="id=$ID secret=$SECRET cf=$CFAUTH" t ok get -i /api/health
    expect_rc 0
    out_clean
    head -n 1 "$last/out" | grep -q '^HTTP/' || fail "headers not first"
    grep -qi '^set-cookie:.*\[redacted\]' "$last/out" || fail "Set-Cookie line not redacted"
    out_has "id=[redacted] secret=[redacted] cf=[redacted]"
    pass

    case=p09
    XTRACE=1 t ok get /api/health
    expect_rc 0
    expect_calls 1
    out_clean
    pass

    case=p10
    jar_dir="$work/tmp-p10/preprod-curl-$UID"
    mkdir -p "$work/tmp-p10"
    TMPD="$work/tmp-p10" t ok get --as agent /api/me
    argv_lacks "password in argv" "$AGENT_PW" "$AGENT_PW_JSON"
    expect_rc 0
    expect_calls 2
    argv_clean
    argv_lacks "session in argv" "$SESSION"
    [ "$(argv_last 0)" = "$HOST/api/auth/sign-in/email" ] || fail "call 0 is not the sign-in"
    argv_has 0 POST || fail "sign-in is not a POST"
    sent 0 "Origin: $HOST" || fail "no Origin on sign-in"
    [ -s "$last/call0.data" ] || fail "no sign-in body on a /dev/fd argument"
    jq -e --arg pw "$AGENT_PW" 'keys == ["email", "password"] and .password == $pw' "$last/call0.data" >/dev/null ||
      fail "sign-in body is not {email, password}"
    jq -e '.email == "agent-agent@preliz.com"' "$last/call0.data" >/dev/null ||
      fail "sign-in email is not agent-<account>@preliz.com"
    [ "$(argv_last 1)" = "$HOST/api/me" ] || fail "wrong URL"
    [ -f "$jar_dir/agent.jar" ] || fail "no jar at \$TMPDIR/preprod-curl-\$UID/agent.jar"
    if argv_has 1 -b || argv_has 1 --cookie || sent 1 "$SESSION"; then :; else fail "session not sent"; fi
    out_clean
    # Valid jar: no new sign-in; a body echoing the session is scrubbed.
    MODE=body BODY="tok=$SESSION" TMPD="$work/tmp-p10" t ok get --as agent /api/me
    expect_rc 0
    expect_calls 1
    argv_lacks "session in argv" "$SESSION"
    out_clean
    out_has "tok=[redacted]"
    # A body echoing the password JSON-escaped is scrubbed too.
    MODE=body BODY="{\"pw\":\"$AGENT_PW_JSON\"}" TMPD="$work/tmp-p10" t ok get --as agent /api/me
    expect_rc 0
    expect_calls 1
    out_clean
    out_has '{"pw":"[redacted]"}'
    TMPD="$work/tmp-p10" t ok get --as agent --fresh /api/me
    expect_rc 0
    expect_calls 2
    [ "$(argv_last 0)" = "$HOST/api/auth/sign-in/email" ] || fail "--fresh did not sign in"
    argv_lacks "password in argv" "$AGENT_PW" "$AGENT_PW_JSON"
    out_clean
    pass

    case=p11
    mkdir -p "$work/tmp-p11"
    MODE=signin401 TMPD="$work/tmp-p11" t ok get --as agent /api/me
    expect_rc 1
    expect_calls 1
    err_has "INVALID_EMAIL_OR_PASSWORD"
    out_clean
    pass

    case=p12
    # Unknown account = missing password file.
    t ok get --as ghost /api/me
    expect_calls 0
    expect_rc 1
    err_has "missing or unreadable"
    err_has "preliz-preprod-ghost-password"
    out_clean
    # Empty or whitespace-only password file: refused before any call.
    for h in pw0 pwblank; do
      t "$h" get --as agent /api/me
      expect_calls 0
      expect_rc 1
      err_has "is empty"
      err_has "preliz-preprod-agent-password"
      out_clean
    done
    # Multi-line password file: refused before any call, neither line shown
    # (the sign-in body would carry the first line only, unscrubbed: C11).
    mkdir -p "$work/tmp-p12m"
    TMPD="$work/tmp-p12m" t pwmulti get --as agent /api/me
    [ "$(calls)" = 0 ] || fail "multi-line password file not refused"
    expect_rc 1
    err_has "more than one line"
    err_has "preliz-preprod-agent-password"
    for n in pw-a1 second-b2; do
      if grep -qaF -- "$n" "$last/out" "$last/err"; then fail "password line in stdout/stderr"; fi
    done
    out_clean
    # A directory in place of the password file: refused as unreadable.
    t pwdir get --as agent /api/me
    expect_calls 0
    expect_rc 1
    err_has "missing or unreadable"
    err_has "preliz-preprod-agent-password"
    out_clean
    # A 32-char slug using every class member is accepted and signs in.
    a32=abcdefghijklmnopqrstuvwxyz0_-789
    [ "''${#a32}" = 32 ] || fail "a32 is ''${#a32} chars"
    printf ' \t%s \r\n\n' "$AGENT_PW" >"$work/ok/.config/secrets/preliz-preprod-$a32-password"
    mkdir -p "$work/tmp-p12"
    TMPD="$work/tmp-p12" t ok get --as "$a32" /api/me
    expect_rc 0
    expect_calls 2
    [ "$(argv_last 0)" = "$HOST/api/auth/sign-in/email" ] || fail "call 0 is not the sign-in"
    jq -e --arg pw "$AGENT_PW" --arg em "agent-$a32@preliz.com" '.email == $em and .password == $pw' "$last/call0.data" >/dev/null ||
      fail "sign-in body is not agent-<slug>@preliz.com + the file password"
    [ -f "$work/tmp-p12/preprod-curl-$UID/$a32.jar" ] || fail "no jar for the 32-char slug"
    argv_lacks "password in argv" "$AGENT_PW" "$AGENT_PW_JSON"
    out_clean
    # Bad slugs: usage error before any secret read. agent.bad first: its
    # decoy file exists, so a disabled slug check signs in (C9).
    printf -v a33 '%*s' 33 ""
    a33="''${a33// /a}"
    for a in agent.bad Agent ../agent "" -agent "$a33"; do
      t ok get --as "$a" /api/me
      expect_calls 0
      expect_rc 2
      if [ -n "$a" ] && grep -qaF -- "$a" "$last/err"; then fail "bad slug echoed on stderr"; fi
    done
    t none get --as ../agent /api/me
    expect_calls 0
    expect_rc 2
    pass

    case=p13
    printf '%s' '{"title":"marker-7f3a"}' >"$work/post.json"
    IN="$work/post.json" t ok post --json /api/items
    argv_clean
    expect_rc 0
    expect_calls 1
    argv_has 0 POST || fail "post is not a POST"
    [ "$(argv_last 0)" = "$HOST/api/items" ] || fail "wrong URL"
    sent 0 "Origin: $HOST" || fail "no Origin on a write"
    sent 0 "Content-Type: application/json" || argv_has 0 --json || fail "no JSON content type"
    argv_lacks "body in argv" "marker-7f3a"
    [ "$(cat "$last/call0.data" 2>/dev/null)" = '{"title":"marker-7f3a"}' ] || fail "body not sent on a /dev/fd argument"
    out_clean
    printf '{"leak":"%s"}' "$ID" >"$work/leak.json"
    IN="$work/leak.json" t ok post --json /api/items
    expect_calls 0
    expect_rc 2
    out_clean
    printf '{"leak":"%s"}' "$AGENT_PW" >"$work/leakpw.json"
    # A loaded password counts too; refused before the sign-in call.
    mkdir -p "$work/tmp-p13"
    IN="$work/leakpw.json" TMPD="$work/tmp-p13" t ok put --as agent --json /api/items/1
    expect_calls 0
    expect_rc 2
    out_clean
    # A loaded secret in PATH (argv/URL) is refused too, before any call.
    t ok get "/x?s=$SECRET"
    expect_calls 0
    expect_rc 2
    out_clean
    head -c 1048577 /dev/zero | tr '\0' a >"$work/big.json"
    IN="$work/big.json" t ok patch --json /api/items/1
    expect_calls 0
    expect_rc 2
    IN="$work/post.json" t ok get --json /api/items
    expect_calls 0
    expect_rc 2
    pass

    case=p14
    for args in "delete /api/items/1" "options /x" "get --bogus /x" "get --cookie-out ../x.json /" \
      "get --cookie-out /a.json /" "get --cookie-out x.txt /"; do
      # `ok` has ~/projects/Preliz/.playwright-mcp: the name rule, not the
      # missing-dir guard, must be what refuses the --cookie-out shapes.
      # shellcheck disable=SC2086
      t ok $args
      expect_calls 0
      expect_rc 2
    done
    mkdir -p "$work/ok/projects/Preliz/.playwright-mcp/dir.json"
    t ok get --cookie-out dir.json /
    expect_calls 0
    expect_rc 2
    [ -z "$(ls -A "$work/ok/projects/Preliz/.playwright-mcp/dir.json")" ] || fail "file written into the directory"
    printf 'orig' >"$work/elsewhere.json"
    ln -s "$work/elsewhere.json" "$work/ok/projects/Preliz/.playwright-mcp/link.json"
    t ok get --cookie-out link.json /
    expect_rc 2
    [ "$(cat "$work/elsewhere.json")" = orig ] || fail "symlink target written"
    pass

    case=p15
    t ok get --cookie-out pw.json /
    expect_rc 0
    f="$work/ok/projects/Preliz/.playwright-mcp/pw.json"
    [ -f "$f" ] && [ ! -L "$f" ] || fail "no cookie file"
    [ "$(stat -c %a "$f")" = 600 ] || fail "cookie file mode $(stat -c %a "$f"), expected 600"
    jq -e --arg v "$CFAUTH" 'type == "array" and any(.[]; .name == "CF_Authorization" and .value == $v and (.domain | ltrimstr(".")) == "preliz-preprod.alxwrtl.workers.dev")' "$f" >/dev/null ||
      fail "cookie JSON shape"
    out_clean
    pass

    case=p16
    MODE=net t ok get /api/health
    expect_rc 1
    out_clean
    MODE=body CODE=404 BODY='{"error":"nope-91"}' t ok get /api/missing
    expect_rc 1
    out_has "nope-91"
    out_clean
    pass

    echo "suite: 16 runtime cases"
  '';

  fail = msg: throw "preprod-curl: ${msg}";
in
pkgs.runCommand "preprod-curl-check" { nativeBuildInputs = [ pkgs.jq ]; } (
  if failures != [ ] then
    fail (
      "${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    ''
      # p17 — inheritPath = false: the wrapper's PATH must not end with the caller's.
      grep -q '^export PATH=' ${real}/bin/preprod-curl || { echo "FAIL p17: no PATH line in the wrapper"; exit 1; }
      if grep '^export PATH=' ${real}/bin/preprod-curl | grep -qF '$PATH'; then
        echo "FAIL p17: the wrapper inherits the caller's PATH (inheritPath must be false)"
        exit 1
      fi
      echo "PASS p17"

      ${suite} ${real}/bin/preprod-curl "$TMPDIR/real" >real.log 2>&1 || {
        cat real.log
        echo "preprod-curl: suite FAILED on the real binary"
        exit 1
      }
      cat real.log
      for r in p01 p02 p03 p04 p05 p06 p07 p08 p09 p10 p11 p12 p13 p14 p15 p16; do
        grep -qx "PASS $r" real.log || { echo "preprod-curl: case $r did not run"; exit 1; }
      done

      canary() {
        if ${suite} "$2" "$TMPDIR/$1" >"$1.log" 2>&1; then
          cat "$1.log"
          echo "preprod-curl: canary $1 SURVIVED — the suite cannot see its fault"
          exit 1
        fi
        grep -qxF "$3" "$1.log" || {
          cat "$1.log"
          echo "preprod-curl: canary $1 killed for the wrong reason (expected: $3)"
          exit 1
        }
        echo "preprod-curl: canary $1 killed — $3"
      }
      ${builtins.concatStringsSep "\n" (
        map (c: "canary ${c.id} ${c.bin}/bin/preprod-curl ${pkgs.lib.escapeShellArg c.kill}") mutants
      )}

      echo "preprod-curl: ${toString (builtins.length assertions)} invariants, 17 cases, ${toString (builtins.length canaries)} canaries — OK"
      touch $out
    ''
)
