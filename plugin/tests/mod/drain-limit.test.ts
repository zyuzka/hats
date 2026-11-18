import { describe, expect, test } from 'claude-code/testing'
import {
  NEXT_SESSION,
  SESSION,
  NOTE_TEXT,
  START,
  STATE,
  STAGE_FILE,
  THRESHOLDS,
  createScene,
} from './world.ts'
import {
  createLimits,
  getLimitDenyText,
  setEpisode,
} from '../../hooks/limit-rules.js'
import {
  findDeadline,
  findDrainSetting,
  isLimitDrainCause,
  settleLimitWaits,
} from '../../hooks/limit-drain.js'
import { findListText, getWaitLine, getWakeLine } from '../../hooks/drain.js'
import { DRAIN_OFF_REASON, getReleaseText, getWindowReason } from '../../hooks/drain-release.js'
import { setAsked } from '../../hooks/limits.js'
import { STOPPED, createPrevious, findRefusalOutcome } from '../../hooks/thresholds.js'
import { hasLimitDrainCause } from '../../hooks/limit-drain.js'
import { setRefusedBack } from '../../hooks/requests.js'

const MINUTE = 60 * 1000
const HOUR = 60 * MINUTE
const HAT_USAGE = `${STATE}/hat-usage.json`
const FIVE_RESETS = '2026-11-14T15:00:00.000Z'
const WEEK_RESETS = '2026-11-18T09:00:00.000Z'
const WINDOW_FILE = { warn_percent: 60, save_percent: 70, after_save: 'tell', drain: true, drain_minutes: 10 }
const READ = { tool: 'Read', file_path: '/w/README.md' }
const AGENT = { tool: 'Agent', prompt: 'go', description: 'helper' }
const ECHO = { tool: 'Bash', command: 'echo hi' }
const CELL = 'Claude Code-credentials'
const NO_HAT = 'Hats has no other hat to switch to'
const TELL = 'Tell the user so in one short line in your reply, in their language, and go on with the task.'
const DRAIN_ON =
  ' Drain is on: do not start subagents, workflows, monitors or background commands; ' +
  'they are refused until the session is asked to anchor.'
const REFUSAL_TAIL =
  'so new background work — subagents, workflows, monitors and background commands — is refused until the session is asked to anchor. ' +
  'Do this step in the foreground (a Bash call without run_in_background and with a timeout long enough for it, ' +
  'or the work yourself) or leave it for the next session, and tell the user in one line.'
const FIVE_DENIAL = `Hats drain: this session's account is close to its 5-hour limit and ${NO_HAT}, ${REFUSAL_TAIL}`
const WEEK_DENIAL = `Hats drain: this session's account is close to its weekly limit and ${NO_HAT}, ${REFUSAL_TAIL}`
const HOLDERS = [
  { id: 'b1shell', type: 'shell', status: 'running', description: 'sleep 600' },
]
const REQUEST_81 = 'hat limit: 5-hour 81% (anchor threshold 80%) — anchoring this session.'

const getStampOf = (ms: number) => new Date(ms).toISOString()

const createHatUsage = (fields: Record<string, unknown> = {}) => ({
  worn: 'work',
  five_hour: null,
  weekly: null,
  measured_at: null,
  has_a_hat_to_switch_to: false,
  auto_switch_on: true,
  credential_service: CELL,
  switch_covers: { five_hour: false, seven_day: false },
  alive_at: new Date(START).toISOString(),
  written_at: '2026-11-14T12:00:00Z',
  ...fields,
})

type Files = { thresholds?: Record<string, unknown>; hat?: Record<string, unknown> }

const setHat = (scene: any, fields: Record<string, unknown> = {}) => {
  scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage({ alive_at: getStampOf(scene.world.clock.now()), ...fields })))
}

const setThresholds = (scene: any, fields: Record<string, unknown> = {}) => {
  scene.world.setFile(THRESHOLDS, JSON.stringify({ ...WINDOW_FILE, ...fields }))
}

const startScene = async ($: any, on: any, files: Files = {}, options: Record<string, unknown> = {}) => {
  const scene = createScene($, { on, ...options })
  setThresholds(scene, files.thresholds)
  scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage(files.hat)))
  await scene.start()

  return scene
}

const setLimits = (scene: any, limits: { five?: number; week?: number; fiveResets?: string; weekResets?: string }) => {
  const entries = []
  if (limits.five !== undefined) entries.push({ kind: 'five_hour', percentUsed: limits.five, resetsAt: limits.fiveResets ?? FIVE_RESETS })
  if (limits.week !== undefined) entries.push({ kind: 'seven_day', percentUsed: limits.week, resetsAt: limits.weekResets ?? WEEK_RESETS })
  scene.world.rateLimits = entries
}

const toolAt = async (scene: any, limits: Parameters<typeof setLimits>[1], input: any = READ, window = 10) => {
  setLimits(scene, limits)

  return scene.callTool(window, input)
}

const endTurnAt = async (scene: any, limits: Parameters<typeof setLimits>[1], job: { tasks?: unknown[]; crons?: number; window?: number; noSnapshot?: boolean } = {}) => {
  const window = job.window ?? 10
  const turnId = await scene.startTurn(window)
  setLimits(scene, limits)
  if (job.noSnapshot !== true) setSnapshot(scene, { tasks: job.tasks ?? HOLDERS, crons: job.crons ?? 0 })
  if (job.noSnapshot !== true) {
    await scene.endTurn(turnId, { percent: window })
    return
  }
  const held = await scene.holdTurnEnd(turnId, { percent: window })
  await scene.world.clock.advance(2100)
  await held.done
}

const setSnapshot = (scene: any, fields: Record<string, unknown>) => {
  const id = scene.world.sessionId
  const snapshot = { session: id, at_ms: scene.world.clock.now(), ok: true, tasks: [], crons: 0, ...fields }
  scene.world.setFile(`${STATE}/stop-snapshots/${id}.json`, JSON.stringify(snapshot))
}

const getLimitStage = (scene: any) => scene.world.getStage(STAGE_FILE)?.limits

const getWaiting = (scene: any, kind = 'five_hour') => getLimitStage(scene)?.[kind]?.waiting ?? null

const getContext = (out: any) => out.context ?? []

const getSaveSteps = (scene: any) => [
  () => scene.runSteps(),
  scene.createNote,
  () => scene.writeNote(NOTE_TEXT),
  scene.runSave,
  () => scene.runSteps(),
]

const warnFive = async (scene: any) => {
  await toolAt(scene, { five: 72 })

  return Date.parse(getLimitStage(scene).five_hour.warned.at)
}

