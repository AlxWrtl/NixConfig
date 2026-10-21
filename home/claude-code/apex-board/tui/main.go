package main

// apex-board --tui: the APEX board of index.html in the terminal, read straight from disk.
//
//	apex-board-tui [--sessions DIR] <runs-dir> [budget-dir] [repo-name]
//	apex-board-tui --derive-json <runs-dir> <budget-dir> <now-ms>   (parity check, not for users)
//	apex-board-tui [--sessions DIR] --agents-snapshot <width> <height>   (one Agents frame, text)
//
// The Agents tab reads $HOME/.claude/session-state unless --sessions names another dir (tests, the
// check), and asks abduco which sessions run. Read-only but for one action: Enter on a session
// runs `agent-pane pick <name>`, the board stays open. Bubble Tea restores the terminal on q,
// Ctrl-C, SIGTERM, SIGHUP and a panic.

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/term"
)

// abducoBin, agentPaneBin and dispatchBin (claude-dispatch): store paths, set by -X ldflags in
// apex-board.nix (no PATH lookup). Empty (a bare `go build`): abduco is not asked (liveness
// unknown, said in the tab), and a pick, a stop or a new agent says the binary is missing,
// nothing run.
var abducoBin, agentPaneBin, dispatchBin string

func main() { os.Exit(run(os.Args[1:])) }

// defaultSessionsDir: $HOME/.claude/session-state, "" (no Agents tab content) without a home.
func defaultSessionsDir() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	return filepath.Join(home, ".claude", "session-state")
}

func run(args []string) int {
	sessionsDir := defaultSessionsDir()
	if len(args) > 0 && args[0] == "--sessions" {
		if len(args) < 2 || args[1] == "" {
			fmt.Fprintln(os.Stderr, "usage: apex-board-tui --sessions <session-state-dir> ...")
			return 2
		}
		sessionsDir, args = args[1], args[2:]
	}
	if len(args) > 0 && args[0] == "--agents-snapshot" {
		rc := agentsSnapshot(args[1:], sessionsDir, os.Stdout)
		if rc < 0 {
			fmt.Fprintln(os.Stderr, "usage: apex-board-tui [--sessions DIR] --agents-snapshot <width> <height>")
			return 2
		}
		return rc
	}
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
	m := newModel(runsDir, budgetDir, repo, w, h)
	m.setSessionsDir(sessionsDir)
	if _, err := tea.NewProgram(m).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "apex-board --tui: %v\n", err)
		return 1
	}
	return 0
}
