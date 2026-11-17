import {
  DEFAULTS,
  HOOK_FAILED_DROP,
  INTERRUPTED_LINE,
  KEPT,
  REASONS,
  RELOADED_LINE,
  createArm,
  findRefusalOutcome,
  getFailedLine,
  getPauseLine,
  getRequestLine,
  getSavedLine,
  getTurnFailure,
  getWarningText,
  isSaveDue,
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
  findVerdict,
  recordHandoffOutput,
  recordOwnWrite,
  recordSnapshot,
  recordStepsOutput,
} from './anchor-check.js'
import {
  endClearBeforeRun,
  endClearOnSessionEnd,
  failOwnRun,
  forgetClear,
  isClearOpen,
  isOwnClear,
  isOwnContinuation,
  isPausedAfterClear,
  markChainFailed,
  noteInput,
  noteToolEnd,
  passAgentCall,
  passContinuation,
  refuseLostClear,
  runOwnClear,
  startClear,
  watchInputs,
} from './clear-chain.js'

const WRITE_TOOLS = [
  'Write',
  'Edit',
  'MultiEdit',
]

let isActive = false
let cwd = ''
let session = null
let requestCount = 0

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
})

const endChain = async ($, job) => {
  const { state, reason } = job
  if (state.request === null) return
  state.request = null
  setStage(state, { stage: 'interrupted', reason })
  await queueStage($, state)
}

const failRequest = async ($, job) => {
  const { state, reason } = job
  state.request = null
  setStage(state, { stage: 'failed', reason })
  await queueStage($, state)
  tellUser($, getFailedLine(reason))
}

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

const isCurrent = state => session === state

const fireWarning = async ($, job) => {
  const { state, reading } = job
  if (state.request !== null) return
  state.arm.warn = false
  state.warnRound += 1
  state.percent = reading.percent
  state.thresholds = reading.thresholds
  state.pending = getWarningText(reading)
  setStage(state, { stage: 'warned' })
  await queueStage($, state)
}

const isChainAlive = async ($, job) =>
  isCurrent(job.state) && job.state.request === job.request && (await $.session.id()) === job.request.sessionId

const finishRequest = async ($, job) => {
  const { state, reason, turn } = job
  const request = state.request
  if (request === null || request.turnId !== job.turnId) return
  let verdict = reason === 'answer' || reason === 'aborted' ? null : getTurnFailure(reason)
  if (reason === 'answer' && request.hasHookFailed) verdict = REASONS.hookFailed
  if (reason === 'answer' && !request.hasHookFailed) verdict = await findVerdict($, { turn, askedAt: request.askedAt })
  if (!(await isChainAlive($, { state, request }))) return
  if (reason === 'aborted') {
    state.request = null
    setStage(state, { stage: 'interrupted' })
    await queueStage($, state)
    tellUser($, INTERRUPTED_LINE)
    return
  }
  if (verdict !== null) {
    await failRequest($, { state, reason: verdict })
    return
  }
  state.request = null
  setStage(state, { stage: 'saved', marker: turn.save.path })
  await queueStage($, state)
  if (request.after === 'clear') {
    await startClear($, { state, request, turn })
    return
  }
  tellUser($, getSavedLine(request))
}

const onRunDone = async ($, job) => {
  if (job.request.isRaised || !(await isChainAlive($, job))) return
  await failRequest($, { state: job.state, reason: REASONS.notStarted })
}

const onRunRefused = async ($, job) => {
  const { state, request, error } = job
  if (!(await isChainAlive($, { state, request }))) return
  const outcome = findRefusalOutcome(String(error?.message ?? error), request.previous)
  if (outcome.kind === 'failed') {
    await failRequest($, { state, reason: outcome.reason })
    return
  }
  state.request = null
  Object.assign(state, outcome.fields)
  state.arm.save = outcome.isSaveArmed
  await queueStage($, state)
}

const createRequest = (state, reading) => {
  requestCount += 1

  return {
    n: requestCount,
    sessionId: state.id,
    askedAt: 0,
    percent: reading.percent,
    save: reading.thresholds.save,
    after: reading.thresholds.after,
    turnId: null,
    isRaised: false,
    isSubmitted: false,
    hasHookFailed: false,
    previous: {
      stage: state.stage,
      reason: state.reason,
      marker: state.marker,
      saveRound: state.saveRound,
      percent: state.percent,
      thresholds: state.thresholds,
    },
  }
}