describe('the drain refusal by a limit', () => {
  test('the warning delivered, the anchor ahead, under Hats and nowhere to go: a subagent is refused, an echo runs', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)

    const agent = await toolAt(scene, { five: 73 }, AGENT)
    const echo = await toolAt(scene, { five: 73 }, ECHO)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
    expect(echo.deny).toBe(undefined)
  })

  test('no warning yet: nothing is refused and the hat file is not read for an ordinary call', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)

    const agent = await toolAt(scene, { five: 50 }, AGENT)
    scene.world.readPaths.length = 0
    await toolAt(scene, { five: 50 }, ECHO)

    expect(agent.deny).toBe(undefined)
    expect(scene.world.readPaths).not.toContain(HAT_USAGE)
  })

  test('drain off: the warning has no drain words and nothing is refused', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { drain: false } })
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 72 })
    const agent = await toolAt(scene, { five: 73 }, AGENT)

    expect(getContext(out)[0].includes('Drain is on')).toBe(false)
    expect(agent.deny).toBe(undefined)
  })

  test('the warning with drain on carries the later turn and the drain phrase', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 72 })

    expect(getContext(out)).toEqual([
      "Hats limit threshold: this session's account is at 72% of its 5-hour limit (warning threshold 70%) " +
        `and ${NO_HAT}. This session anchors at the end of a turn once it reaches 80%, or, while its background work runs, ` +
        `at the end of a later turn within 10 min. ${TELL}${DRAIN_ON}`,
    ])
  })

  test('the limit anchor off: the warning has no drain words and nothing is refused', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_save_percent: null } })
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 72 })
    const agent = await toolAt(scene, { five: 73 }, AGENT)

    expect(getContext(out)[0].includes('Drain is on')).toBe(false)
    expect(agent.deny).toBe(undefined)
  })

  test('a reload keeps the cause: the warned event comes back from the stage file', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await scene.start()

    const agent = await toolAt(scene, { five: 73 }, AGENT)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('a raised warning threshold above the percent keeps the cause: the hat file is still read', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setThresholds(scene, { limit_warn_percent: 76 })

    const agent = await toolAt(scene, { five: 72 }, AGENT)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('not under Hats any more: the cell in the file is another one', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setHat(scene, { credential_service: 'Claude Code-credentials-0eaa50e6' })

    const agent = await toolAt(scene, { five: 73 }, AGENT)

    expect(agent.deny).toBe(undefined)
  })

  test('Hats would move the session again: the limit is covered and Hats is alive', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setHat(scene, { has_a_hat_to_switch_to: true, switch_covers: { five_hour: true, seven_day: true } })

    const agent = await toolAt(scene, { five: 73 }, AGENT)

    expect(agent.deny).toBe(undefined)
  })

  test('a new episode or a reset that has passed ends the cause', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)

    const later = await toolAt(scene, { five: 5, fiveResets: '2026-11-14T20:00:00.000Z' }, AGENT)
    const passed = await toolAt(scene, { five: 73, fiveResets: '2026-11-14T11:00:00.000Z' }, AGENT)

    expect(later.deny).toBe(undefined)
    expect(passed.deny).toBe(undefined)
  })

  test('two limits: the 5-hour asked, the weekly warned: the refusal names the weekly', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { drain: false } })
    await endTurnAt(scene, { five: 81 })
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    setThresholds(scene, { drain: true })
    await scene.startTurn(10)
    await toolAt(scene, { five: 82, week: 72 })

    const agent = await toolAt(scene, { five: 82, week: 73 }, AGENT)

    expect(agent).toEqual({ deny: WEEK_DENIAL })
  })

  test('the window off and no window reading: the limit refuses all the same', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { save_percent: null, warn_percent: null } })
    await scene.startTurn(undefined)
    await toolAt(scene, { five: 72 }, READ, undefined)

    const agent = await toolAt(scene, { five: 73 }, AGENT, undefined)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('the window and the limit both draining: one refusal, the text of the limit', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(61)
    await toolAt(scene, { five: 72 }, READ, 61)

    const agent = await toolAt(scene, { five: 73 }, AGENT, 61)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('the limit waits with no warning (warning off): a subagent is refused', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_warn_percent: null } })
    await endTurnAt(scene, { five: 81 })
    expect(getWaiting(scene)).toMatchObject({ origin: 'deferred' })

    await scene.startTurn(10)
    const agent = await toolAt(scene, { five: 81 }, AGENT)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('a session with another configuration home is not under Hats: no refusal, no wait', async ($, on) => {
    const scene = await startScene($, on, {}, { configDir: '/tmp/alt' })
    await scene.startTurn(10)
    await toolAt(scene, { five: 72 })
    const agent = await toolAt(scene, { five: 73 }, AGENT)
    await endTurnAt(scene, { five: 81 })

    expect(agent.deny).toBe(undefined)
    expect(scene.world.files.has(STAGE_FILE)).toBe(false)
  })
})

