package main

// The Agents tab: testdata/jobs (one session per observed state tuple: done/idle, blocked/active,
// working/idle, working/blocked never started, plus failed, stopped, stale working, needs-you by
// `needs`, by `block.questions` and by the last reply, stalled, an unknown state, a finished one
// over 24 h, a half-written state.json) copied to a temp dir, where the edges that cannot live in
// git are added: a dir without state.json, a state.json link and a dir link out of the jobs dir,
// an oversized state.json, a timeline link, control chars and secrets in a detail.

import (
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

var testNow = float64(time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC).UnixMilli())

type jobsFixture struct{ jobs, outside string }

func newJobsFixture(t *testing.T) *jobsFixture {
	t.Helper()
	root := t.TempDir()
	f := &jobsFixture{jobs: filepath.Join(root, "jobs"), outside: filepath.Join(root, "outside")}
	copyTree(t, "testdata/jobs", f.jobs)
	put := func(rel, text string) {
		p := filepath.Join(f.jobs, rel)
		mustDo(t, os.MkdirAll(filepath.Dir(p), 0o755))
		mustDo(t, os.WriteFile(p, []byte(text), 0o600))
	}
	// Control chars and secrets, written here: raw control bytes are no valid JSON in a file.
	put("a000000a/state.json", `{"name":null,"nameSource":"auto","state":"working","tempo":"active","intent":"explore le cache","detail":"lit \u001b[31mrouge\u0007 avec token=abcdef123456 et ghp_abcdefghijklmnop","cwd":"/Users/u/projects/Gamma/","updatedAt":"2026-10-20T11:59:30.000Z"}`)
	put("a000000a/timeline.jsonl", `{"at":"2026-10-20T11:59:30.000Z","state":"working","detail":"lecture"}`+"\n")
	mustDo(t, os.MkdirAll(filepath.Join(f.jobs, "b0000001", "tmp"), 0o755)) // never wrote its state
	mustDo(t, os.MkdirAll(f.outside, 0o755))
	secret := `{"name":"SECRET-OUTSIDE","state":"blocked","cwd":"/x","intent":"x","updatedAt":"2026-10-20T11:59:00.000Z"}`
	mustDo(t, os.WriteFile(filepath.Join(f.outside, "state.json"), []byte(secret), 0o600))
	mustDo(t, os.WriteFile(filepath.Join(f.outside, "timeline.jsonl"), []byte(`{"at":"2026-10-20T11:59:00.000Z","state":"blocked","detail":"SECRET-TIMELINE"}`+"\n"), 0o600))
	mustDo(t, os.MkdirAll(filepath.Join(f.jobs, "b0000002"), 0o755))
	mustDo(t, os.Symlink(filepath.Join(f.outside, "state.json"), filepath.Join(f.jobs, "b0000002", "state.json")))
	put("b0000003/state.json", `{"name":"big","state":"working","cwd":"/x","pad":"`+strings.Repeat("x", maxStateBytes)+`"}`)
	mustDo(t, os.Symlink(f.outside, filepath.Join(f.jobs, "b0000004"))) // a dir link: never listed
	put("b0000005/state.json", `{"name":"linked-tl","state":"blocked","tempo":"active","cwd":"/x","intent":"x","updatedAt":"2026-10-20T11:00:00.000Z"}`)
	mustDo(t, os.Symlink(filepath.Join(f.outside, "timeline.jsonl"), filepath.Join(f.jobs, "b0000005", "timeline.jsonl")))
	put("pins.json", `[]`)
	return f
}

func (f *jobsFixture) read(t *testing.T) (jobsRead, agentsBoard) {
	t.Helper()
	r := &JobsReader{Dir: f.jobs}
	read, err := r.Read()
	mustDo(t, err)
	return read, deriveAgents(read.jobs, read.empty, testNow)
}

