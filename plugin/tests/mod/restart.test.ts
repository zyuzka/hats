import { describe, expect, test } from 'claude-code/testing'
import {
  NOTE_TEXT,
  SESSION,
  STAGE_FILE,
  STATE,
  START,
  THRESHOLDS,
  createBashResult,
  createScene,
} from './world.ts'
import {
  RESTART_DENY_TEXT,
  getRestartLine,
  getRestartText,
  isRestartCall,
  isRestartDue,
} from '../../hooks/restart.js'
import { DENY_TEXT } from '../../hooks/drain.js'

const MINUTE = 60 * 1000
const FILE = { warn_percent: 45, save_percent: 55, after_save: 'clear' }
const THRESHOLDS_ON = { warn: 45, save: 55, after: 'clear', drain: false, drainMinutes: 10 }
const READ = { tool: 'Read', file_path: '/w/README.md' }
const AGENT = { tool: 'Agent', description: 'probe', prompt: 'Reply OK.' }
const ECHO = { tool: 'Bash', command: 'echo hi' }
const LAUNCHES = [
  AGENT,
  { tool: 'Task', description: 'probe', prompt: 'Reply OK.' },
  { tool: 'Workflow', script: 'export const meta = {}' },
  { tool: 'Monitor', command: 'sleep 5; echo tick', description: 'm', timeout_ms: 60000 },
  { tool: 'Bash', command: 'sleep 30', run_in_background: true },
  { tool: 'PowerShell', command: 'Start-Sleep 30', run_in_background: 'true' },
  { tool: 'CronCreate', cron: '0 * * * *', prompt: 'x' },
  { tool: 'ScheduleWakeup', delaySeconds: 60, prompt: 'x' },
]
const FOREGROUND = [
  ECHO,
  { tool: 'Bash', command: 'echo hi', run_in_background: false },
  { tool: 'PowerShell', command: 'Get-Date' },
  { tool: 'Edit', file_path: '/w/a.txt', old_string: 'a', new_string: 'b' },
  { tool: 'Write', file_path: '/w/b.txt', content: 'b' },
  { tool: 'TaskStop', task_id: 'b1' },
  { tool: 'SendMessage', to: 'a1', message: 'go on' },
  { tool: 'Skill', skill: 'hats:anchor' },
  READ,
]
const LINE_56 = getRestartLine(56)
const RELEASE = 'background work is allowed again'

const useFile = (scene: any, fields: Record<string, unknown> = {}) =>
  scene.world.setFile(THRESHOLDS, JSON.stringify({ ...FILE, ...fields }))

const getContext = (out: any) => out?.context ?? []

const getRestartLines = (scene: any) => scene.world.logs.filter((line: string) => line.includes('this session restarts after saving'))

const startPast = async (scene: any, percent = 56) => {
  await scene.start()
  const first = await scene.startTurn(10)
  await scene.endTurn(first, { percent: 10 })
  const turnId = await scene.startTurn(10)
  const out = await scene.callTool(percent, READ)

  return { turnId, out }
}

const callOnce = async (scene: any, input: any, percent: number | null = 56) => {
  scene.world.nextToolAnswer = createBashResult('ran')
  const out = await scene.callTool(percent ?? undefined, input)
  scene.world.nextToolAnswer = null

  return out
}

const getSaveSteps = (scene: any) => [
  () => scene.runSteps(),
  scene.createNote,
  () => scene.writeNote(NOTE_TEXT),
  scene.runSave,
  () => scene.runSteps(),
  async () => scene.setSnapshot(),
]

const promptOnce = async (scene: any, text = 'next') => {
  await scene.prompt(text)

  return scene.world.prompts.at(-1).context ?? []
}

const keepAfterSave = async (scene: any) => {
  useFile(scene)
  scene.world.isPluginGone = true
  await scene.askToAnchor()
  await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
}

