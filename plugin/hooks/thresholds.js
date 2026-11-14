export const DEFAULTS = {
  warn: 45,
  save: 55,
  after: 'offer_clear',
}
export const ACTIONS = [
  'tell',
  'offer_clear',
  'offer_exit',
]
export const FILE_LIMIT = 64 * 1024
export const THRESHOLDS_FILE = 'window-thresholds.json'
export const STAGE_FOLDER = 'session-thresholds'
export const HATS_FOLDER = 'Library/Application Support/Hats'
export const NOTES_FOLDER = 'Library/Application Support/Hats/notes'
export const STOPPED = 'the session was stopped and nobody has sent input since'
export const REASONS = {
  off: 'handoff is off',
  noMarker: 'no marker this turn',
  stale: 'stale marker',
  unreadable: 'unreadable marker',
  notRewritten: 'the note was not rewritten in this anchor',
  changed: 'the note changed after this session wrote it',
  hookFailed: 'a plugin hook failed',
  manual: 'manual',
  reloaded: 'plugin reloaded',
  sessionChanged: 'session changed',
  notStarted: 'the anchor command did not start a turn',
}
export const FAILED_TURN = {
  refusal: 'the anchor turn was refused',
  error: 'the anchor turn ended in an error',
}

const SESSION_ID = /^[0-9A-Za-z_-]{1,128}$/
const STAMP = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/
const NOW_HEADING = /^##\s+(?:СЕЙЧАС(?![\p{L}\p{N}_])|[Nn][Oo][Ww]\s*(?:$|[—–:(,]|-\s|\d))/u
const HANDOFF_COMMAND = /^sh "([^"]*)\/scripts\/py\.sh" "([^"]*)\/scripts\/handoff\.py" (new|save)(?:\s|$)/
const SERVICE_NAMES = [
  'resume-index.md',
  'memory.md',
]
const MARKER_TEXT_FIELDS = [
  'started',
  'cwd',
  'note',
  'topic',
  'saved_at',
]
const MARKER_NONEMPTY_FIELDS = [
  'started',
  'cwd',
  'note',
]

const PERCENT_RANGE = { low: 0, high: 100 }
const WARN_RANGE = { low: 10, high: 94 }
const SAVE_RANGE = { low: 11, high: 95 }
const ROUND_RANGE = { low: 0, high: Number.MAX_SAFE_INTEGER }

const isWholeIn = (value, range) => Number.isInteger(value) && value >= range.low && value <= range.high

const isThresholdShape = (value, range) => value === null || isWholeIn(value, range)

export const getPercent = usage => {
  const percent = usage?.context?.percent

  return isWholeIn(percent, PERCENT_RANGE) ? percent : null
}

export const findThresholds = text => {
  let data
  try {
    data = JSON.parse(text)
  } catch {
    return null
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return null
  const warn = data.warn_percent
  const save = data.save_percent
  if (!isThresholdShape(warn, WARN_RANGE) || !isThresholdShape(save, SAVE_RANGE)) return null
  if (warn !== null && save !== null && warn >= save) return null
  const after = ACTIONS.includes(data.after_save) ? data.after_save : 'tell'

  return { warn, save, after }
}

export const createArm = () => ({ seenBelowLowest: false, warn: false, save: false })

const getLowest = thresholds => {
  const enabled = [
    thresholds.warn,
    thresholds.save,
  ].filter(value => value !== null)

  return enabled.length === 0 ? null : Math.min(...enabled)
}

export const setArm = (arm, reading) => {
  const { thresholds, percent } = reading
  const lowest = getLowest(thresholds)
  if (lowest === null) return
  if (percent < lowest) arm.seenBelowLowest = true
  if (!arm.seenBelowLowest) return
  if (thresholds.warn !== null && percent < thresholds.warn) arm.warn = true
  if (thresholds.save !== null && percent < thresholds.save) arm.save = true
}

export const isWarnDue = (arm, reading) =>
  reading.thresholds.warn !== null && arm.warn && reading.percent >= reading.thresholds.warn

export const isSaveDue = (arm, reading) =>
  reading.thresholds.save !== null && arm.save && reading.percent >= reading.thresholds.save

const getAnchorPart = ({ thresholds, percent }) => {
  if (thresholds.save === null) return ''
  if (percent >= thresholds.save) return 'It anchors itself at the end of this turn. '

  return `It anchors itself at the end of a turn once it reaches ${thresholds.save}%. `
}

export const getWarningText = reading =>
  `Hats context threshold: this session's context window is at ${reading.percent}% ` +
  `(warning threshold ${reading.thresholds.warn}%). ${getAnchorPart(reading)}` +
  'Tell the user so in one short line in your reply, in their language, and go on with the task.'

export const getRequestLine = (percent, save) => `context ${percent}% (anchor threshold ${save}%) — anchoring this session.`

export const getSavedLine = ({ percent, save, after }) => {
  const line = `anchored at ${percent}% of the context window (threshold ${save}%).`
  if (after === 'offer_clear') return `${line} Type /clear to go on from the note in an empty context: the plugin gives it back.`
  if (after === 'offer_exit') return `${line} Type /exit and start claude again in this folder: the new session lists this note.`

  return line
}

export const getFailedLine = reason => `the session was not anchored: ${reason}. Say "anchor" to try again.`

export const INTERRUPTED_LINE = 'anchoring was stopped; nothing else happens until you say "anchor".'

export const RELOADED_LINE = 'anchoring was not checked: the plugin reloaded. Say "anchor" to save again.'

export const isSessionId = id => typeof id === 'string' && SESSION_ID.test(id)

export const getStamp = ms => `${new Date(ms).toISOString().slice(0, 19)}Z`

export const getStampSeconds = text => {
  const parts = typeof text === 'string' ? STAMP.exec(text) : null
  if (parts === null) return null
  const [year, month, day, hour, minute, second] = parts.slice(1).map(Number)
  const ms = Date.UTC(
    year,
    month - 1,
    day,
    hour,
    minute,
    second,
  )

  return Number.isNaN(ms) || getStamp(ms) !== text ? null : ms / 1000
}

export const isMarkerFresh = (savedAt, askedAtMs) => {
  const seconds = getStampSeconds(savedAt)

  return seconds !== null && seconds >= Math.floor(askedAtMs / 1000)
}

const isUsableText = value => typeof value === 'string' && value !== '' && !value.includes('\0')

export const isMarkerShape = marker =>
  marker !== null &&
  typeof marker === 'object' &&
  !Array.isArray(marker) &&
  Number.isInteger(marker.pid) &&
  MARKER_TEXT_FIELDS.every(field => typeof marker[field] === 'string') &&
  MARKER_NONEMPTY_FIELDS.every(field => isUsableText(marker[field]))

export const hasNowHeading = text => text.split('\n').some(line => NOW_HEADING.test(line))

export const findHandoffCommand = command => {
  const parts = typeof command === 'string' ? HANDOFF_COMMAND.exec(command) : null
  if (parts === null || parts[1] !== parts[2]) return null

  return parts[3]
}

export const findSaveOutcome = stdout => {
  const lines = typeof stdout === 'string' ? stdout.split('\n') : []
  const markers = lines.filter(line => line.startsWith('marker: '))
  if (markers.length > 0) return { kind: 'marker', path: markers[markers.length - 1].slice('marker: '.length).trim() }
  if (lines.some(line => line.startsWith('handoff is off'))) return { kind: 'off' }

  return null
}

export const findNewNote = stdout => {
  const path = typeof stdout === 'string' ? stdout.trim() : ''
  if (path === '' || path.includes('\n') || !path.startsWith('/') || !path.endsWith('.md')) return null

  return path
}

const getParent = path => path.slice(0, path.lastIndexOf('/'))

const getName = path => path.slice(path.lastIndexOf('/') + 1)

const isMemoryNote = (folder, memoryRoot) =>
  memoryRoot !== null && getName(folder) === 'memory' && getParent(getParent(folder)) === memoryRoot

const isOwnNotesNote = (folder, notesRoot) =>
  notesRoot !== null && getParent(folder) === notesRoot && /^[0-9a-f]{16}$/.test(getName(folder))

export const isNoteCandidate = (realPath, roots) => {
  if (typeof realPath !== 'string' || !realPath.startsWith('/') || !realPath.endsWith('.md')) return false
  if (SERVICE_NAMES.includes(getName(realPath).toLowerCase())) return false
  const folder = getParent(realPath)

  return isMemoryNote(folder, roots.memoryRoot) || isOwnNotesNote(folder, roots.notesRoot)
}

const getSingleSlashed = path => path.replace(/\/{2,}/g, '/')

export const isMarkerPlace = (path, stateFolder) =>
  typeof path === 'string' &&
  path.startsWith('/') &&
  path.endsWith('.json') &&
  getParent(getSingleSlashed(path)) === getSingleSlashed(stateFolder)

export const getNormalPath = path => {
  const parts = []
  for (const part of path.split('/')) {
    if (part === '..') parts.pop()
    if (part !== '' && part !== '.' && part !== '..') parts.push(part)
  }

  return `/${parts.join('/')}`
}

export const isMemoryLinkNote = note => {
  const { lexical, real } = note
  const folder = getParent(lexical)
  if (!lexical.endsWith('.md') || !real.endsWith('.md') || getName(folder) !== 'memory') return false
  if (SERVICE_NAMES.includes(getName(lexical).toLowerCase()) || SERVICE_NAMES.includes(getName(real).toLowerCase())) return false

  return note.memoryRoot !== null && note.projectsReal === note.memoryRoot && note.folderReal === getParent(real)
}

export const getMemoryLinkPaths = lexical => {
  const folder = getParent(lexical)

  return { folder, projects: getParent(getParent(folder)) }
}

export const getTurnFailure = reason => FAILED_TURN[reason] ?? `the anchor turn ended: ${reason}`

export const getRefusedReason = message => `the anchor command was refused: ${message}`

export const findRefusalOutcome = (message, previous) => {
  if (!message.includes(STOPPED)) return { kind: 'failed', reason: getRefusedReason(message) }

  return { kind: 'stopped', fields: { ...previous }, isSaveArmed: true }
}

export const getSha256 = async text => {
  const bytes = new TextEncoder().encode(text)
  const digest = await crypto.subtle.digest('SHA-256', bytes)

  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('')
}

export const findNoteVerdict = note => {
  const isWritten = note.kind === 'file' && note.size > 0 && note.mtimeMs >= note.askedAtMs
  if (!isWritten || typeof note.text !== 'string' || !hasNowHeading(note.text)) return REASONS.notRewritten
  if (note.before === undefined || note.own === undefined) return REASONS.notRewritten
  if (note.sha !== note.own) return REASONS.changed
  if (note.before !== 'absent' && note.before === note.sha) return REASONS.notRewritten

  return null
}

export const createStageRecord = (state, now) => ({
  session: state.id,
  cwd: state.cwd,
  stage: state.stage,
  warn_round: state.warnRound,
  save_round: state.saveRound,
  percent: state.percent,
  warn_percent: state.thresholds.warn,
  save_percent: state.thresholds.save,
  after_save: state.thresholds.after,
  reason: state.reason,
  marker: state.marker,
  at: getStamp(now),
})

export const findRounds = (text, id) => {
  let data
  try {
    data = JSON.parse(text)
  } catch {
    return null
  }
  if (data === null || typeof data !== 'object' || data.session !== id) return null
  if (!isWholeIn(data.warn_round, ROUND_RANGE) || !isWholeIn(data.save_round, ROUND_RANGE)) return null

  return { warnRound: data.warn_round, saveRound: data.save_round, stage: data.stage }
}
