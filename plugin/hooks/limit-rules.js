import {
  DRAIN_WARNING,
  getSha256,
  getStamp,
  getStampSeconds,
  isDrainMinutes,
} from './thresholds.js'

export const LIMIT_DEFAULTS = { warn: 70, save: 80 }
export const LIMIT_KINDS = [
  'five_hour',
  'seven_day',
]
export const HAT_USAGE_FILE = 'hat-usage.json'
export const EPISODE_MS = 60 * 60 * 1000
export const ALIVE_MS = 15 * 60 * 1000
export const WHY = {
  no_hat: 'Hats has no other hat to switch to',
  auto_switch_off: 'Hats does not change hats by itself (auto-switch is off)',
  switch_threshold_off: 'Hats does not switch hats on this limit',
  hats_not_running: 'Hats is not running',
}

const LIMIT_RANGE = { low: 10, high: 95 }
export const LIMIT_WORDS = { five_hour: '5-hour', seven_day: 'weekly' }
const DAYS = [
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
]
const EVENT_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value)

const isLimitThreshold = value =>
  value === null ||
  (Number.isInteger(value) &&
    value >= LIMIT_RANGE.low &&
    value <= LIMIT_RANGE.high)

const isLimitPercent = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 100

const getField = (data, name, fallback) => (Object.hasOwn(data, name) ? data[name] : fallback)

export const findLimitThresholds = text => {
  let data
  try {
    data = JSON.parse(text)
  } catch {
    return null
  }
  if (!isObject(data)) return null
  const warn = getField(data, 'limit_warn_percent', LIMIT_DEFAULTS.warn)
  const save = getField(data, 'limit_save_percent', LIMIT_DEFAULTS.save)
  if (!isLimitThreshold(warn) || !isLimitThreshold(save)) return null
  if (warn !== null && save !== null && warn >= save) return null

  return { warn, save }
}

export const getLimitLowest = thresholds => {
  const enabled = [
    thresholds.warn,
    thresholds.save,
  ].filter(value => value !== null)

  return enabled.length === 0 ? null : Math.min(...enabled)
}

const findReading = (entry, now) => {
  if (!isObject(entry) || !LIMIT_KINDS.includes(entry.kind) || !isLimitPercent(entry.percentUsed)) return null
  const resetsMs = typeof entry.resetsAt === 'string' ? Date.parse(entry.resetsAt) : Number.NaN

  return Number.isNaN(resetsMs) || resetsMs <= now ? null : { percent: entry.percentUsed, resetsMs }
}

export const findLimitReadings = (rateLimits, now) => {
  const readings = {}
  if (!Array.isArray(rateLimits)) return readings
  for (const entry of rateLimits) {
    const reading = findReading(entry, now)
    if (reading !== null && readings[entry.kind] === undefined) readings[entry.kind] = reading
  }

  return readings
}

export const createLimits = () => ({ five_hour: null, seven_day: null })

const createEpisode = (job, previous) => ({
  resetsMs: job.reading.resetsMs,
  lastResetsMs: job.reading.resetsMs,
  percent: job.reading.percent,
  warn: job.thresholds.warn,
  save: job.thresholds.save,
  lead: job.thresholds.lead,
  warned: null,
  asked: null,
  waiting: null,
  failedAsks: 0,
  previous,
})

const isSameEpisode = (episode, resetsMs) => episode !== null && Math.abs(resetsMs - episode.resetsMs) < EPISODE_MS

export const setEpisode = (limits, job) => {
  const { kind, reading, thresholds } = job
  const current = limits[kind]
  if (isSameEpisode(current, reading.resetsMs)) {
    current.percent = reading.percent
    current.lastResetsMs = reading.resetsMs
    current.warn = thresholds.warn
    current.save = thresholds.save
    current.lead = thresholds.lead
    return current
  }
  limits[kind] = createEpisode(job, current === null ? null : { ...current, previous: null })

  return limits[kind]
}

export const isLimitWarnDue = episode => episode.warn !== null && episode.percent >= episode.warn && episode.warned === null

export const isLimitAskDue = episode => episode.save !== null && episode.percent >= episode.save && episode.asked === null

const findFirstWarning = value => {
  if (!isObject(value) || typeof value.episode !== 'string' || typeof value.at !== 'string') return null
  const episodeMs = Date.parse(value.episode)
  const atMs = Date.parse(value.at)

  return Number.isNaN(episodeMs) || Number.isNaN(atMs) ? null : { episodeMs, atMs }
}

const findFirstWarned = value => ({
  five_hour: isObject(value) ? findFirstWarning(value.five_hour) : null,
  seven_day: isObject(value) ? findFirstWarning(value.seven_day) : null,
})

