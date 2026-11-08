// deck state contract: Flightdeck's panels (main, architect, agents, receipt,
// log), the background agents panel and the TTW block (the live run, its live steps, alerts and background
// shells). Self-contained (no import), as the plugin-authoring reference asks.

export type DeckMoment = 'before a plan' | 'error repeats' | 'before done'

export type DeckMain = { model: string; effort: string; mode: string; steps: number; isRunning: boolean }

export type DeckUsage = {
  pct: number | null
  tokens: number | null
  window: number
  costUsd: number | null
  limits: { kind: string; pct: number }[]
  compactions: number
  lastCompactAt: number | null
}

export type DeckConsult = { id: string; at: number; endAt: number | null; moment: DeckMoment; via: string }

export type DeckArchitect = { consults: DeckConsult[]; ids: string[]; seen: string[]; lastAdvice: string }

export type DeckToolNote = { tool: string; text: string; isError: boolean }

export type DeckAgentCard = {
  id: string
  type: string
  model: string
  description: string
  status: string
  spawnedAt: number
  endedAt: number | null
  /** The agent's context now: input + cache read + cache write of its latest step. */
  ctx: number
  /** Output tokens summed over its steps. */
  out: number
  steps: number
  lastStop: string | null
  tools: DeckToolNote[]
  answer: string
}

export type DeckLogLine = {
  at: number
  who: string
  text: string
  agentId: string | null
  kind: 'info' | 'error' | 'consult' | 'done'
}

export type DeckTurn = {
  edits: number
  errorStreak: number
  errors: number
  isReviewing: boolean
  startedAt: number
  costAtStart: number | null
}

export type DeckReceipt = {
  durationMs: number
  agents: number
  edits: number
  errors: number
  costDelta: number | null
  reason: string
}

export type DeckLayout = 'auto' | 'compact' | 'wide' | 'mini'

export type DeckView = { expanded: string | null; layout: DeckLayout | null }

export type DeckRoster = { architectTypes: string[] }

// ---------------------------------------------------------------- TTW

export type DeckTtwStepKind = 'done' | 'pending' | 'running' | 'skipped' | 'failed' | 'other'

export type DeckTtwStep = { step: string; status: string; kind: DeckTtwStepKind }

/** A live TTW run, read from <cwd>/.claude/output/ttw/<dir>/00-context.md. */
export type DeckTtwRun = {
  title: string
  /** `Tier:` of the context file (first word), else its older `Mode:`. */
  tier?: string
  branch?: string
  steps: DeckTtwStep[]
  currentStep?: string
  /** The run's directory under .claude/output/ttw, set by the poll. */
  dir?: string
}

/** A live step of a TTW run, read from the run's tool calls. */
export type DeckTtwStepName = 'plan' | 'edit' | 'implement' | 'tests' | 'gate' | 'Codex' | 'review' | 'ship'

export type DeckTtwLiveStep = {
  name: DeckTtwStepName
  status: 'seen'
  /** When it was last seen. */
  at: number
  /** An agent step's description and model family. */
  detail?: string
  /** Codex's PASS/FAIL/BLOCKED or a reviewer's APPROVED/NEEDS_FIXES/BLOCKED. */
  verdict?: string
  findings?: number
  /** The agent this step started, and when it ended. */
  agentId?: string
  endedAt?: number
  /** plan / edit: the distinct path tails touched (bounded). */
  files?: string[]
  /** gate / ship: the last call's command, shortened. */
  command?: string
  /** gate: the exit code its output names, its error flag, its last non-empty output line. */
  exitCode?: number
  isError?: boolean
  lastLine?: string
  /** ship: the commit subject and the PR URL, kept across its calls. */
  subject?: string
  url?: string
  /** An agent step: the first lines of its final answer (a reviewer's: those after its verdict). */
  lines?: string[]
  /** An agent step whose turn ended otherwise than with an answer. */
  isFailed?: boolean
}

/** The live steps of the run `runKey` (a session key, else the run dir); `current` was seen last. */
export type DeckTtwSteps = { runKey: string | null; steps: DeckTtwLiveStep[]; current: DeckTtwStepName | null }

/** `killed` is its own word (stopped, drawn ■), not a failure. */
export type DeckTtwShellStatus = 'running' | 'completed' | 'failed' | 'killed'

/** One background shell of this session (its backgroundTaskId). */
export type DeckTtwShell = {
  id: string
  label: string
  startedAt: number
  endedAt?: number
  status: DeckTtwShellStatus
  toolUseId?: string
  /** The subagent whose loop started it (absent on the main loop). */
  ownerAgentId?: string
}

/** The run's correction rounds used and granted (~/.claude/ttw-correction-budget). */
export type DeckTtwBudget = { dir: string; rounds: number; grants: number }

/** What the user must act on, most urgent kind first. */
export type DeckTtwAlert =
  | { kind: 'step'; step: string }
  | { kind: 'verify'; verdict: 'FAIL' | 'BLOCKED' | 'ERROR'; findings: number }
  | { kind: 'budget'; rounds: number; cap: number }

/** The session's last main-loop Skill(ttw) call: a run without a folder (yet). */
export type DeckTtwSessionRun = {
  startedAt: number
  lastAt: number
  args: string
  /** When the main turn last completed; cleared by any new activity (null: the run is busy). */
  turnEndAt?: number | null
  /** A `gh pr merge` ship call was seen: at rest once the turn completes. */
  merged?: boolean
}

/** The run's external verification file, as far as the block shows it. */
export type DeckTtwVerdict = { dir: string; verdict: string; findings: number; mtimeMs: number }

// ---------------------------------------------------------------- background agents

/**
 * A background session's state as the panel groups it: the five words session-state.js writes,
 * any other word `other`.
 */
export type DeckBgKind = 'needs-you' | 'waiting' | 'working' | 'idle' | 'other' | 'done'

/** One background session, read from ~/.claude/session-state/<name>.json. */
export type DeckBgAgent = {
  /** Its abduco session name (the file stem). */
  id: string
  name: string
  cwd: string
  /** The repo folder's name (a worktree reads as its repo). */
  project: string
  /** The raw `state` word. */
  state: string
  kind: DeckBgKind
  /** Its last notice (one line, redacted), or empty. */
  detail: string
  /** Its first prompt (one line, redacted), or empty. */
  intent: string
  /** Its last update (ms), else its file's mtime. */
  updatedAt: number
}

declare module 'claude-code' {
  interface PluginState {
    'deck': {
      main: DeckMain
      usage: DeckUsage
      architect: DeckArchitect
      agents: DeckAgentCard[]
      log: DeckLogLine[]
      turn: DeckTurn
      receipt: DeckReceipt | null
      view: DeckView
      roster: DeckRoster
      run: DeckTtwRun | null
      ttwSteps: DeckTtwSteps
      verdict: DeckTtwVerdict | null
      budget: DeckTtwBudget | null
      shells: DeckTtwShell[]
      sessionRun: DeckTtwSessionRun | null
      /** The step whose explanation box is open under the step row. */
      openStep: DeckTtwStepName | null
      /** Background sessions of the current project, polled while the pane is open. */
      background: DeckBgAgent[]
    }
  }
}
