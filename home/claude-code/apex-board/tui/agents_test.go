package main

// The Agents tab: testdata/session-state (one file per state the writer writes, an unknown word,
// done over 24 h, a session ended under abduco and one closed without SessionEnd, plus files that
// are no session: bad JSON, an array, no cwd, name ≠ stem, `-x.json`, a dotted temp file, an
// uppercase name) copied to a temp dir, where the edges that cannot live in git are added: a link
// out of the dir, an oversized file, a FIFO. testdata/abduco/listing.txt is abduco's list in its
// real format (header, `*`, `+`, bad names); abducoList and runPick are stubbed in every test, so
// no process is ever started.

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

var testNow = float64(time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC).UnixMilli())

// stubAbduco: abducoList answers out (or err) for the test's length.
func stubAbduco(t testing.TB, out []byte, err error) {
	t.Helper()
	prev := abducoList
	abducoList = func() ([]byte, error) { return out, err }
	t.Cleanup(func() { abducoList = prev })
}

func listing(t testing.TB) []byte {
	t.Helper()
	b, err := os.ReadFile("testdata/abduco/listing.txt")
	mustDo(t, err)
	return b
}

// stubPick records each runPick argv; agentPaneBin is a fake store path for the test's length.
func stubPick(t testing.TB, err error) *[][]string {
	t.Helper()
	var calls [][]string
	prevRun, prevBin := runPick, agentPaneBin
	runPick = func(argv []string) error {
		calls = append(calls, slices.Clone(argv))
		return err
	}
	agentPaneBin = "/nix/store/x-agent-pane/bin/agent-pane"
	t.Cleanup(func() { runPick, agentPaneBin = prevRun, prevBin })
	return &calls
}

type sessionsFixture struct{ dir, outside string }

func newSessionsFixture(t *testing.T) *sessionsFixture {
	t.Helper()
	root := t.TempDir()
	f := &sessionsFixture{dir: filepath.Join(root, "session-state"), outside: filepath.Join(root, "outside")}
	copyTree(t, "testdata/session-state", f.dir)
	mustDo(t, os.MkdirAll(f.outside, 0o755))
	secret := `{"name":"linked","state":"needs-you","cwd":"/x","intent":"SECRET-OUTSIDE","updatedAt":"2026-10-20T11:59:00.000Z"}`
	mustDo(t, os.WriteFile(filepath.Join(f.outside, "linked.json"), []byte(secret), 0o600))
	mustDo(t, os.Symlink(filepath.Join(f.outside, "linked.json"), filepath.Join(f.dir, "linked.json")))
	big := `{"name":"big","state":"working","cwd":"/x","pad":"` + strings.Repeat("x", maxStateBytes) + `"}`
	mustDo(t, os.WriteFile(filepath.Join(f.dir, "big.json"), []byte(big), 0o600))
	mustDo(t, syscall.Mkfifo(filepath.Join(f.dir, "fifo.json"), 0o600))
	return f
}

func (f *sessionsFixture) read(t *testing.T) (sessionsRead, agentsBoard) {
	t.Helper()
	read, err := (&SessionsReader{Dir: f.dir}).Read()
	mustDo(t, err)
	live, err := readAbduco()
	mustDo(t, err)
	return read, deriveAgents(withLiveness(read.sessions, live), testNow)
}

func agentsModel(t *testing.T, f *sessionsFixture, w, h int) *Model {
	t.Helper()
	stubAbduco(t, listing(t), nil)
	m := newModel("", "", "fixture", w, h)
	m.setSessionsDir(f.dir)
	m.tab = tabAgents
	p := pollAgents(m.ag.reader)
	mustDo(t, p.err)
	// Derived again at testNow: the ages and the 24 h keep do not move with the clock.
	read, err := m.ag.reader.Read()
	mustDo(t, err)
	live, _ := readAbduco()
	p.board, p.now, p.clock = deriveAgents(withLiveness(read.sessions, live), testNow), testNow, "12:00:00"
	m.applyAgents(p)
	return m
}

func colIDs(b agentsBoard, key string) []string {
	var ids []string
	for _, a := range b.cols[colIndex(key)] {
		ids = append(ids, a.ID)
	}
	return ids
}