describe('the restart state as a rule', () => {
  const state = { saveReached: true, id: SESSION }
  const base = { thresholds: THRESHOLDS_ON, percent: 56 }

  test('holds with the mark, clear after the save, the save threshold on and the window at or past it', () => {
    expect(isRestartDue(state, base)).toBe(true)
    expect(isRestartDue(state, { ...base, percent: 55 })).toBe(true)
  })

  test('ends without the mark, with another action, with the save threshold off, below it, or with nothing measured', () => {
    expect(isRestartDue({ ...state, saveReached: false }, base)).toBe(false)
    expect(isRestartDue(state, { ...base, thresholds: { ...THRESHOLDS_ON, after: 'offer_clear' } })).toBe(false)
    expect(isRestartDue(state, { ...base, thresholds: { ...THRESHOLDS_ON, after: 'tell' } })).toBe(false)
    expect(isRestartDue(state, { ...base, thresholds: { ...THRESHOLDS_ON, save: null } })).toBe(false)
    expect(isRestartDue(state, { ...base, percent: 54 })).toBe(false)
    expect(isRestartDue(state, { ...base, thresholds: null })).toBe(false)
    expect(isRestartDue(state, { ...base, percent: null })).toBe(false)
  })

  test('refuses subagents, workflows, monitors, background commands, cron jobs and wake-ups, nothing in the foreground', () => {
    expect(LAUNCHES.map(isRestartCall)).toEqual(LAUNCHES.map(() => true))
    expect(FOREGROUND.map(isRestartCall)).toEqual(FOREGROUND.map(() => false))
  })

  test('tells the model to save only and how to leave, and the user once', () => {
    const head =
      "Hats restart: this session's context window is at 75% and the session is cleared after saving, " +
      'so start no new work in it: only save, and leave new work to the next session. ' +
      'Subagents, workflows, monitors, background commands, cron jobs and wake-ups are refused until the session is cleared. '

    expect(getRestartText(75, false)).toBe(`${head}The note is not saved yet: tell the user in one short line, in their language, to say "anchor".`)
    expect(getRestartText(75, true)).toBe(`${head}The note is saved: tell the user in one short line, in their language, to type /clear.`)
    expect(getRestartLine(72)).toBe('context 72% — this session restarts after saving; new work waits for the next session.')
  })
})

describe('the threshold crossed in the middle of a turn', () => {
  for (const launch of LAUNCHES) {
    test(`refuses ${launch.tool}${launch.tool === 'Bash' || launch.tool === 'PowerShell' ? ' in the background' : ''}`, async ($, on) => {
      const scene = createScene($, { on })
      useFile(scene)
      await startPast(scene)

      expect((await callOnce(scene, launch)).deny).toBe(RESTART_DENY_TEXT)
    })
  }

  test('passes the foreground: a Bash, an edit, TaskStop, SendMessage', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startPast(scene)

    const denials = []
    for (const call of FOREGROUND) denials.push((await callOnce(scene, call)).deny)

    expect(denials).toEqual(FOREGROUND.map(() => undefined))
  })

  test('refuses a launch from a subagent, tells the user once, drops the warning and keeps the mark in the file', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const { out } = await startPast(scene)

    const fromAgent = await callOnce(scene, { ...AGENT, agentId: 'a1' })
    await callOnce(scene, AGENT)

    expect(fromAgent.deny).toBe(RESTART_DENY_TEXT)
    expect(scene.world.logs).toEqual([LINE_56])
    expect(getContext(out).some((text: string) => text.startsWith('Hats context threshold'))).toBe(false)
    expect(scene.world.getStage()).toMatchObject({ save_reached: true, after_save: 'clear' })
  })

  test('a measurement that cannot be read: the last percent decides', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { warn_percent: null })
    await startPast(scene)

    expect((await callOnce(scene, AGENT, null)).deny).toBe(RESTART_DENY_TEXT)
  })

  test('the window falls below the threshold: nothing is refused and no line is added', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startPast(scene)

    const agent = await callOnce(scene, AGENT, 40)
    const context = await promptOnce(scene)

    expect(agent.deny).toBe(undefined)
    expect(context).toEqual([])
    expect(getRestartLines(scene)).toEqual([LINE_56])
  })

  test('another action after the save: nothing new', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { after_save: 'offer_clear' })
    await startPast(scene)

    const agent = await callOnce(scene, AGENT)
    const context = await promptOnce(scene)

    expect(agent.deny).toBe(undefined)
    expect(context.some((text: string) => text.startsWith('Hats restart'))).toBe(false)
    expect(getRestartLines(scene)).toEqual([])
  })

  test('the settings change to another action or the save threshold off: the refusal ends without a line', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startPast(scene)
    const logs = scene.world.logs.length

    useFile(scene, { after_save: 'tell' })
    const told = await callOnce(scene, AGENT)
    useFile(scene, { save_percent: null })
    const off = await callOnce(scene, AGENT)

    expect(told.deny).toBe(undefined)
    expect(off.deny).toBe(undefined)
    expect(scene.world.logs.length).toBe(logs)
  })
})

