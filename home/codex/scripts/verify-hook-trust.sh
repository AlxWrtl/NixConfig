# verify-hook-trust — warn, after a rebuild, when a generated Codex hook is
# not going to run.
# (writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
# build time — do not add either here.)
#
# WHAT IT CANNOT DO, SAID FIRST
#   It cannot ask Codex anything. There is no hooks subcommand, and
#   `codex doctor` runs 23 checks of which none concerns hooks. So it can never
#   confirm that a hook IS trusted at runtime. It can only say that one is
#   un-approved or stale. Its silence is not proof of protection, and its
#   output says so out loud — a checker that implies a guarantee it cannot
#   verify is worse than no checker.
#
# TWO DETECTORS, AND WHY BOTH
#   1. MISSING TRUST ENTRY — the expected [hooks.state] keys are passed in as
#      arguments by nix, from the same expression that generates hooks.json, so
#      they cannot drift from it. They are compared against
#      `tomlq -r '.hooks.state | keys[]' ~/.codex/config.toml`.
#   2. STALE HASH — the sha256 of the generated hooks.json against a baseline
#      recorded at the last reviewed verification. If the content changed,
#      every trust entry is stale BY CONSTRUCTION, because the hash Codex
#      records is over hook content.
#   Detector 1 alone would be wrong today: the two expected keys ALREADY exist,
#   carrying the hashes of the old, now-deleted hooks. It would report
#   "trusted". Detector 2 is what makes the first rebuild warn correctly.
#
# WHERE THE BASELINE LIVES, AND WHY THERE
#   ~/.local/state/codex-declarative/hooks.sha256 — deliberately NOT under
#   ~/.codex, which is inside the agent's writable set. An agent must not be
#   able to forge its own clean bill of health.
#   It is written ONLY by an explicit `-a` (accept), never by activation: the
#   review it records is a human act (open Codex, /hooks, trust), and nothing
#   here can perform it. Until then the warning repeats at every rebuild, which
#   is the point.
#
# CONTRACT: exits 0 unconditionally, never aborts the activation chain, never
# deletes anything.
#
# Usage: codex-verify-hook-trust [-j hooks.json] [-c config.toml]
#                                [-s baseline] [-a] KEY...
#   -a   record the current hooks.json hash as the reviewed baseline
#   KEY  an expected [hooks.state] key, e.g.
#        /Users/you/.codex/hooks.json:pre_tool_use:0:0

HOOKS="$HOME/.codex/hooks.json"
CONFIG="$HOME/.codex/config.toml"
STATE="$HOME/.local/state/codex-declarative/hooks.sha256"
ACCEPT=no

FINDINGS=""
NFOUND=0
CUR_HASH=""

add() {
  NFOUND=$((NFOUND + 1))
  FINDINGS="$FINDINGS  ! $1"$'\n'
}

# Nothing below may take the activation chain down with it.
trap 'printf "codex-hook-trust: unexpected failure (exit %s); nothing checked.\n" "$?" >&2; exit 0' ERR

usage() {
  printf '%s\n' \
    'usage: codex-verify-hook-trust [-j hooks.json] [-c config.toml] [-s baseline] [-a] KEY...' \
    '  -a  record the current hooks.json hash as the reviewed baseline'
}

# Hand-rolled rather than getopts, and the reason is a real bug this had.
# getopts stops at the first non-option word, so `… KEY KEY -a` left ACCEPT
# unset AND fed `-a` in as a fourth expected trust key — the tool then reported
# "never approved — no trust entry for: -a" and silently declined to record.
# The flag's position must not matter: a human typing it at the end is the
# natural spelling, and the guidance printed below used to suggest exactly that.
KEYS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -j)
      if [ "$#" -lt 2 ]; then usage >&2; exit 0; fi
      HOOKS="$2"; shift 2 ;;
    -c)
      if [ "$#" -lt 2 ]; then usage >&2; exit 0; fi
      CONFIG="$2"; shift 2 ;;
    -s)
      if [ "$#" -lt 2 ]; then usage >&2; exit 0; fi
      STATE="$2"; shift 2 ;;
    -a) ACCEPT=yes; shift ;;
    -h) usage; exit 0 ;;
    --) shift; while [ "$#" -gt 0 ]; do KEYS+=("$1"); shift; done ;;
    -*)
      # Never let an unknown flag pass for a trust key: it would be reported as
      # un-approved, which reads as a security finding about a hook that does
      # not exist.
      printf 'codex-hook-trust: unknown option %s\n' "$1" >&2
      usage >&2
      exit 0 ;;
    *) KEYS+=("$1"); shift ;;
  esac
