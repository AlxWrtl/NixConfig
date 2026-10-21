package main

// The Agents tab's groups: an accordion by project once the board knows its repo (tabRepo). The
// boards are derived from sessionInputs at testNow; genericRoot points at a fixed path, never
// touched (isGenericOf only compares paths); runPick is stubbed where a key could pick.

import (
	"slices"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

const groupsTab = "/t/Tab"

// groupSessions: two repos named Preliz, a repo with an agent in its worktree and one in its root,
// a plain cwd, a generic, a dir under the generic root that is not its own, one without cwd, and
// one in a worktree of the tab's repo when withTab.
func groupSessions(withTab bool) []*sessionInput {
	s := func(name, cwd, state string, live int) *sessionInput {
		return &sessionInput{Name: name, Cwd: cwd, State: state, Live: live, UpdatedAt: testNow - 60_000}
	}
	out := []*sessionInput{
		s("p1", "/a/Preliz/.claude/worktrees/p1", "working", liveRunning),
		s("p2", "/b/Preliz/.claude/worktrees/p2", "needs-you", liveRunning),
		s("al1", "/u/Alpha/.claude/worktrees/al1", "needs-you", liveRunning),
		s("al2", "/u/Alpha", "working", liveRunning),
		s("z1", "/u/Zeta", "done", liveRunning),
		s("g1", "/g/agents/g1", "waiting", liveRunning),
		s("g2", "/g/agents/other", "working", liveRunning),
		{Name: "s1", Live: liveRunning, noState: true},
	}
	if withTab {
		out = append(out, s("t1", groupsTab+"/.claude/worktrees/t1", "working", liveRunning))
	}
	return out
}

// groupsModel: the Agents tab of a board run in groupsTab (runsDir as apex-board.sh passes it).
func groupsModel(t *testing.T, sessions []*sessionInput, w, h int) *Model {
	t.Helper()
	stubGenericRoot(t, "/g/agents")
	m := newModel(groupsTab+"/.claude/output/apex", "", "Tab", w, h)
	m.tab = tabAgents
	m.applyAgents(&agentsPoll{board: deriveAgents(sessions, testNow), now: testNow, clock: "12:00:00"})
	return m
}

func groupLabels(gs []*agentGroup) []string {
	var out []string
	for _, g := range gs {
		out = append(out, g.label+":"+strings.Join(groupIDs(g), ","))
	}
	return out
}

func groupIDs(g *agentGroup) []string {
	var ids []string
	for _, col := range g.cols {
		for _, a := range col {
			ids = append(ids, a.ID)
		}
	}
	return ids
}

func TestTabRepo(t *testing.T) {
	for runs, want := range map[string]string{
		"/u/repo/.claude/output/apex":                       "/u/repo",
		"/u/repo/.claude/worktrees/wt/.claude/output/apex":  "/u/repo",
		"/u/repo/.claude/worktrees/wt/.claude/output/apex/": "/u/repo",
		"/u/repo/.claude/worktrees/a/b/.claude/output/apex": "/u/repo/.claude/worktrees/a/b",
		"relative/.claude/worktrees/wt/.claude/output/apex": "",
		"/.claude/worktrees/wt/.claude/output/apex":         "/.claude/worktrees/wt",
		"": "",
	} {
		if got := tabRepo(runs); got != want {
			t.Errorf("tabRepo(%q) = %q, want %q", runs, got, want)
		}
	}
}

// The tab's project first even empty, the others by label (two Preliz apart, by their parent),
// a repo's worktree and root in one group, Génériques then « sans dossier » last.
func TestGroupAgents(t *testing.T) {
	stubGenericRoot(t, "/g/agents")
	b := deriveAgents(groupSessions(false), testNow)
	gs := groupAgents(&b, groupsTab)
	want := []string{"Tab:", "a/Preliz:p1", "Alpha:al1,al2", "b/Preliz:p2", "other:g2", "Zeta:z1", "Génériques:g1", "sans dossier:s1"}
	if got := groupLabels(gs); !slices.Equal(got, want) {
		t.Fatalf("groups %q, want %q", got, want)
	}
	if gs[0].key != groupsTab || gs[1].key != "/a/Preliz" || gs[3].key != "/b/Preliz" || gs[2].key != "/u/Alpha" || gs[0].n != 0 || gs[2].n != 2 {
		t.Fatalf("keys %q %q %q, n %d %d", gs[1].key, gs[2].key, gs[3].key, gs[0].n, gs[2].n)
	}
	// Two of one name and one parent: the full path.
	b = deriveAgents([]*sessionInput{
		{Name: "r1", Cwd: "/x/a/Repo", State: "working", Live: liveRunning},
		{Name: "r2", Cwd: "/y/a/Repo/.claude/worktrees/r2", State: "working", Live: liveRunning},
	}, testNow)
	if got := groupLabels(groupAgents(&b, "/t/Repo")); !slices.Equal(got, []string{"t/Repo:", "/x/a/Repo:r1", "/y/a/Repo:r2"}) {
		t.Fatalf("same parent: %q", got)
	}
	// No generic, no stateless: neither group; the tab's worktree agent in the first one; one
	// Preliz left: its bare name.
	all := groupSessions(true)
	b = deriveAgents([]*sessionInput{all[0], all[8]}, testNow)
	if got := groupLabels(groupAgents(&b, groupsTab)); !slices.Equal(got, []string{"Tab:t1", "Preliz:p1"}) {
		t.Fatalf("tab agents: %q", got)
	}
}

// At start the tab's project is expanded (`▾`), empty, the others folded with their counts; only
// the expanded group's cards are drawn; `p` / `P` step (wrapping), a header click expands its
// group, a poll keeps it, and the hidden count is the whole board's.
func TestGroupsAccordion(t *testing.T) {
	sessions := append(groupSessions(true), &sessionInput{Name: "old", Cwd: "/u/Zeta", State: "done", Live: liveAbsent, UpdatedAt: testNow - keepMs - 1})
	m := groupsModel(t, sessions, 180, 50)
	stubPick(t, nil)
	text := strings.Join(plain(m.View().Content), "\n")
	for _, want := range []string{"▾ Tab · 1   Travaille 1", "▸ Alpha · 2   Attend ta réponse 1 · Travaille 1", "▸ Génériques · 1   Attend ta réponse 1", "▸ sans dossier · 1   Figé 1", "1 terminée depuis plus de 24 h masquée", "N générique · p projet"} {
		if !strings.Contains(text, want) {
			t.Fatalf("%q not drawn:\n%s", want, text)
		}
	}
	shown := func() []string {
		m.View()
		var ids []string
		for _, h := range m.hits {
			if h.kind == hitCard {
				ids = append(ids, h.id)
			}
		}
		slices.Sort(ids)
		return ids
	}
	if got := shown(); !slices.Equal(got, []string{"t1"}) {
		t.Fatalf("tab group cards %q", got)
	}
	if s := m.agentSelection(); s.idx < 0 || (*m.shownCols())[s.col][s.idx].ID != "t1" {
		t.Fatalf("selection %+v", s)
	}
	send(m, char('p'))
	if got := shown(); m.ag.group != "/a/Preliz" || !slices.Equal(got, []string{"p1"}) {
		t.Fatalf("p: group %q cards %q", m.ag.group, got)
	}
	if !strings.Contains(strings.Join(plain(m.View().Content), "\n"), "▾ a/Preliz · 1") {
		t.Fatal("p: header not expanded")
	}
	send(m, char('P'))
	send(m, char('P'))
	if got := shown(); m.ag.group != noneKey || !slices.Equal(got, []string{"s1"}) {
		t.Fatalf("P wraps: group %q cards %q", m.ag.group, got)
	}
	// A click on a folded header expands it.
	m.View()
	var alpha *hit
	for i := range m.hits {
		if h := &m.hits[i]; h.kind == hitGroup && h.id == "/u/Alpha" {
			alpha = h
		}
	}
	if alpha == nil {
		t.Fatal("no Alpha header hit")
	}
	if row := plain(m.View().Content)[alpha.y]; !strings.Contains(row, "▸ Alpha · 2") {
		t.Fatalf("hit over %q", row)
	}
	if cmd := send(m, tea.MouseClickMsg{X: alpha.x + 3, Y: alpha.y, Button: tea.MouseLeft}); cmd != nil {
		t.Fatal("a header click ran something")
	}
	if got := shown(); m.ag.group != "/u/Alpha" || !slices.Equal(got, []string{"al1", "al2"}) {
		t.Fatalf("click: group %q cards %q", m.ag.group, got)
	}
	// Keys move in the expanded group; a poll keeps it.
	send(m, key(tea.KeyRight))
	if s := m.agentSelection(); s.idx < 0 || (*m.shownCols())[s.col][s.idx].ID != "al2" {
		t.Fatalf("right in Alpha: %+v", s)
	}
	m.applyAgents(&agentsPoll{board: deriveAgents(sessions, testNow), now: testNow, clock: "12:00:05"})
	if got := shown(); m.ag.group != "/u/Alpha" || !slices.Equal(got, []string{"al1", "al2"}) {
		t.Fatalf("after a poll: group %q cards %q", m.ag.group, got)
	}
	// Enter picks the expanded group's selected card.
	picks := stubPick(t, nil)
	send(m, send(m, key(tea.KeyEnter))())
	if len(*picks) != 1 || (*picks)[0][len((*picks)[0])-1] != "al2" {
		t.Fatalf("picks %q", *picks)
	}
	// A card selected by name (a launch) opens its group.
	m.ag.sel, m.dirty = &selState{id: "g1"}, true
	if got := shown(); m.ag.group != genericKey || !slices.Equal(got, []string{"g1"}) {
		t.Fatalf("selected g1: group %q cards %q", m.ag.group, got)
	}
}

// The × of the expanded group's card arms it; the hits never reach a folded group's card.
func TestGroupsStop(t *testing.T) {
	m := groupsModel(t, groupSessions(true), 180, 50)
	stubPick(t, nil)
	for range 3 { // Tab → a/Preliz → Alpha → b/Preliz
		send(m, char('p'))
	}
	m.View()
	x := findHit(m, hitStop, "p2")
	if x == nil || findHit(m, hitStop, "t1") != nil {
		t.Fatalf("× hits: p2 %v t1 %v", x != nil, findHit(m, hitStop, "t1") != nil)
	}
	send(m, tea.MouseClickMsg{X: x.x + 1, Y: x.y, Button: tea.MouseLeft})
	if m.ag.armed != "p2" {
		t.Fatalf("armed %q", m.ag.armed)
	}
}

// Without a tab repo (the snapshot, no runs dir): no header, every card in the kanban.
func TestGroupsFlatWithoutRepo(t *testing.T) {
	stubGenericRoot(t, "/g/agents")
	m := newModel("", "", "x", 180, 50)
	m.tab = tabAgents
	m.applyAgents(&agentsPoll{board: deriveAgents(groupSessions(false), testNow), now: testNow, clock: "12:00:00"})
	text := strings.Join(plain(m.View().Content), "\n")
	if strings.Contains(text, "▾") || strings.Contains(text, "▸") || findHit(m, hitGroup, "") != nil {
		t.Fatal("headers drawn without a repo")
	}
	for _, id := range []string{"p1", "p2", "al1", "al2", "z1", "g1", "g2", "s1"} {
		if findHit(m, hitCard, id) == nil {
			t.Fatalf("%s not drawn", id)
		}
	}
	send(m, char('p'))
	if m.ag.group != "" {
		t.Fatalf("p without groups: %q", m.ag.group)
	}
}

// Short screens: every size draws exactly its lines, the expanded header first kept.
func TestGroupsSmall(t *testing.T) {
	m := groupsModel(t, groupSessions(true), 180, 50)
	for _, wh := range [][2]int{{180, 16}, {180, 12}, {60, 8}, {30, 6}, {10, 4}, {1, 1}} {
		m.width, m.height, m.dirty = wh[0], wh[1], true
		for _, k := range []rune{0, 'p', 'P', 'P'} {
			if k != 0 {
				send(m, char(k))
			}
			lines := strings.Split(m.View().Content, "\n")
			if len(lines) != wh[1] {
				t.Fatalf("%v: %d lines", wh, len(lines))
			}
			for y, l := range lines {
				if visibleWidth(l) != wh[0] {
					t.Fatalf("%v line %d width %d", wh, y, visibleWidth(l))
				}
			}
			if m.ag.view.areaH < 0 {
				t.Fatalf("%v: areaH %d", wh, m.ag.view.areaH)
			}
		}
	}
	m.width, m.height, m.dirty = 180, 12, true
	if text := strings.Join(plain(m.View().Content), "\n"); !strings.Contains(text, "▾ ") {
		t.Fatalf("12 rows: no expanded header:\n%s", text)
	}
}

// N and P with their text, or reported without it (kitty keyboard), name the same key.
func TestKeyNamesShift(t *testing.T) {
	for _, c := range []struct {
		k    tea.KeyPressMsg
		want string
	}{
		{tea.KeyPressMsg{Code: 'n', Mod: tea.ModShift}, "N"}, {tea.KeyPressMsg{Code: 'n', Text: "N", Mod: tea.ModShift}, "N"},
		{tea.KeyPressMsg{Code: 'p', Mod: tea.ModShift}, "P"}, {char('n'), "n"}, {char('p'), "p"},
	} {
		if got := keyName(c.k); got != c.want {
			t.Fatalf("%v → %q, want %q", c.k, got, c.want)
		}
	}
}