describe('the end of a turn with a limit to drain', () => {
  test('wait: the anchor of the limit waits up to 10 minutes from the own warning, with the line and the waiting event', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    const warnedAt = await warnFive(scene)

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([getWaitLine(1, 10)])
    expect(getWaiting(scene)).toMatchObject({
      percent: 81,
      worn: 'work',
      reason: 'no_hat',
      until: getStampOf(warnedAt + 10 * MINUTE),
      origin: 'warned',
      drain_minutes: 10,
      cancelled_at: null,
    })
    expect(scene.world.getStage().stage).toBe(null)
  })

  test('the deadline passed: one request and the list in the first result of the anchor turn', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 })
    await scene.world.clock.advance(10 * MINUTE)

    await endTurnAt(scene, { five: 81 })
    await scene.ownAnchor()
    scene.world.releaseRuns()
    await scene.world.clock.settle()
    await scene.startTurn(10)
    const out = await toolAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs).toEqual([getWaitLine(1, 10), REQUEST_81])
    expect(getContext(out).some((text: string) => text.includes('(id b1shell)'))).toBe(true)
  })

  test('no holders: the request at once', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)

    await endTurnAt(scene, { five: 81 }, { tasks: [] })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(getWaiting(scene)).toBe(null)
  })

  test('not checkable: no fresh snapshot, the request at once with the line of task 10', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)

    await endTurnAt(scene, { five: 81 }, { noSnapshot: true })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs[0]).toBe('background work could not be checked (drain).')
  })

  test('wake-ups and no holders: the request, and the list names the wake-ups', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 }, { tasks: [], crons: 1 })
    await scene.ownAnchor()
    scene.world.releaseRuns()
    await scene.world.clock.settle()
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(getContext(out)).toContain('Scheduled wake-ups: 1 — they are not listed here, and they stop the automatic clear.')
  })

  test('warned late: the own warning 10 minutes after the first on the hat, the deadline has passed: the request at once', async ($, on) => {
    const scene = await startScene($, on)
    await scene.world.clock.advance(10 * MINUTE)
    setHat(scene, { first_warned: { five_hour: { episode: '2026-11-14T15:00:00Z', at: getStampOf(START) }, seven_day: null } })
    await scene.startTurn(10)
    await warnFive(scene)

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(getWaiting(scene)).toBe(null)
  })

  test('Hats has not read it yet: from the own warning; once Hats writes an earlier one the next end of a turn asks', async ($, on) => {
    const scene = await startScene($, on)
    await scene.world.clock.advance(10 * MINUTE)
    setHat(scene)
    await scene.startTurn(10)
    const warnedAt = await warnFive(scene)
    await endTurnAt(scene, { five: 81 })
    expect(getWaiting(scene)).toMatchObject({ until: getStampOf(warnedAt + 10 * MINUTE), origin: 'warned' })
    setHat(scene, { first_warned: { five_hour: { episode: '2026-11-14T15:00:00Z', at: getStampOf(START) }, seven_day: null } })

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(getWaiting(scene)).toMatchObject({ until: getStampOf(START + 10 * MINUTE), origin: 'hat' })
  })

  test('Hats not running: the first warning it wrote still sets the deadline', async ($, on) => {
    const scene = await startScene($, on)
    await scene.world.clock.advance(2 * MINUTE)
    scene.world.setFile(
      HAT_USAGE,
      JSON.stringify(
        createHatUsage({
          alive_at: getStampOf(START - HOUR),
          first_warned: { five_hour: { episode: '2026-11-14T15:00:00Z', at: getStampOf(START) }, seven_day: null },
        }),
      ),
    )
    await scene.startTurn(10)
    await toolAt(scene, { five: 72 })

    await endTurnAt(scene, { five: 81 })

    expect(getWaiting(scene)).toMatchObject({ until: getStampOf(START + 10 * MINUTE), origin: 'hat', reason: 'hats_not_running' })
  })

  test('the first warning of another episode does not count: from the own warning', async ($, on) => {
    const scene = await startScene($, on, {
      hat: { first_warned: { five_hour: { episode: '2026-11-14T20:00:00Z', at: getStampOf(START - HOUR) }, seven_day: null } },
    })
    await scene.startTurn(10)
    const warnedAt = await warnFive(scene)

    await endTurnAt(scene, { five: 81 })

    expect(getWaiting(scene)).toMatchObject({ until: getStampOf(warnedAt + 10 * MINUTE), origin: 'warned' })
  })

  test('no warning: the deadline runs from this end of a turn', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_warn_percent: null } })
    const turnId = await scene.startTurn(10)
    setLimits(scene, { five: 81 })
    scene.setSnapshot({ tasks: HOLDERS })
    await scene.world.clock.advance(500)
    const endAt = scene.world.clock.now()
    await scene.endTurn(turnId, { percent: 10 })

    expect(Date.parse(getWaiting(scene).until) - Date.parse(getWaiting(scene).at)).toBe(10 * MINUTE)
    expect(Date.parse(getWaiting(scene).at)).toBeGreaterThanOrEqual(endAt)
    expect(getWaiting(scene).origin).toBe('deferred')
  })

  test('a warning after the wait began does not move the deadline away', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_warn_percent: null } })
    await endTurnAt(scene, { five: 81 })
    const until = getWaiting(scene).until
    setThresholds(scene, { limit_warn_percent: 70 })
    await scene.world.clock.advance(4 * MINUTE)
    await scene.startTurn(10)
    await toolAt(scene, { five: 81 })
    expect(getLimitStage(scene).five_hour.warned).not.toBe(null)

    await endTurnAt(scene, { five: 81 })

    expect(getWaiting(scene).until).toBe(until)
    expect(scene.world.runs).toEqual([])
  })

  test('the deadline had passed when the anchor came due: the request at once, no waiting event', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await scene.world.clock.advance(15 * MINUTE)
    setHat(scene)

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(getWaiting(scene)).toBe(null)
  })

  test('the hat changed: the wait is cancelled; by the new hat it starts again', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 })
    setHat(scene, { worn: 'personal' })

    await endTurnAt(scene, { five: 81 })

    const waiting = getWaiting(scene)
    expect(waiting.worn).toBe('personal')
    expect(waiting.origin).toBe('deferred')
    expect(scene.world.getStageWrites().some((write: any) => write.limits.five_hour?.waiting?.cancelled_at !== null && write.limits.five_hour?.waiting?.worn === 'work')).toBe(true)
  })

  test('a raised threshold still below the percent keeps the wait; above it cancels it', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 85 })
    const until = getWaiting(scene).until
    setThresholds(scene, { limit_save_percent: 82 })

    await endTurnAt(scene, { five: 85 })
    expect(getWaiting(scene)).toMatchObject({ until, cancelled_at: null })
    setThresholds(scene, { limit_save_percent: 90 })
    await endTurnAt(scene, { five: 85 })

    expect(getWaiting(scene).cancelled_at).not.toBe(null)
    expect(scene.world.runs).toEqual([])
  })

  test('a cancelled wait does not come back after a reload', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 85 })
    setThresholds(scene, { limit_save_percent: 90 })
    await endTurnAt(scene, { five: 85 })
    setThresholds(scene, { limit_save_percent: 80, limit_warn_percent: 70 })
    await scene.start()
    await scene.startTurn(10)

    const agent = await toolAt(scene, { five: 85 }, AGENT)

    expect(getWaiting(scene).cancelled_at).not.toBe(null)
    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('a reload while the limit waits: the wait goes on with the same deadline and asks after it', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 })
    const until = getWaiting(scene).until
    await scene.start()

    await endTurnAt(scene, { five: 81 })
    expect(scene.world.runs).toEqual([])
    expect(getWaiting(scene).until).toBe(until)
    await scene.world.clock.advance(10 * MINUTE)
    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
  })

  test('a reload while a deferred wait runs keeps its deadline: no new deferral', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_warn_percent: null } })
    await endTurnAt(scene, { five: 81 })
    const until = getWaiting(scene).until
    await scene.world.clock.advance(3 * MINUTE)
    await scene.start()

    await endTurnAt(scene, { five: 81 })

    expect(getWaiting(scene).until).toBe(until)
    expect(scene.world.runs).toEqual([])
  })

  test('the episode ended while waiting: the wait is cancelled without a request', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 })

    await endTurnAt(scene, { five: 3, fiveResets: '2026-11-14T20:00:00.000Z' })

    expect(scene.world.runs).toEqual([])
    expect(getLimitStage(scene).five_hour.previous.waiting.cancelled_at).not.toBe(null)
  })

  test('Hats would move it again while waiting: cancelled, no request', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 })
    setHat(scene, { has_a_hat_to_switch_to: true, switch_covers: { five_hour: true, seven_day: true } })

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual([])
    expect(getWaiting(scene).cancelled_at).not.toBe(null)
  })

  test('a verified manual anchor with two limits waiting counts both', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await toolAt(scene, { five: 72, week: 72 })
    await endTurnAt(scene, { five: 81, week: 81 })
    expect(getWaiting(scene, 'seven_day')).not.toBe(null)

    const turnId = await scene.startTurn(10)
    setLimits(scene, { five: 81, week: 81 })
    for (const step of getSaveSteps(scene)) await step()
    await scene.endTurn(turnId, { percent: 10 })
    await scene.startTurn(10)
    const agent = await toolAt(scene, { five: 81, week: 81 }, AGENT)

    expect(scene.world.runs).toEqual([])
    expect(getLimitStage(scene).five_hour.asked).not.toBe(null)
    expect(getLimitStage(scene).seven_day.asked).not.toBe(null)
    expect(agent.deny).toBe(undefined)
  })

  test('a new session after the joint request gets its own warning and its own deadline', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 }, { tasks: [] })
    expect(scene.world.runs).toEqual(['hats:anchor'])
    scene.world.sessionId = NEXT_SESSION
    await scene.world.clock.advance(2 * MINUTE)

    await scene.startTurn(10)
    const out = await toolAt(scene, { five: 81 })
    await endTurnAt(scene, { five: 81 })

    const stage = scene.world.getStage(`${STATE}/session-thresholds/${NEXT_SESSION}.json`)
    expect(getContext(out)[0].startsWith("Hats limit threshold: this session's account is at 81%")).toBe(true)
    expect(stage.limits.five_hour.waiting).toMatchObject({ origin: 'warned', until: getStampOf(Date.parse(stage.limits.five_hour.warned.at) + 10 * MINUTE) })
  })
})

