#!/usr/bin/env python3
"""APEX run metrics read from the on-disk runs, to compare before/after a
harness change.

    B1  correction rounds: runs, runs with a correction round, rate, and the
        correction lines (`- … →` / `C1 … ->`) they hold
    B2  acceptance criteria in */02-acs.md: proven by a command vs prose only,
        and the class of each one (below)
    B3  tokens by phase from the `## Tokens` table of */00-context.md
        (n and median per phase)
    B4  memory index health: MEMORY.md lines/bytes, notes missing from the
        index, index links to missing notes, dangling [[wikilinks]]
    B5  did a step change the run's outcome: per step, runs where it ran,
        recorded a result, changed something, are unknown (ran, recorded
        nothing), and the changed/recorded rate (below)

The metrics stay a manual probe (the run dirs are git-ignored), while
--self-test and --hook are run by checks/hook-wiring.nix:

    python3 -I checks/apex-metrics-probe.py [--runs DIR] [--memory DIR]
    python3 -I checks/apex-metrics-probe.py --self-test
    python3 -I checks/apex-metrics-probe.py --acs FILE
    python3 -I checks/apex-metrics-probe.py --hook < event.json

Output: one key=value line per metric, sorted. A missing directory or index
exits 2 with a message on stderr.

--acs FILE prints the class of each AC of one 02-acs.md, then the counts;
exit 1 when one is unproven, 2 when the file is missing.

--hook is the same file deployed as the PostToolUse hook on Write|Edit
(~/.claude/hooks/apex-metrics-probe.py): it reads the event on stdin and,
when the written file is an APEX run's 02-acs.md, lists its unproven ACs,
count first and capped, as context for the model. A symlink, a non-regular
file or one over HOOK_MAX_BYTES is not read: DEFERRED backtracks
quadratically on a line of unclosed brackets, 0.8 s at 64 KiB. One classifier for the
plan-time gate and the B2 metric. A Write or Edit of a run's 04-validate.md
instead names the passes that ran and left no tally (B5 below: e, x), same
guards. Anything else, an error included, exits 0 with nothing on stdout.

B5 STEPS, per run dir. A run that ran a step and recorded nothing is
unknown, never a yes or a no.
  - e (external pass): ran = the newest `*external-verify*.json` (mtime) is
    not BLOCKED (`verdict` or `status`); recorded = a tally in
    04-external-triage.md; changed = its confirmed count > 0;
  - x (examine): ran = 05-examine.md; recorded = a tally in it; changed =
    its confirmed count > 0;
  - o (vault): ran = an 01b-obsidian*.md; recorded = it cites a [[target]];
    changed = one of those targets is cited by 02-plan.md or 02-acs.md too.
    A target is compared by its last `/` segment, lowercased, without
    `.md`, `|alias` or `#anchor`; `[[ -v X ]]` (a space first) is no link;
  - analyze: ran = an 01-analyze*.md; recorded = 00-context.md and
    02-plan.md both have a `Files:` line; changed = a repo path (a token
    with a `/` and an extension) named by 01-analyze and by the plan's
    `Files:` line but not by the one of 00-context.md: analyze found a file
    not known before it. That baseline holds only because step-00 says the
    00-context line is the pre-analyze guess and is never rewritten; a run
    that rewrites it anyway reads not changed. A text rule, residual risk
    accepted.
A tally is a line holding `confirmed=N` and `dismissed=D`; the last one of
the file counts. A triage or examine file the guards refuse (symlink, not
a regular file, over the cap in --hook) is unreadable: unknown in the
metrics, never named by the hook.

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

B2 CLASSES. Each block gets one of five classes, first match wins:
  - deferred: a bracket holding `deferred to user` (`[deferred to user]`,
    `[démarrage deferred to user R-e]`), even when it names a command;
  - lecture: `[lecture]` then a dash or a colon and a reason;
  - docs: the block starts with `AC-docs`;
  - command: the rule above;
  - unproven: everything else, a subset of the prose blocks.

--self-test grades that classifier on real AC text copied from run dirs,
then runs the v0 rule on the same table: if v0 mislabels nothing, the
fixtures cannot fail and the self-test exits 1. The class table is graded
the same way against the unmarked rule (command or unproven only). B5 is
graded on real tally text (changed, not changed, unknown) and on small vault
and analyze cases; the table must hold all three outcomes.
"""
import argparse
import json
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
LECTURE = re.compile(r"\[lecture\]\s*[—–:-]\s*\S")
DEFERRED = re.compile(r"\[[^\[\]\n]*\bdeferred to user\b[^\]\n]*\]")
AC_DOCS = re.compile(r"^\s*(?:[-*]\s+)?\**AC-docs\b")
ACS_PATH = re.compile(r"/\.claude/output/apex/[^/]+/02-acs\.md$")
VALIDATE_PATH = re.compile(r"/\.claude/output/apex/[^/]+/04-validate\.md$")
TALLY = re.compile(r"\bconfirmed=(\d+)")
TALLY_PAIR = re.compile(r"\bdismissed=\d+")
WIKILINK = re.compile(r"\[\[([^\]\s|#][^\]\n]*)")
FILES_LINE = re.compile(r"^Files:(.*)$", re.MULTILINE)
PATH_TOKEN = re.compile(r"(?<![\w.~/-])[\w.~-]*(?:/[\w.-]+)+")  # starts at a token edge: linear
B5_STEPS = ("analyze", "e", "o", "x")
CLASSES = ("command", "deferred", "docs", "lecture", "unproven")
HOOK_CAP = 10
HOOK_MAX_BYTES = 64 * 1024
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


