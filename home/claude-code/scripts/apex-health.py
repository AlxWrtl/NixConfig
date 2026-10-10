"""apex-health: compare APEX runs BEFORE vs AFTER a date and flag a quality drift.

Read-only, zero network, zero model call. Sources: Claude Code transcripts,
the correction-budget round/grant files, 00-context.md of each repo, git log.
Exit 0 = no drift (or not enough data), 2 = drift, 1 = usage/IO error.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_SINCE = "2026-10-10"
MIN_N = 5
DRIFT_RATIO = 1.5
DRIFT_MIN = 0.1
FIX_WINDOW = datetime.timedelta(days=7)
EXCLUDED_MARKERS = ("scratchpad", "-private-tmp-", "-var-folders-")
CONTEXT_RE = re.compile(r"\.claude/output/apex/([^/]+)/00-context\.md$")
BUDGET_RE = re.compile(r"^(?P<run>.+)\.(?P<kind>round|grant)(?P<n>\d+)$")
UTC = datetime.timezone.utc


class UsageError(Exception):
    pass


def parse_when(text, flag):
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
            return datetime.datetime.strptime(text, "%Y-%m-%d").replace(tzinfo=UTC)
        value = datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        raise UsageError(f"{flag} : date invalide « {text} » (attendu YYYY-MM-DD ou ISO 8601)")
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value


def parse_ts(text):
    if not isinstance(text, str):
        return None
    try:
        value = datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value


class Periods:
    def __init__(self, since, days, now):
        self.start = since - datetime.timedelta(days=days)
        self.since = since
        self.now = now

    def of(self, when):
        if when is None:
            return None
        if self.start <= when < self.since:
            return "before"
        if self.since <= when < self.now:
            return "after"
        return None


def is_excluded(project_name):
    return any(marker in project_name for marker in EXCLUDED_MARKERS)


def iter_json_lines(path, stats):
    try:
        handle = path.open("r", encoding="utf-8", errors="replace")
    except OSError:
        stats["unreadable_files"] += 1
        return
    with handle:
        for line in handle:
            if '"assistant"' not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                stats["malformed"] += 1
                continue
            if isinstance(record, dict):
                yield record


def tool_uses(record):
    message = record.get("message")
    if record.get("type") != "assistant" or not isinstance(message, dict):
        return []
    content = message.get("content")
    if not isinstance(content, list):
        return []
    return [c for c in content if isinstance(c, dict) and c.get("type") == "tool_use"]


def scan_session(path, stats, with_subagents):
    """Return (first apex call time, run count, usages by message id) or None if not APEX."""
    first_apex = None
    contexts = set()
    usages = {}
    for record in iter_json_lines(path, stats):
        for use in tool_uses(record):
            data = use.get("input") if isinstance(use.get("input"), dict) else {}
            if use.get("name") == "Skill" and data.get("skill") == "apex":
                when = parse_ts(record.get("timestamp"))
                if when is not None and (first_apex is None or when < first_apex):
                    first_apex = when
            if use.get("name") == "Write" and isinstance(data.get("file_path"), str):
                if CONTEXT_RE.search(data["file_path"]):
                    contexts.add(data["file_path"])
        collect_usage(record, usages)
    if first_apex is None:
        return None
    subagents = path.with_suffix("") / "subagents"
    if with_subagents and subagents.is_dir():
        for sub in sorted(subagents.glob("*.jsonl")):
            for record in iter_json_lines(sub, stats):
                collect_usage(record, usages)
    return first_apex, max(1, len(contexts)), usages


def collect_usage(record, usages):
    message = record.get("message")
    if record.get("type") != "assistant" or not isinstance(message, dict):
        return
    usage = message.get("usage")
    msg_id = message.get("id")
    if isinstance(usage, dict) and isinstance(msg_id, str):
        usages[msg_id] = usage


def num(usage, key):
    value = usage.get(key)
    return value if isinstance(value, (int, float)) else 0


def weighted(usage):
    return num(usage, "input_tokens") + 2 * num(usage, "cache_creation_input_tokens") + num(usage, "cache_read_input_tokens") / 10 + 5 * num(usage, "output_tokens")


def scan_sessions(claude_dir, periods, stats):
    acc = {p: {"sessions": 0, "runs": 0, "weighted": 0.0, "output": 0} for p in ("before", "after")}
    included = set()
    projects = claude_dir / "projects"
    if not projects.is_dir():
        return acc, included
    for project in sorted(projects.iterdir()):
        if not project.is_dir():
            continue
        for path in sorted(project.glob("*.jsonl")):
            excluded = is_excluded(project.name)
            result = scan_session(path, stats, not excluded)
            if result is None:
                continue
            if excluded:
                stats["excluded"] += 1
                continue
            first_apex, runs, usages = result
            included.add(path.stem)
            period = periods.of(first_apex)
            if period is None:
                continue
            bucket = acc[period]
            bucket["sessions"] += 1
            bucket["runs"] += runs
            bucket["weighted"] += sum(weighted(u) for u in usages.values())
            bucket["output"] += sum(num(u, "output_tokens") for u in usages.values())
    return acc, included


def scan_budget(claude_dir, periods, included, stats):
    counts = {p: {"round": 0, "grant": 0} for p in ("before", "after")}
    budget = claude_dir / "apex-correction-budget"
    if not budget.is_dir():
        return counts
    for path in sorted(budget.iterdir()):
        match = BUDGET_RE.match(path.name)
        if match is None or not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8", errors="replace").strip().splitlines()[0])
        except (OSError, ValueError, IndexError):
            stats["malformed"] += 1
            continue
        if not isinstance(data, dict) or data.get("session") not in included:
            continue
        period = periods.of(parse_ts(data.get("ts")))
        if period is not None:
            counts[period][match.group("kind")] += 1
    return counts


def git(repo, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    proc = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        return None
    return proc.stdout


def resolve_repos(paths, warnings):
    repos = []
    for raw in paths:
        try:
            top = git(raw, "rev-parse", "--show-toplevel")
        except FileNotFoundError:
            warnings.append("git introuvable : dépôts ignorés")
            return []
        if top is None:
            warnings.append(f"{raw} : pas un dépôt git, ignoré")
            continue
        repos.append(Path(top.strip()))
    return repos


def scan_escalations(repos, periods):
    counts = {p: {"runs": 0, "escalated": 0} for p in ("before", "after")}
    for repo in repos:
        for ctx in sorted((repo / ".claude" / "output" / "apex").glob("*/00-context.md")):
            try:
                lines = ctx.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            when = None
            for line in lines:
                found = re.match(r"^Date:\s*(\d{4}-\d{2}-\d{2})", line)
                if found:
                    when = datetime.datetime.strptime(found.group(1), "%Y-%m-%d").replace(tzinfo=UTC)
                    break
            if when is None:
                when = datetime.datetime.fromtimestamp(ctx.stat().st_mtime, tz=UTC)
            period = periods.of(when)
            if period is None:
                continue
            counts[period]["runs"] += 1
            if any(line.startswith("Escalated:") for line in lines):
                counts[period]["escalated"] += 1
    return counts


def default_branch(repo):
    for ref in ("master", "main"):
        if git(repo, "rev-parse", "--verify", "-q", f"refs/heads/{ref}") is not None:
            return ref
    return "HEAD"


def read_commits(repo):
    out = git(repo, "log", "--first-parent", "--format=%x1e%H%x09%cI%x09%s", "--name-only", default_branch(repo))
    if out is None:
        return []
    commits = []
    for chunk in out.split("\x1e"):
        lines = chunk.strip("\n").splitlines()
        if not lines:
            continue
        head = lines[0].split("\t", 2)
        if len(head) != 3:
            continue
        when = parse_ts(head[1])
        if when is None:
            continue
        files = {f for f in lines[1:] if f.strip() and not is_doc(f)}
        commits.append({"when": when, "subject": head[2], "files": files})
    commits.sort(key=lambda c: c["when"])
    return commits


def is_doc(path):
    """Docs and the lock file ride along with almost every PR: sharing one proves nothing."""
    return path.endswith(".md") or path.rsplit("/", 1)[-1] == "flake.lock"


def is_fix(subject):
    return subject.lower().startswith("fix")


def scan_fix_after(repos, periods):
    counts = {p: {"scored": 0, "followed": 0, "pending": 0} for p in ("before", "after")}
    for repo in repos:
        commits = read_commits(repo)
        for i, commit in enumerate(commits):
            if is_fix(commit["subject"]) or not commit["files"]:
                continue
            period = periods.of(commit["when"])
            if period is None:
                continue
            if periods.now - commit["when"] < FIX_WINDOW:
                counts[period]["pending"] += 1
                continue
            counts[period]["scored"] += 1
            limit = commit["when"] + FIX_WINDOW
            for later in commits[i + 1:]:
                if later["when"] > limit:
                    break
                if later["when"] > commit["when"] and is_fix(later["subject"]) and later["files"] & commit["files"]:
                    counts[period]["followed"] += 1
                    break
    return counts


def ratio(numer, denom):
    return numer / denom if denom else None


def is_drift(before, after):
    return after > before * DRIFT_RATIO and after - before >= DRIFT_MIN


def verdict(n_before, v_before, n_after, v_after):
    if n_after < MIN_N or n_before < MIN_N or v_before is None or v_after is None:
        return "insuffisant"
    if is_drift(v_before, v_after):
        return "DÉRIVE"
    return "ok"


def fmt(value, digits):
    return "—" if value is None else f"{value:.{digits}f}"


def delta(before, after):
    if before is None or after is None or before == 0:
        return "—"
    return f"{(after - before) / before * 100:+.0f} %"


def build_report(args, periods):
    claude_dir = Path(os.path.expanduser(args.claude_dir))
    if not claude_dir.is_dir():
        raise UsageError(f"--claude-dir : {claude_dir} introuvable")
    stats = {"malformed": 0, "excluded": 0, "unreadable_files": 0}
    warnings = []
    sessions, included = scan_sessions(claude_dir, periods, stats)
    budget = scan_budget(claude_dir, periods, included, stats)
    repo_args = args.repo
    if not repo_args:
        try:
            repo_args = ["."] if git(".", "rev-parse", "--git-dir") is not None else []
        except FileNotFoundError:
            warnings.append("git introuvable : dépôts ignorés")
            repo_args = []
    repos = resolve_repos(repo_args, warnings)
    esc = scan_escalations(repos, periods)
    fixes = scan_fix_after(repos, periods)

    b, a = sessions["before"], sessions["after"]
    rows = [
        ("tokens pondérés / run", b["runs"], ratio(b["weighted"], b["runs"]), a["runs"], ratio(a["weighted"], a["runs"]), 1, False),
        ("tokens de sortie / run", b["runs"], ratio(b["output"], b["runs"]), a["runs"], ratio(a["output"], a["runs"]), 1, False),
        ("rounds / run", b["runs"], ratio(budget["before"]["round"], b["runs"]), a["runs"], ratio(budget["after"]["round"], a["runs"]), 2, True),
        ("grants / run", b["runs"], ratio(budget["before"]["grant"], b["runs"]), a["runs"], ratio(budget["after"]["grant"], a["runs"]), 2, True),
        ("taux d'escalade", esc["before"]["runs"], ratio(esc["before"]["escalated"], esc["before"]["runs"]), esc["after"]["runs"], ratio(esc["after"]["escalated"], esc["after"]["runs"]), 2, True),
        ("taux fix-after", fixes["before"]["scored"], ratio(fixes["before"]["followed"], fixes["before"]["scored"]), fixes["after"]["scored"], ratio(fixes["after"]["followed"], fixes["after"]["scored"]), 2, True),
    ]

    out = []
    out.append(f"apex-health — coupure {periods.since.isoformat()}, fenêtre {args.days} j")
    out.append(f"AVANT = [{periods.start.isoformat()}, {periods.since.isoformat()})")
    out.append(f"APRÈS = [{periods.since.isoformat()}, {periods.now.isoformat()})")
    out.append(f"Sessions APEX : avant {b['sessions']} ({b['runs']} runs), après {a['sessions']} ({a['runs']} runs)")
    out.append(f"Sessions exclues (bancs, dépôts jetables) : {stats['excluded']}")
    out.append(f"Lignes illisibles ignorées : {stats['malformed']}")
    out.append(f"Dépôts : {', '.join(str(r) for r in repos) if repos else 'aucun'}")
    for warning in warnings:
        out.append(f"Avertissement : {warning}")
    out.append("")
    out.append(f"{'métrique':<24} | {'AVANT n':>7} | {'AVANT':>12} | {'APRÈS n':>7} | {'APRÈS':>12} | {'delta':>7}")
    out.append("-" * 85)
    for label, nb, vb, na, va, digits, _quality in rows:
        out.append(f"{label:<24} | {nb:>7} | {fmt(vb, digits):>12} | {na:>7} | {fmt(va, digits):>12} | {delta(vb, va):>7}")
    out.append("")
    out.append(f"fix-after : avant {fixes['before']['followed']}/{fixes['before']['scored']} suivis, après {fixes['after']['followed']}/{fixes['after']['scored']} suivis ; en attente (< 7 j) : {fixes['before']['pending'] + fixes['after']['pending']}")
    out.append("")

    drifting = []
    for label, nb, vb, na, va, _digits, quality in rows:
        if not quality:
            continue
        state = verdict(nb, vb, na, va)
        out.append(f"{label} : {state}")
        if state == "DÉRIVE":
            drifting.append(label)
    if drifting:
        out.append(f"VERDICT: DÉRIVE ({', '.join(drifting)})")
        return out, 2
    if min(b["runs"], a["runs"]) < MIN_N:
        out.append("VERDICT: insuffisant")
    else:
        out.append("VERDICT: ok")
    return out, 0


def main(argv):
    parser = argparse.ArgumentParser(
        prog="apex-health",
        description="Compare les runs APEX AVANT / APRÈS une date et signale une dérive de qualité (lecture seule, 0 appel modèle).",
    )
    parser.add_argument("--since", default=DEFAULT_SINCE, help=f"date de coupure YYYY-MM-DD ou ISO 8601, UTC (défaut {DEFAULT_SINCE})")
    parser.add_argument("--days", type=int, default=30, help="largeur de la fenêtre AVANT en jours (défaut 30)")
    parser.add_argument("--claude-dir", default="~/.claude", help="répertoire Claude Code (défaut ~/.claude)")
    parser.add_argument("--repo", action="append", default=[], help="dépôt git à analyser (répétable ; défaut : le répertoire courant s'il est un dépôt)")
    parser.add_argument("--now", default=None, help="horloge fixe ISO 8601 (tests)")
    args = parser.parse_args(argv)
    try:
        if args.days <= 0:
            raise UsageError("--days doit être > 0")
        since = parse_when(args.since, "--since")
        now = parse_when(args.now, "--now") if args.now else datetime.datetime.now(tz=UTC)
        lines, code = build_report(args, Periods(since, args.days, now))
    except UsageError as err:
        print(f"apex-health : {err}", file=sys.stderr)
        return 1
    except OSError as err:
        print(f"apex-health : erreur d'E/S : {err}", file=sys.stderr)
        return 1
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
