import {
  DEFAULTS,
  THRESHOLDS_FILE,
  findThresholds,
} from './thresholds.js'
import {
  HAT_USAGE_FILE,
  LIMIT_DEFAULTS,
  LIMIT_KINDS,
  createEvent,
  findHatUsage,
  findLimitReadings,
  findLimitThresholds,
  findWhy,
  getCredentialService,
  getLimitDenyText,
  getLimitLowest,
  getLimitTakenLine,
  getLimitWarningText,
  isLimitAskDue,
  isLimitWarnDue,
  isSameEpisode,
  isUnderHats,
  setEpisode,
} from './limit-rules.js'
import {
  findSmallText,
  getStateRoot,
  queueStage,
  tellUser,
} from './files.js'
import {
  DRAIN_OFF,
  findDrainSetting,
  hasLimitDrainCause,
  isLimitDrainCause,
} from './limit-drain.js'
import {
  createPace,
  findEarly,
  findLeadSeconds,
  getLeadSeconds,
  setPoints,
} from './pace.js'
import { noteLimitsTold } from './drain-release.js'
import {
  findLimitSaves,
  queueLimitSaves,
} from './limit-saves.js'

let cell = null

export const forgetCell = () => {
  cell = null
}

async function findCell($) {
  if (cell !== null) return cell
  cell = await getCredentialService({
    CLAUDE_CONFIG_DIR: await $.env.get('CLAUDE_CONFIG_DIR'),
    CLAUDE_SECURESTORAGE_CONFIG_DIR: await $.env.get('CLAUDE_SECURESTORAGE_CONFIG_DIR'),
    CLAUDE_CODE_CUSTOM_OAUTH_URL: await $.env.get('CLAUDE_CODE_CUSTOM_OAUTH_URL'),
  })

  return cell
}

async function findThresholdsNow($, root) {
  const path = `${root}/${THRESHOLDS_FILE}`
  if (!(await $.fs.exists(path).catch(() => true))) return { ...LIMIT_DEFAULTS, lead: getLeadSeconds(DRAIN_OFF), drain: DRAIN_OFF, after: DEFAULTS.after }
  const text = await findSmallText($, path)
  const thresholds = text === null ? null : findLimitThresholds(text)
  if (thresholds === null) return null

  return { ...thresholds, lead: findLeadSeconds(text), drain: findDrainSetting(text), after: findThresholds(text)?.after ?? null }
}

async function findHatUsageNow($, root) {
  const text = await findSmallText($, `${root}/${HAT_USAGE_FILE}`)

  return text === null ? null : findHatUsage(text)
}

function setEpisodes(state, job) {
  const { readings, thresholds } = job

  return LIMIT_KINDS.filter(kind => readings[kind] !== undefined).map(kind => ({
    kind,
    episode: setEpisode(state.limits, { kind, reading: readings[kind], thresholds }),
  }))
}

export const setPacePoints = (state, job) => {
  if (state.pace === undefined) state.pace = createPace()
  setPoints(state.pace, job)
}

export async function notePace($, state) {
  const usage = await $.session.usage().catch(() => null)
  setPacePoints(state, { rateLimits: usage?.rateLimits, now: await $.clock.now() })
}

const isWorthReading = (episodes, lowest) =>
  lowest !== null && episodes.some(item => item.episode.percent >= lowest || item.early !== null || isLimitDrainCause(item.episode))

const createView = (now, fields) => ({
  now,
  items: [],
  all: [],
  seen: [],
  hat: null,
  isUnder: null,
  thresholds: null,
  drain: DRAIN_OFF,
  ...fields,
})

