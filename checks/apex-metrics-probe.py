#!/usr/bin/env python3
"""APEX run metrics read from the on-disk runs, to compare before/after a
harness change.

    B1  correction rounds: runs, runs with a correction round, rate, and the
        correction lines (`- … →` / `C1 … ->`) they hold
    B2  acceptance criteria in */02-acs.md: proven by a command vs prose only
    B3  tokens by phase from the `## Tokens` table of */00-context.md
        (n and median per phase)
    B4  memory index health: MEMORY.md lines/bytes, notes missing from the
        index, index links to missing notes, dangling [[wikilinks]]

Manual probe, outside the flake (the run dirs are git-ignored):

    python3 -I checks/apex-metrics-probe.py [--runs DIR] [--memory DIR]
    python3 -I checks/apex-metrics-probe.py --self-test

Output: one key=value line per metric, sorted. A missing directory or index
exits 2 with a message on stderr.

B2 CLASSIFIER. An AC is a block: its marker line (`AC1`, `AC-2`, `**AC`,
`1.` / `1)`, `- ` / `* `) plus its continuation lines, up to a blank line, a
heading, a rule or the next marker at the same or a lower indent (a deeper
bullet is a sub-item of the AC above). A fenced code block belongs to the AC
it follows. The block has a command when:
  - a backticked span holds a run: after env assignments and `sudo`, its
    first word is a known executable or a script (`./x`, `*.sh`, `*.py`),
    and it has an argument (a bare `codex` or `home/x.nix` names a thing,
    it does not run it);
  - a fenced line starts with a known executable or a script;
  - the text names a gate, backticked or not (`nix flake check`, `nix eval`,
    `nixfmt`, `pnpm typecheck`, `shellcheck`, a `*-probe.sh` script, a
    `*-probe N/N` score …).
Everything else is prose. v0 counted any backtick as a command.

--self-test grades that classifier on real AC text copied from run dirs,
then runs the v0 rule on the same table: if v0 mislabels nothing, the
fixtures cannot fail and the self-test exits 1.
"""
import argparse
import pathlib
import re
import sys

KNOWN_EXECUTABLES = frozenset({
    "apex-board", "apex-health", "apex-tier", "awk", "bash", "brew", "cargo",
    "cat", "claude", "codex", "curl", "darwin-rebuild", "deadnix", "diff", "env",
    "find", "gh", "git", "go", "grep", "head", "jq", "launchctl", "ls", "mas",
    "nix", "nix-instantiate", "nix-store", "nixfmt", "node", "npx", "perl",
    "plutil", "pnpm", "prettier", "python3", "readlink", "rg", "sed", "sh",
    "shellcheck", "sort", "stat", "statix", "tail", "test", "trello", "tsc",
    "uniq", "uv", "uvx", "wc", "xargs", "zsh",
})
GATE = re.compile(
    r"\b(?:nix flake check|nix eval|nix build|nix-instantiate|nixfmt|shellcheck"
    r"|pnpm (?:typecheck|lint|test)|go test|cargo test)\b"
    r"|[\w./-]+-(?:probe|fuzz|bench)\.(?:sh|py)\b"
    r"|\b[\w-]+-(?:probe|fuzz|bench)(?: stays)? \d+/\d+"
)
AC_START = re.compile(r"^(\s*)(?:[-*]\s+|\d+[.)]\s+|\*\*AC|AC[-\d])")
FENCE = re.compile(r"^\s*```")
BREAK = re.compile(r"^\s*(?:#|---+\s*$)")
SPAN = re.compile(r"`([^`]+)`")
ASSIGN = re.compile(r"^\w+=\S*$")


class Block:
    def __init__(self, line, indent):
        self.prose = [line]
        self.code = []
        self.indent = indent

    def text(self):
        return "\n".join(self.prose)


def parse_ac_blocks(text):
    """Split an 02-acs.md into AC blocks (see the module docstring)."""
    blocks = []
    cur = None
    in_fence = False
    for line in text.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            if cur is not None:
                cur.code.append(line)
            continue
        if not line.strip() or BREAK.match(line):
            cur = None
            continue
        m = AC_START.match(line)
        if m and len(line.strip()) > 8:
            indent = len(m.group(1).expandtabs())
            if cur is None or indent <= cur.indent:
                cur = Block(line, indent)
                blocks.append(cur)
                continue
        if cur is not None:
            cur.prose.append(line)
    return blocks


def _is_runnable(word):
    word = word.lstrip("$(<")
    return word in KNOWN_EXECUTABLES or word.startswith("./") or word.endswith((".sh", ".py"))


def _strip_prefix(words):
    while words and (ASSIGN.match(words[0]) or words[0] == "sudo"):
        words = words[1:]
    return words


def _span_runs(span):
    words = _strip_prefix(span.split())
    return len(words) >= 2 and _is_runnable(words[0])