func agentOf(t *testing.T, b agentsBoard, id string) *Agent {
	t.Helper()
	for _, col := range b.cols {
		for _, a := range col {
			if a.ID == id {
				return a
			}
		}
	}
	t.Fatalf("%s not on the board", id)
	return nil
}

func TestSessionKind(t *testing.T) {
	for state, want := range map[string]string{
		"needs-you": "needs-you", "waiting": "waiting", "idle": "idle", "working": "working", "done": "done",
		"Working": "other", "blocked": "other", "paused": "other", "": "other", " done": "other",
	} {
		if got := sessionKind(state); got != want {
			t.Errorf("sessionKind(%q) = %q, want %q", state, got, want)
		}
	}
	if projectOf("/a/Repo/.claude/worktrees/x") != "Repo" || projectOf("/a/b/") != "b" || projectOf("/") != "/" || projectOf("") != "" {
		t.Fatal("projectOf is not deck's")
	}
}

func TestValidName(t *testing.T) {
	for name, want := range map[string]bool{
		"a": true, "0": true, "ask-needs": true, "a-": true, strings.Repeat("a", 48): true,
		"": false, "-x": false, "--help": false, "Upper": false, "a_b": false, "a.b": false, "a/b": false,
		"../a": false, "a\n": false, "a b": false, "é": false, strings.Repeat("a", 49): false,
	} {
		if got := validName(name); got != want {
			t.Errorf("validName(%q) = %v", name, got)
		}
	}
}

func TestParseSessionState(t *testing.T) {
	ok := `{"name":"s1","state":"working","cwd":"/x","event":"UserPromptSubmit","updatedAt":"2026-10-20T11:59:00.000Z","intent":"[claude-dispatch]  fais\nça  avec token=abcdef123456","notice":"x\u0007y"}`
	s := parseSessionState("s1", []byte(ok))
	if s == nil || s.Intent != "fais ça avec token=•••" || s.State != "working" || s.Event != "UserPromptSubmit" || s.UpdatedAt != testNow-60_000 || s.Notice != "x\x07y" {
		t.Fatalf("parsed %+v", s)
	}
	for name, data := range map[string]string{
		"not json":      `{not json`,
		"array":         `[1]`,
		"null":          `null`,
		"string":        `"x"`,
		"no state":      `{"name":"s1","cwd":"/x"}`,
		"state number":  `{"name":"s1","state":1,"cwd":"/x"}`,
		"no cwd":        `{"name":"s1","state":"working"}`,
		"name mismatch": `{"name":"s2","state":"working","cwd":"/x"}`,
		"no name":       `{"state":"working","cwd":"/x"}`,
		"name number":   `{"name":1,"state":"working","cwd":"/x"}`,
	} {
		if parseSessionState("s1", []byte(data)) != nil {
			t.Errorf("%s: parsed", name)
		}
	}
}

func TestParseAbduco(t *testing.T) {
	got := parseAbduco(listing(t))
	var names, marks, pids []string
	for _, s := range got {
		names, marks, pids = append(names, s.Name), append(marks, string(s.Mark)), append(pids, s.Pid)
	}
	want := []string{"ask-needs", "ask-wait", "ask-idle", "work-live", "work-stale", "odd-state", "ended-cmd", "stateless", "gone-cmd"}
	if !slices.Equal(names, want) {
		t.Fatalf("names %q", names)
	}
	if !slices.Equal(marks, []string{"*", " ", " ", "*", " ", " ", "+", " ", "+"}) || pids[0] != "101" || pids[8] != "109" {
		t.Fatalf("marks %q pids %q", marks, pids)
	}
	if parseAbduco(nil) != nil || parseAbduco([]byte("Active sessions (on host x)\n")) != nil {
		t.Fatal("empty list")
	}
	live, err := func() (map[string]int, error) {
		stubAbduco(t, listing(t), nil)
		return readAbduco()
	}()
	mustDo(t, err)
	if live["ask-needs"] != liveRunning || live["ended-cmd"] != liveEnded || live["gone-cmd"] != liveEnded {
		t.Fatalf("liveness %v", live)
	}
	if _, listed := live["closed"]; listed {
		t.Fatal("closed listed")
	}
}

