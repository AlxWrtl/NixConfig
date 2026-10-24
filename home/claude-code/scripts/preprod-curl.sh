# preprod-curl — HTTP to the Preliz preprod (Cloudflare Access) from the shell.
#
# Why a packaged CLI instead of curl: reaching the preprod needs the Access
# service token (~/.config/secrets/cf-access-client-*) and, to act as a preprod
# account, its password (~/.config/secrets/preliz-preprod-<account>-password).
# The auto-mode classifier refused
# `$(cat ~/.config/secrets/…)` followed by curl as Credential Exploration.
# This binary reads the secrets itself and never prints them:
#   - the Access id + secret travel only as headers inside a curl config fed
#     on stdin (curl -K, "-" = read the config from stdin; `-q` first so no
#     curlrc is read), never in argv (visible in `ps`), the URL or the output;
#   - the sign-in email + password reach curl only through a process-
#     substitution fd (`--data-binary @/dev/fd/N`); jq builds that body from a
#     builtin-printf pipe, so the password is never in argv or the environment;
#   - the host is fixed; PATH is validated BEFORE any secret is read;
#   - redirects are never followed and there is no -L: curl(1) -H warns that
#     custom headers "are set in all HTTP requests - even after redirects are
#     followed", so the Access secret would go to the redirect host.
#     --max-redirs set to zero caps it, `--proto =https` refuses any other
#     scheme;
#   - `-g` (--globoff): no curl URL globbing of {}[] in PATH;
#   - `-D FILE` (--dump-header) keeps the response headers out of stdout;
#     `-i` prints them, scrubbed;
#   - every byte printed (body, headers, curl's own stderr, server error text)
#     goes through scrub(): Set-Cookie values, the id, the secret, the
#     account passwords (raw and JSON-escaped) and every cookie value in the
#     jar become [redacted].
# No --noproxy: inside the Claude sandbox, egress goes through its proxy.
#
# Accounts (--as): better-auth sign-in (POST /api/auth/sign-in/email with an
# Origin header), session kept in a Netscape cookie jar (curl -c writes it,
# -b reads it) at $TMPDIR/preprod-curl-$UID/<account>.jar — dir 0700, file 0600,
# refused when a symlink or owned by someone else. The jar is reused until its
# session cookie expires, which also keeps clear of the sign-in rate limit;
# --fresh signs in again. `--as <account>` signs in as
# agent-<account>@preliz.com with the password from
# ~/.config/secrets/preliz-preprod-<account>-password: the whole file,
# surrounding whitespace (CR included) trimmed, so a password cannot start or
# end with whitespace.
#
# Exit codes: 0 ok | 1 runtime (secrets, network, Access, HTTP >= 400) |
# 2 usage (bad arguments, PATH, body). Only bash builtins + curl + jq +
# coreutils: the package sets inheritPath = false.
#
# Inherited shell state: an exported SHELLOPTS=xtrace is neutralised below.
# BASH_ENV is the same class — bash sources it before this script runs — and
# cannot be fixed from inside the script.

# An inherited SHELLOPTS=xtrace would trace the secrets to stderr.
set +o xtrace
umask 077

readonly HOST="https://preliz-preprod.alxwrtl.workers.dev"
readonly EMAIL_DOMAIN=preliz.com
readonly SECRETS="$HOME/.config/secrets"
readonly PW_DIR="$HOME/projects/Preliz"
readonly PATH_RE='^/[A-Za-z0-9/._~%?&=+,:-]*$'
readonly ID_RE='^[A-Za-z0-9]{32}\.access$'
readonly SECRET_RE='^(cfast_[A-Za-z0-9_-]{48}|[0-9a-fA-F]{64})$'
readonly NAME_RE='^[A-Za-z0-9._-]{1,64}\.json$'
# Classes spelled out: a range like a-z follows the locale's collation (under
# ISO8859-1 it admits A-Y and Latin-1 letters).
readonly ACCOUNT_RE='^[abcdefghijklmnopqrstuvwxyz0123456789][abcdefghijklmnopqrstuvwxyz0123456789_-]{0,31}$'
readonly MAX_BODY=1048576
readonly SIGNIN=/api/auth/sign-in/email

