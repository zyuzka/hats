import {
  getLowest,
  isDrainOn,
  isSaveDue,
} from './thresholds.js'
import {
  findCurrentThresholds,
  queueStage,
  setStage,
  tellUser,
} from './files.js'
import { waitForSnapshot } from './clear-check.js'
import { getLastMainToolEnd } from './clear-chain.js'

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
const FREE = { isHeld: false, list: null }
const HELD = { isHeld: true, list: null }
const NO_SNAPSHOT = { kind: 'none' }

export const WAIT_CANCELLED = 'wait cancelled'

export const DENY_TEXT =
  "Hats drain: this session's context window is close to its anchor threshold, so new background work — " +
  'subagents, workflows, monitors and background commands — is refused until the session is asked to anchor. ' +
  'Do this step in the foreground (a Bash call without run_in_background and with a timeout long enough for it, ' +
  'or the work yourself) or leave it for the next session, and tell the user in one line.'

export const UNCHECKED_LINE = 'Hats drain: background work could not be checked.'

export const RELOADED_WAIT_LINE = 'anchoring waited for background work and the plugin reloaded; say "anchor" to save.'

const LIST_HEAD =
  'Hats drain: still running — they outlive /clear, and the next session is told when one ends ' +
  'but not what it was for, so list each in the note:'

export const getWaitLine = (count, minutes) =>
  `Hats drain: anchoring waits for ${count} background ${count === 1 ? 'job' : 'jobs'}, up to ${minutes} min.`

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

export const findListText = tasks => {
  if (tasks.length === 0) return null

  return [
    LIST_HEAD,
    ...tasks.map(getListLine),
  ].join('\n')
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

  return thresholds !== null && isDrainOn(thresholds) ? DENY_TEXT : null
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
  if (isBelow) state.drain = null
}

async function holdAnchor($, job) {
  const { state, reading, holders } = job
  if (isWaiting(state)) return
  const now = await $.clock.now()
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
  await queueStage($, state)
  tellUser($, getWaitLine(holders, round.minutes))
}

async function findFreshSnapshot($, job) {
  const { state, turn } = job
  if (turn === null) return NO_SNAPSHOT

  return waitForSnapshot($, { id: state.id, getAfter: () => Math.max(turn.startedAt, getLastMainToolEnd()) })
}

export async function findDrainChoice($, job) {
  const { state, reading } = job
  if (!isDrainOn(reading.thresholds)) return FREE
  const snapshot = await findFreshSnapshot($, job)
  if (state.request !== null || (await $.session.id()) !== state.id) return HELD
  if (snapshot.kind !== 'snapshot' || !snapshot.ok) {
    tellUser($, UNCHECKED_LINE)
    return FREE
  }
  const list = findListText(snapshot.tasks)
  const holders = getHolderCount(snapshot.tasks)
  if (holders === 0 || !job.canHold || isDeadlinePassed(state.drain, await $.clock.now())) return { isHeld: false, list }
  await holdAnchor($, { state, reading, holders })

  return HELD
}
