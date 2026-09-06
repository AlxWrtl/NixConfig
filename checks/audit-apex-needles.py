#!/usr/bin/env python3
"""Audit the SHAPE of every needle in checks/apex-consistency.nix.

WHAT THIS REPLACED, AND WHY
---------------------------
This started as a mutation harness: delete what each invariant guards, rebuild,
require red. Two modes were built and both turned out to measure nothing,
because the check is a substring test —

    missingInvariants = filter (i: !(hasInfix i.needle scope)) invariants

  - deleting the needle makes it red ALWAYS, so every invariant scores ALIVE
    and the run is a tautology (measured: 33/33, meaningless);
  - keeping the needle and deleting the prose under it means the invariant
    can NEVER fire, so nothing can score ALIVE either (measured: 0/33, equally
    meaningless — the reds all came from neighbouring needles caught in the
    same cut).

The structural conclusion: a substring test cannot verify that a RULE survived.
It can only verify its own needle. No mutation harness gets around that, and
the check is already self-verifying for presence — a vanished needle turns
`nix flake check` red on its own.

What DOES distinguish a real guard from a decorative one is decidable without
building anything: is the needle the rule, or a signpost pointing at it?

    "Max 3 correction rounds"  -> deleting the rule deletes the needle -> red
    "Scope ladder"             -> deleting the rungs leaves the heading -> green

The second shape is not hypothetical. On 2026-09-05 the scope-ladder invariant
stayed green after all five rungs were deleted, because its needle was the
heading. It had looked healthy for weeks. The fix was to add a needle quoting a
rung ("Does this codebase already do it?") beside the one quoting the title.

VERDICTS
--------
  SENTENCE   >=3 words and not sitting on a heading line   -> sound by construction
  SHORT      1-2 words                                     -> may match incidentally
  HEADING    the needle's line is a markdown heading        -> ladder-shaped, inspect

HEADING and SHORT are prompts to look, not failures. A needle can sit on a
heading and still be sound when the heading IS the rule statement, and a
section can be covered in depth by sibling invariants that quote its body.
Judgement belongs to the reader; this only says where to look.

USAGE
-----
  python3 checks/audit-apex-needles.py
  python3 checks/audit-apex-needles.py --strict   # exit 1 if any HEADING

Not wired into `nix flake check`: the verdicts need a human, and a heuristic
that blocks a merge would just get worked around.
"""

import argparse
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CHECK = REPO / "checks" / "apex-consistency.nix"
SOURCES = [
    REPO / "home" / "claude-code" / "skills.nix",
    REPO / "home" / "claude-code" / "hooks.nix",
]


def unescape_nix(s):
    return (
        s.replace('\\"', '"')
        .replace("\\n", "\n")
        .replace("\\t", "\t")
        .replace("\\\\", "\\")
    )


def parse_invariants(text):
    block = re.search(r"\n  invariants = \[\n(.*?)\n  \];\n", text, re.S)
    if not block:
        sys.exit("apex-consistency.nix: could not locate the `invariants` list")
    return [
        (unescape_nix(m.group(1)), unescape_nix(m.group(2)))
        for m in re.finditer(
            r'name\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*\n\s*needle\s*=\s*"((?:[^"\\]|\\.)*)"\s*;',
            block.group(1),
        )
    ]


def classify(needle, lines):
    """HEADING beats SHORT beats SENTENCE — report the strongest warning."""
    for line in lines:
        if needle in line and line.strip().startswith("#"):
            return "HEADING"
    return "SHORT" if len(needle.split()) <= 2 else "SENTENCE"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 when any needle is HEADING-shaped")
    args = ap.parse_args()

    lines = []
    for p in SOURCES:
        lines += p.read_text().split("\n")

    invariants = parse_invariants(CHECK.read_text())
    if not invariants:
        sys.exit("parsed zero invariants — the declaration format changed and "
                 "this audit is now checking nothing")

    buckets = {"HEADING": [], "SHORT": [], "SENTENCE": []}
    for name, needle in invariants:
        buckets[classify(needle, lines)].append((name, needle))

    for kind, blurb in (
        ("HEADING", "the needle's line is a heading — deleting the rule under it "
                    "leaves the needle, and the check stays green"),
        ("SHORT", "one or two words — may match somewhere unrelated, and carries "
                  "little of the rule"),
        ("SENTENCE", "quotes an operative sentence — deleting the rule deletes "
                     "the needle"),
    ):
        rows = buckets[kind]
        print(f"\n=== {kind}  ({len(rows)}/{len(invariants)}) — {blurb}")
        for name, needle in rows:
            print(f"  {needle!r}")
            print(f"      {name}")

    n_head, n_short = len(buckets["HEADING"]), len(buckets["SHORT"])
    print("\n" + "=" * 72)
    print(f"  SENTENCE {len(buckets['SENTENCE'])}   SHORT {n_short}   HEADING {n_head}")
    if n_head or n_short:
        print("  Look at the flagged ones: does the needle carry the rule, or "
              "point at it?")
        print("  A section can also be sound because sibling invariants quote "
              "its body.")
    print("=" * 72)
    return 1 if (args.strict and n_head) else 0


if __name__ == "__main__":
    sys.exit(main())