def _fence_line_runs(line):
    words = line.split()
    if words and re.match(r"^\w+=\$\(", words[0]):
        words = [words[0].split("=$(", 1)[1]] + words[1:]
    words = _strip_prefix(words)
    return bool(words) and _is_runnable(words[0])


def has_command(block):
    joined = " ".join(s.strip() for s in block.prose)  # a span may wrap a line
    return (
        any(_span_runs(s) for s in SPAN.findall(joined))
        or any(_fence_line_runs(c) for c in block.code)
        or GATE.search(joined) is not None
    )


def has_command_v0(block):
    """The v0 rule, kept as the self-test's mutant: any backtick = command."""
    return "`" in block.prose[0]


# Real AC blocks, verbatim from .claude/output/apex/<run>/02-acs.md.
# (run dir, AC, expected has_command, text)
FIXTURES = [
    ("53-apex-leftovers", "AC3", True,
     "- AC3: nix flake check green; diff limited to the 2 files."),
    ("65-git-prefix-redos", "AC5", True,
     "AC5 nix flake check green (js-lint included); no eslint-disable."),
    ("pin-brag-skill", "AC5", True,
     "AC5: nix flake check --no-build green"),
    ("17-doctor-cleanup", "AC1", True, (
        "AC1. At the commit where A10 exists but the trello fix does not, `nix flake check\n"
        "--no-build` exits non-zero and its output names both `A10` and `trello`. This must\n"
        "be OBSERVED and the output recorded, never assumed.")),
    ("19-skill-footer-guard", "AC11", True, (
        "AC11. `nixfmt --check` passes and `nix-instantiate --parse` is clean on every\n"
        "touched file.")),
    ("59-vault-snapshot-sandbox", "AC6", True, (
        "- AC6: The block from `DIRTY=$(git -C \"$VAULT\" status` to its closing `fi` is "
        "byte-identical to master. `bash checks/vault-autocommit-bench.sh` reports 28/28 pass.")),
    ("59-vault-snapshot-sandbox", "AC8", True, (
        "- AC8: `nix flake check` is green:\n"
        "  - hook-wiring still 25/8\n"
        "  - apex-consistency evaluates (hooks.nix takes no new argument)\n"
        "  - vault-snapshot passes writeShellApplication shellcheck")),
    ("16-codex-skills-from-source", "AC-4", True, (
        "**AC-4 — Le check de structure passe.**\n"
        "```sh\n"
        "nix build --no-link \"$FLAKE#$SYS.codex-skills\"\n"
        "```\n"
        "PASS ⟺ code de retour 0.")),
    ("28-goat-fix-loop", "AC5", True, (
        "- **AC5** — Contrainte du harnais préservée :\n"
        "  `grep -Fxc 'readonly SANDBOX_EXEC=/usr/bin/sandbox-exec' bin/agent-run.sh` → `1`.")),
    ("17-doctor-cleanup", "AC4", False, (
        "AC4. `home/codex/skills-translate.nix` contains exactly one occurrence of\n"
        "`indentedFrontmatter = [ ];` and no occurrence of `indentedFrontmatter = [ \"trello\" ];`.")),
    ("17-doctor-cleanup", "AC6", False, (
        "AC6. `home/claude-code/activation.nix` references `skillOverrides` at least twice:\n"
        "once to read it from the nix base, once in the jq assignment chain that force-writes\n"
        "it into the live file. The comment enumerating the force-overridden keys names it too.")),
    ("19-skill-footer-guard", "AC6", False, (
        "AC6. Exactly two skills are exempt, `caveman` and `cavemem`, and the exemption\n"
        "is declared in the source rather than implied by the predicate.")),
    ("59-vault-snapshot-sandbox", "AC4", False, (
        "- AC4: When the vault `.git` is writable, the probe:\n"
        "  - logs nothing\n"
        "  - leaves no `.snap-probe.*` entry\n"
        "  - lets execution continue to the `DIRTY=` block unchanged")),
    ("19-skill-footer-guard", "AC7", False,
     "AC7. No skill's content was altered to make A11 pass."),
    ("65-git-prefix-redos", "AC6", False,
     "AC6 Header comment explains the linear-time construction in one or two sentences."),
]


def self_test():
    failures = []
    v0_wrong = 0
    for run, ac, expected, text in FIXTURES:
        blocks = parse_ac_blocks(text)
        if len(blocks) != 1:
            failures.append(f"{run} {ac}: parsed as {len(blocks)} blocks, expected 1")
            continue
        got = has_command(blocks[0])
        if got != expected:
            failures.append(f"{run} {ac}: labelled {_label(got)}, expected {_label(expected)}")
        if has_command_v0(blocks[0]) != expected:
            v0_wrong += 1
    n_cmd = sum(1 for f in FIXTURES if f[2])
    n_prose = len(FIXTURES) - n_cmd
    if n_cmd < 6 or n_prose < 4:
        failures.append(f"table too thin: {n_cmd} command, {n_prose} prose (need >= 6 and >= 4)")
    if v0_wrong == 0:
        failures.append("fixtures cannot fail: the v0 rule mislabels none of them")
    for f in failures:
        print(f"FAIL {f}")
    print(f"self-test fixtures={len(FIXTURES)} command={n_cmd} prose={n_prose} "
          f"v0_mislabels={v0_wrong} failures={len(failures)}")
    return 1 if failures else 0