describe('the window and the limits decided together', () => {
  const startBoth = async ($: any, on: any) => {
    const scene = await startScene($, on, { thresholds: { drain_minutes: 10 } })
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })

    return scene
  }

  test('the window deadline later: the limit deadline passes first and one request carries both', async ($, on) => {
    const scene = await startBoth($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await scene.world.clock.advance(5 * MINUTE)
    await endTurnAt(scene, { five: 81 }, { window: 71 })
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', save_round: 1 })
    expect(scene.world.logs).toEqual([getWaitLine(1, 5)])
    await scene.world.clock.advance(5 * MINUTE)

    await endTurnAt(scene, { five: 81 }, { window: 71 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs.slice(1)).toEqual([REQUEST_81, 'context 71% (anchor threshold 70%) — anchoring this session.'])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1 })
  })

  test('the limit deadline later: the window deadline passes first and one request carries both', async ($, on) => {
    const scene = await startBoth($, on)
    await endTurnAt(scene, {}, { window: 71 })
    await scene.world.clock.advance(5 * MINUTE)
    await scene.startTurn(71)
    await toolAt(scene, { five: 72 }, READ, 71)
    await endTurnAt(scene, { five: 81 }, { window: 71 })
    expect(scene.world.runs).toEqual([])
    await scene.world.clock.advance(5 * MINUTE)

    await endTurnAt(scene, { five: 81 }, { window: 71 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs).toEqual([getWaitLine(1, 10), REQUEST_81, 'context 71% (anchor threshold 70%) — anchoring this session.'])
  })

  test('neither has passed: a wait; the line names the nearest deadline and only when it changes', async ($, on) => {
    const scene = await startBoth($, on)
    await endTurnAt(scene, {}, { window: 71 })
    await scene.world.clock.advance(2 * MINUTE)
    await scene.startTurn(71)
    await toolAt(scene, { five: 72 }, READ, 71)

    await endTurnAt(scene, { five: 81 }, { window: 71 })
    await endTurnAt(scene, { five: 81 }, { window: 71 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([getWaitLine(1, 10)])
  })

  test('the limit episode ends while both wait: its deadline does not release the window, the line names what is left', async ($, on) => {
    const scene = await startBoth($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 }, { window: 71 })
    expect(scene.world.logs).toEqual([getWaitLine(1, 10)])
    await scene.world.clock.advance(MINUTE)

    await endTurnAt(scene, { five: 3, fiveResets: '2026-11-14T20:00:00.000Z' }, { window: 71 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([getWaitLine(1, 10), getWaitLine(1, 9)])
  })

  test('the window passes its threshold during the 9b pause while the limit waits: the limit keeps its own wait', async ($, on) => {
    const scene = createScene($, { on })
    setThresholds(scene, { warn_percent: null, save_percent: 55, after_save: 'clear', drain: false })
    scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage()))
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: [...getSaveSteps(scene), async () => scene.setSnapshot()] })
    expect(scene.world.runs).toEqual(['hats:anchor', 'clear'])
    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 52 })
    setThresholds(scene, { warn_percent: null, save_percent: 55, after_save: 'clear' })
    setHat(scene)
    await scene.startTurn(52)
    await toolAt(scene, { five: 72 }, READ, 52)

    await endTurnAt(scene, { five: 81 }, { window: 56 })

    expect(scene.world.runs).toEqual(['hats:anchor', 'clear'])
    const stage = scene.world.getStage(`${STATE}/session-thresholds/${NEXT_SESSION}.json`)
    expect(stage.limits.five_hour.waiting).toMatchObject({ origin: 'warned', cancelled_at: null })
  })
})

