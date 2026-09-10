# config-merge — reconcile ~/.codex/config.toml with the repo, WITHOUT ever
# regenerating it.
# (writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
# build time — do not add either here.)
#
# WHY THIS FILE IS MERGED AND NEVER GENERATED
#   Codex stores per-hook trust INSIDE this same file, as
#     [hooks.state."<abs-path>:<snake_event>:<group>:<hook>"]
#   tables carrying `trusted_hash = "sha256:…"`. Wiping them silently
#   un-trusts every hook, and an un-trusted hook is SKIPPED IN SILENCE — the
#   exact failure this module exists to repair.
#
# WHAT IT FORCES: the root keys named on the command line, and nothing else.
#   Today nix passes two.
#     sandbox_mode     — decides what the agent may break; a silent drift to
#                        full access is what a declarative config exists to
#                        prevent.
#     approval_policy  — with approvals off there is no human confirmation
#                        left, so what stands between the model and the
#                        filesystem is the sandbox and the branch hooks. A
#                        deliberate trade, not a convenience.
#   `model` and `model_reasoning_effort` are deliberately NOT forced: the
#   application rewrites them itself when the user runs /model, exactly as the
#   Claude side of this repo refuses to force `.model`.
#
# WHERE IT WRITES: the PREAMBLE only — every line before the first line
#   matching /^\[/. TOML requires root keys to precede the first table header,
#   so a root key can only legally live there: the restriction is the
#   language, not a heuristic. Everything from the first `[` to EOF passes
#   through byte for byte, and that is re-checked with cmp before the rename.
#   A key of the same name INSIDE a table (say [profiles.x] sandbox_mode) is a
#   different key and is never touched.
#
# CONTRACT
#   - ALWAYS exits 0. It runs inside a home-manager activation, where a
#     non-zero exit kills the whole DAG chain.
#   - Atomic: writes a temp file in the SAME directory, validates it, then
#     renames — a live Codex session may be writing the same file.
#   - Validated before it commits: the result must still parse, must keep the
#     same number of trust entries, and must keep the table section byte for
#     byte. Any failure leaves the original untouched and warns.
#   - Never silent on a change: one line per key, naming the old value and the
#     new one. Silent when nothing changes; a second run changes no byte.
#
# Usage: codex-config-merge [--config PATH] KEY=VALUE [KEY=VALUE ...]
#   --config exists so the offline harness can exercise a COPY. Activation
#   passes the pairs only.

CONFIG="$HOME/.codex/config.toml"
KEYS=()
VALS=()

warn() { printf 'codex-config-merge: %s\n' "$*" >&2; }
note() { printf 'codex-config-merge: %s\n' "$*"; }

# The temp file never outlives the run.
TMP=""
# shellcheck disable=SC2329  # invoked indirectly, by the trap below.
cleanup() {
  if [ -n "$TMP" ] && [ -e "$TMP" ]; then rm -f "$TMP"; fi
}
trap cleanup EXIT
trap 'warn "unexpected failure (exit $?); $CONFIG left untouched"; exit 0' ERR

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      if [ "$#" -lt 2 ]; then
        warn "--config needs a path; nothing to do"
        exit 0
      fi
      CONFIG="$2"
      shift 2
      ;;
    *=*)
      KEYS+=("${1%%=*}")
      VALS+=("${1#*=}")
      shift
      ;;
    *)
      warn "not a KEY=VALUE pair: $1; nothing to do"
      exit 0
      ;;
  esac
done

BACKUP="$CONFIG.backup"

if [ "${#KEYS[@]}" -eq 0 ]; then
  warn "no KEY=VALUE pair given; nothing to do"
  exit 0
fi

# tomlq comes from pkgs.yq (modules/packages.nix). Without it there is no way
# to validate the result, so nothing gets written.
if ! command -v tomlq > /dev/null 2>&1; then
  warn "tomlq not found (pkgs.yq); $CONFIG left untouched"
  exit 0
fi

# First install: the file may simply not exist yet.
if [ ! -f "$CONFIG" ]; then
  mkdir -p "$(dirname "$CONFIG")"
  : > "$CONFIG"
  for i in "${!KEYS[@]}"; do
    printf '%s = "%s"\n' "${KEYS[$i]}" "${VALS[$i]}" >> "$CONFIG"
    note "created $CONFIG with ${KEYS[$i]} = \"${VALS[$i]}\""
  done
  exit 0
fi

