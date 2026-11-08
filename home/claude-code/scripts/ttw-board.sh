# ttw-board — serve the TTW run board of one repo on 127.0.0.1, or draw it
# in the terminal with --tui.
#
# usage: ttw-board [--tui] [--port N] [--no-open] [--dry-run] [repo]
#
# repo defaults to the git toplevel of the cwd; exit 1 if it holds neither a
# `.claude/output/ttw` nor a `.claude/output/apex` directory (ttw wins when
# both exist). READ-ONLY: the served root is a temp dir of links and page copies, the page only issues GETs, and serve.py (next to the
# page in the store, never in the root) answers GET/HEAD only, to a Host of
# 127.0.0.1:<port> or localhost:<port> only, inside the root, runs/ or budget/.
#
# Served root (removed on exit, Ctrl-C included):
#   index.html, board.js  copies of the page in the nix store, made at launch
#   runs                  -> <repo>/.claude/output/ttw, else <repo>/.claude/output/apex
#   budget                -> ~/.claude/ttw-correction-budget, else the apex one, else an empty dir
#   meta.json             {"repo": "<basename of repo>"}
#
# --dry-run builds the root, prints it and stops, one entry per line:
#   root: <dir>
#   url: http://127.0.0.1:<port>/
#   <name>: copy of <store path> (index.html, board.js)
#   <name> -> <link target>      (runs, budget)
#   budget: empty dir            (when neither budget dir exists)
#   meta.json: <compact json>
# checks/ttw-board.nix asserts this format.
#
# --tui: no server, no temp root, no port: exec the Go board (ttw-board-tui,
# store path baked in by ttw-board.nix) with the runs dir, the budget dir (""
# when absent) and the repo name; it reads the disk itself, read-only, and
# never leaves the runs dir.
# --port and --no-open are ignored. With --dry-run it prints and stops:
#   tui: <tui_bin>
#   runs: <runs dir above>
#   budget: <dir> | none

board_dir="@boardDir@"
tui_bin="@tuiBin@"
port=8765
open_page=1
dry_run=0
tui=0
repo=""

usage() {
  echo "usage: ttw-board [--tui] [--port N] [--no-open] [--dry-run] [repo]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
  --port)
    [ $# -ge 2 ] || usage
    port="$2"
    shift 2
    ;;
  --no-open)
    open_page=0
    shift
    ;;
  --dry-run)
    dry_run=1
    shift
    ;;
  --tui)
    tui=1
    shift
    ;;
  -h | --help)
    usage
    ;;
  -*)
    echo "ttw-board: unknown option: $1" >&2
    usage
    ;;
  *)
    [ -z "$repo" ] || usage
    repo="$1"
    shift
    ;;
  esac
done

if [ "$tui" -eq 0 ]; then
  case "$port" in
  '' | *[!0-9]*)
    echo "ttw-board: --port needs an integer in 1-65535" >&2
    usage
    ;;
  esac
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "ttw-board: --port needs an integer in 1-65535" >&2
    usage
  fi
fi

if [ -z "$repo" ]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ttw-board: not inside a git repo; pass the repo path" >&2
    exit 1
  }
fi
repo="$(cd "$repo" 2>/dev/null && pwd -P)" || {
  echo "ttw-board: no such directory: $repo" >&2
  exit 1
}
# The ttw dir wins; the apex one is the pre-rename layout, read until phase 4.
runs="$repo/.claude/output/ttw"
if [ ! -d "$runs" ]; then
  runs="$repo/.claude/output/apex"
fi
if [ ! -d "$runs" ]; then
  echo "ttw-board: no runs here: neither $repo/.claude/output/ttw nor $runs, not a directory" >&2
  exit 1
fi

# Same order for the correction budget; "" when neither exists.
budget_src=""
if [ -n "${HOME:-}" ]; then
  for b in "$HOME/.claude/ttw-correction-budget" "$HOME/.claude/apex-correction-budget"; do
    if [ -d "$b" ]; then
      budget_src="$b"
      break
    fi
  done
fi

if [ "$tui" -eq 1 ]; then
  budget_dir="$budget_src"
  if [ "$dry_run" -eq 1 ]; then
    printf 'tui: %s\n' "$tui_bin"
    printf 'runs: %s\n' "$runs"
    printf 'budget: %s\n' "${budget_dir:-none}"
    exit 0
  fi
  exec "$tui_bin" "$runs" "$budget_dir" "$(basename "$repo")"
fi

root="$(mktemp -d "${TMPDIR:-/tmp}/ttw-board.XXXXXX")"
# rm -rf removes the links, never what they point to. INT/TERM exit through
# the EXIT trap, so Ctrl-C on the server cleans up too.
# The server runs in the background so the shell can kill it here: a TERM to the
# shell alone would otherwise leave it holding the port.
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$root"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Copies, not links: store files carry mtime 1970, so Last-Modified never moves
# and the browser keeps serving a stale page from cache after a rebuild.
cp "$board_dir/index.html" "$root/index.html"
cp "$board_dir/board.js" "$root/board.js"
ln -s "$runs" "$root/runs"
if [ -n "$budget_src" ]; then
  ln -s "$budget_src" "$root/budget"
else
  mkdir "$root/budget"
fi
jq -n --arg repo "$(basename "$repo")" '{repo: $repo}' >"$root/meta.json"

url="http://127.0.0.1:$port/"

if [ "$dry_run" -eq 1 ]; then
  printf 'root: %s\n' "$root"
  printf 'url: %s\n' "$url"
  for name in index.html board.js runs budget; do
    if [ -L "$root/$name" ]; then
      printf '%s -> %s\n' "$name" "$(readlink "$root/$name")"
    elif [ -f "$root/$name" ]; then
      printf '%s: copy of %s\n' "$name" "$board_dir/$name"
    else
      printf '%s: empty dir\n' "$name"
    fi
  done
  printf 'meta.json: %s\n' "$(jq -c . "$root/meta.json")"
  exit 0
fi

echo "ttw-board: $runs"
echo "ttw-board: $url (Ctrl-C to stop)"
if [ "$open_page" -eq 1 ] && command -v open >/dev/null 2>&1; then
  (
    sleep 1
    open "$url" >/dev/null 2>&1 || true
  ) &
fi

# Loopback only: serve.py binds 127.0.0.1, fixed in the file (checks/ttw-board.nix
# asserts it). Not exec: the shell must outlive the server so the EXIT trap
# kills it and removes $root; `wait` returns early on INT/TERM to run the trap.
python3 "$board_dir/serve.py" --directory "$root" "$port" &
server_pid=$!
wait "$server_pid"
