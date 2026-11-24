import {
  LIMIT_SAVES_FILE,
  getStamp,
  getStampSeconds,
} from './thresholds.js'
import {
  findSmallText,
  getStateRoot,
  isWritablePlace,
} from './files.js'
import { LIMIT_KINDS } from './limit-rules.js'

let writes = Promise.resolve()

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value)

const findData = text => {
  let data
  try {
    data = JSON.parse(text ?? '')
  } catch {
    return {}
  }

  return isObject(data) ? data : {}
}

const findResetsMs = value => {
  const seconds = isObject(value) ? getStampSeconds(value.resets_at) : null

  return seconds === null ? null : seconds * 1000
}

async function findPlace($) {
  const root = await getStateRoot($)

  return root === null ? null : { folder: root, file: `${root}/${LIMIT_SAVES_FILE}` }
}

export async function findLimitSaves($, cell) {
  const saves = { five_hour: null, seven_day: null }
  const place = cell === null ? null : await findPlace($)
  if (place === null) return saves
  const data = findData(await findSmallText($, place.file))
  const own = isObject(data[cell]) ? data[cell] : {}
  for (const kind of LIMIT_KINDS) saves[kind] = findResetsMs(own[kind])

  return saves
}

async function writeLimitSaves($, job) {
  const { cell, items, now } = job
  const place = await findPlace($)
  if (place === null || !(await isWritablePlace($, place))) return
  const data = findData(await findSmallText($, place.file))
  const own = isObject(data[cell]) ? data[cell] : {}
  for (const item of items) own[item.kind] = { resets_at: getStamp(item.episode.resetsMs), saved_at: getStamp(now) }
  data[cell] = own
  await $.fs.write(place.file, `${JSON.stringify(data, null, 1)}\n`)
}

export function queueLimitSaves($, job) {
  if (job.cell === null || job.items.length === 0) return writes
  writes = writes.then(() => writeLimitSaves($, job)).catch(() => {})

  return writes
}