def classify(block):
    text = block.text()
    if DEFERRED.search(text):
        return "deferred"
    if LECTURE.search(text):
        return "lecture"
    if AC_DOCS.match(block.prose[0]):
        return "docs"
    return "command" if has_command(block) else "unproven"


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

# Real AC blocks, verbatim from .claude/output/apex/<run>/02-acs.md.
# (run dir, AC, expected class, text)
CLASS_FIXTURES = [
    ("25-goat-worker-launchagent", "AC8", "deferred", (
        "- AC8 [deferred to user] — Témoin avant bootstrap (après Ctrl-C, ≥25 s) : "
        "PING20 = 0 ligne ; `launchctl print S` rc ≠ 0.")),
    ("27-goat-agent-sandbox", "AC20", "deferred", (
        "- AC20 [deferred to user] Combinaisons de rôles non exercées par R1/R2 "
        "(routage par quota) : listées dans 04-validate.")),
    ("24-goat-windmill-poc", "AC15", "deferred", (
        "AC15 — Routage positif : même job, après démarrage du worker "
        "[démarrage deferred to user R-e] → terminé, sortie contient `Darwin` "
        "et les chemins de claude et codex.")),
    ("53-apex-leftovers", "AC-docs", "docs",
     "- AC-docs: n/a (text)."),
    ("54-nix-audit-fixes", "AC-docs", "docs",
     "- AC-docs: nixfmt@1.5.0 — `nixfmt --check <files>` (rung 5)."),
    ("76-apex-ac-proof", "AC13", "lecture", (
        "AC13 [lecture] — the new AC rule reads as one rule in step-02, step-04 and "
        "the verify loop, its two exceptions named alike in all three; "
        "apex-consistency proves the sentences exist, not that a planner reads "
        "them unambiguously.")),
    ("27-goat-agent-sandbox", "AC3", "unproven", (
        "- AC3 Chaque exception L4/W6 du profil figure dans "
        "`scratchpad/apex27/03-exceptions.md` avec la commande D1/D2 qui l'exige "
        "(relecture coordinateur, 1:1).")),
    ("65-git-prefix-redos", "AC6", "unproven",
     "AC6 Header comment explains the linear-time construction in one or two sentences."),
    ("53-apex-leftovers", "AC3", "command",
     "- AC3: nix flake check green; diff limited to the 2 files."),
]