const askToAnchor = async ($, job) => {
  const { state, reading } = job
  const askedAt = await $.clock.now()
  if (!isCurrent(state) || state.request !== null) return
  const request = createRequest(state, reading)
  request.askedAt = askedAt
  state.arm.save = false
  state.arm.warn = false
  state.pending = null
  state.saveRound += 1
  state.percent = reading.percent
  state.thresholds = reading.thresholds
  setStage(state, { stage: 'requested' })
  state.request = request
  watchInputs()
  await queueStage($, state)
  tellUser($, getRequestLine(reading.percent, reading.thresholds.save))
  $.command.run({ command: 'hats:anchor' })
    .then(() => onRunDone($, { state, request }), error => onRunRefused($, { state, request, error }))
    .catch(() => {})
}

const acceptManualSave = async ($, job) => {
  const { state, turn, reading } = job
  if (turn === null || turn.save === null) return false
  if ((await findVerdict($, { turn, askedAt: turn.startedAt })) !== null || !isCurrent(state)) return false
  state.arm.save = false
  if (isWarnDue(state.arm, reading)) state.arm.warn = false
  state.pending = null
  state.percent = reading.percent
  state.thresholds = reading.thresholds
  setStage(state, { stage: 'saved', reason: REASONS.manual, marker: turn.save.path })
  await queueStage($, state)

  return true
}

const judgeTurnEnd = async ($, job) => {
  const { state, turn } = job
  const reading = await findReading($)
  if (reading === null || !isCurrent(state)) return
  setArm(state.arm, reading)
  if (isSaveDue(state.arm, reading)) {
    if (await acceptManualSave($, { state, turn, reading })) return
    if (isPausedAfterClear(await $.clock.now())) {
      state.arm.save = false
      tellUser($, getPauseLine(reading.percent, reading.thresholds.save))
      return
    }
    await askToAnchor($, { state, reading })
    return
  }
  if (isWarnDue(state.arm, reading)) await fireWarning($, { state, reading })
}

const updateArm = async ($, state) => {
  const reading = await findReading($)
  if (reading !== null) setArm(state.arm, reading)

  return reading
}

const findDelivered = async ($, job) => {
  const { state, out } = job
  const reading = await updateArm($, state)
  if (reading !== null && isCurrent(state) && isWarnDue(state.arm, reading)) await fireWarning($, { state, reading })
  if (state.pending === null || out.deny !== undefined) return out
  const text = state.pending
  state.pending = null

  return {
    ...out,
    context: [
      ...(out.context ?? []),
      text,
    ],
  }
}

const restoreStage = async ($, state) => {
  const saved = await findStageFile($, state.id)
  if (saved === null) return
  state.warnRound = saved.warnRound
  state.saveRound = saved.saveRound
  if (saved.stage !== 'requested') return
  setStage(state, { stage: 'interrupted', reason: REASONS.reloaded })
  await queueStage($, state)
  tellUser($, RELOADED_LINE)
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
  state.request = null
  setStage(state, { stage: 'failed', reason: REASONS.hookFailed })
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
  if (state.pending === null || e.origin?.kind === 'plugin' || e.command !== undefined) return next(e)
  const text = state.pending
  state.pending = null
  const out = await next({
    ...e,
    context: [
      ...(e.context ?? []),
      text,
    ],
  })
  if (out.drop !== undefined && state.pending === null) state.pending = text

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

  return next(e)
}

const onToolCall = async (
  $,
  e,
  next,
) => {
  if (!isActive) return next(e)
  if (e.agentId !== undefined) return passAgentCall($, e, next)
  const state = await findState($)
  const turn = state.turn
  const isWrite = turn !== null && WRITE_TOOLS.includes(e.tool)
  const target = isWrite ? await recordSnapshot($, { turn, path: e.file_path }) : null
  const out = await next(e)
  noteToolEnd(await $.clock.now())
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
    await updateArm($, state)
    await finishRequest($, { state, reason: e.reason, turn, turnId: e.turnId })
  } else if (e.reason === 'answer') {
    await judgeTurnEnd($, { state, turn })
  }

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
}
