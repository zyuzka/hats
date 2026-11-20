import { describe, expect, test } from 'claude-code/testing'
import {
  OTHER_SESSION,
  START,
  STATE,
  STAGE_FILE,
  STAGES,
  THRESHOLDS,
  createScene,
} from './world.ts'
import {
  BASE_AGE_MS,
  POINT_LIFE_MS,
  createPace,
  findEarly,
  findRate,
  findLeadSeconds,
  setPoint,
} from '../../hooks/pace.js'
import { findLimits, getLimitsRecord } from '../../hooks/limit-rules.js'

const SECOND = 1000
const MINUTE = 60 * SECOND
const HAT_USAGE = `${STATE}/hat-usage.json`
const FIVE_RESETS = '2026-11-14T15:00:00.000Z'
const FIVE_RESETS_MS = Date.parse(FIVE_RESETS)
const WINDOW_FILE = { warn_percent: 60, save_percent: 70, after_save: 'tell' }
const READ = { tool: 'Read', file_path: '/w/README.md' }
const NO_HAT = 'Hats has no other hat to switch to'
const TELL = 'Tell the user so in one short line in your reply, in their language, and go on with the task.'
const LEAD_OFF = 682

const getEarlyPart = (percent: number, minutes: number, word = '5-hour') =>
  `at ${percent}% of its ${word} limit and spending fast: ` +
  `at the pace of the last minutes it reaches 80% in about ${minutes} minutes, and ${NO_HAT}`

const getEarlyText = (percent: number, minutes: number, word = '5-hour') =>
  `Hats limit threshold: this session's account is ${getEarlyPart(percent, minutes, word)}. ` +
  `This session anchors at the end of a turn once it reaches 80%. ${TELL}`

const DRAIN_ON =
  ' Drain is on: do not start subagents, workflows, monitors or background commands; ' +
  'they are refused until the session is asked to anchor.'

const getEarlyDrainText = (percent: number, minutes: number, drainMinutes: number) =>
  `Hats limit threshold: this session's account is ${getEarlyPart(percent, minutes, '5-hour')}. ` +
  'This session anchors at the end of a turn once it reaches 80%, or, while its background work runs, ' +
  `at the end of a later turn within ${drainMinutes} min. ${TELL}${DRAIN_ON}`

const WARN_72 =
  "Hats limit threshold: this session's account is at 72% of its 5-hour limit (warning threshold 70%) " +
  `and ${NO_HAT}. This session anchors at the end of a turn once it reaches 80%. ${TELL}`

const createHatUsage = (fields: Record<string, unknown> = {}) => ({
  worn: 'work',
  five_hour: null,
  weekly: null,
  measured_at: null,
  has_a_hat_to_switch_to: false,
  auto_switch_on: true,
  credential_service: 'Claude Code-credentials',
  switch_covers: { five_hour: false, seven_day: false },
  alive_at: new Date(START).toISOString(),
  written_at: '2026-11-14T12:00:00Z',
  ...fields,
})

type Files = { thresholds?: Record<string, unknown>; hat?: Record<string, unknown> }

const startScene = async ($: any, on: any, files: Files = {}) => {
  const scene = createScene($, { on })
  scene.world.setFile(THRESHOLDS, JSON.stringify({ ...WINDOW_FILE, ...(files.thresholds ?? {}) }))
  scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage(files.hat)))
  await scene.start()

  return scene
}

const setFive = (scene: any, five: number) => {
  scene.world.rateLimits = [
    { kind: 'five_hour', percentUsed: five, resetsAt: FIVE_RESETS },
  ]
}

const WEEK_RESETS = '2026-11-18T09:00:00.000Z'

const setBoth = (scene: any, five: number, week: number) => {
  scene.world.rateLimits = [
    { kind: 'five_hour', percentUsed: five, resetsAt: FIVE_RESETS },
    { kind: 'seven_day', percentUsed: week, resetsAt: WEEK_RESETS },
  ]
}

