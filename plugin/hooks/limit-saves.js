import {
  LIMIT_SAVE_PREFIX,
  getStamp,
  getStampSeconds,
} from './thresholds.js'
import {
  findSmallText,
  getStateRoot,
  isWritablePlace,
} from './files.js'
import { LIMIT_KINDS } from './limit-rules.js'

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value)

export const getLimitSaveName = (cell, kind) => `${LIMIT_SAVE_PREFIX}${cell.replace(/[^A-Za-z0-9-]/g, '-')}-${kind}.json`

const findData = text => {
  let data
  try {
    data = JSON.parse(text ?? '')
  } catch {
    return {}
  }

  return isObject(data) ? data : {}
}

const findResetsMs = (data, cell) => {
  const isWhole = data.cell === cell && getStampSeconds(data.saved_at) !== null
  const seconds = isWhole ? getStampSeconds(data.resets_at) : null

  return seconds === null ? null : seconds * 1000
}

async function findPlace($, cell, kind) {
  const root = await getStateRoot($)

  return root === null ? null : { folder: root, file: `${root}/${getLimitSaveName(cell, kind)}` }
}

export async function findLimitSaves($, cell) {
  const saves = { five_hour: null, seven_day: null }
  if (cell === null) return saves
  for (const kind of LIMIT_KINDS) {
    const place = await findPlace($, cell, kind)
    if (place !== null) saves[kind] = findResetsMs(findData(await findSmallText($, place.file)), cell)
  }

  return saves
}

async function writeLimitSave($, job) {
  const { cell, item, now } = job
  const place = await findPlace($, cell, item.kind)
  if (place === null || !(await isWritablePlace($, place))) return
  const held = findResetsMs(findData(await findSmallText($, place.file)), cell)
  if (held !== null && held > item.episode.resetsMs) return
  const record = { cell, resets_at: getStamp(item.episode.resetsMs), saved_at: getStamp(now) }
  await $.fs.write(place.file, `${JSON.stringify(record, null, 1)}\n`)
}

export async function queueLimitSaves($, job) {
  if (job.cell === null) return
  for (const item of job.items) await writeLimitSave($, { cell: job.cell, item, now: job.now }).catch(() => {})
}