func agentsModel(t *testing.T, f *jobsFixture, w, h int) *Model {
	t.Helper()
	m := newModel("", "", "fixture", w, h)
	m.setJobsDir(f.jobs)
	m.tab = tabAgents
	read, err := m.ag.reader.Read()
	mustDo(t, err)
	m.applyAgents(&agentsPoll{board: deriveAgents(read.jobs, read.empty, testNow), problems: read.problems, now: testNow, clock: "12:00:00"})
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

// deck's bgKind table (background.ts), case by case.
func TestBgKindIsDecks(t *testing.T) {
	for _, c := range []struct {
		state, tempo string
		asks         bool
		want         string
	}{
		{"working", "blocked", true, "needs-you"},
		{"working", "blocked", false, "stalled"},
		{"Working", "blocked", false, "working"}, // the blocked rule is exact case, as deck's
		{"working", "Blocked", true, "working"},
		{"working", "idle", false, "working"},
		{"working", "active", true, "working"},
		{"blocked", "active", false, "needs-you"},
		{"BLOCKED", "", false, "needs-you"},
		{"done", "idle", false, "done"},
		{"completed", "", false, "done"},
		{"failed", "", false, "failed"},
		{"error", "", false, "failed"},
		{"stopped", "", false, "stopped"},
		{"killed", "", false, "stopped"},
		{"paused", "", false, "other"},
		{"", "", false, "other"},
	} {
		if got := bgKind(c.state, c.tempo, c.asks); got != c.want {
			t.Errorf("bgKind(%q, %q, %v) = %q, want %q", c.state, c.tempo, c.asks, got, c.want)
		}
	}
	if projectOf("/a/Repo/.claude/worktrees/x") != "Repo" || projectOf("/a/b/") != "b" || projectOf("/") != "/" {
		t.Fatal("projectOf is not deck's")
	}
}

func TestReadJobsColumns(t *testing.T) {
	f := newJobsFixture(t)
	read, b := f.read(t)
	// a0000004 (never started) and b0000001 (no state.json) are the empty ones.
	if read.empty != 2 || b.empty != 2 || b.old != 1 {
		t.Fatalf("empty %d, old %d", b.empty, b.old)
	}
	if len(read.problems) != 2 || !strings.Contains(read.problems[0], "b0000002 : state.json est un lien") || !strings.Contains(read.problems[1], "b0000003 : state.json de 256 Ko") {
		t.Fatalf("problems %q", read.problems)
	}
	for key, want := range map[string][]string{
		"ask":   {"a0000002", "a0000008", "a000000c", "a000000d", "b0000005"},
		"work":  {"a000000a", "a0000003"},
		"stuck": {"a0000009", "a0000005", "a0000007", "a000000e"}, // BG_ORDER: stalled, failed, working (stale), other
		"done":  {"a0000006", "a0000001"},                         // stopped before done, as BG_ORDER
	} {
		if got := colIDs(b, key); !slices.Equal(got, want) {
			t.Errorf("%s: %v, want %v", key, got, want)
		}
	}
	if b.total != 13 {
		t.Fatalf("total %d", b.total)
	}
	for _, id := range []string{"a0000004", "a000000b", "a000000f", "b0000001", "b0000002", "b0000003", "b0000004"} {
		for _, col := range b.cols {
			if slices.ContainsFunc(col, func(a *Agent) bool { return a.ID == id }) {
				t.Fatalf("%s shown", id)
			}
		}
	}
	// What each card says.
	if a := agentOf(t, b, "a0000002"); !a.Asking || a.Current != "Je merge la PR #12 ou j'attends ta relecture ?" || a.Age != "il y a 3 min" || a.Project != "Beta" {
		t.Fatalf("blocked/active: %+v", a)
	}
	if a := agentOf(t, b, "a0000008"); a.Current != "Autoriser l'édition de config.ts ?" {
		t.Fatalf("needs: %q", a.Current)
	}
	if a := agentOf(t, b, "a000000c"); a.Current != "Quelle base : Postgres ou SQLite ?" {
		t.Fatalf("block.questions: %q", a.Current)
	}
	if a := agentOf(t, b, "a000000d"); a.Current != "Je pars sur l'option A ?" {
		// no needs, questions nor detail: the last reply's last paragraph speaks
		t.Fatalf("last reply: %q", a.Current)
	}
	if a := agentOf(t, b, "a0000003"); a.Mission != "/card X1 — monter vite en 7.3" || a.Project != "Alpha" || a.Branch != "worktree-deps-bump" || a.Asking {
		t.Fatalf("working/idle: %+v", a)
	}
	if a := agentOf(t, b, "a0000007"); !a.Stale || a.Chips[0].Label != "rien depuis 40 min" {
		t.Fatalf("stale: %+v", a)
	}
	if a := agentOf(t, b, "a0000005"); a.Chips[0].State != "fail" || a.Chips[0].Label != "échec" {
		t.Fatalf("failed chip: %+v", a.Chips)
	}
	if a := agentOf(t, b, "a000000e"); a.Chips[0].Label != "paused" {
		t.Fatalf("other chip: %+v", a.Chips)
	}
	if a := agentOf(t, b, "a000000a"); a.Name != "" || a.Project != "Gamma" || strings.Contains(a.Current, "abcdef123456") || strings.Contains(a.Current, "ghp_abcdefghijklmnop") || !strings.Contains(a.Current, "token=•••") {
		t.Fatalf("redaction: %q", a.Current)
	}
	// b0000005's timeline is a link: not read, so no reply text and no timeline.
	if a := agentOf(t, b, "b0000005"); a.Current != "" || strings.Contains(a.Current, "SECRET") {
		t.Fatalf("linked timeline read: %q", a.Current)
	}
}

// Only an 8-char name of 0123456789abcdef is a session: anything else never reaches the argv
// of `claude attach`.
func TestJobDirNamesValidated(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "jobs")
	for _, id := range []string{"--help", "ABCDEF12", "a000000", "a00000001", "-x", "d0000001"} {
		mustDo(t, os.MkdirAll(filepath.Join(dir, id), 0o755))
		mustDo(t, os.WriteFile(filepath.Join(dir, id, "state.json"), []byte(`{"name":"n-`+id+`","state":"blocked","tempo":"active","cwd":"/x","intent":"x","updatedAt":"2026-10-20T11:59:00.000Z"}`), 0o600))
	}
	read, err := (&JobsReader{Dir: dir}).Read()
	mustDo(t, err)
	var ids []string
	for _, j := range read.jobs {
		ids = append(ids, j.ID)
	}
	if !slices.Equal(ids, []string{"d0000001"}) || read.empty != 0 || len(read.problems) != 0 {
		t.Fatalf("listed %v, empty %d, problems %q", ids, read.empty, read.problems)
	}
	if _, msg := loadAgentTimeline(dir, "--help"); msg == "" {
		t.Fatal("timeline of a non-id dir read")
	}
}

