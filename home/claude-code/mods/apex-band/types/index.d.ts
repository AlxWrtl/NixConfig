// apex-band state contract: the live APEX run the pane shows, or null; the
// session's model loops and background shells; the signals asking the user
// to act. Self-contained (no import), as the plugin-authoring reference asks.

export type ApexBandStepKind = 'done' | 'pending' | 'running' | 'skipped' | 'failed' | 'other'

export type ApexBandStep = { step: string; status: string; kind: ApexBandStepKind }

export type ApexBandRun = {
  title: string
  mode?: string
  branch?: string
  baseline?: string
  steps: ApexBandStep[]
  currentStep?: string
  // The run's directory under .claude/output/apex, set by the poll.
  dir?: string
}

// Token counts of one or more model responses, as the API reports them.
export type ApexBandTally = { input: number; output: number; cacheRead: number; cacheWrite: number }

export type ApexBandLoopStatus = 'running' | 'done' | 'failed' | 'stopped'

// One model loop seen this session: a subagent (its agentId) or `main`.
export type ApexBandLoop = {
  id: string
  label?: string
  type?: string
  model?: string
  status: ApexBandLoopStatus
  steps: number
  calls: number
  tool?: string
  toolUseId?: string
  tally: ApexBandTally
  startedAt: number
  // Running time of the finished turns; the live one counts from `since`.
  durationMs: number
  since?: number
  endedAt?: number
  // What ended it: the agent snapshot (an estimate, until its turn.complete
  // reconciles it once) or its own turn.complete.
  endedBy?: 'snapshot' | 'turn'
  // Named by the agent list or launched by an Agent call: a subagent proper.
  // A loop seen by its steps alone (a workflow agent, an engine fork, a
  // teammate before its first snapshot) never counts as at work, never
  // orphans shells.
  listed?: boolean
  // The agent list reads this listed subagent idle: kept, not at work.
  idle?: boolean
  // The context its last step sent: input plus cache reads and writes.
  context?: number
  // Its last tool calls (at most 3), oldest first.
  recent?: ApexBandToolUse[]
  // The prompt it was launched with (cut at 2000 characters).
  task?: string
  // The head of its final answer, on one line (cut at 400 characters).
  answer?: string
  // The thinking effort its last step asked for (a level, or a budget).
  effort?: string
}

// One tool call of a loop and what it aimed at (a path, a command, a URL).
export type ApexBandToolUse = { tool: string; target?: string }

export type ApexBandLogKind = 'prompt' | 'spawn' | 'done' | 'edit' | 'error' | 'compact'

// One journal line: when, what kind, its text on one line.
export type ApexBandLogEntry = { at: number; kind: ApexBandLogKind; text: string }

// One main-loop turn's receipt: its subagents, the files it edited, the tool
// errors, its cost (the session's cost when it began, and what it added).
export type ApexBandReceipt = {
  turnId: string
  startedAt: number
  endedAt?: number
  durationMs?: number
  reason?: string
  // The subagents it launched, each id once.
  agents: string[]
  // The files it edited, each path once.
  edits: string[]
  errors: number
  costAtStart: number | null
  costDelta?: number
}

// The turn under way (null between turns) and the last one ended.
export type ApexBandReceipts = { current: ApexBandReceipt | null; last: ApexBandReceipt | null }

// One rate-limit window: percent used, when it resets (ms; absent unknown).
export type ApexBandLimit = { kind: string; percent: number; resetsAt?: number }

// The main context window and the rate-limit windows, as session.usage reads them.
export type ApexBandGauge = { percent: number | null; tokens: number | null; window: number; limits: ApexBandLimit[] }

// `killed` is its own word (stopped, drawn ■), not a failure.
export type ApexBandShellStatus = 'running' | 'completed' | 'failed' | 'killed'

// One background shell of this session (its backgroundTaskId).
export type ApexBandShell = {
  id: string
  label: string
  startedAt: number
  endedAt?: number
  status: ApexBandShellStatus
  toolUseId?: string
  // The subagent whose loop started it (absent on the main loop).
  ownerAgentId?: string
}

// The run's correction rounds used and granted
// (~/.claude/apex-correction-budget/<dir>.round<n> / .grant<n>).
export type ApexBandBudget = { dir: string; rounds: number; grants: number }

// What the user must act on, most urgent kind first.
export type ApexBandAlert =
  | { kind: 'step'; step: string }
  | { kind: 'verify'; verdict: 'FAIL' | 'BLOCKED' | 'ERROR'; findings: number }
  | { kind: 'budget'; rounds: number; cap: number }

// The run's external verification file, as far as the pane shows it.
export type ApexBandVerdict = { dir: string; verdict: string; findings: number; mtimeMs: number }

// Tokens per APEX step of the run in `dir` (approximate: polled step).
export type ApexBandPhases = { dir: string | null; byStep: Record<string, ApexBandTally> }

declare module 'claude-code' {
  interface PluginState {
    'apex-band': {
      run: ApexBandRun | null
      loops: ApexBandLoop[]
      phases: ApexBandPhases
      now: number
      cost: number | null
      verdict: ApexBandVerdict | null
      shells: ApexBandShell[]
      budget: ApexBandBudget | null
      // The journal, newest last (at most LOG_CAP entries).
      log: ApexBandLogEntry[]
      receipts: ApexBandReceipts
      gauge: ApexBandGauge | null
      // Compactions this session, per trigger (manual, auto, plugin).
      compactions: Record<string, number>
      // The loop id whose block the pane shows expanded, or null.
      expanded: string | null
      isOpen: boolean
      showAll: boolean
    }
  }
}
