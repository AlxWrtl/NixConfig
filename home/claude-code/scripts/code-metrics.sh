# code-metrics — Uncle Bob's dryer (duplication), crapper (CRAP) and mutator
# (mutation testing), limited to what the current branch changed.
#
# The three tools are pinned flake inputs (store paths below), installed once
# by `code-metrics setup` into one venv under $CACHE (it needs the network:
# PyPI and the tree-sitter grammars). The other subcommands only read $CACHE,
# so they run inside the agent sandbox.
#
# Exit codes: 0 clean, 1 findings, 2 not run (usage, setup missing, no base
# ref, a tool or the coverage command failed). 2 is never a green result.

CRAPPER_SRC="@CRAPPER@"
MUTATOR_SRC="@MUTATOR@"
DRYER_SRC="@DRYER@"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/code-metrics"
VENV="$CACHE/venv"
STAMP="$CACHE/.ready"
export PYTHONDONTWRITEBYTECODE=1
export TREE_SITTER_LANGUAGE_PACK_CACHE_DIR="$CACHE/tslp"

usage() {
  cat <<'EOF'
usage: code-metrics setup
       code-metrics dup [--base REF]
       code-metrics crap --coverage-command CMD [--threshold N] [--base REF]
       code-metrics mutate --test-command CMD [--coverage-command CMD] [--base REF]

setup   install dryer, crapper and mutator into ~/.cache/code-metrics
        (network: run it outside the sandbox, once per tool update)
dup     full dryer scan; keeps the pairs touching a changed file, minus
        components/ui/
crap    crapper on the changed source files (tests and components/ui/ left out)
mutate  mutator on the added lines of each changed source file (whole file
        when untracked)

The diff base is git merge-base HEAD REF, REF = --base, else origin/HEAD,
master, main. Changed = tracked changes since the base plus untracked files.
Exit: 0 clean, 1 findings, 2 not run.
EOF
}

die() {
  printf 'code-metrics: %s\n' "$*" >&2
  exit 2
}

bad_usage() {
  printf 'code-metrics: %s\n' "$*" >&2
  usage >&2
  exit 2
}

g() {
  git -c core.fsmonitor=false -c core.quotePath=false "$@"
}

expected_stamp() {
  printf '%s\n' "$CRAPPER_SRC" "$MUTATOR_SRC" "$DRYER_SRC"
}

require_ready() {
  if [ -f "$STAMP" ] && [ -x "$VENV/bin/python" ] && [ "$(cat "$STAMP")" = "$(expected_stamp)" ]; then
    return 0
  fi
  die "tools not installed for this build: run \`code-metrics setup\` outside the sandbox"
}

tool() {
  "$VENV/bin/python" -m "$@"
}

copy_src() {
  local dest="$CACHE/src/$1"
  if [ -e "$dest" ]; then
    chmod -R u+w "$dest"
    rm -r "$dest"
  fi
  cp -R "$2" "$dest"
  chmod -R u+w "$dest"
}

warm_grammars() {
  local warm
  warm=$(mktemp -d)
  printf 'export function add(a: number, b: number): number {\n  return a + b;\n}\n' > "$warm/a.ts"
  printf 'export function View(): JSX.Element {\n  return <div />;\n}\n' > "$warm/b.tsx"
  printf 'def add(a, b):\n    return a + b\n' > "$warm/c.py"
  printf 'package main\n\nfunc add(a int, b int) int {\n\treturn a + b\n}\n' > "$warm/d.go"
  printf 'fn add(a: i32, b: i32) -> i32 {\n    a + b\n}\n' > "$warm/e.rs"
  printf 'class F {\n  int add(int a, int b) {\n    return a + b;\n  }\n}\n' > "$warm/F.java"
  printf '(ns g)\n\n(defn add [a b]\n  (+ a b))\n' > "$warm/g.clj"
  (cd "$warm" && tool dryer > /dev/null && tool crapper --no-coverage > /dev/null)
  rm -r "$warm"
}

run_setup() {
  [ $# -eq 0 ] || bad_usage "setup takes no option"
  mkdir -p "$CACHE/src"
  rm -f "$STAMP"
  copy_src crapper "$CRAPPER_SRC"
  copy_src mutator "$MUTATOR_SRC"
  copy_src dryer "$DRYER_SRC"
  python3 -m venv --clear "$VENV"
  "$VENV/bin/pip" install --disable-pip-version-check \
    "$CACHE/src/crapper" "$CACHE/src/mutator" "$CACHE/src/dryer"
  "$VENV/bin/pip" freeze --disable-pip-version-check > "$CACHE/freeze.txt"
  warm_grammars
  expected_stamp > "$STAMP"
  echo "code-metrics: setup done ($CACHE)"
}

# Sets $mb to the merge base of HEAD and the first ref that resolves.
resolve_base() {
  local ref
  local -a refs=(origin/HEAD master main)
  if [ -n "$base" ]; then
    refs=("$base")
  fi
  for ref in "${refs[@]}"; do
    if g rev-parse --verify --quiet "$ref^{commit}" > /dev/null; then
      mb=$(g merge-base HEAD "$ref") || die "no merge base between HEAD and $ref"
      return 0
    fi
  done
  die "no base ref resolves (tried: ${refs[*]}); pass --base REF"
}

# Writes $work/changed (tracked changes since $mb + untracked files) and
# $work/untracked.
collect_changed() {
  g diff --name-only "$mb" -- > "$work/tracked" || die "git diff failed"
  g ls-files --others --exclude-standard > "$work/untracked" || die "git ls-files failed"
  cat "$work/tracked" "$work/untracked" > "$work/changed"
}

run_dup() {
  local rc=0
  tool dryer > "$work/dryer.txt" || rc=$?
  [ "$rc" = 0 ] || die "dryer exited $rc"
  code-metrics-filter dup --changed "$work/changed" < "$work/dryer.txt"
}

run_coverage() {
  local rc=0
  sh -c "$coverage_command" || rc=$?
  [ "$rc" = 0 ] || die "coverage command exited $rc: no report read"
}

run_crap() {
  local rc=0
  local -a files=() extra=()
  code-metrics-filter sources --changed "$work/changed" > "$work/sources" || die "source filter failed"
  mapfile -t files < "$work/sources"
  if [ "${#files[@]}" -eq 0 ]; then
    echo "code-metrics crap: no changed source file"
    return 0
  fi
  if [ -n "$threshold" ]; then
    extra=(--threshold "$threshold")
  fi
  run_coverage
  tool crapper --use-existing-coverage "${extra[@]}" "${files[@]}" || rc=$?
  case $rc in
    0) return 0 ;;
    2) return 1 ;;
    *) die "crapper exited $rc" ;;
  esac
}