func TestAttachIDCheck(t *testing.T) {
	for id, want := range map[string]bool{
		"d0000001": true, "0123abcd": true, "fedcba98": true,
		"--help": false, "-x": false, "ABCDEF12": false, "a000000": false, "a00000001": false,
		"0123abcg": false, "0123abc-": false, "": false, "a000000\n": false, "a000000é": false, "../a0000": false,
	} {
		if got := validJobID(id); got != want {
			t.Errorf("validJobID(%q) = %v", id, got)
		}
	}
	defer func(f func(string, []string, []string) error) { execve = f }(execve)
	var execd [][]string
	execve = func(_ string, argv, _ []string) error {
		execd = append(execd, argv)
		return os.ErrPermission
	}
	defer func(f func(string) (string, error)) { lookPath = f }(lookPath)
	lookPath = func(string) (string, error) { return "/bin/claude", nil }
	er, ew, err := os.Pipe()
	mustDo(t, err)
	stderr := os.Stderr
	os.Stderr = ew
	rc := execAttach("--help")
	good := execAttach("d0000001")
	os.Stderr = stderr
	mustDo(t, ew.Close())
	msg, _ := io.ReadAll(er)
	if rc != 1 || !strings.Contains(string(msg), "pas un id de session") {
		t.Fatalf("execAttach(--help) rc %d: %s", rc, msg)
	}
	if good != 1 || len(execd) != 1 || !slices.Equal(execd[0], []string{"claude", "attach", "d0000001"}) {
		t.Fatalf("exec calls %q (rc %d): only the valid id may be execed", execd, good)
	}
	m := newModel("", "", "", 80, 24)
	if m.attachTo("--help") != nil || m.attach != "" {
		t.Fatal("attachTo took a non-id")
	}
}

func TestDetailBeforeLastReply(t *testing.T) {
	f := newJobsFixture(t)
	p := filepath.Join(f.jobs, "a000000d", "state.json")
	data, err := os.ReadFile(p)
	mustDo(t, err)
	mustDo(t, os.WriteFile(p, []byte(strings.Replace(string(data), `"detail":null`, `"detail":"Analyse terminée"`, 1)), 0o600))
	_, b := f.read(t)
	if a := agentOf(t, b, "a000000d"); a.Current != "Analyse terminée" {
		t.Fatalf("detail: %q", a.Current)
	}
}