# Values scrub() replaces; filled as secrets and cookies become known.
SCRUB=()
CF_ID=""
CF_SECRET=""
email=""
password=""
work=""

usage() {
  local text
  IFS= read -r -d "" text <<'EOF' || true
preprod-curl — HTTP to https://preliz-preprod.alxwrtl.workers.dev through
Cloudflare Access (service token never printed)

Usage:
  preprod-curl <get|head|post|put|patch> [options] PATH

Options:
  --as ACCOUNT          sign in as agent-<ACCOUNT>@preliz.com with the password
                        from
                        ~/.config/secrets/preliz-preprod-<ACCOUNT>-password
                        (surrounding whitespace trimmed; ACCOUNT: a-z 0-9 _ -,
                        32 chars max; session cached in
                        $TMPDIR/preprod-curl-$UID/ACCOUNT.jar)
  --fresh               sign in again even if the cached session is valid
  --json | --form       request body on stdin (post, put, patch only; 1 MiB max)
  -i                    print the response headers (scrubbed) before the body
  --cookie-out NAME.json
                        write the cookies (Playwright addCookies format) to
                        ~/projects/Preliz/.playwright-mcp/NAME.json, mode 600
  -h, --help            this help

PATH: absolute, ASCII letters, digits and / . _ ~ % ? & = + , : - only,
no `..`, no encoded . / or \, at most 2048 chars.

Exit codes: 0 ok, 1 runtime (secrets, network, Access, HTTP >= 400),
2 usage.
EOF
  printf '%s' "$text"
}

die() {
  local code=$1
  shift
  printf 'preprod-curl: %s\n' "$*" >&2
  exit "$code"
}

# stdin -> stdout: every known secret or cookie value becomes [redacted], and
# so does the value of any Set-Cookie line.
scrub() {
  local s v line out=""
  s=$(
    cat
    printf x
  )
  s=${s%x}
  for v in "${SCRUB[@]}"; do
    [ -z "$v" ] || s=${s//"$v"/[redacted]}
  done
  if [[ ${s,,} == *set-cookie:* ]]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ ${line,,} == set-cookie:* ]]; then
        if [[ $line == *$'\r' ]]; then
          line="${line%%=*}=[redacted]"$'\r'
        else
          line="${line%%=*}=[redacted]"
        fi
      fi
      out+=$line$'\n'
    done <<<"$s"
    [[ $s == *$'\n' ]] || out=${out%$'\n'}
    s=$out
  fi
  printf '%s' "$s"
}

# Remember a value for scrub(); short cookie values would redact noise.
remember() {
  [ "${#1}" -ge "${2:-1}" ] || return 0
  SCRUB+=("$1")
}

# --- arguments: all validated before any secret is read ------------------------
[ $# -gt 0 ] || {
  usage >&2
  exit 2
}
case $1 in -h | --help)
  usage
  exit 0
  ;;
esac
method=$1
shift
case $method in get | head | post | put | patch) ;; *)
  usage >&2
  exit 2
  ;;
esac

as="" fresh=0 kind="" incl=0 cookie_out="" path="" have_path=0
while [ $# -gt 0 ]; do
  case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  --as)
    [ $# -ge 2 ] || die 2 "--as needs an account name"
    [[ $2 =~ $ACCOUNT_RE ]] || die 2 "--as takes an account name: a-z 0-9 _ -, first char a-z 0-9, 32 chars max"
    as=$2
    shift 2
    ;;
  --fresh)
    fresh=1
    shift
    ;;
  --json | --form)
    kind=${1#--}
    shift
    ;;
  -i)
    incl=1
    shift
    ;;
  --cookie-out)
    [ $# -ge 2 ] || die 2 "--cookie-out needs NAME.json"
    cookie_out=$2
    shift 2
    ;;
  -*) die 2 "unknown option '$1' (see --help)" ;;
  *)
    [ "$have_path" = 0 ] || die 2 "one PATH only"
    path=$1
    have_path=1
    shift
    ;;
  esac