describe('the rules of the drain by a limit', () => {
  test('the drain fields: on only when true, minutes 1…60 or 10', () => {
    expect(findDrainSetting('{"drain":true,"drain_minutes":5}')).toEqual({ isOn: true, minutes: 5 })
    expect(findDrainSetting('{"drain":"true","drain_minutes":61}')).toEqual({ isOn: false, minutes: 10 })
    expect(findDrainSetting('x')).toEqual({ isOn: false, minutes: 10 })
  })

  test('the deadline: the earliest of the first on the hat (this episode), the own warning (this hat), the deferral', () => {
    const resetsMs = Date.parse(FIVE_RESETS)
    const warned = { at: getStampOf(START + 10 * MINUTE), worn: 'work' }
    const hat = { firstWarned: { five_hour: { episodeMs: resetsMs, atMs: START }, seven_day: null } }
    const job = { hat, episode: { resetsMs, warned }, worn: 'work', minutes: 10, deferredMs: START + 11 * MINUTE }

    expect(findDeadline('five_hour', job)).toEqual({ untilMs: START + 10 * MINUTE, origin: 'hat' })
    expect(findDeadline('five_hour', { ...job, hat: { firstWarned: { five_hour: { episodeMs: resetsMs + HOUR, atMs: START }, seven_day: null } } })).toEqual({
      untilMs: START + 20 * MINUTE,
      origin: 'warned',
    })
    expect(findDeadline('five_hour', { ...job, hat: null, worn: 'personal' })).toEqual({ untilMs: START + 21 * MINUTE, origin: 'deferred' })
  })

  test('the cause needs the anchor ahead and a warning or a live wait', () => {
    const base = { save: 80, asked: null, warned: null, waiting: null }

    expect(isLimitDrainCause({ ...base, warned: {} })).toBe(true)
    expect(isLimitDrainCause({ ...base, waiting: { cancelled_at: null } })).toBe(true)
    expect(isLimitDrainCause({ ...base, waiting: { cancelled_at: 'x' } })).toBe(false)
    expect(isLimitDrainCause({ ...base, warned: {}, asked: {} })).toBe(false)
    expect(isLimitDrainCause({ ...base, warned: {}, save: null })).toBe(false)
  })

  test('the refusal of two limits names both', () => {
    expect(getLimitDenyText([
      { kind: 'five_hour', why: 'no_hat' },
      { kind: 'seven_day', why: 'auto_switch_off' },
    ])).toBe(
      "Hats drain: this session's account is close to its 5-hour limit and Hats has no other hat to switch to, " +
        `and to its weekly limit and Hats does not change hats by itself (auto-switch is off), ${REFUSAL_TAIL}`,
    )
  })

  test('the refusal of two limits with one reason names the reason once', () => {
    expect(getLimitDenyText([
      { kind: 'five_hour', why: 'auto_switch_off' },
      { kind: 'seven_day', why: 'auto_switch_off' },
    ])).toBe(
      "Hats drain: this session's account is close to its 5-hour and weekly limits and " +
        `Hats does not change hats by itself (auto-switch is off), ${REFUSAL_TAIL}`,
    )
  })

  test('the list carries the wake-ups line, alone or after the jobs', () => {
    expect(getWakeLine(2)).toBe('Scheduled wake-ups: 2 — they are not listed here, and they stop the automatic clear.')
    expect(findListText([], 1)).toBe(getWakeLine(1))
    expect(findListText(HOLDERS, 0)?.endsWith('(id b1shell)')).toBe(true)
    expect(findListText([], 0)).toBe(null)
  })

  const createWaitingState = () => {
    const limits = createLimits()
    const thresholds = { warn: 70, save: 80, lead: 682 }
    const episode = setEpisode(limits, { kind: 'five_hour', reading: { percent: 81, resetsMs: Date.parse(FIVE_RESETS) }, thresholds })
    episode.waiting = {
      at: getStampOf(START),
      percent: 81,
      worn: 'work',
      reason: 'no_hat',
      until: getStampOf(START + 20 * MINUTE),
      origin: 'deferred',
      drain_minutes: 20,
      cancelled_at: null,
    }
    const items = [{ kind: 'five_hour', episode, worn: 'work', why: 'no_hat' }]
    const state: any = { limits, request: null, arm: {} }

    return { state, episode, items }
  }

  const createView = (firstAt: number) => ({
    hat: { worn: 'work', firstWarned: { five_hour: { episodeMs: Date.parse(FIVE_RESETS), atMs: firstAt }, seven_day: null } },
    thresholds: {},
    isUnder: true,
    all: [],
  })

  test('Esc after the deadline came nearer while the request was queued: the wait comes back with the nearer deadline', () => {
    const { state, episode, items } = createWaitingState()
    setAsked(items, START + MINUTE)
    state.request = { limits: items, isWindow: false }

    settleLimitWaits(state, { view: createView(START - 5 * MINUTE), now: START + 2 * MINUTE })
    setRefusedBack(state, { request: state.request, outcome: { kind: 'stopped', fields: {}, isSaveArmed: true } })

    expect(episode.asked).toBe(null)
    expect(episode.waiting).toMatchObject({ until: getStampOf(START + 15 * MINUTE), origin: 'hat', cancelled_at: null })
  })

  test('Esc after the episode changed: the wait of the old episode does not come back', () => {
    const { state, episode, items } = createWaitingState()
    setAsked(items, START + MINUTE)
    const request = { limits: items, isWindow: false }
    state.request = request
    setEpisode(state.limits, { kind: 'five_hour', reading: { percent: 2, resetsMs: Date.parse(FIVE_RESETS) + 5 * HOUR }, thresholds: { warn: 70, save: 80, lead: 682 } })

    setRefusedBack(state, { request, outcome: { kind: 'stopped', fields: {}, isSaveArmed: true } })

    expect(episode.asked).not.toBe(null)
    expect(state.limits.five_hour.waiting).toBe(null)
  })
})

const anchorAndList = async (scene: any) => {
  await scene.ownAnchor()
  scene.world.releaseRuns()
  await scene.world.clock.settle()
  await scene.startTurn(10)

  return toolAt(scene, { five: 81 })
}

const hasJob = (out: any) => getContext(out).some((text: string) => text.includes('(id b1shell)'))

