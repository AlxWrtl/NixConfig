"""ttw-ci-gate: classify a repo's GitHub Actions `run:` steps and run the
ones that are recognised local checks, so TTW validation covers what CI
checks.

Each `run:` step gets one class, first match wins:
  setup               it only installs/prepares (pnpm install, apt-get, an
                      echo to $GITHUB_ENV/OUTPUT/PATH/STEP_SUMMARY, ...)
  ci-only (<reason>)  shell, condition, secrets, expression, service,
                      deploy, database, container, browser, github,
                      privileged, or unrecognised (not on the allowlist)
  local               every command in it is an allowlisted check
Job state: every step after a database / service / secrets / container step
of the same job is `ci-only (after <reason>)`: it depends on that state.
A job env holding a secret does not by itself make a step ci-only.

--run executes the local steps one at a time, deduplicated on (run text,
working directory, literal env), each as `bash -eo pipefail -c <run>` in its
own process group, killed when the step ends or times out (rc 124).
No network, no git of its own.
"""
import argparse
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile

import yaml

PROG = "ttw-ci-gate"
DEFAULT_TIMEOUT = 600

# A step classed ci-only for one of these leaves state the job's later
# steps depend on (a migrated DB, a secret-fetched file, a built image).
AFTER_REASONS = ("database", "service", "secrets", "container")

SETUP_CMD = re.compile(
    r"^(sudo\s+apt-get|apt-get|pnpm\s+install|npm\s+ci|npm\s+install|yarn\s+install"
    r"|bun\s+install|pip\s+install|brew\s+install|corepack|cargo\s+fetch|git\s+config)(\s|$)"
)
GITHUB_FILE_WRITE = re.compile(
    r"^(echo|printf|cat)\b.*>>?\s*\"?\$\{?GITHUB_(ENV|OUTPUT|PATH|STEP_SUMMARY)\}?\"?\s*$"
)

# Order matters: the first reason that matches is printed.
WORD_REASONS = [
    ("deploy", re.compile(
        r"(?<![-\w])(deploy|publish|release)\b|docker\s+push|wrangler\s+deploy|gh\s+release")),
    ("database", re.compile(
        r"db:|\bmigrate\b|\bpsql\b|\bpg_dump\b|DATABASE_URL|\bseed\b")),
    ("container", re.compile(r"\b(docker|podman|kubectl|colima)\b")),
    ("browser", re.compile(r"\b(playwright|cypress|e2e|lighthouse|lhci)\b")),
    ("github", re.compile(
        r"(^|[\s;&|(])gh\s|GITHUB_TOKEN|curl[^\n]*api\.github\.com")),
    ("privileged", re.compile(r"\bsudo\b")),
]

# --- allowlist ---------------------------------------------------------------
# Flags that make a check write: never local.
WRITE_FLAGS = {"--write", "--fix", "-w", "--watch", "--watchAll"}
# A banned word counts only at the start of a script-name segment (split on
# : - _ .): `test:serve` and `dev-server` are refused, `test:reservedx` is not.
BAD_SCRIPT_WORD = re.compile(
    r"(^|[:_.-])(deploy|release|publish|db:|migrate|seed|start|dev|serve|preview|watch)")
# Package-manager built-ins that `pm <word>` would run instead of a script.
PM_BUILTINS = {
    "add", "audit", "bin", "cache", "config", "create", "dedupe", "deploy",
    "dlx", "env", "exec", "fetch", "i", "import", "init", "install", "link",
    "patch", "patch-commit", "pack", "prune", "publish", "rebuild", "remove",
    "rm", "root", "set", "setup", "store", "un", "uninstall", "unlink",
    "up", "update", "upgrade", "version", "why", "x",
}
CHECK_TOOLS = {"tsc", "eslint", "vitest", "jest", "svelte-check"}
# Tool -> the subcommand/flag it must carry to be a check.
CHECK_TOOLS_WITH = {
    "prettier": "--check",
    "biome": "check",
    "react-router": "typegen",
    "astro": "check",
}
FD_DUP = re.compile(r"\s*[12]?>&[12]")


def ok_script(name):
    if not name or name.startswith("-") or name in PM_BUILTINS:
        return False
    return not BAD_SCRIPT_WORD.search(name)


