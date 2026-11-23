import { isSaveDue } from './thresholds.js'
import {
  findCurrentThresholds,
  tellUser,
} from './files.js'
import { isDrainCall } from './drain.js'
import {
  TASK_NOTICE,
  isPausedAfterClear,
} from './clear-chain.js'

const RESTART_ONLY_TOOLS = [
  'CronCreate',
  'ScheduleWakeup',
]
const SAVED_STAGES = [
  'saved',
  'kept',
  'cleared',
]

export const RESTART_DENY_TEXT =
  "Hats restart: this session's context window is past its anchor threshold and the session is cleared after saving, " +
  'so new work that outlives this turn — subagents, workflows, monitors, background commands, cron jobs and ' +
  'wake-ups — is refused until the session is cleared. Do this step in the foreground or leave it for the next ' +
  "session, and tell the user in one line. If it is one of the user's own anchor steps, skip it and name it in the summary."

const getRestartHead = percent =>
  `Hats restart: this session's context window is at ${percent}% and the session is cleared after saving, ` +
  'so start no new work in it: only save, and leave new work to the next session. ' +
  'Subagents, workflows, monitors, background commands, cron jobs and wake-ups are refused until the session is cleared. '

export const getRestartText = (percent, isSaved) =>
  getRestartHead(percent) +
  (isSaved
    ? 'The note is saved: tell the user in one short line, in their language, to type /clear.'
    : 'The note is not saved yet: tell the user in one short line, in their language, to say "anchor".')

export const getRestartLine = percent => `context ${percent}% — this session restarts after saving; new work waits for the next session.`

export const isRestartCall = e => isDrainCall(e) || RESTART_ONLY_TOOLS.includes(e.tool)

export const isUserInput = e => e.origin?.kind !== TASK_NOTICE

export const isRestartDue = (state, job) => {
  const { thresholds, percent } = job
  if (state.saveReached !== true || thresholds === null || percent === null) return false

  return thresholds.after === 'clear' && thresholds.save !== null && percent >= thresholds.save
}

export const noteSaveReached = (state, job) => {
  const { reading, now } = job
  if (state.saveReached === true || !isSaveDue(state.arm, reading) || isPausedAfterClear(now, state.id)) return false
  state.saveReached = true

  return true
}

const isStoppedSaved = state => state.stage === 'interrupted' && state.stoppedSaveRound === state.saveRound

const isNoteSaved = state => SAVED_STAGES.includes(state.stage ?? state.loaded?.stage ?? null) || isStoppedSaved(state)

async function findLastReading($, state) {
  const thresholds = (await findCurrentThresholds($)) ?? state.seen?.thresholds ?? null

  return { thresholds, percent: state.seen?.percent ?? state.percent ?? state.loaded?.percent ?? null }
}

export const setLoaded = (state, saved) => {
  state.saveReached = saved.saveReached
  state.loaded = { stage: saved.stage, percent: saved.percent }
}

export async function findRestart($, job) {
  const { state, reading } = job
  if (reading !== null) state.seen = { thresholds: reading.thresholds, percent: reading.percent }
  if (state.saveReached !== true) {
    state.isRestartOn = false
    return null
  }
  const last = reading ?? (await findLastReading($, state))
  const isOn = isRestartDue(state, last)
  if (isOn && state.isRestartOn !== true) tellUser($, getRestartLine(last.percent))
  state.isRestartOn = isOn

  return isOn ? getRestartText(last.percent, isNoteSaved(state)) : null
}