const bothAt = (scene: any, five: number, week: number) => {
  setBoth(scene, five, week)

  return scene.callTool(10, READ)
}

const toolAt = (scene: any, five: number) => {
  setFive(scene, five)

  return scene.callTool(10, READ)
}

const measureAt = ($: any, scene: any, five: number) => {
  setFive(scene, five)

  return $.session.measure({ context: { window: 1000000 }, rateLimits: scene.world.rateLimits, changed: ['rateLimits'] })
}

const goTo = async (scene: any, sinceStartMs: number) => {
  await scene.world.clock.advance(START + sinceStartMs - scene.world.clock.now())
}

const getContext = (out: any) => out.context ?? []

const getFiveStage = (scene: any) => scene.world.getStage(STAGE_FILE)?.limits?.five_hour

const fastScene = async ($: any, on: any, files: Files = {}) => {
  const scene = await startScene($, on, files)
  await toolAt(scene, 53)
  await goTo(scene, 150 * SECOND)

  return scene
}

describe('the early signal through the registered hooks', () => {
  test('fast: 53 then 58 two and a half minutes later is the early warning with 11 minutes, and its event', async ($, on) => {
    const scene = await fastScene($, on)

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([
      getEarlyText(58, 11),
    ])
    expect(getFiveStage(scene).warned).toMatchObject({
      percent: 58,
      worn: 'work',
      reason: 'no_hat',
      early: true,
      minutes_to_save: 11,
      target: 80,
      lead_seconds: LEAD_OFF,
    })
  })

  test('a fractional reading counts the rest from itself: 58.9 is 633 seconds, still 11 minutes and early', async ($, on) => {
    const scene = await fastScene($, on)

    const out = await toolAt(scene, 58.9)

    expect(getContext(out)).toEqual([
      getEarlyText(58, 11),
    ])
    expect(getFiveStage(scene).warned).toMatchObject({ percent: 58.9, minutes_to_save: 11 })
  })

  test('the decimals decide: 57.5 is 675 seconds from 80, early with 12 minutes, while 57 would be 690', async ($, on) => {
    const scene = await startScene($, on)
    await toolAt(scene, 52)
    await goTo(scene, 150 * SECOND)

    const out = await toolAt(scene, 57.5)

    expect(getContext(out)).toEqual([
      getEarlyText(57, 12),
    ])
  })

  test('very fast: a point every 10 seconds from session.measure gives a base at least 60 seconds old', async ($, on) => {
    const scene = await startScene($, on)
    for (let step = 0; step <= 10; step += 1) {
      await goTo(scene, step * 10 * SECOND)
      await measureAt($, scene, 50 + step)
    }

    const out = await toolAt(scene, 60)

    expect(getContext(out)).toEqual([
      getEarlyText(60, 4),
    ])
  })

  test('gaps: 53 then straight to 59 two minutes later is 3 points a minute, 7 minutes', async ($, on) => {
    const scene = await startScene($, on)
    await toolAt(scene, 53)
    await goTo(scene, 120 * SECOND)

    const out = await toolAt(scene, 59)

    expect(getContext(out)).toEqual([
      getEarlyText(59, 7),
    ])
  })

  test('slow: 53 then 58 ten minutes later is nothing, and no event', async ($, on) => {
    const scene = await startScene($, on)
    await toolAt(scene, 53)
    await goTo(scene, 10 * MINUTE)

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([])
    expect(getFiveStage(scene)?.warned ?? null).toBe(null)
  })

  test('plateau: no new points until 12 1/2 minutes later drops the untold text; then 72 is the usual warning', async ($, on) => {
    const scene = await startScene($, on)
    await measureAt($, scene, 53)
    await goTo(scene, 150 * SECOND)
    await measureAt($, scene, 58)
    await goTo(scene, 750 * SECOND)

    const plateau = await toolAt(scene, 58)
    const later = await toolAt(scene, 72)

    expect(getContext(plateau)).toEqual([])
    expect(getContext(later)).toEqual([
      WARN_72,
    ])
    expect(getFiveStage(scene).warned).toMatchObject({ percent: 72, early: false, target: 80, lead_seconds: LEAD_OFF })
    expect(getFiveStage(scene).warned.minutes_to_save).toBe(undefined)
  })

  test('a refused result holds the signal; the delivery at 68 says 68 and the minutes of that moment', async ($, on) => {
    const scene = await fastScene($, on)
    scene.world.nextToolAnswer = { deny: 'refused for the test' }
    const refused = await toolAt(scene, 58)
    await goTo(scene, 180 * SECOND)

    const told = await toolAt(scene, 68)

    expect(getContext(refused)).toEqual([])
    expect(getContext(told)).toEqual([
      getEarlyText(68, 3),
    ])
    expect(getFiveStage(scene).warned).toMatchObject({ percent: 68, early: true, minutes_to_save: 3 })
  })

  test('a user message carries the early signal when no tool ran', async ($, on) => {
    const scene = await startScene($, on)
    await measureAt($, scene, 53)
    await goTo(scene, 150 * SECOND)
    await measureAt($, scene, 58)

    await scene.prompt('go on')

    expect(scene.world.prompts.at(-1).context).toEqual([
      getEarlyText(58, 11),
    ])
    expect(getFiveStage(scene).warned).toMatchObject({ early: true, minutes_to_save: 11 })
  })

  test('the early signal is the warning of the episode: at 72 there is none, and no stage at 70 is moved', async ($, on) => {
    const scene = await fastScene($, on)
    await toolAt(scene, 58)

    const after = await toolAt(scene, 72)

    expect(getContext(after)).toEqual([])
    expect(getFiveStage(scene).warned).toMatchObject({ percent: 58, early: true })
    expect(getFiveStage(scene).asked).toBe(null)
  })

  test('the request at 80 still comes after an early signal, and its event carries the target and the lead', async ($, on) => {
    const scene = await fastScene($, on)
    await toolAt(scene, 58)
    const turnId = await scene.startTurn(10)
    setFive(scene, 81)

    await scene.endTurn(turnId, { percent: 10 })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
    ])
    expect(getFiveStage(scene).asked).toMatchObject({ percent: 81, early: false, target: 80, lead_seconds: LEAD_OFF })
  })

  test('below the thresholds and fast the hat file is read; Hats would switch: nothing', async ($, on) => {
    const scene = await fastScene($, on, { hat: { switch_covers: { five_hour: true, seven_day: false } } })

    const out = await toolAt(scene, 58)

    expect(scene.world.readPaths).toContain(HAT_USAGE)
    expect(getContext(out)).toEqual([])
    expect(scene.world.files.has(STAGE_FILE)).toBe(false)
  })

  test('below the thresholds and slow the hat file is not read', async ($, on) => {
    const scene = await startScene($, on)
    await toolAt(scene, 53)
    await goTo(scene, 10 * MINUTE)

    await toolAt(scene, 58)

    expect(scene.world.readPaths).not.toContain(HAT_USAGE)
  })

  test('not under Hats: nothing', async ($, on) => {
    const scene = await fastScene($, on, { hat: { credential_service: 'Claude Code-credentials-0eaa50e6' } })

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([])
  })

  test('the warning threshold off: no early signal', async ($, on) => {
    const scene = await fastScene($, on, { thresholds: { limit_warn_percent: null } })

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([])
  })

  test('the anchor threshold off: nothing to forecast', async ($, on) => {
    const scene = await fastScene($, on, { thresholds: { limit_save_percent: null } })

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([])
  })

  const riseFiveIn5Minutes = async ($: any, on: any, files: Files = {}) => {
    const scene = await startScene($, on, files)
    await toolAt(scene, 58)
    await goTo(scene, 5 * MINUTE)

    return { scene, out: await toolAt(scene, 63) }
  }

  test('drain off: 17 minutes away is past the lead of 682 seconds, so nothing', async ($, on) => {
    const { out } = await riseFiveIn5Minutes($, on)

    expect(getContext(out)).toEqual([])
  })

  test('drain on for 30 minutes makes the lead 1882 seconds: 17 minutes away is early', async ($, on) => {
    const { scene, out } = await riseFiveIn5Minutes($, on, { thresholds: { drain: true, drain_minutes: 30 } })

    expect(getContext(out)).toEqual([
      getEarlyDrainText(63, 17, 30),
    ])
    expect(getFiveStage(scene).warned).toMatchObject({ lead_seconds: 1882, target: 80, minutes_to_save: 17 })
  })

  test('a reload starts with an empty memory: the forecast waits for new points', async ($, on) => {
    const scene = await startScene($, on)
    await toolAt(scene, 53)
    await goTo(scene, 150 * SECOND)
    await scene.start()

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([])
  })

  test('a new session keeps its own memory: the points of the old one do not count', async ($, on) => {
    const scene = await startScene($, on)
    await toolAt(scene, 53)
    await goTo(scene, 150 * SECOND)
    scene.world.sessionId = OTHER_SESSION

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([])
    expect(scene.world.files.has(`${STAGES}/${OTHER_SESSION}.json`)).toBe(false)
  })

  test('a refused tool result still leaves its point: 53 refused, 58 two and a half minutes later is early', async ($, on) => {
    const scene = await startScene($, on)
    scene.world.nextToolAnswer = { deny: 'refused for the test' }
    await toolAt(scene, 53)
    await goTo(scene, 150 * SECOND)

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([
      getEarlyText(58, 11),
    ])
  })

  test('the start of a turn leaves its point: a turn started at 53, a tool at 58 later is early', async ($, on) => {
    const scene = await startScene($, on)
    setFive(scene, 53)
    await scene.startTurn(10)
    await goTo(scene, 150 * SECOND)

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([
      getEarlyText(58, 11),
    ])
  })

  test('without a thresholds file a slow rise is nothing', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage()))
    await scene.start()
    await toolAt(scene, 53)
    await goTo(scene, 10 * MINUTE)

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([])
  })

  test('without a thresholds file a fast rise is early with the lead of 682 seconds', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(HAT_USAGE, JSON.stringify(createHatUsage()))
    await scene.start()
    await toolAt(scene, 53)
    await goTo(scene, 150 * SECOND)

    const out = await toolAt(scene, 58)

    expect(getContext(out)).toEqual([
      getEarlyText(58, 11),
    ])
    expect(getFiveStage(scene).warned).toMatchObject({ lead_seconds: LEAD_OFF, target: 80 })
  })

  test('drain switched on after the first reading of the episode makes the lead 1882 seconds', async ($, on) => {
    const scene = await startScene($, on)
    await toolAt(scene, 58)
    scene.world.setFile(THRESHOLDS, JSON.stringify({ ...WINDOW_FILE, drain: true, drain_minutes: 30 }))
    await goTo(scene, 5 * MINUTE)

    const out = await toolAt(scene, 63)

    expect(getContext(out)).toEqual([
      getEarlyDrainText(63, 17, 30),
    ])
    expect(getFiveStage(scene).warned).toMatchObject({ lead_seconds: 1882 })
  })

  test('an episode restored from the stage file after a reload, then a fast rise, is early', async ($, on) => {
    const scene = await startScene($, on)
    await bothAt(scene, 40, 72)
    await scene.start()
    await bothAt(scene, 53, 72)
    await goTo(scene, 150 * SECOND)

    const out = await bothAt(scene, 58, 72)

    expect(getContext(out)).toEqual([
      getEarlyText(58, 11),
    ])
  })

  test('the weekly limit spending fast is an early signal that names it', async ($, on) => {
    const scene = await startScene($, on)
    await bothAt(scene, 10, 53)
    await goTo(scene, 150 * SECOND)

    const out = await bothAt(scene, 10, 58)

    expect(getContext(out)).toEqual([
      getEarlyText(58, 11, 'weekly'),
    ])
    expect(scene.world.getStage(STAGE_FILE).limits.seven_day.warned).toMatchObject({ early: true, minutes_to_save: 11 })
  })

  test('both limits spending fast at once are one text naming both', async ($, on) => {
    const scene = await startScene($, on)
    await bothAt(scene, 53, 53)
    await goTo(scene, 150 * SECOND)

    const out = await bothAt(scene, 58, 58)

    expect(getContext(out)).toEqual([
      `Hats limit threshold: this session's account is ${getEarlyPart(58, 11)}; it is also ${getEarlyPart(58, 11, 'weekly')}. ` +
        `This session anchors at the end of a turn once it reaches 80%. ${TELL}`,
    ])
  })

  test('without session.measure the points come from the events of the mod alone', async ($, on) => {
    const scene = await fastScene($, on)

    const out = await toolAt(scene, 58)

    expect(getContext(out)[0]).toStartWith("Hats limit threshold: this session's account is at 58% of its 5-hour limit and spending fast")
  })
})