# Refuse to edit a file that does not parse: the after-the-fact validation
# below would have nothing to compare against, and a hand-broken file must be
# fixed by hand, not silently rewritten around.
if ! tomlq -e . "$CONFIG" > /dev/null 2>&1; then
  warn "$CONFIG does not parse as TOML; refusing to edit it — fix it by hand, then rebuild"
  exit 0
fi

ORIG_TRUST="$(tomlq -r '(.hooks.state // {}) | keys | length' "$CONFIG" 2> /dev/null || printf '')"
if [ -z "$ORIG_TRUST" ]; then
  warn "could not read the trust table from $CONFIG; refusing to edit it"
  exit 0
fi

# Which keys actually differ? A key already at its target value is left alone,
# and that — not canonical rewriting — is what makes a second run change zero
# bytes.
TODO_KEYS=()
TODO_VALS=()
TODO_OLD=()
for i in "${!KEYS[@]}"; do
  current="$(tomlq -r ".${KEYS[$i]} // \"\"" "$CONFIG" 2> /dev/null || printf '')"
  if [ "$current" != "${VALS[$i]}" ]; then
    TODO_KEYS+=("${KEYS[$i]}")
    TODO_VALS+=("${VALS[$i]}")
    if [ -n "$current" ]; then
      TODO_OLD+=("$current")
    else
      TODO_OLD+=("(absent)")
    fi
  fi
done

if [ "${#TODO_KEYS[@]}" -eq 0 ]; then
  exit 0
fi

TMP="$(mktemp "$CONFIG.merge.XXXXXX" 2> /dev/null || printf '')"
if [ -z "$TMP" ]; then
  warn "could not create a temp file next to $CONFIG; left untouched"
  exit 0
fi
# Inherit the original's mode through the inode: the redirections below
# truncate the temp file, they do not recreate it.
cp -p "$CONFIG" "$TMP"

STAGE="$TMP.stage"
for i in "${!TODO_KEYS[@]}"; do
  key="${TODO_KEYS[$i]}"
  # Tolerant match: bare, double-quoted and single-quoted key spellings are
  # all legal TOML. The `\t` reaches awk as a real tab (awk -v processes
  # escapes).
  key_re="^[ \t]*(\"$key\"|'$key'|$key)[ \t]*="
  new_line="$(printf '%s = "%s"' "$key" "${TODO_VALS[$i]}")"

  # Is the key present in the PREAMBLE? An occurrence inside a table is a
  # different key and must be left alone.
  if awk -v re="$key_re" '
        BEGIN { pre = 1 }
        /^\[/ { pre = 0 }
        pre && $0 ~ re { found = 1; exit }
        END { exit(found ? 0 : 1) }
      ' "$TMP"; then
    awk -v re="$key_re" -v repl="$new_line" '
      BEGIN { pre = 1; done = 0 }
      /^\[/ { pre = 0 }
      {
        if (pre && !done && $0 ~ re) { print repl; done = 1 }
        else { print }
      }
    ' "$TMP" > "$STAGE"
  else
    # Root keys must precede the first table header, so the top of the file is
    # the only universally legal place to put one.
    {
      printf '%s\n' "$new_line"
      cat "$TMP"
    } > "$STAGE"
  fi
  mv "$STAGE" "$TMP"
done

if ! tomlq -e . "$TMP" > /dev/null 2>&1; then
  warn "the edited file would not parse as TOML; $CONFIG left untouched"
  exit 0
fi

NEW_TRUST="$(tomlq -r '(.hooks.state // {}) | keys | length' "$TMP" 2> /dev/null || printf '')"
if [ "$NEW_TRUST" != "$ORIG_TRUST" ]; then
  warn "trust entries would go from $ORIG_TRUST to ${NEW_TRUST:-unreadable}; $CONFIG left untouched"
  exit 0
fi

# Belt and braces for the whole design: everything from the first table header
# to EOF must be identical, byte for byte.
if ! cmp -s \
  <(awk 'BEGIN { t = 0 } /^\[/ { t = 1 } t' "$CONFIG") \
  <(awk 'BEGIN { t = 0 } /^\[/ { t = 1 } t' "$TMP"); then
  warn "the table section would change; $CONFIG left untouched"
  exit 0
fi

cp -p "$CONFIG" "$BACKUP" || warn "could not write $BACKUP"
mv "$TMP" "$CONFIG"
TMP=""

for i in "${!TODO_KEYS[@]}"; do
  note "${TODO_KEYS[$i]}: ${TODO_OLD[$i]} -> ${TODO_VALS[$i]}"
done
exit 0
