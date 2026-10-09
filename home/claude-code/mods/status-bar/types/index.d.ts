// status-bar state contract: what the hooks module keeps in $.state.
// Self-contained (no import), as the plugin-authoring reference asks.

// One rate-limit window as $.session.usage() reports it (`five_hour`,
// `seven_day`); `resetsAt` is an ISO 8601 timestamp, null when unknown.
export type StatusBarLimit = { kind: string; percentUsed: number; resetsAt: string | null }

// The figures of $.session.usage(); null where the engine has none yet.
export type StatusBarUsage = {
  contextPercent: number | null
  contextTokens: number | null
  limits: StatusBarLimit[]
}

// The main loop's last model response: input (uncached + cache write + cache
// read) and output tokens, and the model id the API reported.
export type StatusBarStep = { tokensIn: number; tokensOut: number; model: string }

declare module 'claude-code' {
  interface PluginState {
    'status-bar': {
      usage: StatusBarUsage
      step: StatusBarStep | null
      model: string
      cwd: string
      branch: string | null
      now: number
    }
  }
}
