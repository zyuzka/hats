export const DEFAULTS = {
  warn: 60,
  save: 70,
  after: 'offer_clear',
  drain: false,
  drainMinutes: 10,
}
export const ACTIONS = [
  'tell',
  'offer_clear',
  'offer_exit',
  'clear',
]
export const FILE_LIMIT = 64 * 1024
export const THRESHOLDS_FILE = 'window-thresholds.json'
export const STAGE_FOLDER = 'session-thresholds'
export const HATS_FOLDER = 'Library/Application Support/Hats'
export const NOTES_NAME = 'notes'
export const SNAPSHOT_FOLDER = 'stop-snapshots'
export const STOPPED = 'the session was stopped and nobody has sent input since'
export const REMOVED = 'the command was removed from the queue before it ran'
export const CLEAR_PAUSE_MS = 10 * 60 * 1000
export const SNAPSHOT_WAIT_MS = 2000
export const SNAPSHOT_STEP_MS = 100
export const HANDED_WAIT_MS = 5000
export const HANDED_STEP_MS = 200
export const KEPT = {
  hookFailed: 'a plugin hook failed',
  draft: 'a draft is in the prompt',
  unexpected: 'unexpected input from Claude Code',
  afterSteps: 'own after-steps ran',
  stepsUnread: 'own steps could not be read',
  noSnapshot: 'background work could not be checked',
  noteUnread: 'the note could not be read',
  noteChanged: 'the note changed after this session wrote it',
  noPlugin: 'the plugin files are not in place',
  handoffOff: 'HANDOFF_OFF=1 keeps the note from coming back after /clear',
  sessionChanged: 'the session changed',
  notCleared: 'the session did not change after /clear',
}
export const CONTINUE_DROPPED = 'hats: other input came after /clear, so the session does not go on by itself'
export const HOOK_FAILED_DROP = 'hats: a plugin hook failed, so the session does not go on by itself'
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
const STEPS_COMMAND = /^sh "([^"]*)\/scripts\/py\.sh" "([^"]*)\/scripts\/anchor-steps\.py"/
const STEPS_EXACT = /^sh "[^"]*\/scripts\/py\.sh" "[^"]*\/scripts\/anchor-steps\.py"\s*$/
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
const MINUTES_RANGE = { low: 1, high: 60 }
const ROUND_RANGE = { low: 0, high: Number.MAX_SAFE_INTEGER }

const isWholeIn = (value, range) => Number.isInteger(value) && value >= range.low && value <= range.high

const isThresholdShape = (value, range) => value === null || isWholeIn(value, range)

export const isDrainMinutes = value => isWholeIn(value, MINUTES_RANGE)

export const getDrainFields = data => ({
  drain: data.drain === true,
  drainMinutes: isDrainMinutes(data.drain_minutes) ? data.drain_minutes : DEFAULTS.drainMinutes,
})

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

  return { warn, save, after, ...getDrainFields(data) }
}

export const isDrainOn = thresholds => thresholds.drain === true && thresholds.save !== null

export const createArm = () => ({ seenBelowLowest: false, warn: false, save: false, failures: 0 })

export const getLowest = thresholds => {
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
  if (thresholds.save === null || percent >= thresholds.save) return
  arm.save = true
  arm.failures = 0
}

export const isWarnDue = (arm, reading) =>
  reading.thresholds.warn !== null && arm.warn && reading.percent >= reading.thresholds.warn

export const isSaveDue = (arm, reading) =>
  reading.thresholds.save !== null && arm.save && reading.percent >= reading.thresholds.save

const getDrainAnchorPart = ({ thresholds, percent }) => {
  const later = `, or, while its background work runs, at the end of a later turn within ${thresholds.drainMinutes} min. `
  if (percent >= thresholds.save) return `It anchors itself at the end of this turn${later}`

  return `It anchors itself once it reaches ${thresholds.save}%: at the end of that turn${later}`
}

const getAnchorPart = ({ thresholds, percent }) => {
  if (thresholds.save === null) return ''
  if (isDrainOn(thresholds)) return getDrainAnchorPart({ thresholds, percent })
  if (percent >= thresholds.save) return 'It anchors itself at the end of this turn. '

  return `It anchors itself at the end of a turn once it reaches ${thresholds.save}%. `
}

export const DRAIN_WARNING =
  ' Drain is on: do not start subagents, workflows, monitors or background commands; ' +
  'they are refused until the session is asked to anchor.'

export const getWarningText = reading =>
  `Hats context threshold: this session's context window is at ${reading.percent}% ` +
  `(warning threshold ${reading.thresholds.warn}%). ${getAnchorPart(reading)}` +
  'Tell the user so in one short line in your reply, in their language, and go on with the task.' +
  (isDrainOn(reading.thresholds) ? DRAIN_WARNING : '')

export const getRequestLine = (percent, save) => `context ${percent}% (anchor threshold ${save}%) — anchoring this session.`

export const getSavedLine = ({ percent, save, after }) => {
  const line = `anchored at ${percent}% of the context window (threshold ${save}%).`
  if (after === 'offer_clear') return `${line} Type /clear to go on from the note in an empty context: the plugin gives it back.`
  if (after === 'offer_exit') return `${line} Type /exit and start claude again in this folder: the new session lists this note.`

  return line
}

export const getFailedLine = reason => `the session was not anchored: ${reason}. Say "anchor" to try again.`

export const CANCELLED_LINE = 'anchoring was cancelled before it started; the context was not saved.'

export const STOPPED_SAVED_LINE = 'anchoring was stopped; the note was saved.'

export const STOPPED_UNCHECKED_LINE =
  'anchoring was stopped; whether the note was saved could not be checked. Say "anchor" to save.'

export const getStoppedFailedLine = reason => `anchoring was stopped; the note was not saved: ${reason}. Say "anchor" to save.`

export const RELOADED_LINE = 'anchoring was not checked: the plugin reloaded. Say "anchor" to save again.'

export const getClearingLine = percent => `anchored at ${percent}% — clearing the context; the session goes on from its note.`

export const getKeptLine = (percent, reason) =>
  `anchored at ${percent}%, not cleared: ${reason}. Type /clear when ready: the plugin gives the note back.`

export const getNotBackLine = path => `cleared, but the note did not come back to this session; it is at ${path}.`

export const DRAFT_AFTER_LINE = 'cleared; the note is in context — send your message.'

export const getPauseLine = (percent, save) =>
  `context ${percent}% (anchor threshold ${save}%): not anchoring within 10 minutes of the last automatic clear. Say "anchor" to save.`

export const getContinueText = percent =>
  `Hats: this session reached ${percent}% of its context window, was anchored and cleared. ` +
  'Continue the task from the resume note the plugin gave you after /clear: read the whole note with the Read tool, ' +
  'tell the user in one short line, in their language, which note you picked up, then go on with its next step.'

export const UNEXPECTED_INPUT = 'unexpected'

export const isOwnOrigin = origin => origin?.kind === 'plugin' && origin?.name === 'hats'

export const getInputKind = origin => {
  if (origin === null || typeof origin !== 'object' || typeof origin.kind !== 'string') return UNEXPECTED_INPUT

  return isOwnOrigin(origin) ? null : origin.kind
}

export const getInputReason = kind => (kind === UNEXPECTED_INPUT ? KEPT.unexpected : `input arrived during anchoring (${kind})`)

export const getWakeReason = count => `scheduled wake-ups: ${count}`

export const getMissingReason = ids => `background work not in the note: ${ids.join(', ')}`

export const getClearRefusal = message => {
  if (message.includes(STOPPED)) return STOPPED
  if (message.includes(REMOVED)) return REMOVED

  return `the clear command was refused: ${message}`
}

export const isStepsCommand = command => {
  const parts = typeof command === 'string' ? STEPS_COMMAND.exec(command) : null

  return parts !== null && parts[1] === parts[2]
}

export const isExactStepsCommand = command => isStepsCommand(command) && STEPS_EXACT.test(command)

export const findStepsOutcome = stdout => {
  const lines = typeof stdout === 'string' ? stdout.split('\n').map(line => line.trimEnd()) : []
  if (lines.some(line => line.startsWith('anchor-steps:'))) return 'unread'
  if (lines.includes('after anchor:')) return 'after'
  if (lines.includes('after anchor: none') || lines.includes('no own steps')) return 'none'

  return 'unread'
}

export const findStepsReason = outcomes => {
  if (outcomes.includes('after')) return KEPT.afterSteps
  if (outcomes.length === 0 || outcomes.includes('unread')) return KEPT.stepsUnread

  return null
}

const isTaskShape = task => task !== null && typeof task === 'object' && typeof task.id === 'string'

const getTaskText = value => (typeof value === 'string' ? value : '')

const getTaskFields = task => ({
  id: task.id,
  type: getTaskText(task.type),
  status: getTaskText(task.status),
  description: getTaskText(task.description),
})

const isSnapshotShape = (data, id) =>
  data !== null &&
  typeof data === 'object' &&
  data.session === id &&
  Number.isInteger(data.at_ms) &&
  typeof data.ok === 'boolean' &&
  Array.isArray(data.tasks) &&
  data.tasks.every(isTaskShape) &&
  isWholeIn(data.crons, ROUND_RANGE)

export const findSnapshot = (text, id) => {
  let data
  try {
    data = JSON.parse(text)
  } catch {
    return { kind: 'bad' }
  }
  if (!isSnapshotShape(data, id)) return { kind: 'bad' }

  return {
    kind: 'snapshot',
    at: data.at_ms,
    ok: data.ok,
    ids: data.tasks.map(task => task.id),
    crons: data.crons,
    tasks: data.tasks.map(getTaskFields),
  }
}

const getEscaped = text => text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')

const isNamedIn = (text, id) => id !== '' && new RegExp(`(?<![\\p{L}\\p{N}_-])${getEscaped(id)}(?![\\p{L}\\p{N}_-])`, 'u').test(text)

export const findMissingIds = (text, ids) => ids.filter(id => !isNamedIn(text, id))

export const isBoxShape = box => box !== null && typeof box === 'object' && typeof box.text === 'string'

export const getHandedPath = markerPath => `${markerPath.slice(0, -'.json'.length)}.handed`

export const getHandedKey = marker => `${marker.saved_at}|${marker.note}`

export const isHandedTo = (text, handed) => {
  let data
  try {
    data = JSON.parse(text)
  } catch {
    return false
  }

  return data !== null && typeof data === 'object' && data.key === handed.key && data.session === handed.session
}

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

export const createPrevious = state => ({
  stage: state.stage,
  reason: state.reason,
  marker: state.marker,
  saveRound: state.saveRound,
  percent: state.percent,
  thresholds: state.thresholds,
  drainMinutes: state.drainMinutes,
  drain: state.drain,
})

export const findRefusalOutcome = (message, previous) => {
  if (!message.includes(STOPPED)) return { kind: 'failed', reason: getRefusedReason(message) }

  return { kind: 'stopped', fields: { ...previous }, isSaveArmed: true }
}

export const getSha256 = async text => {
  const bytes = new TextEncoder().encode(text)
  const digest = await crypto.subtle.digest('SHA-256', bytes)

  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('')
}

const findUnownedVerdict = note => {
  if (note.before === undefined || note.before === note.sha) return REASONS.notRewritten

  return typeof note.saved === 'string' && note.saved !== note.sha ? REASONS.changed : null
}

export const findNoteVerdict = note => {
  const isWritten = note.kind === 'file' && note.size > 0 && note.mtimeMs >= note.askedAtMs
  if (!isWritten || typeof note.text !== 'string' || !hasNowHeading(note.text)) return REASONS.notRewritten
  if (note.own === undefined) return findUnownedVerdict(note)
  if (note.before === undefined) return REASONS.notRewritten
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
  drain_minutes: state.drainMinutes ?? null,
  reason: state.reason,
  marker: state.marker,
  at: getStamp(now),
  limits: state.limits ?? { five_hour: null, seven_day: null },
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

  const percent = isWholeIn(data.percent, PERCENT_RANGE) ? data.percent : null

  return { warnRound: data.warn_round, saveRound: data.save_round, stage: data.stage, percent }
}
