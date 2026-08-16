# libdocs — up-to-date library docs from the Context7 REST API. No MCP server.
#
# Why pinned ids instead of "best search hit": a search for "react router"
# returns v5 (27195 snippets, trustScore 9.7) ABOVE v7. Ranking by score or
# corpus size serves React Router v5 docs to someone writing v7. The ids below
# were verified on 2026-08-16 to return v19 / v7 content:
#   /reactjs/react.dev        -> useActionState, Server Components, no useFormState
#   /remix-run/react-router   -> routes.ts, from "react-router", no react-router-dom
#
# The API key is optional: without CONTEXT7_API_KEY requests use the anonymous
# tier (rate-limited, no signup).

API="https://context7.com/api/v2"
MAX_BYTES="${LIBDOCS_MAX_BYTES:-14000}"

usage() {
  cat <<'EOF'
libdocs — up-to-date library docs (Context7 REST API, no MCP)

Usage:
  libdocs <lib> <question...>    docs for a library, scoped to the question
  libdocs --search <term>        list candidate library ids with scores
  libdocs --list                 show pinned ids

Pinned (stack: React 19 + React Router 7 + TypeScript):
  react, reactjs           -> /reactjs/react.dev
  react-router, rr, router -> /remix-run/react-router
  typescript, ts           -> /microsoft/typescript-website

Any other name falls through to --search: candidates are listed, nothing is
guessed. Pass a raw /org/project id to query it directly.

Examples:
  libdocs react "useEffect pitfalls, when not to use it"
  libdocs rr "loader vs clientLoader, route config in routes.ts"
  libdocs --search zustand

Env:
  CONTEXT7_API_KEY   optional; anonymous tier used when unset
  LIBDOCS_MAX_BYTES  output cap, default 14000
EOF
}

pins() {
  cat <<'EOF'
react          /reactjs/react.dev         React 19 (main branch)
react-router   /remix-run/react-router    React Router 7 (framework mode)
typescript     /microsoft/typescript-website
EOF
}

resolve() {
  case "$1" in
  react | reactjs | react19) echo "/reactjs/react.dev" ;;
  react-router | reactrouter | router | rr | rr7) echo "/remix-run/react-router" ;;
  typescript | ts) echo "/microsoft/typescript-website" ;;
  /*/*) echo "$1" ;;
  *) echo "" ;;
  esac
}

urlencode() { printf '%s' "$1" | jq -sRr @uri; }

# Header array stays empty when no key is set -> anonymous tier.
auth_args=()
if [ -n "${CONTEXT7_API_KEY:-}" ]; then
  auth_args=(-H "Authorization: Bearer ${CONTEXT7_API_KEY}")
fi

search() {
  local term="$1" body
  if ! body=$(curl -sS --max-time 25 "${auth_args[@]}" \
    "${API}/libs/search?query=$(urlencode "$term")"); then
    echo "libdocs: search request failed" >&2
    return 1
  fi
  local count
  count=$(printf '%s' "$body" | jq -r '.results | length // 0')
  if [ "$count" = "0" ]; then
    echo "libdocs: no library matches '${term}'" >&2
    return 1
  fi
  printf '%s' "$body" | jq -r '
    .results[:8][]
    | "\(.id)\n    trust \(.trustScore // "-") | bench \(.benchmarkScore // "-") | \(.totalSnippets // 0) snippets | updated \((.lastUpdateDate // "-")[0:10])\n    \(.description // "" | .[0:110])\n"
  '
  echo "Pick an id, then: libdocs <id> \"<question>\"" >&2
  echo "Check the VERSION before using an id — several versions share a name." >&2
}

main() {
  case "${1:-}" in
  "" | -h | --help)
    usage
    exit 0
    ;;
  --list)
    pins
    exit 0
    ;;
  --search)
    shift
    [ $# -gt 0 ] || {
      echo "libdocs: --search needs a term" >&2
      exit 2
    }
    search "$*"
    exit $?
    ;;
  esac

  local lib="$1"
  shift
  local id
  id=$(resolve "$lib")

  if [ -z "$id" ]; then
    echo "libdocs: '${lib}' is not pinned. Candidates:" >&2
    echo >&2
    search "$lib"
    exit 1
  fi

  if [ $# -eq 0 ]; then
    echo "libdocs: a question is required, e.g. libdocs ${lib} \"how do loaders work\"" >&2
    exit 2
  fi

  local question="$*" body
  if ! body=$(curl -sS --max-time 45 "${auth_args[@]}" \
    "${API}/context?libraryId=${id}&query=$(urlencode "$question")"); then
    echo "libdocs: docs request failed for ${id}" >&2
    exit 1
  fi

  if [ -z "$body" ]; then
    echo "libdocs: empty response for ${id} (rate limited? set CONTEXT7_API_KEY)" >&2
    exit 1
  fi

  echo "=== ${id} — ${question} ==="
  echo
  # Bash substring, not `head -c`: head closes the pipe and SIGPIPE would trip
  # the `set -o pipefail` that writeShellApplication enables.
  if [ "${#body}" -gt "$MAX_BYTES" ]; then
    printf '%s\n' "${body:0:$MAX_BYTES}"
    echo
    echo "[truncated at ${MAX_BYTES} bytes — narrow the question, or raise LIBDOCS_MAX_BYTES]"
  else
    printf '%s\n' "$body"
  fi
}

main "$@"
