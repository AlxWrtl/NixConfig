package main

// The Runs tab also reads the agents' runs: `<repo>/.claude/worktrees/<name>/.claude/output/apex`
// and `<genericRoot>/<name>/.claude/output/apex`. Each link of the way must be a real dir; a
// link's target sits inside the agents' dir here, so only the Lstat guard can refuse it (the
// realpath guard has its own test).

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

type agentFixture struct {
	root, repo, runs, wt, gen string
}

func putFile(t *testing.T, p, text string) {
	t.Helper()
	mustDo(t, os.MkdirAll(filepath.Dir(p), 0o755))
	mustDo(t, os.WriteFile(p, []byte(text), 0o644))
}

// apexOf: the runs dir of an agent's home dir.
func apexOf(home string) string { return filepath.Join(home, ".claude", "output", "apex") }

// newAgentFixture: main run r1; worktree agent wa with r1 (same id) and r2; generic ga with g1.
func newAgentFixture(t *testing.T) *agentFixture {
	t.Helper()
	root := t.TempDir()
	f := &agentFixture{root: root, repo: filepath.Join(root, "repo")}
	f.runs = apexOf(f.repo)
	f.wt = filepath.Join(f.repo, ".claude", "worktrees")
	f.gen = filepath.Join(root, "agents")
	putFile(t, filepath.Join(f.runs, "r1", "00-context.md"), ctxText("main-one", nil))
	putFile(t, filepath.Join(apexOf(filepath.Join(f.wt, "wa")), "r1", "00-context.md"), ctxText("wt-one", nil))
	putFile(t, filepath.Join(apexOf(filepath.Join(f.wt, "wa")), "r1", "wt-only.md"), "# only in wa\n")
	putFile(t, filepath.Join(apexOf(filepath.Join(f.wt, "wa")), "r2", "00-context.md"), ctxText("wt-two", nil))
	putFile(t, filepath.Join(apexOf(filepath.Join(f.gen, "ga")), "g1", "00-context.md"), ctxText("gen-one", nil))
	stubGenericRoot(t, f.gen)
	return f
}

// keys: the card keys of an interactive read, sorted.
func (f *agentFixture) keys(t *testing.T) []string {
	t.Helper()
	runs, problems, err := (&Reader{RunsDir: f.runs, Agents: true}).Read()
	mustDo(t, err)
	if len(problems) != 0 {
		t.Fatalf("problems: %v", problems)
	}
	out := []string{}
	for _, r := range runs {
		out = append(out, deriveRun(r, 0).key())
	}
	slices.Sort(out)
	return out
}

func wantKeys(t *testing.T, got []string, want ...string) {
	t.Helper()
	slices.Sort(want)
	if !slices.Equal(got, want) {
		t.Fatalf("keys %v, want %v", got, want)
	}
}

func TestAgentRunsListed(t *testing.T) {
	f := newAgentFixture(t)
	runs, _, err := (&Reader{RunsDir: f.runs, Agents: true}).Read()
	mustDo(t, err)
	got := map[string]*Card{}
	for _, r := range runs {
		c := deriveRun(r, 0)
		got[c.key()] = c
		if strings.Contains(r.ID, "/") {
			t.Fatalf("RunInput.ID %q is not the bare run id", r.ID)
		}
	}
	for k, want := range map[string][2]string{"r1": {"main-one", ""}, "wa/r1": {"wt-one", "agent wa"}, "wa/r2": {"wt-two", "agent wa"}, "~ga/g1": {"gen-one", "générique ga"}} {
		c := got[k]
		if c == nil || c.Title != want[0] || c.source.label() != want[1] {
			t.Fatalf("card %s: %+v, want title %q label %q", k, c, want[0], want[1])
		}
	}
	if len(got) != 4 {
		t.Fatalf("%d cards, want 4", len(got))
	}
	// Drawn: the label on the agent cards, none on the board's own.
	m := newModel(f.runs, "", "repo", 220, 60)
	send(m, m.pollCmd()())
	frame := strings.Join(plain(m.View().Content), "\n")
	for _, s := range []string{"agent wa", "générique ga", "main-one", "wt-one", "gen-one"} {
		if !strings.Contains(frame, s) {
			t.Fatalf("frame lacks %q:\n%s", s, frame)
		}
	}
	if n := strings.Count(frame, "agent wa"); n != 2 {
		t.Fatalf("%d « agent wa » labels, want 2", n)
	}
}

