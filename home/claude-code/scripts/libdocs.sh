# libdocs — up-to-date library docs from the Context7 REST API. No MCP server.
#
# Why pinned ids instead of "best search hit": ranking by score or corpus size
# systematically serves the PREVIOUS major version. Measured 2026-08-16:
#   react-router  v5 corpus 27195 snippets vs v7 2407  -> v5 wins on size
#   tailwind      v3 corpus  3071 snippets vs v4 2725  -> v3 wins on size
#   zod           v3 corpus  3184 snippets vs v4  704  -> v3 wins 4.5x
#   vite          /vitejs/vite main already ships v8   -> AHEAD of the 7.3 in use
#
# Each pin was verified on 2026-08-16 by querying it and grepping the answer for
# version-distinctive tokens:
#   react     -> useActionState, Server Components; no useFormState
#   rr        -> routes.ts, from "react-router"; no react-router-dom
#   tailwind  -> @theme x7, @import "tailwindcss" x6; not tailwind.config.js
#   zod       -> z.email() x11 top-level; z.string().email() x1
#   date-fns  -> TZDate x26 (v4); no utcToZonedTime (v2/v3)
#
# Deliberately NOT pinned: `wrangler` — the search returns an OpenGL binding in
# second place and no usable Cloudflare result. The `cf` pin covers it.
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

Run `libdocs --list` for the pinned names.

Any other name falls through to --search: candidates are listed, nothing is
guessed. Pass a raw /org/project id to query it directly.

Examples:
  libdocs react "useEffect pitfalls, when not to use it"
  libdocs rr "loader vs clientLoader, route config in routes.ts"
  libdocs tw "container queries and @theme tokens"
  libdocs drizzle "pgPolicy RLS and migration workflow"
  libdocs --search zustand

Env:
  CONTEXT7_API_KEY   optional; anonymous tier used when unset
  LIBDOCS_MAX_BYTES  output cap, default 14000
EOF
}

pins() {
  cat <<'EOF'
NAME (aliases)          ID                                        PINNED TO
react                   /reactjs/react.dev                        React 19
rr, react-router        /remix-run/react-router                   RR 7, framework mode
ts, typescript          /microsoft/typescript-website             TS docs
tw, tailwind            /tailwindlabs/tailwindcss.com             Tailwind v4
zod                     /colinhacks/zod                           Zod 4
drizzle                 /drizzle-team/drizzle-orm-docs            Drizzle ORM + kit
auth, better-auth       /better-auth/better-auth                  Better Auth 1.6
cf, cloudflare, workers /websites/developers_cloudflare_workers   Workers, R2/KV/DO/AI
neon                    /websites/neon                            Neon serverless PG
dates, date-fns         /date-fns/date-fns                        date-fns 4 (TZDate)
vite                    /websites/v7_vite_dev                     Vite 7 (main is v8)
ui, shadcn              /shadcn-ui/ui                             shadcn + Radix
pw, playwright          /microsoft/playwright                     Playwright E2E
sentry                  /websites/sentry_io_platforms_javascript  Sentry JS
EOF
}

resolve() {
  case "$1" in
  react | reactjs | react19) echo "/reactjs/react.dev" ;;
  react-router | reactrouter | router | rr | rr7) echo "/remix-run/react-router" ;;
  typescript | ts) echo "/microsoft/typescript-website" ;;
  tailwind | tailwindcss | tw) echo "/tailwindlabs/tailwindcss.com" ;;
  zod) echo "/colinhacks/zod" ;;
  drizzle | drizzle-orm | drizzle-kit) echo "/drizzle-team/drizzle-orm-docs" ;;
  better-auth | betterauth | auth) echo "/better-auth/better-auth" ;;
  cloudflare | cf | workers | wrangler) echo "/websites/developers_cloudflare_workers" ;;
  neon | neondb) echo "/websites/neon" ;;
  date-fns | datefns | dates) echo "/date-fns/date-fns" ;;
  vite) echo "/websites/v7_vite_dev" ;;
  shadcn | shadcn-ui | radix | ui) echo "/shadcn-ui/ui" ;;
  playwright | pw) echo "/microsoft/playwright" ;;
  sentry) echo "/websites/sentry_io_platforms_javascript" ;;
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
