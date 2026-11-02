# jev-locate — points at the block of a fetched doc page that answers a
# question, packaged as a real binary on PATH.
#
# Why: reading a whole scraped page (20-200 KB) to answer one factual
# question burns context. TypeSafe Jev, asked which ~2.5 KB block answers it,
# picked the right block 18/18 times on a bench of real doc pages; the CLI
# prints that block and the one before it, or `JEV FULL` when Jev is unsure
# (the caller then reads the whole file), with the `lines A-B` span to Read.
# Any UTF-8 text file (page, code, log, note; user decision 2026-11-02), never
# a secret or a .env: the content is sent to api.typesafe.ai.
#
# The key is read by the script from ~/.config/secrets/typesafe-api-key and
# sent only in the Authorization header: never in argv, stdout or stderr
# (HTTP error bodies are redacted, redirects refused since urllib would carry
# the header to any host). Stdlib only, no PATH dependency.
#
# writePython3Bin runs flake8 at build time (only E501 ignored), so a
# regression in the script fails the rebuild; checks/jev-locate.nix runs the
# built binary's offline `--self-test` plus two canary mutants.
{ pkgs }:
{
  jevLocatePkg = pkgs.writers.writePython3Bin "jev-locate" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/jev-locate.py);
}
