import {
  DEFAULTS,
  HOOK_FAILED_DROP,
  KEPT,
  REASONS,
  createArm,
  getFailedLine,
  isWarnDue,
  setArm,
} from './thresholds.js'
import {
  findReading,
  findStageFile,
  queueStage,
  setStage,
  tellUser,
} from './files.js'
import {
  createTurn,
  recordHandoffOutput,
  recordOwnWrite,
  recordSnapshot,
  recordStepsOutput,
} from './anchor-check.js'
import {
  findDenial,
  getDrainList,
  isDrainCall,
  settleRound,
} from './drain.js'
import {
  endChain,
  failRequest,
  fireWarning,
  restoreStage,
} from './stages.js'
import {
  finishRequest,
  isCurrent,
  judgeTurnEnd,
  setCurrentGetter,
} from './requests.js'
import {
  findLimitDenial,
  findLimitWarning,
  forgetCell,
  markWarned,
  notePace,
  setAskFailed,
  setPacePoints,
} from './limits.js'
import { createLimits } from './limit-rules.js'
import { createPace } from './pace.js'
import {
  endClearBeforeRun,
  endClearOnSessionEnd,
  failOwnRun,
  forgetClear,
  isClearOpen,
  isOwnClear,
  isOwnContinuation,
  markChainFailed,
  noteInput,
  noteMainToolEnd,
  noteToolEnd,
  passAgentCall,
  passContinuation,
  refuseLostClear,
  runOwnClear,
} from './clear-chain.js'

const WRITE_TOOLS = [
  'Write',
  'Edit',
  'MultiEdit',
]

let isActive = false
let cwd = ''
let session = null

setCurrentGetter(() => session)

const createSession = id => ({
  id,
  cwd,
  arm: createArm(),
  warnRound: 0,
  saveRound: 0,
  stage: null,
  reason: null,
  marker: null,
  percent: null,
  thresholds: { ...DEFAULTS },
  pending: null,
  request: null,
  turn: null,
  drain: null,
  drainMinutes: null,
  nearestWait: null,
  limits: createLimits(),
  pace: createPace(),
})

const findState = async $ => {
  const id = await $.session.id()
  if (session !== null && session.id === id) return session
  const old = session
  const fresh = createSession(id)
  const saved = await findStageFile($, id)
  if (session !== old) return session
  session = fresh
  if (saved !== null) {
    fresh.warnRound = saved.warnRound
    fresh.saveRound = saved.saveRound
    fresh.limits = saved.limits
  }
  if (old !== null) await endChain($, { state: old, reason: REASONS.sessionChanged })
  if (old !== null) await endClearBeforeRun($, KEPT.sessionChanged)

  return fresh
}

const markHookFailed = () => {
  if (session?.request?.isSubmitted) session.request.hasHookFailed = true
  markChainFailed()
}

const isOwnAnchor = e => e.origin?.kind === 'plugin' && e.origin?.name === 'hats' && e.command?.name === 'hats:anchor'

const isDone = out => out.deny === undefined && out.isError !== true

const updateArm = async ($, state) => {
  const reading = await findReading($)
  if (reading !== null) setArm(state.arm, reading)
  if (reading !== null) await settleRound($, { state, reading })

  return reading
}

const findDelivered = async ($, job) => {
  const { state, out } = job
  const reading = await updateArm($, state)
  if (reading !== null && isCurrent(state) && isWarnDue(state.arm, reading)) await fireWarning($, { state, reading })
  if (out.deny !== undefined) await notePace($, state)
  const warning = out.deny === undefined ? await findLimitWarning($, state) : null
  const list = getDrainList(state)
  const texts = [
    warning?.text ?? null,
    state.pending,
    list,
  ].filter(text => text !== null)
  if (out.deny !== undefined || texts.length === 0) return out
  state.pending = null
  if (list !== null) state.request.list = null
  if (warning !== null) await markWarned($, { state, warning })

  return {
    ...out,
    context: [
      ...(out.context ?? []),
      ...texts,
    ],
  }
}

const submitOwnAnchor = async ($, job) => {
  const { state, e, next } = job
  const request = state.request
  if (request === null) return { drop: 'hats: no anchor request is open' }
  if (request.turnId === null) request.isRaised = true
  const out = await next(e)
  if (out.drop === undefined && request.turnId === null) request.isSubmitted = true
  if (out.drop !== undefined && state.request === request) await failRequest($, { state, reason: REASONS.notStarted })

  return out
}

const passOn = (
  $,
  e,
  next,
) => next(e)

const passOnFailed = (
  $,
  e,
  next,
) => {
  markHookFailed()

  return next(e)
}

const passOnFailedPrompt = (
  $,
  e,
  next,
) => {
  markHookFailed()
  if (!next.called && isOwnContinuation(e)) return { drop: HOOK_FAILED_DROP }

  return next(e)
}

const passOnFailedRun = (
  $,
  e,
  next,
) => {
  markHookFailed()

  return failOwnRun($, e, next)
}

