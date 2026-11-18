import {
  INTERRUPTED_LINE,
  REASONS,
  createPrevious,
  findRefusalOutcome,
  getPauseLine,
  getRequestLine,
  getSavedLine,
  getTurnFailure,
  isDrainOn,
  isSaveDue,
  isWarnDue,
  setArm,
} from './thresholds.js'
import {
  findReading,
  queueStage,
  setStage,
  tellUser,
} from './files.js'
import { findVerdict } from './anchor-check.js'
import {
  UNCHECKED_LINE,
  findFreshSnapshot,
  findListText,
  findWaitLine,
  getHolderCount,
  getWindowDeadlines,
  holdWindow,
  isRoundPassed,
  isSnapshotGood,
  isWaiting,
  setPaused,
  setReading,
  settleRound,
} from './drain.js'
import {
  forgetCounted,
  forgetReleased,
} from './drain-release.js'
import {
  findPlan,
  getLiveDeadlines,
  setLimitWaiting,
  settleLimitWaits,
} from './limit-drain.js'
import {
  failRequest,
  fireWarning,
} from './stages.js'
import {
  isPausedAfterClear,
  startClear,
  watchInputs,
} from './clear-chain.js'
import {
  findLimitAsks,
  findLimitView,
  setAskFailed,
  setAsked,
  setAskedBack,
} from './limits.js'
import {
  getLimitRequestLine,
  getLimitSavedLine,
  isLimitAskDue,
} from './limit-rules.js'

let getCurrent = () => null
let requestCount = 0

export const setCurrentGetter = getter => {
  getCurrent = getter
}

export const isCurrent = state => getCurrent() === state

async function isChainAlive($, job) {
  return isCurrent(job.state) && job.state.request === job.request && (await $.session.id()) === job.request.sessionId
}

const setWindowSaved = (state, reading) => {
  state.arm.save = false
  if (isWarnDue(state.arm, reading)) state.arm.warn = false
  state.pending = null
  setReading(state, reading)
  state.drain = null
}

const countWindow = (state, job) => {
  const { request, reading } = job
  if (request.isWindow || reading === null || !isSaveDue(state.arm, reading)) return
  setWindowSaved(state, reading)
  state.saveRound += 1
  request.isWindow = true
  request.percent = reading.percent
  request.save = reading.thresholds.save
  request.after = reading.thresholds.after
}

async function findTurnVerdict($, job) {
  const { request, reason, turn } = job
  if (reason !== 'answer' && reason !== 'aborted') return getTurnFailure(reason)
  if (reason === 'aborted') return null
  if (request.hasHookFailed) return REASONS.hookFailed

  return findVerdict($, { turn, askedAt: request.askedAt })
}

export async function finishRequest($, job) {
  const { state, reason, turn, reading } = job
  const request = state.request
  if (request === null || request.turnId !== job.turnId) return
  const verdict = await findTurnVerdict($, { request, reason, turn })
  const counted = reason === 'answer' && verdict === null ? await findLimitAsks($, state) : []
  const now = await $.clock.now()
  if (!(await isChainAlive($, { state, request }))) return
  if (reason === 'aborted') {
    state.request = null
    setAskFailed(request.limits)
    if (request.isWindow) setStage(state, { stage: 'interrupted' })
    await queueStage($, state)
    tellUser($, INTERRUPTED_LINE)
    return
  }
  if (verdict !== null) {
    await failRequest($, { state, reason: verdict })
    return
  }
  state.request = null
  setAsked(counted, now)
  countWindow(state, { request, reading })
  forgetCounted(state, { isWindow: request.isWindow, kinds: [...request.limits, ...counted].map(item => item.kind) })
  if (request.isWindow) setStage(state, { stage: 'saved', marker: turn.save.path })
  await queueStage($, state)
  const limits = [
    ...request.limits,
    ...counted,
  ]
  if (limits.length > 0) tellUser($, getLimitSavedLine(limits, now))
  if (!request.isWindow) return
  if (request.after === 'clear') {
    await startClear($, { state, request, turn })
    return
  }
  tellUser($, getSavedLine(request))
}

export async function onRunDone($, job) {
  if (job.request.isRaised || !(await isChainAlive($, job))) return
  await failRequest($, { state: job.state, reason: REASONS.notStarted })
}

export async function onRunRefused($, job) {
  const { state, request, error } = job
  if (!(await isChainAlive($, { state, request }))) return
  const outcome = findRefusalOutcome(String(error?.message ?? error), request.previous)
  if (outcome.kind === 'failed') {
    await failRequest($, { state, reason: outcome.reason })
    return
  }
  setRefusedBack(state, { request, outcome })
  await queueStage($, state)
}

export const setRefusedBack = (state, job) => {
  const { request, outcome } = job
  state.request = null
  setAskedBack(request.limits, state.limits)
  if (!request.isWindow) return
  Object.assign(state, outcome.fields)
  state.arm.save = outcome.isSaveArmed
}

const createRequest = (state, job) => {
  requestCount += 1
  const { reading, isWindow } = job

  return {
    n: requestCount,
    sessionId: state.id,
    askedAt: 0,
    isWindow,
    percent: isWindow ? reading.percent : null,
    save: isWindow ? reading.thresholds.save : null,
    after: isWindow ? reading.thresholds.after : null,
    limits: job.limits,
    turnId: null,
    isRaised: false,
    isSubmitted: false,
    hasHookFailed: false,
    previous: isWindow ? createPrevious(state) : null,
  }
}

const getRequestItems = limits => limits.map(item => ({ kind: item.kind, percent: item.episode.percent, save: item.episode.save }))