done
[ "$have_path" = 1 ] || die 2 "PATH missing (see --help)"
[ "$fresh" = 0 ] || [ -n "$as" ] || die 2 "--fresh needs --as"
if [ -n "$kind" ]; then
  case $method in post | put | patch) ;; *) die 2 "--$kind needs post, put or patch" ;; esac
fi
[ "$method" != head ] || incl=1

((${#path} <= 2048)) || die 2 "PATH longer than 2048 chars"
[[ $path =~ $PATH_RE ]] || die 2 "invalid PATH — absolute, letters, digits and / . _ ~ % ? & = + , : - only"
case $path in //*) die 2 "PATH must not start with //" ;; esac
case $path in *..*) die 2 "PATH must not contain .." ;; esac
case ${path,,} in *%2e* | *%2f* | *%5c*) die 2 "PATH must not percent-encode . / or \\" ;; esac
rest=$path
while [[ $rest == *%* ]]; do
  rest=${rest#*%}
  [[ $rest =~ ^[0-9A-Fa-f]{2} ]] || die 2 "PATH has a bad percent-encoding"
done

cookie_file=""
if [ -n "$cookie_out" ]; then
  [[ $cookie_out =~ $NAME_RE ]] || die 2 "--cookie-out takes NAME.json (letters, digits, . _ -)"
  [ -d "$PW_DIR" ] || die 2 "--cookie-out: $PW_DIR is missing"
  [ ! -L "$PW_DIR/.playwright-mcp" ] || die 2 "--cookie-out: $PW_DIR/.playwright-mcp is a symlink"
  cookie_file="$PW_DIR/.playwright-mcp/$cookie_out"
  [ ! -L "$cookie_file" ] || die 2 "--cookie-out refuses a symlink: $cookie_file"
  [ ! -d "$cookie_file" ] || die 2 "--cookie-out refuses a directory: $cookie_file"
fi

if [ -n "$kind" ]; then
  [ ! -t 0 ] || die 2 "--$kind reads the body from stdin, not a terminal"
fi

# --- private state dir ----------------------------------------------------------
tmpd="${TMPDIR:-/tmp}"
tmpd="${tmpd%/}/preprod-curl-$UID"
[ ! -L "$tmpd" ] || die 1 "$tmpd is a symlink — refusing it"
if [ ! -d "$tmpd" ]; then
  mkdir -m 700 "$tmpd" || die 1 "cannot create $tmpd"
fi
[ -O "$tmpd" ] || die 1 "$tmpd is not owned by you — refusing it"
chmod 700 "$tmpd"
work=$(mktemp -d "$tmpd/run.XXXXXX")
trap 'rm -rf "$work"' EXIT

bodyf=/dev/null
if [ -n "$kind" ]; then
  bodyf="$work/body.in"
  head -c $((MAX_BODY + 1)) >"$bodyf"
  (($(wc -c <"$bodyf") <= MAX_BODY)) || die 2 "request body over 1 MiB"
fi

# --- secrets ----------------------------------------------------------------------
# trim <value> — value without surrounding whitespace (\r included), in REPLY.
trim() {
  local v=$1
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  REPLY=$v
}

# secret <file> <regex|""> — trimmed value in REPLY; never printed.
secret() {
  local f="$SECRETS/$1" v
  [[ -f $f && -r $f ]] || die 1 "missing or unreadable $f (in the Claude sandbox, ~/.config/secrets opens only its exact token files and preliz-preprod-*-password)"
  v=$(<"$f") || die 1 "cannot read $f"
  trim "$v"
  v=$REPLY
  [ -n "$v" ] || die 1 "$f is empty"
  if [ -n "$2" ] && ! [[ $v =~ $2 ]]; then
    if [[ $v == *:* ]]; then
      die 1 "$f is malformed: it holds a ':' — a header label was pasted with the value; keep the value only"
    fi
    die 1 "$f is malformed — expected ${3:-the value only}"
  fi
  REPLY=$v
}

secret cf-access-client-id "$ID_RE" "32 letters/digits + .access"
CF_ID=$REPLY
secret cf-access-client-secret "$SECRET_RE" "cfast_ + 48 chars, or 64 hex"
CF_SECRET=$REPLY
remember "$CF_ID"
remember "$CF_SECRET"

jar=""
if [ -n "$as" ]; then
  email="agent-$as@$EMAIL_DOMAIN"
  secret "preliz-preprod-$as-password" ""
  password=$REPLY
  [[ $password != *[$'\n\r']* ]] || die 1 "$SECRETS/preliz-preprod-$as-password holds more than one line — keep the password only"
  remember "$password"
  # The password as it reads inside a JSON string, should a body echo it.
  remember "$(printf '%s' "$password" | jq -Rsj 'tojson | .[1:-1]')"
  jar="$tmpd/$as.jar"
  [ ! -L "$jar" ] || die 1 "$jar is a symlink — refusing it"
  if [ -e "$jar" ]; then
    [ -O "$jar" ] || die 1 "$jar is not owned by you — refusing it"
    chmod 600 "$jar"
  fi
fi

# jar_scan <jar> — remember every cookie value; status 0 iff a session cookie
# is still valid.
jar_scan() {
  local dom exp name val now valid=1
  [ -f "$1" ] || return 1
  now=$(date +%s)
  while IFS=$'\t' read -r dom _ _ _ exp name val; do
    case $dom in '#HttpOnly_'*) ;; '#'* | '') continue ;; esac
    remember "${val%$'\r'}" 8
    if [[ $name == *session_token && $exp =~ ^[0-9]+$ ]] && ((exp > now)); then valid=0; fi
  done <"$1"
  return "$valid"
}
session_ok=0
if [ -n "$jar" ] && [ "$fresh" = 0 ] && jar_scan "$jar"; then session_ok=1; fi