// readRuns (--derive-json) and a Reader without Agents read the board's own runs only.
func TestAgentRunsNotInDerive(t *testing.T) {
	f := newAgentFixture(t)
	runs, _, err := readRuns(f.runs, "")
	mustDo(t, err)
	if len(runs) != 1 || runs[0].ID != "r1" || runs[0].source != nil {
		t.Fatalf("readRuns read %d runs", len(runs))
	}
}

// Without a tab repo (runs dir not `<repo>/.claude/output/apex`): no worktree source.
func TestAgentRunsNoTabRepo(t *testing.T) {
	f := newAgentFixture(t)
	stubGenericRoot(t, filepath.Join(f.root, "none"))
	runs := filepath.Join(f.root, "plain")
	putFile(t, filepath.Join(runs, "p1", "00-context.md"), ctxText("plain", nil))
	mustDo(t, os.MkdirAll(filepath.Join(f.root, ".claude"), 0o755))
	mustDo(t, os.Rename(filepath.Join(f.repo, ".claude", "worktrees"), filepath.Join(f.root, ".claude", "worktrees")))
	f.runs = runs
	wantKeys(t, f.keys(t), "p1")
}

// A board opened in a worktree reads that worktree's runs once, as its own.
func TestAgentRunsBoardInWorktree(t *testing.T) {
	f := newAgentFixture(t)
	f.runs = apexOf(filepath.Join(f.wt, "wa"))
	wantKeys(t, f.keys(t), "r1", "r2", "~ga/g1")
}

// move: dir moved to `to` (inside the agents' dir) and a link left in its place.
func move(t *testing.T, dir, to string) {
	t.Helper()
	mustDo(t, os.Rename(dir, to))
	mustDo(t, os.Symlink(to, dir))
}

func TestAgentRunsLinkGuards(t *testing.T) {
	for _, tc := range []struct {
		name string
		do   func(t *testing.T, f *agentFixture)
		want []string
	}{
		{"worktrees", func(t *testing.T, f *agentFixture) {
			move(t, f.wt, filepath.Join(f.repo, ".claude", "wt-real"))
		}, []string{"r1", "~ga/g1"}},
		{"repo .claude", func(t *testing.T, f *agentFixture) {
			// The board's own runs dir follows it (as before); the agents' do not.
			move(t, filepath.Join(f.repo, ".claude"), filepath.Join(f.repo, "claude-real"))
		}, []string{"r1", "~ga/g1"}},
		{"name", func(t *testing.T, f *agentFixture) {
			putFile(t, filepath.Join(apexOf(filepath.Join(f.wt, "x-real")), "l1", "00-context.md"), ctxText("linked", nil))
			mustDo(t, os.Rename(filepath.Join(f.wt, "x-real"), filepath.Join(f.wt, ".x-real")))
			mustDo(t, os.Symlink(filepath.Join(f.wt, ".x-real"), filepath.Join(f.wt, "wl")))
		}, []string{"r1", "wa/r1", "wa/r2", "~ga/g1"}},
		{"agent .claude", func(t *testing.T, f *agentFixture) {
			move(t, filepath.Join(f.wt, "wa", ".claude"), filepath.Join(f.wt, "wa", "claude2"))
		}, []string{"r1", "~ga/g1"}},
		{"output", func(t *testing.T, f *agentFixture) {
			move(t, filepath.Join(f.wt, "wa", ".claude", "output"), filepath.Join(f.wt, "wa", ".claude", "out2"))
		}, []string{"r1", "~ga/g1"}},
		{"apex", func(t *testing.T, f *agentFixture) {
			move(t, apexOf(filepath.Join(f.wt, "wa")), filepath.Join(f.wt, "wa", ".claude", "output", "apex2"))
		}, []string{"r1", "~ga/g1"}},
		{"generic root", func(t *testing.T, f *agentFixture) {
			move(t, f.gen, filepath.Join(f.root, "agents-real"))
		}, []string{"r1", "wa/r1", "wa/r2"}},
		{"generic apex", func(t *testing.T, f *agentFixture) {
			move(t, apexOf(filepath.Join(f.gen, "ga")), filepath.Join(f.gen, "ga", "apex2"))
		}, []string{"r1", "wa/r1", "wa/r2"}},
		{"invalid name", func(t *testing.T, f *agentFixture) {
			putFile(t, filepath.Join(apexOf(filepath.Join(f.wt, "Bad_Name")), "b1", "00-context.md"), ctxText("bad", nil))
			putFile(t, filepath.Join(apexOf(filepath.Join(f.wt, "-x")), "b2", "00-context.md"), ctxText("dash", nil))
		}, []string{"r1", "wa/r1", "wa/r2", "~ga/g1"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newAgentFixture(t)
			tc.do(t, f)
			wantKeys(t, f.keys(t), tc.want...)
		})
	}
}

