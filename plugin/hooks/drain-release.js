import {
  DRAIN_WARNING,
  getLowest,
  isDrainOn,
} from './thresholds.js'
import {
  LIMIT_KINDS,
  LIMIT_WORDS,
} from './limit-rules.js'
import { isLimitDrainCause } from './limit-drain.js'

export const DRAIN_OFF_REASON = 'the drain was turned off in Hats'

const WINDOW_CAUSE = 'window'
const SWITCH_CAUSE = 'switch'

export const createTold = () => ({ window: false, five_hour: null, seven_day: null })

const getReleaseTail = reasons =>
  reasons.includes(DRAIN_OFF_REASON)
    ? '; the session still anchors at its thresholds. '
    : ', so this session no longer anchors for it. '

export const getReleaseText = reasons =>
  `Hats drain: background work is allowed again — ${reasons.join(', and ')}${getReleaseTail(reasons)}` +
  'Tell the user so in one short line in your reply, in their language.'

export const getWindowReason = lowest =>
  lowest === null ? 'the thresholds of its context window are off' : `its context window fell below ${lowest}%`

const addReason = (state, cause, text) => {
  if (!state.released.some(entry => entry.text === text)) state.released.push({ cause, text })
}

export const noteWindowTold = (state, text) => {
  if (text !== null && text.endsWith(DRAIN_WARNING)) state.drainTold.window = true
}

export const noteDenialTold = state => {
  state.drainTold.window = true
}

export const noteLimitsTold = (state, items) => {
  for (const item of items) state.drainTold[item.kind] = { episode: item.episode, worn: item.worn }
}

export const noteWindowBelow = (state, lowest) => {
  if (state.drain === null || !state.drainTold.window) return
  state.drainTold.window = false
  addReason(state, WINDOW_CAUSE, getWindowReason(lowest))
}

export const forgetReleased = state => {
  state.released = []
}

export const forgetCounted = (state, job) => {
  forgetReleased(state)
  if (job.isWindow) state.drainTold.window = false
  for (const kind of job.kinds) state.drainTold[kind] = null
}

const isKindRefusing = (view, kind) => view.items.some(item => item.kind === kind && isLimitDrainCause(item.episode))

const findHatReason = (view, told) => {
  if (view.isUnder === false) return 'this session is no longer under Hats'
  if (view.hat.worn !== told.worn) return 'the hat changed'

  return null
}

const findLimitReason = (state, job) => {
  const { kind, told, view } = job
  const word = LIMIT_WORDS[kind]
  const episode = state.limits[kind] ?? null
  if (episode !== told.episode) return `its ${word} limit reset`
  if (episode.asked !== null) return null
  if (episode.save === null) return `the anchor threshold of its ${word} limit is off`
  if (view.hat === null) return null
  const hatReason = findHatReason(view, told)
  if (hatReason !== null) return hatReason
  if (view.all.some(item => item.kind === kind && item.why === null)) return `Hats now changes hats on its ${word} limit`

  return `Hats no longer holds anchoring for its ${word} limit`
}

const isKindUnread = (view, kind) => view.thresholds === null || !view.seen.includes(kind)

const settleLimitsTold = (state, view) => {
  for (const kind of LIMIT_KINDS) {
    const told = state.drainTold[kind]
    if (told === null || isKindUnread(view, kind)) continue
    if (view.drain.isOn && isKindRefusing(view, kind)) continue
    const reason = view.drain.isOn ? findLimitReason(state, { kind, told, view }) : DRAIN_OFF_REASON
    if (reason === null) continue
    state.drainTold[kind] = null
    addReason(state, SWITCH_CAUSE, reason)
  }
}

const findWindowOffReason = thresholds => {
  if (thresholds.drain !== true) return DRAIN_OFF_REASON
  if (thresholds.save === null) return 'the anchor threshold of its context window is off'

  return null
}

const settleWindowTold = (state, reading) => {
  if (!state.drainTold.window) return
  if (state.drain === null && state.request === null) state.drainTold.window = false
  if (state.drain === null || reading === null) return
  const reason = findWindowOffReason(reading.thresholds)
  if (reason === null) return
  state.drainTold.window = false
  addReason(state, SWITCH_CAUSE, reason)
}

const dropRisenWindow = (state, reading) => {
  if (reading === null) return
  const lowest = getLowest(reading.thresholds)
  if (lowest !== null && reading.percent >= lowest) state.released = state.released.filter(entry => entry.cause !== WINDOW_CAUSE)
}

const isWindowRefusing = (state, thresholds) => state.drain !== null && state.arm.save && isDrainOn(thresholds)

const isAnyRefusing = (state, job) =>
  job.isRestart === true ||
  isWindowRefusing(state, job.reading?.thresholds ?? state.thresholds) ||
  (job.view.drain.isOn && LIMIT_KINDS.some(kind => isKindRefusing(job.view, kind)))

export const findReleaseText = (state, job) => {
  settleLimitsTold(state, job.view)
  settleWindowTold(state, job.reading)
  dropRisenWindow(state, job.reading)
  if (state.released.length === 0 || isAnyRefusing(state, job)) return null

  return getReleaseText(state.released.map(entry => entry.text))
}
