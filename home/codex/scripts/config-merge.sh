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
#   exact failure this module exists to repair. Nine such entries exist today.
#
# WHAT IT FORCES: exactly ONE key, `sandbox_mode`, whose value comes from nix
#   as $1. It is the key that decides what the agent may break; a silent drift
#   to full access is precisely what a declarative configuration exists to
#   prevent. `model` and `model_reasoning_effort` are deliberately NOT touched:
#   the application rewrites them itself when the user runs /model, exactly as
#   the Claude side of this repo refuses to force `.model`
#   (home/claude-code/activation.nix:96-98).
#
# WHERE IT WRITES: the PREAMBLE only — every line before the first line
#   matching /^\[/. TOML requires root keys to precede the first table header,
#   so a root `sandbox_mode` can only legally live there: the restriction is
#   the language, not a heuristic. Everything from the first `[` to EOF passes
#   through byte for byte, and that is re-checked with cmp before the rename.
#
# CONTRACT
#   - ALWAYS exits 0. It runs inside a home-manager activation, where a
#     non-zero exit kills the whole DAG chain.
#   - Atomic: writes a temp file in the SAME directory, validates it, then
#     renames — a live Codex session may be writing the same file.
#   - Validated before it commits: the result must still parse, must keep the
#     same number of trust entries, and must keep the table section byte for
#     byte. Any failure leaves the original untouched and warns.
#   - Never silent on a change: one line naming the key, the old value and the
#     new one. Silent when nothing changes; a second run changes no byte.
#
# Usage: codex-config-merge <sandbox_mode> [config.toml path]
#   $2 exists so the offline harness can exercise a COPY. Activation passes $1
#   only.

MODE="${1:-}"
CONFIG="${2:-$HOME/.codex/config.toml}"
BACKUP="$CONFIG.backup"
TMP=""

warn() { printf 'codex-config-merge: %s\n' "$*" >&2; }
note() { printf 'codex-config-merge: %s\n' "$*"; }

# The temp file never outlives the run. `exit 0` in the ERR trap below runs
# this one too, so a crash cleans up on its way out.
trap 'if [ -n "$TMP" ] && [ -e "$TMP" ]; then rm -f "$TMP" || true; fi' EXIT
# A crash must not take the activation chain down with it, and must not pass
# for success either.
trap 'warn "unexpected failure (exit $?); $CONFIG left untouched"; exit 0' ERR

if [ -z "$MODE" ]; then
  warn "no sandbox_mode value given; nothing to do"
  exit 0
fi

# tomlq comes from pkgs.yq (modules/packages.nix). Without it there is no way
# to validate the result, so nothing gets written.
if ! command -v tomlq >/dev/null 2>&1; then
  warn "tomlq not found (pkgs.yq); $CONFIG left untouched"
  exit 0
fi

# First install: the file may simply not exist yet.
if [ ! -f "$CONFIG" ]; then
  mkdir -p "$(dirname "$CONFIG")"
  printf 'sandbox_mode = "%s"\n' "$MODE" > "$CONFIG"
  note "created $CONFIG with sandbox_mode = \"$MODE\""
  exit 0
fi

# Refuse to edit a file that does not parse: the after-the-fact validation
# below would have nothing to compare against, and a hand-broken file must be
# fixed by hand, not silently rewritten around.
if ! tomlq -e . "$CONFIG" >/dev/null 2>&1; then
  warn "$CONFIG does not parse as TOML; refusing to edit it — fix it by hand, then rebuild"
  exit 0
fi

ORIG_TRUST="$(tomlq -r '(.hooks.state // {}) | keys | length' "$CONFIG" 2>/dev/null || printf '')"
if [ -z "$ORIG_TRUST" ]; then
  warn "could not read the trust table from $CONFIG; refusing to edit it"
  exit 0
fi

CURRENT="$(tomlq -r '.sandbox_mode // ""' "$CONFIG" 2>/dev/null || printf '')"
if [ "$CURRENT" = "$MODE" ]; then
  # Already right. Say nothing, touch nothing — this is what makes a second
  # run change no byte.
  exit 0
fi

# Tolerant match: bare, double-quoted and single-quoted key spellings are all
# legal TOML. The `\t` reaches awk as a real tab (awk -v processes escapes).
KEY_RE='^[ \t]*("sandbox_mode"|'"'"'sandbox_mode'"'"'|sandbox_mode)[ \t]*='
NEW_LINE="$(printf 'sandbox_mode = "%s"' "$MODE")"

# Is the key present in the PREAMBLE? An occurrence inside a table is a
# different key (e.g. [profiles.x] sandbox_mode) and must be left alone.
HAS_LINE=no
if awk -v re="$KEY_RE" '
      BEGIN { pre = 1 }
      /^\[/ { pre = 0 }
      pre && $0 ~ re { found = 1; exit }
      END { exit(found ? 0 : 1) }
    ' "$CONFIG"; then
  HAS_LINE=yes
fi

TMP="$(mktemp "$CONFIG.merge.XXXXXX" 2>/dev/null || printf '')"
if [ -z "$TMP" ]; then
  warn "could not create a temp file next to $CONFIG; left untouched"
  exit 0
fi
# Inherit the original's mode through the inode: the redirection below
# truncates the temp file, it does not recreate it.
cp -p "$CONFIG" "$TMP"

if [ "$HAS_LINE" = yes ]; then
  awk -v re="$KEY_RE" -v repl="$NEW_LINE" '
    BEGIN { pre = 1; done = 0 }
    /^\[/ { pre = 0 }
    {
      if (pre && !done && $0 ~ re) { print repl; done = 1 }
      else { print }
    }
  ' "$CONFIG" > "$TMP"
else
  # Root keys must precede the first table header, so the top of the file is
  # the only universally legal place to put one.
  { printf '%s\n' "$NEW_LINE"; cat "$CONFIG"; } > "$TMP"
fi

if ! tomlq -e . "$TMP" >/dev/null 2>&1; then
  warn "the edited file would not parse as TOML; $CONFIG left untouched"
  exit 0
fi

NEW_TRUST="$(tomlq -r '(.hooks.state // {}) | keys | length' "$TMP" 2>/dev/null || printf '')"
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

OLD_SHOWN="$CURRENT"
[ -n "$OLD_SHOWN" ] || OLD_SHOWN="(absent)"
note "sandbox_mode: $OLD_SHOWN -> $MODE"
exit 0