describe('the line for the model on input of the user', () => {
  test('kept after the save: three messages, each gets the line with /clear, the user line came once', async ($, on) => {
    const scene = createScene($, { on })
    await keepAfterSave(scene)
    expect(scene.world.getStage()).toMatchObject({ stage: 'kept' })

    const contexts = [
      await promptOnce(scene, 'one'),
      await promptOnce(scene, 'two'),
      await promptOnce(scene, 'three'),
    ]

    expect(contexts).toEqual([0, 1, 2].map(() => [getRestartText(58, true)]))
    expect(getRestartLines(scene)).toEqual([LINE_56])
    expect((await callOnce(scene, AGENT, 58)).deny).toBe(RESTART_DENY_TEXT)
  })

  test('the save failed: the line says anchor, and launches are refused', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: [] })
    expect(scene.world.getStage()).toMatchObject({ stage: 'failed' })

    const context = await promptOnce(scene)

    expect(context).toEqual([getRestartText(58, false)])
    expect((await callOnce(scene, AGENT, 58)).deny).toBe(RESTART_DENY_TEXT)
  })

  test('the anchor stopped with Esc: launches stay refused', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: [], reason: 'aborted' })
    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted' })

    expect((await callOnce(scene, AGENT, 58)).deny).toBe(RESTART_DENY_TEXT)
    expect(await promptOnce(scene)).toEqual([getRestartText(58, false)])
  })

  test('the anchor stopped with Esc after a checked save: the line says /clear', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getSaveSteps(scene), reason: 'aborted' })
    expect(scene.world.logs.at(-1)).toBe('anchoring was stopped; the note was saved.')

    expect(await promptOnce(scene)).toEqual([getRestartText(58, true)])
    expect((await callOnce(scene, AGENT, 58)).deny).toBe(RESTART_DENY_TEXT)
  })

  test('a manual save past the threshold: the line says /clear', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.start()
    const turnId = await scene.startTurn(10)
    for (const step of getSaveSteps(scene)) await step()
    await scene.endTurn(turnId, { percent: 58 })
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', reason: 'manual' })

    expect(await promptOnce(scene)).toEqual([getRestartText(58, true)])
  })

  test('a notice of a background task, another plugin and a command get no line', async ($, on) => {
    const scene = createScene($, { on })
    await keepAfterSave(scene)

    await scene.notice('<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>')
    const notice = scene.world.prompts.at(-1).context ?? []
    await scene.pluginPrompt('other')
    const plugin = scene.world.prompts.at(-1).context ?? []
    await scene.prompt('/x', { name: 'x', args: '' })
    const command = scene.world.prompts.at(-1).context ?? []

    expect([notice, plugin, command]).toEqual([[], [], []])
  })
})

describe('the own clear and its pause', () => {
  test('/clear that kept the session: no pause, launches stay refused', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    scene.world.clearAnswer = 'same'
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the session did not change after /clear' })

    expect((await callOnce(scene, AGENT, 58)).deny).toBe(RESTART_DENY_TEXT)
    expect(await promptOnce(scene)).toEqual([getRestartText(58, true)])
  })

  test('/clear that kept the session: the next pass of the threshold asks to anchor again at once', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { warn_percent: null })
    scene.world.clearAnswer = 'same'
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    const low = await scene.startTurn(58)
    await scene.endTurn(low, { percent: 50 })
    const high = await scene.startTurn(50)
    await scene.endTurn(high, { percent: 56 })

    expect(scene.world.runs).toEqual(['hats:anchor', 'clear', 'hats:anchor'])
    expect(scene.world.logs.some((line: string) => line.includes('not anchoring within 10 minutes'))).toBe(false)
  })

  test('within 10 minutes of the own clear the new session gets no refusal and no line, nor after them', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { warn_percent: null })
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })
    expect(scene.world.runs).toEqual(['hats:anchor', 'clear'])

    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 10 })
    const high = await scene.startTurn(10)
    const paused = await callOnce(scene, AGENT, 56)
    await scene.endTurn(high, { percent: 56 })
    const context = await promptOnce(scene)
    await scene.world.clock.advance(10 * MINUTE)
    const later = await callOnce(scene, AGENT, 57)

    expect(paused.deny).toBe(undefined)
    expect(context.some((text: string) => text.startsWith('Hats restart'))).toBe(false)
    expect(later.deny).toBe(undefined)
    expect(getRestartLines(scene)).toEqual([LINE_56])
  })
})