# Real tally text, verbatim from .claude/output/apex/<run>/<file>.
# (run dir, file, expected outcome, text)
B5_TALLY_FIXTURES = [
    ("76-apex-ac-proof", "05-examine.md", "changed", (
        "F3 | commit sweeping staged preprod files | noted | procedural; commit names "
        "the 8 paths (AC17)\n"
        "confirmed=4 unique=4 dismissed=3\n")),
    ("67-apex-token-diet", "04-external-triage.md", "not changed", (
        "# External triage — 67-apex-token-diet\n"
        "Verdict: PASS (gpt-6-astra), 0 findings.\n"
        "\n"
        "confirmed=0 unique=0 dismissed=0\n")),
    # CONFIRMED / DISMISSED in prose, no tally line: ran, recorded nothing.
    ("01-worktree-env-sync", "05-examine.md", "unknown", (
        "PHASE: examine (opus Plan, read-only) + external (codex gpt-5.6-terra, FAIL 1 finding)\n"
        "\n"
        "External:\n"
        "- [important] worktree-env-sync.sh:39 main root derived only when common dir ends "
        "/.git (--separate-git-dir skipped) — CONFIRMED by reading lines 39-42; DISMISSED as "
        "accepted limitation: fails safe (no copy), plan chose session-start.sh:20-23 approach.\n")),
    # Not tallies: a confirmed count with no dismissed= on its line, and a
    # file whose last tally (0) follows an earlier one (2).
    ("no pair", "05-examine.md", "unknown", "confirmed=3 unique=3\n"),
    ("last wins", "05-examine.md", "not changed", (
        "confirmed=2 unique=2 dismissed=0\n"
        "C1 C2 fixed, re-examined\n"
        "confirmed=0 unique=0 dismissed=2\n")),
]

# (case, expected outcome, 01b-obsidian text, 02-plan + 02-acs text)
B5_VAULT_FIXTURES = [
    ("plan cites the note", "changed",
     "- [[A]] — prior decision on the same hook\n", "Context: [[A]] settles the timeout.\n"),
    ("plan cites nothing", "not changed",
     "- [[A]] — prior decision on the same hook\n", "Files: checks/x.nix\n"),
    # Real lines: 67-apex-token-diet/01b-obsidian.md:13 (prefix), 02-plan.md:45.
    ("vault path against basename", "changed", (
        "- [[02-Projets/nix-darwin/sessions/2026-08-14 - refonte-verification-apex]] / "
        "[[02-Projets/nix-darwin/sessions/2026-08-11 - enforcement-apex-et-nettoyage]] — "
        "fix-loop bounds (2 correction rounds)\n"), (
        "T12 Session note (-n): supersedes [[2026-08-14 - refonte-verification-apex]] and "
        "[[2026-09-09 - verificateur-externe-codex-dans-apex]]; keep threshold ≥1 unique "
        "confirmed / 10 runs over ~4 weeks, read from 04-external-triage.md.\n")),
    ("alias, anchor, case, .md", "changed",
     "- [[A.md]] — prior decision\n", "See [[a#Decision|the decision]].\n"),
    ("no link cited", "unknown",
     "Vault: no note on this task.\n", "Context: [[A]] settles the timeout.\n"),
    ("shell test is no link", "unknown",
     "if [[ -v DRY_RUN ]]; then exit 0; fi\n", "[[ -v DRY_RUN ]]\n"),
]

# (case, expected outcome, 01-analyze text, 02-plan text, 00-context text)
B5_ANALYZE_FIXTURES = [
    ("new path", "changed",
     "The wiring lives in checks/hook-wiring.nix:108.\n",
     "Files: checks/hook-wiring.nix, README.md\n", "Files: README.md\n"),
    ("known path", "not changed",
     "The wiring lives in checks/hook-wiring.nix:108.\n",
     "Files: checks/hook-wiring.nix, README.md\n", "Files: checks/hook-wiring.nix\n"),
    ("path only in plan prose", "not changed",
     "The wiring lives in checks/hook-wiring.nix:108.\n",
     "Files: README.md\nT1 read checks/hook-wiring.nix first.\n", "Files: README.md\n"),
    ("plan has no Files: line", "unknown",
     "The wiring lives in checks/hook-wiring.nix:108.\n",
     "## Files\n- checks/hook-wiring.nix\n", "Files: README.md\n"),
    ("context has no Files: line", "unknown",
     "The wiring lives in checks/hook-wiring.nix:108.\n",
     "Files: checks/hook-wiring.nix\n", "Tier: standard\n"),
]


