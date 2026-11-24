import { describe, expect, test } from 'claude-code/testing'
import {
  NEXT_SESSION,
  NOTE_TEXT,
  OTHER_SESSION,
  SESSION,
  START,
  STATE,
  STAGES,
  STAGE_FILE,
  THRESHOLDS,
  createScene,
} from './world.ts'
import {
  ALIVE_MS,
  EPISODE_MS,
  LIMIT_DEFAULTS,
  createLimits,
  findHatUsage,
  findLimitReadings,
  findLimits,
  findLimitThresholds,
  findWhy,
  getLimitRequestLine,
  getLimitSavedLine,
  getLimitWarningText,
  getLimitsRecord,
  getWhen,
  setEpisode,
} from '../../hooks/limit-rules.js'
import { setAsked, setAskedBack } from '../../hooks/limits.js'
import {
  DEFAULTS,
  STOPPED,
  createArm,
  createPrevious,
  findRefusalOutcome,
} from '../../hooks/thresholds.js'
import { setRefusedBack } from '../../hooks/requests.js'

const HOUR = 60 * 60 * 1000
const MINUTE = 60 * 1000
const HAT_USAGE = `${STATE}/hat-usage.json`
const FIVE_RESETS = '2026-11-14T15:00:00.000Z'
const WEEK_RESETS = '2026-11-18T09:00:00.000Z'
const WINDOW_FILE = { warn_percent: 60, save_percent: 70, after_save: 'tell' }
const READ = { tool: 'Read', file_path: '/w/README.md' }
const CELL = 'Claude Code-credentials'
const NO_HAT = 'Hats has no other hat to switch to'
const TELL = 'Tell the user so in one short line in your reply, in their language, and go on with the task.'
const WARN_72 =
  "Hats limit threshold: this session's account is at 72% of its 5-hour limit (warning threshold 70%) " +
  `and ${NO_HAT}. This session anchors at the end of a turn once it reaches 80%. ${TELL}`
const WARN_81 =
  "Hats limit threshold: this session's account is at 81% of its 5-hour limit (warning threshold 70%) " +
  `and ${NO_HAT}. This session anchors at the end of this turn. ${TELL}`
const REQUEST_81 = 'hat limit: 5-hour 81% (anchor threshold 80%) — anchoring this session.'
const WINDOW_REQUEST_71 = 'context 71% (anchor threshold 70%) — anchoring this session.'
const WINDOW_SAVED_71 = 'anchored at 71% of the context window (threshold 70%).'
const ANCHOR_ONLY = [
  'hats:anchor',
]

const getLocalWhen = (iso: string, nowMs: number) => {
  const at = new Date(iso)
  const time = at.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
  const isToday = at.toDateString() === new Date(nowMs).toDateString()

  return isToday ? time : `${at.toLocaleDateString('en-US', { weekday: 'short' })} ${time}`
}

const getSavedLine = (percent: number, nowMs: number) =>
  `anchored: this session's account is at ${percent}% of its 5-hour limit (threshold 80%), ` +
  `which resets at ${getLocalWhen(FIVE_RESETS, nowMs)}.`

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

const useFiles = (scene: any, files: { thresholds?: Record<string, unknown>; hat?: Record<string, unknown> } = {}) => {
  scene.world.setFile(THRESHOLDS, JSON.stringify({ ...WINDOW_FILE, ...(files.thresholds ?? {}) }))
  scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage(files.hat)))
}

const setLimits = (scene: any, limits: { five?: number; week?: number; fiveResets?: string; weekResets?: string }) => {
  const entries = []
  if (limits.five !== undefined) entries.push({ kind: 'five_hour', percentUsed: limits.five, resetsAt: limits.fiveResets ?? FIVE_RESETS })
  if (limits.week !== undefined) entries.push({ kind: 'seven_day', percentUsed: limits.week, resetsAt: limits.weekResets ?? WEEK_RESETS })
  scene.world.rateLimits = entries
}

const getContext = (out: any) => out.context ?? []

const getLimitStage = (scene: any, path = STAGE_FILE) => scene.world.getStage(path)?.limits

const getSaveSteps = (scene: any) => [
  () => scene.runSteps(),
  scene.createNote,
  () => scene.writeNote(NOTE_TEXT),
  scene.runSave,
  () => scene.runSteps(),
]

const startScene = async ($: any, on: any, files: Parameters<typeof useFiles>[1] = {}) => {
  const scene = createScene($, { on })
  useFiles(scene, files)
  await scene.start()

  return scene
}

const endTurnAt = async (scene: any, limits: Parameters<typeof setLimits>[1], window = 10) => {
  const turnId = await scene.startTurn(window)
  setLimits(scene, limits)
  await scene.endTurn(turnId, { percent: window })
}

const askAt81 = async ($: any, on: any, files: Parameters<typeof useFiles>[1] = {}) => {
  const scene = await startScene($, on, files)
  await endTurnAt(scene, { five: 81 })

  return scene
}

const toolAt = async (scene: any, limits: Parameters<typeof setLimits>[1], window = 10) => {
  setLimits(scene, limits)

  return scene.callTool(window, READ)
}