def ok_tool(args):
    if not args:
        return False
    tool, rest = args[0], args[1:]
    if tool in CHECK_TOOLS:
        return not (tool == "vitest" and rest[:1] == ["watch"])
    need = CHECK_TOOLS_WITH.get(tool)
    if need is None:
        return False
    if need.startswith("-"):
        return need in rest
    return rest[:1] == [need]


def ok_path_script(path):
    return path.startswith("scripts/") and ".." not in path.split("/")


def ok_command(seg):
    """True when one simple command (no pipe/list operator) is a check."""
    seg = FD_DUP.sub("", seg).strip()
    if not seg or seg.startswith("#"):
        return True
    if any(c in seg for c in "<>`") or "$(" in seg:
        return False
    try:
        t = shlex.split(seg, comments=True)
    except ValueError:
        return False
    if not t:
        return True
    if any(a in WRITE_FLAGS or a.startswith(("--fix=", "--write=")) for a in t):
        return False
    cmd, args = t[0], t[1:]
    if cmd in ("echo", "printf"):
        return True
    if "$" in seg:
        return False
    if cmd == "set":
        return all(re.match(r"^([-+][a-zA-Z]+|[a-z]+)$", a) for a in args)
    if cmd == "cd":
        if len(args) != 1 or args[0].startswith(("/", "~", "-")):
            return False
        return ".." not in args[0].split("/")
    if cmd == "pnpm":
        while args and args[0] in ("-s", "--silent"):
            args = args[1:]
        if args[:1] == ["run"]:
            return len(args) > 1 and ok_script(args[1])
        if args[:1] == ["exec"]:
            return ok_tool(args[1:])
        return bool(args) and ok_script(args[0])
    if cmd == "npm":
        if args[:1] == ["run"]:
            return len(args) > 1 and ok_script(args[1])
        if args[:1] == ["exec"]:
            return ok_tool(args[1:])
        return args[:1] == ["test"]
    if cmd == "yarn":
        if args[:1] == ["run"]:
            return len(args) > 1 and ok_script(args[1])
        return bool(args) and ok_script(args[0])
    if cmd == "bun":
        return args[:1] == ["run"] and len(args) > 1 and ok_script(args[1])
    if cmd == "npx":
        return ok_tool(args)
    if cmd == "node":
        if args[:2] == ["--import", "tsx"]:
            args = args[2:]
        return bool(args) and ok_path_script(args[0])
    if cmd == "tsx":
        return bool(args) and ok_path_script(args[0])
    if cmd == "cargo":
        if args[:1] == ["fmt"]:
            return "--check" in args
        return args[:1] in (["check"], ["test"], ["clippy"], ["build"])
    if cmd == "go":
        return args[:1] in (["test"], ["vet"], ["build"])
    if cmd in ("python", "python3"):
        return args[:2] == ["-m", "pytest"]
    if cmd in ("pytest", "mypy"):
        return True
    if cmd == "ruff":
        return args[:1] == ["check"]
    if cmd == "nix":
        return args[:2] == ["flake", "check"] or args[:1] == ["build"]
    if cmd == "make":
        return args[:1] in (["check"], ["test"], ["lint"])
    return False


def is_allowlisted(run):
    """Every command of the run text is a recognised check."""
    text = re.sub(r"\\\n", " ", run)
    seen = False
    for line in text.splitlines():
        line = FD_DUP.sub("", line).strip()
        if not line or line.startswith("#"):
            continue
        if re.search(r"(?<!&)&(?!&)", line):
            return False  # a backgrounded command: its result is never read
        for seg in re.split(r"&&|\|\||[;&|]", line):
            if not ok_command(seg):
                return False
            seen = True
    return seen


# --- classification ----------------------------------------------------------
def flat(value):
    """All scalar values of a step's env/with mapping, one per line."""
    if isinstance(value, dict):
        return "\n".join(flat(v) for v in value.values())
    if isinstance(value, list):
        return "\n".join(flat(v) for v in value)
    if value is None:
        return ""
    return str(value)


