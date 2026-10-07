// apex-band state contract: the live APEX run the band draws, or null.
// Self-contained (no import), as the plugin-authoring reference asks.

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
}

// The run's external-verify.json, as far as the pane shows it.
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
    }
  }
}
