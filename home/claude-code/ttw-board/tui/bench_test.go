package main

// The two costs tui.js had on 160 real runs: a frame (renderBoard 10.7 ms) and a wheel notch
// (15.6 ms, a full render to hit-test).

import (
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
)

// benchModel: 160 runs spread over every column, as the real runs dir has.
func benchModel(b *testing.B) *Model {
	now := float64(time.Now().UnixMilli())
	steps := []string{"00-init", "02-plan", "03-execute", "04-validate"}
	runs := make([]*RunInput, 160)
	for i := range runs {
		id := "run-" + itoaT(1000+i)
		ms := now - float64(i)*60_000
		rows := [][2]string{{steps[i%4], "in progress"}}
		if i%10 == 9 {
			rows = [][2]string{{"04-validate", "failed"}}
		}
		if i >= 120 {
			ms = now - float64(7+i)*hourMs
		}
		runs[i] = &RunInput{ID: id, Context: strp(ctxText(id, rows)), MtimeMs: &ms, Files: []string{"00-context.md"}, Budget: &Budget{Rounds: i % 3}}
	}
	m := newModel("", "", "bench", 200, 60)
	m.setRuns(runs, now)
	m.View()
	return m
}

func BenchmarkView(b *testing.B) {
	m := benchModel(b)
	b.ReportAllocs()
	for i := 0; b.Loop(); i++ {
		m.tick = i%2 == 0 // a new frame each time: the live dots pulse
		m.dirty = true
		m.View()
	}
}

func BenchmarkWheel(b *testing.B) {
	m := benchModel(b)
	h := findHit(m, hitCol, "")
	b.ReportAllocs()
	for i := 0; b.Loop(); i++ {
		btn := tea.MouseWheelDown
		if i%8 >= 4 {
			btn = tea.MouseWheelUp
		}
		m.Update(tea.MouseWheelMsg{X: h.x + 1, Y: h.y + 4, Button: btn})
	}
}
