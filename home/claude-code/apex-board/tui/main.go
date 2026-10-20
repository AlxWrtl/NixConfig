package main

// apex-board --tui: the APEX board of index.html in the terminal, read straight from disk.
//
//	apex-board-tui <runs-dir> [budget-dir] [repo-name]
//	apex-board-tui --derive-json <runs-dir> <budget-dir> <now-ms>   (parity check, not for users)
//
// Read-only. Bubble Tea restores the terminal on q, Ctrl-C, SIGTERM, SIGHUP and a panic.

import (
	"fmt"
	"os"
	"strconv"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/term"
)

func main() { os.Exit(run(os.Args[1:])) }

func run(args []string) int {
	if len(args) > 0 && args[0] == "--derive-json" {
		if len(args) != 4 {
			fmt.Fprintln(os.Stderr, "usage: apex-board-tui --derive-json <runs-dir> <budget-dir> <now-ms>")
			return 2
		}
		now, err := strconv.ParseFloat(args[3], 64)
		if err != nil {
			fmt.Fprintf(os.Stderr, "apex-board --derive-json: bad now-ms %q\n", args[3])
			return 2
		}
		out, err := deriveJSON(args[1], args[2], now)
		if err != nil {
			fmt.Fprintf(os.Stderr, "apex-board --derive-json: %v\n", err)
			return 1
		}
		if _, err := os.Stdout.WriteString(out); err != nil {
			fmt.Fprintf(os.Stderr, "apex-board --derive-json: %v\n", err)
			return 1
		}
		return 0
	}
	if len(args) == 0 || args[0] == "" {
		fmt.Fprintln(os.Stderr, "usage: apex-board-tui <runs-dir> [budget-dir] [repo-name]")
		return 2
	}
	runsDir, budgetDir, repo := args[0], "", ""
	if len(args) > 1 {
		budgetDir = args[1]
	}
	if len(args) > 2 {
		repo = args[2]
	}
	if !term.IsTerminal(os.Stdin.Fd()) || !term.IsTerminal(os.Stdout.Fd()) {
		fmt.Fprintln(os.Stderr, "apex-board --tui: needs a terminal on stdin and stdout")
		return 1
	}
	w, h, err := term.GetSize(os.Stdout.Fd())
	if err != nil {
		w, h = 80, 24
	}
	if _, err := tea.NewProgram(newModel(runsDir, budgetDir, repo, w, h)).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "apex-board --tui: %v\n", err)
		return 1
	}
	return 0
}
