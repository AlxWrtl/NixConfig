// task-board state contract: what the hooks module keeps in $.state.
// Self-contained (no import), as the plugin-authoring reference asks.

export type TaskBoardKind = 'shell' | 'agent'

// `killed` is kept as its own word in state and drawn as "arrêtée" (■), not as a failure.
export type TaskBoardStatus = 'running' | 'completed' | 'failed' | 'killed'

export type TaskBoardTask = {
  // backgroundTaskId for a shell, agentId for a subagent.
  id: string
  kind: TaskBoardKind
  label: string
  startedAt: number
  endedAt?: number
  status: TaskBoardStatus
  toolUseId?: string
  agentType?: string
  // Shell only: the subagent whose loop started it (absent on the main loop).
  ownerAgentId?: string
  // Agent only: the tool its loop is running now, cleared when its turn ends.
  tool?: string
  // Agent only: input + output + cache-write tokens of its steps (cache reads excluded).
  tokens?: number
}

declare module 'claude-code' {
  interface PluginState {
    'task-board': { tasks: TaskBoardTask[]; now: number; isOpen: boolean; showAll: boolean }
  }
}
