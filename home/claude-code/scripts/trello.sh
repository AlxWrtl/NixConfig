# trello — Trello REST API v1 from the shell. Replaces the former MCP server.
#
# Why a packaged CLI instead of curl in the skill: the skill and /card used to
# `cat ~/.config/secrets/trello-*` into shell variables, then curl
# api.trello.com with `?key=…&token=…`. The auto-mode classifier reads that as
# a secret read followed by egress — exfiltration-shaped — and its verdict
# drifted from one call to the next (writes passed, later ones were refused).
# This binary reads the key + token itself and never prints them. They travel
# only as an `Authorization: OAuth …` header inside a curl config fed on stdin
# (`curl -q -K -`), so they never reach argv (visible in `ps`), the URL,
# stdout or stderr. `printf` is a bash builtin: no process sees them in argv.
#
# Deliberately narrow — one subcommand per endpoint the skill and /card use:
#   - no generic `api METHOD path` passthrough: `Bash(trello *)` would then
#     cover DELETE and admin endpoints;
#   - no `--file` option: an auto-approved command could then post any
#     readable file, the secrets included.
#
# Only bash builtins + curl + jq: the package sets inheritPath = false.
#
# Exit codes: 0 ok | 1 runtime (secrets, network, HTTP >= 400, no match) |
# 2 usage (bad arguments, malformed id). Arguments and ids are validated
# BEFORE the secrets are read and before any network call.
#
# Inherited shell state: `SHELLOPTS=xtrace` is neutralised below. BASH_ENV is
# the same class — bash sources it before this script runs, so it can trace or
# read anything — and cannot be fixed from inside the script.

# An inherited SHELLOPTS=xtrace would trace the key + token to stderr.
set +o xtrace

readonly API="https://api.trello.com/1"
readonly SECRETS="$HOME/.config/secrets"
# Board and card: 24-hex id or 8-char shortLink. List: 24-hex id only.
readonly ID_RE='^([0-9a-fA-F]{24}|[A-Za-z0-9]{8})$'
readonly LIST_RE='^[0-9a-fA-F]{24}$'
readonly MAX_TEXT=16384
readonly REJECTED_RE='invalid key|invalid token|unauthorized permission requested'

key=""
token=""

usage() {
  local text
  IFS= read -r -d "" text <<'EOF' || true
trello — Trello REST API v1 from the shell (key + token never printed)

Usage:
  trello boards                       open boards: id<TAB>name
  trello lists <board>                lists of a board: id<TAB>name
  trello cards <list>                 cards of a list: id<TAB>name<TAB>shortUrl
  trello search <query...>            matching cards (max 10): id<TAB>name<TAB>shortUrl
  trello card <card>                  one JSON object: card, checklists, last 10 comments
  trello find-list <board> <name...>  id of the list named <name> (case-insensitive, exact)
  trello create <list> <name> [-]     new card: id<TAB>shortUrl; `-` = description on stdin
  trello move <card> <list>           move a card to another list
  trello comment <card> <text...|->   comment a card; `-` = text on stdin

Ids: <board> and <card> = 24-hex id or 8-char shortLink; <list> = 24-hex id.

Secrets, read by this binary and never printed:
  ~/.config/secrets/trello-api-key
  ~/.config/secrets/trello-token

Exit: 0 ok | 1 runtime error (secrets, network, HTTP, no match) | 2 usage
EOF
  printf '%s' "$text"
}

die() {
  echo "trello: $1" >&2
  exit "${2:-1}"
}

usage_error() {
  echo "trello: $1" >&2
  usage >&2
  exit 2
}

need_id() {
  [[ $2 =~ $ID_RE ]] || die "invalid $1 id '$2' — expected a 24-hex id or an 8-char shortLink" 2
}

need_list() {
  [[ $1 =~ $LIST_RE ]] || die "invalid list id '$1' — expected a 24-hex id" 2
}

need_text() {
  [ -n "$2" ] || die "$1 is empty" 2
  [ "${#2}" -le "$MAX_TEXT" ] || die "$1 is longer than $MAX_TEXT chars" 2
}

# read_secret <file> <other file> — prints the value, for a capture only.
read_secret() {
  local file="$SECRETS/$1" value
  [ -r "$file" ] || die "missing $file — populate it (and $2)"
  value=$(<"$file")
  # Trim leading/trailing whitespace only (CR of a CRLF file included);
  # embedded whitespace stays and the check below rejects it.
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [ -n "$value" ] || die "empty $file — populate it (and $2)"
  # Letters and digits only: the value is spliced into a curl config line,
  # where a quote or a backslash would rewrite the config.
  [[ $value =~ ^[A-Za-z0-9]+$ ]] || die "malformed $file — expected letters and digits only; repopulate it (and $2)"
  printf '%s' "$value"
}

load_secrets() {
  key=$(read_secret trello-api-key trello-token)
  token=$(read_secret trello-token trello-api-key)
}

