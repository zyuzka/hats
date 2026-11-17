import { THRESHOLDS_FILE } from './thresholds.js'
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
  getLimitLowest,
  getLimitWarningText,
  isLimitAskDue,
  isLimitWarnDue,
  isUnderHats,
  setEpisode,
} from './limit-rules.js'
import {
  findSmallText,
  getStateRoot,
  queueStage,
} from './files.js'
import {
  createPace,
  findEarly,
  findLeadSeconds,
  getLeadSeconds,
  setPoints,
} from './pace.js'

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
  if (!(await $.fs.exists(path).catch(() => true))) return { ...LIMIT_DEFAULTS, lead: getLeadSeconds(null) }
  const text = await findSmallText($, path)
  const thresholds = text === null ? null : findLimitThresholds(text)

  return thresholds === null ? null : { ...thresholds, lead: findLeadSeconds(text) }
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
  lowest !== null && episodes.some(item => item.episode.percent >= lowest || item.early !== null)

async function findView($, state) {
  const usage = await $.session.usage().catch(() => null)
  const now = await $.clock.now()
  setPacePoints(state, { rateLimits: usage?.rateLimits, now })
  const root = await getStateRoot($)
  const thresholds = root === null ? null : await findThresholdsNow($, root)
  if (thresholds === null) return { now, items: [] }
  const episodes = setEpisodes(state, { readings: findLimitReadings(usage?.rateLimits, now), thresholds }).map(item => ({
    ...item,
    early: findEarly(state.pace, { kind: item.kind, episode: item.episode, now }),
  }))
  if (!isWorthReading(episodes, getLimitLowest(thresholds))) return { now, items: [] }
  const hat = await findHatUsageNow($, root)
  if (hat === null || !isUnderHats(hat, await findCell($))) return { now, items: [] }
  const items = episodes.map(item => ({ ...item, why: findWhy(hat, item.kind, now), worn: hat.worn }))

  return { now, items: items.filter(item => item.why !== null) }
}

const isWarningDue = item => isLimitWarnDue(item.episode) || (item.early !== null && item.episode.warned === null)

export async function findLimitWarning($, state) {
  const view = await findView($, state)
  const items = view.items.filter(isWarningDue)

  return items.length === 0 ? null : { text: getLimitWarningText(items), items, now: view.now }
}

export async function findLimitAsks($, state) {
  const view = await findView($, state)

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

export const setAskedBack = items => {
  for (const item of items) if (item.episode.asked === item.event) item.episode.asked = null
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
  await queueStage($, state)
}