const passOnFailedTurn = (
  $,
  e,
  next,
) => {
  const state = session
  endClearBeforeRun($, KEPT.hookFailed).catch(() => {})
  if (state === null || state.request === null || state.request.turnId !== e.turnId) return passOnFailed($, e, next)
  const isWindow = state.request.isWindow
  setAskFailed(state.request.limits)
  state.request = null
  if (isWindow) setStage(state, { stage: 'failed', reason: REASONS.hookFailed })
  queueStage($, state)
  tellUser($, getFailedLine(REASONS.hookFailed))

  return next(e)
}

const onSessionStart = async (
  $,
  e,
  next,
) => {
  isActive = e.isInteractive === true
  cwd = e.cwd
  if (!isActive) return next(e)
  forgetClear()
  forgetCell()
  session = createSession(await $.session.id())
  await restoreStage($, session)

  return next(e)
}

const onSessionEnd = async (
  $,
  e,
  next,
) => {
  if (!isActive || session === null) return next(e)
  if (e.reason === 'clear' || e.reason === 'resume') {
    const state = session
    session = null
    await endChain($, { state, reason: REASONS.sessionChanged })
    await endClearOnSessionEnd($, e.reason)
  }

  return next(e)
}

const onPromptSubmit = async (
  $,
  e,
  next,
) => {
  if (!isActive) return next(e)
  noteInput(e.origin)
  if (isOwnContinuation(e)) return passContinuation($, e, next)
  const state = await findState($)
  if (isOwnAnchor(e)) return submitOwnAnchor($, { state, e, next })
  if (e.origin?.kind === 'plugin' || e.command !== undefined) return next(e)
  const warning = await findLimitWarning($, state)
  const text = state.pending
  const texts = [
    warning?.text ?? null,
    text,
  ].filter(part => part !== null)
  if (texts.length === 0) return next(e)
  state.pending = null
  const out = await next({
    ...e,
    context: [
      ...(e.context ?? []),
      ...texts,
    ],
  })
  if (out.drop !== undefined && state.pending === null) state.pending = text
  if (out.drop === undefined && warning !== null) await markWarned($, { state, warning })

  return out
}

const onTurnStart = async (
  $,
  e,
  next,
) => {
  if (!isActive || e.agentId !== undefined) return next(e)
  const state = await findState($)
  const startedAt = await $.clock.now()
  const request = state.request
  if (request !== null && request.isSubmitted && request.turnId === null) request.turnId = e.turnId
  state.turn = createTurn(e.turnId, startedAt)
  await updateArm($, state)
  await notePace($, state)

  return next(e)
}

const findCallDenial = async ($, e) => {
  if (!isDrainCall(e)) return null
  const state = await findState($)
  await updateArm($, state)
  const limit = await findLimitDenial($, state)

  return limit ?? findDenial($, state)
}

const onToolCall = async (
  $,
  e,
  next,
) => {
  if (!isActive) return next(e)
  const denial = await findCallDenial($, e)
  if (denial !== null) return { deny: denial }
  if (e.agentId !== undefined) return passAgentCall($, e, next)
  const state = await findState($)
  const turn = state.turn
  const isWrite = turn !== null && WRITE_TOOLS.includes(e.tool)
  const target = isWrite ? await recordSnapshot($, { turn, path: e.file_path }) : null
  const out = await next(e)
  const endedAt = await $.clock.now()
  noteToolEnd(endedAt)
  noteMainToolEnd(endedAt)
  if (target !== null && isDone(out)) await recordOwnWrite($, { turn, target })
  if (turn !== null && e.tool === 'Bash') recordStepsOutput(turn, { command: e.command, out })
  if (turn !== null && e.tool === 'Bash' && isDone(out)) await recordHandoffOutput($, { turn, command: e.command, out })

  return findDelivered($, { state, out })
}

const onCommandRun = async (
  $,
  e,
  next,
) => {
  if (!isActive || !isOwnClear(e, next)) return next(e)
  if (isClearOpen()) return runOwnClear($, e, next)

  return refuseLostClear($, await findState($))
}

const onTurnComplete = async (
  $,
  e,
  next,
) => {
  if (!isActive || e.agentId !== undefined) return next(e)
  const state = await findState($)
  const turn = state.turn?.id === e.turnId ? state.turn : null
  state.turn = null
  if (state.request !== null && state.request.turnId === e.turnId) {
    const reading = await updateArm($, state)
    await finishRequest($, { state, reason: e.reason, turn, turnId: e.turnId, reading })
  } else if (e.reason === 'answer') {
    await judgeTurnEnd($, { state, turn })
  }

  return next(e)
}

const onMeasure = async (
  $,
  e,
  next,
) => {
  if (!isActive) return next(e)
  const state = await findState($)
  setPacePoints(state, { rateLimits: e.rateLimits, now: await $.clock.now() })

  return next(e)
}

export const register = on => {
  on('session.start', onSessionStart).catch(passOn)
  on('session.end', onSessionEnd).catch(passOn)
  on('prompt.submit', onPromptSubmit).catch(passOnFailedPrompt)
  on('turn.start', onTurnStart).catch(passOnFailed)
  on('tool.call', onToolCall).catch(passOnFailed)
  on('turn.complete', onTurnComplete).catch(passOnFailedTurn)
  on('command.run', onCommandRun).catch(passOnFailedRun)
  on('session.measure', onMeasure).catch(passOn)
}