def _label(is_cmd):
    return "command" if is_cmd else "prose"


def _read(path):
    return path.read_text(errors="replace")


def metrics(runs_root, mem_root):
    out = {}
    runs = sorted(p for p in runs_root.iterdir() if p.is_dir())

    # B1: correction rounds per run
    corr_runs = corr_items = 0
    for r in runs:
        text = "\n".join(_read(f) for f in r.glob("*.md"))
        rounds = re.findall(r"^#+ .*CORRECTIONS|^CORRECTIONS", text, re.MULTILINE)
        has_files = any(r.glob("*correction*")) or (r / "06-resolve.md").exists()
        if rounds or has_files:
            corr_runs += 1
            corr_items += len(re.findall(r"^\s*(?:[-*]|C\d+|R\d+)\s?.*(?:→|->)", text, re.MULTILINE))
    out["B1.runs"] = len(runs)
    out["B1.with_corrections"] = corr_runs
    out["B1.rate"] = f"{corr_runs / len(runs):.1%}" if runs else "n/a"
    out["B1.correction_lines"] = corr_items

    # B2: ACs proven by a command vs prose only
    ac_files = sorted(runs_root.glob("*/02-acs.md"))
    proven = prose = 0
    for f in ac_files:
        for block in parse_ac_blocks(_read(f)):
            if has_command(block):
                proven += 1
            else:
                prose += 1
    total = proven + prose
    out["B2.ac_files"] = len(ac_files)
    out["B2.acs"] = total
    out["B2.with_command"] = proven
    out["B2.prose_only"] = prose
    out["B2.prose_rate"] = f"{prose / total:.1%}" if total else "n/a"

    # B3: tokens by phase from 00-context Tokens tables
    phase_tok = {}
    for f in sorted(runs_root.glob("*/00-context.md")):
        m = re.search(r"## Tokens(.*?)(?:\n## |\Z)", _read(f), re.DOTALL)
        if not m:
            continue
        for row in m.group(1).splitlines():
            cells = [c.strip() for c in row.strip("|").split("|")]
            if len(cells) < 4:
                continue
            num = re.sub(r"[^\d.k]", "", cells[3].lower())
            try:
                val = float(num.rstrip("k")) * (1000 if num.endswith("k") else 1)
            except ValueError:
                continue  # header or separator row, no number in the cell
            phase_tok.setdefault(cells[0], []).append(int(val))
    for ph, vals in phase_tok.items():
        key = re.sub(r"[^a-z0-9]+", "_", ph.lower()).strip("_") or "unnamed"
        out[f"B3.{key}.n"] = len(vals)
        out[f"B3.{key}.median"] = sorted(vals)[len(vals) // 2]

    # B4: memory index health
    idx = _read(mem_root / "MEMORY.md")
    files = {p.name for p in mem_root.glob("*.md")} - {"MEMORY.md"}
    linked = set(re.findall(r"\]\(([^)]+\.md)\)", idx))
    names = set()
    wikilinks = set()
    for f in files:
        body = _read(mem_root / f)
        m = re.search(r"^name:\s*(\S+)", body, re.MULTILINE)
        if m:
            names.add(m.group(1))
        wikilinks |= set(re.findall(r"\[\[([^\]|#]+)", body))
    out["B4.index_lines"] = len(idx.splitlines())
    out["B4.index_bytes"] = len(idx.encode())
    out["B4.files"] = len(files)
    out["B4.unindexed"] = len(files - linked)
    out["B4.dead_index"] = len(linked - files)
    out["B4.dangling_wikilinks"] = len(wikilinks - names)
    return out


def main():
    ap = argparse.ArgumentParser(description="APEX run metrics (B1-B4).")
    ap.add_argument("--runs", type=pathlib.Path, default=pathlib.Path(".claude/output/apex"))
    ap.add_argument(
        "--memory",
        type=pathlib.Path,
        default=pathlib.Path("~/.claude/projects/-Users-alx--config-nix-darwin/memory"),
    )
    ap.add_argument("--self-test", action="store_true",
                    help="grade the B2 classifier on real AC fixtures")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    runs_root = args.runs.expanduser()
    mem_root = args.memory.expanduser()
    for label, path in (("runs dir", runs_root), ("memory dir", mem_root)):
        if not path.is_dir():
            print(f"apex-metrics-probe: {label} not found: {path}", file=sys.stderr)
            return 2
    if not (mem_root / "MEMORY.md").is_file():
        print(f"apex-metrics-probe: no MEMORY.md in {mem_root}", file=sys.stderr)
        return 2
    for key, val in sorted(metrics(runs_root, mem_root).items()):
        print(f"{key}={val}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