def is_setup(run):
    lines = [ln.strip() for ln in run.splitlines()]
    lines = [ln for ln in lines if ln and not ln.startswith("#")]
    if not lines:
        return False
    for line in lines:
        for seg in re.split(r"&&|\|\||;", line):
            seg = seg.strip()
            if not seg:
                continue
            if SETUP_CMD.match(seg) or GITHUB_FILE_WRITE.match(seg):
                continue
            return False
    return True


def classify(run, step, job):
    """The step's own class: `setup`, `local` or `ci-only (<reason>)`."""
    if is_setup(run):
        return "setup"
    shell = str(step.get("shell") or "bash").split()
    if not shell or shell[0] not in ("bash", "sh"):
        return "ci-only (shell)"
    if "if" in step:
        return "ci-only (condition)"
    extra = "\n".join([flat(step.get("env")), flat(step.get("with"))])
    text = run + "\n" + extra
    if "secrets." in text:
        return "ci-only (secrets)"
    if "${{" in text:
        return "ci-only (expression)"
    if job.get("services"):
        return "ci-only (service)"
    for reason, rx in WORD_REASONS:
        if rx.search(text):
            return "ci-only (%s)" % reason
    if not is_allowlisted(run):
        return "ci-only (unrecognised)"
    return "local"


def after_reason(cls):
    m = re.match(r"^ci-only \((\w+)\)$", cls)
    if m and m.group(1) in AFTER_REASONS:
        return m.group(1)
    return None


# --- workflow walk -------------------------------------------------------------
def one_line(text):
    return re.sub(r"[\t\r\n]+", " ", text).strip()


def first_line(run):
    for line in run.splitlines():
        if line.strip():
            return one_line(line)
    return "-"


def run_wd(node):
    defaults = node.get("defaults") if isinstance(node, dict) else None
    if isinstance(defaults, dict) and isinstance(defaults.get("run"), dict):
        return defaults["run"].get("working-directory")
    return None


def env_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return "" if v is None else str(v)


def literal_env(*layers):
    """Workflow < job < step env, values holding `${{` dropped."""
    out = {}
    for layer in layers:
        if not isinstance(layer, dict):
            continue
        for k, v in layer.items():
            val = env_value(v)
            if "${{" in val:
                out.pop(str(k), None)
            else:
                out[str(k)] = val
    return out


def minutes(*values):
    for v in values:
        if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0:
            return v * 60
    return None


def workflow_files(repo):
    wdir = os.path.join(repo, ".github", "workflows")
    if not os.path.isdir(wdir):
        return wdir, []
    names = sorted(
        n for n in os.listdir(wdir)
        if n.endswith((".yml", ".yaml")) and os.path.isfile(os.path.join(wdir, n))
    )
    return wdir, names


class Unparsable(Exception):
    pass


def collect(repo):
    """Every listed run step as a dict, in file/job/step order."""
    wdir, names = workflow_files(repo)
    steps = []
    for name in names:
        path = os.path.join(wdir, name)
        try:
            with open(path, encoding="utf-8") as f:
                doc = yaml.safe_load(f)
        except (yaml.YAMLError, UnicodeDecodeError) as e:
            raise Unparsable("%s: unparsable: %s" % (path, one_line(str(e))))
        jobs = doc.get("jobs") if isinstance(doc, dict) else None
        if not isinstance(jobs, dict):
            continue
        for job_id, job in jobs.items():
            if not isinstance(job, dict) or not isinstance(job.get("steps"), list):
                continue
            job_wd = run_wd(job) or run_wd(doc)
            after = None
            for index, step in enumerate(job["steps"], 1):
                if not isinstance(step, dict):
                    continue
                run = step.get("run")
                if not isinstance(run, str) or not run.strip():
                    continue
                own = classify(run, step, job)
                cls = "ci-only (after %s)" % after if after else own
                if after is None:
                    after = after_reason(own)
                wd = step.get("working-directory") or job_wd
                steps.append({
                    "file": name,
                    "job": str(job_id),
                    "name": one_line(str(step.get("name") or "")) or "#%d" % index,
                    "run": run,
                    "class": cls,
                    "cwd": os.path.normpath(os.path.join(repo, str(wd))) if wd else repo,
                    "env": literal_env(doc.get("env"), job.get("env"), step.get("env")),
                    "timeout": minutes(step.get("timeout-minutes"), job.get("timeout-minutes")),
                })
    return names, steps