// Every row of the plan's state / liveness table.
func TestAgentColumnOf(t *testing.T) {
	recent := testNow - 60_000
	for _, c := range []struct {
		name            string
		in              sessionInput
		kind, col, chip string
		stale, asking   bool
		current         string
	}{
		{"needs-you", sessionInput{State: "needs-you", Notice: "permission Bash", Live: liveRunning}, "needs-you", "ask", "", false, true, "permission Bash"},
		{"waiting", sessionInput{State: "waiting", Notice: "old", Live: liveRunning}, "waiting", "ask", "à toi", false, false, ""},
		{"idle", sessionInput{State: "idle", Live: liveRunning}, "idle", "ask", "pas encore lancée", false, false, ""},
		{"working", sessionInput{State: "working", Live: liveRunning}, "working", "work", "", false, false, ""},
		{"working stale", sessionInput{State: "working", Live: liveRunning, UpdatedAt: testNow - 40*60_000}, "working", "stuck", "rien depuis 40 min", true, false, ""},
		{"done", sessionInput{State: "done", Live: liveAbsent}, "done", "done", "", false, false, ""},
		{"done ended", sessionInput{State: "done", Live: liveEnded}, "done", "done", "", false, false, ""},
		{"ended +", sessionInput{State: "working", Live: liveEnded}, "done", "done", "commande terminée", false, false, ""},
		{"absent", sessionInput{State: "needs-you", Notice: "x", Live: liveAbsent}, "done", "done", "session fermée", false, false, ""},
		{"no state file", sessionInput{Live: liveRunning, noState: true}, "other", "stuck", "sans état", false, false, ""},
		{"unknown word", sessionInput{State: "paused", Live: liveRunning}, "other", "stuck", "paused", false, false, ""},
		{"empty word", sessionInput{State: "", Live: liveRunning}, "other", "stuck", "état vide", false, false, ""},
		{"abduco failed: never ended", sessionInput{State: "waiting", Live: liveUnknown}, "waiting", "ask", "à toi", false, false, ""},
	} {
		in := c.in
		in.Name = "s"
		if in.UpdatedAt == 0 && !in.noState {
			in.UpdatedAt = recent
		}
		a := deriveAgent(&in, testNow)
		chip := ""
		if len(a.Chips) > 0 {
			chip = a.Chips[0].Label
		}
		if a.Kind != c.kind || a.Column != c.col || chip != c.chip || a.Stale != c.stale || a.Asking != c.asking || a.Current != c.current {
			t.Errorf("%s: kind %q col %q chip %q stale %v asking %v current %q", c.name, a.Kind, a.Column, chip, a.Stale, a.Asking, a.Current)
		}
	}
}

// staleMs and keepMs at their edges.
func TestStaleAndKeep(t *testing.T) {
	at := func(state string, ago float64) *sessionInput {
		return &sessionInput{Name: "s", State: state, Live: liveRunning, UpdatedAt: testNow - ago}
	}
	if a := deriveAgent(at("working", staleMs), testNow); a.Column != "work" {
		t.Fatal("stale at exactly staleMs")
	}
	if a := deriveAgent(at("working", staleMs+1), testNow); a.Column != "stuck" {
		t.Fatal("not stale past staleMs")
	}
	b := deriveAgents([]*sessionInput{at("done", keepMs), at("done", keepMs+1), at("waiting", 3*keepMs)}, testNow)
	if b.total != 2 || b.old != 1 || len(b.cols[colIndex("done")]) != 1 || len(b.cols[colIndex("ask")]) != 1 {
		t.Fatalf("keep: total %d old %d", b.total, b.old)
	}
	// Ended by abduco counts as done for the 24 h keep.
	gone := at("working", keepMs+1)
	gone.Live = liveAbsent
	if b := deriveAgents([]*sessionInput{gone}, testNow); b.old != 1 || b.total != 0 {
		t.Fatal("an old closed session kept")
	}
	if hiddenText(b) != "1 terminée depuis plus de 24 h masquée" || hiddenText(agentsBoard{}) != "" {
		t.Fatalf("hidden %q", hiddenText(b))
	}
}