describe('the limit warning', () => {
  test('below the warning threshold: nothing, and the hat file is not read', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 69, week: 20 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.readPaths).not.toContain(HAT_USAGE)
    expect(scene.world.files.has(STAGE_FILE)).toBe(false)
  })

  test('at 72 the result of a tool carries the text once, and the stage file the warned event', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)

    const first = await toolAt(scene, { five: 72 })
    const second = await toolAt(scene, { five: 73 })

    expect(getContext(first)).toEqual([
      WARN_72,
    ])
    expect(getContext(second)).toEqual([])
    expect(getLimitStage(scene).five_hour).toMatchObject({
      resets_at: '2026-11-14T15:00:00Z',
      warn_percent: 70,
      save_percent: 80,
      warned: { percent: 72, worn: 'work', reason: 'no_hat', at: expect.stringMatching(/^2026-11-14T12:00:\d{2}\.\d{3}Z$/) },
      asked: null,
      previous: null,
    })
    expect(scene.world.getStage().stage).toBe(null)
  })

  test('a user message carries the text when no tool ran', async ($, on) => {
    const scene = await startScene($, on)
    setLimits(scene, { five: 72 })

    await scene.prompt('go on')

    expect(scene.world.prompts.at(-1).context).toEqual([
      WARN_72,
    ])
    expect(getLimitStage(scene).five_hour.warned).toMatchObject({ percent: 72 })
  })

  test('a dropped user message leaves the text for the next one, with no event', async ($, on) => {
    const scene = await startScene($, on)
    setLimits(scene, { five: 72 })
    scene.world.dropNextPrompt = 'dropped for the test'

    await scene.prompt('go on')
    expect(scene.world.files.has(STAGE_FILE)).toBe(false)
    await scene.prompt('again')

    expect(scene.world.prompts.at(-1).context).toEqual([
      WARN_72,
    ])
  })

  test('a refused tool carries nothing and writes no event; the next result carries the text', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    scene.world.nextToolAnswer = { deny: 'refused for the test' }

    const refused = await toolAt(scene, { five: 72 })
    const stageBefore = scene.world.files.has(STAGE_FILE)
    const next = await toolAt(scene, { five: 72 })

    expect(getContext(refused)).toEqual([])
    expect(stageBefore).toBe(false)
    expect(getContext(next)).toEqual([
      WARN_72,
    ])
  })

  test('past 80 in the middle of a turn: the warning says it anchors at the end of this turn', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 81 })

    expect(getContext(out)).toEqual([
      WARN_81,
    ])
  })

  test('both limits: one warning names both, the limits first and the window after', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(61)

    const out = await toolAt(scene, { five: 81, week: 72 }, 61)

    const limitText =
      "Hats limit threshold: this session's account is at 81% of its 5-hour limit (warning threshold 70%) " +
      `and ${NO_HAT}; it is also at 72% of its weekly limit (warning threshold 70%) and ${NO_HAT}. ` +
      `This session anchors at the end of this turn. ${TELL}`
    expect(getContext(out)[0]).toBe(limitText)
    expect(getContext(out)[1]).toStartWith('Hats context threshold:')
    expect(getContext(out).length).toBe(2)
  })

  test('the hat changed before the text went out: no text, no event', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    scene.world.nextToolAnswer = { deny: 'refused for the test' }
    await toolAt(scene, { five: 72 })
    scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage({ has_a_hat_to_switch_to: true, switch_covers: { five_hour: true, seven_day: true } })))

    const out = await toolAt(scene, { five: 72 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.files.has(STAGE_FILE)).toBe(false)
  })

  test('a reading whose reset has passed does not count, and its text is gone', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 90, fiveResets: '2026-11-14T11:59:00.000Z' })

    expect(getContext(out)).toEqual([])
  })

  const whyCases = [
    {
      name: 'auto-switch is off',
      hat: { auto_switch_on: false, has_a_hat_to_switch_to: true },
      why: 'Hats does not change hats by itself (auto-switch is off)',
    },
    {
      name: 'the switch threshold of the limit is off',
      hat: { has_a_hat_to_switch_to: true, switch_covers: { five_hour: false, seven_day: true } },
      why: 'Hats does not switch hats on this limit',
    },
    {
      name: 'Hats is not running',
      hat: {
        has_a_hat_to_switch_to: true,
        switch_covers: { five_hour: true, seven_day: true },
        alive_at: new Date(START - 16 * MINUTE).toISOString(),
      },
      why: 'Hats is not running',
    },
  ]
  for (const item of whyCases) {
    test(`the warning says why when ${item.name}`, async ($, on) => {
      const scene = await startScene($, on, { hat: item.hat })
      await scene.startTurn(10)

      const out = await toolAt(scene, { five: 72 })

      expect(getContext(out)).toEqual([
        "Hats limit threshold: this session's account is at 72% of its 5-hour limit (warning threshold 70%) " +
          `and ${item.why}. This session anchors at the end of a turn once it reaches 80%. ${TELL}`,
      ])
    })
  }

  test('a warning after the request of the episode has no anchor part', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.startTurn(10)

    const out = await toolAt(scene, { five: 83 })

    expect(getContext(out)).toEqual([
      "Hats limit threshold: this session's account is at 83% of its 5-hour limit (warning threshold 70%) " +
        `and ${NO_HAT}. ${TELL}`,
    ])
  })

  test('an untold text whose reset has passed is dropped, with no event', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    scene.world.nextToolAnswer = { deny: 'refused for the test' }
    await toolAt(scene, { five: 72 })

    const out = await toolAt(scene, { five: 72, fiveResets: '2026-11-14T11:59:00.000Z' })

    expect(getContext(out)).toEqual([])
    expect(scene.world.files.has(STAGE_FILE)).toBe(false)
  })

  test('no readings or only a spend limit: nothing', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    scene.world.rateLimits = [
      { kind: 'spend_limit', percentUsed: 99, resetsAt: FIVE_RESETS },
      { kind: 'five_hour', percentUsed: 81 },
      { kind: 'seven_day', percentUsed: '90', resetsAt: WEEK_RESETS },
      { kind: 'five_hour', percentUsed: 101, resetsAt: FIVE_RESETS },
    ]

    const out = await scene.callTool(10, READ)

    expect(getContext(out)).toEqual([])
  })

  test('a subagent tool result carries nothing', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    setLimits(scene, { five: 72 })

    const out = await scene.callTool(10, { ...READ, agentId: 'a1' })

    expect(getContext(out)).toEqual([])
  })

  test('a session that is not interactive gets nothing', async ($, on) => {
    const scene = createScene($, { on })
    useFiles(scene)
    await scene.start(false)
    const turnId = await scene.startTurn(10)
    const out = await toolAt(scene, { five: 81 })
    await scene.endTurn(turnId, { percent: 10 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual([])
  })
})