def dedup_key(step):
    """Two steps are the same run when text, directory and literal env match."""
    return (step["run"], step["cwd"], tuple(sorted(step["env"].items())))


def list_line(s):
    return "%s\t%s:%s\t%s\t%s" % (s["class"], s["file"], s["job"], s["name"], first_line(s["run"]))


# --- execution -----------------------------------------------------------------
def kill_group(pgid):
    try:
        os.killpg(pgid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def run_step(s, log_path, timeout):
    env = dict(os.environ)
    env["CI"] = "true"
    env.update(s["env"])
    with open(log_path, "w") as log:
        try:
            proc = subprocess.Popen(
                ["bash", "-eo", "pipefail", "-c", s["run"]],
                cwd=s["cwd"], env=env, stdin=subprocess.DEVNULL,
                stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
            )
        except OSError as e:
            log.write("%s: could not start the step in %s: %s\n" % (PROG, s["cwd"], e))
            return 127
        try:
            rc = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            kill_group(proc.pid)
            proc.wait()
            log.write("\n%s: timed out after %ss, process group killed\n" % (PROG, timeout))
            return 124
        kill_group(proc.pid)
    return rc


def make_log_dir(path):
    if not path:
        return tempfile.mkdtemp(prefix=PROG + "-")
    path = os.path.abspath(path)
    if os.path.exists(path) and not os.path.isdir(path):
        raise RuntimeError("--log-dir %s is not a directory" % path)
    os.makedirs(path, exist_ok=True)
    return path


def gate(args):
    repo = os.path.abspath(args.repo)
    try:
        names, steps = collect(repo)
    except Unparsable as e:
        print("%s: %s" % (PROG, e), file=sys.stderr)
        return 2
    if not names:
        print("%s: no workflows" % PROG)
        return 0

    local = [s for s in steps if s["class"] == "local"]
    setup = sum(1 for s in steps if s["class"] == "setup")
    ci_only = sum(1 for s in steps if s["class"].startswith("ci-only"))

    if not args.run:
        for s in steps:
            print(list_line(s))
        print("%s: local=%d ci-only=%d setup=%d" % (PROG, len(local), ci_only, setup))
        return 0

    log_dir = make_log_dir(args.log_dir)
    for s in steps:
        if s["class"].startswith("ci-only"):
            print(list_line(s))
    seen = set()
    passed = failed = 0
    for i, s in enumerate(local):
        key = dedup_key(s)
        if key in seen:
            continue
        seen.add(key)
        slug = re.sub(r"[^A-Za-z0-9_.-]+", "_", "%s-%s" % (s["file"], s["job"]))
        log_path = os.path.join(log_dir, "%03d-%s.log" % (i + 1, slug))
        rc = run_step(s, log_path, s["timeout"] or args.timeout)
        if rc == 0:
            passed += 1
        else:
            failed += 1
        print("%s rc=%d\t%s:%s\t%s\tlog=%s" % (
            "PASS" if rc == 0 else "FAIL", rc, s["file"], s["job"], s["name"], log_path))
        sys.stdout.flush()
    print("%s: run local=%d pass=%d fail=%d ci-only=%d setup=%d" % (
        PROG, len(local), passed, failed, ci_only, setup))
    return 1 if failed else 0


def main(argv):
    """Exit code: 0 ok, 1 a local step failed, 2 unparsable or internal error."""
    ap = argparse.ArgumentParser(
        prog=PROG,
        description="List the GitHub Actions run steps of a repo by class (local / setup / ci-only (reason)); --run executes the local ones.",
    )
    ap.add_argument("--repo", default=".", help="repository root (default: .)")
    ap.add_argument("--run", action="store_true", help="execute the local steps")
    ap.add_argument("--log-dir", help="where step logs go (default: a new temp dir)")
    ap.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT,
                    help="per-step timeout in seconds when the workflow sets no timeout-minutes (default: 600)")
    args = ap.parse_args(argv)
    try:
        return gate(args)
    except Exception as e:
        print("%s: error: %s: %s" % (PROG, type(e).__name__, e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
