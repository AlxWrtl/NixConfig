# Runtime check for ttw-ci-gate (home/claude-code/ttw-ci-gate.nix): the BUILT
# tool reads workflow fixtures written in throwaway repos under $TMPDIR and
# must print the exact lines and exit codes of its contract.
#
#   AC1  the package's bin holds exactly ttw-ci-gate, executable; --help
#        exits 0 and names it.
#   AC2  no .github/workflows, an empty one, one holding only README.md
#        -> stdout `ttw-ci-gate: no workflows`, exit 0.
#   AC3  unparsable bad.yml -> exit 2, stderr
#        `ttw-ci-gate: …bad.yml: unparsable: <reason>`.
#   AC4  `uses:` steps are not listed.
#   AC5  pnpm install / sudo apt-get / `>> $GITHUB_OUTPUT` -> setup.
#   AC6  job env holds `''${{ secrets.X }}`, step runs pnpm typecheck -> local.
#   AC7  one job per ci-only reason, exact `ci-only (<reason>)` printed.
#   AC8  list format: <class>\t<file>:<job>\t<name or #index>\t<first run
#        line>, last line the counts; a.yaml before b.yml; README.md ignored;
#        the same output with no --repo from inside the repo.
#   AC9  --run all green: two local steps (one multi-line `run: |`) PASS,
#        exact last line, exit 0; the ci-only and setup steps leave no marker.
#   AC10 --run, a check exiting 3 -> FAIL rc=3, the next step still runs,
#        exit 1, its log= file holds its output.
#   AC11 --run dedups an identical step across jobs and workflows, honours
#        step working-directory and job defaults.run.working-directory; a
#        failing check piped into a passing one FAILs (pipefail).
#   AC12 a step's literal env reaches its command.
#   AC16 allowlist: recognised checks are local; git clean/reset/push,
#        semantic-release, npm version, curl | sh, --write/--fix/-w, sleep,
#        dev/start/watch/serve/preview scripts, a pipe into sh, an echo to a
#        file, an absolute cd, a trailing rm are not.
#   AC25 a banned script word counts only at the start of a name segment
#        (split on : - _ .): test:reservedmanufacturer, test:predeployment
#        local; serve, test:serve, dev-server unrecognised; db:x, migrate:up,
#        release-notes ci-only (their database / deploy reason comes first).
#   AC17 job state: after a database / secrets / container step, the job's
#        later steps are `ci-only (after <reason>)`; earlier steps keep their
#        class; a deploy step does not propagate.
#   AC18 --timeout 2: a check that hangs -> FAIL rc=124 within seconds, the
#        next step runs, the hung check's background child is dead.
#   AC19 dedup key = run text + working directory + literal env.
#   AC20 working directory step > job > workflow defaults; env workflow < job
#        < step, `''${{` values dropped; CI=true.
#   AC21 shell: pwsh -> shell, if: -> condition, `''${{` in step env/with ->
#        expression, an empty or non-string run is not listed; an internal
#        error (--log-dir is a file) -> exit 2, `ttw-ci-gate: error:`.
#   AC22 an unnamed step is `#<position in its job's steps:>` (uses: steps
#        count), in list and run lines alike.
#
# Every executed step is a recognised check (`pnpm <script>`) backed by the
# fake pnpm below, which does the shell work keyed on its script name.
#
# Canaries (AC13, AC24). Each mutant is a copy of the BUILT script, run
# through a small runner (runpy, same interpreter + PyYAML). It must make its
# target case fail, while AC2 and AC3 still pass (a mutant that no longer runs
# is broken, not killed). A survivor fails the check.
#   M1  job-env           runner merges each job's env into its steps' env
#                         (classification per job, not per step)  -> AC6
#   M2  drop-reason       `playwright` renamed in the script       -> AC7:browser
#   M3  no-dedup          runner makes every run text unique       -> AC11:dedup
#   M4  no-pipefail       `pipefail` renamed `errexit`             -> AC11:pipefail
#   M5  exit0             runner reports exit 1 as 0               -> AC10:exit
#   M6  run-ci-only       `== "local"` / `!= "local"` turned into
#                         `!= "setup"` / `== "setup"`              -> AC9:ci-only-ran
#   M7  no-job-state      module-level AFTER_REASONS emptied       -> AC17
#   M8  no-timeout        runner drops the timeout of Popen.wait /
#                         communicate (subprocess.run uses them)   -> AC18:timeout
#   M9  text-key          dedup_key(step) cut to its first item,
#                         the run text                             -> AC19
#   M10 unrecognised-local the literal "ci-only (unrecognised)"
#                         rewritten "local"                        -> AC16:GitClean
# A text mutant whose anchor is absent, a runner anchor (AFTER_REASONS,
# dedup_key, main) that is missing, or a runner swap that never fired, fails
# the build: the mutant would equal the source. Control M0 (runner, script
# unchanged) must pass every case, or the runner itself is what kills.
#
# Offline: no network, no git.
{ pkgs }:

let
  pkg = (import ../home/claude-code/ttw-ci-gate.nix { inherit pkgs; }).ttwCiGatePkg;
  py = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  pnpmShim = pkgs.writeShellScriptBin "pnpm" ''
    case "$1" in
    install) touch setup.ran ;;
    one) echo one > one.out ;;
    two-a) echo a > two.out ;;
    two-b) echo b >> two.out ;;
    upload) touch ci-only.ran ;;
    boom) echo boom-output; exit 3 ;;
    after) echo after > after.out ;;
    count) echo once >> dedup.count ;;
    wd-step) pwd > step-wd.txt ;;
    wd-job) pwd > job-wd.txt ;;
    fails) exit 1 ;;
    sink) cat > /dev/null ;;
    envcheck) test "$FOO" = bar ;;
    envdump)
      printf 'WF=%s JOB=%s SHARED=%s STEP=%s CI=%s DROP=%s\n' \
        "''${WF-unset}" "''${JOB-unset}" "''${SHARED-unset}" "''${STEP-unset}" "''${CI-unset}" "''${DROP-unset}" > env.out
      ;;
    wd-a) pwd > wd-a.txt ;;
    wd-b) pwd > wd-b.txt ;;
    stamp) echo x >> stamp.out ;;
    hang)
      sleep 20 &
      echo $! > hang.pid
      wait
      ;;
    *) echo "fake pnpm: unknown script '$1'" >&2; exit 64 ;;
    esac
  '';
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.coreutils
    pkgs.diffutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.bash
  ];
  casePath = pkgs.lib.makeBinPath [
    pnpmShim
    pkgs.coreutils
    pkgs.bash
  ];

  runner = pkgs.writeText "ttw-ci-gate-runner.py" ''
    """Runs a copy of the built ttw-ci-gate in-process, one behaviour swapped
    by MUT_MODE:
      none          unchanged (control: must pass every case)
      job-env       each job's env merged into each of its steps' env
      no-dedup      each run text made unique (a numbered trailing comment)
      exit0         an exit status of 1 reported as 0
      no-timeout    the timeout of Popen.wait / Popen.communicate dropped
      no-job-state  module-level AFTER_REASONS emptied
      text-key      dedup_key(step) cut to its first item (the run text)
    The last two load the script as a module and call its main(argv).
    MUT_HIT gets a line each time the swap changes something. MUT_PROBE=1:
    check the module anchors and exit."""
    import os
    import runpy
    import subprocess
    import sys

    import yaml

    MODE = os.environ.get("MUT_MODE", "none")
    HIT = os.environ.get("MUT_HIT", "")
    MODULE_MODES = ("no-job-state", "text-key")
    seq = [0]


    def mark():
        if HIT:
            with open(HIT, "a") as f:
                f.write(MODE + "\n")


    def swap(doc):
        jobs = doc.get("jobs") if isinstance(doc, dict) else None
        if not isinstance(jobs, dict):
            return doc
        for job in jobs.values():
            steps = job.get("steps") if isinstance(job, dict) else None
            if not isinstance(steps, list):
                continue
            for step in steps:
                if not isinstance(step, dict):
                    continue
                if MODE == "job-env" and isinstance(job.get("env"), dict):
                    env = dict(job["env"])
                    env.update(step.get("env") or {})
                    step["env"] = env
                    mark()
                if MODE == "no-dedup" and isinstance(step.get("run"), str):
                    seq[0] += 1
                    step["run"] = step["run"].rstrip("\n") + "\n# mutant-%d\n" % seq[0]
                    mark()
        return doc


    if MODE in ("job-env", "no-dedup"):
        real_load = yaml.load
        real_load_all = yaml.load_all

        # safe_load / full_load call the module-level load, so this covers them.
        def load(stream, Loader):
            return swap(real_load(stream, Loader))

        def load_all(stream, Loader):
            for doc in real_load_all(stream, Loader):
                yield swap(doc)

        yaml.load = load
        yaml.load_all = load_all
    elif MODE == "no-timeout":
        real_wait = subprocess.Popen.wait
        real_communicate = subprocess.Popen.communicate

        def wait(self, timeout=None):
            if timeout is not None:
                mark()
            return real_wait(self)

        def communicate(self, input=None, timeout=None):
            if timeout is not None:
                mark()
            return real_communicate(self, input)

        subprocess.Popen.wait = wait
        subprocess.Popen.communicate = communicate
    elif MODE not in ("none", "exit0") + MODULE_MODES:
        sys.exit("runner: unknown MUT_MODE " + MODE)

    script = sys.argv[1]
    sys.argv = sys.argv[1:]
    real = None
    if MODE in MODULE_MODES:
        g = runpy.run_path(script, run_name="ttw_ci_gate_mutant")
        if not callable(g.get("main")):
            sys.exit("runner: anchor main(argv) absent from " + script)
        # run_path returns a copy: patch the dict the functions really read.
        real = g["main"].__globals__
        if MODE == "no-job-state":
            if "AFTER_REASONS" not in real:
                sys.exit("runner: anchor AFTER_REASONS absent from " + script)
            real["AFTER_REASONS"] = ()
            mark()
        else:
            if not callable(real.get("dedup_key")):
                sys.exit("runner: anchor dedup_key(step) absent from " + script)
            whole_key = real["dedup_key"]

            def text_key(step):
                mark()
                return (whole_key(step)[0],)

            real["dedup_key"] = text_key
        if os.environ.get("MUT_PROBE"):
            print("runner: %s anchors present" % MODE)
            sys.exit(0)
    code = 0
    try:
        if real is not None:
            code = real["main"](sys.argv[1:])
        else:
            runpy.run_path(script, run_name="__main__")
    except SystemExit as e:
        code = e.code
    if MODE == "exit0" and code == 1:
        mark()
        code = 0
    sys.stdout.flush()
    sys.exit(code)
  '';

  mutate = pkgs.writeText "ttw-ci-gate-mutate.py" ''
    """mutate MODE SRC DST: DST = SRC with one text rewrite. Exits non-zero
    when SRC is not a Python script or the anchor is absent: the mutant
    would equal the source and its kill would prove nothing."""
    import re
    import sys

    mode, src, dst = sys.argv[1:4]
    text = open(src).read()
    first = text.split("\n", 1)[0]
    if not (first.startswith("#!") and "python" in first):
        sys.exit("mutate: %s is not a Python script (first line %r): mutants would test a wrapper" % (src, first))


    def flip(m):
        op = "!=" if m.group(1) == "==" else "=="
        return op + m.group(2) + m.group(3) + "setup" + m.group(3)


    if mode == "none":
        out, n = text, 1
    elif mode == "drop-reason":
        out, n = re.subn("playwright", "playwrighX", text)
    elif mode == "no-pipefail":
        out, n = re.subn("pipefail", "errexit", text)
    elif mode == "run-ci-only":
        out, n = re.subn(r"""(==|!=)(\s*)(["'])local\3""", flip, text)
    elif mode == "unrecognised-local":
        out, n = re.subn(r"""(["'])ci-only \(unrecognised\)\1""", '"local"', text)
    else:
        sys.exit("mutate: unknown mode " + mode)
    if n == 0 or (mode != "none" and out == text):
        sys.exit("mutate: %s anchor absent from %s: the mutant would equal the source" % (mode, src))
    with open(dst, "w") as f:
        f.write(out)
    print("mutate: %s rewrote %d site(s)" % (mode, n))
  '';

  fxReadme = pkgs.writeText "README.md" ''
    Workflows live here.
  '';

  fxBad = pkgs.writeText "bad.yml" ''
    name: bad
    jobs: [unclosed
  '';

  fxUses = pkgs.writeText "uses.yml" ''
    name: ci
    on: push
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - name: Lint
            run: make lint
          - uses: actions/setup-node@v4
            with:
              node-version: 22
  '';

  fxSetup = pkgs.writeText "setup.yml" ''
    jobs:
      prep:
        runs-on: ubuntu-latest
        steps:
          - name: Install
            run: pnpm install --frozen-lockfile
          - name: Apt
            run: sudo apt-get install -y x
          - name: Output
            run: echo "k=v" >> $GITHUB_OUTPUT
  '';

  fxStatic = pkgs.writeText "static.yml" ''
    jobs:
      static:
        runs-on: ubuntu-latest
        env:
          X: ''${{ secrets.X }}
        steps:
          - name: Typecheck
            run: pnpm typecheck
  '';

  # One job per reason: a database / secrets / container / service step
  # turns the rest of its job ci-only (AC17), which would mask the next reason.
  fxReasons = pkgs.writeText "reasons.yml" ''
    jobs:
      secrets:
        runs-on: ubuntu-latest
        steps:
          - name: Secret
            env:
              T: ''${{ secrets.T }}
            run: make check
      expression:
        runs-on: ubuntu-latest
        steps:
          - name: Expr
            run: echo ''${{ matrix.os }}
      service:
        runs-on: ubuntu-latest
        services:
          postgres:
            image: postgres:16
        steps:
          - name: WithService
            run: make check
      deploy:
        runs-on: ubuntu-latest
        steps:
          - name: Ship
            run: pnpm run deploy
      database:
        runs-on: ubuntu-latest
        steps:
          - name: Schema
            run: pnpm db:migrate
      container:
        runs-on: ubuntu-latest
        steps:
          - name: Image
            run: docker build .
      browser:
        runs-on: ubuntu-latest
        steps:
          - name: Browser
            run: pnpm exec playwright test
      github:
        runs-on: ubuntu-latest
        steps:
          - name: Hub
            run: gh pr view 1
      privileged:
        runs-on: ubuntu-latest
        steps:
          - name: Root
            run: sudo make
  '';

  fxListA = pkgs.writeText "a.yaml" ''
    jobs:
      x:
        runs-on: ubuntu-latest
        steps:
          - run: make lint
          - name: Install
            run: pnpm install --frozen-lockfile
  '';

  fxListB = pkgs.writeText "b.yml" ''
    jobs:
      y:
        runs-on: ubuntu-latest
        steps:
          - name: Multi
            run: |
              pnpm lint
              pnpm test
          - name: Image
            run: docker build .
  '';

  fxRun = pkgs.writeText "run.yml" ''
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - name: Install
            run: pnpm install --frozen-lockfile
          - name: One
            run: pnpm one
          - run: |
              pnpm two-a
              pnpm two-b
          - name: Upload
            env:
              T: ''${{ secrets.T }}
            run: pnpm upload
  '';

  fxFail = pkgs.writeText "fail.yml" ''
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - name: Boom
            run: pnpm boom
          - name: After
            run: pnpm after
  '';

  fxDedupCi = pkgs.writeText "ci.yml" ''
    jobs:
      a:
        runs-on: ubuntu-latest
        steps:
          - name: Count
            run: pnpm count
          - name: StepWd
            working-directory: sub
            run: pnpm wd-step
          - name: Pipe
            run: pnpm fails | pnpm sink
      b:
        runs-on: ubuntu-latest
        defaults:
          run:
            working-directory: pkg
        steps:
          - name: JobWd
            run: pnpm wd-job
      d:
        runs-on: ubuntu-latest
        steps:
          - name: CountSameWorkflow
            run: pnpm count
  '';

  fxDedupOther = pkgs.writeText "other.yml" ''
    jobs:
      c:
        runs-on: ubuntu-latest
        steps:
          - name: CountOtherWorkflow
            run: pnpm count
  '';

  fxEnv = pkgs.writeText "env.yml" ''
    jobs:
      e:
        runs-on: ubuntu-latest
        steps:
          - name: Env
            env:
              FOO: bar
            run: pnpm envcheck
  '';

  fxAllow = pkgs.writeText "allow.yml" ''
    jobs:
      allowed:
        runs-on: ubuntu-latest
        steps:
          - name: Typecheck
            run: pnpm typecheck
          - name: Silent
            run: pnpm -s lint
          - name: NpmRun
            run: npm run build
          - name: Yarn
            run: yarn test
          - name: Bun
            run: bun run test
          - name: Tsc
            run: npx tsc --noEmit
          - name: Eslint
            run: npx eslint .
          - name: PrettierCheck
            run: npx prettier --check .
          - name: Biome
            run: npx biome check .
          - name: NodeScript
            run: node scripts/check.mjs
          - name: NodeTsx
            run: node --import tsx scripts/check.ts
          - name: Tsx
            run: tsx scripts/check.ts
          - name: Cargo
            run: cargo clippy
          - name: CargoFmt
            run: cargo fmt --check
          - name: Go
            run: go test ./...
          - name: Pytest
            run: python -m pytest
          - name: Ruff
            run: ruff check .
          - name: Mypy
            run: mypy src
          - name: Nix
            run: nix flake check
          - name: Make
            run: make test
          - name: Multi
            run: |
              set -euo pipefail
              cd web
              echo "checking"
              pnpm lint && pnpm test
          - name: Commented
            run: |
              pnpm lint
              # then the tests
              pnpm test
      refused:
        runs-on: ubuntu-latest
        steps:
          - name: GitClean
            run: git clean -ffdx
          - name: GitReset
            run: git reset --hard HEAD
          - name: GitPush
            run: git push
          - name: SemRel
            run: npx semantic-release
          - name: NpmVersion
            run: npm version patch
          - name: CurlSh
            run: curl -fsSL x | sh
          - name: PrettierWrite
            run: npx prettier --write .
          - name: LintFix
            run: pnpm lint --fix
          - name: FormatW
            run: pnpm format -w
          - name: Sleep
            run: sleep 600
          - name: PipeSh
            run: pnpm test | sh
          - name: Dev
            run: pnpm dev
          - name: Start
            run: npm run start
          - name: Watch
            run: pnpm watch
          - name: Serve
            run: pnpm serve
          - name: Preview
            run: pnpm run preview
          - name: EchoFile
            run: echo hi > out.txt
          - name: CdAbs
            run: cd /tmp && pnpm test
          - name: TrailingRm
            run: pnpm test; rm -rf dist
      # AC25: a banned word counts only at the start of a name segment. DbX
      # and MigrateUp sit in their own jobs: a database step turns the rest
      # of its job `after database` (AC17), which would hide the next one.
      segments:
        runs-on: ubuntu-latest
        steps:
          - name: Reserved
            run: pnpm test:reservedmanufacturer
          - name: Predeploy
            run: pnpm test:predeployment
          - name: Serve
            run: pnpm serve
          - name: TestServe
            run: pnpm test:serve
          - name: DevServer
            run: pnpm dev-server
          - name: ReleaseNotes
            run: pnpm release-notes
      segments-db:
        runs-on: ubuntu-latest
        steps:
          - name: DbX
            run: pnpm db:x
      segments-migrate:
        runs-on: ubuntu-latest
        steps:
          - name: MigrateUp
            run: pnpm migrate:up
  '';

  fxState = pkgs.writeText "state.yml" ''
    jobs:
      db:
        runs-on: ubuntu-latest
        steps:
          - name: Before
            run: pnpm lint
          - name: Migrate
            run: pnpm db:migrate
          - name: After
            run: pnpm test:x
      sec:
        runs-on: ubuntu-latest
        steps:
          - name: Fetch
            env:
              T: ''${{ secrets.T }}
            run: pnpm fetch-data
          - name: Then
            run: pnpm lint
      img:
        runs-on: ubuntu-latest
        steps:
          - name: Build
            run: docker build .
          - name: Check
            run: pnpm test
      dep:
        runs-on: ubuntu-latest
        steps:
          - name: Ship
            run: pnpm run deploy
          - name: Lint
            run: pnpm lint
  '';

  fxTimeout = pkgs.writeText "t.yml" ''
    jobs:
      t:
        runs-on: ubuntu-latest
        steps:
          - name: Hang
            run: pnpm hang
          - name: Next
            run: pnpm after
  '';

  fxKey = pkgs.writeText "key.yml" ''
    jobs:
      k:
        runs-on: ubuntu-latest
        steps:
          - name: A
            working-directory: a
            run: pnpm stamp
          - name: B
            working-directory: b
            run: pnpm stamp
          - name: C
            working-directory: a
            env:
              V: one
            run: pnpm stamp
          - name: D
            working-directory: a
            run: pnpm stamp
  '';

  fxDefaults = pkgs.writeText "defaults.yml" ''
    defaults:
      run:
        working-directory: app
    env:
      WF: w
      SHARED: wf
    jobs:
      e:
        runs-on: ubuntu-latest
        env:
          JOB: j
          SHARED: job
          DROP: ''${{ github.sha }}
        steps:
          - name: Dump
            env:
              STEP: s
            run: pnpm envdump
      jobwd:
        runs-on: ubuntu-latest
        defaults:
          run:
            working-directory: lib
        steps:
          - name: JobOverWf
            run: pnpm wd-a
          - name: StepOverJob
            working-directory: tools
            run: pnpm wd-b
  '';

  fxGuards = pkgs.writeText "guards.yml" ''
    jobs:
      g:
        runs-on: ubuntu-latest
        steps:
          - name: Pwsh
            shell: pwsh
            run: make test
          - name: Bash
            shell: bash
            run: make lint
          - name: Sh
            shell: sh
            run: make lint
          - name: Cond
            if: github.event_name == 'push'
            run: make check
          - name: ExprEnv
            env:
              V: ''${{ matrix.v }}
            run: make test
          - name: ExprWith
            with:
              a: ''${{ matrix.v }}
            run: make test
          - name: Empty
            run: ""
          - name: NotString
            run: [make, test]
          - name: Last
            run: make lint
  '';

  fxIndex = pkgs.writeText "idx.yml" ''
    jobs:
      i:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - run: make lint
          - name: Named
            run: make test
          - run: make check
      j:
        runs-on: ubuntu-latest
        steps:
          - run: pnpm lint
  '';
in
pkgs.runCommand "ttw-ci-gate-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR"

  # AC1 (package shape, real build only).
  [ -x ${pkg}/bin/ttw-ci-gate ] || { echo "ttw-ci-gate: AC1 FAILED — ${pkg}/bin/ttw-ci-gate is missing or not executable"; exit 1; }
  bins="$(ls -A ${pkg}/bin | tr '\n' ' ')"
  [ "$bins" = "ttw-ci-gate " ] || { echo "ttw-ci-gate: AC1 FAILED — bin/ holds '$bins', want exactly 'ttw-ci-gate'"; exit 1; }
  echo "ttw-ci-gate: AC1 bin is exactly ttw-ci-gate OK"

  # bad TAG MSG: records a failed assertion of the current suite.
  bad() {
    echo "ttw-ci-gate: [$label] $1 FAILED — $2"
    echo "$1" >> "$fails"
  }

  # tl TEXT: TEXT with every | turned into a tab.
  tl() { printf '%s' "$1" | tr '|' '\t'; }

  # same TAG FILE LINE...: FILE must equal LINE... (| = tab).
  same() {
    tag="$1"; f="$2"; shift 2
    printf '%s\n' "$@" | tr '|' '\t' > "$f.want"
    if ! cmp -s "$f.want" "$f"; then
      bad "$tag" "$(basename "$f") differs from the expected text:
  $(diff "$f.want" "$f" || true)"
    fi
  }

  # mkrepo NAME [DEST=SRC...]: fresh repo dir in R; any DEST=SRC is copied
  # into R/.github/workflows/DEST.
  mkrepo() {
    R="$W/$1/repo"; shift
    mkdir -p "$R"
    if [ $# -gt 0 ]; then
      mkdir -p "$R/.github/workflows"
      for p in "$@"; do cp "''${p#*=}" "$R/.github/workflows/''${p%%=*}"; done
    fi
  }

  # gate OUT DIR ARGS...: runs the tool under test (array G) with cwd DIR and
  # none of the fixtures' env names inherited; stdout OUT.out, stderr
  # OUT.err, exit status in rc.
  gate() {
    o="$1"; d="$2"; shift 2
    rc=0
    (cd "$d" && env -u FOO -u CI -u WF -u JOB -u SHARED -u STEP -u DROP -u V PATH=${casePath} "''${G[@]}" "$@") > "$o.out" 2> "$o.err" || rc=$?
  }

  # execs OUT: OUT.exec = the PASS/FAIL lines minus their log= field;
  # OUT.logs = the log= paths.
  execs() {
    grep -E '^(PASS|FAIL) rc=' "$1.out" | sed 's/\tlog=.*$//' > "$1.exec" || true
    grep -E '^(PASS|FAIL) rc=' "$1.out" | sed -n 's/^.*\tlog=//p' > "$1.logs" || true
  }

  case_ac1() {
    gate "$W/ac1" "$W/elsewhere" --help
    if [ "$rc" != 0 ] || ! grep -qF ttw-ci-gate "$W/ac1.out"; then
      bad AC1:help "--help exited $rc (want 0) and/or does not name ttw-ci-gate: $(cat "$W/ac1.out" "$W/ac1.err")"
    fi
  }

  case_ac2() {
    for v in none empty readme; do
      case "$v" in
      none) mkrepo ac2-$v ;;
      empty) mkrepo ac2-$v; mkdir -p "$R/.github/workflows" ;;
      readme) mkrepo ac2-$v README.md=${fxReadme} ;;
      esac
      gate "$W/ac2-$v" "$W/elsewhere" --repo "$R"
      same AC2 "$W/ac2-$v.out" "ttw-ci-gate: no workflows"
      [ "$rc" = 0 ] || bad AC2 "workflows=$v: exit $rc, want 0"
    done
  }

  case_ac3() {
    mkrepo ac3 bad.yml=${fxBad}
    gate "$W/ac3" "$W/elsewhere" --repo "$R"
    [ "$rc" = 2 ] || bad AC3 "unparsable YAML: exit $rc, want 2"
    grep -qE '^ttw-ci-gate: .*bad\.yml: unparsable: ' "$W/ac3.err" \
      || bad AC3 "stderr lacks 'ttw-ci-gate: …bad.yml: unparsable: ': $(cat "$W/ac3.err")"
  }

  case_ac4() {
    mkrepo ac4 ci.yml=${fxUses}
    gate "$W/ac4" "$W/elsewhere" --repo "$R"
    same AC4 "$W/ac4.out" \
      "local|ci.yml:build|Lint|make lint" \
      "ttw-ci-gate: local=1 ci-only=0 setup=0"
    [ "$rc" = 0 ] || bad AC4 "exit $rc, want 0"
  }

  case_ac5() {
    mkrepo ac5 setup.yml=${fxSetup}
    gate "$W/ac5" "$W/elsewhere" --repo "$R"
    same AC5 "$W/ac5.out" \
      "setup|setup.yml:prep|Install|pnpm install --frozen-lockfile" \
      "setup|setup.yml:prep|Apt|sudo apt-get install -y x" \
      'setup|setup.yml:prep|Output|echo "k=v" >> $GITHUB_OUTPUT' \
      "ttw-ci-gate: local=0 ci-only=0 setup=3"
  }

  case_ac6() {
    mkrepo ac6 static.yml=${fxStatic}
    gate "$W/ac6" "$W/elsewhere" --repo "$R"
    same AC6 "$W/ac6.out" \
      "local|static.yml:static|Typecheck|pnpm typecheck" \
      "ttw-ci-gate: local=1 ci-only=0 setup=0"
  }

  case_ac7() {
    mkrepo ac7 reasons.yml=${fxReasons}
    gate "$W/ac7" "$W/elsewhere" --repo "$R"
    while IFS='=' read -r reason line; do
      grep -qxF "$(tl "$line")" "$W/ac7.out" \
        || bad "AC7:$reason" "no line '$line' in: $(cat "$W/ac7.out" "$W/ac7.err")"
    done <<'EOF'
  secrets=ci-only (secrets)|reasons.yml:secrets|Secret|make check
  expression=ci-only (expression)|reasons.yml:expression|Expr|echo ''${{ matrix.os }}
  service=ci-only (service)|reasons.yml:service|WithService|make check
  deploy=ci-only (deploy)|reasons.yml:deploy|Ship|pnpm run deploy
  database=ci-only (database)|reasons.yml:database|Schema|pnpm db:migrate
  container=ci-only (container)|reasons.yml:container|Image|docker build .
  browser=ci-only (browser)|reasons.yml:browser|Browser|pnpm exec playwright test
  github=ci-only (github)|reasons.yml:github|Hub|gh pr view 1
  privileged=ci-only (privileged)|reasons.yml:privileged|Root|sudo make
  EOF
    [ "$(tail -n 1 "$W/ac7.out")" = "ttw-ci-gate: local=0 ci-only=9 setup=0" ] \
      || bad AC7:counts "last line '$(tail -n 1 "$W/ac7.out")'"
    [ "$(wc -l < "$W/ac7.out")" = 10 ] || bad AC7:counts "want 9 step lines + counts, got $(wc -l < "$W/ac7.out") lines"
  }

  case_ac8() {
    mkrepo ac8 b.yml=${fxListB} a.yaml=${fxListA} README.md=${fxReadme}
    want8=(
      "local|a.yaml:x|#1|make lint"
      "setup|a.yaml:x|Install|pnpm install --frozen-lockfile"
      "local|b.yml:y|Multi|pnpm lint"
      "ci-only (container)|b.yml:y|Image|docker build ."
      "ttw-ci-gate: local=2 ci-only=1 setup=1"
    )
    gate "$W/ac8" "$W/elsewhere" --repo "$R"
    same AC8 "$W/ac8.out" "''${want8[@]}"
    gate "$W/ac8-default" "$R"
    same AC8:default-repo "$W/ac8-default.out" "''${want8[@]}"
  }

  case_ac9() {
    mkrepo ac9 run.yml=${fxRun}
    mkdir -p "$W/ac9-logs"
    gate "$W/ac9" "$W/elsewhere" --repo "$R" --run --log-dir "$W/ac9-logs"
    execs "$W/ac9"
    same AC9:exec "$W/ac9.exec" \
      "PASS rc=0|run.yml:build|One" \
      "PASS rc=0|run.yml:build|#3"
    [ "$(tail -n 1 "$W/ac9.out")" = "ttw-ci-gate: run local=2 pass=2 fail=0 ci-only=1 setup=1" ] \
      || bad AC9:last "last line '$(tail -n 1 "$W/ac9.out")'"
    [ "$rc" = 0 ] || bad AC9:exit "exit $rc, want 0"
    [ ! -e "$R/ci-only.ran" ] || bad AC9:ci-only-ran "the ci-only step was executed"
    [ ! -e "$R/setup.ran" ] || bad AC9:setup-ran "the setup step was executed"
    [ "$(cat "$R/one.out" 2>/dev/null)" = one ] && [ "$(cat "$R/two.out" 2>/dev/null)" = "$(printf 'a\nb')" ] \
      || bad AC9:markers "one.out / two.out (both lines of the multi-line step) missing or wrong in $R"
    n=0
    while read -r l; do
      [ -f "$l" ] || bad AC9:logs "log '$l' is not a file"
      n=$((n + 1))
    done < "$W/ac9.logs"
    [ "$n" = 2 ] || bad AC9:logs "want 2 log= paths, got $n"
  }

  case_ac10() {
    mkrepo ac10 fail.yml=${fxFail}
    mkdir -p "$W/ac10-logs"
    gate "$W/ac10" "$W/elsewhere" --repo "$R" --run --log-dir "$W/ac10-logs"
    execs "$W/ac10"
    same AC10:exec "$W/ac10.exec" \
      "FAIL rc=3|fail.yml:build|Boom" \
      "PASS rc=0|fail.yml:build|After"
    [ "$(tail -n 1 "$W/ac10.out")" = "ttw-ci-gate: run local=2 pass=1 fail=1 ci-only=0 setup=0" ] \
      || bad AC10:last "last line '$(tail -n 1 "$W/ac10.out")'"
    [ "$rc" = 1 ] || bad AC10:exit "exit $rc, want 1"
    [ -e "$R/after.out" ] || bad AC10:after "the step after the failure did not run"
    log="$(grep -E '^FAIL rc=3' "$W/ac10.out" | sed -n 's/^.*\tlog=//p' || true)"
    grep -qF boom-output "$log" 2>/dev/null || bad AC10:log "log '$log' of the failing step lacks its output"
  }

  case_ac11() {
    mkrepo ac11 ci.yml=${fxDedupCi} other.yml=${fxDedupOther}
    mkdir -p "$R/sub" "$R/pkg" "$W/ac11-logs"
    gate "$W/ac11" "$W/elsewhere" --repo "$R" --run --log-dir "$W/ac11-logs"
    execs "$W/ac11"
    same AC11:exec "$W/ac11.exec" \
      "PASS rc=0|ci.yml:a|Count" \
      "PASS rc=0|ci.yml:a|StepWd" \
      "FAIL rc=1|ci.yml:a|Pipe" \
      "PASS rc=0|ci.yml:b|JobWd"
    [ "$(wc -l < "$R/dedup.count" 2>/dev/null)" = 1 ] && [ "$(wc -l < "$W/ac11.exec")" = 4 ] \
      || bad AC11:dedup "the shared step ran $(cat "$R/dedup.count" 2>/dev/null | wc -l) time(s), want 1"
    grep -qxF "$(tl 'FAIL rc=1|ci.yml:a|Pipe')" "$W/ac11.exec" \
      || bad AC11:pipefail "'pnpm fails | pnpm sink' did not FAIL rc=1"
    grep -q '/sub$' "$R/sub/step-wd.txt" 2>/dev/null && [ ! -e "$R/step-wd.txt" ] \
      || bad AC11:wd "step working-directory not honoured"
    grep -q '/pkg$' "$R/pkg/job-wd.txt" 2>/dev/null && [ ! -e "$R/job-wd.txt" ] \
      || bad AC11:wd "job defaults.run.working-directory not honoured"
    [ "$rc" = 1 ] || bad AC11:exit "exit $rc, want 1"
  }

  case_ac12() {
    mkrepo ac12 env.yml=${fxEnv}
    mkdir -p "$W/ac12-logs"
    gate "$W/ac12" "$W/elsewhere" --repo "$R" --run --log-dir "$W/ac12-logs"
    execs "$W/ac12"
    same AC12 "$W/ac12.exec" "PASS rc=0|env.yml:e|Env"
    [ "$rc" = 0 ] || bad AC12 "exit $rc, want 0"
  }

  case_ac16() {
    local name first n25 job25 want25 got25
    mkrepo ac16 allow.yml=${fxAllow}
    gate "$W/ac16" "$W/elsewhere" --repo "$R"
    while IFS='=' read -r name first; do
      grep -qxF "$(tl "local|allow.yml:allowed|$name|$first")" "$W/ac16.out" \
        || bad "AC16:$name" "recognised check not local, want 'local|allow.yml:allowed|$name|$first'"
    done <<'EOF'
  Typecheck=pnpm typecheck
  Silent=pnpm -s lint
  NpmRun=npm run build
  Yarn=yarn test
  Bun=bun run test
  Tsc=npx tsc --noEmit
  Eslint=npx eslint .
  PrettierCheck=npx prettier --check .
  Biome=npx biome check .
  NodeScript=node scripts/check.mjs
  NodeTsx=node --import tsx scripts/check.ts
  Tsx=tsx scripts/check.ts
  Cargo=cargo clippy
  CargoFmt=cargo fmt --check
  Go=go test ./...
  Pytest=python -m pytest
  Ruff=ruff check .
  Mypy=mypy src
  Nix=nix flake check
  Make=make test
  Multi=set -euo pipefail
  Commented=pnpm lint
  EOF
    for name in GitClean GitReset GitPush SemRel NpmVersion CurlSh PrettierWrite LintFix FormatW Sleep \
      PipeSh Dev Start Watch Serve Preview EchoFile CdAbs TrailingRm; do
      awk -F '\t' -v n="$name" '$2 == "allow.yml:refused" && $3 == n && $1 ~ /^ci-only \([a-z ]+\)$/ { f = 1 } END { exit !f }' "$W/ac16.out" \
        || bad "AC16:$name" "not classed ci-only: $(awk -F '\t' -v n="$name" '$2 == "allow.yml:refused" && $3 == n' "$W/ac16.out")"
    done
    # AC25 NAME|JOB|CLASS-PATTERN. db:x / migrate:up / release-notes also hit
    # the database / deploy reason, which is checked before the allowlist
    # (AC7 order): any ci-only class is right for them, never local.
    while IFS='|' read -r n25 job25 want25; do
      got25="$(awk -F '\t' -v j="allow.yml:$job25" -v n="$n25" '$2 == j && $3 == n { print $1 }' "$W/ac16.out")"
      case "$got25" in
      $want25) ;;
      *) bad "AC25:$n25" "class '$got25', want '$want25'" ;;
      esac
    done <<'EOF'
  Reserved|segments|local
  Predeploy|segments|local
  Serve|segments|ci-only (unrecognised)
  TestServe|segments|ci-only (unrecognised)
  DevServer|segments|ci-only (unrecognised)
  ReleaseNotes|segments|ci-only (*)
  DbX|segments-db|ci-only (*)
  MigrateUp|segments-migrate|ci-only (*)
  EOF
  }

  case_ac17() {
    mkrepo ac17 state.yml=${fxState}
    gate "$W/ac17" "$W/elsewhere" --repo "$R"
    same AC17 "$W/ac17.out" \
      "local|state.yml:db|Before|pnpm lint" \
      "ci-only (database)|state.yml:db|Migrate|pnpm db:migrate" \
      "ci-only (after database)|state.yml:db|After|pnpm test:x" \
      "ci-only (secrets)|state.yml:sec|Fetch|pnpm fetch-data" \
      "ci-only (after secrets)|state.yml:sec|Then|pnpm lint" \
      "ci-only (container)|state.yml:img|Build|docker build ." \
      "ci-only (after container)|state.yml:img|Check|pnpm test" \
      "ci-only (deploy)|state.yml:dep|Ship|pnpm run deploy" \
      "local|state.yml:dep|Lint|pnpm lint" \
      "ttw-ci-gate: local=2 ci-only=7 setup=0"
  }

  case_ac18() {
    mkrepo ac18 t.yml=${fxTimeout}
    mkdir -p "$W/ac18-logs"
    t0=$(date +%s)
    gate "$W/ac18" "$W/elsewhere" --repo "$R" --run --timeout 2 --log-dir "$W/ac18-logs"
    t1=$(date +%s)
    execs "$W/ac18"
    grep -qxF "$(tl 'FAIL rc=124|t.yml:t|Hang')" "$W/ac18.exec" && [ $((t1 - t0)) -lt 15 ] \
      || bad AC18:timeout "the hung check is not 'FAIL rc=124' within 15 s ($((t1 - t0)) s): $(cat "$W/ac18.out" "$W/ac18.err")"
    grep -qxF "$(tl 'PASS rc=0|t.yml:t|Next')" "$W/ac18.exec" && [ -e "$R/after.out" ] \
      || bad AC18:next "the step after the timeout did not run"
    [ "$rc" = 1 ] || bad AC18:exit "exit $rc, want 1"
    if [ -s "$R/hang.pid" ]; then
      pid="$(cat "$R/hang.pid")"; alive=1
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || { alive=0; break; }
        sleep 0.2
      done
      if [ "$alive" = 1 ]; then
        kill "$pid" 2>/dev/null || true
        bad AC18:orphan "the hung check's child $pid outlived the step: its process group was not killed"
      fi
    else
      bad AC18:orphan "hang.pid missing: the hanging check never started"
    fi
  }

  case_ac19() {
    mkrepo ac19 key.yml=${fxKey}
    mkdir -p "$R/a" "$R/b" "$W/ac19-logs"
    gate "$W/ac19" "$W/elsewhere" --repo "$R" --run --log-dir "$W/ac19-logs"
    execs "$W/ac19"
    same AC19 "$W/ac19.exec" \
      "PASS rc=0|key.yml:k|A" \
      "PASS rc=0|key.yml:k|B" \
      "PASS rc=0|key.yml:k|C"
    [ "$(wc -l < "$R/a/stamp.out" 2>/dev/null)" = 2 ] && [ "$(wc -l < "$R/b/stamp.out" 2>/dev/null)" = 1 ] \
      || bad AC19 "want a/stamp.out 2 lines (A, C) and b/stamp.out 1 line (B)"
  }

  case_ac20() {
    mkrepo ac20 defaults.yml=${fxDefaults}
    mkdir -p "$R/app" "$R/lib" "$R/tools" "$W/ac20-logs"
    gate "$W/ac20" "$W/elsewhere" --repo "$R" --run --log-dir "$W/ac20-logs"
    execs "$W/ac20"
    same AC20:exec "$W/ac20.exec" \
      "PASS rc=0|defaults.yml:e|Dump" \
      "PASS rc=0|defaults.yml:jobwd|JobOverWf" \
      "PASS rc=0|defaults.yml:jobwd|StepOverJob"
    got="$(cat "$R/app/env.out" 2>/dev/null || true)"
    [ "$got" = "WF=w JOB=j SHARED=job STEP=s CI=true DROP=unset" ] \
      || bad AC20:env "app/env.out is '$got', want 'WF=w JOB=j SHARED=job STEP=s CI=true DROP=unset'"
    [ -e "$R/lib/wd-a.txt" ] && [ ! -e "$R/app/wd-a.txt" ] \
      || bad AC20:wd "job defaults.run did not override the workflow's"
    [ -e "$R/tools/wd-b.txt" ] && [ ! -e "$R/lib/wd-b.txt" ] \
      || bad AC20:wd "step working-directory did not override job defaults.run"
  }

  case_ac21() {
    mkrepo ac21 guards.yml=${fxGuards}
    gate "$W/ac21" "$W/elsewhere" --repo "$R"
    same AC21:guards "$W/ac21.out" \
      "ci-only (shell)|guards.yml:g|Pwsh|make test" \
      "local|guards.yml:g|Bash|make lint" \
      "local|guards.yml:g|Sh|make lint" \
      "ci-only (condition)|guards.yml:g|Cond|make check" \
      "ci-only (expression)|guards.yml:g|ExprEnv|make test" \
      "ci-only (expression)|guards.yml:g|ExprWith|make test" \
      "local|guards.yml:g|Last|make lint" \
      "ttw-ci-gate: local=3 ci-only=4 setup=0"
    mkrepo ac21-err ci.yml=${fxUses}
    : > "$W/ac21-logfile"
    gate "$W/ac21-err" "$W/elsewhere" --repo "$R" --run --log-dir "$W/ac21-logfile"
    [ "$rc" = 2 ] && grep -q '^ttw-ci-gate: error:' "$W/ac21-err.err" \
      || bad AC21:internal "--log-dir on a file: exit $rc (want 2), stderr: $(head -c 300 "$W/ac21-err.err")"
  }

  case_ac22() {
    mkrepo ac22 idx.yml=${fxIndex}
    gate "$W/ac22" "$W/elsewhere" --repo "$R"
    same AC22 "$W/ac22.out" \
      "local|idx.yml:i|#2|make lint" \
      "local|idx.yml:i|Named|make test" \
      "local|idx.yml:i|#4|make check" \
      "local|idx.yml:j|#1|pnpm lint" \
      "ttw-ci-gate: local=4 ci-only=0 setup=0"
  }

  # suite LABEL CASE...: fresh work root W, runs the cases, failed tags in $fails.
  suite() {
    label="$1"; shift
    W="$TMPDIR/run-$label"
    rm -rf "$W"; mkdir -p "$W/elsewhere"
    fails="$W/fails"; : > "$fails"
    for c in "$@"; do "case_$c"; done
  }

  all="ac1 ac2 ac3 ac4 ac5 ac6 ac7 ac8 ac9 ac10 ac11 ac12 ac16 ac17 ac18 ac19 ac20 ac21 ac22"

  G=(${pkg}/bin/ttw-ci-gate)
  suite real $all
  if [ -s "$fails" ]; then
    echo "ttw-ci-gate: $(sort -u "$fails" | wc -l) assertion tag(s) failed: $(sort -u "$fails" | tr '\n' ' ')"
    exit 1
  fi
  echo "ttw-ci-gate: AC1-AC12, AC16-AC22 OK"

  # mkmut NAME TEXT_MODE: the built script copied (and rewritten) to
  # $TMPDIR/mut-NAME/ttw-ci-gate, G set to run it through the runner.
  mkmut() {
    md="$TMPDIR/mut-$1"
    mkdir -p "$md"
    ${py}/bin/python3 ${mutate} "$2" ${pkg}/bin/ttw-ci-gate "$md/ttw-ci-gate"
    G=(${py}/bin/python3 ${runner} "$md/ttw-ci-gate")
  }

  # Control M0: the runner on the unchanged script passes every case.
  mkmut m0 none
  export MUT_MODE=none MUT_HIT="$TMPDIR/mut-m0/hit"
  suite m0 $all
  if [ -s "$fails" ]; then
    echo "ttw-ci-gate: control M0 FAILED — the runner alone breaks $(sort -u "$fails" | tr '\n' ' '); mutant kills would prove nothing"
    exit 1
  fi
  echo "ttw-ci-gate: control M0 (runner, unchanged script) passes every case OK"

  # mutant NAME TEXT_MODE HOOK_MODE TARGET_TAG CASE...
  mutant() {
    local name="$1" tmode="$2" hmode="$3" target="$4"
    shift 4
    mkmut "$name" "$tmode"
    export MUT_MODE="$hmode" MUT_HIT="$TMPDIR/mut-$name/hit"
    case "$hmode" in
    no-job-state | text-key)
      MUT_PROBE=1 ${py}/bin/python3 ${runner} "$TMPDIR/mut-$name/ttw-ci-gate" \
        || { echo "ttw-ci-gate: canary $name — runner anchor missing: the mutant would equal the source"; exit 1; }
      rm -f "$MUT_HIT"
      ;;
    esac
    suite "$name" "$@" ac2 ac3
    if grep -qE '^AC[23]$' "$fails"; then
      echo "ttw-ci-gate: canary $name BROKEN — it fails AC2/AC3 too: the mutant no longer runs, so its kill proves nothing"
      exit 1
    fi
    if [ "$hmode" != none ] && [ ! -s "$MUT_HIT" ]; then
      echo "ttw-ci-gate: canary $name INERT — runner swap '$hmode' never fired: the mutant equals the source"
      exit 1
    fi
    if ! grep -qxF "$target" "$fails"; then
      echo "ttw-ci-gate: canary $name SURVIVED — $target still passes (failed tags: $(sort -u "$fails" | tr '\n' ' '))"
      exit 1
    fi
    echo "ttw-ci-gate: canary $name killed by $target"
  }

  mutant m1-job-env none job-env AC6 ac6
  mutant m2-drop-reason drop-reason none AC7:browser ac7
  mutant m3-no-dedup none no-dedup AC11:dedup ac11
  mutant m4-no-pipefail no-pipefail none AC11:pipefail ac11
  mutant m5-exit0 none exit0 AC10:exit ac10
  mutant m6-run-ci-only run-ci-only none AC9:ci-only-ran ac9
  mutant m7-no-job-state none no-job-state AC17 ac17
  mutant m8-no-timeout none no-timeout AC18:timeout ac18
  mutant m9-text-key none text-key AC19 ac19
  mutant m10-unrecognised-local unrecognised-local none AC16:GitClean ac16

  echo "ttw-ci-gate: AC1-AC12, AC16-AC22 OK, control M0 clean, 10 canaries killed — OK"
  touch $out
''