func TestReadSessionsColumns(t *testing.T) {
	stubAbduco(t, listing(t), nil)
	f := newSessionsFixture(t)
	read, b := f.read(t)
	wantProblems := []string{"big : 64 Ko, plus de 64 Ko : non lu", "fifo : pas un fichier ordinaire : non lu", "linked : lien : non lu"}
	if !slices.Equal(read.problems, wantProblems) {
		t.Fatalf("problems %q", read.problems)
	}
	for key, want := range map[string][]string{
		"ask":   {"ask-needs", "ask-wait", "ask-idle"}, // bgOrder: needs-you, waiting, idle
		"work":  {"work-live"},
		"stuck": {"work-stale", "odd-state", "stateless"}, // working (stale) before other; newest first
		"done":  {"closed", "ended-cmd", "done-recent"},   // newest first
	} {
		if got := colIDs(b, key); !slices.Equal(got, want) {
			t.Errorf("%s: %v, want %v", key, got, want)
		}
	}
	if b.total != 10 || b.old != 1 {
		t.Fatalf("total %d, old %d", b.total, b.old)
	}
	if a := agentOf(t, b, "ask-needs"); !a.Asking || a.Current != "Claude needs your permission to use Bash (token=•••" || a.Mission != "corrige le login qui boucle" || a.Project != "Beta" || a.Age != "il y a 3 min" {
		t.Fatalf("needs-you: %+v", a)
	}
	if a := agentOf(t, b, "ask-wait"); a.Project != "Gamma" || strings.Contains(a.Mission, "ghp_abcdefghijklmnop") || a.Chips[0].Label != "à toi" {
		t.Fatalf("waiting: %+v", a)
	}
	if a := agentOf(t, b, "work-live"); a.Mission != "/card X1 — monter vite en 7.3" || a.Project != "Alpha" {
		t.Fatalf("working: %+v", a)
	}
	if a := agentOf(t, b, "ended-cmd"); a.Chips[0].Label != "commande terminée" {
		t.Fatalf("ended: %+v", a.Chips)
	}
	if a := agentOf(t, b, "closed"); a.Chips[0].Label != "session fermée" {
		t.Fatalf("closed: %+v", a.Chips)
	}
	if a := agentOf(t, b, "stateless"); a.Chips[0].Label != "sans état" || a.Age != "date inconnue" {
		t.Fatalf("stateless: %+v", a)
	}
	if a := agentOf(t, b, "done-recent"); len(a.Chips) != 0 {
		t.Fatalf("done needs no reason: %+v", a.Chips)
	}
	for _, col := range b.cols {
		for _, a := range col {
			for _, bad := range []string{"no-cwd", "someone-else", "wrong-name", "-x", "Upper", "array", "bad-json", "gone-cmd", "linked", "big", "fifo", "done-old"} {
				if a.ID == bad {
					t.Fatalf("%s shown", bad)
				}
			}
		}
	}
}

// Only `<name>.json` with a valid name is read: anything else never reaches pick's argv.
func TestSessionNamesValidated(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "session-state")
	mustDo(t, os.MkdirAll(dir, 0o755))
	for _, name := range []string{"--help", "-x", "ABC", "a.b", ".s1", "s1.json.1.2", "ok-1"} {
		body := `{"name":"` + name + `","state":"needs-you","cwd":"/x","updatedAt":"2026-10-20T11:59:00.000Z"}`
		mustDo(t, os.WriteFile(filepath.Join(dir, name+".json"), []byte(body), 0o600))
	}
	mustDo(t, os.WriteFile(filepath.Join(dir, ".ok-1.json.99.1.tmp"), []byte(`{"name":"ok-1","state":"done","cwd":"/x"}`), 0o600))
	mustDo(t, os.MkdirAll(filepath.Join(dir, "sub"), 0o755))
	read, err := (&SessionsReader{Dir: dir}).Read()
	mustDo(t, err)
	var names []string
	for _, s := range read.sessions {
		names = append(names, s.Name)
	}
	if !slices.Equal(names, []string{"ok-1"}) || len(read.problems) != 0 || read.sessions[0].State != "needs-you" {
		t.Fatalf("listed %v, problems %q", names, read.problems)
	}
}

