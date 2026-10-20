package main

// apex-board --tui: the APEX board of index.html in the terminal, read straight from disk.
//
//	apex-board-tui [--jobs DIR] <runs-dir> [budget-dir] [repo-name]
//	apex-board-tui --derive-json <runs-dir> <budget-dir> <now-ms>   (parity check, not for users)
//	apex-board-tui [--jobs DIR] --agents-snapshot <width> <height> [open]   (one Agents frame, text)
//
// The Agents tab reads $HOME/.claude/jobs unless --jobs names another dir (tests, the check).
// Read-only. Bubble Tea restores the terminal on q, Ctrl-C, SIGTERM, SIGHUP and a panic; `o` on a
// session quits, then this process execs `claude attach <id>` in the restored terminal.

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"syscall"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/term"
)

func main() { os.Exit(run(os.Args[1:])) }

// execve replaces the process (syscall.Exec); a variable so the tests never really exec.
var execve = syscall.Exec

// defaultJobsDir: $HOME/.claude/jobs, "" (no Agents tab content) without a home.
func defaultJobsDir() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	return filepath.Join(home, ".claude", "jobs")
}

func run(args []string) int {
	jobsDir := defaultJobsDir()
	if len(args) > 0 && args[0] == "--jobs" {
		if len(args) < 2 || args[1] == "" {
			fmt.Fprintln(os.Stderr, "usage: apex-board-tui --jobs <jobs-dir> ...")
			return 2
		}
		jobsDir, args = args[1], args[2:]
	}
	if len(args) > 0 && args[0] == "--agents-snapshot" {
		rc := agentsSnapshot(args[1:], jobsDir, os.Stdout)
		if rc < 0 {
			fmt.Fprintln(os.Stderr, "usage: apex-board-tui [--jobs DIR] --agents-snapshot <width> <height> [open]")
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
	m.setJobsDir(jobsDir)
	if _, err := tea.NewProgram(m).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "apex-board --tui: %v\n", err)
		return 1
	}
	if m.attach != "" {
		return execAttach(m.attach)
	}
	return 0
}

// execAttach replaces this process with `claude attach <id>` (no shell: id is one argv word). An id
// that is no job id is refused here too (defence in depth: the jobs reader already skips them),
// so nothing claude could read as a flag reaches its argv.
func execAttach(id string) int {
	if !validJobID(id) {
		fmt.Fprintf(os.Stderr, "apex-board --tui: %q n’est pas un id de session (8 caractères parmi 0123456789abcdef) : pas de claude attach\n", id)
		return 1
	}
	path, err := lookPath("claude")
	if err == nil {
		err = execve(path, []string{"claude", "attach", id}, os.Environ())
	}
	fmt.Fprintf(os.Stderr, "apex-board --tui: claude attach %s: %v\n", id, err)
	return 1
}