async function askToAnchor($, job) {
  const { state, reading, isWindow, limits } = job
  const askedAt = await $.clock.now()
  if (!isCurrent(state) || state.request !== null) return
  const request = createRequest(state, job)
  request.askedAt = askedAt
  request.list = job.list ?? null
  setAsked(limits, askedAt)
  forgetReleased(state)
  if (isWindow) {
    state.arm.save = false
    state.arm.warn = false
    state.pending = null
    if (!isWaiting(state)) state.saveRound += 1
    setReading(state, reading)
    state.drain = null
    setStage(state, { stage: 'requested' })
  }
  state.request = request
  watchInputs()
  await queueStage($, state)
  if (limits.length > 0) tellUser($, getLimitRequestLine(getRequestItems(limits)))
  if (isWindow) tellUser($, getRequestLine(reading.percent, reading.thresholds.save))
  $.command.run({ command: 'hats:anchor' })
    .then(() => onRunDone($, { state, request }), error => onRunRefused($, { state, request, error }))
    .catch(() => {})
}

async function acceptManualSave($, job) {
  const { state, turn, reading, isWindow, limits } = job
  if (turn === null || turn.save === null) return false
  if ((await findVerdict($, { turn, askedAt: turn.startedAt })) !== null || !isCurrent(state)) return false
  setAsked(limits, await $.clock.now())
  forgetCounted(state, { isWindow, kinds: limits.map(item => item.kind) })
  if (isWindow) setWindowSaved(state, reading)
  if (isWindow) setStage(state, { stage: 'saved', reason: REASONS.manual, marker: turn.save.path })
  await queueStage($, state)

  return true
}

async function findCauses($, state) {
  const reading = await findReading($)
  if (!isCurrent(state)) return null
  if (reading !== null) setArm(state.arm, reading)
  if (reading !== null) await settleRound($, { state, reading })
  const view = await findLimitView($, state)
  if (!isCurrent(state)) return null
  if (settleLimitWaits(state, { view, now: view.now })) await queueStage($, state)
  const limits = view.items.filter(item => isLimitAskDue(item.episode))
  const isWindowDue = reading !== null && isSaveDue(state.arm, reading)

  return { reading, view, limits, isWindowDue }
}

async function isWindowWanted($, job) {
  const { state, causes } = job
  if (!causes.isWindowDue) return false
  if (!isPausedAfterClear(await $.clock.now())) return true
  setPaused(state)
  if (causes.limits.length === 0) tellUser($, getPauseLine(causes.reading.percent, causes.reading.thresholds.save))

  return false
}

const isDrainWanted = (causes, isWindow) =>
  (isWindow && isDrainOn(causes.reading.thresholds)) || (causes.limits.length > 0 && causes.view.drain.isOn)

const isAnyReady = (state, job) => {
  const { causes, plans, holders, now } = job
  const isWindowReady = causes.isWindowDue && (!isDrainOn(causes.reading.thresholds) || holders === 0 || isRoundPassed(state, now))
  const isLimitReady = plans.some(plan => !causes.view.drain.isOn || holders === 0 || plan.untilMs <= now)

  return isWindowReady || isLimitReady
}

async function holdCauses($, job) {
  const { state, causes, plans, holders, now } = job
  if (causes.isWindowDue) holdWindow(state, { reading: causes.reading, now })
  for (const plan of plans) if (plan.isNew) setLimitWaiting(plan, { now, minutes: causes.view.drain.minutes })
  await queueStage($, state)
  const line = findWaitLine(state, { deadlines: [...getWindowDeadlines(state), ...getLiveDeadlines(state)], holders, now })
  if (line !== null) tellUser($, line)
}

async function decideDrain($, job) {
  const { state, causes, snapshot } = job
  if (!causes.isWindowDue && causes.limits.length === 0) return
  const isGood = isSnapshotGood(snapshot)
  if (!isGood) tellUser($, UNCHECKED_LINE)
  const list = isGood ? findListText(snapshot.tasks, snapshot.crons) : null
  const holders = isGood ? getHolderCount(snapshot.tasks) : 0
  const now = await $.clock.now()
  const plans = causes.limits.map(item => findPlan(item, { view: causes.view, now }))
  if (!isGood || isAnyReady(state, { causes, plans, holders, now })) {
    await askToAnchor($, { state, reading: causes.reading, isWindow: causes.isWindowDue, limits: causes.limits, list })
    return
  }
  if (!isCurrent(state) || state.request !== null) return
  await holdCauses($, { state, causes, plans, holders, now })
}

export async function judgeTurnEnd($, job) {
  const { state, turn } = job
  const first = await findCauses($, state)
  if (first === null) return
  if (!first.isWindowDue && first.limits.length === 0) {
    if (first.reading !== null && isWarnDue(state.arm, first.reading)) await fireWarning($, { state, reading: first.reading })
    return
  }
  const isWindowDue = first.isWindowDue
  if (await acceptManualSave($, { state, turn, reading: first.reading, isWindow: isWindowDue, limits: first.limits })) return
  const isWindow = await isWindowWanted($, { state, causes: first })
  if (!isWindow && first.limits.length === 0) return
  if (!isDrainWanted(first, isWindow)) {
    await askToAnchor($, { state, reading: first.reading, isWindow, limits: first.limits, list: null })
    return
  }
  const snapshot = await findFreshSnapshot($, { state, turn })
  if (state.request !== null || (await $.session.id()) !== state.id) return
  const causes = await findCauses($, state)
  if (causes !== null) await decideDrain($, { state, causes, snapshot })
}