run_mutate() {
  local file rc path numbers survived=0 not_run=0 ran=0
  local -a files=() lines_arg=()
  local -A lines_of=() untracked=()
  code-metrics-filter sources --changed "$work/changed" > "$work/sources" || die "source filter failed"
  mapfile -t files < "$work/sources"
  if [ "${#files[@]}" -eq 0 ]; then
    echo "code-metrics mutate: no changed source file"
    return 0
  fi
  g diff -U0 --no-ext-diff --no-textconv --no-color --src-prefix=a/ --dst-prefix=b/ "$mb" -- > "$work/diff" || die "git diff failed"
  code-metrics-filter lines < "$work/diff" > "$work/lines" || die "line filter failed"
  while IFS=$'\t' read -r path numbers; do
    lines_of[$path]=$numbers
  done < "$work/lines"
  while IFS= read -r path; do
    untracked[$path]=1
  done < "$work/untracked"
  for file in "${files[@]}"; do
    if [ -n "${lines_of[$file]-}" ]; then
      lines_arg=(--lines "${lines_of[$file]}")
    elif [ -n "${untracked[$file]-}" ]; then
      lines_arg=()
    else
      echo "code-metrics mutate: $file has no added line, skipped"
      continue
    fi
    if [ -n "$coverage_command" ]; then
      run_coverage
    fi
    rc=0
    tool mutator --test-command "$test_command" --use-existing-coverage "${lines_arg[@]}" "$file" 2> "$work/mutator.err" || rc=$?
    cat "$work/mutator.err" >&2
    ran=$((ran + 1))
    # mutator exits 0 when no report covers the file: every site is skipped
    # as uncovered, so nothing was tested.
    if [ "$rc" = 0 ] && grep -q '^No coverage data for ' "$work/mutator.err"; then
      rc=uncovered
    fi
    case $rc in
      0) ;;
      3) survived=$((survived + 1)) ;;
      *)
        echo "code-metrics mutate: $file not tested (mutator: $rc)" >&2
        not_run=$((not_run + 1))
        ;;
    esac
  done
  echo "code-metrics mutate: files=$ran survived=$survived not_run=$not_run"
  if [ "$not_run" -gt 0 ]; then
    return 2
  fi
  if [ "$survived" -gt 0 ]; then
    return 1
  fi
  return 0
}

[ $# -gt 0 ] || bad_usage "missing subcommand"
cmd=$1
shift
case $cmd in
  -h | --help | help)
    usage
    exit 0
    ;;
  setup)
    run_setup "$@"
    exit 0
    ;;
  dup | crap | mutate) ;;
  *) bad_usage "unknown subcommand: $cmd" ;;
esac

base=""
coverage_command=""
test_command=""
threshold=""
while [ $# -gt 0 ]; do
  case $1 in
    --base | --coverage-command | --test-command | --threshold)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        bad_usage "$1 needs a value"
      fi
      case $2 in
        -*) bad_usage "$1 needs a value, got $2" ;;
      esac
      case $1 in
        --base) base=$2 ;;
        --coverage-command) coverage_command=$2 ;;
        --test-command) test_command=$2 ;;
        --threshold) threshold=$2 ;;
      esac
      shift 2
      ;;
    *) bad_usage "unknown argument for $cmd: $1" ;;
  esac
done

case $cmd in
  dup)
    [ -z "$coverage_command$test_command$threshold" ] || bad_usage "dup takes only --base"
    ;;
  crap)
    [ -n "$coverage_command" ] || bad_usage "crap needs --coverage-command"
    [ -z "$test_command" ] || bad_usage "crap takes no --test-command"
    ;;
  mutate)
    [ -n "$test_command" ] || bad_usage "mutate needs --test-command"
    [ -z "$threshold" ] || bad_usage "mutate takes no --threshold"
    ;;
esac

require_ready
top=$(g rev-parse --show-toplevel 2> /dev/null) || die "not inside a git work tree"
cd "$top"
mb=""
resolve_base
work=$(mktemp -d)
trap 'rm -r "$work"' EXIT
collect_changed

rc=0
case $cmd in
  dup) run_dup || rc=$? ;;
  crap) run_crap || rc=$? ;;
  mutate) run_mutate || rc=$? ;;
esac
exit "$rc"