describe('the limit request', () => {
  test('at the end of a turn past 80: the line, the command and the asked event', async ($, on) => {
    const scene = await askAt81($, on)

    expect(scene.world.logs).toEqual([
      REQUEST_81,
    ])
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ percent: 81, worn: 'work', reason: 'no_hat' })
    expect(scene.world.getStage()).toMatchObject({ stage: null, save_round: 0, warn_round: 0 })
  })

  test('saved: the line with the reset time, and the action of the window does not run', async ($, on) => {
    const scene = await askAt81($, on, { thresholds: { after_save: 'clear' } })

    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(scene.world.logs).toEqual([
      REQUEST_81,
      getSavedLine(81, scene.world.clock.now()),
    ])
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.getStage().stage).toBe(null)
  })

  test('not saved: the failed line, one more request at the next turn end, none after a second failure', async ($, on) => {
    const scene = await askAt81($, on)
    const notSaved = 'the session was not anchored: no marker this turn. Say "anchor" to try again.'

    await scene.runAnchorTurn({ steps: [] })
    expect(getLimitStage(scene).five_hour).toMatchObject({ asked: null, failed_asks: 1 })
    await endTurnAt(scene, { five: 82 })
    await scene.runAnchorTurn({ steps: [] })
    await endTurnAt(scene, { five: 83 })
    await endTurnAt(scene, { five: 84 })

    expect(scene.world.logs).toEqual([
      REQUEST_81,
      notSaved,
      'hat limit: 5-hour 82% (anchor threshold 80%) — anchoring this session.',
      notSaved,
    ])
    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    expect(getLimitStage(scene).five_hour).toMatchObject({ asked: { percent: 82 }, failed_asks: 2 })
    expect(scene.world.getStage().stage).toBe(null)
  })

  test('the second request that saves ends the episode: no third request', async ($, on) => {
    const scene = await askAt81($, on)

    await scene.runAnchorTurn({ steps: [] })
    await endTurnAt(scene, { five: 82 })
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    await endTurnAt(scene, { five: 83 })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    expect(scene.world.logs.at(-1)).toBe(getSavedLine(82, scene.world.clock.now()))
  })

  test('a reload between the two requests keeps the count: one repeat in all', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.runAnchorTurn({ steps: [] })
    await scene.start()

    await endTurnAt(scene, { five: 82 })
    await scene.runAnchorTurn({ steps: [] })
    await scene.start()
    await endTurnAt(scene, { five: 83 })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
  })

  test('Esc in the anchor turn without a save: the unchecked line, and it counts as the one failure of the episode', async ($, on) => {
    const scene = await askAt81($, on)

    await scene.runAnchorTurn({ steps: [], reason: 'aborted' })
    expect(scene.world.logs.at(-1)).toBe('anchoring was stopped; whether the note was saved could not be checked. Say "anchor" to save.')
    await endTurnAt(scene, { five: 82 })
    await scene.runAnchorTurn({ steps: [], reason: 'aborted' })
    await endTurnAt(scene, { five: 83 })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    expect(scene.world.getStage().stage).toBe(null)
  })

  test('Esc in the anchor turn after a checked save: the saved line, the save counts and nothing is asked again', async ($, on) => {
    const scene = await askAt81($, on)

    await scene.runAnchorTurn({ steps: getSaveSteps(scene), reason: 'aborted' })
    expect(scene.world.logs.slice(-2)).toEqual([
      getSavedLine(81, scene.world.clock.now()),
      'anchoring was stopped; the note was saved.',
    ])
    await endTurnAt(scene, { five: 82 })
    await endTurnAt(scene, { five: 83 })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ percent: 81 })
  })

  test('the same episode with the reset 2 minutes later: nothing again', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    await endTurnAt(scene, { five: 85, fiveResets: '2026-11-14T15:02:00.000Z' })
    await endTurnAt(scene, { five: 83, fiveResets: '2026-11-14T14:59:00.000Z' })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a reset an hour or more from the episode: the stages again, the old episode in previous', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    await endTurnAt(scene, { five: 81, fiveResets: '2026-11-14T15:59:59.000Z' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    await endTurnAt(scene, { five: 81, fiveResets: '2026-11-14T16:00:00.000Z' })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    const five = getLimitStage(scene).five_hour
    expect(five.resets_at).toBe('2026-11-14T16:00:00Z')
    expect(five.previous).toMatchObject({ resets_at: '2026-11-14T15:00:00Z', asked: { percent: 81 } })
    expect(five.previous.previous).toBeUndefined()
  })

  test('both limits at the end of a turn: one request with both, both asked', async ($, on) => {
    const scene = await startScene($, on)

    await endTurnAt(scene, { five: 81, week: 85 })
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(scene.world.logs[0]).toBe('hat limit: 5-hour 81%, weekly 85% (anchor threshold 80%) — anchoring this session.')
    expect(scene.world.logs[1]).toBe(
      "anchored: this session's account is at 81% of its 5-hour limit (threshold 80%), " +
        `which resets at ${getLocalWhen(FIVE_RESETS, scene.world.clock.now())}, ` +
        `and at 85% of its weekly limit (threshold 80%), which resets at ${getLocalWhen(WEEK_RESETS, scene.world.clock.now())}.`,
    )
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getLimitStage(scene).seven_day.asked).toMatchObject({ percent: 85 })
  })

  test('the window has no reading: the limit is judged all the same', async ($, on) => {
    const scene = await startScene($, on)
    const turnId = await scene.startTurn(undefined)
    setLimits(scene, { five: 81 })

    await scene.endTurn(turnId, { percent: undefined })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a new session in the same episode gets the warning and the request again', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    scene.world.sessionId = NEXT_SESSION

    const turnId = await scene.startTurn(10)
    const out = await toolAt(scene, { five: 82 })
    await scene.endTurn(turnId, { percent: 10 })

    expect(getContext(out)[0]).toStartWith("Hats limit threshold: this session's account is at 82%")
    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    expect(getLimitStage(scene, `${STAGES}/${NEXT_SESSION}.json`).five_hour.asked).toMatchObject({ percent: 82 })
  })

  test('a request already given is not taken back when the hat changes', async ($, on) => {
    const scene = await askAt81($, on)
    scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage({ switch_covers: { five_hour: true, seven_day: true } })))

    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(scene.world.logs.at(-1)).toBe(getSavedLine(81, scene.world.clock.now()))
  })
})