# Refused before the sign-in: a PATH or body carrying a secret is a leak, not a
# request.
for v in "${SCRUB[@]}"; do
  [[ $path != *"$v"* ]] || die 2 "PATH contains a secret — refusing to send it"
done
if [ -n "$kind" ]; then
  body=$(<"$bodyf")
  for v in "${SCRUB[@]}"; do
    [[ $body != *"$v"* ]] || die 2 "the request body contains a secret — refusing to send it"
  done
  unset body
fi

# --- HTTP ---------------------------------------------------------------------------
# http <method> <path> [curl args…] — one request; prints the status code.
http() {
  local m=$1 path=$2
  shift 2
  local -a opts=(--proto "=https" --max-redirs 0 -g -sS -D "$work/headers" -o "$work/out" -w '%{http_code}')
  if [ "$m" = head ]; then
    opts+=(--head)
  else
    opts+=(-X "${m^^}")
  fi
  case $m in get | head) ;; *) opts+=(-H "Origin: $HOST") ;; esac
  printf 'header = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' "$CF_ID" "$CF_SECRET" |
    curl -q -K - "${opts[@]}" "$@" "$HOST$path" 2>"$work/curl.err"
}

signin_json() {
  printf '%s\n%s' "$email" "$password" | jq -Rsc 'split("\n") | {email: .[0], password: .[1]}'
}

# Remember the Set-Cookie values of the last response.
header_cookies() {
  local line v
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ ${line,,} == set-cookie:* ]] || continue
    v=${line#*=}
    remember "${v%%;*}" 8
  done <"$work/headers"
}