describe('a reload of the mod', () => {
  test('before the request: the mark comes back from the file and launches stay refused', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startPast(scene)

    await scene.start()

    expect((await callOnce(scene, AGENT, 75)).deny).toBe(RESTART_DENY_TEXT)
  })

  test('after kept and twice: refused, and the line still says /clear', async ($, on) => {
    const scene = createScene($, { on })
    await keepAfterSave(scene)

    await scene.start()
    await scene.start()

    expect((await callOnce(scene, AGENT, 75)).deny).toBe(RESTART_DENY_TEXT)
    expect(await promptOnce(scene)).toEqual([getRestartText(75, true)])
  })

  test('an old stage file without the mark: no refusal', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const record = { session: SESSION, stage: 'kept', warn_round: 0, save_round: 1, percent: 56 }
    scene.world.setFile(STAGE_FILE, JSON.stringify(record))
    await scene.start()

    const old = await callOnce(scene, AGENT, 75)
    scene.world.setFile(STAGE_FILE, JSON.stringify({ ...record, save_reached: true }))
    await scene.start()
    const marked = await callOnce(scene, AGENT, 75)

    expect(old.deny).toBe(undefined)
    expect(marked.deny).toBe(RESTART_DENY_TEXT)
  })
})

const HAT_USAGE = `${STATE}/hat-usage.json`

const setHat = (scene: any) =>
  scene.world.setFile(HAT_USAGE, JSON.stringify({
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
  }))

const setFive = (scene: any, percent: number, resetsAt = '2026-11-14T15:00:00.000Z') => {
  scene.world.rateLimits = [{ kind: 'five_hour', percentUsed: percent, resetsAt }]
}

describe('the order of the refusals', () => {
  test('restart and the window drain: the restart text, and the drain is not marked as told', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { drain: true, drain_minutes: 5 })
    await startPast(scene)

    const agent = await callOnce(scene, AGENT)
    const below = await scene.callTool(40, READ)

    expect(agent.deny).toBe(RESTART_DENY_TEXT)
    expect(agent.deny).not.toBe(DENY_TEXT)
    expect(getContext(below).some((text: string) => text.includes(RELEASE))).toBe(false)
  })

  test('restart, a limit and the window drain at once: the restart text, and the limit drain is not marked as told', async ($, on) => {
    const scene = createScene($, { on })
    const file = { warn_percent: 60, save_percent: 70, after_save: 'clear', drain: false, drain_minutes: 10 }
    scene.world.setFile(THRESHOLDS, JSON.stringify(file))
    setHat(scene)
    await scene.start()
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(10)
    setFive(scene, 72)
    const warned = await scene.callTool(10, READ)
    await scene.callTool(71, READ)

    scene.world.setFile(THRESHOLDS, JSON.stringify({ ...file, drain: true }))
    setFive(scene, 73)
    const all = await callOnce(scene, AGENT, 71)
    setFive(scene, 10, '2026-11-14T20:00:00.000Z')
    const fallen = await scene.callTool(40, READ)

    expect(getContext(warned).some((text: string) => text.startsWith('Hats limit threshold'))).toBe(true)
    expect(all.deny).toBe(RESTART_DENY_TEXT)
    expect(getContext(fallen).some((text: string) => text.includes(RELEASE))).toBe(false)
  })

  test('the drain turned off while the restart holds: no release until the window falls', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { drain: true, drain_minutes: 5 })
    await scene.start()
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(10)
    const warned = await scene.callTool(47, READ)
    await scene.callTool(56, READ)

    useFile(scene, { drain: false })
    const held = await scene.callTool(56, READ)
    const prompted = await promptOnce(scene)
    const fallen = await scene.callTool(40, READ)

    expect(getContext(warned).some((text: string) => text.includes('Drain is on'))).toBe(true)
    expect(getContext(held).some((text: string) => text.includes(RELEASE))).toBe(false)
    expect(prompted).toEqual([getRestartText(56, false)])
    expect(getContext(fallen).some((text: string) => text.includes(RELEASE))).toBe(true)
  })
})