describe('the pace rules', () => {
  const reading = (percent: number, resetsMs = FIVE_RESETS_MS) => ({ percent, resetsMs })

  const createMemory = (points: [number, number][]) => {
    const pace = createPace()
    for (const [percent, atMs] of points) setPoint(pace, { kind: 'five_hour', reading: reading(percent), now: atMs })

    return pace
  }

  test('less than 5 points of rise is no forecast', () => {
    const pace = createMemory([
      [53, 0],
      [57, 5 * MINUTE],
    ])

    expect(findRate(pace.five_hour, 5 * MINUTE)).toBe(null)
  })

  test('a base less than 60 seconds before now is no forecast; at 60 seconds it is', () => {
    const pace = createMemory([
      [53, 0],
      [58, 30 * SECOND],
    ])

    expect(findRate(pace.five_hour, BASE_AGE_MS - 1)).toBe(null)
    expect(findRate(pace.five_hour, BASE_AGE_MS)).toBe(5 / 60)
  })

  test('points older than 60 minutes are forgotten and the forecast uses the rest', () => {
    const pace = createMemory([
      [40, 0],
      [53, 50 * MINUTE],
      [58, 61 * MINUTE],
    ])

    expect(findRate(pace.five_hour, 61 * MINUTE)).toBe(5 / 660)
    expect(pace.five_hour.points.map((point: any) => point.whole)).toEqual([
      53,
      58,
    ])
    expect(findRate(pace.five_hour, 50 * MINUTE + POINT_LIFE_MS + 1)).toBe(null)
  })

  test('an equal number in the same episode is not a point, a lower one starts again; a new episode starts again', () => {
    const equal = createMemory([
      [53, 0],
      [58.4, MINUTE],
      [58.9, 2 * MINUTE],
    ])
    const lower = createMemory([
      [53, 0],
      [58.4, MINUTE],
      [57, 2 * MINUTE],
    ])
    setPoint(lower, { kind: 'five_hour', reading: reading(5, FIVE_RESETS_MS + 5 * 60 * MINUTE), now: 4 * MINUTE })

    expect(equal.five_hour.points).toEqual([
      { whole: 53, atMs: 0 },
      { whole: 58, atMs: MINUTE },
    ])
    expect(lower.five_hour.points).toEqual([
      { whole: 5, atMs: 4 * MINUTE },
    ])
  })

  test('already at the warning threshold the stage is 11a, not an early signal', () => {
    const pace = createMemory([
      [60, 0],
      [70, MINUTE],
    ])
    const episode = { warn: 70, save: 80, warned: null, percent: 70, lead: LEAD_OFF }

    expect(findEarly(pace, { kind: 'five_hour', episode, now: MINUTE })).toBe(null)
    expect(findEarly(pace, { kind: 'five_hour', episode: { ...episode, percent: 69.9 }, now: MINUTE })).toMatchObject({ minutes: 2 })
  })

  test('the lead is the drain minutes plus 82 seconds with drain on, 10 minutes plus 82 with it off', () => {
    const lead = (fields: Record<string, unknown>) => findLeadSeconds(JSON.stringify({ ...WINDOW_FILE, ...fields }))

    expect(findLeadSeconds('{')).toBe(LEAD_OFF)
    expect(lead({ drain: false, drain_minutes: 30 })).toBe(LEAD_OFF)
    expect(lead({ drain: true, drain_minutes: 30 })).toBe(1882)
    expect(lead({ drain: true, drain_minutes: 61 })).toBe(LEAD_OFF)
  })

  test('drain on with the window anchor threshold off still waits by the limit, so the lead is the drain minutes plus 82', () => {
    expect(findLeadSeconds(JSON.stringify({ ...WINDOW_FILE, save_percent: null, drain: true, drain_minutes: 30 }))).toBe(1882)
  })

  test('a reading below the top in the same episode is another account: the points start again from it', () => {
    const pace = createMemory([
      [53, 0],
      [58, MINUTE],
      [20, 2 * MINUTE],
      [26, 4 * MINUTE],
    ])

    expect(pace.five_hour.points).toEqual([
      { whole: 20, atMs: 2 * MINUTE },
      { whole: 26, atMs: 4 * MINUTE },
    ])
    expect(findRate(pace.five_hour, 4 * MINUTE)).toBe(6 / 120)
  })

  test('no forecast with no finite lead, or with less than a minute that rounds to 0', () => {
    const pace = createMemory([
      [60, 0],
      [70, MINUTE],
    ])
    const episode = { warn: 70, save: 80, warned: null, percent: 69, lead: LEAD_OFF }

    expect(findEarly(pace, { kind: 'five_hour', episode: { ...episode, lead: undefined }, now: MINUTE })).toBe(null)
    expect(findEarly(pace, { kind: 'five_hour', episode: { ...episode, lead: null }, now: MINUTE })).toBe(null)
    expect(findEarly(pace, { kind: 'five_hour', episode: { ...episode, warn: 85, percent: 80 }, now: MINUTE })).toBe(null)
  })

  test('a reading a second from the threshold says about 1 minute, never 0', () => {
    const pace = createMemory([
      [60, 0],
      [70, MINUTE],
    ])
    const episode = { warn: 81, save: 82, warned: null, percent: 80.9, lead: LEAD_OFF }

    expect(findEarly(pace, { kind: 'five_hour', episode, now: MINUTE })).toMatchObject({ minutes: 1 })
  })

  test('the pace fields of an event survive the stage file; an old event gains none', () => {
    const early = {
      at: '2026-11-14T12:40:02.800Z',
      percent: 58,
      worn: 'work',
      reason: 'no_hat',
      early: true,
      target: 80,
      lead_seconds: 682,
      minutes_to_save: 11,
    }
    const old = { at: '2026-11-14T12:40:02.800Z', percent: 72, worn: 'work', reason: 'no_hat' }
    const episode = { resets_at: '2026-11-14T15:00:00Z', percent: 81, warn_percent: 70, save_percent: 80, failed_asks: 0 }

    const withEarly = getLimitsRecord(findLimits({ five_hour: { ...episode, warned: early, asked: null, previous: null } }))
    const withOld = getLimitsRecord(findLimits({ five_hour: { ...episode, warned: old, asked: null, previous: null } }))

    expect(withEarly.five_hour?.warned).toEqual(early)
    expect(withOld.five_hour?.warned).toEqual(old)
  })
})
