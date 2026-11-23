import {
  FAILED_TURN,
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
import { setLoaded } from './restart.js'

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

export const RETRY_REASONS = [
  REASONS.noMarker,
  REASONS.stale,
  REASONS.notRewritten,
  REASONS.changed,
  REASONS.hookFailed,
  REASONS.notStarted,
  FAILED_TURN.error,
]

const isWindowRequest = state => state.request === null || state.request.isWindow

const isRetryDue = (state, reason) =>
  isWindowRequest(state) &&
  RETRY_REASONS.includes(reason) &&
  state.arm.failures < SAVE_RETRIES

export const getRequestFailedLine = (state, reason) => (isRetryDue(state, reason) ? getRetryLine(reason) : getFailedLine(reason))

export const setRequestFailed = (state, reason) => {
  const isWindow = isWindowRequest(state)
  const isRetry = isRetryDue(state, reason)
  const round = state.request?.round ?? null
  setAskFailed(state.request?.limits ?? [])
  state.request = null
  if (!isWindow) return
  setStage(state, { stage: 'failed', reason })
  if (!isRetry) return
  state.arm.save = true
  state.arm.failures += 1
  if (round !== null) round.isWaiting = false
  state.drain = round
}

export async function failRequest($, job) {
  const { state, reason } = job
  const line = getRequestFailedLine(state, reason)
  setRequestFailed(state, reason)
  await queueStage($, state)
  tellUser($, line)
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
  setLoaded(state, saved)
  if (saved.stage !== 'requested' && saved.stage !== 'waiting') return
  setStage(state, { stage: 'interrupted', reason: REASONS.reloaded })
  await queueStage($, state)
  tellUser($, saved.stage === 'waiting' ? RELOADED_WAIT_LINE : RELOADED_LINE)
}
