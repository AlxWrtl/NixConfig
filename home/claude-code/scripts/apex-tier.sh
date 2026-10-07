# apex-tier — classify the APEX tier from the DIFF, not from the brief text.
#
# READ-ONLY: runs only `git diff`, `git show`, `git ls-files`, `git merge-base`
# and reads files. Never `git add -N`, never writes the index or the tree.
#
# Output, one line, exit 0:
#   tier=direct|standard|high lines=N files=F reasons=a,b
# Exit 2 only on a usage error (unknown option, bad --base / --max-lines).
#
# Size: `git diff --numstat REF` (working tree vs REF, tracked files) plus
# untracked, non-ignored files counted whole by `wc -l`. `.claude/output` is
# excluded everywhere (APEX's own artifacts). A binary file counts 0 lines but
# raises the tier to at least standard: its content cannot be read here.
#
# Tier: high if any reason; else standard if lines > --max-lines (30) or
# files > 3 (a change spread over many files is not "direct" even when small);
# else direct.
#
# Reasons (all escalate to high — the heuristic errs toward escalation):
#   secret-path   .env*, secrets/, an ssh key name (id_rsa...), or the FULL
#                 path containing token|key|cert|pem|secret|credential|password
#                 as a case-insensitive SUBSTRING (spec: `*token*`, `*key*`,
#                 `*cert*`). Accepted false positives: `keybindings.json`,
#                 `monkey.ts`, `hotkeys/` all go high — errs toward escalation.
#   permission    a changed line, or one of its indentation ancestors, is a
#                 permissions / sandbox / allow / deny / ask KEY. Ancestors =
#                 the lines above with strictly smaller indentation, walking
#                 up (new file for + lines, old file for - lines). So an entry
#                 added inside `deny = [` is high, while a `matcher = "..."`
#                 added under hooks.Notification is not (its ancestry is
#                 hooks/Notification). Lines that only close brackets are
#                 skipped as ancestors.
#   hook-decision a changed file under a hooks/ directory whose WHOLE content
#                 (new file, or base file when deleted) holds a guard
#                 decision anywhere: permissionDecision, "deny", 'deny',
#                 "block", decision...block, exit 2, process.exit(2). Whole
#                 file, not changed lines: a changed condition above an
#                 unchanged deny is still a guard change. A hook with no
#                 decision statement (a notifier) is not escalated.
#   destructive   --force, push -f, DROP, TRUNCATE, DELETE FROM, rm -rf,
#                 migrat*, deploy.
#   A comment that says "deny" also escalates: accepted false positive.
#
# --paths p... classifies PATHS ONLY (plan time, before any diff exists):
# only secret-path and the files>3 rule apply; lines=0. Re-run without
# --paths once the diff exists — that run is authoritative.

usage() {
  echo "usage: apex-tier [--base REF] [--max-lines N] [--paths PATH...]" >&2
  exit 2
}

base=""
max_lines=30
paths_mode=0
declare -a paths=()

while [ $# -gt 0 ]; do
  case "$1" in
  --base)
    [ $# -ge 2 ] || usage
    base="$2"
    shift 2
    ;;
  --max-lines)
    [ $# -ge 2 ] || usage
    max_lines="$2"
    shift 2
    ;;
  --paths)
    paths_mode=1
    shift
    while [ $# -gt 0 ]; do
      paths+=("$1")
      shift
    done
    ;;
  -h | --help)
    usage
    ;;
  *)
    echo "apex-tier: unknown argument: $1" >&2
    usage
    ;;
  esac
done

case "$max_lines" in
'' | *[!0-9]*)
  echo "apex-tier: --max-lines needs a non-negative integer" >&2
  usage
  ;;
esac

declare -a reasons=()
add_reason() {
  local r
  for r in "${reasons[@]+"${reasons[@]}"}"; do
    [ "$r" = "$1" ] && return 0
  done
  reasons+=("$1")
}