const isHatUsageShape = data =>
  isObject(data) &&
  (data.worn === null || typeof data.worn === 'string') &&
  (data.credential_service === null || typeof data.credential_service === 'string') &&
  isObject(data.switch_covers) &&
  LIMIT_KINDS.every(kind => typeof data.switch_covers[kind] === 'boolean') &&
  typeof data.alive_at === 'string' &&
  !Number.isNaN(Date.parse(data.alive_at)) &&
  typeof data.auto_switch_on === 'boolean' &&
  typeof data.has_a_hat_to_switch_to === 'boolean'

export const findHatUsage = text => {
  let data
  try {
    data = JSON.parse(text)
  } catch {
    return null
  }
  if (!isHatUsageShape(data)) return null

  return {
    worn: data.worn,
    service: data.credential_service,
    covers: { ...data.switch_covers },
    aliveMs: Date.parse(data.alive_at),
    isAutoSwitchOn: data.auto_switch_on,
    hasAHat: data.has_a_hat_to_switch_to,
    firstWarned: findFirstWarned(data.first_warned),
  }
}

export const isUnderHats = (usage, cell) => usage.worn !== null && usage.service !== null && usage.service === cell

export const findWhy = (usage, kind, now) => {
  if (now - usage.aliveMs > ALIVE_MS) return 'hats_not_running'
  if (usage.covers[kind]) return null
  if (!usage.isAutoSwitchOn) return 'auto_switch_off'
  if (!usage.hasAHat) return 'no_hat'

  return 'switch_threshold_off'
}

const getHashSuffix = async env => {
  const secure = env.CLAUDE_SECURESTORAGE_CONFIG_DIR
  const config = typeof env.CLAUDE_CONFIG_DIR === 'string' ? env.CLAUDE_CONFIG_DIR.trim() : ''
  let named = null
  if (typeof secure === 'string') named = secure.trim() === '' ? null : secure.trim()
  if (typeof secure !== 'string' && config.startsWith('/')) named = config
  if (named === null) return ''

  return `-${(await getSha256(named.normalize('NFC'))).slice(0, 8)}`
}

export const getCredentialService = async env => {
  const custom = typeof env.CLAUDE_CODE_CUSTOM_OAUTH_URL === 'string' ? env.CLAUDE_CODE_CUSTOM_OAUTH_URL.trim() : ''

  return `Claude Code${custom === '' ? '' : '-custom-oauth'}-credentials${await getHashSuffix(env)}`
}

export const createEvent = job => {
  const early = job.early ?? null

  return {
    at: new Date(job.now).toISOString(),
    percent: job.percent,
    worn: job.worn,
    reason: job.reason,
    early: early !== null,
    target: early === null ? (job.target ?? null) : early.target,
    lead_seconds: early === null ? (job.lead ?? null) : early.lead,
    ...(early === null ? {} : { minutes_to_save: early.minutes }),
  }
}

const getWhole = percent => Math.floor(percent)

const getPadded = value => String(value).padStart(2, '0')

export const getWhen = (resetsMs, now) => {
  const at = new Date(resetsMs)
  const today = new Date(now)
  const time = `${getPadded(at.getHours())}:${getPadded(at.getMinutes())}`
  const isToday = at.getFullYear() === today.getFullYear() && at.getMonth() === today.getMonth() && at.getDate() === today.getDate()

  return isToday ? time : `${DAYS[at.getDay()]} ${time}`
}

const getAsking = items => items.filter(item => item.episode.save !== null && item.episode.asked === null)

const getAnchorPart = (asking, drain) => {
  if (asking.length === 0) return ''
  const later = drain === null ? '' : `, or, while its background work runs, at the end of a later turn within ${drain.minutes} min`
  if (asking.some(item => item.episode.percent >= item.episode.save)) return `This session anchors at the end of this turn${later}. `

  return `This session anchors at the end of a turn once it reaches ${Math.min(...asking.map(item => item.episode.save))}%${later}. `
}

const getWarningPart = item => {
  const at = `at ${getWhole(item.episode.percent)}% of its ${LIMIT_WORDS[item.kind]} limit `
  if ((item.early ?? null) === null) return `${at}(warning threshold ${item.episode.warn}%) and ${WHY[item.why]}`

  return (
    `${at}and spending fast: at the pace of the last minutes it reaches ${item.early.target}% ` +
    `in about ${item.early.minutes} minutes, and ${WHY[item.why]}`
  )
}

export const getLimitWarningText = (items, drain = null) => {
  const asking = getAsking(items)
  const isDraining = drain !== null && asking.length > 0

  return (
    `Hats limit threshold: this session's account is ${items.map(getWarningPart).join('; it is also ')}. ` +
    `${getAnchorPart(asking, isDraining ? drain : null)}` +
    'Tell the user so in one short line in your reply, in their language, and go on with the task.' +
    (isDraining ? DRAIN_WARNING : '')
  )
}

const getDenyPart = item => `${LIMIT_WORDS[item.kind]} limit and ${WHY[item.why]}`

const isOneWhy = items => items.length > 1 && items.every(item => item.why === items[0].why)

