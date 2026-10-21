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
- **Background agents** (ours, only while one exists): the dispatched abduco sessions of the
  current project (its subfolders and `.claude/worktrees/` count), read from
  `~/.claude/session-state/<name>.json` (written by `hooks/session-state.js`) while the pane is
  open (the 12 newest files per 5 s poll; links, temp files and names outside claude-dispatch's
  rule skipped). Needs you first (with its notice line), then waiting, idle, working, other (an
  unknown state, by its word), done; a session silent 24 h leaves, done or not (the deck does
  not ask abduco, so a crashed session stays up to 24 h); 6 rows, then `+N more`. A pressed name
  unfolds its first prompt and last notice. Inline, one summary row (`bg: 1 needs you · 2
  working`). Each row not done carries `↗ afficher`: pressed, it runs
  `/etc/profiles/per-user/alx/bin/agent-pane pick <name>` (argument vector, no shell, 5 s at
  most, one run per name at a time), which shows that session in the agent screen's top pane;
  the outcome goes to the session log as `bg`.

`/deck close`, `/deck reset`, `/deck layout auto|compact|wide|mini`. Options (`/config`, or
`pluginConfigs.deck.options`): `architectPattern`, `architectLabel`, `panels`, `motion`,
`moments`, `matchDescriptions`, `maxCards`, `layout`, `palette`.

It observes: every hook returns the event's result unchanged, and it never writes a file. Its one
action is that button, the mod's only host command: `hooks/pick.ts` holds the single call
`checks/claude-mods.nix` (M5) allows there, character for character, and nowhere else.
It reads `<cwd>/.claude/output/apex/*/00-context.md`, the run's `external-verify.json`,
`~/.claude/apex-correction-budget/`, `.git/HEAD` and, while the pane is open,
`~/.claude/session-state/*.json`.

## Attribution

Built from [Flightdeck](https://github.com/scasella/claude-flightdeck) v0.3.2 by Stephen Casella,
MIT licensed (see `LICENSE`). The permission gate and other-loops panels were removed; the APEX
block is ours.