func TestTimelineFoldAndOrder(t *testing.T) {
	f := newJobsFixture(t)
	ev, err := loadAgentTimeline(f.jobs, "a0000002")
	if err != "" {
		t.Fatal(err)
	}
	var details []string
	for _, e := range ev {
		details = append(details, e.Detail)
	}
	want := []string{"Je merge la PR #12 ou j'attends ta relecture ?", "Correctif écrit, tests verts", "Lecture du module auth"}
	if !slices.Equal(details, want) {
		t.Fatalf("newest first, folded: %q", details)
	}
	if ev[2].Text != "Le module boucle sur le refresh." {
		t.Fatalf("folded reply text: %q", ev[2].Text)
	}
	if _, err := loadAgentTimeline(f.jobs, "b0000005"); !strings.Contains(err, "lien") {
		t.Fatalf("timeline link read: %q", err)
	}
	if _, err := loadAgentTimeline(f.jobs, "b0000004"); err == "" {
		t.Fatal("dir link read")
	}
	if _, err := loadAgentTimeline(f.jobs, "../outside"); err == "" {
		t.Fatal("traversal read")
	}
	if ev, err := loadAgentTimeline(f.jobs, "a0000005"); err != "" || ev == nil || len(ev) != 0 {
		t.Fatalf("no timeline: %v %q", ev, err)
	}
}

func TestTimelineTailCapped(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "jobs")
	mustDo(t, os.MkdirAll(filepath.Join(dir, "c0000001"), 0o755))
	var sb strings.Builder
	for i := 0; sb.Len() < maxTimelineBytes+200*1024; i++ {
		sb.WriteString(`{"at":"2026-10-20T11:00:00.000Z","state":"working","detail":"step ` + itoaT(i) + `","text":"` + strings.Repeat("y", 300) + `"}` + "\n")
	}
	p := filepath.Join(dir, "c0000001", "timeline.jsonl")
	mustDo(t, os.WriteFile(p, []byte(sb.String()), 0o600))
	tail, err := readTail(p, maxTimelineBytes)
	mustDo(t, err)
	if len(tail) > maxTimelineBytes || len(tail) == 0 || tail[0] != '{' {
		t.Fatalf("tail %d bytes, starts %q", len(tail), tail[:1])
	}
	ev, msg := loadAgentTimeline(dir, "c0000001")
	if msg != "" || len(ev) != timelineMax || !strings.HasSuffix(sb.String(), `"detail":"`+ev[0].Detail+`","text":"`+strings.Repeat("y", 300)+`"}`+"\n") {
		t.Fatalf("%d events, newest %q", len(ev), ev[0].Detail)
	}
}

func TestJobsReaderIncremental(t *testing.T) {
	f := newJobsFixture(t)
	r := &JobsReader{Dir: f.jobs}
	first, err := r.Read()
	mustDo(t, err)
	again, err := r.Read()
	mustDo(t, err)
	find := func(rd jobsRead, id string) *jobInput {
		for _, j := range rd.jobs {
			if j.ID == id {
				return j
			}
		}
		return nil
	}
	if find(first, "a0000002") != find(again, "a0000002") || find(again, "a0000002") == nil {
		t.Fatal("unchanged session parsed again")
	}
	p := filepath.Join(f.jobs, "a0000002", "state.json")
	mustDo(t, os.WriteFile(p, []byte(`{"name":"fix-login","state":"done","cwd":"/Users/u/projects/Beta","intent":"x","updatedAt":"2026-10-20T11:59:00.000Z"}`), 0o600))
	third, err := r.Read()
	mustDo(t, err)
	if j := find(third, "a0000002"); j == nil || j.State != "done" {
		t.Fatal("changed session not read again")
	}
	if rd, err := (&JobsReader{Dir: filepath.Join(t.TempDir(), "none")}).Read(); err != nil || len(rd.jobs) != 0 {
		t.Fatalf("missing jobs dir: %v", err)
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

func TestAgentsReadOnly(t *testing.T) {
	f := newJobsFixture(t)
	before := append(snapshotTree(t, f.jobs), snapshotTree(t, f.outside)...)
	m := agentsModel(t, f, 160, 48)
	runCmd(t, m, m.openAgentDrawer(0, 0, "a0000002"))
	m.View()
	all := strings.Join(plain(m.View().Content), "\n")
	if strings.Contains(all, "SECRET") {
		t.Fatal("a file outside the jobs dir was drawn")
	}
	if after := append(snapshotTree(t, f.jobs), snapshotTree(t, f.outside)...); !slices.Equal(before, after) {
		t.Fatal("the jobs dir changed")
	}
}

func TestRenderAgents(t *testing.T) {
	f := newJobsFixture(t)
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
		"[Agents ● 5]", " Runs ", "jobs/ · 13 · 12:00:00",
		"fix-login", "Beta", "il y a 3 min", "corrige le login qui boucle", "Je merge la PR #12",
		"sans nom · a000000a", "lit ?[31mrouge?", "token=•••", "/card X1 — monter vite en 7.3", "Alpha · worktree-deps",
		"échec", "arrêtée", "rien depuis 40 min", "paused", "bloquée sans question",
		"2 sessions vides masquées · 1 terminée depuis plus de 24 h masquée",
		"b0000002 : state.json est un lien", "o reprendre",
	} {
		if !strings.Contains(all, want) {
			t.Fatalf("%q not drawn:\n%s", want, all)
		}
	}
	for _, not := range []string{"[claude-dispatch]", "abcdef123456", "SECRET", "ancien", "half-written", "send a prompt"} {
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
	f := newJobsFixture(t)
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
			runCmd(t, m, m.openAgentDrawer(0, 0, "a0000002"))
		}
	}
}

