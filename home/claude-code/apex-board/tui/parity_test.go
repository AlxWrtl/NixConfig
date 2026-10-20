package main

// Parity smoke test on testdata: the fixture runs aged as testdata/mtimes.tsv says, read by
// --derive-json; the À-toi / Terminé cases of test.js land where board.js puts them, and when
// node is on PATH, parity.js (board.js) writes the same bytes. The nix check runs the full
// comparison; this keeps a broken fixture or port from reaching it.

import (
	"bufio"
	"encoding/json"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

const parityNow = 1792500000000

// copyTree copies a fixture tree, links kept as links.
func copyTree(t *testing.T, src, dst string) {
	t.Helper()
	mustDo(t, filepath.WalkDir(src, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, p)
		out := filepath.Join(dst, rel)
		switch {
		case d.Type()&fs.ModeSymlink != 0:
			target, err := os.Readlink(p)
			if err != nil {
				return err
			}
			return os.Symlink(target, out)
		case d.IsDir():
			return os.MkdirAll(out, 0o755)
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		return os.WriteFile(out, b, 0o644)
	}))
}

// agedTestdata: a copy of testdata whose run files are dated NOW minus their mtimes.tsv age
// (1 h when not listed). Links are not touched: they may point out of the copy.
func agedTestdata(t *testing.T) string {
	t.Helper()
	dst := filepath.Join(t.TempDir(), "testdata")
	copyTree(t, "testdata", dst)
	ages := map[string]int64{}
	fh, err := os.Open(filepath.Join(dst, "mtimes.tsv"))
	mustDo(t, err)
	defer fh.Close()
	sc := bufio.NewScanner(fh)
	for sc.Scan() {
		id, age, ok := strings.Cut(sc.Text(), "\t")
		if !ok {
			continue
		}
		n, err := strconv.ParseInt(age, 10, 64)
		mustDo(t, err)
		ages[id] = n
	}
	mustDo(t, sc.Err())
	runs := filepath.Join(dst, "runs")
	entries, err := os.ReadDir(runs)
	mustDo(t, err)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		age, ok := ages[e.Name()]
		if !ok {
			age = 3600
		}
		at := time.Unix(parityNow/1000-age, 0)
		mustDo(t, filepath.WalkDir(filepath.Join(runs, e.Name()), func(p string, d fs.DirEntry, err error) error {
			if err != nil || !d.Type().IsRegular() {
				return err
			}
			return os.Chtimes(p, at, at)
		}))
	}
	return dst
}

func TestParityFixtures(t *testing.T) {
	dir := agedTestdata(t)
	runs, budget := filepath.Join(dir, "runs"), filepath.Join(dir, "budget")
	out, err := deriveJSON(runs, budget, parityNow)
	mustDo(t, err)

	var tree struct {
		Problems int
		Columns  []struct {
			Key   string
			More  int
			Cards []struct {
				ID, Column string
				Flag       *string
				Reasons    []string
			}
		}
	}
	mustDo(t, json.Unmarshal([]byte(out), &tree))
	where := map[string]string{}
	more := 0
	for _, c := range tree.Columns {
		for _, card := range c.Cards {
			where[card.ID] = c.Key
		}
		if c.Key == "done" {
			more = c.More
		}
	}
	want := map[string]string{
		"vorssaint-cask": "init", "01-worktree-env-sync": "human", "worktree-idle": "done", "wrangler-oauth-config": "done",
		"wrangler-execute": "execute", "live-failed": "human", "failed-red": "human", "failed-echoue": "human",
		"failed-bold": "human", "blocked-step": "human", "blocked-line": "human", "blocked-status": "human",
		"blocked-bullet": "human", "blocked-prose": "execute", "blocked-cell": "validate", "budget-spent": "human",
		"budget-granted": "execute", "ext-pass": "validate", "ext-fail": "human", "ext-blocked": "human",
		"ext-error": "human", "ext-half": "validate", "ext-rounds": "validate", "live-edge": "execute",
		"stale-edge": "done", "stale": "done", "no-table": "validate", "no-table-plan": "plan", "unicode-edges": "human",
	}
	for id, col := range want {
		if where[id] != col {
			t.Fatalf("%s in %q, want %q", id, where[id], col)
		}
	}
	if _, ok := where["linked-run"]; ok {
		t.Fatal("a linked run dir was read")
	}
	if more == 0 || tree.Problems != 0 {
		t.Fatalf("Terminé more %d, problems %d", more, tree.Problems)
	}
	if strings.Contains(out, "TOP SECRET") || !strings.Contains(out, `"name": "escape.md",`+"\n"+`     "kind": "outside"`) {
		t.Fatal("escape.md not outside")
	}

	node, err := exec.LookPath("node")
	if err != nil {
		t.Log("node not on PATH: board.js side skipped (the nix check runs it)")
		return
	}
	js, err := exec.Command(node, "../parity.js", runs, budget, strconv.Itoa(parityNow)).Output()
	mustDo(t, err)
	if string(js) != out {
		t.Fatal("parity.js (board.js) and --derive-json differ on testdata")
	}
}