export async function findLimitView($, state) {
  const usage = await $.session.usage().catch(() => null)
  const now = await $.clock.now()
  setPacePoints(state, { rateLimits: usage?.rateLimits, now })
  const root = await getStateRoot($)
  const thresholds = root === null ? null : await findThresholdsNow($, root)
  if (thresholds === null) return createView(now, {})
  const episodes = setEpisodes(state, { readings: findLimitReadings(usage?.rateLimits, now), thresholds }).map(item => ({
    ...item,
    early: findEarly(state.pace, { kind: item.kind, episode: item.episode, now }),
  }))
  const known = { thresholds, drain: thresholds.drain, seen: episodes.map(item => item.kind) }
  if (!isWorthReading(episodes, getLimitLowest(thresholds))) return createView(now, known)
  const hat = await findHatUsageNow($, root)
  if (hat === null || !isUnderHats(hat, await findCell($))) return createView(now, { ...known, hat, isUnder: false })
  const all = episodes.map(item => ({ ...item, why: findWhy(hat, item.kind, now), worn: hat.worn }))
  const view = createView(now, { ...known, hat, isUnder: true, all, items: all.filter(item => item.why !== null) })
  if (thresholds.after === 'clear') await takeEarlierSaves($, { state, view })

  return view
}

const isSavedBefore = (item, saves) => saves[item.kind] !== null && isLimitAskDue(item.episode) && isSameEpisode(item.episode, saves[item.kind])

async function takeEarlierSaves($, job) {
  const { state, view } = job
  const saves = await findLimitSaves($, await findCell($))
  const taken = view.items.filter(item => isSavedBefore(item, saves))
  if (taken.length === 0) return
  for (const item of taken) {
    const event = createEvent({
      now: view.now,
      percent: item.episode.percent,
      worn: item.worn,
      reason: item.why,
      target: item.episode.save,
      lead: item.episode.lead,
    })
    if (item.episode.warned === null) item.episode.warned = event
    item.episode.asked = event
  }
  await queueStage($, state)
  tellUser($, getLimitTakenLine(taken, view.now))
}

export async function noteLimitSaves($, job) {
  await queueLimitSaves($, { cell: await findCell($), items: job.items, now: job.now })
}

const isWarningDue = item => isLimitWarnDue(item.episode) || (item.early !== null && item.episode.warned === null)

const isAskAhead = item => item.episode.save !== null && item.episode.asked === null

const getLimitWarning = view => {
  const items = view.items.filter(isWarningDue)
  const drain = view.drain.isOn ? view.drain : null
  if (items.length === 0) return null

  return { text: getLimitWarningText(items, drain), items, told: drain === null ? [] : items.filter(isAskAhead), now: view.now }
}

export async function findLimitNews($, state) {
  const view = await findLimitView($, state)

  return { view, warning: getLimitWarning(view) }
}

export async function findLimitDenial($, state) {
  if (!hasLimitDrainCause(state)) return null
  const view = await findLimitView($, state)
  if (!view.drain.isOn) return null
  const items = view.items.filter(item => isLimitDrainCause(item.episode))
  if (items.length === 0) return null
  noteLimitsTold(state, items)

  return getLimitDenyText(items)
}

export async function findLimitAsks($, state) {
  const view = await findLimitView($, state)

  return view.items.filter(item => isLimitAskDue(item.episode))
}

export const setAsked = (items, now) => {
  for (const item of items) {
    item.event = createEvent({
      now,
      percent: item.episode.percent,
      worn: item.worn,
      reason: item.why,
      target: item.episode.save,
      lead: item.episode.lead,
    })
    item.episode.asked = item.event
  }
}

export const setAskFailed = items => {
  for (const item of items) {
    if (item.episode.asked !== item.event) continue
    if (item.episode.failedAsks === 0) item.episode.asked = null
    item.episode.failedAsks += 1
  }
}

export const setAskedBack = (items, limits) => {
  for (const item of items) {
    if (item.episode.asked === item.event && limits[item.kind] === item.episode) item.episode.asked = null
  }
}

export async function markWarned($, job) {
  const { state, warning } = job
  for (const item of warning.items) {
    if (item.episode.warned !== null) continue
    item.episode.warned = createEvent({
      now: warning.now,
      percent: item.episode.percent,
      worn: item.worn,
      reason: item.why,
      target: item.episode.save,
      lead: item.episode.lead,
      early: item.early,
    })
  }
  noteLimitsTold(state, warning.told)
  await queueStage($, state)
}
