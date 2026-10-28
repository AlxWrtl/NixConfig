package main

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

// cellIndex: the grid x of s's first char in row (wide halves skipped), -1 when absent.
func cellIndex(row []cell, s string) int {
	var text []rune
	var at []int
	for x, c := range row {
		for _, r := range c.ch {
			text, at = append(text, r), append(at, x)
		}
	}
	if i := strings.Index(string(text), s); i >= 0 {
		return at[len([]rune(string(text)[:i]))]
	}
	return -1
}

// AC1: short and too narrow for every column, the Agents footer keeps the note; its colour says
// a failure (P.err) from a neutral line (P.muted).
func TestAgentsNoteWinsOverColumns(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 60, 12)
	m.View()
	if m.ag.view.nVis >= len(AgentColumns) {
		t.Fatalf("precondition: %d of %d columns shown", m.ag.view.nVis, len(AgentColumns))
	}
	H := 12
	if foot := plain(m.View().Content)[H-1]; !strings.Contains(foot, "colonnes") {
		t.Fatalf("no note: footer %q lacks the columns indicator", foot)
	}
	for _, c := range []struct {
		failed bool
		want   rgb
	}{{false, P.muted}, {true, P.err}} {
		m.ag.say("éteinte : x", c.failed)
		m.dirty = true
		foot := plain(m.View().Content)[H-1]
		if !strings.Contains(foot, "éteinte : x") || strings.Contains(foot, "colonnes") {
			t.Fatalf("failed=%v: footer %q", c.failed, foot)
		}
		if x := cellIndex(m.g[H-1], "éteinte"); x < 0 || m.g[H-1][x].st.fg != c.want {
			t.Fatalf("failed=%v: note colour at %d", c.failed, x)
		}
	}
}

// AC2: the key hints of the board, drawer and Agents footers are muted, not faint.
func TestKeysRowsMuted(t *testing.T) {
	check := func(name string, m *Model, y int, word string) {
		t.Helper()
		m.View()
		x := cellIndex(m.g[y], word)
		if x < 0 {
			t.Fatalf("%s: %q not on row %d", name, word, y)
		}
		if got := m.g[y][x].st.fg; got != P.muted || got == P.faint {
			t.Fatalf("%s: %q drawn in %v", name, word, got)
		}
	}
	fx := newFixture(t)
	m := fx.model(t, 180, 50)
	check("board", m, 49, "naviguer")
	m.View()
	h := findHit(m, hitCard, "live-failed")
	runCmd(t, m, send(m, tea.MouseClickMsg{X: h.x + 2, Y: h.y + 1, Button: tea.MouseLeft}))
	if m.drawer == nil {
		t.Fatal("drawer not open")
	}
	m.View()
	y := -1
	for i, l := range plain(m.View().Content) {
		if strings.Contains(l, "pgup/pgdn page") {
			y = i
		}
	}
	if y < 0 {
		t.Fatal("drawer keys row not drawn")
	}
	check("drawer", m, y, "pgup/pgdn")
	check("agents", agentsModel(t, newSessionsFixture(t), 180, 50), 49, "naviguer")
}

// AC3: chips and file verdicts read without colour: ✓ / ✗ before a pass / fail label, and
// ✓ ~ ✗ · beside a file; the derived Label itself is untouched.
func TestStateGlyphs(t *testing.T) {
	chips := []Chip{{Key: "v", Label: "validate", State: "fail"}, {Key: "e", Label: "verify", State: "pass"}}
	line := chipLines(chips, 60, P.card)[0]
	var text strings.Builder
	for _, c := range line {
		text.WriteString(c.ch)
	}
	if got := text.String(); !strings.Contains(got, "[✗ validate]") || !strings.Contains(got, " ✓ verify ") {
		t.Fatalf("chips %q", got)
	}
	if x := cellIndex(line, "✗"); x < 0 || line[x].st.fg != P.err {
		t.Fatal("fail chip not in P.err")
	}
	if chips[0].Label != "validate" {
		t.Fatalf("Label changed: %q", chips[0].Label)
	}

	f := newFixture(t)
	m := f.model(t, 180, 50)
	m.View()
	h := findHit(m, hitCard, "live-failed")
	runCmd(t, m, send(m, tea.MouseClickMsg{X: h.x + 2, Y: h.y + 1, Button: tea.MouseLeft}))
	d := m.drawer
	if d == nil {
		t.Fatal("drawer not open")
	}
	d.tones["00-context.md"], d.tones["sub/notes.md"] = "warn", "stop"
	want := map[string]struct {
		glyph string
		c     rgb
	}{
		"04-validate.md": {"✓", P.pass},
		"00-context.md":  {"~", P.changes},
		"sub/notes.md":   {"✗", P.err},
		"escape.md":      {"·", P.faint},
	}
	m.dirty = true
	m.View()
	seen := 0
	for _, hf := range m.hits {
		w, ok := want[hf.path]
		if hf.kind != hitFile || !ok {
			continue
		}
		seen++
		if c := m.g[hf.y][hf.x+1]; c.ch != w.glyph || c.st.fg != w.c {
			t.Fatalf("%s: %q in %v, want %q in %v", hf.path, c.ch, c.st.fg, w.glyph, w.c)
		}
	}
	if seen != len(want) {
		t.Fatalf("%d of %d files drawn", seen, len(want))
	}
}

// AC4: an armed card's × and border are P.err, a red apart from the decision pink.
func TestArmedCardRed(t *testing.T) {
	if P.err == P.human {
		t.Fatal("P.err is P.human")
	}
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	stubPick(t, nil)
	m.View()
	x := findHit(m, hitStop, "work-live")
	card := findHit(m, hitCard, "work-live")
	if x == nil || card == nil {
		t.Fatal("work-live not drawn with its ×")
	}
	if c := m.g[x.y][x.x+1]; c.ch != "×" || c.st.fg == P.err {
		t.Fatalf("unarmed ×: %q in %v", c.ch, c.st.fg)
	}
	send(m, tea.MouseClickMsg{X: x.x + 1, Y: x.y, Button: tea.MouseLeft})
	if m.ag.armed != "work-live" {
		t.Fatalf("not armed: %q", m.ag.armed)
	}
	m.View()
	if c := m.g[x.y][x.x+1]; c.ch != "×" || c.st.fg != P.err {
		t.Fatalf("armed ×: %q in %v", c.ch, c.st.fg)
	}
	for _, at := range [][2]int{{card.x, card.y}, {card.x + card.w - 1, card.y + 1}} {
		if c := m.g[at[1]][at[0]]; c.st.fg != P.err {
			t.Fatalf("armed border at %v: %q in %v", at, c.ch, c.st.fg)
		}
	}
	if !m.ag.noteErr {
		t.Fatal("the confirm question is not drawn as a warning")
	}
}
