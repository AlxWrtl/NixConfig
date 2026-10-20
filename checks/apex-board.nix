# Runtime check for apex-board (home/claude-code/apex-board.nix): the page's
# stage rules under node, then the BUILT launcher in --dry-run against
# throwaway repos and HOMEs.
#
#   T1  `node test.js board.js` (fixtures in the three real 00-context.md
#       shapes + synthetic À-toi cases)         -> exit 0
#   T2  `node tui-test.js` (tui.js on temp-dir fixture runs: disk reads, links
#       out of the runs dir never read, board render width/colors/cap, keys
#       and mouse, markdown, terminal restore)  -> exit 0
#   D1  --dry-run --port 9999 <repo>, HOME holds .claude/apex-correction-budget
#       -> url on 127.0.0.1:9999, runs -> <repo>/.claude/output/apex,
#          budget -> $HOME/.claude/apex-correction-budget, index.html and
#          board.js: copy of the store file (byte-equal to the sources,
#          test.js not shipped, serve.py byte-equal next to them),
#          meta.json {"repo":"<basename>"}, temp root gone on exit
#   K1  same, built script with `trap cleanup EXIT` disarmed so the root
#       stays -> index.html and board.js are regular files (not links),
#          byte-equal to the store copies, mtime past 1970-01-02 (store files
#          sit at 1: a link or `cp -p` would freeze Last-Modified and the
#          browser would keep the old page after a rebuild); no serve.py
#          in the root
#   D2  same, HOME without the budget dir      -> budget: empty dir, port 8765
#   D3  no repo argument, cwd = a subdir of a git repo -> runs of its toplevel
#   D4  repo without .claude/output/apex       -> exit 1, nothing served
#   D5  --port 0                               -> exit 2 (usage)
#   D6  --tui --dry-run, HOME with and without the budget dir -> exactly
#       `tui: node <store page dir>/tui.js`, `runs: <repo>/.claude/output/apex`,
#       `budget: <dir>` / `budget: none`; tui.js in the store byte-equal to its
#       source, tui-test.js not shipped, no temp root made; --port 0 ignored
#   D7  --tui with PATH=/var/empty and no terminal -> node found through the
#       package's runtimeInputs, tui.js refuses: exit 1, "needs a terminal"
#   S1  serve.py's gates imported under python3: host_allowed takes
#       127.0.0.1:<port> and localhost:<port> only (another host, another
#       port, no port, no Host -> refused); path_allowed takes the root,
#       runs/, a run file and a run subdir, refuses a link to a file or a dir
#       outside, a `loop -> .` and an `up -> ..` under runs/
#   S2  the BUILT launcher serving for real (__darwinAllowLocalNetworking:
#       loopback only) a repo whose run holds an escaping link and a loop:
#       200 on index.html for both loopback Hosts, 403 for another Host or
#       none, 404 on the escape and the loop, 405 on POST, 304 on an
#       If-Modified-Since equal to Last-Modified, a listing naming the run's
#       file; a TERM to the launcher leaves nothing on the port
#   B1  the built script runs serve.py from the page's store dir exactly once
#       and no `http.server` anywhere; serve.py binds the literal 127.0.0.1
#       once, through BIND, and takes no bind argument; K1 already shows
#       serve.py stays out of the served root
#
# Canary M1: a copy of board.js whose statusKind reads `failed` as `done`
# (`return 'failed'` -> `return 'done'`) must make test.js exit non-zero on
# the failed-step case expecting À toi ('human'). If it still passes, the À-toi
# assertion does not rest on the failed status and proves nothing, so the
# check fails. A guard fails too if the sed anchor is gone (the mutant would
# equal the source).
#
# Canary M2: a copy of serve.py whose host_allowed returns True (DNS
# rebinding open again) must make S1 exit non-zero on the foreign-Host case;
# guarded the same way against a vanished anchor.
#
# Canary M3: a copy of tui.js (board.js next to it) whose LEAVE no longer
# leaves the alternate screen (`?1049l` -> `?1049h`) must make tui-test.js exit
# non-zero on the terminal-restore case; the anchor must appear exactly once.
#
# Offline: node, python3, git and coreutils only; HOME and system git config
# isolated in $TMPDIR. The only socket is S2's, bound to 127.0.0.1.
{ pkgs }:

let
  board = (import ../home/claude-code/apex-board.nix { inherit pkgs; }).apexBoardPkg;
  pageDir = ../home/claude-code/apex-board;
  # S1/S2 harness: `unit SERVE WORKDIR`, `port`, `http PORT`, `down PORT`.
  probe = pkgs.writeText "apex-board-serve-probe.py" ''
    import http.client
    import importlib.util
    import os
    import socket
    import sys
    import time


    def fail(msg):
        sys.stderr.write(f"FAIL {msg}\n")
        sys.exit(1)


    def unit(serve, work):
        spec = importlib.util.spec_from_file_location("serve", serve)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        for host, ok in [("127.0.0.1:8765", True), ("localhost:8765", True), ("evil.example:8765", False),
                         ("127.0.0.1:8766", False), ("127.0.0.1", False), ("", False), (None, False),
                         ("localhost:8765.evil.example", False)]:
            if m.host_allowed(host, 8765) is not ok:
                fail(f"host_allowed({host!r}, 8765) is not {ok}")
        root, runs, out = (os.path.join(work, d) for d in ("root", "runs", "outside"))
        os.makedirs(os.path.join(runs, "run-1", "sub"))
        os.makedirs(out)
        os.makedirs(root)
        open(os.path.join(out, "secret"), "w").close()
        open(os.path.join(runs, "run-1", "00-context.md"), "w").close()
        os.symlink(runs, os.path.join(root, "runs"))
        os.symlink(os.path.join(out, "secret"), os.path.join(runs, "run-1", "escape"))
        os.symlink(out, os.path.join(runs, "run-1", "escape-dir"))
        os.symlink(".", os.path.join(runs, "run-1", "loop"))
        os.symlink("..", os.path.join(runs, "run-1", "up"))
        roots = [root, os.path.join(root, "runs"), os.path.join(root, "budget")]
        for rel, ok in [("", True), ("index.html", True), ("runs", True), ("runs/", True),
                        ("runs/run-1/00-context.md", True), ("runs/run-1/sub/", True),
                        ("runs/run-1/escape", False), ("runs/run-1/escape-dir/secret", False),
                        ("runs/run-1/loop/", False), ("runs/run-1/up", False)]:
            if m.path_allowed(os.path.join(root, rel), roots) is not ok:
                fail(f"path_allowed(<root>/{rel}) is not {ok}")


    def request(port, method, path, host, headers=()):
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        c.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
        if host is not None:
            c.putheader("Host", host)
        for k, v in headers:
            c.putheader(k, v)
        c.endheaders()
        r = c.getresponse()
        body = r.read()
        c.close()
        return r.status, r.getheader("Last-Modified"), body


    def live(port):
        for _ in range(100):
            try:
                return request(port, "HEAD", "/", f"127.0.0.1:{port}")
            except OSError:
                time.sleep(0.1)
        fail(f"no server on 127.0.0.1:{port} after 10 s")


    def serve_http(port):
        port = int(port)
        live(port)
        me, lh = f"127.0.0.1:{port}", f"localhost:{port}"
        for method, path, host, want in [
            ("GET", "/index.html", me, 200), ("GET", "/index.html", lh, 200),
            ("GET", "/index.html", f"evil.example:{port}", 403), ("GET", "/index.html", None, 403),
            ("GET", "/runs/run-1/00-context.md", me, 200), ("GET", "/runs/run-1/", me, 200),
            ("GET", "/runs/run-1/escape", me, 404), ("GET", "/runs/run-1/loop/", me, 404),
            ("POST", "/index.html", me, 405), ("HEAD", "/index.html", me, 200),
        ]:
            got = request(port, method, path, host)[0]
            if got != want:
                fail(f"{method} {path} Host={host!r}: {got}, expected {want}")
        _, lm, _ = request(port, "GET", "/index.html", me)
        if not lm:
            fail("no Last-Modified on /index.html")
        if request(port, "GET", "/index.html", me, [("If-Modified-Since", lm)])[0] != 304:
            fail("If-Modified-Since equal to Last-Modified did not answer 304")
        if b"00-context.md" not in request(port, "GET", "/runs/run-1/", me)[2]:
            fail("directory listing of runs/run-1/ lacks 00-context.md")


    def free_port():
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        print(s.getsockname()[1])
        s.close()


    def down(port):
        try:
            request(int(port), "HEAD", "/", f"127.0.0.1:{port}")
        except OSError:
            return
        fail(f"server still answers on 127.0.0.1:{port}")


    if __name__ == "__main__":
        {"unit": unit, "port": free_port, "http": serve_http, "down": down}[sys.argv[1]](*sys.argv[2:])
  '';
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.nodejs
    pkgs.git
    pkgs.coreutils
    pkgs.diffutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.python3
  ];