// The source's realpath must stay under the agents' dir as discovered: a repo swapped for a
// link to a same-shaped tree (every link below it still a real dir) is refused.
func TestAgentRunsRealpathGuard(t *testing.T) {
	f := newAgentFixture(t)
	srcs, problems := agentSources(f.runs)
	if len(problems) != 0 || len(srcs) != 2 {
		t.Fatalf("sources %d, problems %v", len(srcs), problems)
	}
	if _, ok, err := srcs[0].check(); err != nil || !ok {
		t.Fatalf("check before the swap: %v %v", ok, err)
	}
	other := filepath.Join(f.root, "other")
	mustDo(t, os.Rename(f.repo, other))
	mustDo(t, os.Symlink(other, f.repo))
	if _, ok, err := srcs[0].check(); err != nil || ok {
		t.Fatalf("check after the swap: %v %v, want refused", ok, err)
	}
}

// A run file of an agent that links out of its source is not read (realInside, source as base).
func TestAgentRunsFileOutsideSource(t *testing.T) {
	f := newAgentFixture(t)
	secret := filepath.Join(f.root, "secret-ctx.md")
	putFile(t, secret, ctxText("secret", nil))
	ln := filepath.Join(apexOf(filepath.Join(f.wt, "wa")), "r3", "00-context.md")
	mustDo(t, os.MkdirAll(filepath.Dir(ln), 0o755))
	mustDo(t, os.Symlink(secret, ln))
	runs, _, err := (&Reader{RunsDir: f.runs, Agents: true}).Read()
	mustDo(t, err)
	for _, r := range runs {
		if deriveRun(r, 0).key() == "wa/r3" {
			if r.Context != nil {
				t.Fatal("wa/r3 read a context outside its source")
			}
			return
		}
	}
	t.Fatal("wa/r3 not listed")
}

// The drawer of an agent's card lists and reads its source, not the board's runs dir; a
// source swapped for a link after the poll is not read.
func TestAgentRunsDrawer(t *testing.T) {
	f := newAgentFixture(t)
	m := newModel(f.runs, "", "repo", 220, 60)
	send(m, m.pollCmd()())
	send(m, m.openDrawer(0, 0, "wa/r1")())
	if m.drawer == nil || !slices.Contains(m.drawer.files, "wt-only.md") {
		t.Fatalf("drawer of wa/r1: %+v", m.drawer)
	}
	send(m, m.fileAt(slices.Index(m.drawer.files, "wt-only.md"))())
	if m.drawer.doc == nil || !strings.Contains(m.drawer.doc.Text, "only in wa") {
		t.Fatalf("doc of wa/r1: %+v", m.drawer.doc)
	}
	frame := strings.Join(plain(m.View().Content), "\n")
	if !strings.Contains(frame, "r1 · agent wa") {
		t.Fatalf("drawer head lacks the agent:\n%s", frame)
	}
	send(m, key('q'))
	send(m, m.openDrawer(0, 0, "r1")())
	if m.drawer == nil || slices.Contains(m.drawer.files, "wt-only.md") || !slices.Contains(m.drawer.files, "00-context.md") {
		t.Fatalf("drawer of r1: %+v", m.drawer)
	}
	send(m, key('q'))
	cmd := m.openDrawer(0, 0, "wa/r2")
	move(t, apexOf(filepath.Join(f.wt, "wa")), filepath.Join(f.wt, "wa", ".claude", "output", "apex2"))
	send(m, cmd())
	if m.drawer == nil || len(m.drawer.files) != 0 || m.drawer.doc == nil || m.drawer.doc.Kind != "outside" {
		t.Fatalf("drawer of a swapped source: %+v", m.drawer)
	}
	if d := loadDocFrom(f.runs, m.drawer.src, "r2", "00-context.md"); d.Kind != "outside" {
		t.Fatalf("doc of a swapped source: %+v", d)
	}
}