def tally(text):
    """The confirmed count of the file's last tally line, None when it has none."""
    found = None
    for line in text.splitlines():
        m = TALLY.search(line)
        if m and TALLY_PAIR.search(line):
            found = int(m.group(1))
    return found


def tally_outcome(text):
    n = tally(text)
    if n is None:
        return "unknown"
    return "changed" if n > 0 else "not changed"


def wikilink_target(raw):
    """`[[dir/Note.md#h|alias]]` and `[[note]]` name the same note: `note`."""
    t = re.split(r"[|#]", raw, maxsplit=1)[0].strip().rsplit("/", 1)[-1].strip().lower()
    return t[:-3] if t.endswith(".md") else t


def wikilinks(text):
    return {wikilink_target(t) for t in WIKILINK.findall(text)} - {""}


def vault_outcome(obsidian, plan):
    cited = wikilinks(obsidian)
    if not cited:
        return "unknown"
    return "changed" if cited & wikilinks(plan) else "not changed"


def repo_paths(text):
    """Tokens with a `/` whose last segment has an extension (`checks/x.nix`)."""
    out = set()
    for tok in PATH_TOKEN.findall(text):
        tok = tok.rstrip(".")
        if tok.startswith("./"):
            tok = tok[2:]
        if re.search(r"[^./]\.[A-Za-z0-9]+$", tok):
            out.add(tok)
    return out


def files_line(text):
    m = FILES_LINE.search(text)
    return m.group(1) if m else None


def analyze_outcome(analyze, plan, context):
    planned, guessed = files_line(plan), files_line(context)
    if planned is None or guessed is None:
        return "unknown"
    found = (repo_paths(analyze) & repo_paths(planned)) - repo_paths(guessed)
    return "changed" if found else "not changed"


def _guarded_text(p, cap):
    """A regular non-symlink file within cap bytes, else None (no tally)."""
    if p.is_symlink() or not p.is_file():
        return None
    if cap is not None and p.stat().st_size > cap:
        return None
    return _read(p)


def external_ran(run, cap):
    """The newest verify json carries a verdict that is not BLOCKED; one that
    does not parse is no verdict, so the pass did not run."""
    verifies = [p for p in run.glob("*external-verify*.json") if not p.is_symlink() and p.is_file()]
    if not verifies:
        return False
    text = _guarded_text(max(verifies, key=lambda p: (p.stat().st_mtime, p.name)), cap)
    try:
        data = json.loads(text) if text is not None else None
    except ValueError:
        return False
    return isinstance(data, dict) and "BLOCKED" not in (data.get("verdict"), data.get("status"))


def _tally_step(p, cap):
    """Outcome of one tally file: absent = no tally (unknown); present but
    refused by the guards = unreadable, which the hook never names."""
    if not p.exists() and not p.is_symlink():
        return "unknown"
    text = _guarded_text(p, cap)
    return "unreadable" if text is None else tally_outcome(text)


def b5_tallied(run, cap=None):
    """Outcome of the two passes that record a tally: e and x."""
    examine = run / "05-examine.md"
    e = _tally_step(run / "04-external-triage.md", cap) if external_ran(run, cap) else "not run"
    x = _tally_step(examine, cap) if examine.exists() or examine.is_symlink() else "not run"
    return {"e": e, "x": x}


