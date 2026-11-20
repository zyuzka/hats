import {
  CLEAR_PAUSE_MS,
  CONTINUE_DROPPED,
  DRAFT_AFTER_LINE,
  KEPT,
  REASONS,
  findStepsReason,
  getClearRefusal,
  getClearingLine,
  getContinueText,
  getHandedKey,
  getHandedPath,
  getInputKind,
  getInputReason,
  getKeptLine,
  getNotBackLine,
  isOwnOrigin,
} from './thresholds.js'
import {
  findStageFile,
  queueStage,
  setStage,
  tellUser,
} from './files.js'
import { findAnchorFacts } from './anchor-check.js'
import {
  findNoteState,
  findPromptReason,
  findSessionReason,
  getSnapshotReason,
  isHandoffOff,
  isPluginInPlace,
  waitForHanded,
  waitForSnapshot,
} from './clear-check.js'

const NOT_WAITING = 'hats: no clear of this plugin is waiting to go on'

let chain = null
let foreign = null
let lastClearAt = null
let lastToolEndAt = 0
let lastMainToolEndAt = 0

export const watchInputs = () => {
  foreign = null
}

export const noteInput = origin => {
  const kind = getInputKind(origin)
  if (kind === null) return
  if (foreign === null) foreign = kind
  if (chain !== null && chain.isCleared && chain.foreignAfter === null) chain.foreignAfter = kind
}

export const noteToolEnd = at => {
  if (at > lastToolEndAt) lastToolEndAt = at
}

export const noteMainToolEnd = at => {
  if (at > lastMainToolEndAt) lastMainToolEndAt = at
}

export const getLastMainToolEnd = () => lastMainToolEndAt

export async function passAgentCall($, e, next) {
  const out = await next(e)
  noteToolEnd(await $.clock.now())

  return out
}

export const forgetClear = () => {
  chain = null
}

export const isClearOpen = () => chain !== null

export const isPausedAfterClear = now => lastClearAt !== null && now - lastClearAt < CLEAR_PAUSE_MS

export const markChainFailed = () => {
  if (chain !== null) chain.hasHookFailed = true
}

export const isOwnClear = (e, next) => e.command === 'clear' && next.origin?.plugin === 'hats'

export const isOwnContinuation = e => isOwnOrigin(e.origin) && e.origin.asUser === true && e.command === undefined

const isBeforeClear = current => current.stage === 'checking' || current.stage === 'queued'

const finish = current => {
  current.stage = 'done'
  if (chain === current) chain = null
}

async function keep($, current, reason) {
  if (current.stage === 'done') return
  finish(current)
  setStage(current.state, { stage: 'kept', reason, marker: current.state.marker })
  await queueStage($, current.state)
  tellUser($, getKeptLine(current.request.percent, reason))
}

const findEarlyReason = current => {
  if (current.hasHookFailed) return KEPT.hookFailed
  if (foreign !== null) return getInputReason(foreign)

  return findStepsReason(current.turn.steps)
}

async function findKeptReason($, current) {
  const { request, turn } = current
  const early = findEarlyReason(current)
  if (early !== null) return early
  if (!(await isPluginInPlace($))) return KEPT.noPlugin
  if (await isHandoffOff($)) return KEPT.handoffOff
  const snapshot = await waitForSnapshot($, { id: request.sessionId, getAfter: () => lastToolEndAt })
  current.facts = await findAnchorFacts($, turn)
  const note = await findNoteState($, current.facts)
  if (note.reason !== null) return note.reason
  const background = getSnapshotReason(snapshot, note.text)
  if (background !== null) return background
  const late = (await findPromptReason($)) ?? (await findSessionReason($, request.sessionId))

  return late ?? findEarlyReason(current)
}

const getHanded = current => ({
  path: getHandedPath(current.facts.markerPath),
  key: getHandedKey(current.facts.marker),
  session: current.newId,
})

async function tellCleared($, current) {
  const isBack = current.newId !== null && (await waitForHanded($, getHanded(current)))
  finish(current)
  tellUser($, isBack ? DRAFT_AFTER_LINE : getNotBackLine(current.facts.notePath))
}

async function tellAfterFailure($, current) {
  const id = await $.session.id().catch(() => null)
  current.newId = typeof id === 'string' && id !== current.request.sessionId ? id : null
  await tellCleared($, current)
}

