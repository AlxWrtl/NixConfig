// apex-band state contract: the live APEX run the band draws, or null; the
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
}

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

// When this session first saw the run in `dir` (the run's own start is not
// readable): the band's elapsed time counts from it.
export type ApexBandSeen = { dir: string; at: number }

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
      // The spinner's frame (0-3), advanced only while something runs.
      frame: number
      seen: ApexBandSeen | null
      isOpen: boolean
      showAll: boolean
    }
  }
}