describe('the gaps the matrix check of 11c found', () => {
  test('the window shrinks below its lowest threshold: the limit still refuses', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(61)
    await toolAt(scene, { five: 72 }, READ, 61)

    const agent = await toolAt(scene, { five: 73 }, AGENT, 30)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('both limit thresholds passed in one answer, the warning not delivered yet, the anchor put off: refused', async ($, on) => {
    const scene = await startScene($, on)
    await endTurnAt(scene, { five: 81 })
    expect(getLimitStage(scene).five_hour.warned).toBe(null)
    expect(getWaiting(scene)).toMatchObject({ origin: 'deferred', cancelled_at: null })

    await scene.startTurn(10)
    const agent = await toolAt(scene, { five: 81 }, AGENT)

    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('the cell in the hat file is null: no refusal by the limit', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setHat(scene, { credential_service: null })

    const agent = await toolAt(scene, { five: 73 }, AGENT)

    expect(agent.deny).toBe(undefined)
  })

  test('warned late, the deadline passed: the request at once lists the running work', async ($, on) => {
    const scene = await startScene($, on)
    await scene.world.clock.advance(10 * MINUTE)
    setHat(scene, { first_warned: { five_hour: { episode: '2026-11-14T15:00:00Z', at: getStampOf(START) }, seven_day: null } })
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 })

    const out = await anchorAndList(scene)

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(hasJob(out)).toBe(true)
  })

  test('Hats not running and no first warning in its file: from the own warning', async ($, on) => {
    const scene = await startScene($, on, { hat: { alive_at: getStampOf(START - HOUR) } })
    await scene.startTurn(10)
    const warnedAt = await warnFive(scene)

    await endTurnAt(scene, { five: 81 })

    expect(getWaiting(scene)).toMatchObject({ until: getStampOf(warnedAt + 10 * MINUTE), origin: 'warned', reason: 'hats_not_running' })
  })

  test('the window deadline later: the joint request lists the running work', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(10)
    await warnFive(scene)
    await scene.world.clock.advance(5 * MINUTE)
    await endTurnAt(scene, { five: 81 }, { window: 71 })
    await scene.world.clock.advance(5 * MINUTE)
    await endTurnAt(scene, { five: 81 }, { window: 71 })

    const out = await anchorAndList(scene)

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(hasJob(out)).toBe(true)
  })

  test('the limit deadline later: after the joint save, the limit line and then the action of the window', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await endTurnAt(scene, {}, { window: 71 })
    await scene.world.clock.advance(5 * MINUTE)
    await scene.startTurn(71)
    await toolAt(scene, { five: 72 }, READ, 71)
    await endTurnAt(scene, { five: 81 }, { window: 71 })
    await scene.world.clock.advance(5 * MINUTE)
    await endTurnAt(scene, { five: 81 }, { window: 71 })
    expect(scene.world.runs).toEqual(['hats:anchor'])

    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    const after = scene.world.logs.slice(3)
    expect(after.length).toBe(2)
    expect(after[0].startsWith("anchored: this session's account is at 81% of its 5-hour limit (threshold 80%)")).toBe(true)
    expect(after[1]).toBe('anchored at 71% of the context window (threshold 70%).')
  })

  test('the reset passes while both wait: the limit wait is cancelled, the window keeps waiting with the line of what is left', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { drain_minutes: 30 } })
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    const resets = getStampOf(START + 15 * MINUTE)
    await scene.startTurn(10)
    await toolAt(scene, { five: 72, fiveResets: resets })
    await endTurnAt(scene, { five: 81, fiveResets: resets }, { window: 71 })
    expect(getWaiting(scene)).toMatchObject({ cancelled_at: null })
    await scene.world.clock.advance(16 * MINUTE)
    setHat(scene)

    await endTurnAt(scene, { five: 81, fiveResets: resets }, { window: 71 })

    expect(scene.world.runs).toEqual([])
    expect(getWaiting(scene).cancelled_at).not.toBe(null)
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting' })
    expect(scene.world.logs).toEqual([getWaitLine(1, 30), getWaitLine(1, 14)])
  })

  test('no longer under Hats while both wait: the limit wait is cancelled, the window keeps waiting', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 }, { window: 71 })
    setHat(scene, { credential_service: null })

    await endTurnAt(scene, { five: 81 }, { window: 71 })

    expect(scene.world.runs).toEqual([])
    expect(getWaiting(scene).cancelled_at).not.toBe(null)
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting' })
  })

  test('two sessions under Hats in one process share the deadline of the first warning on the hat', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    const firstAt = await warnFive(scene)
    setHat(scene, { first_warned: { five_hour: { episode: '2026-11-14T15:00:00Z', at: getStampOf(firstAt) }, seven_day: null } })
    await scene.world.clock.advance(5 * MINUTE)
    scene.world.sessionId = NEXT_SESSION
    await scene.start()
    await scene.startTurn(10)
    await toolAt(scene, { five: 75 })
    await endTurnAt(scene, { five: 81 })
    scene.world.sessionId = SESSION
    await scene.start()

    await endTurnAt(scene, { five: 81 })

    const second = scene.world.getStage(`${STATE}/session-thresholds/${NEXT_SESSION}.json`).limits.five_hour
    expect(second.warned.at).not.toBe(getStampOf(firstAt))
    expect(second.waiting).toMatchObject({ until: getStampOf(firstAt + 10 * MINUTE), origin: 'hat' })
    expect(getWaiting(scene)).toMatchObject({ until: getStampOf(firstAt + 10 * MINUTE) })
  })

  test('a verified manual anchor, the limit passing its threshold during it: counted, no wait and no request', async ($, on) => {
    const scene = await startScene($, on)
    const turnId = await scene.startTurn(10)
    setLimits(scene, { five: 79 })
    for (const step of getSaveSteps(scene)) await step()
    setLimits(scene, { five: 81 })
    setSnapshot(scene, { tasks: HOLDERS })
    await scene.endTurn(turnId, { percent: 10 })

    expect(scene.world.runs).toEqual([])
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ percent: 81 })
    expect(getWaiting(scene)).toBe(null)
  })

  test('the wait line of a limit counts every holding job', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)

    await endTurnAt(scene, { five: 81 }, { tasks: [...HOLDERS, { id: 'b2agent', type: 'subagent', status: 'running', description: 'x' }] })

    expect(scene.world.logs).toEqual([getWaitLine(2, 10)])
  })
})

describe('Esc on a joint request, by the functions the refusal path calls', () => {
  const createJoint = () => {
    const limits = createLimits()
    const thresholds = { warn: 70, save: 80, lead: 682 }
    const five = setEpisode(limits, { kind: 'five_hour', reading: { percent: 81, resetsMs: Date.parse(FIVE_RESETS) }, thresholds })
    const week = setEpisode(limits, { kind: 'seven_day', reading: { percent: 82, resetsMs: Date.parse(WEEK_RESETS) }, thresholds })
    five.waiting = {
      at: getStampOf(START),
      percent: 81,
      worn: 'work',
      reason: 'no_hat',
      until: getStampOf(START + 10 * MINUTE),
      origin: 'warned',
      drain_minutes: 10,
      cancelled_at: null,
    }
    week.warned = { at: getStampOf(START), percent: 72, worn: 'work', reason: 'no_hat' }
    const round = { isWaiting: true, deadline: START + 8 * MINUTE, minutes: 10 }
    const state: any = {
      limits,
      request: null,
      arm: { seenBelowLowest: true, warn: false, save: true },
      stage: 'waiting',
      reason: null,
      marker: null,
      saveRound: 1,
      percent: 71,
      thresholds: { warn: 60, save: 70, after: 'tell', drain: true, drainMinutes: 10 },
      drainMinutes: 10,
      drain: round,
    }
    const items = [
      { kind: 'five_hour', episode: five, worn: 'work', why: 'no_hat' },
      { kind: 'seven_day', episode: week, worn: 'work', why: 'no_hat' },
    ]
    const request = { limits: items, isWindow: true, previous: createPrevious(state) }
    setAsked(items, START + 9 * MINUTE)
    Object.assign(state, { request, stage: 'requested', drain: null, arm: { ...state.arm, save: false } })

    return { state, request, five, week, round }
  }

  test('the window released the waiting 5-hour, the weekly in warned: both waits and the window round come back', () => {
    const { state, request, five, week, round } = createJoint()

    setRefusedBack(state, { request, outcome: findRefusalOutcome(`Error: ${STOPPED}`, request.previous) })

    expect(state).toMatchObject({ stage: 'waiting', saveRound: 1, drain: round, request: null })
    expect(state.arm.save).toBe(true)
    expect(five.asked).toBe(null)
    expect(five.waiting.cancelled_at).toBe(null)
    expect(week.asked).toBe(null)
    expect(hasLimitDrainCause(state)).toBe(true)
  })

  test('the episodes of both limits changed between the queue and the refusal: neither old asked comes back', () => {
    const { state, request, five, week } = createJoint()
    const thresholds = { warn: 70, save: 80, lead: 682 }
    setEpisode(state.limits, { kind: 'five_hour', reading: { percent: 2, resetsMs: Date.parse(FIVE_RESETS) + 5 * HOUR }, thresholds })
    setEpisode(state.limits, { kind: 'seven_day', reading: { percent: 2, resetsMs: Date.parse(WEEK_RESETS) + 7 * 24 * HOUR }, thresholds })

    setRefusedBack(state, { request, outcome: findRefusalOutcome(`Error: ${STOPPED}`, request.previous) })

    expect(five.asked).not.toBe(null)
    expect(week.asked).not.toBe(null)
    expect(hasLimitDrainCause(state)).toBe(false)
    expect(state.stage).toBe('waiting')
  })
})

