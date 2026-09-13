# Reconcile only repo-owned Codex TOML regions. Always exits zero because it
# runs inside one Home Manager activation DAG.

CONFIG="$HOME/.codex/config.toml"
PROFILE=""
PROFILE_BLOCK=""
KEYS=()
VALS=()
TMP=""
STAGE=""
PROFILE_SEEN=0
BLOCK_SEEN=0

warn() { printf 'codex-config-merge: %s\n' "$*" >&2; }
note() { printf 'codex-config-merge: %s\n' "$*"; }
# shellcheck disable=SC2329 # Invoked indirectly by EXIT trap.
cleanup() {
  [ -z "$STAGE" ] || [ ! -e "$STAGE" ] || rm -f "$STAGE"
  [ -z "$TMP" ] || [ ! -e "$TMP" ] || rm -f "$TMP"
}
trap cleanup EXIT
trap 'warn "unexpected failure (exit $?); $CONFIG left untouched"; exit 0' ERR

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) [ "$#" -ge 2 ] || { warn "--config needs a path"; exit 0; }; CONFIG="$2"; shift 2 ;;
    --permissions-profile) [ "$#" -ge 2 ] && [ "$PROFILE_SEEN" -eq 0 ] || { warn "--permissions-profile missing or duplicated"; exit 0; }; PROFILE="$2"; PROFILE_SEEN=1; shift 2 ;;
    --permissions-block) [ "$#" -ge 2 ] && [ "$BLOCK_SEEN" -eq 0 ] || { warn "--permissions-block missing or duplicated"; exit 0; }; PROFILE_BLOCK="$2"; BLOCK_SEEN=1; shift 2 ;;
    *=*) KEYS+=("${1%%=*}"); VALS+=("${1#*=}"); shift ;;
    *) warn "unknown argument: $1"; exit 0 ;;
  esac
done

# THE SECOND COPY OF THE BLOCK, AND WHY IT IS ALLOWED TO EXIST.
# This script writes exactly one known block and refuses any other, so an
# argument reaching it from elsewhere cannot install an arbitrary permissions
# profile. That allowlist is the point, and it costs a duplicate of the string
# in `home/codex.nix`.
#
# The duplicate FAILS OPEN: a mismatch warns and `exit 0`, so the rebuild stays
# green and the profile is simply never updated. Measured 2026-09-14 —
# `workspace_roots` was added to `home/codex.nix`, `nix flake check` was green
# with 8 checks, `darwin-rebuild switch` succeeded, and the live config.toml came
# out byte-identical to the one from before. The only signal was one `warn` line
# in the middle of forty lines of activation output.
#
# C11 in checks/codex-config.nix now ties the two spellings together at eval
# time, because a green build that changes nothing is the failure this repo
# keeps finding. Editing either copy alone must turn the build red.
CANONICAL=$'[permissions.git-workspace]\nextends = ":workspace"\nworkspace_roots = { "/Users/alx/Vaults/AlxVault" = true }\nfilesystem = { ":workspace_roots" = { ".git" = "write", ".git/hooks" = "read" } }'
if [ "$PROFILE_BLOCK" = "$CANONICAL"$'\n' ]; then PROFILE_BLOCK="$CANONICAL"; fi
if [ "$PROFILE" != "git-workspace" ] || [ "$PROFILE_BLOCK" != "$CANONICAL" ]; then
  warn "exact git-workspace permissions profile is required; nothing to do"
  exit 0
fi
if [ "${#KEYS[@]}" -ne 2 ] \
  || [ "${KEYS[0]}=${VALS[0]}" != "default_permissions=git-workspace" ] \
  || [ "${KEYS[1]}=${VALS[1]}" != "approval_policy=never" ]; then
  warn "expected exactly default_permissions=git-workspace then approval_policy=never"
  exit 0
fi
command -v tomlq >/dev/null 2>&1 || { warn "tomlq not found (pkgs.yq); $CONFIG left untouched"; exit 0; }

mkdir -p "$(dirname "$CONFIG")"
if [ ! -e "$CONFIG" ]; then
  TMP="$(mktemp "$CONFIG.merge.XXXXXX" 2>/dev/null || printf '')"
  [ -n "$TMP" ] || { warn "could not create a temp file next to $CONFIG"; exit 0; }
  for i in "${!KEYS[@]}"; do printf '%s = "%s"\n' "${KEYS[$i]}" "${VALS[$i]}" >>"$TMP"; done
  printf '\n%s\n' "$PROFILE_BLOCK" >>"$TMP"
  tomlq -e . "$TMP" >/dev/null 2>&1 || { warn "generated config would not parse"; exit 0; }
  mv "$TMP" "$CONFIG"; TMP=""; note "created $CONFIG"; exit 0
fi
tomlq -e . "$CONFIG" >/dev/null 2>&1 || { warn "$CONFIG does not parse as TOML; refusing to edit it"; exit 0; }