done
set -- "${KEYS[@]+"${KEYS[@]}"}"

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Detector 2 runs FIRST: staleness is a property of the whole hooks file, and
# it decides how each key of detector 1 has to be read. A key that is present
# but stale looks approved and is not.
# ---------------------------------------------------------------------------
STALE=unknown
if [ ! -f "$HOOKS" ]; then
  add "$HOOKS does not exist: no generated hook is installed"
else
  CUR_HASH="$(sha_of "$HOOKS" 2>/dev/null || printf '')"
  if [ -z "$CUR_HASH" ]; then
    # Do not name a cause the code has not established. The first version said
    # "no sha256 tool found" and was wrong: sha256sum was present, `awk` was
    # not, so the pipeline failed. A check that misreports why it could not run
    # sends the reader after the wrong thing.
    if command -v sha256sum > /dev/null 2>&1 || command -v shasum > /dev/null 2>&1; then
      add "could not compute the hash of $HOOKS although a sha256 tool exists — a helper it pipes through (awk) is missing from PATH"
    else
      add "no sha256 tool found: $HOOKS could not be checked against its baseline"
    fi
  elif [ ! -f "$STATE" ]; then
    STALE=yes
    add "no reviewed baseline at $STATE: this hooks file has never been recorded as reviewed"
  else
    OLD_HASH=""
    read -r OLD_HASH _ < "$STATE" || true
    if [ "$OLD_HASH" != "$CUR_HASH" ]; then
      STALE=yes
      add "$HOOKS changed since the reviewed baseline (${OLD_HASH:0:12}… -> ${CUR_HASH:0:12}…): the hash Codex records is over hook content, so every trust entry below is stale by construction"
    else
      STALE=no
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Detector 1 — a generated hook with no trust entry was never approved.
# ---------------------------------------------------------------------------
TRUSTED=""
TRUST_READABLE=no
if [ ! -f "$CONFIG" ]; then
  add "$CONFIG does not exist, so no hook can be trusted yet"
elif ! command -v tomlq >/dev/null 2>&1; then
  add "tomlq not found (pkgs.yq): the trust table in $CONFIG could not be read"
elif ! tomlq -e . "$CONFIG" >/dev/null 2>&1; then
  add "$CONFIG does not parse as TOML: the trust table could not be read"
else
  TRUSTED="$(tomlq -r '(.hooks.state // {}) | keys[]' "$CONFIG" 2>/dev/null || printf '')"
  TRUST_READABLE=yes
fi

if [ "$#" -eq 0 ]; then
  add "no expected trust keys were passed in, so no hook was checked for approval"
fi

# A key with NO trust entry is the one finding that contradicts `-a` outright,
# so it is counted separately: see the record block at the end.
NEVER=0
for key in "$@"; do
  if [ "$TRUST_READABLE" = no ]; then
    add "could not check the trust entry for: $key"
  elif ! printf '%s\n' "$TRUSTED" | grep -Fxq -- "$key"; then
    NEVER=$((NEVER + 1))
    add "never approved — no trust entry for: $key"
  elif [ "$STALE" = yes ]; then
    add "approval is STALE, re-approve: $key"
  elif [ "$STALE" = unknown ]; then
    add "trust entry present, but staleness could not be checked: $key"
  fi
done