in
pkgs.runCommand "apex-board-check" { __darwinAllowLocalNetworking = true; } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR/home-none" GIT_CONFIG_NOSYSTEM=1
  bin=${board}/bin/apex-board
  fail() {
    echo "apex-board: $*" >&2
    exit 1
  }

  # T1: stage rules on the real board.js.
  node ${pageDir}/test.js ${pageDir}/board.js || fail "T1 FAILED — test.js is red on board.js"
  echo "apex-board: T1 OK — test.js green on board.js"

  # Canary M1: failed read as done.
  sed "s/return 'failed'/return 'done'/" ${pageDir}/board.js > "$TMPDIR/mutant.js"
  if cmp -s ${pageDir}/board.js "$TMPDIR/mutant.js"; then
    fail "canary anchor \"return 'failed'\" gone from board.js — the mutant equals the source"
  fi
  if m1="$(node ${pageDir}/test.js "$TMPDIR/mutant.js" 2>&1)"; then
    fail "canary M1 SURVIVED — board.js with failed read as done still passes test.js; the À-toi assertion does not rest on the failed status"
  fi
  case "$m1" in
  *FAIL*"'human'"*) ;;
  *) fail "canary M1 died for another reason than the À-toi case: $m1" ;;
  esac
  echo "apex-board: canary M1 killed — failed read as done turns the failed-step run away from À toi"

  # T2: the terminal board on the real tui.js and board.js.
  node ${pageDir}/tui-test.js || fail "T2 FAILED — tui-test.js is red on tui.js"
  echo "apex-board: T2 OK — tui-test.js green on tui.js"

  # Canary M3: LEAVE stays on the alternate screen.
  mkdir "$TMPDIR/m3"
  cp ${pageDir}/board.js "$TMPDIR/m3/board.js"
  sed 's/?1049l/?1049h/' ${pageDir}/tui.js > "$TMPDIR/m3/tui.js"
  if [ "$(grep -c '?1049l' ${pageDir}/tui.js)" != 1 ] || cmp -s ${pageDir}/tui.js "$TMPDIR/m3/tui.js"; then
    fail "canary anchor '?1049l' not found once in tui.js — the mutant equals the source"
  fi
  if m3="$(node ${pageDir}/tui-test.js "$TMPDIR/m3/tui.js" 2>&1)"; then
    fail "canary M3 SURVIVED — tui.js whose LEAVE stays on the alternate screen still passes tui-test.js"
  fi
  case "$m3" in
  *"FAIL terminal restore"*"LEAVE does not leave the alt screen"*) ;;
  *) fail "canary M3 died for another reason than the terminal restore: $m3" ;;
  esac
  echo "apex-board: canary M3 killed — a LEAVE that keeps the alternate screen is caught"

  # Fixtures: a repo with one run, a repo without runs, two HOMEs.
  R="$TMPDIR/myrepo"
  mkdir -p "$R/.claude/output/apex/run-1" "$R/sub" "$TMPDIR/norun" \
    "$TMPDIR/home-with/.claude/apex-correction-budget" "$TMPDIR/home-without"
  printf '# APEX: fixture\n' > "$R/.claude/output/apex/run-1/00-context.md"
  Rp="$(cd "$R" && pwd -P)"

  # has RES LINE: RES holds LINE exactly.
  has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }

  # store_copy RES NAME: NAME is reported as a copy of the page's store file,
  # byte-equal to its source; prints that store dir.
  store_copy() {
    t="$(printf '%s\n' "$1" | sed -n "s|^$2: copy of ||p")"
    case "$t" in
    /nix/store/*-apex-board-page/"$2") ;;
    *) fail "$2 is not reported as a copy of the store page file: '$t'" ;;
    esac
    cmp -s "$t" "${pageDir}/$2" || fail "$2 in the store differs from its source"
    dirname "$t"
  }

  # D1
  res="$(HOME="$TMPDIR/home-with" "$bin" --dry-run --port 9999 "$R")" || fail "D1 exited non-zero: $res"
  has "$res" "url: http://127.0.0.1:9999/" || fail "D1 url line missing: $res"
  has "$res" "runs -> $Rp/.claude/output/apex" || fail "D1 runs link wrong: $res"
  has "$res" "budget -> $TMPDIR/home-with/.claude/apex-correction-budget" || fail "D1 budget link wrong: $res"
  has "$res" 'meta.json: {"repo":"myrepo"}' || fail "D1 meta.json wrong: $res"
  d="$(store_copy "$res" index.html)"
  store_copy "$res" board.js >/dev/null
  [ ! -e "$d/test.js" ] || fail "D1 test.js shipped in the store page dir $d"
  cmp -s "$d/serve.py" "${pageDir}/serve.py" || fail "D1 serve.py missing from $d or differs from its source"
  root="$(printf '%s\n' "$res" | sed -n 's|^root: ||p')"
  [ -n "$root" ] || fail "D1 root line missing: $res"
  [ ! -e "$root" ] || fail "D1 temp root $root left behind after exit"
  [ "$(printf '%s\n' "$res" | wc -l | tr -d ' ')" = 7 ] || fail "D1 expected 7 lines: $res"
  echo "apex-board: D1 OK — links, copies, meta.json, root removed"

  # K1: the built script with its cleanup trap disarmed, so the root survives
  # and the page files themselves can be inspected.
  sed 's/^trap cleanup EXIT$/:/' "$bin" > "$TMPDIR/keep-root"
  if cmp -s "$bin" "$TMPDIR/keep-root"; then
    fail "K1 anchor 'trap cleanup EXIT' gone from $bin — the root cannot be kept"
  fi
  chmod +x "$TMPDIR/keep-root"
  res="$(HOME="$TMPDIR/home-with" "$TMPDIR/keep-root" --dry-run "$R")" || fail "K1 exited non-zero: $res"
  root="$(printf '%s\n' "$res" | sed -n 's|^root: ||p')"
  [ -d "$root" ] || fail "K1 kept root missing: '$root'"
  for name in index.html board.js; do
    [ -f "$root/$name" ] && [ ! -L "$root/$name" ] ||
      fail "K1 $name in the root is not a regular file"
    cmp -s "$root/$name" "$d/$name" || fail "K1 $name in the root differs from the store copy"
    mtime="$(stat -c %Y "$root/$name")"
    [ "$mtime" -gt 86400 ] ||
      fail "K1 $name mtime $mtime is the store's epoch — Last-Modified would never move"
  done
  [ ! -e "$root/serve.py" ] || fail "K1 serve.py copied into the served root"
  rm -rf "$root"
  echo "apex-board: K1 OK — index.html and board.js are fresh regular copies, serve.py not served"

  # D2
  res="$(HOME="$TMPDIR/home-without" "$bin" --dry-run "$R")" || fail "D2 exited non-zero: $res"
  has "$res" "budget: empty dir" || fail "D2 budget not an empty dir: $res"
  has "$res" "url: http://127.0.0.1:8765/" || fail "D2 default port not 8765: $res"
  echo "apex-board: D2 OK — empty budget dir, default port"

  # D3
  (cd "$R" && git init -q --template=) || fail "D3 git init failed"
  res="$(cd "$R/sub" && "$bin" --dry-run)" || fail "D3 exited non-zero: $res"
  has "$res" "runs -> $Rp/.claude/output/apex" || fail "D3 default repo is not the git toplevel: $res"
  echo "apex-board: D3 OK — repo defaults to the git toplevel"

  # D4
  rc=0
  res="$("$bin" --dry-run "$TMPDIR/norun" 2>&1)" || rc=$?
  [ "$rc" = 1 ] || fail "D4 expected exit 1 on a repo without runs, got $rc: $res"
  case "$res" in *"not a directory"*) ;; *) fail "D4 message missing: $res" ;; esac
  echo "apex-board: D4 OK — no runs, exit 1"

  # D5
  rc=0
  res="$("$bin" --dry-run --port 0 "$R" 2>&1)" || rc=$?
  [ "$rc" = 2 ] || fail "D5 expected exit 2 on --port 0, got $rc: $res"
  echo "apex-board: D5 OK — bad port, exit 2"

  # D6: --tui --dry-run, no server and no temp root.
  [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'apex-board.*')" ] || fail "D6 a temp root is already there before the case"
  res="$(HOME="$TMPDIR/home-with" "$bin" --tui --dry-run --port 0 "$R")" || fail "D6 exited non-zero: $res"
  has "$res" "tui: node $d/tui.js" || fail "D6 tui line wrong: $res"
  has "$res" "runs: $Rp/.claude/output/apex" || fail "D6 runs line wrong: $res"
  has "$res" "budget: $TMPDIR/home-with/.claude/apex-correction-budget" || fail "D6 budget line wrong: $res"
  [ "$(printf '%s\n' "$res" | wc -l | tr -d ' ')" = 3 ] || fail "D6 expected 3 lines: $res"
  res="$(HOME="$TMPDIR/home-without" "$bin" --tui --dry-run "$R")" || fail "D6 (no budget) exited non-zero: $res"
  has "$res" "budget: none" || fail "D6 budget not none: $res"
  cmp -s "$d/tui.js" "${pageDir}/tui.js" || fail "D6 tui.js missing from $d or differs from its source"
  [ ! -e "$d/tui-test.js" ] || fail "D6 tui-test.js shipped in the store page dir $d"
  [ -z "$(find "$TMPDIR" -maxdepth 1 -name 'apex-board.*')" ] || fail "D6 --tui made a temp root"
  echo "apex-board: D6 OK — --tui dry-run: node on the store tui.js, runs, budget, no root"

  # D7: --tui for real without a terminal, node only from runtimeInputs.
  rc=0
  res="$(PATH=/var/empty HOME="$TMPDIR/home-with" "$bin" --tui "$R" < /dev/null 2>&1)" || rc=$?
  [ "$rc" = 1 ] || fail "D7 expected exit 1 from tui.js without a terminal, got $rc: $res"
  case "$res" in *"needs a terminal"*) ;; *) fail "D7 message missing: $res" ;; esac
  echo "apex-board: D7 OK — node from runtimeInputs, no terminal refused"

  # S1: serve.py's gates, imported from the store copy the launcher runs.
  python3 -I ${probe} unit "$d/serve.py" "$TMPDIR/s1" || fail "S1 FAILED — serve.py gates"
  echo "apex-board: S1 OK — Host and path gates"

  # Canary M2: host_allowed open to every Host.
  anchor='return host in ('
  sed "s/$anchor.*/return True/" "$d/serve.py" > "$TMPDIR/mutant.py"
  if [ "$(grep -c "$anchor" "$d/serve.py")" != 1 ] || cmp -s "$d/serve.py" "$TMPDIR/mutant.py"; then
    fail "canary anchor '$anchor' not found once in serve.py — the mutant equals the source"
  fi
  if m2="$(python3 -I ${probe} unit "$TMPDIR/mutant.py" "$TMPDIR/m2" 2>&1)"; then
    fail "canary M2 SURVIVED — serve.py with host_allowed always True still passes S1"
  fi
  case "$m2" in
  *"FAIL host_allowed('evil.example:8765', 8765) is not False"*) ;;
  *) fail "canary M2 died for another reason than the foreign Host: $m2" ;;
  esac
  echo "apex-board: canary M2 killed — a Host gate open to all is caught"

  # S2: the built launcher serving for real.
  S="$TMPDIR/srepo/.claude/output/apex/run-1"
  mkdir -p "$S/sub" "$TMPDIR/outside"
  printf 'secret\n' > "$TMPDIR/outside/secret"
  printf '# APEX: served\n' > "$S/00-context.md"
  ln -s "$TMPDIR/outside/secret" "$S/escape"
  ln -s . "$S/loop"
  port="$(python3 -I ${probe} port)" || fail "S2 no free loopback port"
  HOME="$TMPDIR/home-with" "$bin" --no-open --port "$port" "$TMPDIR/srepo" > "$TMPDIR/s2.log" 2>&1 &
  spid=$!
  python3 -I ${probe} http "$port" || {
    kill "$spid" 2>/dev/null || true
    fail "S2 FAILED — served root on 127.0.0.1:$port; launcher log: $(cat "$TMPDIR/s2.log")"
  }
  kill -TERM "$spid"
  wait "$spid" || true
  python3 -I ${probe} down "$port" || fail "S2 server outlived a TERM to the launcher"
  echo "apex-board: S2 OK — Host 403, escape and loop 404, POST 405, 304, listing; TERM frees the port"

  # B1: loopback only. Comment lines are skipped: headers name the servers.
  code="$(grep -v '^[[:space:]]*#' "$bin")"
  if printf '%s\n' "$code" | grep -q 'http\.server'; then
    fail "B1 http.server still run by $bin"
  fi
  has "$code" "board_dir=\"$d\"" || fail "B1 board_dir in $bin is not the page store dir $d"
  [ "$(printf '%s\n' "$code" | grep -c 'python3 ')" = 1 ] &&
    printf '%s\n' "$code" | grep -qF -- 'python3 "$board_dir/serve.py" ' ||
    fail "B1 expected exactly one python3, running \"\$board_dir/serve.py\", in $bin"
  py="$(grep -v '^[[:space:]]*#' "$d/serve.py")"
  [ "$(printf '%s\n' "$py" | grep -c '127\.0\.0\.1')" -ge 1 ] &&
    printf '%s\n' "$py" | grep -qx 'BIND = "127.0.0.1"' ||
    fail "B1 serve.py does not set BIND = \"127.0.0.1\""
  [ "$(printf '%s\n' "$py" | grep -c 'ThreadingHTTPServer((')" = 1 ] &&
    printf '%s\n' "$py" | grep -qF 'ThreadingHTTPServer((BIND, args.port),' ||
    fail "B1 serve.py binds something other than BIND"
  if printf '%s\n' "$py" | grep -qE -- "--bind|add_argument\(\"(-b|--host|--address)"; then
    fail "B1 serve.py takes a bind argument"
  fi
  echo "apex-board: B1 OK — serve.py from the store, bound to 127.0.0.1 only"

  echo "apex-board: 2 node suites, 8 launcher cases, 2 serve cases, 1 static case, 3 canaries — OK"
  touch $out
''