const getDenyCause = items => {
  if (!isOneWhy(items)) return items.map(getDenyPart).join(', and to its ')

  return `${items.map(item => LIMIT_WORDS[item.kind]).join(' and ')} limits and ${WHY[items[0].why]}`
}

export const getLimitDenyText = items =>
  `Hats drain: this session's account is close to its ${getDenyCause(items)}, ` +
  'so new background work — subagents, workflows, monitors and background commands — is refused until the session is asked to anchor. ' +
  'Do this step in the foreground (a Bash call without run_in_background and with a timeout long enough for it, ' +
  'or the work yourself) or leave it for the next session, and tell the user in one line.'

export const getLimitRequestLine = items => {
  const named = items.map(item => `${LIMIT_WORDS[item.kind]} ${getWhole(item.percent)}%`).join(', ')

  return `hat limit: ${named} (anchor threshold ${items[0].save}%) — anchoring this session.`
}

const getSavedPart = (item, now) =>
  `at ${getWhole(item.episode.percent)}% of its ${LIMIT_WORDS[item.kind]} limit (threshold ${item.episode.save}%), ` +
  `which resets at ${getWhen(item.episode.lastResetsMs, now)}`

export const getLimitSavedLine = (items, now) =>
  `anchored: this session's account is ${items.map(item => getSavedPart(item, now)).join(', and ')}.`

const getEventRecord = event => (event === null ? null : { ...event })

const getEpisodeRecord = (episode, isOuter) => {
  if (episode === null) return null
  const record = {
    resets_at: getStamp(episode.resetsMs),
    percent: episode.percent,
    warn_percent: episode.warn,
    save_percent: episode.save,
    warned: getEventRecord(episode.warned),
    asked: getEventRecord(episode.asked),
    waiting: getEventRecord(episode.waiting ?? null),
    failed_asks: episode.failedAsks,
  }

  return isOuter ? { ...record, previous: getEpisodeRecord(episode.previous, false) } : record
}

export const getLimitsRecord = limits => ({
  five_hour: getEpisodeRecord(limits.five_hour, true),
  seven_day: getEpisodeRecord(limits.seven_day, true),
})

const isEventShape = value =>
  isObject(value) &&
  typeof value.at === 'string' &&
  EVENT_TIME.test(value.at) &&
  isLimitPercent(value.percent) &&
  typeof value.worn === 'string' &&
  Object.hasOwn(WHY, value.reason)

const isCount = value => Number.isInteger(value) && value >= 0

const PACE_FIELDS = {
  early: value => typeof value === 'boolean',
  target: isLimitThreshold,
  lead_seconds: value => value === null || isCount(value),
  minutes_to_save: isCount,
}

const getPaceFields = value => {
  const kept = Object.entries(PACE_FIELDS).filter(([name, isKept]) => Object.hasOwn(value, name) && isKept(value[name]))

  return Object.fromEntries(kept.map(([name]) => [name, value[name]]))
}

const findEvent = value =>
  isEventShape(value) ? { at: value.at, percent: value.percent, worn: value.worn, reason: value.reason, ...getPaceFields(value) } : null

const WAIT_ORIGINS = [
  'hat',
  'warned',
  'deferred',
]

const isEventTime = value => typeof value === 'string' && EVENT_TIME.test(value)

const isWaitingShape = value =>
  isEventTime(value.until) &&
  WAIT_ORIGINS.includes(value.origin) &&
  isDrainMinutes(value.drain_minutes) &&
  (value.cancelled_at === null || isEventTime(value.cancelled_at))

const findWaiting = value => {
  const event = findEvent(value)
  if (event === null || !isWaitingShape(value)) return null

  return {
    ...event,
    until: value.until,
    origin: value.origin,
    drain_minutes: value.drain_minutes,
    cancelled_at: value.cancelled_at,
  }
}

const isEpisodeShape = value =>
  isObject(value) &&
  getStampSeconds(value.resets_at) !== null &&
  isLimitPercent(value.percent) &&
  isLimitThreshold(value.warn_percent) &&
  isLimitThreshold(value.save_percent)

const findEpisode = (value, isOuter) => {
  if (!isEpisodeShape(value)) return null
  const resetsMs = getStampSeconds(value.resets_at) * 1000

  return {
    resetsMs,
    lastResetsMs: resetsMs,
    percent: value.percent,
    warn: value.warn_percent,
    save: value.save_percent,
    lead: null,
    warned: findEvent(value.warned),
    asked: findEvent(value.asked),
    waiting: findWaiting(value.waiting),
    failedAsks: Number.isInteger(value.failed_asks) && value.failed_asks > 0 ? value.failed_asks : 0,
    previous: isOuter ? findEpisode(value.previous, false) : null,
  }
}

export const findLimits = value => {
  const limits = createLimits()
  if (!isObject(value)) return limits
  for (const kind of LIMIT_KINDS) limits[kind] = findEpisode(value[kind], true)

  return limits
}