describe('a limit-only request that ends early', () => {
  test('a hook that fails at the end of the anchor turn: the failed line, the window stage stays null', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.ownAnchor()
    scene.world.releaseRuns()
    const turnId = await scene.startTurn(10)
    scene.world.sessionIdDenials = 1

    await scene.endTurn(turnId, { percent: 10 })

    expect(scene.world.logs).toEqual([
      REQUEST_81,
      'the session was not anchored: a plugin hook failed. Say "anchor" to try again.',
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: null, save_round: 0, reason: null })
    await endTurnAt(scene, { five: 82 })
    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
  })

  test('the own command that did not start a turn: one more request at the next turn end', async ($, on) => {
    const scene = await askAt81($, on)
    scene.world.dropNextPrompt = 'dropped for the test'

    await scene.ownAnchor()
    await scene.world.clock.settle()
    await endTurnAt(scene, { five: 82 })

    expect(scene.world.logs[1]).toBe('the session was not anchored: the anchor command did not start a turn. Say "anchor" to try again.')
    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
  })

  test('a session change before the anchor turn: no line, the window stage stays null', async ($, on) => {
    const scene = await askAt81($, on)

    await scene.end('resume')
    scene.world.sessionId = OTHER_SESSION
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(scene.world.logs).toEqual([
      REQUEST_81,
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: null, save_round: 0, reason: null })
  })

  test('at 100% it asks, asks once more after a failed anchor, and then stops', async ($, on) => {
    const scene = await startScene($, on)
    await endTurnAt(scene, { five: 100 })

    await scene.runAnchorTurn({ steps: [] })
    await endTurnAt(scene, { five: 100 })
    await scene.runAnchorTurn({ steps: [] })
    await endTurnAt(scene, { five: 100 })
    await endTurnAt(scene, { five: 100 })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    expect(scene.world.logs[0]).toBe('hat limit: 5-hour 100% (anchor threshold 80%) — anchoring this session.')
    expect(scene.world.logs.length).toBe(4)
  })
})

describe('the limit with the window', () => {
  test('the window at 71 and the limit at 81: one request, the limit line and then the window action', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })

    await endTurnAt(scene, { five: 81 }, 71)
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(scene.world.logs).toEqual([
      REQUEST_81,
      WINDOW_REQUEST_71,
      getSavedLine(81, scene.world.clock.now()),
      WINDOW_SAVED_71,
    ])
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', save_round: 1 })
  })

  test('only the limit: the arm and the save round of the window are untouched', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 59 })

    await endTurnAt(scene, { five: 81 }, 59)
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    expect(scene.world.getStage()).toMatchObject({ stage: null, save_round: 0 })
    await endTurnAt(scene, { five: 82 }, 71)

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    expect(scene.world.logs.at(-1)).toBe(WINDOW_REQUEST_71)
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1 })
  })

  test('the window passed its threshold in the limit anchor turn: counted for the window too', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 69 })
    await endTurnAt(scene, { five: 81 }, 69)

    await scene.runAnchorTurn({ steps: getSaveSteps(scene), endPercent: 71 })

    expect(scene.world.logs).toEqual([
      REQUEST_81,
      getSavedLine(81, scene.world.clock.now()),
      WINDOW_SAVED_71,
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', save_round: 1 })
  })

  test('Esc after a checked save while the window passed its threshold: counted for the window, interrupted, no request after', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 69 })
    await endTurnAt(scene, { five: 81 }, 69)

    await scene.runAnchorTurn({ steps: getSaveSteps(scene), endPercent: 71, reason: 'aborted' })
    await endTurnAt(scene, { five: 81 }, 72)

    expect(scene.world.logs).toEqual([
      REQUEST_81,
      getSavedLine(81, scene.world.clock.now()),
      'anchoring was stopped; the note was saved.',
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', save_round: 1 })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the limit passed 80 in the window anchor turn: counted, no limit request after', async ($, on) => {
    const scene = await startScene($, on)
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await endTurnAt(scene, { five: 79 }, 71)
    setLimits(scene, { five: 81 })

    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    await endTurnAt(scene, { five: 82 })

    expect(scene.world.logs).toEqual([
      WINDOW_REQUEST_71,
      getSavedLine(81, scene.world.clock.now()),
      'anchored at 71% of the context window (threshold 70%).',
    ])
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ percent: 81 })
  })

  test('a manual anchor at 82 counts as the request of the episode', async ($, on) => {
    const scene = await startScene($, on)
    setLimits(scene, { five: 82 })

    const turnId = await scene.startTurn(10)
    for (const step of getSaveSteps(scene)) await step()
    await scene.endTurn(turnId, { percent: 10 })

    expect(scene.world.runs).toEqual([])
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ percent: 82 })
    expect(scene.world.getStage().stage).toBe(null)
  })

  test('the window waits and the limit comes due with drain on: the limit waits too; one request once the window deadline passes', async ($, on) => {
    const holders = [
      { id: 'b1shell', type: 'shell', status: 'running', description: 'sleep 180' },
    ]
    const scene = await startScene($, on, { thresholds: { drain: true, drain_minutes: 5 } })
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    const waiting = await scene.startTurn(71)
    scene.setSnapshot({ tasks: holders })
    await scene.endTurn(waiting, { percent: 71 })
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', save_round: 1 })
    const next = await scene.startTurn(71)
    setLimits(scene, { five: 81 })
    scene.setSnapshot({ tasks: holders })
    await scene.endTurn(next, { percent: 71 })
    expect(scene.world.runs).toEqual([])
    expect(getLimitStage(scene).five_hour.waiting).toMatchObject({ origin: 'deferred', drain_minutes: 5, cancelled_at: null })
    await scene.world.clock.advance(5 * MINUTE)

    const late = await scene.startTurn(71)
    scene.setSnapshot({ tasks: holders })
    await scene.endTurn(late, { percent: 71 })
    await scene.ownAnchor()
    scene.world.releaseRuns()
    await scene.world.clock.settle()
    await scene.startTurn(71)
    const out = await scene.callTool(71, READ)

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1 })
    expect(getContext(out).some((text: string) => text.includes('(id b1shell)'))).toBe(true)
  })

  test('10 minutes after an own clear: the limit asks without the pause line, the window keeps its pause', async ($, on) => {
    const scene = createScene($, { on })
    useFiles(scene, { thresholds: { warn_percent: null, save_percent: 55, after_save: 'clear' } })
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: [...getSaveSteps(scene), async () => scene.setSnapshot()] })
    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'clear',
    ])
    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 52 })

    const high = await scene.startTurn(52)
    setLimits(scene, { five: 81 })
    await scene.endTurn(high, { percent: 56 })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'clear',
      'hats:anchor',
    ])
    expect(scene.world.logs.at(-1)).toBe(REQUEST_81)
    expect(scene.world.logs.filter((line: string) => line.includes('not anchoring within 10 minutes'))).toEqual([])
    expect(scene.world.getStage(`${STAGES}/${NEXT_SESSION}.json`).stage).not.toBe('requested')
  })

  test('the window shrinks: the limit events stay', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    await endTurnAt(scene, { five: 83 }, undefined)
    await endTurnAt(scene, { five: 84 }, 5)

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ percent: 81 })
  })
})