def b5_run(run):
    """{step: not run | unknown | unreadable | changed | not changed} for one run dir."""
    out = b5_tallied(run)
    def text(name):
        return _guarded_text(run / name, None) or ""
    obs = sorted(run.glob("01b-obsidian*.md"))
    if obs:
        cited = "\n".join(_read(p) for p in obs)
        out["o"] = vault_outcome(cited, text("02-plan.md") + "\n" + text("02-acs.md"))
    else:
        out["o"] = "not run"
    an = sorted(run.glob("01-analyze*.md"))
    if an:
        found = "\n".join(_read(p) for p in an)
        out["analyze"] = analyze_outcome(found, text("02-plan.md"), text("00-context.md"))
    else:
        out["analyze"] = "not run"
    return out


def b5_self_test(failures):
    outcomes = {"changed", "not changed", "unknown"}
    for run, name, expected, text in B5_TALLY_FIXTURES:
        got = tally_outcome(text)
        if got != expected:
            failures.append(f"B5 {run} {name}: {got}, expected {expected}")
    for case, expected, obsidian, plan in B5_VAULT_FIXTURES:
        got = vault_outcome(obsidian, plan)
        if got != expected:
            failures.append(f"B5 o {case}: {got}, expected {expected}")
    for case, expected, analyze, plan, context in B5_ANALYZE_FIXTURES:
        got = analyze_outcome(analyze, plan, context)
        if got != expected:
            failures.append(f"B5 analyze {case}: {got}, expected {expected}")
    for label, table in (("tally", B5_TALLY_FIXTURES), ("o", B5_VAULT_FIXTURES),
                         ("analyze", B5_ANALYZE_FIXTURES)):
        idx = 2 if label == "tally" else 1
        missing = outcomes - {f[idx] for f in table}
        if missing:
            failures.append(f"B5 {label} table too thin: no fixture for {', '.join(sorted(missing))}")
    return len(B5_TALLY_FIXTURES) + len(B5_VAULT_FIXTURES) + len(B5_ANALYZE_FIXTURES)


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
    unmarked_wrong = 0
    for run, ac, expected, text in CLASS_FIXTURES:
        blocks = parse_ac_blocks(text)
        if len(blocks) != 1:
            failures.append(f"{run} {ac}: parsed as {len(blocks)} blocks, expected 1")
            continue
        got = classify(blocks[0])
        if got != expected:
            failures.append(f"{run} {ac}: classed {got}, expected {expected}")
        if ("command" if has_command(blocks[0]) else "unproven") != expected:
            unmarked_wrong += 1
    missing = [c for c in CLASSES if c not in {f[2] for f in CLASS_FIXTURES}]
    if missing:
        failures.append(f"class table too thin: no fixture for {', '.join(missing)}")
    if unmarked_wrong == 0:
        failures.append("class fixtures cannot fail: the unmarked rule mislabels none of them")
    n_b5 = b5_self_test(failures)
    for f in failures:
        print(f"FAIL {f}")
    print(f"self-test fixtures={len(FIXTURES)} command={n_cmd} prose={n_prose} "
          f"v0_mislabels={v0_wrong} class_fixtures={len(CLASS_FIXTURES)} "
          f"unmarked_mislabels={unmarked_wrong} b5_fixtures={n_b5} failures={len(failures)}")
    return 1 if failures else 0


def _label(is_cmd):
    return "command" if is_cmd else "prose"


def _read(path):
    return path.read_text(encoding="utf-8", errors="replace")


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
    counts = dict.fromkeys(CLASSES, 0)
    for f in ac_files:
        for block in parse_ac_blocks(_read(f)):
            if has_command(block):
                proven += 1
            else:
                prose += 1
            counts[classify(block)] += 1
    total = proven + prose
    out["B2.ac_files"] = len(ac_files)
    out["B2.acs"] = total
    out["B2.with_command"] = proven
    out["B2.prose_only"] = prose
    out["B2.prose_rate"] = f"{prose / total:.1%}" if total else "n/a"
    for cls in ("deferred", "docs", "lecture", "unproven"):
        out[f"B2.{cls}"] = counts[cls]

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

    # B5: did a step change the outcome (see the module docstring)
    outcomes = [b5_run(r) for r in runs]
    for s in B5_STEPS:
        got = [o[s] for o in outcomes]
        ran = sum(1 for g in got if g != "not run")
        recorded = sum(1 for g in got if g in ("changed", "not changed"))
        changed = got.count("changed")
        out[f"B5.{s}.ran"] = ran
        out[f"B5.{s}.recorded"] = recorded
        out[f"B5.{s}.changed"] = changed
        out[f"B5.{s}.unknown"] = ran - recorded
        out[f"B5.{s}.rate"] = f"{changed / recorded:.1%}" if recorded else "n/a"
    return out