# api METHOD PATH [curl args...] — prints the response body when HTTP < 400.
api() {
  local method="$1" path="$2" out code body
  shift 2
  # `\\"` in the format: bash printf turns `\"` into a bare quote, while curl's
  # config parser needs `\"` inside the quoted header value.
  if ! out=$(printf 'header = "Authorization: OAuth oauth_consumer_key=\\"%s\\", oauth_token=\\"%s\\""\n' "$key" "$token" |
    curl -q -sS --max-time 25 -K - -X "$method" -w '\n%{http_code}' "$@" "${API}/${path}"); then
    die "network error on $method /1/${path%%\?*}"
  fi
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  [[ $code =~ ^[0-9]{3}$ ]] || die "no HTTP status on $method /1/${path%%\?*}"
  # Every body, success included: a card or board name can echo a secret.
  body="${body//"$key"/[redacted]}"
  body="${body//"$token"/[redacted]}"
  if [ "$code" -ge 400 ]; then
    echo "trello: HTTP $code on $method /1/${path%%\?*}: ${body:0:300}" >&2
    if [ "$code" = 401 ] || [[ $body =~ $REJECTED_RE ]]; then
      echo "trello: credentials rejected — repopulate $SECRETS/trello-api-key and $SECRETS/trello-token with a freshly generated key + token" >&2
    elif [ "$code" = 404 ]; then
      echo "trello: not found — check the id" >&2
    elif [ "$code" = 429 ]; then
      echo "trello: rate limited (300 req/10s per key, 100 req/10s per token) — wait, then retry" >&2
    fi
    exit 1
  fi
  printf '%s\n' "$body"
}

main() {
  local cmd="${1:-}" json
  [ $# -eq 0 ] || shift
  case "$cmd" in
  -h | --help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
  boards)
    [ $# -eq 0 ] || usage_error "boards takes no argument"
    load_secrets
    json=$(api GET "members/me/boards?fields=id,name&filter=open")
    jq -r '.[] | [.id, .name] | @tsv' <<<"$json"
    ;;
  lists)
    [ $# -eq 1 ] || usage_error "lists needs exactly one <board>"
    need_id board "$1"
    load_secrets
    json=$(api GET "boards/$1/lists?fields=id,name")
    jq -r '.[] | [.id, .name] | @tsv' <<<"$json"
    ;;
  cards)
    [ $# -eq 1 ] || usage_error "cards needs exactly one <list>"
    need_list "$1"
    load_secrets
    json=$(api GET "lists/$1/cards?fields=id,name,shortUrl")
    jq -r '.[] | [.id, .name, .shortUrl] | @tsv' <<<"$json"
    ;;
  search)
    [ $# -gt 0 ] || usage_error "search needs a <query>"
    need_text query "$*"
    load_secrets
    json=$(api GET search --url-query modelTypes=cards --url-query cards_limit=10 --url-query "query=$*")
    # No hit -> empty stdout, exit 0.
    jq -r '.cards[]? | [.id, .name, .shortUrl] | @tsv' <<<"$json"
    ;;
  card)
    [ $# -eq 1 ] || usage_error "card needs exactly one <card>"
    need_id card "$1"
    load_secrets
    local fields checklists actions
    fields=$(api GET "cards/$1?fields=name,desc,idList,idBoard,shortUrl&labels=all")
    checklists=$(api GET "cards/$1/checklists")
    actions=$(api GET "cards/$1/actions?filter=commentCard&limit=10")
    jq -n --argjson card "$fields" --argjson checklists "$checklists" --argjson actions "$actions" \
      '{card: $card, checklists: $checklists, comments: [$actions[] | {date, author: .memberCreator.fullName, text: .data.text}]}'
    ;;
  find-list)
    [ $# -ge 2 ] || usage_error "find-list needs a <board> and a <name>"
    local board="$1" name ids
    shift
    name="$*"
    need_id board "$board"
    need_text "list name" "$name"
    load_secrets
    json=$(api GET "boards/$board/lists?fields=id,name")
    ids=$(jq -r --arg n "$name" '.[] | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .id' <<<"$json")
    local -a matches=()
    [ -z "$ids" ] || mapfile -t matches <<<"$ids"
    if [ "${#matches[@]}" -eq 1 ]; then
      printf '%s\n' "${matches[0]}"
    else
      echo "trello: ${#matches[@]} lists named '$name' on board $board (need exactly 1). Lists:" >&2
      jq -r '.[] | .name' <<<"$json" >&2
      exit 1
    fi
    ;;
  create)
    { [ $# -eq 2 ] || { [ $# -eq 3 ] && [ "$3" = "-" ]; }; } || usage_error "create needs <list> <name> [-]"
    need_list "$1"
    need_text "card name" "$2"
    local desc
    local -a extra=()
    if [ $# -eq 3 ]; then
      [ ! -t 0 ] || die "create - needs text on stdin (pipe or heredoc)" 2
      desc=$(</dev/stdin)
      need_text description "$desc"
      extra=(--data-urlencode "desc=$desc")
    fi
    load_secrets
    json=$(api POST cards --data-urlencode "idList=$1" --data-urlencode "name=$2" "${extra[@]}")
    jq -r '[.id, .shortUrl] | @tsv' <<<"$json"
    ;;
  move)
    [ $# -eq 2 ] || usage_error "move needs <card> <list>"
    need_id card "$1"
    need_list "$2"
    load_secrets
    json=$(api PUT "cards/$1" --data-urlencode "idList=$2")
    echo "moved $1 -> $2"
    ;;
  comment)
    [ $# -ge 2 ] || usage_error "comment needs <card> and a text (or - for stdin)"
    local card="$1" text action
    shift
    need_id card "$card"
    if [ $# -eq 1 ] && [ "$1" = "-" ]; then
      [ ! -t 0 ] || die "comment - needs text on stdin (pipe or heredoc)" 2
      text=$(</dev/stdin)
    else
      text="$*"
    fi
    need_text "comment text" "$text"
    load_secrets
    json=$(api POST "cards/$card/actions/comments" --data-urlencode "text=$text")
    action=$(jq -r '.id' <<<"$json")
    echo "commented $card ($action)"
    ;;
  *)
    usage_error "unknown subcommand '$cmd'"
    ;;
  esac
}

main "$@"