func TestSessionsReaderIncremental(t *testing.T) {
	f := newSessionsFixture(t)
	r := &SessionsReader{Dir: f.dir}
	first, err := r.Read()
	mustDo(t, err)
	again, err := r.Read()
	mustDo(t, err)
	find := func(rd sessionsRead, name string) *sessionInput {
		for _, s := range rd.sessions {
			if s.Name == name {
				return s
			}
		}
		return nil
	}
	if find(first, "ask-needs") == nil || find(first, "ask-needs") != find(again, "ask-needs") {
		t.Fatal("unchanged session parsed again")
	}
	if len(again.problems) != len(first.problems) {
		t.Fatalf("problems drift: %q", again.problems)
	}
	// As the writer does: a temp file renamed over the state file.
	tmp := filepath.Join(f.dir, ".ask-needs.json.1.2.tmp")
	mustDo(t, os.WriteFile(tmp, []byte(`{"name":"ask-needs","state":"done","cwd":"/x","updatedAt":"2026-10-20T11:59:00.000Z"}`), 0o600))
	mustDo(t, os.Rename(tmp, filepath.Join(f.dir, "ask-needs.json")))
	third, err := r.Read()
	mustDo(t, err)
	if s := find(third, "ask-needs"); s == nil || s.State != "done" {
		t.Fatal("changed session not read again")
	}
	// A cached parse is never mutated by a poll's liveness.
	withLiveness(third.sessions, map[string]int{})
	if find(third, "ask-needs").Live != liveUnknown {
		t.Fatal("cached session mutated")
	}
	if rd, err := (&SessionsReader{Dir: filepath.Join(t.TempDir(), "none")}).Read(); err != nil || len(rd.sessions) != 0 {
		t.Fatalf("missing dir: %v", err)
	}
}

// abduco failing marks nothing ended (fail-open) and says so in the tab.
func TestAbducoFailureFailsOpen(t *testing.T) {
	f := newSessionsFixture(t)
	stubAbduco(t, nil, errors.New("exit status 1"))
	p := pollAgents(&SessionsReader{Dir: f.dir})
	if p.err != nil || !slices.Contains(p.problems, "abduco : exit status 1 : sessions non vérifiées") {
		t.Fatalf("problems %q", p.problems)
	}
	read, _ := (&SessionsReader{Dir: f.dir}).Read()
	b := deriveAgents(withLiveness(read.sessions, nil), testNow)
	if a := agentOf(t, b, "closed"); a.Column != "ask" {
		t.Fatalf("closed drawn %q with abduco unknown", a.Column)
	}
	if a := agentOf(t, b, "ended-cmd"); a.Column != "stuck" || !a.Stale { // working, 20 min silent
		t.Fatalf("ended-cmd drawn %q with abduco unknown", a.Column)
	}
	if slices.Contains(colIDs(b, "stuck"), "stateless") {
		t.Fatal("a stateless session invented")
	}
}

func TestAbducoListNoBinary(t *testing.T) {
	prev := abducoBin
	defer func() { abducoBin = prev }()
	abducoBin = ""
	if _, err := abducoList(); err == nil || err.Error() != "binaire absent" {
		t.Fatalf("no binary: %v", err)
	}
	abducoBin = filepath.Join(t.TempDir(), "abduco")
	if _, err := abducoList(); err == nil {
		t.Fatal("a missing binary answered")
	}
}

