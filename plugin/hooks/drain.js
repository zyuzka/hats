import {
  getLowest,
  isDrainOn,
  isSaveDue,
} from './thresholds.js'
import {
  findCurrentThresholds,
  queueStage,
  setStage,
} from './files.js'
import { waitForSnapshot } from './clear-check.js'
import { getLastMainToolEnd } from './clear-chain.js'
import {
  noteDenialTold,
  noteWindowBelow,
} from './drain-release.js'

const DRAIN_TOOLS = [
  'Agent',
  'Task',
  'Workflow',
  'Monitor',
]
const SHELL_TOOLS = [
  'Bash',
  'PowerShell',
]
const HOLDING_TYPES = [
  'shell',
  'subagent',
  'workflow',
]
const DESCRIPTION_LIMIT = 120
const MINUTE_MS = 60 * 1000
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/gu
const NO_SNAPSHOT = { kind: 'none' }

export const WAIT_CANCELLED = 'wait cancelled'

export const DENY_TEXT =
  "Hats drain: this session's context window is close to its anchor threshold, so new background work — " +
  'subagents, workflows, monitors and background commands — is refused until the session is asked to anchor. ' +
  'Do this step in the foreground (a Bash call without run_in_background and with a timeout long enough for it, ' +
  'or the work yourself) or leave it for the next session, and tell the user in one line.'

export const UNCHECKED_LINE = 'background work could not be checked (drain).'

export const RELOADED_WAIT_LINE = 'anchoring waited for background work and the plugin reloaded; say "anchor" to save.'

const LIST_HEAD =
  'Hats drain: still running — they outlive /clear, and the next session is told when one ends ' +
  'but not what it was for, so list each in the note:'

export const getWaitLine = (count, minutes) =>
  `anchoring waits for ${count} background ${count === 1 ? 'job' : 'jobs'}, up to ${minutes} min (drain).`

const isBackgroundFlag = value =>
  value === true ||
  (typeof value === 'string' &&
    value.toLowerCase() === 'true')

export const isDrainCall = e =>
  DRAIN_TOOLS.includes(e.tool) ||
  (SHELL_TOOLS.includes(e.tool) &&
    isBackgroundFlag(e.run_in_background))

const createRound = () => ({ isWaiting: false, deadline: null, minutes: null })

export const isWaiting = state => state.drain !== null && state.drain.isWaiting

const isRequestAhead = state => state.drain !== null && state.arm.save

const isListDue = state =>
  state.request !== null &&
  state.request.list !== null &&
  state.turn !== null &&
  state.turn.id === state.request.turnId

export const getDrainList = state => (isListDue(state) ? state.request.list : null)

const isDeadlinePassed = (round, now) =>
  round !== null &&
  round.deadline !== null &&
  now > round.deadline

const getDescription = text => {
  const plain = Array.from(text.replace(CONTROL, ' ')).slice(0, DESCRIPTION_LIMIT).join('')

  return plain.trim() === '' ? '(no description)' : plain
}

const getListLine = (task, index) => `${index + 1}. ${task.type} "${getDescription(task.description)}" (id ${task.id})`

export const getWakeLine = count => `Scheduled wake-ups: ${count} — they are not listed here, and they stop the automatic clear.`

export const findListText = (tasks, crons = 0) => {
  const lines = [
    ...(tasks.length === 0 ? [] : [LIST_HEAD, ...tasks.map(getListLine)]),
    ...(crons > 0 ? [getWakeLine(crons)] : []),
  ]

  return lines.length === 0 ? null : lines.join('\n')
}

export const getHolderCount = tasks => tasks.filter(task => HOLDING_TYPES.includes(task.type)).length

export const setRoundStarted = state => {
  if (state.drain === null) state.drain = createRound()
}

export const setReading = (state, reading) => {
  state.percent = reading.percent
  state.thresholds = reading.thresholds
  state.drainMinutes = isDrainOn(reading.thresholds) ? (state.drain?.minutes ?? reading.thresholds.drainMinutes) : null
}

export const setPaused = state => {
  state.arm.save = false
  state.arm.warn = false
  state.pending = null
  state.drain = null
}

export async function findDenial($, state) {
  if (!isRequestAhead(state)) return null
  const thresholds = await findCurrentThresholds($)
  if (thresholds === null || !isDrainOn(thresholds)) return null
  noteDenialTold(state)

  return DENY_TEXT
}

async function cancelWait($, state) {
  state.drain.isWaiting = false
  state.drain.deadline = null
  state.drain.minutes = null
  setStage(state, { stage: 'warned', reason: WAIT_CANCELLED })
  await queueStage($, state)
}

export async function settleRound($, job) {
  const { state, reading } = job
  if (state.drain === null) return
  const lowest = getLowest(reading.thresholds)
  const isBelow = lowest === null || reading.percent < lowest
  const isStillDue = !isBelow && isSaveDue(state.arm, reading)
  if (state.drain.isWaiting && !isStillDue) await cancelWait($, state)
  if (!isBelow) return
  noteWindowBelow(state, lowest)
  state.drain = null
}

export function holdWindow(state, job) {
  const { reading, now } = job
  if (isWaiting(state)) return
  const round = state.drain ?? createRound()
  round.minutes = reading.thresholds.drainMinutes
  round.deadline = now + round.minutes * MINUTE_MS
  round.isWaiting = true
  state.drain = round
  state.arm.warn = false
  state.pending = null
  state.saveRound += 1
  setReading(state, reading)
  setStage(state, { stage: 'waiting' })
}

export async function findFreshSnapshot($, job) {
  const { state, turn } = job
  if (turn === null) return NO_SNAPSHOT

  return waitForSnapshot($, { id: state.id, getAfter: () => Math.max(turn.startedAt, getLastMainToolEnd()) })
}

export const isSnapshotGood = snapshot => snapshot.kind === 'snapshot' && snapshot.ok

export const findWaitLine = (state, job) => {
  const { deadlines, holders, now } = job
  if (deadlines.length === 0) return null
  const nearest = Math.min(...deadlines)
  if (nearest === state.nearestWait) return null
  state.nearestWait = nearest

  return getWaitLine(holders, Math.max(1, Math.ceil((nearest - now) / MINUTE_MS)))
}

export const getWindowDeadlines = state => (isWaiting(state) && state.drain.deadline !== null ? [state.drain.deadline] : [])

export const isRoundPassed = (state, now) => isDeadlinePassed(state.drain, now)