# Path class, on the lowercased FULL path (substring, not word).
is_secret_path() {
  local lp lb
  lp="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  lb="${lp##*/}"
  case "$lb" in .env*) return 0 ;; esac
  case "$lp" in secrets/* | */secrets/*) return 0 ;; esac
  grep -Eq 'token|key|cert|pem|secret|credential|password' <<<"$lp" && return 0
  grep -Eq '^id_(rsa|dsa|ecdsa|ed25519)' <<<"$lb" && return 0
  return 1
}

PERM_RE='(^|[^a-z0-9_-])"?(permissions|sandbox|allow|deny|ask)"?[[:space:]]*[=:]|(^|[^a-z0-9_-])(permissions|sandbox)\.'
HOOK_RE='permissiondecision|"deny"|'"'"'deny'"'"'|"block"|decision.*block|exit[[:space:]]+2([^0-9]|$)|process\.exit\([[:space:]]*2[[:space:]]*\)'
DESTR_RE='--force|push[[:space:]]+-f([^a-z]|$)|rm[[:space:]]+-rf|migrat|deploy|delete[[:space:]]+from'
SQL_RE='\b(DROP|TRUNCATE)\b'

# Context text check: stdin = changed lines + their ancestors.
classify_text() {
  local file="$1" text
  text="$(cat)"
  [ -n "$text" ] || return 0
  if grep -Eiq -- "$PERM_RE" <<<"$text"; then
    add_reason "permission@$file"
  fi
  if grep -Eiq -- "$DESTR_RE" <<<"$text" ||
    grep -Eq -- "$SQL_RE" <<<"$text"; then
    add_reason "destructive@$file"
  fi
}

# Hook class on the WHOLE file: working-tree content, or the base content
# when the file was deleted. Paths-mode never calls it ($base unset there).
classify_hook_file() {
  local file="$1" content
  case "/$file" in */hooks/*) ;; *) return 0 ;; esac
  if [ -f "$file" ]; then
    content="$(cat -- "$file")"
  else
    content="$(git show "$base:$file" 2>/dev/null || true)"
  fi
  if grep -Eiq -- "$HOOK_RE" <<<"$content"; then
    add_reason "hook-decision@$file"
  fi
  return 0
}

# stdin = file content; $1 = space-separated line numbers. Prints each target
# line and its indentation ancestors.
# shellcheck disable=SC2016 # awk program, not shell expansion
ANCESTRY_AWK='
function indent(s,   m) { match(s, /^[ \t]*/); return RLENGTH }
{ L[NR] = $0 }
END {
  n = split(targets, T, " ")
  for (k = 1; k <= n; k++) {
    t = T[k] + 0
    if (t < 1 || t > NR) continue
    print L[t]
    cur = indent(L[t])
    for (i = t - 1; i >= 1 && cur > 0; i--) {
      s = L[i]
      if (s ~ /^[ \t]*$/) continue
      if (s ~ /^[ \t\]\)\};,'"'"'"]*$/) continue
      d = indent(s)
      if (d < cur) { print s; cur = d }
    }
  }
}'

ancestry() {
  awk -v targets="$1" "$ANCESTRY_AWK"
}

files=0
lines=0
binary=0

if [ "$paths_mode" -eq 1 ]; then
  for p in "${paths[@]+"${paths[@]}"}"; do
    files=$((files + 1))
    if is_secret_path "$p"; then add_reason "secret-path@$p"; fi
  done
else
  top="$(git rev-parse --show-toplevel)" || usage
  cd "$top"
  if [ -z "$base" ]; then
    base="$(git merge-base HEAD master 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
    [ -n "$base" ] || base="HEAD"
  fi
  if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
    echo "apex-tier: --base is not a commit: $base" >&2
    usage
  fi

  # Tracked: working tree vs base.
  while IFS= read -r -d '' rec; do
    added="${rec%%$'\t'*}"
    rest="${rec#*$'\t'}"
    deleted="${rest%%$'\t'*}"
    file="${rest#*$'\t'}"
    files=$((files + 1))
    if is_secret_path "$file"; then add_reason "secret-path@$file"; fi
    classify_hook_file "$file"
    if [ "$added" = "-" ]; then
      binary=1
      continue
    fi
    lines=$((lines + added + deleted))

    hunks="$(git diff -U0 --no-color --no-ext-diff --no-renames "$base" -- "$file" |
      awk '/^@@ / {
        split($2, o, ","); split($3, w, ",")
        os = substr(o[1], 2) + 0; oc = (2 in o) ? o[2] + 0 : 1
        ns = substr(w[1], 2) + 0; nc = (2 in w) ? w[2] + 0 : 1
        for (i = 0; i < oc; i++) printf "o %d\n", os + i
        for (i = 0; i < nc; i++) printf "n %d\n", ns + i
      }')"
    old_targets="$(printf '%s\n' "$hunks" | awk '$1 == "o" { printf "%s ", $2 }')"
    new_targets="$(printf '%s\n' "$hunks" | awk '$1 == "n" { printf "%s ", $2 }')"
    # Captured, then fed by here-string: a pipe INTO classify_text would run
    # it in a subshell and drop every reason it adds.
    ctx="$(
      if [ -n "$old_targets" ]; then
        git show "$base:$file" 2>/dev/null | ancestry "$old_targets" || true
      fi
      if [ -n "$new_targets" ] && [ -f "$file" ]; then
        ancestry "$new_targets" <"$file" || true
      fi
    )"
    classify_text "$file" <<<"$ctx"
  done < <(git diff --numstat -z --no-renames "$base" -- . ':!.claude/output')

  # Untracked, not ignored: every line is added.
  while IFS= read -r -d '' file; do
    files=$((files + 1))
    if is_secret_path "$file"; then add_reason "secret-path@$file"; fi
    if [ ! -s "$file" ]; then continue; fi
    classify_hook_file "$file"
    if ! grep -Iq . "$file"; then
      binary=1
      continue
    fi
    n="$(wc -l <"$file" | tr -d '[:space:]')"
    lines=$((lines + n))
    ctx="$(cat -- "$file")"
    classify_text "$file" <<<"$ctx"
  done < <(git ls-files -z --others --exclude-standard -- . ':!.claude/output')
fi

if [ "${#reasons[@]}" -gt 0 ]; then
  tier=high
elif [ "$lines" -gt "$max_lines" ] || [ "$files" -gt 3 ] || [ "$binary" -eq 1 ]; then
  tier=standard
else
  tier=direct
fi

joined="$(
  IFS=,
  printf '%s' "${reasons[*]+"${reasons[*]}"}"
)"
printf 'tier=%s lines=%s files=%s reasons=%s\n' "$tier" "$lines" "$files" "$joined"
exit 0
