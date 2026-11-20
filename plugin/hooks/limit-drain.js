import {
  DEFAULTS,
  getDrainFields,
} from './thresholds.js'
import {
  EPISODE_MS,
  LIMIT_KINDS,
  createEvent,
} from './limit-rules.js'

export const DRAIN_OFF = { isOn: false, minutes: DEFAULTS.drainMinutes }

const MINUTE_MS = 60 * 1000

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value)

export const findDrainSetting = text => {
  let data
  try {
    data = JSON.parse(text)
  } catch {
    return DRAIN_OFF
  }
  if (!isObject(data)) return DRAIN_OFF
  const fields = getDrainFields(data)

  return { isOn: fields.drain, minutes: fields.drainMinutes }
}

const getStampOf = ms => new Date(ms).toISOString()

const isOpenWait = episode =>
  episode !== null &&
  episode.waiting !== null &&
  episode.waiting !== undefined &&
  episode.waiting.cancelled_at === null

export const isWaitLive = episode => isOpenWait(episode) && episode.asked === null

const isAskedBy = (episode, request) =>
  request !== null && request.limits.some(item => item.episode === episode && item.event === episode.asked)

export const isLimitDrainCause = episode =>
  episode !== null &&
  episode.save !== null &&
  episode.asked === null &&
  (episode.warned !== null || isWaitLive(episode))

export const hasLimitDrainCause = state => LIMIT_KINDS.some(kind => isLimitDrainCause(state.limits[kind] ?? null))

const findHatBase = (kind, job) => {
  const first = job.hat?.firstWarned?.[kind] ?? null
  if (first === null || Math.abs(first.episodeMs - job.episode.resetsMs) >= EPISODE_MS) return null

  return { ms: first.atMs, origin: 'hat' }
}

const findWarnedBase = job => {
  const warned = job.episode.warned
  if (warned === null || warned.worn !== job.worn) return null

  return { ms: Date.parse(warned.at), origin: 'warned' }
}

export const findDeadline = (kind, job) => {
  const bases = [
    findHatBase(kind, job),
    findWarnedBase(job),
    { ms: job.deferredMs, origin: 'deferred' },
  ].filter(base => base !== null)
  const base = bases.reduce((best, next) => (next.ms < best.ms ? next : best))

  return { untilMs: base.ms + job.minutes * MINUTE_MS, origin: base.origin }
}

const setNearer = (episode, job) => {
  const waiting = episode.waiting
  const deadline = findDeadline(job.kind, {
    hat: job.hat,
    episode,
    worn: waiting.worn,
    minutes: waiting.drain_minutes,
    deferredMs: Date.parse(waiting.at),
  })
  if (deadline.untilMs >= Date.parse(waiting.until)) return false
  waiting.until = getStampOf(deadline.untilMs)
  waiting.origin = deadline.origin

  return true
}

const isWaitBroken = (episode, job) => {
  const { view, now } = job
  const item = view.all.find(entry => entry.episode === episode) ?? null

  return (
    episode.lastResetsMs <= now ||
    view.thresholds === null ||
    view.isUnder === false ||
    (item !== null && item.why === null) ||
    episode.save === null ||
    episode.percent < episode.save ||
    (view.hat !== null && view.hat.worn !== episode.waiting.worn)
  )
}

const setCancelled = (episode, now) => {
  episode.waiting.cancelled_at = getStampOf(now)
}

const settleKind = (state, job) => {
  const { kind, view, now } = job
  const episode = state.limits[kind] ?? null
  const previous = episode?.previous ?? null
  let isChanged = false
  if (isWaitLive(previous)) {
    setCancelled(previous, now)
    isChanged = true
  }
  if (isWaitLive(episode) && isWaitBroken(episode, { view, now })) {
    setCancelled(episode, now)
    return true
  }
  const isKept = isWaitLive(episode) || (isOpenWait(episode) && isAskedBy(episode, state.request))

  return (isKept && view.hat !== null && setNearer(episode, { kind, hat: view.hat })) || isChanged
}

export const settleLimitWaits = (state, job) => {
  let isChanged = false
  for (const kind of LIMIT_KINDS) {
    if (settleKind(state, { kind, ...job })) isChanged = true
  }

  return isChanged
}

export const findPlan = (item, job) => {
  const { view, now } = job
  if (isWaitLive(item.episode)) return { item, untilMs: Date.parse(item.episode.waiting.until), isNew: false }
  const deadline = findDeadline(item.kind, {
    hat: view.hat,
    episode: item.episode,
    worn: item.worn,
    minutes: view.drain.minutes,
    deferredMs: now,
  })

  return { item, untilMs: deadline.untilMs, origin: deadline.origin, isNew: true }
}

export const setLimitWaiting = (plan, job) => {
  const { item } = plan
  item.episode.waiting = {
    ...createEvent({
      now: job.now,
      percent: item.episode.percent,
      worn: item.worn,
      reason: item.why,
      target: item.episode.save,
      lead: item.episode.lead,
    }),
    until: getStampOf(plan.untilMs),
    origin: plan.origin,
    drain_minutes: job.minutes,
    cancelled_at: null,
  }
}

export const getLiveDeadlines = state =>
  LIMIT_KINDS.map(kind => state.limits[kind] ?? null)
    .filter(isWaitLive)
    .map(episode => Date.parse(episode.waiting.until))