# ---------------------------------------------------------------------------
# Stray sibling files. NOTICE ONLY — never a deletion. A half-written
# hooks.json.new is one rename away from blanking every hook, but installing a
# recurring delete-by-name primitive in a directory this repo does not own
# would solve forever a problem that exists once.
# ---------------------------------------------------------------------------
for stray in "$HOOKS".*; do
  [ -e "$stray" ] || continue
  add "stray file beside the hooks file: $stray — one rename away from replacing it. Remove it BY HAND; nothing here deletes files in ~/.codex."
done

# ---------------------------------------------------------------------------
# Report.
# ---------------------------------------------------------------------------
if [ "$NFOUND" -gt 0 ]; then
  {
    printf 'codex-hook-trust: %s finding(s) — a generated hook may be skipped in silence.\n' "$NFOUND"
    printf '%s' "$FINDINGS"
    printf '%s\n' \
      '  This check CANNOT confirm that a hook is trusted at runtime: Codex exposes no' \
      '  command that reports hook trust. It can only report that a hook is un-approved' \
      '  or stale. Its silence is not proof that you are protected.' \
      '  FIX, in this order: open Codex, run /hooks, review and trust the hooks.' \
      '  ONLY THEN record the baseline, and pass the same keys the activation' \
      '  passes — recording it first would satisfy the staleness check for that' \
      '  content forever, while the hooks may never have been approved:' \
      "    codex-verify-hook-trust -a $*"
  } >&2
else
  printf 'codex-hook-trust: nothing un-approved or stale detected. This check cannot confirm a hook is trusted at runtime — only that one is un-approved or stale.\n'
fi

if [ "$ACCEPT" = yes ]; then
  # Refuse to record when nothing was checked. Measured 2026-09-10: run as a
  # bare `-a`, this tool printed "no expected trust keys were passed in, so no
  # hook was checked for approval" and then recorded a baseline anyway. That
  # baseline satisfies the staleness detector for that exact content forever,
  # so a later run reports clean while the hooks may never have been approved —
  # a security tool issuing a certificate it has just said it cannot justify.
  # The baseline is a HUMAN statement that the hooks were reviewed in a Codex
  # session; it is only meaningful alongside the keys it vouches for.
  #
  # What `-a` can and cannot refuse, and the line between them was drawn the
  # hard way. It CANNOT refuse on staleness: staleness is derived from this
  # baseline, so after every rebuild every key reads stale until the baseline
  # is re-recorded. Blocking there would make the flag impossible to use in the
  # one situation it exists for. Nothing here can observe that a human just
  # approved in a Codex session — `-a` IS that human statement.
  # It CAN refuse when a key has NO trust entry at all: that is checkable, and
  # it flatly contradicts the claim being recorded.
  if [ "$#" -eq 0 ]; then
    printf 'codex-hook-trust: refusing to record a baseline — no expected trust keys were passed, so nothing was checked.\n' >&2
    printf '  Approve the hooks first (open Codex, run /hooks), then re-run this with the same keys the activation passes, plus -a.\n' >&2
  elif [ "$NEVER" -gt 0 ]; then
    printf 'codex-hook-trust: refusing to record a baseline — %s of the hooks you are vouching for has no trust entry at all, so it was never approved.\n' "$NEVER" >&2
    printf '  Open Codex, run /hooks, trust them, then re-run this command.\n' >&2
  elif [ -z "$CUR_HASH" ]; then
    printf 'codex-hook-trust: nothing to record — no hash could be computed for %s\n' "$HOOKS" >&2
  elif mkdir -p "$(dirname "$STATE")" 2>/dev/null && printf '%s\n' "$CUR_HASH" > "$STATE" 2>/dev/null; then
    printf 'codex-hook-trust: reviewed baseline recorded (%s… in %s)\n' "${CUR_HASH:0:12}" "$STATE"
    printf '  This records YOUR statement that you have just reviewed and trusted these hooks in Codex. Nothing here can verify it.\n'
  else
    printf 'codex-hook-trust: could not write the baseline to %s\n' "$STATE" >&2
  fi
fi

exit 0
