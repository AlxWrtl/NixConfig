package main

// --derive-json: every derived value the board shows, for the parity check against board.js
// (parity.js writes the same tree with JSON.stringify(v, null, 1)). Arrays and fixed keys only:
// a JS object would move integer-like keys first.

import (
	"path/filepath"
	"strconv"
	"strings"
)

func cardJSON(c *Card) jobj {
	chips := make([]any, len(c.Chips))
	for i, ch := range c.Chips {
		chips[i] = jobj{{"key", ch.Key}, {"label", ch.Label}, {"state", ch.State}, {"title", ch.Title}}
	}
	return jobj{
		{"id", c.ID}, {"title", c.Title}, {"tier", c.Tier}, {"branch", c.Branch}, {"mtimeMs", c.MtimeMs},
		{"live", c.Live}, {"column", c.Column}, {"current", c.Current}, {"finished", c.Finished}, {"flag", c.Flag},
		{"reasons", c.Reasons}, {"hints", c.Hints}, {"chips", chips},
	}
}

func toneJSON(t string) any {
	if t == "" {
		return nil
	}
	return t
}

// lineTones: "i:tone" for every line of text that has one, `;`-joined.
func lineTones(text string) string {
	var sb strings.Builder
	for i, line := range strings.Split(text, "\n") {
		if t := lineTone(line); t != "" {
			if sb.Len() > 0 {
				sb.WriteByte(';')
			}
			sb.WriteString(strconv.Itoa(i) + ":" + t)
		}
	}
	return sb.String()
}

func runFilesJSON(runsDir, id string) jobj {
	files, err := listRunFiles(filepath.Join(runsDir, id))
	if err != nil {
		return jobj{{"id", id}, {"listed", false}, {"files", []any{}}}
	}
	out := []any{}
	for _, f := range sortFiles(files) {
		kind, tone, lines := "error", any(nil), ""
		if r, err := readRunFile(runsDir, id, f); err == nil {
			kind = r.Kind
			if r.Kind == "text" {
				if strings.HasSuffix(f, ".md") || strings.HasSuffix(f, ".json") {
					tone = toneJSON(fileTone(f, r.Text))
				}
				lines = lineTones(r.Text)
			}
		}
		out = append(out, jobj{{"name", f}, {"kind", kind}, {"tone", tone}, {"lines", lines}})
	}
	return jobj{{"id", id}, {"listed", true}, {"files", out}}
}

// deriveJSON reads runsDir as the board does and writes the derived tree.
func deriveJSON(runsDir, budgetDir string, now float64) (string, error) {
	runs, problems, err := readRuns(runsDir, budgetDir)
	if err != nil {
		return "", err
	}
	cards := make([]*Card, len(runs))
	for i, r := range runs {
		cards[i] = deriveRun(r, now)
	}
	groups := groupRuns(cards)
	cols := make([]any, len(Columns))
	for i, c := range Columns {
		g := groups[c.Key]
		cs := make([]any, len(g.Cards))
		for k, card := range g.Cards {
			cs[k] = cardJSON(card)
		}
		cols[i] = jobj{{"key", c.Key}, {"label", c.Label}, {"more", g.More}, {"cards", cs}}
	}
	files := make([]any, len(runs))
	for i, r := range runs {
		files[i] = runFilesJSON(runsDir, r.ID)
	}
	root := jobj{{"now", now}, {"problems", len(problems)}, {"columns", cols}, {"runs", files}}
	var sb strings.Builder
	writeJSON(&sb, root, 0)
	sb.WriteByte('\n')
	return sb.String(), nil
}