// Enter, o and a card click run exactly [agentPaneBin, pick, name]; the board stays open.
func TestPick(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	calls := stubPick(t, nil)
	bin := agentPaneBin
	for i, k := range []tea.Msg{key(tea.KeyEnter), char('o')} {
		cmd := send(m, k)
		if cmd == nil || m.quit {
			t.Fatalf("%v: no pick Cmd, or quit", k)
		}
		if len(*calls) != i {
			t.Fatal("pick ran on the UI goroutine")
		}
		msg := cmd()
		if _, ok := msg.(tea.QuitMsg); ok {
			t.Fatal("pick quit")
		}
		send(m, msg)
	}
	want := []string{bin, "pick", "ask-needs"}
	if len(*calls) != 2 || !slices.Equal((*calls)[0], want) || !slices.Equal((*calls)[1], want) {
		t.Fatalf("calls %q", *calls)
	}
	if m.quit || m.ag.note != "affichée en haut : ask-needs" || !strings.Contains(strings.Join(plain(m.View().Content), "\n"), "affichée en haut : ask-needs") {
		t.Fatalf("note %q", m.ag.note)
	}
	send(m, key(tea.KeyDown))
	if m.ag.note != "" {
		t.Fatal("note not cleared by the next key")
	}
	// A click on a card selects it and picks it.
	*calls = nil
	card := findHit(m, hitCard, "work-live")
	cmd := send(m, tea.MouseClickMsg{X: card.x + 1, Y: card.y, Button: tea.MouseLeft})
	if cmd == nil {
		t.Fatal("click: no pick")
	}
	send(m, cmd())
	if len(*calls) != 1 || !slices.Equal((*calls)[0], []string{bin, "pick", "work-live"}) || m.ag.sel.id != "work-live" {
		t.Fatalf("click calls %q", *calls)
	}
	// A refused pick says stderr's first line.
	runPick = func([]string) error { return errors.New("name must match ^[a-z0-9][a-z0-9-]{0,47}$") }
	send(m, send(m, key(tea.KeyEnter))())
	if m.ag.note != "agent-pane pick work-live : name must match ^[a-z0-9][a-z0-9-]{0,47}$" {
		t.Fatalf("error note %q", m.ag.note)
	}
	// An invalid name never reaches runPick, nor does any name without the binary.
	*calls = nil
	runPick = func(argv []string) error { *calls = append(*calls, argv); return nil }
	for _, bad := range []string{"--help", "-x", "", "A", "a b", "a\n"} {
		if m.pickCmd(bad) != nil {
			t.Fatalf("pickCmd(%q) gave a Cmd", bad)
		}
	}
	agentPaneBin = ""
	if m.pickCmd("ask-needs") != nil || m.ag.note != "agent-pane : binaire absent, rien lancé" {
		t.Fatalf("no binary: note %q", m.ag.note)
	}
	if len(*calls) != 0 {
		t.Fatalf("runPick called: %q", *calls)
	}
}

func TestAgentsReadOnly(t *testing.T) {
	f := newSessionsFixture(t)
	before := append(snapshotTree(t, f.dir), snapshotTree(t, f.outside)...)
	m := agentsModel(t, f, 160, 48)
	m.View()
	all := strings.Join(plain(m.View().Content), "\n")
	if strings.Contains(all, "SECRET") {
		t.Fatal("a file outside the dir was drawn")
	}
	if after := append(snapshotTree(t, f.dir), snapshotTree(t, f.outside)...); !slices.Equal(before, after) {
		t.Fatal("the session-state dir changed")
	}
}

// snapshotTree: every path under root with its size, mode and mtime.
func snapshotTree(t testing.TB, root string) []string {
	var out []string
	mustDo(t, filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		fi, err := os.Lstat(p)
		if err != nil {
			return err
		}
		out = append(out, p+" "+fi.Mode().String()+" "+itoaT(int(fi.Size()))+" "+fi.ModTime().String())
		return nil
	}))
	return out
}

func TestRenderAgents(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	frame := m.View().Content
	lines := strings.Split(frame, "\n")
	if len(lines) != 50 {
		t.Fatalf("%d lines", len(lines))
	}
	for y, l := range lines {
		if w := visibleWidth(l); w != 180 {
			t.Fatalf("line %d width %d", y, w)
		}
		if w := lipgloss.Width(l); w != 180 {
			t.Fatalf("line %d lipgloss width %d", y, w)
		}
	}
	text := plain(frame)
	all := strings.Join(text, "\n")
	head := ""
	for _, l := range text {
		if strings.Contains(l, "Attend ta réponse") && strings.Contains(l, "Terminé") {
			head = l
		}
	}
	last := -1
	for _, c := range AgentColumns {
		at := strings.Index(head, c.Label)
		if at <= last {
			t.Fatalf("columns out of order in %q", head)
		}
		last = at
	}
	for _, want := range []string{
		"[Agents ● 3]", " Runs ", "session-state/ · 10 · 12:00:00",
		"ask-needs", "Beta", "il y a 3 min", "corrige le login qui boucle", "Claude needs your permission",
		"lit ?[31mrouge? le cache", "à toi", "pas encore lancée", "/card X1 — monter vite en 7.3", "Alpha",
		"rien depuis 40 min", "paused", "sans état", "commande terminée", "session fermée",
		"1 terminée depuis plus de 24 h masquée", "linked : lien : non lu", "⏎/o afficher en haut",
	} {
		if !strings.Contains(all, want) {
			t.Fatalf("%q not drawn:\n%s", want, all)
		}
	}
	for _, not := range []string{"[claude-dispatch]", "abcdef123456", "ghp_abcdefghijklmnop", "SECRET", "ancien travail", "NOCWD", "WRONGNAME", "DASHNAME", "TMPFILE", "UPPERNAME", "gone-cmd", "attach"} {
		if strings.Contains(all, not) {
			t.Fatalf("%q drawn", not)
		}
	}
	if !strings.Contains(frame, "\x1b[0;38;2;255;121;198") {
		t.Fatal("no human truecolor")
	}
	if strings.Contains(strings.ReplaceAll(frame, "\x1b[", ""), "\x1b") || strings.Contains(frame, "\x07") {
		t.Fatal("a control char reached the terminal")
	}
}