def acs_report(path):
    """--acs: the class of each AC of one 02-acs.md, then the counts."""
    try:
        text = _read(path)
    except OSError as e:
        print(f"apex-metrics-probe: cannot read {path}: {e.strerror or e}", file=sys.stderr)
        return 2
    blocks = parse_ac_blocks(text)
    counts = dict.fromkeys(CLASSES, 0)
    for block in blocks:
        cls = classify(block)
        counts[cls] += 1
        print(f"{cls}\t{block.prose[0].strip()[:100]}")
    print(f"acs={len(blocks)} " + " ".join(f"{c}={counts[c]}" for c in CLASSES))
    return 1 if counts["unproven"] > 0 else 0


def hook():
    data = json.loads(sys.stdin.read())
    path = data["tool_input"]["file_path"]
    if isinstance(path, str) and VALIDATE_PATH.search(path):
        return validate_hook(pathlib.Path(path))
    if not isinstance(path, str) or not ACS_PATH.search(path):
        return 0
    p = pathlib.Path(path)
    if p.is_symlink() or not p.is_file():
        return 0
    if p.stat().st_size > HOOK_MAX_BYTES:
        return 0
    flagged = [b for b in parse_ac_blocks(_read(pathlib.Path(path))) if classify(b) == "unproven"]
    if not flagged:
        return 0
    shown = " | ".join(b.prose[0].strip()[:120] for b in flagged[:HOOK_CAP])
    more = f" | +{len(flagged) - HOOK_CAP} more" if len(flagged) > HOOK_CAP else ""
    msg = (f"{len(flagged)} AC(s) in {path} name no command and carry neither "
           "`[lecture] — reason` nor `[deferred to user]`; validate reports them non prouvé: "
           f"{shown}{more}")
    print(json.dumps({"hookSpecificOutput": dict(hookEventName="PostToolUse", additionalContext=msg)}))
    return 0


def validate_hook(p):
    """--hook on a run's 04-validate.md: name the passes that ran untallied."""
    if p.is_symlink() or not p.is_file() or p.stat().st_size > HOOK_MAX_BYTES:
        return 0
    got = b5_tallied(p.parent, HOOK_MAX_BYTES)
    missing = [name for step, name in (("e", "external"), ("x", "examine")) if got[step] == "unknown"]
    if not missing:
        return 0
    msg = (f"B5: {p.parent.name} records no confirmed/dismissed tally for: {', '.join(missing)} "
           "— add `confirmed=N unique=U dismissed=D` (step-04/step-05)")
    print(json.dumps({"hookSpecificOutput": dict(hookEventName="PostToolUse", additionalContext=msg)}))
    return 0


def main():
    ap = argparse.ArgumentParser(description="APEX run metrics (B1-B5).")
    ap.add_argument("--runs", type=pathlib.Path, default=pathlib.Path(".claude/output/apex"))
    ap.add_argument(
        "--memory",
        type=pathlib.Path,
        default=pathlib.Path("~/.claude/projects/-Users-alx--config-nix-darwin/memory"),
    )
    ap.add_argument("--self-test", action="store_true",
                    help="grade the B2 classifier on real AC fixtures")
    ap.add_argument("--acs", type=pathlib.Path,
                    help="print the class of each AC of one 02-acs.md")
    ap.add_argument("--hook", action="store_true",
                    help="PostToolUse hook: read the event on stdin, list unproven ACs")
    args = ap.parse_args()
    if args.hook:
        try:
            return hook()
        except Exception:
            return 0
    if args.self_test:
        return self_test()
    if args.acs is not None:
        return acs_report(args.acs.expanduser())
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