const getReleased = (reason: string) => getReleaseText([reason])

const hasRelease = (out: any) => getContext(out).some((text: string) => text.startsWith('Hats drain: background work is allowed again'))

const COVERED = { has_a_hat_to_switch_to: true, switch_covers: { five_hour: true, seven_day: true } }

const warnWindow = async (scene: any, limits: Parameters<typeof setLimits>[1] = {}) => {
  const first = await scene.startTurn(10)
  await scene.endTurn(first, { percent: 10 })
  await scene.startTurn(61)

  return toolAt(scene, limits, READ, 61)
}

describe('the drain released', () => {
  test('the text says what is allowed again and why', () => {
    expect(getReleaseText([
      'Hats now changes hats on its 5-hour limit',
      'its context window fell below 60%',
    ])).toBe(
      'Hats drain: background work is allowed again — Hats now changes hats on its 5-hour limit, and its context window fell below 60%, ' +
        'so this session no longer anchors for it. Tell the user so in one short line in your reply, in their language.',
    )
  })

  test('the drain turned off does not say the anchor is gone: the thresholds still anchor', () => {
    expect(getReleaseText([DRAIN_OFF_REASON])).toBe(
      'Hats drain: background work is allowed again — the drain was turned off in Hats; the session still anchors at its thresholds. ' +
        'Tell the user so in one short line in your reply, in their language.',
    )
  })

  test('the limit wait cancelled because Hats changes hats again: the subagent runs and carries the release once', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 })
    setHat(scene, COVERED)
    await endTurnAt(scene, { five: 81 })
    expect(getWaiting(scene).cancelled_at).not.toBe(null)
    await scene.startTurn(10)

    const agent = await toolAt(scene, { five: 81 }, AGENT)
    const next = await toolAt(scene, { five: 81 }, READ)

    expect(agent.deny).toBe(undefined)
    expect(getContext(agent)).toEqual([getReleased('Hats now changes hats on its 5-hour limit')])
    expect(hasRelease(next)).toBe(false)
  })

  test('the refusal ended without a wait: the release comes with the next prompt, once', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setLimits(scene, { five: 73 })
    setHat(scene, COVERED)

    await scene.prompt('go on')
    await scene.prompt('and more')

    expect(scene.world.prompts[0].context).toEqual([getReleased('Hats now changes hats on its 5-hour limit')])
    expect(scene.world.prompts[1].context ?? []).toEqual([])
  })

  test('a dropped prompt keeps the release for the next one', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setLimits(scene, { five: 73 })
    setHat(scene, COVERED)
    scene.world.dropNextPrompt = 'no'

    await scene.prompt('go on')
    await scene.prompt('and more')

    expect(scene.world.prompts[1].context).toEqual([getReleased('Hats now changes hats on its 5-hour limit')])
  })

  test('the episode ended: the release names the reset', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)

    const out = await toolAt(scene, { five: 3, fiveResets: '2026-11-14T20:00:00.000Z' }, AGENT)

    expect(out.deny).toBe(undefined)
    expect(getContext(out)).toEqual([getReleased('its 5-hour limit reset')])
  })

  test('the anchor threshold of the limit turned off: the release names it', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setThresholds(scene, { limit_save_percent: null })

    const out = await toolAt(scene, { five: 73 }, AGENT)

    expect(getContext(out)).toEqual([getReleased('the anchor threshold of its 5-hour limit is off')])
  })

  test('told only by a refusal: the release comes all the same', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_warn_percent: null } })
    await endTurnAt(scene, { five: 81 })
    await scene.startTurn(10)
    expect(await toolAt(scene, { five: 81 }, AGENT)).toEqual({ deny: FIVE_DENIAL })
    setHat(scene, COVERED)
    await endTurnAt(scene, { five: 81 })
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 81 }, AGENT)

    expect(getContext(out)).toEqual([getReleased('Hats now changes hats on its 5-hour limit')])
  })

  test('drain off: no drain text, so no release', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { drain: false } })
    await scene.startTurn(10)
    await warnFive(scene)
    setHat(scene, COVERED)

    const out = await toolAt(scene, { five: 73 }, AGENT)

    expect(hasRelease(out)).toBe(false)
  })

  test('a wait that was never told: cancelled silently', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_warn_percent: null } })
    await endTurnAt(scene, { five: 81 })
    setHat(scene, COVERED)
    await endTurnAt(scene, { five: 81 })
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 81 }, AGENT)

    expect(getWaiting(scene).cancelled_at).not.toBe(null)
    expect(hasRelease(out)).toBe(false)
  })

  test('the refusal ended by the request to anchor: nothing new', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 }, { tasks: [] })
    expect(scene.world.runs).toEqual(['hats:anchor'])
    setHat(scene, COVERED)
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 81 }, AGENT)

    expect(hasRelease(out)).toBe(false)
  })

  test('the window fell below its lowest threshold: the release names it', async ($, on) => {
    const scene = await startScene($, on)
    const warned = await warnWindow(scene)
    expect(getContext(warned)[0].endsWith(DRAIN_ON)).toBe(true)

    const out = await toolAt(scene, {}, AGENT, 50)
    const next = await toolAt(scene, {}, READ, 50)

    expect(out.deny).toBe(undefined)
    expect(getContext(out)).toEqual([getReleased('its context window fell below 60%')])
    expect(hasRelease(next)).toBe(false)
  })

  test('the window fell below while the limit still refuses: no release, the refusal stays', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene, { five: 72 })

    const out = await toolAt(scene, { five: 73 }, READ, 50)
    const agent = await toolAt(scene, { five: 73 }, AGENT, 50)

    expect(hasRelease(out)).toBe(false)
    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('the window fell below and the limit released after: one release with both reasons', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene, { five: 72 })
    await toolAt(scene, { five: 73 }, READ, 50)
    setHat(scene, COVERED)

    const out = await toolAt(scene, { five: 73 }, AGENT, 50)

    expect(getContext(out)).toEqual([
      getReleaseText([
        'its context window fell below 60%',
        'Hats now changes hats on its 5-hour limit',
      ]),
    ])
  })

  test('a window drain told before an anchor does not count for the next round', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene)
    await endTurnAt(scene, {}, { tasks: [], window: 71 })
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    const quiet = await scene.startTurn(50)
    await scene.endTurn(quiet, { percent: 61 })
    await scene.startTurn(50)

    const out = await toolAt(scene, {}, READ, 50)

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(hasRelease(out)).toBe(false)
  })

  test('the window back above its lowest threshold but below the warning: refusals go on, no release', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene)

    const out = await toolAt(scene, {}, READ, 65)
    const agent = await toolAt(scene, {}, AGENT, 65)

    expect(hasRelease(out)).toBe(false)
    expect(agent.deny).not.toBe(undefined)
  })

  test('the reasons of the window, by their exact words', () => {
    expect(getWindowReason(60)).toBe('its context window fell below 60%')
    expect(getWindowReason(null)).toBe('the thresholds of its context window are off')
    expect(DRAIN_OFF_REASON).toBe('the drain was turned off in Hats')
  })

  test('the window fell below as the first limit warning with drain arrives: only the warning, the refusal stands', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene)

    const both = await toolAt(scene, { five: 72 }, READ, 50)
    const agent = await toolAt(scene, { five: 73 }, AGENT, 50)

    expect(getContext(both)).toHaveLength(1)
    expect(getContext(both)[0].endsWith(DRAIN_ON)).toBe(true)
    expect(agent).toEqual({ deny: FIVE_DENIAL })
  })

  test('the hat changed and the new one is moved by Hats: the release names the change of hat', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setHat(scene, { worn: 'personal', ...COVERED })

    const out = await toolAt(scene, { five: 73 }, AGENT)

    expect(getContext(out)).toEqual([getReleased('the hat changed')])
  })

  test('the session is no longer under Hats: the release says so', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setHat(scene, { credential_service: 'Claude Code-credentials-0eaa50e6' })

    const out = await toolAt(scene, { five: 73 }, AGENT)

    expect(getContext(out)).toEqual([getReleased('this session is no longer under Hats')])
  })

  test('the hat file cannot be read: the told limit is kept and nothing is said until it is read', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    scene.world.files.delete(HAT_USAGE)

    const unread = await toolAt(scene, { five: 73 }, AGENT)
    setHat(scene, COVERED)
    const read = await toolAt(scene, { five: 73 }, READ)

    expect(hasRelease(unread)).toBe(false)
    expect(getContext(read)).toEqual([getReleased('Hats now changes hats on its 5-hour limit')])
  })

  test('the weekly limit released: the release names the weekly limit', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await toolAt(scene, { week: 72 })
    setHat(scene, COVERED)

    const out = await toolAt(scene, { week: 73 }, AGENT)

    expect(getContext(out)).toEqual([getReleased('Hats now changes hats on its weekly limit')])
  })

  test('the thresholds of the window turned off while its drain was told: the release names them', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene)
    setThresholds(scene, { warn_percent: null, save_percent: null })

    const out = await toolAt(scene, {}, AGENT, 61)

    expect(getContext(out)).toEqual([getReleased('the thresholds of its context window are off')])
  })

  test('the drain switch turned off while a limit refused: the release says so, once', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    setThresholds(scene, { drain: false })

    const out = await toolAt(scene, { five: 73 }, AGENT)
    const next = await toolAt(scene, { five: 73 }, READ)

    expect(getContext(out)).toEqual([getReleased(DRAIN_OFF_REASON)])
    expect(hasRelease(next)).toBe(false)
  })

  test('the drain switch turned off while the window refused: the release says so', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene)
    setThresholds(scene, { drain: false })

    const out = await toolAt(scene, {}, AGENT, 61)

    expect(getContext(out)).toEqual([getReleased(DRAIN_OFF_REASON)])
  })

  test('the drain switch turned off while the window refused: the next prompt carries the release', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene)
    setThresholds(scene, { drain: false })

    await scene.prompt('go on')

    expect(scene.world.prompts[0].context).toEqual([getReleased(DRAIN_OFF_REASON)])
  })

  test('a queued reason, then the request to anchor: no release after it', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene, { five: 72 })
    await toolAt(scene, { five: 73 }, READ, 50)
    await endTurnAt(scene, { five: 81 }, { tasks: [], window: 50 })
    expect(scene.world.runs).toEqual(['hats:anchor'])
    const outs: any[] = []
    await scene.runAnchorTurn({ steps: getSaveSteps(scene).map(step => async () => outs.push(await step())) })
    await scene.startTurn(50)

    const after = await toolAt(scene, { five: 81 }, AGENT, 50)

    expect(outs.some(hasRelease)).toBe(false)
    expect(hasRelease(after)).toBe(false)
  })

  test('the window told only by a refusal (warning off): the release comes once when it falls below', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { warn_percent: null } })
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await endTurnAt(scene, {}, { window: 71 })
    await scene.startTurn(71)
    expect((await toolAt(scene, {}, AGENT, 71)).deny).not.toBe(undefined)

    const out = await toolAt(scene, {}, READ, 50)
    const next = await toolAt(scene, {}, READ, 50)

    expect(getContext(out)).toEqual([getReleased('its context window fell below 70%')])
    expect(hasRelease(next)).toBe(false)
  })

  test('a queued reason, then a verified manual anchor: no release after it', async ($, on) => {
    const scene = await startScene($, on)
    await warnWindow(scene, { five: 72 })
    await toolAt(scene, { five: 73 }, READ, 50)
    const turnId = await scene.startTurn(50)
    setLimits(scene, { five: 79 })
    for (const step of getSaveSteps(scene)) await step()
    setLimits(scene, { five: 81 })
    setSnapshot(scene, { tasks: HOLDERS })
    await scene.endTurn(turnId, { percent: 50 })
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ percent: 81 })
    await scene.startTurn(50)

    const out = await toolAt(scene, { five: 81 }, AGENT, 50)

    expect(hasRelease(out)).toBe(false)
  })

  test('Esc in the anchor turn gives the refusal back: its later lift is told', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await warnFive(scene)
    await endTurnAt(scene, { five: 81 }, { tasks: [] })
    await scene.runAnchorTurn({ steps: [() => scene.runSteps()], reason: 'aborted' })
    expect(getLimitStage(scene).five_hour.asked).toBe(null)
    await scene.startTurn(10)
    expect(await toolAt(scene, { five: 81 }, AGENT)).toEqual({ deny: FIVE_DENIAL })
    setHat(scene, COVERED)

    const out = await toolAt(scene, { five: 81 }, AGENT)

    expect(getContext(out)).toEqual([getReleased('Hats now changes hats on its 5-hour limit')])
  })

  test('the window risen back to its lowest threshold before delivery: its queued reason is dropped', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { warn_percent: null } })
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await endTurnAt(scene, {}, { window: 71 })
    await scene.startTurn(71)
    expect((await toolAt(scene, {}, AGENT, 71)).deny).not.toBe(undefined)
    await toolAt(scene, { five: 72 }, READ, 71)
    expect(hasRelease(await toolAt(scene, { five: 73 }, READ, 50))).toBe(false)
    setHat(scene, COVERED)

    const out = await toolAt(scene, { five: 73 }, AGENT, 72)

    expect(getContext(out)).toEqual([getReleased('Hats now changes hats on its 5-hour limit')])
  })
})