describe('when Hats would move the session itself', () => {
  test('Hats covers the limit and is alive: nothing', async ($, on) => {
    const scene = await askAt81($, on, {
      hat: { has_a_hat_to_switch_to: true, switch_covers: { five_hour: true, seven_day: true } },
    })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.files.has(STAGE_FILE)).toBe(false)
  })

  test('the switch threshold of the weekly limit is off: the weekly stages, with that reason', async ($, on) => {
    const scene = await startScene($, on, {
      hat: { has_a_hat_to_switch_to: true, switch_covers: { five_hour: true, seven_day: false } },
    })

    await endTurnAt(scene, { five: 90, week: 81 })

    expect(scene.world.logs).toEqual([
      'hat limit: weekly 81% (anchor threshold 80%) — anchoring this session.',
    ])
    expect(getLimitStage(scene).seven_day.asked).toMatchObject({ reason: 'switch_threshold_off' })
    expect(getLimitStage(scene).five_hour.asked).toBe(null)
  })

  test('Hats has not been alive for more than 15 minutes: the stages, as nowhere to go', async ($, on) => {
    const scene = await askAt81($, on, {
      hat: {
        has_a_hat_to_switch_to: true,
        switch_covers: { five_hour: true, seven_day: true },
        alive_at: new Date(START - 15 * MINUTE - 1000).toISOString(),
      },
    })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ reason: 'hats_not_running' })
  })

  test('auto-switch is off: the reason says so', async ($, on) => {
    const scene = await askAt81($, on, { hat: { auto_switch_on: false, has_a_hat_to_switch_to: true } })

    expect(getLimitStage(scene).five_hour.asked).toMatchObject({ reason: 'auto_switch_off' })
  })

  for (const service of ['Claude Code-credentials-78553e2b', null]) {
    test(`the cell in the file is ${service}: nothing`, async ($, on) => {
      const scene = await askAt81($, on, { hat: { credential_service: service } })

      expect(scene.world.runs).toEqual([])
    })
  }

  test('no hat worn: nothing', async ($, on) => {
    const scene = await askAt81($, on, { hat: { worn: null } })

    expect(scene.world.runs).toEqual([])
  })

  test('an empty secure storage variable with a configuration home: the cell without a hash', async ($, on) => {
    const scene = createScene($, { on, env: { CLAUDE_SECURESTORAGE_CONFIG_DIR: '', CLAUDE_CONFIG_DIR: '/tmp/alt' } })
    useFiles(scene)
    await scene.start()

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a configuration home alone: the cell with its hash does not match the plain one', async ($, on) => {
    const scene = createScene($, { on, env: { CLAUDE_CONFIG_DIR: '/tmp/alt' } })
    useFiles(scene)
    await scene.start()

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual([])
  })

  const broken = [
    { name: 'not JSON', text: 'not json' },
    { name: 'a switch cover not a boolean', text: JSON.stringify(createHatUsage({ switch_covers: { five_hour: 'no', seven_day: false } })) },
    { name: 'alive_at not a time', text: JSON.stringify(createHatUsage({ alive_at: 'yesterday' })) },
    { name: 'auto_switch_on a number', text: JSON.stringify(createHatUsage({ auto_switch_on: 1 })) },
    { name: 'worn a number', text: JSON.stringify(createHatUsage({ worn: 7 })) },
    { name: 'has_a_hat_to_switch_to null', text: JSON.stringify(createHatUsage({ has_a_hat_to_switch_to: null })) },
    { name: 'over 64 KB', text: `${JSON.stringify(createHatUsage())}${' '.repeat(64 * 1024)}` },
  ]
  for (const file of broken) {
    test(`a hat file ${file.name}: nothing`, async ($, on) => {
      const scene = createScene($, { on })
      useFiles(scene)
      scene.world.setFile(HAT_USAGE, file.text)
      await scene.start()

      await endTurnAt(scene, { five: 81 })

      expect(scene.world.runs).toEqual([])
    })
  }

  test('the hat file is a link: nothing', async ($, on) => {
    const scene = createScene($, { on })
    useFiles(scene)
    scene.world.setLink(HAT_USAGE, '/elsewhere/hat-usage.json')
    scene.world.setFile('/elsewhere/hat-usage.json', JSON.stringify(createHatUsage()))
    await scene.start()

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual([])
  })

  test('the hat file is a folder: nothing', async ($, on) => {
    const scene = createScene($, { on })
    useFiles(scene)
    scene.world.setFolder(HAT_USAGE)
    await scene.start()

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual([])
  })
})