async function onClearDone($, current) {
  if (current.stage !== 'queued' || chain !== current) return
  const id = await $.session.id().catch(() => null)
  if (current.stage !== 'queued') return
  if (typeof id !== 'string' || id === current.request.sessionId) {
    await keep($, current, KEPT.notCleared)
    return
  }
  lastClearAt = await $.clock.now()
  current.stage = 'clearing'
  current.newId = id
  await tellCleared($, current)
}

export async function startClear($, job) {
  const { state, request, turn } = job
  const current = {
    state,
    request,
    turn,
    stage: 'checking',
    hasHookFailed: false,
    isCleared: false,
    foreignAfter: null,
    facts: null,
    newId: null,
  }
  chain = current
  const reason = await findKeptReason($, current)
  if (current.stage !== 'checking') return
  if (reason !== null) {
    await keep($, current, reason)
    return
  }
  current.stage = 'queued'
  setStage(state, { stage: 'cleared', marker: state.marker })
  await queueStage($, state)
  if (current.stage !== 'queued') return
  tellUser($, getClearingLine(request.percent))
  $.command.run({ command: 'clear' })
    .then(() => onClearDone($, current), error => keep($, current, getClearRefusal(String(error?.message ?? error))))
    .catch(() => {})
}

export async function endClearBeforeRun($, reason) {
  const current = chain
  if (current !== null && isBeforeClear(current)) await keep($, current, reason)
}

export async function endClearOnSessionEnd($, reason) {
  const isQueuedClearLanding = reason === 'clear' && chain?.stage === 'queued'
  if (!isQueuedClearLanding) await endClearBeforeRun($, KEPT.sessionChanged)
}

export async function refuseLostClear($, state) {
  const saved = await findStageFile($, state.id)
  if (saved === null || saved.stage !== 'cleared') return {}
  state.percent = saved.percent
  setStage(state, { stage: 'kept', reason: REASONS.reloaded })
  await queueStage($, state)
  if (saved.percent !== null) tellUser($, getKeptLine(saved.percent, REASONS.reloaded))

  return {}
}

async function findRunReason($, current) {
  const reason = (await findPromptReason($)) ?? (await findSessionReason($, current.request.sessionId))
  if (current.hasHookFailed) return KEPT.hookFailed
  if (foreign !== null) return getInputReason(foreign)

  return reason
}

async function goOn($, current) {
  const isBack = await waitForHanded($, getHanded(current))
  if (current.stage !== 'clearing') return
  if (!isBack) {
    finish(current)
    tellUser($, getNotBackLine(current.facts.notePath))
    return
  }
  const draft = await findPromptReason($)
  if (current.stage !== 'clearing') return
  if (draft !== null || current.foreignAfter !== null || current.hasHookFailed) {
    finish(current)
    tellUser($, DRAFT_AFTER_LINE)
    return
  }
  current.stage = 'continuing'
  current.text = getContinueText(current.request.percent)
  $.prompt.submit({ text: current.text, asUser: true })
    .then(() => finish(current), () => finish(current))
    .catch(() => {})
}

export async function runOwnClear($, e, next) {
  const current = chain
  if (current === null || current.stage !== 'queued') return {}
  const reason = await findRunReason($, current)
  if (current.stage !== 'queued') return {}
  if (reason !== null) {
    await keep($, current, reason)
    return {}
  }
  current.stage = 'clearing'
  current.isCleared = true
  current.ranAt = await $.clock.now()
  const out = await next(e).catch(error => keep($, current, getClearRefusal(String(error?.message ?? error))))
  if (current.stage !== 'clearing') return {}
  lastClearAt = current.ranAt
  const id = await $.session.id()
  if (typeof id !== 'string' || id === current.request.sessionId) {
    await keep($, current, KEPT.notCleared)
    return out
  }
  current.newId = id
  await goOn($, current)

  return out
}

export function failOwnRun($, e, next) {
  markChainFailed()
  if (next.called) {
    const current = chain
    if (current !== null && current.stage === 'clearing') {
      finish(current)
      tellAfterFailure($, current).catch(() => {})
    }
    return next(e)
  }
  if (!isOwnClear(e, next)) return next(e)
  const current = chain
  if (current !== null && isBeforeClear(current)) keep($, current, KEPT.hookFailed).catch(() => {})

  return {}
}

export async function passContinuation($, e, next) {
  const current = chain
  if (current === null || current.stage !== 'continuing' || e.text !== current.text) return { drop: NOT_WAITING }
  const id = await $.session.id()
  if (current.foreignAfter !== null || current.hasHookFailed || id !== current.newId) {
    finish(current)
    return { drop: CONTINUE_DROPPED }
  }

  return next(e)
}