func TestRenderAgentsNarrow(t *testing.T) {
	f := newSessionsFixture(t)
	for _, wh := range [][2]int{{60, 30}, {23, 12}, {10, 5}, {1, 1}} {
		m := agentsModel(t, f, wh[0], wh[1])
		for pass := range 2 {
			lines := strings.Split(m.View().Content, "\n")
			if len(lines) != wh[1] {
				t.Fatalf("%v: %d lines", wh, len(lines))
			}
			for y, l := range lines {
				if visibleWidth(l) != wh[0] {
					t.Fatalf("%v pass %d line %d width %d", wh, pass, y, visibleWidth(l))
				}
			}
			m.ag.note, m.dirty = "affichée en haut : ask-needs", true
		}
	}
}

func TestAgentsTabKeys(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	stubPick(t, nil)
	m.tab = tabRuns
	m.dirty = true
	if !strings.Contains(plain(m.View().Content)[1], "[Runs]") {
		t.Fatalf("runs tab not shown active: %q", plain(m.View().Content)[1])
	}
	send(m, char('a'))
	if m.tab != tabAgents || !strings.Contains(plain(m.View().Content)[1], "[Agents ● 3]") {
		t.Fatal("a did not switch to Agents")
	}
	send(m, key(tea.KeyTab))
	if m.tab != tabRuns {
		t.Fatal("tab did not switch back")
	}
	send(m, char('a'))
	sel := func() string {
		s := m.agentSelection()
		if s.idx < 0 {
			return ""
		}
		return m.ag.board.cols[s.col][s.idx].ID
	}
	if sel() != "ask-needs" {
		t.Fatalf("first selection %q", sel())
	}
	send(m, key(tea.KeyDown))
	send(m, char('j'))
	if sel() != "ask-idle" {
		t.Fatalf("down: %q", sel())
	}
	send(m, key(tea.KeyRight))
	if sel() != "work-live" {
		t.Fatalf("right keeps the row, clamped: %q", sel())
	}
	send(m, char('l'))
	send(m, char('G'))
	if sel() != "stateless" {
		t.Fatalf("end: %q", sel())
	}
	send(m, char('l'))
	send(m, char('g'))
	if sel() != "closed" {
		t.Fatalf("home: %q", sel())
	}
	if cmd := send(m, char('r')); cmd == nil {
		t.Fatal("r did not poll")
	}
	if cmd := send(m, char('q')); cmd == nil || !m.quit {
		t.Fatal("q did not quit")
	}
}

func TestAgentsMouse(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 18) // short: Attend ta réponse overflows
	stubPick(t, nil)
	m.View()
	tabs := findHit(m, hitTab, "")
	if tabs == nil || tabs.col != tabRuns {
		t.Fatal("no Runs tab hit")
	}
	send(m, tea.MouseClickMsg{X: tabs.x, Y: tabs.y, Button: tea.MouseLeft})
	if m.tab != tabRuns {
		t.Fatal("tab click")
	}
	var agentsTab *hit
	for i := range m.hits {
		if m.hits[i].kind == hitTab && m.hits[i].col == tabAgents {
			agentsTab = &m.hits[i]
		}
	}
	send(m, tea.MouseClickMsg{X: agentsTab.x, Y: agentsTab.y, Button: tea.MouseLeft})
	if m.tab != tabAgents {
		t.Fatal("agents tab click")
	}
	col := findHit(m, hitCol, "")
	before := m.ag.scroll[0]
	send(m, tea.MouseWheelMsg{X: col.x + 1, Y: col.y + 4, Button: tea.MouseWheelDown})
	if m.ag.scroll[0] <= before {
		t.Fatal("wheel did not scroll the column")
	}
}

