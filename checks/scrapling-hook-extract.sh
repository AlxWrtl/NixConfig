#!/usr/bin/env bash
# Extract the EVALUATED hookScraplingAiTargeted string from hooks.nix via nix
# itself, so the tested artefact is what nix will actually write to disk —
# not a hand-dedented copy of the source.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT="${1:?usage: scrapling-hook-extract.sh <outfile>}"

nix-instantiate --eval --strict --json -E "
  (import $REPO/home/claude-code/hooks.nix {
     graphifyReindexPkg = { outPath = \"/nix-store-stub-graphify\"; };
   }).hookScraplingAiTargeted
" | jq -r . > "$OUT"

chmod +x "$OUT"
echo "extracted $(wc -l < "$OUT") lines -> $OUT"
