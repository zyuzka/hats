import { EPISODE_MS, LIMIT_KINDS, findLimitReadings } from './limit-rules.js'
import { DEFAULTS, findThresholds, isDrainOn } from './thresholds.js'

export const SAVE_COST_SECONDS = 82
export const BASE_RISE = 5
export const BASE_AGE_MS = 60 * 1000
export const POINT_LIFE_MS = 60 * 60 * 1000

export const getLeadSeconds = thresholds => {
  const minutes = thresholds !== null && isDrainOn(thresholds) ? thresholds.drainMinutes : DEFAULTS.drainMinutes

  return minutes * 60 + SAVE_COST_SECONDS
}

export const findLeadSeconds = text => getLeadSeconds(findThresholds(text))

export const createPace = () => ({ five_hour: null, seven_day: null })

const isSameEpisode = (memory, resetsMs) => memory !== null && Math.abs(resetsMs - memory.resetsMs) < EPISODE_MS

export const setPoint = (pace, job) => {
  const { kind, reading, now } = job
  const whole = Math.floor(reading.percent)
  if (!isSameEpisode(pace[kind], reading.resetsMs)) pace[kind] = { resetsMs: reading.resetsMs, top: null, points: [] }
  const memory = pace[kind]
  memory.points = memory.points.filter(point => now - point.atMs <= POINT_LIFE_MS)
  if (memory.top !== null && whole === memory.top) return
  if (memory.top !== null && whole < memory.top) memory.points = []
  memory.top = whole
  memory.points.push({ whole, atMs: now })
}

export const setPoints = (pace, job) => {
  const readings = findLimitReadings(job.rateLimits, job.now)
  for (const kind of LIMIT_KINDS) {
    if (readings[kind] !== undefined) setPoint(pace, { kind, reading: readings[kind], now: job.now })
  }
}

const isBase = (point, job) => job.last.whole - point.whole >= BASE_RISE && job.now - point.atMs >= BASE_AGE_MS

export const findRate = (memory, now) => {
  if (memory === null) return null
  const points = memory.points.filter(point => now - point.atMs <= POINT_LIFE_MS)
  if (points.length === 0) return null
  const last = points[points.length - 1]
  const bases = points.filter(point => isBase(point, { last, now }))
  if (bases.length === 0) return null
  const base = bases[bases.length - 1]

  return (last.whole - base.whole) / ((now - base.atMs) / 1000)
}

const isForecastable = episode =>
  episode.warn !== null &&
  episode.save !== null &&
  episode.warned === null &&
  episode.percent < episode.warn &&
  Number.isFinite(episode.lead)

export const findEarly = (pace, job) => {
  const { kind, episode, now } = job
  if (!isForecastable(episode)) return null
  const rate = findRate(pace[kind], now)
  if (rate === null || rate <= 0) return null
  const seconds = (episode.save - episode.percent) / rate
  const minutes = Math.ceil(seconds / 60)
  if (seconds > episode.lead || minutes < 1) return null

  return { seconds, minutes, target: episode.save, lead: episode.lead }
}
