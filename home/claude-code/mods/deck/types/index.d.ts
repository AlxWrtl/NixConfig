// deck state contract: Flightdeck's panels (main, architect, agents, receipt,
// log) and the APEX block (the live run, its live steps, alerts and background
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

// ---------------------------------------------------------------- APEX

export type DeckApexStepKind = 'done' | 'pending' | 'running' | 'skipped' | 'failed' | 'other'

export type DeckApexStep = { step: string; status: string; kind: DeckApexStepKind }

/** A live APEX run, read from <cwd>/.claude/output/apex/<dir>/00-context.md. */
export type DeckApexRun = {
  title: string
  /** `Tier:` of the context file (first word), else its older `Mode:`. */
  tier?: string
  branch?: string
  steps: DeckApexStep[]
  currentStep?: string
  /** The run's directory under .claude/output/apex, set by the poll. */
  dir?: string
}

/** A live step of an APEX run, read from the run's tool calls. */
export type DeckApexStepName = 'plan' | 'edit' | 'implement' | 'tests' | 'gate' | 'Codex' | 'review' | 'ship'

export type DeckApexLiveStep = {
  name: DeckApexStepName
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
}

/** The live steps of the run `runKey` (a session key, else the run dir); `current` was seen last. */
export type DeckApexSteps = { runKey: string | null; steps: DeckApexLiveStep[]; current: DeckApexStepName | null }

/** `killed` is its own word (stopped, drawn ■), not a failure. */
export type DeckApexShellStatus = 'running' | 'completed' | 'failed' | 'killed'

/** One background shell of this session (its backgroundTaskId). */
export type DeckApexShell = {
  id: string
  label: string
  startedAt: number
  endedAt?: number
  status: DeckApexShellStatus
  toolUseId?: string
  /** The subagent whose loop started it (absent on the main loop). */
  ownerAgentId?: string
}

/** The run's correction rounds used and granted (~/.claude/apex-correction-budget). */
export type DeckApexBudget = { dir: string; rounds: number; grants: number }

/** What the user must act on, most urgent kind first. */
export type DeckApexAlert =
  | { kind: 'step'; step: string }
  | { kind: 'verify'; verdict: 'FAIL' | 'BLOCKED' | 'ERROR'; findings: number }
  | { kind: 'budget'; rounds: number; cap: number }

/** The session's last main-loop Skill(apex) call: a run without a folder (yet). */
export type DeckApexSessionRun = { startedAt: number; lastAt: number; args: string }

/** The run's external verification file, as far as the block shows it. */
export type DeckApexVerdict = { dir: string; verdict: string; findings: number; mtimeMs: number }

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
      run: DeckApexRun | null
      apexSteps: DeckApexSteps
      verdict: DeckApexVerdict | null
      budget: DeckApexBudget | null
      shells: DeckApexShell[]
      sessionRun: DeckApexSessionRun | null
    }
  }
}