func TestAgentsPollOffLoop(t *testing.T) {
	f := newFixture(t)
	sf := newSessionsFixture(t)
	called := 0
	prev := abducoList
	abducoList = func() ([]byte, error) { called++; return []byte("Active sessions (on host x)\n"), nil }
	defer func() { abducoList = prev }()
	m := newModel(f.runs, f.budget, "fixture", 120, 40)
	m.setSessionsDir(sf.dir)
	_, cmd := m.Update(pollTickMsg{})
	if cmd == nil || m.ag.status != nil || called != 0 {
		t.Fatal("sessions read on the UI goroutine")
	}
	msg := cmd()
	pm, ok := msg.(pollMsg)
	if !ok || pm.agents == nil || pm.agents.err != nil || len(pm.cards) != 3 || called != 1 {
		t.Fatalf("poll result %+v", msg)
	}
	_, next := m.Update(msg)
	if next == nil || m.ag.status == nil || !m.ag.status.ok || m.status == nil || !m.status.ok {
		t.Fatal("agents poll not applied")
	}
	// An empty abduco list: every session with a state file is gone, none is stateless.
	if len(m.ag.board.cols[colIndex("ask")]) != 0 || len(m.ag.board.cols[colIndex("work")]) != 0 {
		t.Fatalf("sessions absent from abduco still live: %v", colIDs(m.ag.board, "ask"))
	}
}

func TestAgentsSnapshotFlag(t *testing.T) {
	f := newSessionsFixture(t)
	stubAbduco(t, listing(t), nil)
	r, w, err := os.Pipe()
	mustDo(t, err)
	stdout := os.Stdout
	os.Stdout = w
	rc := run([]string{"--sessions", f.dir, "--agents-snapshot", "120", "30"})
	os.Stdout = stdout
	mustDo(t, w.Close())
	out, err := io.ReadAll(r)
	mustDo(t, err)
	if rc != 0 || !strings.Contains(string(out), "Attend ta réponse") || !strings.Contains(string(out), "ask-needs") || strings.Contains(string(out), "\x1b") {
		t.Fatalf("rc %d:\n%s", rc, out)
	}
	er, ew, err := os.Pipe()
	mustDo(t, err)
	stderr := os.Stderr
	os.Stderr = ew
	bad := run([]string{"--agents-snapshot", "x", "3"})
	open := run([]string{"--agents-snapshot", "80", "24", "open"})
	noDir := run([]string{"--sessions"})
	os.Stderr = stderr
	mustDo(t, ew.Close())
	msg, _ := io.ReadAll(er)
	if bad != 2 || open != 2 || noDir != 2 || !strings.Contains(string(msg), "usage") {
		t.Fatalf("usage rc %d %d %d: %s", bad, open, noDir, msg)
	}
}

func BenchmarkAgentsView(b *testing.B) {
	sessions := make([]*sessionInput, 80)
	states := []string{"needs-you", "waiting", "working", "done", "idle"}
	for i := range sessions {
		sessions[i] = &sessionInput{
			Name: "session-" + itoaT(i), Cwd: "/Users/u/projects/P" + itoaT(i%7), State: states[i%len(states)], Live: liveRunning,
			Intent: "mission " + strings.Repeat("longue ", 8), Notice: "étape en cours " + itoaT(i), UpdatedAt: testNow - float64(i)*120_000,
		}
	}
	m := newModel("", "", "bench", 200, 60)
	m.tab = tabAgents
	m.applyAgents(&agentsPoll{board: deriveAgents(sessions, testNow), now: testNow, clock: "12:00:00"})
	m.View()
	b.ReportAllocs()
	for i := 0; b.Loop(); i++ {
		m.tick = i%2 == 0
		m.dirty = true
		m.View()
	}
}
