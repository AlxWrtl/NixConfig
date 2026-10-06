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
}

declare module 'claude-code' {
  interface PluginState {
    'apex-band': { run: ApexBandRun | null }
  }
}