describe('the limit thresholds', () => {
  test('the warning switched off: no warning, the request stays', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_warn_percent: null } })
    const turnId = await scene.startTurn(10)

    const out = await toolAt(scene, { five: 81 })
    await scene.endTurn(turnId, { percent: 10 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the anchor switched off: the warning has no anchor part, and no request', async ($, on) => {
    const scene = await startScene($, on, { thresholds: { limit_save_percent: null } })
    const turnId = await scene.startTurn(10)

    const out = await toolAt(scene, { five: 90 })
    await scene.endTurn(turnId, { percent: 10 })

    expect(getContext(out)).toEqual([
      "Hats limit threshold: this session's account is at 90% of its 5-hour limit (warning threshold 70%) " +
        `and ${NO_HAT}. ${TELL}`,
    ])
    expect(scene.world.runs).toEqual([])
  })

  const brokenPairs = [
    { limit_warn_percent: 9 },
    { limit_save_percent: 96 },
    { limit_warn_percent: 80 },
    { limit_warn_percent: 70.5 },
  ]
  for (const pair of brokenPairs) {
    test(`a broken pair ${JSON.stringify(pair)}: nothing by the limit, the window as before`, async ($, on) => {
      const scene = await startScene($, on, { thresholds: pair })
      const first = await scene.startTurn(10)
      await scene.endTurn(first, { percent: 10 })
      await scene.startTurn(61)

      const out = await toolAt(scene, { five: 90 }, 61)

      expect(getContext(out).length).toBe(1)
      expect(getContext(out)[0]).toStartWith('Hats context threshold:')
    })
  }

  test('a file without the limit fields: 70 and 80', () => {
    expect(findLimitThresholds(JSON.stringify(WINDOW_FILE))).toEqual({ warn: 70, save: 80 })
    expect(LIMIT_DEFAULTS).toEqual({ warn: 70, save: 80 })
  })

  test('the pair is read on its own rules', () => {
    const read = (fields: Record<string, unknown>) => findLimitThresholds(JSON.stringify({ ...WINDOW_FILE, ...fields }))

    expect(read({ limit_warn_percent: 10, limit_save_percent: 95 })).toEqual({ warn: 10, save: 95 })
    expect(read({ limit_warn_percent: null, limit_save_percent: null })).toEqual({ warn: null, save: null })
    expect(read({ limit_warn_percent: 95, limit_save_percent: null })).toEqual({ warn: 95, save: null })
    expect(read({ limit_warn_percent: 80, limit_save_percent: 80 })).toBe(null)
    expect(read({ limit_warn_percent: 9 })).toBe(null)
    expect(read({ limit_save_percent: 96 })).toBe(null)
    expect(read({ limit_save_percent: '80' })).toBe(null)
    expect(findLimitThresholds('[]')).toBe(null)
    expect(findLimitThresholds('{')).toBe(null)
  })
})

describe('the stage file and a reload', () => {
  test('the events survive a reload and are not repeated', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    await toolAt(scene, { five: 72 })
    await scene.start()
    const turnId = await scene.startTurn(10)
    const after = await toolAt(scene, { five: 74 })
    await scene.endTurn(turnId, { percent: 10 })

    expect(getContext(after)).toEqual([])
    expect(getLimitStage(scene).five_hour.warned).toMatchObject({ percent: 72 })
  })

  test('untold text after a reload comes back from the next reading', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)
    scene.world.nextToolAnswer = { deny: 'refused for the test' }
    await toolAt(scene, { five: 72 })

    await scene.start()
    const told = await toolAt(scene, { five: 73 })

    expect(getContext(told)[0]).toStartWith("Hats limit threshold: this session's account is at 73%")
  })

  test('a reload after the request: the asked event keeps the request from coming again', async ($, on) => {
    const scene = await askAt81($, on)
    await scene.start()

    await endTurnAt(scene, { five: 85 })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a session taken up again with its stage file: its events hold, no request again', async ($, on) => {
    const scene = await askAt81($, on)
    const record = scene.world.getStage()
    scene.world.setFile(`${STAGES}/${NEXT_SESSION}.json`, JSON.stringify({ ...record, session: NEXT_SESSION }))
    scene.world.sessionId = NEXT_SESSION

    await endTurnAt(scene, { five: 85 })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the record carries both limits, fractional percents and both episodes', () => {
    const limits = createLimits()
    const thresholds = { warn: 70, save: 80 }
    const first = setEpisode(limits, { kind: 'five_hour', reading: { percent: 72.5, resetsMs: Date.parse(FIVE_RESETS) }, thresholds })
    first.warned = { at: '2026-11-14T12:40:02.800Z', percent: 72.5, worn: 'work', reason: 'no_hat' }
    setEpisode(limits, { kind: 'five_hour', reading: { percent: 3, resetsMs: Date.parse(FIVE_RESETS) + 5 * HOUR }, thresholds })

    const record = getLimitsRecord(limits)
    const back = findLimits(JSON.parse(JSON.stringify(record)))

    expect(record).toEqual({
      five_hour: {
        resets_at: '2026-11-14T20:00:00Z',
        percent: 3,
        warn_percent: 70,
        save_percent: 80,
        warned: null,
        asked: null,
        waiting: null,
        failed_asks: 0,
        previous: {
          resets_at: '2026-11-14T15:00:00Z',
          percent: 72.5,
          warn_percent: 70,
          save_percent: 80,
          warned: { at: '2026-11-14T12:40:02.800Z', percent: 72.5, worn: 'work', reason: 'no_hat' },
          asked: null,
          waiting: null,
          failed_asks: 0,
        },
      },
      seven_day: null,
    })
    expect(getLimitsRecord(back)).toEqual(record)
  })

  test('a broken limits field reads as no episodes, a broken event as no event', () => {
    expect(findLimits('x')).toEqual(createLimits())
    expect(findLimits({ five_hour: { resets_at: 'soon', percent: 1, warn_percent: 70, save_percent: 80 } })).toEqual(createLimits())
    const episode = { resets_at: '2026-11-14T15:00:00Z', percent: 81, warn_percent: 70, save_percent: 80 }
    const read = findLimits({ five_hour: { ...episode, warned: { at: '2026-11-14T12:40:02Z', percent: 72, worn: 'f', reason: 'no_hat' } } })
    expect(read.five_hour?.warned).toBe(null)
  })

  test('a record of only limit events has no window stage', async ($, on) => {
    const scene = await startScene($, on)
    await scene.startTurn(10)

    await toolAt(scene, { five: 72 })

    expect(scene.world.getStage()).toMatchObject({ session: SESSION, stage: null, warn_round: 0, save_round: 0 })
  })
})

