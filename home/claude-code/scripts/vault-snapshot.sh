# vault-snapshot — encrypted, off-machine snapshot of the Obsidian vault.
#
# Chain: git bundle --all  ->  age  ->  gh release asset.
#
# Deliberately NOT a git remote. `git remote` inside the vault must stay empty:
# block-main-bash (hooks.nix) enforces the main/master ban only on repos that
# HAVE a remote, and that exemption is why commits to the vault work at all.
# An encrypted carrier also cannot offer the PR route the guard's message
# points at. `bundle` is absent from the guard's RULES table, so this whole
# chain sits outside its jurisdiction by construction rather than by exception.
#
# Carrier design: one release per snapshot, the KEEP most recent kept, older
# ones removed with --cleanup-tag. The carrier repo's git object store never
# grows — its default branch holds exactly one commit forever and release
# assets live outside the object store. A snapshot committed as a file would
# instead add ~3 MB of undeltifiable ciphertext per run, permanently, with no
# way to purge it short of rewriting history and calling GitHub support.

VAULT="/Users/alx/Vaults/AlxVault"
REPO="AlxWrtl/attic"
TARGET="master"
KEY_PUB="$HOME/.config/age/alxvault-backup.pub"
KEEP=3
LOG="$HOME/GraphVault/vault-snapshot.log"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG"; }

# The key must never live inside the vault: it would sit inside the very thing
# it protects, and inside the git repo that gets bundled.
case "$KEY_PUB" in
  "$VAULT"/*) log "FATAL key sits inside the vault: $KEY_PUB"; exit 1 ;;
esac
[ -f "$KEY_PUB" ] || { log "FATAL age recipient missing: $KEY_PUB"; exit 1; }
[ -d "$VAULT/.git" ] || { log "FATAL not a git repo: $VAULT"; exit 1; }
command -v gh >/dev/null 2>&1 || { log "FATAL gh not on PATH"; exit 1; }

# A dirty tree is REPORTED, never a reason to skip. A bundle carries committed
# history only, so refusing here would mean no backup at all on most session
# ends — strictly worse than an incomplete backup that names what it omits.
DIRTY=$(git -C "$VAULT" status --porcelain 2>/dev/null || true)
if [ -n "$DIRTY" ]; then
  log "WARN these uncommitted files are NOT in this snapshot:"
  printf '%s\n' "$DIRTY" >>"$LOG"
fi

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

git -C "$VAULT" bundle create "$W/snapshot.bundle" --all >/dev/null 2>&1 || {
  log "FATAL bundle create failed"; exit 1; }
git -C "$VAULT" bundle verify "$W/snapshot.bundle" >/dev/null 2>&1 || {
  log "FATAL bundle verify failed — refusing to upload a bundle git cannot read"; exit 1; }

age -R "$KEY_PUB" -o "$W/snapshot.age" "$W/snapshot.bundle" || {
  log "FATAL age encryption failed"; exit 1; }
rm -f "$W/snapshot.bundle"   # the plaintext never outlives the encryption

LOCAL_SHA=$(sha256sum "$W/snapshot.age" | cut -d' ' -f1)
[ -n "$LOCAL_SHA" ] || { log "FATAL empty local checksum"; exit 1; }

TAG="snapshot-$(date -u +%Y%m%dT%H%M%SZ)"
gh release create "$TAG" --repo "$REPO" --target "$TARGET" \
   --title "$TAG" --notes "" "$W/snapshot.age#snapshot.age" >>"$LOG" 2>&1 || {
  log "FATAL gh release create failed for $TAG"; exit 1; }

# Proof, not exit 0. Download it back and compare. This project's notes carry
# three separate entries saying parse OK / build OK / exit 0 proved nothing.
mkdir -p "$W/back"
gh release download "$TAG" --repo "$REPO" --pattern snapshot.age --dir "$W/back" >>"$LOG" 2>&1 || {
  log "FATAL could not download back $TAG — snapshot unverified, no rotation"; exit 1; }
REMOTE_SHA=$(sha256sum "$W/back/snapshot.age" | cut -d' ' -f1)

# BOTH must be non-empty. Comparing two empty strings succeeds, and that exact
# bug once reported a verified snapshot when nothing had been uploaded at all.
if [ -z "$REMOTE_SHA" ] || [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
  log "FATAL round-trip mismatch local=$LOCAL_SHA remote=$REMOTE_SHA — no rotation"
  exit 1
fi

# Rotate only AFTER the round trip is proven, never before. And never
# `gh release upload --clobber`: it deletes the existing asset before uploading
# the replacement (cli/cli#8822), so an interruption loses both copies.
#
# Sort on tagName, NOT on createdAt. A release's createdAt is the date of the
# COMMIT it targets, and this carrier holds exactly one commit for ever, so
# every release reports the SAME createdAt. Sorting on that constant yields
# jq's stable order — gh's own newest-first listing — which `reverse` then
# inverts, so `.[KEEP:]` picked the NEWEST release and deleted the snapshot
# just uploaded. Measured 2026-09-09: four releases, all
# createdAt=2026-09-09T08:59:57Z, and the run rotated out the tag it had
# created seconds earlier. In steady state the backup would have stayed frozen
# on its first three generations for ever, without ever raising an error.
# tagName is an ISO-8601 UTC stamp by construction, so lexicographic order is
# chronological order and depends on nothing GitHub decides.
gh release list --repo "$REPO" --limit 100 --json tagName \
   --jq "sort_by(.tagName) | reverse | .[${KEEP}:] | .[].tagName" 2>/dev/null \
| while read -r old; do
    [ -n "$old" ] || continue
    # Belt and braces: whatever any future ordering does, never delete the
    # generation this run just proved.
    if [ "$old" = "$TAG" ]; then
      log "REFUSED to rotate out the tag just created: $TAG"
      continue
    fi
    gh release delete "$old" --repo "$REPO" --cleanup-tag --yes >>"$LOG" 2>&1 || true
    log "rotated out $old"
  done

log "OK $TAG sha=$LOCAL_SHA"
