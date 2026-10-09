# deck

A live dashboard pane for Claude Code, opened on demand only: `/deck` (aliases `/apex-pane`,
`/task-board`). It never opens by itself and draws no status line: nothing above the prompt
unless you open it.

- **APEX block** (first, full width, only while an APEX run of the session's folder is live):
  `APEX · <branch or title> · <tier>`, one dot per phase (● done, ◐ current, ○ pending, ✗ failed,
  · skipped) with its approximate tokens, what asks you to act (a failed step, a red external
  verification, a spent correction budget) and the background shells with their live duration.
  Each phase move is written to the session log as `apex`.
- **Panels** (from Flightdeck): main model vitals, the on-call architect, subagent cards and
  swimlanes (keys 1-6 expand a card), the turn receipt, the session log.

`/deck close`, `/deck reset`, `/deck layout auto|compact|wide|mini`. Options (`/config`, or
`pluginConfigs.deck.options`): `architectPattern`, `architectLabel`, `panels`, `motion`,
`moments`, `matchDescriptions`, `maxCards`, `layout`, `palette`.

It only observes: every hook returns the event's result unchanged, and it never writes a file.
It reads `<cwd>/.claude/output/apex/*/00-context.md`, the run's `external-verify.json`,
`~/.claude/apex-correction-budget/` and `.git/HEAD`.

## Attribution

Built from [Flightdeck](https://github.com/scasella/claude-flightdeck) v0.3.2 by Stephen Casella,
MIT licensed (see `LICENSE`). The permission gate and other-loops panels were removed; the APEX
block is ours.