describe('the rules of the limits', () => {
  test('an episode is the first reset time; under an hour either way is the same episode', () => {
    const limits = createLimits()
    const thresholds = { warn: 70, save: 80 }
    const at = Date.parse(FIVE_RESETS)
    const first = setEpisode(limits, { kind: 'five_hour', reading: { percent: 81, resetsMs: at }, thresholds })

    expect(setEpisode(limits, { kind: 'five_hour', reading: { percent: 82, resetsMs: at + EPISODE_MS - 1 }, thresholds })).toBe(first)
    expect(setEpisode(limits, { kind: 'five_hour', reading: { percent: 83, resetsMs: at - EPISODE_MS + 1 }, thresholds })).toBe(first)
    expect(first.resetsMs).toBe(at)
    const next = setEpisode(limits, { kind: 'five_hour', reading: { percent: 1, resetsMs: at + EPISODE_MS }, thresholds })
    expect(next).not.toBe(first)
    expect(next.previous?.percent).toBe(83)
  })

  test('readings: only five_hour and seven_day, a percent 0 to 100 and a reset still ahead', () => {
    const now = START
    const readings = findLimitReadings(
      [
        { kind: 'five_hour', percentUsed: 81.5, resetsAt: FIVE_RESETS },
        { kind: 'seven_day', percentUsed: 7, resetsAt: new Date(now).toISOString() },
        { kind: 'spend_limit', percentUsed: 1, resetsAt: FIVE_RESETS },
      ],
      now,
    )

    expect(readings).toEqual({ five_hour: { percent: 81.5, resetsMs: Date.parse(FIVE_RESETS) } })
    expect(findLimitReadings(null, now)).toEqual({})
  })

  test('the reason: not alive first, then covered, auto-switch, no hat, the switch threshold', () => {
    const usage = findHatUsage(JSON.stringify(createHatUsage({ has_a_hat_to_switch_to: true })))
    const alive = Date.parse(createHatUsage().alive_at as string)

    expect(findWhy(usage, 'five_hour', alive + ALIVE_MS)).toBe('switch_threshold_off')
    expect(findWhy(usage, 'five_hour', alive + ALIVE_MS + 1)).toBe('hats_not_running')
    expect(findWhy({ ...usage, covers: { five_hour: true, seven_day: false } }, 'five_hour', alive)).toBe(null)
    expect(findWhy({ ...usage, isAutoSwitchOn: false, hasAHat: false }, 'five_hour', alive)).toBe('auto_switch_off')
    expect(findWhy({ ...usage, hasAHat: false }, 'five_hour', alive)).toBe('no_hat')
  })

  test('the time of the reset: today as hours, another day with its weekday', () => {
    const now = Date.parse('2026-11-14T12:00:00Z')
    const later = Date.parse('2026-11-14T12:30:00Z')
    const nextWeek = Date.parse('2026-11-20T12:00:00Z')

    expect(getWhen(later, now)).toBe(getLocalWhen('2026-11-14T12:30:00Z', now))
    expect(getWhen(nextWeek, now)).toBe(getLocalWhen('2026-11-20T12:00:00Z', now))
    expect(getWhen(nextWeek, now)).toMatch(/^[A-Z][a-z]{2} \d{2}:\d{2}$/)
  })

  test('the lines of the request and of the save, the percent floored', () => {
    const episode = { percent: 81.9, save: 80, lastResetsMs: Date.parse(FIVE_RESETS) }

    expect(getLimitRequestLine([{ kind: 'five_hour', percent: 81.9, save: 80 }])).toBe(REQUEST_81)
    expect(getLimitSavedLine([{ kind: 'five_hour', episode }], START)).toBe(getSavedLine(81, START))
    expect(getLimitWarningText([{ kind: 'five_hour', why: 'no_hat', episode: { percent: 72.9, warn: 70, save: 80, asked: null } }])).toBe(WARN_72)
  })

  test('a refusal "stopped" of a limit-only request gives the asked back and leaves the window alone', () => {
    const limits = createLimits()
    const episode = setEpisode(limits, { kind: 'five_hour', reading: { percent: 81, resetsMs: Date.parse(FIVE_RESETS) }, thresholds: { warn: 70, save: 80 } })
    const items = [{ kind: 'five_hour', episode, worn: 'work', why: 'no_hat' }]
    setAsked(items, START)
    const arm = { ...createArm(), seenBelowLowest: true, save: false }
    const state: any = { stage: 'warned', reason: null, marker: null, saveRound: 2, percent: 61, thresholds: DEFAULTS, arm, limits }
    const request = { isWindow: false, limits: items, previous: null }
    state.request = request

    setRefusedBack(state, { request, outcome: findRefusalOutcome(STOPPED, null) })

    expect(state.request).toBe(null)
    expect(state.limits.five_hour.asked).toBe(null)
    expect(state).toMatchObject({ stage: 'warned', saveRound: 2, percent: 61 })
    expect(state.arm.save).toBe(false)
  })

  test('a refusal "stopped" of a request with the window gives both causes back', () => {
    const limits = createLimits()
    const episode = setEpisode(limits, { kind: 'five_hour', reading: { percent: 81, resetsMs: Date.parse(FIVE_RESETS) }, thresholds: { warn: 70, save: 80 } })
    const items = [{ kind: 'five_hour', episode, worn: 'work', why: 'no_hat' }]
    const state: any = { stage: 'warned', reason: null, marker: null, saveRound: 0, percent: 61, thresholds: DEFAULTS, arm: createArm(), limits, drainMinutes: null, drain: null }
    const previous = createPrevious(state)
    setAsked(items, START)
    Object.assign(state, { stage: 'requested', saveRound: 1, percent: 71 })
    const request = { isWindow: true, limits: items, previous }
    state.request = request

    setRefusedBack(state, { request, outcome: findRefusalOutcome(`Error: ${STOPPED}`, previous) })

    expect(state.limits.five_hour.asked).toBe(null)
    expect(state).toMatchObject({ stage: 'warned', saveRound: 0, percent: 61, request: null })
    expect(state.arm.save).toBe(true)
  })

  test('Esc on the own command gives each limit its asked back; the window by its own previous', () => {
    const limits = createLimits()
    const episode = setEpisode(limits, { kind: 'five_hour', reading: { percent: 81, resetsMs: Date.parse(FIVE_RESETS) }, thresholds: { warn: 70, save: 80 } })
    const items = [{ kind: 'five_hour', episode, worn: 'work', why: 'no_hat' }]
    setAsked(items, START)
    expect(episode.asked).toMatchObject({ percent: 81, worn: 'work', reason: 'no_hat', at: '2026-11-14T12:00:00.000Z' })

    setAskedBack(items, limits)

    expect(episode.asked).toBe(null)
    expect(findRefusalOutcome(`Error: ${STOPPED}`, null)).toMatchObject({ kind: 'stopped', fields: {} })
  })
})

