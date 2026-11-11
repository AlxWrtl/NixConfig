#!/usr/bin/env python3
"""TTW run metrics read from the on-disk runs, to compare before/after a
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
    B6  run files due at the end of a run: tiered non-Direct runs, those
        with no known tier, those with a 02-acs.md, those owing a tally and
        those holding every tally they owe (below); the same keys again
        under B6.since.* for the runs dated on or after --since
    B7  did step-01b query the knowledge graph: runs with an
        01b-obsidian*.md, each graph outcome (below), and the contributed
        rate

The metrics stay a manual probe (the run dirs are git-ignored), while
--self-test and --hook are run by checks/hook-wiring.nix:

    python3 -I checks/ttw-metrics-probe.py [--runs DIR]... [--memory DIR] [--since DATE]
    python3 -I checks/ttw-metrics-probe.py --self-test
    python3 -I checks/ttw-metrics-probe.py --acs FILE
    python3 -I checks/ttw-metrics-probe.py --hook < event.json

Output: one key=value line per metric, sorted. --runs repeats: the metrics
cover every runs dir given. A missing directory or index exits 2 with a
message on stderr.

--acs FILE prints the class of each AC of one 02-acs.md, then the counts;
exit 1 when one is unproven, 2 when the file is missing.

--hook is the same file deployed as the PostToolUse hook on Write|Edit
(~/.claude/hooks/ttw-metrics-probe.py): it reads the event on stdin and,
when the written file is a TTW run's 02-acs.md, lists its unproven ACs,
count first and capped, as context for the model. A symlink, a non-regular
file or one over HOOK_MAX_BYTES is not read: DEFERRED backtracks
quadratically on a line of unclosed brackets, 0.8 s at 64 KiB. One classifier for the
plan-time gate and the B2 metric. A Write or Edit of a run's 04-validate.md
instead names the passes that ran and left no tally (B5 below: e, x), same
guards. A Write or Edit of a run's 01b-obsidian*.md whose graph outcome
(B7 below) is not unavailable and that records no query line asks for
`mcp__graphify__query_graph` and the `- Query:` line, same guards. A Write
or Edit of a Claude memory note
(.claude/projects/<project>/memory/<note>.md) names what B4 counts against
it: each [[link]] that is no sibling's `name:` slug, with the slug when the
link is a sibling's file stem (exact stem first, then `_` and `-` read as
each other; a sibling without `name:` is said so), and the note missing
from MEMORY.md; one of MEMORY.md itself names the notes it links that are
not in the directory. B4 and that branch share their regexes, same guards
(a symlinked sibling is not read). The same body is also the PostToolUse
hook on Bash: after a successful lone `gh pr create`, it finds the branch's
run (git in the event's cwd; a `--head`/`-H` argv token names the branch
instead; a command shlex cannot split is silence) and
names the B6 files it still owes. Anything else, an error included, exits
0 with nothing on stdout.

B6 RUN FILES. A run's tier is the first word of its LAST `Tier:` line (an
escalation counts); Direct owes nothing, no or an unknown tier is untiered.
Every other tier owes a 02-acs.md; an examine tally when 05-examine.md
exists or a `Flags:` line holds `-x` or `+x`; an external tally when the
external pass ran (B5 rule). A tally file the guards refuse is never named
and does not count as held. The hook's run: a non-symlink dir of
<toplevel>/.claude/output/ttw/ whose 00-context.md passes the guards and
whose first `Branch:` token is the branch, with no pr.md and no commit.txt;
the newest 00-context.md wins. A run's date is its `Date:` line, else the
mtime of its 00-context.md.

B7 GRAPH, per run dir with an 01b-obsidian*.md (several are read as one).
The section is the lines after a `#… Graph relations` heading up to the
next heading; a `Graph status:` line anywhere is read with it. One outcome,
first match wins:
  - nosection: no such heading and no `Graph status:` line;
  - unavailable: a status `absent` or `unavailable` (the graph could not
    be asked; a reason given beside it changes nothing);
  - skipped: the section says the graph was not queried (`not queried`,
    `non interrog…`, `pas interrog…`, `skipp…`, any case);
  - contributed: the section cites a [[wikilink]] (B5 rule);
  - nothing: queried, nothing cited.
contributed_rate = contributed / (contributed + nothing + skipped): the
runs that could ask the graph. A query is recorded when a section line
starts with `Query:` or `Requête :` (a bullet first is allowed).
Citations: the run's project is the folder P of the first `[[02-Projets/P/`
link on a `Project note:` line, as written. Each `[[02-Projets/X/` link in
the section counts in cited_same when X equals P in any case, else in
cited_other; a run with no such line counts its links in cited_unknown.

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
and analyze cases; the table must hold all three outcomes. B7 is graded on
real 01b lines: every outcome and both query states present, and the rule
that reads the skip words before the status must mislabel one.
"""
import argparse
import datetime
import json
import pathlib
import re
import shlex
import subprocess
import sys

