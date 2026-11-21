import {
  REASONS,
  RELOADED_LINE,
  getFailedLine,
  getWarningText,
} from './thresholds.js'
import {
  findStageFile,
  queueStage,
  setStage,
  tellUser,
} from './files.js'
import {
  RELOADED_WAIT_LINE,
  isWaiting,
  setReading,
  setRoundStarted,
} from './drain.js'
import { setAskFailed } from './limits.js'

export async function endChain($, job) {
  const { state, reason } = job
  if (state.request === null && !isWaiting(state)) return
  const isLimitOnly = state.request !== null && !state.request.isWindow && !isWaiting(state)
  state.request = null
  if (isLimitOnly) return
  state.drain = null
  setStage(state, { stage: 'interrupted', reason })
  await queueStage($, state)
}

export const SAVE_RETRIES = 2

export const getRetryLine = reason =>
  `the session was not anchored: ${reason}. It tries again at the end of the next turn; say "anchor" to save now.`

export const setWindowFailed = (state, reason) => {
  state.arm.save = state.arm.failures < SAVE_RETRIES
  state.arm.failures += 1
  setStage(state, { stage: 'failed', reason })
}

export const getWindowFailedLine = (arm, reason) => (arm.save ? getRetryLine(reason) : getFailedLine(reason))

export async function failRequest($, job) {
  const { state, reason } = job
  const isWindow = state.request === null || state.request.isWindow
  setAskFailed(state.request?.limits ?? [])
  state.request = null
  if (isWindow) setWindowFailed(state, reason)
  await queueStage($, state)
  tellUser($, isWindow ? getWindowFailedLine(state.arm, reason) : getFailedLine(reason))
}

export async function fireWarning($, job) {
  const { state, reading } = job
  if (state.request !== null) return
  state.arm.warn = false
  state.warnRound += 1
  setRoundStarted(state)
  setReading(state, reading)
  state.pending = getWarningText(reading)
  setStage(state, { stage: 'warned' })
  await queueStage($, state)
}

export async function restoreStage($, state) {
  const saved = await findStageFile($, state.id)
  if (saved === null) return
  state.warnRound = saved.warnRound
  state.saveRound = saved.saveRound
  state.limits = saved.limits
  if (saved.stage !== 'requested' && saved.stage !== 'waiting') return
  setStage(state, { stage: 'interrupted', reason: REASONS.reloaded })
  await queueStage($, state)
  tellUser($, saved.stage === 'waiting' ? RELOADED_WAIT_LINE : RELOADED_LINE)
}