const getSavePath = (cell: string, kind: string) => `${STATE}/limit-save-${cell.replace(/[^A-Za-z0-9-]/g, '-')}-${kind}.json`
const FIVE_SAVE = getSavePath(CELL, 'five_hour')
const SEVEN_SAVE = getSavePath(CELL, 'seven_day')
const CLEAR = { thresholds: { after_save: 'clear' } }

const getTakenLine = (percent: number, nowMs: number) =>
  `hat limit: this session's account is at ${percent}% of its 5-hour limit (threshold 80%), ` +
  `which resets at ${getLocalWhen(FIVE_RESETS, nowMs)}, and ${NO_HAT}; ` +
  'a session before this one anchored in this window, so this one goes on without anchoring.'

const getLimitSaves = (scene: any) => JSON.parse(scene.world.files.get(FIVE_SAVE).text)

const saveAndMoveOn = async ($: any, on: any, files: Parameters<typeof useFiles>[1] = CLEAR) => {
  const scene = await askAt81($, on, files)
  await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
  scene.world.sessionId = NEXT_SESSION

  return scene
}

describe('a limit anchored before in the same window, with the clear action', () => {
  test('a checked save writes the episode to the shared file under the login cell', async ($, on) => {
    const scene = await askAt81($, on, CLEAR)

    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(getLimitSaves(scene)).toEqual({
      cell: CELL,
      resets_at: '2026-11-14T15:00:00Z',
      saved_at: expect.stringMatching(/^2026-11-14T12:\d{2}:\d{2}Z$/),
    })
  })

  test('a request without a save writes nothing to the shared file', async ($, on) => {
    const scene = await askAt81($, on, CLEAR)

    await scene.runAnchorTurn({ steps: [] })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.files.has(FIVE_SAVE)).toBe(false)
  })

  test('a checked save in a stopped anchor turn writes the episode too', async ($, on) => {
    const scene = await askAt81($, on, CLEAR)

    await scene.runAnchorTurn({ steps: getSaveSteps(scene), reason: 'aborted' })

    expect(getLimitSaves(scene).resets_at).toBe('2026-11-14T15:00:00Z')
  })

  test('a manual anchor past the threshold writes the episode too', async ($, on) => {
    const scene = await startScene($, on, CLEAR)
    setLimits(scene, { five: 82 })

    const turnId = await scene.startTurn(10)
    for (const step of getSaveSteps(scene)) await step()
    await scene.endTurn(turnId, { percent: 10 })

    expect(scene.world.runs).toEqual([])
    expect(getLimitSaves(scene).resets_at).toBe('2026-11-14T15:00:00Z')
  })

  test('a new session in the same episode: one line, no warning and no request', async ($, on) => {
    const scene = await saveAndMoveOn($, on)
    const before = scene.world.logs.length

    const turnId = await scene.startTurn(10)
    const out = await toolAt(scene, { five: 82 })
    await scene.endTurn(turnId, { percent: 10 })
    await endTurnAt(scene, { five: 83 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs.slice(before)).toEqual([
      getTakenLine(82, scene.world.clock.now()),
    ])
    expect(getLimitStage(scene, `${STAGES}/${NEXT_SESSION}.json`).five_hour.asked).toMatchObject({ percent: 82 })
  })

  test('a new session after a reload of the plugin: the same one line, no request', async ($, on) => {
    const scene = await saveAndMoveOn($, on)
    const before = scene.world.logs.length
    await scene.start()

    await endTurnAt(scene, { five: 82 })
    await endTurnAt(scene, { five: 83 })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs.slice(before)).toEqual([
      getTakenLine(82, scene.world.clock.now()),
    ])
  })

  test('another action after the save: the new session is warned and asked again', async ($, on) => {
    const scene = await saveAndMoveOn($, on, { thresholds: { after_save: 'offer_clear' } })

    await endTurnAt(scene, { five: 82 })

    expect(scene.world.files.has(FIVE_SAVE)).toBe(true)
    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
  })

  test('a reset an hour or more from the saved one is a new window: the request again', async ($, on) => {
    const scene = await saveAndMoveOn($, on)

    await endTurnAt(scene, { five: 81, fiveResets: '2026-11-14T16:00:00.000Z' })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
  })

  test('a save under another login cell does not count for this one', async ($, on) => {
    const scene = await startScene($, on, CLEAR)
    scene.world.setFile(FIVE_SAVE, JSON.stringify({ cell: 'other', resets_at: '2026-11-14T15:00:00Z', saved_at: '2026-11-14T11:00:00Z' }))

    await endTurnAt(scene, { five: 81 })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a shared file that is not JSON reads as no saves, and the next save writes it whole', async ($, on) => {
    const scene = await startScene($, on, CLEAR)
    scene.world.setFile(FIVE_SAVE, '{')

    await endTurnAt(scene, { five: 81 })
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getLimitSaves(scene).cell).toBe(CELL)
  })

  test('a save writes only the file of its own cell and kind; the file of the other kind stays as it was', async ($, on) => {
    const scene = await askAt81($, on, CLEAR)
    scene.world.setFile(SEVEN_SAVE, 'untouched')

    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    expect(getLimitSaves(scene).resets_at).toBe('2026-11-14T15:00:00Z')
    expect(scene.world.files.get(SEVEN_SAVE).text).toBe('untouched')
  })

  test('no limit awaits a decision: the saved files are not read', async ($, on) => {
    const scene = await startScene($, on, CLEAR)
    const saved = JSON.stringify({ cell: CELL, resets_at: '2026-11-14T15:00:00Z', saved_at: '2026-11-14T11:00:00Z' })
    scene.world.setFile(FIVE_SAVE, saved)
    scene.world.setFile(SEVEN_SAVE, saved)
    scene.world.readPaths.length = 0

    await endTurnAt(scene, { five: 75 })

    expect(scene.world.readPaths).not.toContain(FIVE_SAVE)
    expect(scene.world.readPaths).not.toContain(SEVEN_SAVE)
  })
})