KNOWN_EXECUTABLES = frozenset({
    "awk", "bash", "brew", "cargo",
    "ttw-board", "ttw-health", "ttw-tier", "ttw-verify-external",
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
ACS_PATH = re.compile(r"/\.claude/output/ttw/[^/]+/02-acs\.md$")
VALIDATE_PATH = re.compile(r"/\.claude/output/ttw/[^/]+/04-validate\.md$")
OBSIDIAN_PATH = re.compile(r"/\.claude/output/ttw/[^/]+/01b-obsidian[^/]*\.md$")
GRAPH_HEADING = re.compile(r"^\s*#+\s*Graph relations\b", re.IGNORECASE)
HEADING = re.compile(r"^\s*#")
GRAPH_STATUS = re.compile(r"Graph status\s*:\s*[*`]*\s*([A-Za-z]+)", re.IGNORECASE)
GRAPH_SKIP = re.compile(r"not queried|non interrog|pas interrog|skipp", re.IGNORECASE)
GRAPH_QUERY = re.compile(r"^\s*(?:[-*]\s+)?[*`]*(?:Query|Requête)[*`]*\s*:", re.IGNORECASE)
GRAPH_OUTCOMES = ("nosection", "unavailable", "skipped", "contributed", "nothing")
# Run dirs, relative to the repo root.
RUN_DIRS = (pathlib.Path(".claude/output/ttw"),)
MEMORY_PATH = re.compile(r"/\.claude/projects/[^/]+/memory/[^/]+\.md$")
MEM_LINK = re.compile(r"\[\[([^\]|#]+)")
INDEX_LINK = re.compile(r"\]\(([^)]+\.md)\)")
NAME_LINE = re.compile(r"^name:\s*(\S+)", re.MULTILINE)
TALLY = re.compile(r"\bconfirmed=(\d+)")
TALLY_PAIR = re.compile(r"\bdismissed=\d+")
WIKILINK = re.compile(r"\[\[([^\]\s|#][^\]\n]*)")
FILES_LINE = re.compile(r"^Files:(.*)$", re.MULTILINE)
PATH_TOKEN = re.compile(r"(?<![\w.~/-])[\w.~-]*(?:/[\w.-]+)+")  # starts at a token edge: linear
GH_PR_CREATE = re.compile(r"^\s*gh\s+pr\s+create(\s|$)")
TIER_LINE = re.compile(r"^Tier:\s*[*`]*([A-Za-z-]+)", re.MULTILINE)
BRANCH_LINE = re.compile(r"^Branch:\s*(\S+)", re.MULTILINE)
FLAGS_LINE = re.compile(r"^(?:Tier:[^\n]*?)?\bFlags:([^\n]*)", re.MULTILINE)
DATE_LINE = re.compile(r"^Date:\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE)
X_FLAG = re.compile(r"(?<![\w-])[-+]x(?![\w-])")
NON_DIRECT = frozenset({"Standard", "High-stakes", "Diagnosis"})
GIT_TIMEOUT = 2
B6_SINCE = "2026-10-26"
B6_ITEMS = (
    ("acs", "02-acs.md (the ACs, each with its proving command)"),
    ("x", "the confirmed=N unique=U dismissed=D tally in 05-examine.md"),
    ("e", "the confirmed=N unique=U dismissed=D tally in 04-external-triage.md"),
)
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


# Real AC blocks, from .claude/output/ttw/<run>/02-acs.md (run ids and names renamed to ttw in phase 4).
# (run dir, AC, expected has_command, text)
FIXTURES = [
    ("53-ttw-leftovers", "AC3", True,
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
        "  - ttw-consistency evaluates (hooks.nix takes no new argument)\n"
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

# Real AC blocks, from .claude/output/ttw/<run>/02-acs.md (run ids and names renamed to ttw in phase 4).
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
    ("53-ttw-leftovers", "AC-docs", "docs",
     "- AC-docs: n/a (text)."),
    ("54-nix-audit-fixes", "AC-docs", "docs",
     "- AC-docs: nixfmt@1.5.0 — `nixfmt --check <files>` (rung 5)."),
    ("76-ttw-ac-proof", "AC13", "lecture", (
        "AC13 [lecture] — the new AC rule reads as one rule in step-02, step-04 and "
        "the verify loop, its two exceptions named alike in all three; "
        "ttw-consistency proves the sentences exist, not that a planner reads "
        "them unambiguously.")),
    ("27-goat-agent-sandbox", "AC3", "unproven", (
        "- AC3 Chaque exception L4/W6 du profil figure dans "
        "`scratchpad/ttw27/03-exceptions.md` avec la commande D1/D2 qui l'exige "
        "(relecture coordinateur, 1:1).")),
    ("65-git-prefix-redos", "AC6", "unproven",
     "AC6 Header comment explains the linear-time construction in one or two sentences."),
    ("53-ttw-leftovers", "AC3", "command",
     "- AC3: nix flake check green; diff limited to the 2 files."),
]

# Real tally text, from .claude/output/ttw/<run>/<file> (run ids and names renamed to ttw in phase 4).
# (run dir, file, expected outcome, text)
B5_TALLY_FIXTURES = [
    ("76-ttw-ac-proof", "05-examine.md", "changed", (
        "F3 | commit sweeping staged preprod files | noted | procedural; commit names "
        "the 8 paths (AC17)\n"
        "confirmed=4 unique=4 dismissed=3\n")),
    ("67-ttw-token-diet", "04-external-triage.md", "not changed", (
        "# External triage — 67-ttw-token-diet\n"
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
    # Real lines: 67-ttw-token-diet/01b-obsidian.md:13 (prefix), 02-plan.md:45.
    ("vault path against basename", "changed", (
        "- [[02-Projets/nix-darwin/sessions/2026-08-14 - refonte-verification-ttw]] / "
        "[[02-Projets/nix-darwin/sessions/2026-08-11 - enforcement-ttw-et-nettoyage]] — "
        "fix-loop bounds (2 correction rounds)\n"), (
        "T12 Session note (-n): supersedes [[2026-08-14 - refonte-verification-ttw]] and "
        "[[2026-09-09 - verificateur-externe-codex-dans-ttw]]; keep threshold ≥1 unique "
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

# Real 00-context.md lines, from .claude/output/ttw/<run>/ (run ids and names renamed to ttw in phase 4).
# (source, expected tier, expected examine due, text). "escalated" joins two
# real Tier: lines in escalation order: the last one decides.
B6_FIXTURES = [
    ("escalated: 77-correction-lessons + deck-bg-open", "High-stakes", True, (
        "Flags: -t -pr -o -n (Standard, provisoire : revu sur le diff réel par ttw-tier)\n"
        "Tier: Standard (provisoire)\n"
        "Tier: High-stakes. Flags: -t -x -pr -o -n -e\n")),
    ("77-correction-lessons", "Standard", False, (
        "Flags: -t -pr -o -n (Standard, provisoire : revu sur le diff réel par ttw-tier)\n"
        "Tier: Standard (provisoire)\n")),
    ("76-ttw-ac-proof", "Standard", True, (
        "Tier: Standard (provisional) — Files: unknown (analyze)\n"
        "Flags: -t -pr -o -n; escalated +x +e at validate\n")),
    ("ui-expert-skill", "Standard", False,
     "Flags: -t -pr -o -n (Standard defaults)\nTier: Standard\n"),
    ("01-worktree-env-sync", "High-stakes", True, (
        "Tier: High-stakes (sandbox denyRead/allowRead keys; new hook)\n"
        "Flags: -t -f -x -pr -o -n -e\n")),
    ("skills-header-count", "Direct", False,
     "Tier: Direct · Flags: -pr · Files: home/claude-code/skills.nix · Est-lines: 2\n"),
    ("session-state-child-overwrite", "Diagnosis", True,
     "Tier: Diagnosis (bug; coordinator inline, reproduced by probe)\nFlags: -x -pr -o -n\n"),
    # `Mode:` predates the Tier: line: untiered.
    ("task-board-ui", None, False,
     "Date: 2026-10-07\nMode: Standard\nFlags: -t -pr -o -n\nBranch: feat/task-board-ui\n"),
]

# Real 01b-obsidian lines, from <repo>/.claude/output/ttw/<run>/ (browser/ = ~/Projects/browser).
# (source, expected outcome, expected query recorded, text)
B7_FIXTURES = [
    ("14-codex-external-verifier", "nosection", False, (
        "## Requêtes graphe\n"
        "1. `codex vérificateur externe diff read-only cross-vendor` (depth 1, budget 1200)\n"
        "   → `[!] TRUNCATED`, 22/23 nœuds, **0 edge** → traitée comme requête ratée.\n")),
    ("21-codex-git-autonomy", "unavailable", False, (
        "### Graph relations (graphify)\n"
        "- Graph status: unavailable (no MCP on this host)\n"
        "\n"
        "### Implications for current task\n")),
    # Skip words beside an unavailable status: the status decides. The
    # retired scope wording is elided (…): AC1 of run 85 greps it away.
    ("browser/77-native-tab-id", "unavailable", False, (
        "### Graph relations (graphify)\n"
        "- Graph status: unavailable — hors scope (graphify couvre …, CLAUDE.md), non interrogé.\n")),
    ("sandbox-network-shape", "skipped", False, (
        "### Graph relations (graphify)\n"
        "- Not queried (recency + grep sufficient for a bounded hook task).\n"
        "- Graph status: fresh (graph.json 2026-10-11 10:06)\n")),
    ("watch-instagram-skill", "skipped", False, (
        "### Graph relations (graphify)\n"
        "- Graph status: fresh (graph.json 2026-10-22 08:17). Not queried: recency + grep already "
        "surfaced the sandbox-cache decisions; topic (video skill) has no prior notes (grep 0 hits "
        "on instagram/yt-dlp in sessions besides generic sandbox ones).\n")),
    ("75-apex-metrics-probe", "contributed", False, (
        "### Graph relations (graphify)\n"
        "- Graph status: fresh (graph.json 2026-10-23 20:49). Query truncated (23/32 nodes, no "
        "edges); hits: [[02-Projets/nix-darwin/sessions/2026-10-10 - banc-modeles-effort]] (bench "
        "method with control arm), [[02-Projets/nix-darwin/sessions/2026-10-22 - "
        "apex-pr-record-runs-direct]] (Direct runs found by run-dir name). Not reformulated: "
        "recency + memory already cover the constraint.\n"
        "\n"
        "### Implications for current task\n")),
    ("85-graph-memory", "contributed", True, (
        "### Graph relations (graphify)\n"
        "- Query: `graphify reindex périmètre étape obsidian sonde métriques` (depth 1, budget "
        "1200) — 14 nodes, complete.\n"
        "- [[02-Projets/nix-darwin/sessions/2026-10-24 - apex-utilite-des-etapes]] — B5 o (vault) "
        "metric: ran / recorded / changed; B7 sits beside it.\n"
        "- Graph status: fresh (graph.json 2026-11-11 13:35)\n")),
    ("browser/81-launcher-orphan-abandon", "nothing", False, (
        "### Graph relations (graphify)\n"
        "- rien de pertinent (requête « hôte orphelin SIGKILL groupe pid réutilisé » : nœuds "
        "Preliz/nix-darwin/GOAT seulement).\n"
        "- Graph status: stale (2026-11-08 13:54) — reindex lancé en arrière-plan.\n")),
    # Lines 19-23 and 58: the status is a heading of its own, after the section.
    ("brew-blender", "nothing", True, (
        "## Graph relations (graphify)\n"
        "\n"
        "Query: `homebrew cask brew zap masApps conventions` (3-6 domain keywords)\n"
        "Depth: 1 | Token budget: 1200\n"
        "\n"
        "### Graph status: fresh\n")),
]

# Real 01b Project note line + graph section, same tree as B7_FIXTURES
# (leboisjean/, portfolio/, Preliz/ = ~/Projects/<name>).
# (source, expected project, expected same, expected other, text)
B7_CITE_FIXTURES = [
    ("leboisjean/01-scaffold-astro", "leboisjean", 0, 2, (
        "### Project note: [[02-Projets/leboisjean/leboisjean]]\n"
        "### Graph relations (graphify)\n"
        "- [[02-Projets/portfolio/decisions/2026-09-23 - stack-technique]] — Astro 7 (sorti "
        "2026-06-22), `@astrojs/cloudflare` 14.x exige astro ^7.2 ; TypeScript reste en 6.0 "
        "(`@astrojs/check` et `typescript-eslint` ne supportent pas TS 7).\n"
        "- [[02-Projets/brasserie-les-ecrivains/references/2026-09-07 - "
        "plan-geo-referencement-ia]] — `llms.txt` n'apporte rien (position Google) : ne pas "
        "investir dessus (étape 3).\n"
        "- Graph status: fresh\n")),
    # The bare word Preliz in the second bullet is no wikilink: one citation.
    ("ui-expert-skill", "nix-darwin", 0, 1, (
        "### Project note: [[02-Projets/nix-darwin/nix-darwin]]\n"
        "### Graph relations (graphify)\n"
        "- [[02-Projets/Preliz/sessions/2026-09-03 - relachement-du-swipe-a-la-velocite]] — "
        "Emil's apple-design §4 (`bounce` + `duration`) contradicts §5 (velocity handoff) on "
        "Motion: motion-dom@12.43.0 spring.mjs:127-134 sets `velocity = 0` for time-defined "
        "springs. Measured in Preliz.\n"
        "- Preliz `apple-motion` was cut from emilkowalski/skills apple-design (graph node, "
        "session 2026-09-02).\n"
        "- Graph status: fresh\n")),
    # The Project note line is itself a 02-Projets link, outside the section:
    # counting the whole file would give same=4.
    ("portfolio/35-refonte-design", "portfolio", 3, 0, (
        "### Project note: [[02-Projets/portfolio/portfolio]]\n"
        "### Graph relations (graphify)\n"
        "- Query \"palette typographie direction artistique schéma\", depth 1: 4 nodes, no "
        "truncation banner. Hits: `palette.ts` ([[02-Projets/portfolio/sessions/2026-09-28 - "
        "mini-planete-style-abouti]], planète GLB, obsolète), \"Direction A / C · Galerie musée "
        "de nuit (éliminée)\" ([[02-Projets/portfolio/portfolio]]), `Schema.astro / "
        "SchemaDirect.astro` --calls--> `Route /api/trace` ([[02-Projets/portfolio/sessions/"
        "2026-10-01 - refonte-schema-vivant]]). Nothing new beyond recency.\n"
        "- enquire search also run (portfolio direction artistique): only portfolio notes above "
        "relevant; rest Preliz email noise.\n"
        "- Graph status: stale (2026-10-07 14:00); `graphify-reindex` fired in background "
        "(completed exit 0).\n")),
    # No Project note line: every citation counts in other.
    ("Preliz/planning-lot1", None, 0, 3, (
        "### Graph relations (graphify)\n"
        "- [[02-Projets/Preliz/sessions/2026-06-27 - prefs-dashboard-atomique]] — écritures de "
        "préférences JSON doivent être ATOMIQUES (upsert/opérateurs jsonb), pas "
        "read-modify-write ; #18b ouvert sur auth/actions.server.ts:87,:129.\n"
        "- [[02-Projets/Preliz/sessions/2026-09-25 - "
        "le-calendrier-journaliste-et-le-goulot-de-l-oeil]] — la ligne de chiffres journaliste "
        "comptait SES demandes (jamais la dispo) ; elle disparaît maintenant.\n"
        "- [[02-Projets/Preliz/sessions/2026-09-24 - "
        "les-compteurs-cliquables-et-ce-que-le-smoke-a-trouve]] — barColumnSpan / SwimLaneBar.\n"
        "- Graph status: fresh (07:21 15/10), réponse TRUNCATED (20/22 nœuds), pas de "
        "reformulation.\n")),
    # Not real: no report spells a folder in another case. planning-lot1 with
    # a template Project note line in lower case; a case-sensitive match
    # would give same=0 other=3.
    ("Preliz/planning-lot1 + lower-case project line", "preliz", 3, 0, (
        "### Project note: [[02-Projets/preliz/preliz]]\n"
        "### Graph relations (graphify)\n"
        "- [[02-Projets/Preliz/sessions/2026-06-27 - prefs-dashboard-atomique]] — écritures de "
        "préférences JSON doivent être ATOMIQUES (upsert/opérateurs jsonb), pas "
        "read-modify-write ; #18b ouvert sur auth/actions.server.ts:87,:129.\n"
        "- [[02-Projets/Preliz/sessions/2026-09-25 - "
        "le-calendrier-journaliste-et-le-goulot-de-l-oeil]] — la ligne de chiffres journaliste "
        "comptait SES demandes (jamais la dispo) ; elle disparaît maintenant.\n"
        "- [[02-Projets/Preliz/sessions/2026-09-24 - "
        "les-compteurs-cliquables-et-ce-que-le-smoke-a-trouve]] — barColumnSpan / SwimLaneBar.\n"
        "- Graph status: fresh (07:21 15/10), réponse TRUNCATED (20/22 nœuds), pas de "
        "reformulation.\n")),
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


def graph_section(text):
    """The lines under each `#… Graph relations` heading, up to the next
    heading; None when the file has no such heading."""
    found = None
    inside = False
    for line in text.splitlines():
        if HEADING.match(line):
            inside = GRAPH_HEADING.match(line) is not None
            if inside and found is None:
                found = []
            continue
        if inside:
            found.append(line)
    return found


PROJECT_FOLDER = re.compile(r"\[\[02-Projets/([^/\]|#]+)/")


def graph_citations(text):
    """(project, same, other) for an 01b-obsidian text (module docstring, B7)."""
    project = None
    for line in text.splitlines():
        if "Project note:" in line:
            m = PROJECT_FOLDER.search(line)
            if m:
                project = m.group(1)
                break
    cited = PROJECT_FOLDER.findall("\n".join(graph_section(text) or []))
    if project is None:
        return None, 0, len(cited)
    same = sum(1 for x in cited if x.lower() == project.lower())
    return project, same, len(cited) - same


def graph_outcome(text):
    """One of GRAPH_OUTCOMES for an 01b-obsidian text (module docstring, B7)."""
    section = graph_section(text)
    status = [line for line in text.splitlines() if GRAPH_STATUS.search(line)]
    if section is None and not status:
        return "nosection"
    if any(GRAPH_STATUS.search(line).group(1).lower() in ("absent", "unavailable") for line in status):
        return "unavailable"
    body = "\n".join((section or []) + status)
    if GRAPH_SKIP.search(body):
        return "skipped"
    return "contributed" if wikilinks(body) else "nothing"


def graph_query_recorded(text):
    """A section line starts with `Query:` or `Requête :`."""
    return any(GRAPH_QUERY.match(line) for line in graph_section(text) or [])


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


def run_tier(ctx):
    """The first word of the last `Tier:` line, None when there is none."""
    found = TIER_LINE.findall(ctx)
    return found[-1] if found else None


def run_branch(ctx):
    m = BRANCH_LINE.search(ctx)
    return m.group(1).strip("`") if m else None


def x_due(ctx):
    """A `Flags:` line asks for the examine pass (`-x`, or `+x` on escalation);
    any of them, as an escalation writes its flags on a later line."""
    return any(X_FLAG.search(f) is not None for f in FLAGS_LINE.findall(ctx))


def run_date(run, ctx):
    m = DATE_LINE.search(ctx)
    if m:
        return m.group(1)
    return datetime.date.fromtimestamp((run / "00-context.md").stat().st_mtime).isoformat()


def _file_state(p):
    """ok for a regular file, unreadable for a symlink or another kind, else missing."""
    if p.is_symlink() or (p.exists() and not p.is_file()):
        return "unreadable"
    return "ok" if p.exists() else "missing"


def run_gaps(run, cap):
    """{item: ok | missing | unreadable} for each B6 file a tiered non-Direct
    run owes, in B6_ITEMS order; None when it owes nothing (Direct, untiered,
    unknown tier) or its 00-context.md is refused by the guards."""
    ctx = _guarded_text(run / "00-context.md", cap)
    if ctx is None or run_tier(ctx) not in NON_DIRECT:
        return None
    tallied = b5_tallied(run, cap)
    if tallied["x"] == "not run" and x_due(ctx):
        tallied["x"] = "unknown"
    out = {"acs": _file_state(run / "02-acs.md")}
    for step in ("x", "e"):
        got = tallied[step]
        if got != "not run":
            out[step] = {"unknown": "missing", "unreadable": "unreadable"}.get(got, "ok")
    return out


def _tool_failed(resp):
    return isinstance(resp, dict) and (resp.get("interrupted") is True or resp.get("is_error") is True)


def head_flag(argv):
    """The value of the first `-H`/`--head` token (`--head=` included), None
    when absent: read from argv, so a `-H` inside a quoted title never counts."""
    for i, tok in enumerate(argv):
        if tok in ("-H", "--head") and i + 1 < len(argv):
            return argv[i + 1]
        if tok.startswith("--head="):
            return tok[len("--head="):]
    return None


def current_run(cwd, cmd):
    """The run dir of the branch a `gh pr create` opens (module docstring), None when unknown."""
    if not isinstance(cwd, str):
        return None
    try:
        got = subprocess.run(
            ["git", "-c", "core.fsmonitor=false", "rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD"],
            cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=GIT_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return None
    lines = got.stdout.splitlines()
    if got.returncode != 0 or len(lines) != 2 or lines[1] == "HEAD":
        return None
    top, branch = lines
    try:
        argv = shlex.split(cmd)
    except ValueError:
        return None
    head = head_flag(argv)
    if head is not None:
        branch = head.split(":", 1)[-1]
    found = []
    for out in RUN_DIRS:
        base = pathlib.Path(top) / out
        if base.is_symlink() or not base.is_dir():
            continue
        found += _branch_runs(base, branch)
    return max(found)[2] if found else None


def _branch_runs(base, branch):
    """(mtime, name, dir) of each unfinished run of `branch` under `base`."""
    found = []
    for r in base.iterdir():
        if r.is_symlink() or not r.is_dir():
            continue
        ctx = _guarded_text(r / "00-context.md", HOOK_MAX_BYTES)
        if ctx is None or run_branch(ctx) != branch:
            continue
        if any((r / n).exists() or (r / n).is_symlink() for n in ("pr.md", "commit.txt")):
            continue
        found.append(((r / "00-context.md").stat().st_mtime, r.name, r))
    return found


def pr_hook(data):
    """--hook after a lone `gh pr create`: name the B6 files the branch's run lacks."""
    cmd = data.get("tool_input", {}).get("command")
    if not isinstance(cmd, str) or not GH_PR_CREATE.match(cmd):
        return 0
    if _tool_failed(data.get("tool_response")):
        return 0
    run = current_run(data.get("cwd"), cmd)
    gaps = run_gaps(run, HOOK_MAX_BYTES) if run is not None else None
    items = [text for key, text in B6_ITEMS if (gaps or {}).get(key) == "missing"]
    if not items:
        return 0
    msg = (f"TTW run .claude/output/{run.parent.name}/{run.name}/ is missing: {'; '.join(items)}. "
           "Write them before merging (B6).")
    print(json.dumps({"hookSpecificOutput": dict(hookEventName="PostToolUse", additionalContext=msg)}))
    return 0


def b6_self_test(failures):
    """Tier and examine-due on real 00-context lines; the first-Tier-line rule
    must mislabel one, or the escalation fixture cannot fail."""
    first_wrong = 0
    for source, tier, due, text in B6_FIXTURES:
        got = run_tier(text)
        if got != tier:
            failures.append(f"B6 {source}: tier {got}, expected {tier}")
        if x_due(text) != due:
            failures.append(f"B6 {source}: examine due {x_due(text)}, expected {due}")
        first = TIER_LINE.search(text)
        if (first.group(1) if first else None) != tier:
            first_wrong += 1
    if first_wrong == 0:
        failures.append("B6 fixtures cannot fail: the first-Tier-line rule mislabels none of them")
    if {f[2] for f in B6_FIXTURES} != {True, False}:
        failures.append("B6 table too thin: examine due needs both outcomes")
    return len(B6_FIXTURES)


def b7_self_test(failures):
    """Graph outcome and query line on real 01b lines; the rule that reads
    the skip words before the status must mislabel one, or the order cannot fail."""
    skip_first_wrong = 0
    for source, outcome, queried, text in B7_FIXTURES:
        got = graph_outcome(text)
        if got != outcome:
            failures.append(f"B7 {source}: {got}, expected {outcome}")
        if graph_query_recorded(text) != queried:
            failures.append(f"B7 {source}: query recorded {graph_query_recorded(text)}, expected {queried}")
        skip_first = "skipped" if GRAPH_SKIP.search(text) else got
        if skip_first != outcome:
            skip_first_wrong += 1
    if skip_first_wrong == 0:
        failures.append("B7 fixtures cannot fail: the skip-first rule mislabels none of them")
    missing = [o for o in GRAPH_OUTCOMES if o not in {f[1] for f in B7_FIXTURES}]
    if missing:
        failures.append(f"B7 table too thin: no fixture for {', '.join(missing)}")
    if {f[2] for f in B7_FIXTURES} != {True, False}:
        failures.append("B7 table too thin: query recorded needs both outcomes")
    return len(B7_FIXTURES), len(GRAPH_OUTCOMES) - len(missing)


def b7_cite_self_test(failures):
    """Project and same/other graph citations on real 01b lines; a fixture
    must cite its project in another case, or the case rule cannot fail."""
    folder = re.compile(r"\[\[02-Projets/([^/\]|#]+)/")
    case_cases = 0
    for source, project, same, other, text in B7_CITE_FIXTURES:
        got = graph_citations(text)
        if got != (project, same, other):
            failures.append(f"B7 cite {source}: {got}, expected {(project, same, other)}")
        if project is not None and any(x != project and x.lower() == project.lower()
                                       for x in folder.findall(text)):
            case_cases += 1
    if case_cases == 0:
        failures.append("B7 cite fixtures cannot fail: none cites its project in another case")
    if not any(f[2] > 0 for f in B7_CITE_FIXTURES):
        failures.append("B7 cite table too thin: no fixture with same > 0")
    if not any(f[3] > 0 and f[1] is not None for f in B7_CITE_FIXTURES):
        failures.append("B7 cite table too thin: no fixture with other > 0 and a project")
    if not any(f[1] is None and f[3] > 0 for f in B7_CITE_FIXTURES):
        failures.append("B7 cite table too thin: no fixture without a project that cites")
    return len(B7_CITE_FIXTURES)


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
    n_b6 = b6_self_test(failures)
    n_b7, b7_outcomes = b7_self_test(failures)
    n_b7_cite = b7_cite_self_test(failures)
    for f in failures:
        print(f"FAIL {f}")
    print(f"self-test fixtures={len(FIXTURES)} command={n_cmd} prose={n_prose} "
          f"v0_mislabels={v0_wrong} class_fixtures={len(CLASS_FIXTURES)} "
          f"unmarked_mislabels={unmarked_wrong} b5_fixtures={n_b5} b6_fixtures={n_b6} "
          f"b7_fixtures={n_b7} b7_outcomes={b7_outcomes}/{len(GRAPH_OUTCOMES)} "
          f"b7_cite_fixtures={n_b7_cite} failures={len(failures)}")
    return 1 if failures else 0


def _label(is_cmd):
    return "command" if is_cmd else "prose"


def _read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def note_slug(text):
    """The `name:` slug of a memory note, None when it has none."""
    m = NAME_LINE.search(text)
    return m.group(1) if m else None


def note_links(text):
    """The [[link]] targets of a memory note, as B4 counts them."""
    return set(MEM_LINK.findall(text))


def index_links(text):
    """The note files MEMORY.md links to."""
    return set(INDEX_LINK.findall(text))


def metrics(runs_roots, mem_root, since=B6_SINCE):
    out = {}
    runs = sorted(p for root in runs_roots for p in root.iterdir() if p.is_dir())

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
    ac_files = sorted(f for root in runs_roots for f in root.glob("*/02-acs.md"))
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
    for f in sorted(f for root in runs_roots for f in root.glob("*/00-context.md")):
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
    linked = index_links(idx)
    names = set()
    wikilinks = set()
    for f in files:
        body = _guarded_text(mem_root / f, None)
        if body is None:
            continue
        slug = note_slug(body)
        if slug is not None:
            names.add(slug)
        wikilinks |= note_links(body)
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

    # B6: run files due at the end of a run (see the module docstring)
    rows = []
    for r in runs:
        ctx = _guarded_text(r / "00-context.md", None)
        if ctx is None:
            rows.append((datetime.date.fromtimestamp(r.stat().st_mtime).isoformat(), "untiered", None))
            continue
        tier = run_tier(ctx)
        kind = "untiered" if tier not in NON_DIRECT | {"Direct"} else tier
        rows.append((run_date(r, ctx), kind, run_gaps(r, None)))
    out["B6.since"] = since
    for prefix, keep in (("B6", rows), ("B6.since", [row for row in rows if row[0] >= since])):
        gaps = [g for _, _, g in keep if g is not None]
        acs = sum(1 for g in gaps if g["acs"] == "ok")
        due = [g for g in gaps if "x" in g or "e" in g]
        held = sum(1 for g in due if all(g.get(s, "ok") == "ok" for s in ("x", "e")))
        out[f"{prefix}.runs"] = len(gaps)
        out[f"{prefix}.untiered"] = sum(1 for _, kind, _ in keep if kind == "untiered")
        out[f"{prefix}.with_acs"] = acs
        out[f"{prefix}.acs_rate"] = f"{acs / len(gaps):.1%}" if gaps else "n/a"
        out[f"{prefix}.tally_due"] = len(due)
        out[f"{prefix}.with_tally"] = held
        out[f"{prefix}.tally_rate"] = f"{held / len(due):.1%}" if due else "n/a"

    # B7: did step-01b query the knowledge graph (see the module docstring)
    graph = []
    cited_same = cited_other = cited_unknown = 0
    for r in runs:
        obs = [_guarded_text(p, None) for p in sorted(r.glob("01b-obsidian*.md"))]
        if obs:
            joined = "\n".join(t for t in obs if t is not None)
            graph.append(graph_outcome(joined))
            project, same, other = graph_citations(joined)
            cited_same += same
            if project is None:
                cited_unknown += other
            else:
                cited_other += other
    out["B7.runs"] = len(graph)
    for o in GRAPH_OUTCOMES:
        out[f"B7.{o}"] = graph.count(o)
    asked = sum(graph.count(o) for o in ("contributed", "nothing", "skipped"))
    out["B7.contributed_rate"] = f"{graph.count('contributed') / asked:.1%}" if asked else "n/a"
    out["B7.cited_same"] = cited_same
    out["B7.cited_other"] = cited_other
    out["B7.cited_unknown"] = cited_unknown
    return out


def acs_report(path):
    """--acs: the class of each AC of one 02-acs.md, then the counts."""
    try:
        text = _read(path)
    except OSError as e:
        print(f"ttw-metrics-probe: cannot read {path}: {e.strerror or e}", file=sys.stderr)
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
    if data.get("tool_name") == "Bash":
        return pr_hook(data)
    path = data["tool_input"]["file_path"]
    if isinstance(path, str) and VALIDATE_PATH.search(path):
        return validate_hook(pathlib.Path(path))
    if isinstance(path, str) and OBSIDIAN_PATH.search(path):
        return graph_hook(pathlib.Path(path))
    if isinstance(path, str) and MEMORY_PATH.search(path):
        return memory_hook(pathlib.Path(path))
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


def graph_hook(p):
    """--hook on a run's 01b-obsidian*.md: ask for the graph query it does not record."""
    if p.is_symlink() or not p.is_file() or p.stat().st_size > HOOK_MAX_BYTES:
        return 0
    text = _read(p)
    outcome = graph_outcome(text)
    if outcome == "unavailable" or graph_query_recorded(text):
        return 0
    msg = (f"B7: {p.parent.name}/{p.name} records no graph query (outcome: {outcome}). "
           "Run `mcp__graphify__query_graph` (step-01b step 7) and record its `- Query:` line "
           "under `### Graph relations`; recency covering the task is no reason to skip. Only a "
           "graph that cannot be asked sets `Graph status: absent` or `unavailable` instead.")
    print(json.dumps({"hookSpecificOutput": dict(hookEventName="PostToolUse", additionalContext=msg)}))
    return 0


def memory_hook(p):
    """--hook on a memory note or its MEMORY.md: name what B4 counts against it."""
    if p.is_symlink():
        return 0
    if not p.is_file() or p.stat().st_size > HOOK_MAX_BYTES:
        return 0
    text = _read(p)
    files = {q.name for q in p.parent.glob("*.md")} - {"MEMORY.md"}
    if p.name == "MEMORY.md":
        dead = sorted(index_links(text) - files)
        if not dead:
            return 0
        more = f", +{len(dead) - HOOK_CAP} more" if len(dead) > HOOK_CAP else ""
        msg = f"memory: MEMORY.md links missing notes: {', '.join(dead[:HOOK_CAP])}{more}"
    else:
        names = set()
        by_stem = {}
        for f in sorted(files):
            body = _guarded_text(p.parent / f, HOOK_MAX_BYTES)
            if body is not None:
                by_stem[f[:-3]] = note_slug(body)
                names.add(by_stem[f[:-3]])
        names.discard(None)
        for stem, slug in list(by_stem.items()):
            by_stem.setdefault(stem.replace("_", "-"), slug)
            by_stem.setdefault(stem.replace("-", "_"), slug)
        items = []
        for link in sorted(note_links(text) - names):
            shown = link[:80]
            if link not in by_stem:
                items.append(f"[[{shown}]] (no such note)")
            elif by_stem[link] is None:
                items.append(f"[[{shown}]] (note has no name: slug)")
            else:
                items.append(f"[[{shown}]] → [[{by_stem[link]}]]")
        if len(items) > HOOK_CAP:
            items[HOOK_CAP:] = [f"+{len(items) - HOOK_CAP} more"]
        idx = _guarded_text(p.parent / "MEMORY.md", HOOK_MAX_BYTES)
        if idx is not None and p.name not in index_links(idx):
            items.append("not listed in MEMORY.md")
        if not items:
            return 0
        msg = f"memory: {p.name}: {'; '.join(items)}"
    print(json.dumps({"hookSpecificOutput": dict(hookEventName="PostToolUse", additionalContext=msg)}))
    return 0


def main():
    ap = argparse.ArgumentParser(description="TTW run metrics (B1-B7).")
    ap.add_argument("--runs", type=pathlib.Path, action="append", default=None,
                    help="a runs dir, repeatable (default: .claude/output/ttw)")
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
    ap.add_argument("--since", type=lambda s: datetime.date.fromisoformat(s).isoformat(),
                    default=B6_SINCE, help="B6.since.*: runs dated on or after DATE (YYYY-MM-DD)")
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
    if args.runs is not None:
        runs_roots = [r.expanduser() for r in args.runs]
    else:
        runs_roots = [p for p in RUN_DIRS if p.is_dir()] or [RUN_DIRS[0]]
    mem_root = args.memory.expanduser()
    for label, path in [("runs dir", r) for r in runs_roots] + [("memory dir", mem_root)]:
        if not path.is_dir():
            print(f"ttw-metrics-probe: {label} not found: {path}", file=sys.stderr)
            return 2
    if not (mem_root / "MEMORY.md").is_file():
        print(f"ttw-metrics-probe: no MEMORY.md in {mem_root}", file=sys.stderr)
        return 2
    for key, val in sorted(metrics(runs_roots, mem_root, args.since).items()):
        print(f"{key}={val}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