# Ambiguity fails closed: duplicate owned root keys or any alternate/dotted
# permissions table may contain user-owned data that cannot safely be removed.
for key in sandbox_mode default_permissions approval_policy; do
  count="$(awk -v k="$key" 'BEGIN{p=1;n=0} /^[[:space:]]*\[/{p=0} p && $0 ~ "^[ \\t]*(\\\"" k "\\\"|\\047" k "\\047|" k ")[ \\t]*="{n++} END{print n}' "$CONFIG")"
  [ "$count" -le 1 ] || { warn "ambiguous duplicate root $key; $CONFIG left untouched"; exit 0; }
  # shellcheck disable=SC2016 # jq program must receive literal $k.
  semantic="$(tomlq -r --arg k "$key" 'has($k)' "$CONFIG" 2>/dev/null || printf '')"
  if [ "$semantic" = "true" ] && [ "$count" -ne 1 ]; then
    warn "semantic root $key has no unique safe textual form; $CONFIG left untouched"
    exit 0
  fi
done
exact_count="$(grep -Ec '^[[:space:]]*\[permissions\.git-workspace\][[:space:]]*$' "$CONFIG" || true)"
permission_headers="$(awk '
  /^[[:space:]]*\[/ {
    h=$0
    gsub(/[[:space:]]/, "", h)
    if (h ~ /^\[(permissions|"permissions"|\047permissions\047)\.(git-workspace|"git-workspace"|\047git-workspace\047)(\.|\])/) n++
  }
  END { print n+0 }
' "$CONFIG")"
[ "$exact_count" -le 1 ] || { warn "multiple permissions.git-workspace blocks; $CONFIG left untouched"; exit 0; }
[ "$permission_headers" -eq "$exact_count" ] || { warn "ambiguous permissions table spelling; $CONFIG left untouched"; exit 0; }
semantic_profile="$(tomlq -r '(.permissions // {}) | has("git-workspace")' "$CONFIG" 2>/dev/null || printf '')"
if [ "$semantic_profile" = "true" ] && [ "$permission_headers" -eq 0 ]; then
  warn "semantic permissions.git-workspace has no safe textual form; $CONFIG left untouched"
  exit 0
fi
if [ "$semantic_profile" = "true" ]; then
  # shellcheck disable=SC2016 # jq program owns $p expansion.
  semantic_shape="$(tomlq -r '
    .permissions."git-workspace" as $p |
    ($p | type) == "object" and
    (($p | keys | sort) == (["extends", "filesystem"] | sort)) and
    (($p.filesystem | type) == "object") and
    (($p.filesystem | keys) == [":workspace_roots"]) and
    (($p.filesystem.":workspace_roots" | type) == "object") and
    (($p.filesystem.":workspace_roots" | keys | sort) == ([".git", ".git/hooks"] | sort))
  ' "$CONFIG" 2>/dev/null || printf '')"
  [ "$semantic_shape" = "true" ] || {
    warn "permissions.git-workspace has extra or malformed semantic structure; $CONFIG left untouched"
    exit 0
  }
fi

# Exact steady state: leave every byte alone, including blank-line choices.
if [ "$exact_count" -eq 1 ] \
  && [ "$(tomlq -r '.default_permissions // ""' "$CONFIG")" = "git-workspace" ] \
  && [ "$(tomlq -r '.approval_policy // ""' "$CONFIG")" = "never" ] \
  && [ "$(tomlq -r '.sandbox_mode // ""' "$CONFIG")" = "" ]; then
  current_block="$(awk '
    /^[[:space:]]*\[permissions\.git-workspace\][[:space:]]*$/ { in_block=1 }
    in_block && seen && /^[[:space:]]*\[/ { exit }
    in_block { print; seen=1 }
  ' "$CONFIG")"
  [ "$current_block" != "$CANONICAL" ] || exit 0
fi

TMP="$(mktemp "$CONFIG.merge.XXXXXX" 2>/dev/null || printf '')"
[ -n "$TMP" ] || { warn "could not create a temp file next to $CONFIG"; exit 0; }
cp -p "$CONFIG" "$TMP"
STAGE="$TMP.stage"
awk '
  BEGIN { pre=1; skip=0 }
  /^[[:space:]]*\[/ {
    pre=0
    if ($0 ~ /^[[:space:]]*\[permissions\.git-workspace\][[:space:]]*$/) { skip=1; next }
    skip=0
  }
  skip { next }
  pre && $0 ~ /^[[:space:]]*("sandbox_mode"|\047sandbox_mode\047|sandbox_mode)[[:space:]]*=/ { next }
  pre && $0 ~ /^[[:space:]]*("default_permissions"|\047default_permissions\047|default_permissions)[[:space:]]*=/ { next }
  pre && $0 ~ /^[[:space:]]*("approval_policy"|\047approval_policy\047|approval_policy)[[:space:]]*=/ { next }
  { print }
' "$TMP" >"$STAGE"
{
  for i in "${!KEYS[@]}"; do printf '%s = "%s"\n' "${KEYS[$i]}" "${VALS[$i]}"; done
  cat "$STAGE"
  printf '%s\n' "$PROFILE_BLOCK"
} >"$TMP"
rm -f "$STAGE"
STAGE=""

tomlq -e . "$TMP" >/dev/null 2>&1 || { warn "edited file would not parse; $CONFIG left untouched"; exit 0; }
ORIG_TRUST="$(tomlq -r '(.hooks.state // {}) | keys | length' "$CONFIG" 2>/dev/null || printf '')"
NEW_TRUST="$(tomlq -r '(.hooks.state // {}) | keys | length' "$TMP" 2>/dev/null || printf '')"
[ -n "$ORIG_TRUST" ] && [ "$NEW_TRUST" = "$ORIG_TRUST" ] || { warn "trust entries would change; $CONFIG left untouched"; exit 0; }
cmp -s "$CONFIG" "$TMP" && exit 0
cp -p "$CONFIG" "$CONFIG.backup" || { warn "could not write $CONFIG.backup; left untouched"; exit 0; }
mv "$TMP" "$CONFIG"; TMP=""
note "reconciled default_permissions, approval_policy, and permissions.git-workspace"
exit 0