func TestAgentsTabKeys(t *testing.T) {
	f := newJobsFixture(t)
	m := agentsModel(t, f, 180, 50)
	m.tab = tabRuns
	m.dirty = true
	if !strings.Contains(plain(m.View().Content)[1], "[Runs]") {
		t.Fatalf("runs tab not shown active: %q", plain(m.View().Content)[1])
	}
	send(m, char('a'))
	if m.tab != tabAgents || !strings.Contains(plain(m.View().Content)[1], "[Agents ● 5]") {
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
	if sel() != "a0000002" {
		t.Fatalf("first selection %q", sel())
	}
	send(m, key(tea.KeyDown))
	send(m, char('j'))
	if sel() != "a000000c" {
		t.Fatalf("down: %q", sel())
	}
	send(m, key(tea.KeyRight))
	if sel() != "a0000003" {
		t.Fatalf("right keeps the row, clamped: %q", sel())
	}
	send(m, char('l'))
	send(m, char('G'))
	if sel() != "a000000e" {
		t.Fatalf("end: %q", sel())
	}
	send(m, char('h'))
	send(m, char('g'))
	send(m, char('h'))
	cmd := send(m, key(tea.KeyEnter))
	if m.ag.drawer == nil || m.ag.drawer.id != "a0000002" {
		t.Fatal("enter opened no drawer")
	}
	runCmd(t, m, cmd)
	all := strings.Join(plain(m.View().Content), "\n")
	for _, want := range []string{"Reprendre : claude attach a0000002", "Mission : corrige le login qui boucle", "Correctif écrit, tests verts", "Le module boucle sur le refresh.", "attend", "travaille"} {
		if !strings.Contains(all, want) {
			t.Fatalf("drawer: %q missing\n%s", want, all)
		}
	}
	send(m, key(tea.KeyDown))
	send(m, key(tea.KeyEscape))
	if m.ag.drawer != nil {
		t.Fatal("esc did not close")
	}

	// o: claude missing says the command; present quits with the id for main to exec.
	defer func(f func(string) (string, error)) { lookPath = f }(lookPath)
	lookPath = func(string) (string, error) { return "", os.ErrNotExist }
	if c := send(m, char('o')); c != nil || m.attach != "" || !strings.Contains(strings.Join(plain(m.View().Content), "\n"), "claude introuvable dans le PATH : lance  claude attach a0000002") {
		t.Fatal("o without claude")
	}
	send(m, key(tea.KeyDown))
	if m.ag.note != "" {
		t.Fatal("note not cleared by the next key")
	}
	send(m, key(tea.KeyUp))
	lookPath = func(string) (string, error) { return "/bin/claude", nil }
	c := send(m, char('o'))
	if c == nil || m.attach != "a0000002" || !m.quit {
		t.Fatal("o did not ask for the attach")
	}
	if _, ok := c().(tea.QuitMsg); !ok {
		t.Fatal("o did not quit")
	}
}

func TestAgentsMouse(t *testing.T) {
	f := newJobsFixture(t)
	m := agentsModel(t, f, 180, 30)
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
	card := findHit(m, hitCard, "")
	cmd := send(m, tea.MouseClickMsg{X: card.x + 1, Y: card.y, Button: tea.MouseLeft})
	if m.ag.drawer == nil || m.ag.drawer.id != card.id {
		t.Fatal("card click")
	}
	runCmd(t, m, cmd)
	cl := findHit(m, hitClose, "")
	send(m, tea.MouseClickMsg{X: cl.x + 1, Y: cl.y + 1, Button: tea.MouseLeft})
	if m.ag.drawer != nil {
		t.Fatal("close click")
	}
}

func TestAgentsPollOffLoop(t *testing.T) {
	f := newFixture(t)
	jf := newJobsFixture(t)
	m := newModel(f.runs, f.budget, "fixture", 120, 40)
	m.setJobsDir(jf.jobs)
	_, cmd := m.Update(pollTickMsg{})
	if cmd == nil || m.ag.status != nil {
		t.Fatal("jobs read on the UI goroutine")
	}
	msg := cmd()
	pm, ok := msg.(pollMsg)
	if !ok || pm.agents == nil || pm.agents.err != nil || len(pm.cards) != 3 {
		t.Fatalf("poll result %+v", msg)
	}
	m.Update(msg)
	if m.ag.status == nil || !m.ag.status.ok || m.ag.board.empty != 2 || m.status == nil || !m.status.ok {
		t.Fatal("agents poll not applied")
	}
	// The open drawer reloads when its session moved.
	m.tab = tabAgents
	runCmd(t, m, m.openAgentDrawer(0, 0, "a0000002"))
	m.ag.drawer.loadedAt = 1
	_, cmd = m.Update(pollTickMsg{})
	_, next := m.Update(cmd())
	if next == nil {
		t.Fatal("no next poll")
	}
}

func TestAgentsSnapshotFlag(t *testing.T) {
	f := newJobsFixture(t)
	r, w, err := os.Pipe()
	mustDo(t, err)
	stdout := os.Stdout
	os.Stdout = w
	rc := run([]string{"--jobs", f.jobs, "--agents-snapshot", "120", "30", "open"})
	os.Stdout = stdout
	mustDo(t, w.Close())
	out, err := io.ReadAll(r)
	mustDo(t, err)
	if rc != 0 || !strings.Contains(string(out), "Attend ta réponse") || !strings.Contains(string(out), "Reprendre : claude attach a0000002") || strings.Contains(string(out), "\x1b") {
		t.Fatalf("rc %d:\n%s", rc, out)
	}
	er, ew, err := os.Pipe()
	mustDo(t, err)
	stderr := os.Stderr
	os.Stderr = ew
	bad := run([]string{"--agents-snapshot", "x", "3"})
	noDir := run([]string{"--jobs"})
	os.Stderr = stderr
	mustDo(t, ew.Close())
	msg, _ := io.ReadAll(er)
	if bad != 2 || noDir != 2 || !strings.Contains(string(msg), "usage") {
		t.Fatalf("usage rc %d %d: %s", bad, noDir, msg)
	}
}

func BenchmarkAgentsView(b *testing.B) {
	jobs := make([]*jobInput, 80)
	states := [][2]string{{"blocked", "active"}, {"working", "idle"}, {"working", "active"}, {"done", "idle"}, {"failed", "idle"}}
	for i := range jobs {
		s := states[i%len(states)]
		jobs[i] = &jobInput{
			ID: "j" + itoaT(1000000+i), Name: "session-" + itoaT(i), Cwd: "/Users/u/projects/P" + itoaT(i%7), State: s[0], Tempo: s[1],
			Intent: "mission " + strings.Repeat("longue ", 8), Detail: "étape en cours " + itoaT(i), UpdatedAt: testNow - float64(i)*120_000, HasTimeline: true,
		}
	}
	m := newModel("", "", "bench", 200, 60)
	m.tab = tabAgents
	m.applyAgents(&agentsPoll{board: deriveAgents(jobs, 3, testNow), now: testNow, clock: "12:00:00"})
	m.View()
	b.ReportAllocs()
	for i := 0; b.Loop(); i++ {
		m.tick = i%2 == 0
		m.dirty = true
		m.View()
	}
}
