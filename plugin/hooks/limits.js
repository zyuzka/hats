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
  if (!(await $.fs.exists(path).catch(() => true))) return { ...LIMIT_DEFAULTS }
  const text = await findSmallText($, path)

  return text === null ? null : findLimitThresholds(text)
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

async function findView($, state) {
  const usage = await $.session.usage().catch(() => null)
  const now = await $.clock.now()
  const root = await getStateRoot($)
  const thresholds = root === null ? null : await findThresholdsNow($, root)
  if (thresholds === null) return { now, items: [] }
  const episodes = setEpisodes(state, { readings: findLimitReadings(usage?.rateLimits, now), thresholds })
  const lowest = getLimitLowest(thresholds)
  if (lowest === null || !episodes.some(item => item.episode.percent >= lowest)) return { now, items: [] }
  const hat = await findHatUsageNow($, root)
  if (hat === null || !isUnderHats(hat, await findCell($))) return { now, items: [] }
  const items = episodes.map(item => ({ ...item, why: findWhy(hat, item.kind, now), worn: hat.worn }))

  return { now, items: items.filter(item => item.why !== null) }
}

export async function findLimitWarning($, state) {
  const view = await findView($, state)
  const items = view.items.filter(item => isLimitWarnDue(item.episode))

  return items.length === 0 ? null : { text: getLimitWarningText(items), items, now: view.now }
}

export async function findLimitAsks($, state) {
  const view = await findView($, state)

  return view.items.filter(item => isLimitAskDue(item.episode))
}

export const setAsked = (items, now) => {
  for (const item of items) {
    item.event = createEvent({ now, percent: item.episode.percent, worn: item.worn, reason: item.why })
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
    item.episode.warned = createEvent({ now: warning.now, percent: item.episode.percent, worn: item.worn, reason: item.why })
  }
  await queueStage($, state)
}