# request <method> <path> [curl args…] — sets CODE; dies on network error and
# on any redirect (Access login redirect named as such).
CODE=""
request() {
  local rc=0 loc="" line
  : >"$work/headers"
  CODE=$(http "$@") || rc=$?
  [ -f "$work/headers" ] && header_cookies
  [ ! -s "$work/curl.err" ] || scrub <"$work/curl.err" >&2
  ((rc == 0)) || die 1 "network error on $1 ${2%%\?*} (curl exit $rc)"
  [[ $CODE =~ ^[0-9]{3}$ ]] || die 1 "no HTTP status on $1 ${2%%\?*}"
  if [[ $CODE == 3* ]]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line%$'\r'}
      if [[ ${line,,} == location:* ]]; then loc=${line#*:}; fi
    done <"$work/headers"
    loc=${loc# }
    case $loc in
    https://*.cloudflareaccess.com/* | https://*.cloudflareaccess.com)
      die 1 "Access rejected the service token (HTTP $CODE to the Access login) — check cf-access-client-id/secret and the Access policy"
      ;;
    esac
    die 1 "HTTP $CODE redirect not followed: $(printf '%s' "$loc" | scrub)"
  fi
}

if [ -n "$as" ] && [ "$session_ok" = 0 ]; then
  rm -f "$jar"
  request post "$SIGNIN" -c "$jar" -H "Content-Type: application/json" --data-binary @<(signin_json)
  if [ "$CODE" != 200 ]; then
    reason=$(jq -r '.code // .message // empty' "$work/out" 2>/dev/null | scrub || true)
    rm -f "$jar"
    die 1 "sign-in as $as failed (HTTP $CODE): ${reason:-no reason given}"
  fi
  jar_scan "$jar" || die 1 "sign-in as $as returned no session cookie"
fi

extra=()
if [ -n "$jar" ]; then
  extra+=(-b "$jar" -c "$jar")
elif [ -n "$cookie_file" ]; then
  extra+=(-c "$work/cookies")
fi
case $kind in
json) extra+=(-H "Content-Type: application/json" --data-binary @/dev/fd/3) ;;
form) extra+=(-H "Content-Type: application/x-www-form-urlencoded" --data-binary @/dev/fd/3) ;;
esac
request "$method" "$path" "${extra[@]}" 3<"$bodyf"
[ -z "$jar" ] || jar_scan "$jar" || true

if [ "$incl" = 1 ]; then scrub <"$work/headers"; fi
scrub <"$work/out"

if [ -n "$cookie_file" ]; then
  src=${jar:-$work/cookies}
  [ -f "$src" ] || die 1 "no cookie jar to export"
  cookies=$(
    jq -R -n '[inputs | rtrimstr("\r") | select(test("^(#HttpOnly_)?[^#]"))
      | split("\t") | select(length == 7)
      | {name: .[5], value: .[6],
         domain: (.[0] | ltrimstr("#HttpOnly_")), path: .[2],
         expires: ((.[4] | tonumber) as $e | if $e == 0 then -1 else $e end),
         httpOnly: (.[0] | startswith("#HttpOnly_")), secure: (.[3] == "TRUE"),
         sameSite: "Lax"}]' <"$src"
  ) || die 1 "cannot read the cookie jar"
  jq -e 'any(.[]; .name == "CF_Authorization")' <<<"$cookies" >/dev/null ||
    die 1 "no CF_Authorization cookie in the response — nothing written"
  mkdir -p "$PW_DIR/.playwright-mcp"
  [ ! -L "$cookie_file" ] || die 2 "--cookie-out refuses a symlink: $cookie_file"
  [ ! -d "$cookie_file" ] || die 2 "--cookie-out refuses a directory: $cookie_file"
  tmpc=$(mktemp "$PW_DIR/.playwright-mcp/.$cookie_out.XXXXXX")
  printf '%s\n' "$cookies" >"$tmpc"
  chmod 600 "$tmpc"
  # rename(2) replaces a symlink planted meanwhile; it never follows it.
  mv -f "$tmpc" "$cookie_file"
  unset cookies
  echo "preprod-curl: cookies written to $cookie_file" >&2
fi

if ((CODE >= 400)); then
  if [ -n "$jar" ] && [ "$session_ok" = 1 ] && [ "$CODE" = 401 ]; then
    die 1 "HTTP 401 with the cached $as session — retry with --fresh"
  fi
  die 1 "HTTP $CODE"
fi
