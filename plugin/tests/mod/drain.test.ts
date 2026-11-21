import { describe, expect, test } from 'claude-code/testing'
import {
  NEXT_SESSION,
  NOTE_TEXT,
  OTHER_SESSION,
  SESSION,
  SNAPSHOT,
  STAGES,
  STAGE_FILE,
  THRESHOLDS,
  createBashResult,
  createScene,
} from './world.ts'
import {
  DENY_TEXT,
  RELOADED_WAIT_LINE,
  UNCHECKED_LINE,
  WAIT_CANCELLED,
  findListText,
  getHolderCount,
  getWaitLine,
  isDrainCall,
} from '../../hooks/drain.js'
import {
  DEFAULTS,
  STOPPED,
  createPrevious,
  createStageRecord,
  findRefusalOutcome,
  findSnapshot,
  findThresholds,
  getWarningText,
} from '../../hooks/thresholds.js'

const MINUTE = 60 * 1000
const DRAIN_FILE = { warn_percent: 45, save_percent: 55, after_save: 'tell', drain: true, drain_minutes: 5 }
const READ = { tool: 'Read', file_path: '/w/README.md' }
const AGENT = { tool: 'Agent', description: 'probe', prompt: 'Reply OK.' }
const BACKGROUND_BASH = { tool: 'Bash', command: 'sleep 30', run_in_background: true }
const REQUEST_56 = 'context 56% (anchor threshold 55%) — anchoring this session.'
const REQUEST_57 = 'context 57% (anchor threshold 55%) — anchoring this session.'
const HOLDERS = [
  { id: 'b1shell', type: 'shell', status: 'running', description: 'sleep 180' },
  { id: 'a2agent', type: 'subagent', status: 'running', description: 'review' },
]
const OTHERS = [
  { id: 't3mate', type: 'teammate', status: 'running', description: 'mate' },
  { id: 'm4ws', type: 'monitor', status: 'running', description: 'socket' },
]
const SERVICE = [
  { id: 'd5dream', type: 'dream', status: 'running', description: 'dream' },
  { id: 'x6scan', type: 'auto-mode scan', status: 'running', description: 'scan' },
  { id: 'i7import', type: 'memory import', status: 'running', description: 'import' },
]
const DENIED_CALLS = [
  AGENT,
  { tool: 'Task', description: 'probe', prompt: 'Reply OK.' },
  { tool: 'Workflow', script: 'export const meta = {}' },
  { tool: 'Monitor', command: 'sleep 5; echo tick', description: 'm', timeout_ms: 60000 },
  { tool: 'Monitor', ws: { url: 'ws://127.0.0.1:1' }, description: 'm', timeout_ms: 60000 },
  BACKGROUND_BASH,
  { tool: 'Bash', command: 'sleep 30', run_in_background: 'true' },
  { tool: 'Bash', command: 'sleep 30', run_in_background: 'TRUE' },
  { tool: 'PowerShell', command: 'Start-Sleep 30', run_in_background: 'True' },
]
const PASSED_CALLS = [
  { tool: 'Bash', command: 'echo hi' },
  { tool: 'Bash', command: 'echo hi', run_in_background: false },
  { tool: 'Bash', command: 'echo hi', run_in_background: 'false' },
  { tool: 'PowerShell', command: 'Get-Date' },
  { tool: 'Skill', skill: 'hats:anchor' },
  { tool: 'SendMessage', to: 'a1', message: 'go on' },
  { tool: 'TaskStop', task_id: 'b1' },
  { tool: 'CronCreate', cron: '0 * * * *', prompt: 'x' },
  { tool: 'ScheduleWakeup', delaySeconds: 60, prompt: 'x' },
  READ,
]
const LIST_HEAD =
  'Hats drain: still running — they outlive /clear, and the next session is told when one ends ' +
  'but not what it was for, so list each in the note:'

const useFile = (scene: any, fields: Record<string, unknown> = {}) =>
  scene.world.setFile(THRESHOLDS, JSON.stringify({ ...DRAIN_FILE, ...fields }))

const startWarned = async (scene: any) => {
  await scene.start()
  const first = await scene.startTurn(10)
  await scene.endTurn(first, { percent: 10 })
  const turnId = await scene.startTurn(47)
  await scene.callTool(47, READ)

  return turnId
}

const callOnce = async (scene: any, input: any, percent = 47) => {
  scene.world.nextToolAnswer = createBashResult('ran')
  const out = await scene.callTool(percent, input)
  const isAnswered = scene.world.nextToolAnswer === null
  scene.world.nextToolAnswer = null

  return { deny: out.deny, isAnswered }
}

const startWaiting = async (scene: any) => {
  const turnId = await startWarned(scene)
  scene.setSnapshot({ tasks: HOLDERS })
  await scene.endTurn(turnId, { percent: 56 })
}

const endTurnWith = async (scene: any, ending: { percent: number; tasks: any[]; waitMs?: number }) => {
  const turnId = await scene.startTurn(ending.percent)
  await scene.world.clock.advance(ending.waitMs ?? 0)
  scene.setSnapshot({ tasks: ending.tasks })
  await scene.endTurn(turnId, { percent: ending.percent })
}

const waitOutSnapshot = async (scene: any, turnId: string, percent: number) => {
  const held = await scene.holdTurnEnd(turnId, { percent })
  await scene.world.clock.advance(2100)
  await held.done
}

const getList = (tasks: any[]) =>
  [
    LIST_HEAD,
    ...tasks.map((task, index) => `${index + 1}. ${task.type} "${task.description}" (id ${task.id})`),
  ].join('\n')

const getSaveSteps = (scene: any, note = NOTE_TEXT) => [
  () => scene.runSteps(),
  scene.createNote,
  () => scene.writeNote(note),
  scene.runSave,
  () => scene.runSteps(),
]

const clearOnce = async (scene: any) => {
  useFile(scene, { after_save: 'clear', drain: false })
  await scene.askToAnchor()
  await scene.runAnchorTurn({
    steps: [
      ...getSaveSteps(scene),
      async () => scene.setSnapshot(),
    ],
  })
  useFile(scene, { after_save: 'clear' })
}

const getStages = (scene: any) => scene.world.getStageWrites().map((write: any) => [
  write.stage,
  write.save_round,
  write.drain_minutes,
])

describe('the drain fields of the thresholds file', () => {
  test('turn drain on only for true and take whole minutes from 1 to 60, else 10', () => {
    const read = (fields: Record<string, unknown>) => findThresholds(JSON.stringify({ ...DRAIN_FILE, ...fields }))

    expect(read({})).toMatchObject({ drain: true, drainMinutes: 5 })
    expect(read({ drain: 'true', drain_minutes: 1 })).toMatchObject({ drain: false, drainMinutes: 1 })
    expect(read({ drain: 1, drain_minutes: 60 })).toMatchObject({ drain: false, drainMinutes: 60 })
    expect(read({ drain_minutes: 0 })?.drainMinutes).toBe(10)
    expect(read({ drain_minutes: 61 })?.drainMinutes).toBe(10)
    expect(read({ drain_minutes: 5.5 })?.drainMinutes).toBe(10)
    expect(read({ drain_minutes: '5' })?.drainMinutes).toBe(10)
    expect(findThresholds(JSON.stringify({ warn_percent: 45, save_percent: 55, after_save: 'tell' }))).toMatchObject({
      warn: 45,
      save: 55,
      drain: false,
      drainMinutes: 10,
    })
    expect(DEFAULTS).toMatchObject({ drain: false, drainMinutes: 10 })
  })

  test('never make the file unusable: the thresholds stay as they are', () => {
    const broken = findThresholds(JSON.stringify({ ...DRAIN_FILE, drain: { on: true }, drain_minutes: [5] }))

    expect(broken).toEqual({ warn: 45, save: 55, after: 'tell', drain: false, drainMinutes: 10 })
  })
})

describe('the calls the drain refuses', () => {
  test('are every Agent, Task, Workflow and Monitor and a Bash or PowerShell with run_in_background true', () => {
    expect(DENIED_CALLS.map(isDrainCall)).toEqual(DENIED_CALLS.map(() => true))
    expect(PASSED_CALLS.map(isDrainCall)).toEqual(PASSED_CALLS.map(() => false))
  })

  test('refuse with the text of the plan', () => {
    expect(DENY_TEXT).toBe(
      "Hats drain: this session's context window is close to its anchor threshold, so new background work — " +
        'subagents, workflows, monitors and background commands — is refused until the session is asked to anchor. ' +
        'Do this step in the foreground (a Bash call without run_in_background and with a timeout long enough for it, ' +
        'or the work yourself) or leave it for the next session, and tell the user in one line.',
    )
  })
})

describe('the list of running work', () => {
  test('names every job of the snapshot with its type, description and id, 25 of them too', () => {
    const tasks = Array.from({ length: 25 }, (_, index) => ({
      id: `j${index}`,
      type: index % 2 === 0 ? 'shell' : 'monitor',
      status: 'running',
      description: `job ${index}`,
    }))

    const text = findListText(tasks)

    expect(text).toBe(getList(tasks))
    expect(text?.split('\n').length).toBe(26)
    expect(findListText([])).toBe(null)
  })

  test('cuts a description to 120 characters, drops control characters and names an empty one', () => {
    const long = 'é'.repeat(130)

    const text = findListText([
      { id: 'a', type: 'shell', status: 'running', description: long },
      { id: 'b', type: 'shell', status: 'running', description: 'two\nlines\u0007' },
      { id: 'c', type: 'subagent', status: 'running', description: '' },
      { id: 'd', type: 'subagent', status: 'running', description: '  \t ' },
    ])

    expect(text?.split('\n').slice(1)).toEqual([
      `1. shell "${'é'.repeat(120)}" (id a)`,
      '2. shell "two lines " (id b)',
      '3. subagent "(no description)" (id c)',
      '4. subagent "(no description)" (id d)',
    ])
  })

  test('holds the wait only for shell, subagent and workflow', () => {
    expect(getHolderCount([
      ...HOLDERS,
      { id: 'w', type: 'workflow', status: 'pending', description: 'w' },
      ...OTHERS,
      ...SERVICE,
    ])).toBe(3)
  })

  test('comes from the snapshot with the fields the drain needs, ids as before', () => {
    const text = JSON.stringify({ session: 's', at_ms: 5, ok: true, tasks: [{ id: 'x', type: 'shell' }], crons: 0 })

    expect(findSnapshot(text, 's')).toMatchObject({
      ids: ['x'],
      tasks: [{ id: 'x', type: 'shell', status: '', description: '' }],
    })
  })
})

describe('the texts of the drain', () => {
  test('add the later turn and the drain line to the warning while the drain is on', () => {
    const thresholds = { warn: 45, save: 55, after: 'tell', drain: true, drainMinutes: 5 }

    expect(getWarningText({ thresholds, percent: 47 })).toBe(
      "Hats context threshold: this session's context window is at 47% (warning threshold 45%). " +
        'It anchors itself once it reaches 55%: at the end of that turn, or, while its background work runs, ' +
        'at the end of a later turn within 5 min. ' +
        'Tell the user so in one short line in your reply, in their language, and go on with the task. ' +
        'Drain is on: do not start subagents, workflows, monitors or background commands; ' +
        'they are refused until the session is asked to anchor.',
    )
    expect(getWarningText({ thresholds, percent: 56 })).toContain(
      'It anchors itself at the end of this turn, or, while its background work runs, at the end of a later turn within 5 min. Tell',
    )
    expect(getWarningText({ thresholds: { ...thresholds, save: null }, percent: 47 })).not.toContain('Drain is on')
  })

  test('say the wait, the unchecked work and the reload to the user', () => {
    expect(getWaitLine(2, 5)).toBe('anchoring waits for 2 background jobs, up to 5 min (drain).')
    expect(getWaitLine(1, 10)).toBe('anchoring waits for 1 background job, up to 10 min (drain).')
    expect(UNCHECKED_LINE).toBe('background work could not be checked (drain).')
    expect(RELOADED_WAIT_LINE).toBe('anchoring waited for background work and the plugin reloaded; say "anchor" to save.')
    expect(WAIT_CANCELLED).toBe('wait cancelled')
  })

  test('put the minutes of the round into the stage file, null while the drain is off', () => {
    const state = { id: 's', cwd: '/w', stage: 'waiting', warnRound: 1, saveRound: 1, percent: 56, reason: null, marker: null }

    expect(createStageRecord({ ...state, thresholds: DEFAULTS, drainMinutes: 5 }, 0).drain_minutes).toBe(5)
    expect(createStageRecord({ ...state, thresholds: DEFAULTS, drainMinutes: null }, 0).drain_minutes).toBe(null)
  })
})

describe('refusing background work after the warning', () => {
  test('refuses the listed calls before next and lets every other call run', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWarned(scene)

    const denied = []
    for (const input of DENIED_CALLS) denied.push(await callOnce(scene, input))
    const passed = []
    for (const input of PASSED_CALLS) passed.push(await callOnce(scene, input))

    expect(denied).toEqual(DENIED_CALLS.map(() => ({ deny: DENY_TEXT, isAnswered: false })))
    expect(passed).toEqual(PASSED_CALLS.map(() => ({ deny: undefined, isAnswered: true })))
  })

  test('refuses a call from inside a subagent', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWarned(scene)

    const inner = await callOnce(scene, { ...BACKGROUND_BASH, agentId: 'agent-1' })
    const plain = await callOnce(scene, { tool: 'Bash', command: 'echo hi', agentId: 'agent-1' })

    expect(inner).toEqual({ deny: DENY_TEXT, isAnswered: false })
    expect(plain).toEqual({ deny: undefined, isAnswered: true })
  })

  test('refuses nothing before the warning', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.start()
    await scene.startTurn(10)

    expect(await callOnce(scene, AGENT)).toEqual({ deny: undefined, isAnswered: true })
  })

  test('reads the toggle in each call: off, no file, a broken file or no anchor threshold refuse nothing', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { drain: false })
    await startWarned(scene)

    const off = await callOnce(scene, AGENT)
    useFile(scene)
    const on1 = await callOnce(scene, AGENT)
    useFile(scene, { save_percent: null })
    const noSave = await callOnce(scene, AGENT)
    scene.world.setFile(THRESHOLDS, 'not json')
    const broken = await callOnce(scene, AGENT)
    scene.world.files.delete(THRESHOLDS)
    const none = await callOnce(scene, AGENT)

    expect(off.deny).toBe(undefined)
    expect(on1.deny).toBe(DENY_TEXT)
    expect(noSave.deny).toBe(undefined)
    expect(broken.deny).toBe(undefined)
    expect(none.deny).toBe(undefined)
  })

  test('ends with the window below the lowest threshold, as after a compaction, and starts again with the next warning', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWarned(scene)

    await scene.callTool(30, READ)
    const after = await callOnce(scene, AGENT)
    await scene.callTool(47, READ)
    const again = await callOnce(scene, AGENT)

    expect(after.deny).toBe(undefined)
    expect(again.deny).toBe(DENY_TEXT)
    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', warn_round: 2 })
  })

  test('refuses nothing while the anchor threshold is not armed', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { save_percent: null })
    await startWarned(scene)
    useFile(scene)

    expect(await callOnce(scene, AGENT, 60)).toEqual({ deny: undefined, isAnswered: true })
  })

  test('lets the call go on when the drain check fails', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWarned(scene)
    scene.world.sessionIdDenials = 1

    expect(await callOnce(scene, AGENT)).toEqual({ deny: undefined, isAnswered: true })
  })

  test('tells the model about the drain in the warning', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.start()
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    await scene.startTurn(47)

    const out = await scene.callTool(47, READ)

    expect(out.context.at(-1)).toContain('at the end of a later turn within 5 min. ')
    expect(out.context.at(-1)).toContain('Drain is on:')
    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', drain_minutes: 5 })
  })
})

describe('waiting at the anchor threshold', () => {
  test('two running jobs: no request, the line, waiting with round 1 and the minutes, refusals go on', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)

    await startWaiting(scene)
    await scene.startTurn(57)
    const call = await callOnce(scene, AGENT, 57)

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([getWaitLine(2, 5)])
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', save_round: 1, warn_round: 1, drain_minutes: 5, percent: 56 })
    expect(call.deny).toBe(DENY_TEXT)
  })

  test('the jobs ended: the request with the list of the rest, round 1 kept, once', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)

    await endTurnWith(scene, { percent: 57, tasks: OTHERS })
    await endTurnWith(scene, { percent: 58, tasks: OTHERS })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs).toEqual([
      getWaitLine(2, 5),
      REQUEST_57,
    ])
    expect(getStages(scene)).toEqual([
      ['warned', 0, 5],
      ['waiting', 1, 5],
      ['requested', 1, 5],
    ])
  })

  test('the deadline passed while a job runs: the request and the whole list, round not raised', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)

    await endTurnWith(scene, { percent: 57, tasks: HOLDERS, waitMs: 4 * MINUTE })
    const before = [...scene.world.runs]
    await endTurnWith(scene, { percent: 57, tasks: HOLDERS, waitMs: 2 * MINUTE })

    expect(before).toEqual([])
    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1, drain_minutes: 5 })
  })

  test('a save that failed for a reason the next turn can fix runs again past the deadline, without a new wait', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    await endTurnWith(scene, { percent: 57, tasks: HOLDERS, waitMs: 6 * MINUTE })
    await scene.runAnchorTurn({ steps: [] })

    await endTurnWith(scene, { percent: 57, tasks: HOLDERS })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'hats:anchor',
    ])
    expect(scene.world.logs.filter((line: string) => line.startsWith('anchoring waits'))).toEqual([getWaitLine(2, 5)])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 2 })
  })

  test('gives the list in the first result of the anchor turn that is not refused, and only there', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    await endTurnWith(scene, { percent: 57, tasks: [...HOLDERS, ...SERVICE], waitMs: 6 * MINUTE })
    const outs: any[] = []
    const record = (step: () => Promise<any>) => async () => outs.push(await step())

    await scene.runAnchorTurn({ steps: getSaveSteps(scene).map(record) })

    expect(outs.map(out => out.context ?? [])).toEqual([
      [getList([...HOLDERS, ...SERVICE])],
      [],
      [],
      [],
      [],
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', save_round: 1 })
  })

  test('no holding job at the threshold: the request at once with the list of the others', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.setSnapshot({ tasks: [...OTHERS, ...SERVICE] })

    await scene.endTurn(turnId, { percent: 56 })
    const outs: any[] = []
    await scene.runAnchorTurn({ steps: [async () => outs.push(await scene.callTool(57, READ))] })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs[0]).toBe(REQUEST_56)
    expect(outs[0].context).toEqual([getList([...OTHERS, ...SERVICE])])
  })

  test('no job at all: the request at once and no list', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.setSnapshot({ tasks: [] })

    await scene.endTurn(turnId, { percent: 56 })
    const outs: any[] = []
    await scene.runAnchorTurn({ steps: [async () => outs.push(await scene.callTool(57, READ))] })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(outs[0].context ?? []).toEqual([])
  })

  test('the drain off at the threshold: the request at once, as before, with no snapshot read', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { drain: false })
    const turnId = await startWarned(scene)

    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs).toEqual([REQUEST_56])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1, drain_minutes: null })
  })

  test('a monitor shell holds the wait; a teammate, a socket monitor and service work do not', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.setSnapshot({ tasks: [{ id: 'mon1', type: 'shell', status: 'running', description: 'm7 monitor command' }, ...OTHERS] })
    await scene.endTurn(turnId, { percent: 56 })
    const waited = [...scene.world.runs]

    await endTurnWith(scene, { percent: 57, tasks: [...OTHERS, ...SERVICE] })

    expect(waited).toEqual([])
    expect(scene.world.logs[0]).toBe(getWaitLine(1, 5))
    expect(scene.world.runs).toEqual(['hats:anchor'])
  })

  test('no snapshot written in the turn: the request at once and the unchecked line', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)

    await waitOutSnapshot(scene, turnId, 56)

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs).toEqual([
      UNCHECKED_LINE,
      REQUEST_56,
    ])
  })

  test('a turn without tools takes only a snapshot written after its start', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    const turnId = await scene.startTurn(57)

    await waitOutSnapshot(scene, turnId, 57)

    expect(scene.world.logs).toEqual([
      getWaitLine(2, 5),
      UNCHECKED_LINE,
      REQUEST_57,
    ])
  })

  test('a turn without tools and a snapshot after its start goes on waiting', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)

    await endTurnWith(scene, { percent: 57, tasks: HOLDERS })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([getWaitLine(2, 5)])
  })

  test('a snapshot that could not list the work, over 200 jobs: unchecked', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.setSnapshot({ ok: false, tasks: [] })

    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.logs).toEqual([
      UNCHECKED_LINE,
      REQUEST_56,
    ])
  })

  test('a broken snapshot file: unchecked', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.world.setFile(SNAPSHOT, '{')

    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.logs).toEqual([
      UNCHECKED_LINE,
      REQUEST_56,
    ])
  })

  test('the minutes changed after the first wait: the deadline stays', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    useFile(scene, { drain_minutes: 60 })

    await endTurnWith(scene, { percent: 57, tasks: HOLDERS, waitMs: 6 * MINUTE })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1, drain_minutes: 5 })
  })

  test('the drain switched off while waiting: the request at once, round kept', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    useFile(scene, { drain: false })

    await endTurnWith(scene, { percent: 57, tasks: HOLDERS })

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1, drain_minutes: null })
  })

  test('the drain switched off and on between turn ends: no refusal while off, the deadline stays', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    const turnId = await scene.startTurn(57)
    useFile(scene, { drain: false })
    const off = await callOnce(scene, AGENT, 57)
    useFile(scene, { drain_minutes: 30 })
    await scene.world.clock.advance(6 * MINUTE)
    scene.setSnapshot({ tasks: HOLDERS })

    await scene.endTurn(turnId, { percent: 57 })

    expect(off.deny).toBe(undefined)
    expect(scene.world.runs).toEqual(['hats:anchor'])
  })

  test('the anchor threshold raised while waiting: no request, warned with the same round, the next round a new number', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    useFile(scene, { save_percent: 70 })

    await endTurnWith(scene, { percent: 57, tasks: HOLDERS })
    const cancelled = scene.world.getStage()
    await endTurnWith(scene, { percent: 71, tasks: HOLDERS })

    expect(cancelled).toMatchObject({ stage: 'warned', save_round: 1, reason: WAIT_CANCELLED })
    expect(scene.world.runs).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', save_round: 2 })
    expect(scene.world.logs).toEqual([
      getWaitLine(2, 5),
      getWaitLine(2, 5),
    ])
  })

  test('the anchor threshold raised during a turn: the wait is cancelled at its end, not at the next event', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    const turnId = await scene.startTurn(57)
    useFile(scene, { save_percent: 70 })
    scene.setSnapshot({ tasks: HOLDERS })

    await scene.endTurn(turnId, { percent: 57 })

    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', save_round: 1, reason: WAIT_CANCELLED })
  })

  test('the anchor threshold switched off while waiting: the wait is cancelled and nothing is refused', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    useFile(scene, { save_percent: null })

    await endTurnWith(scene, { percent: 57, tasks: HOLDERS })
    await scene.startTurn(57)
    const call = await callOnce(scene, AGENT, 57)

    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', save_round: 1, reason: WAIT_CANCELLED })
    expect(call.deny).toBe(undefined)
  })

  test('a compaction while waiting cancels the wait and ends the refusals', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    await scene.startTurn(57)

    await scene.callTool(20, READ)
    const call = await callOnce(scene, AGENT, 20)

    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', save_round: 1, reason: WAIT_CANCELLED })
    expect(call.deny).toBe(undefined)
  })

  test('a manual anchor while waiting is taken as before and ends the round', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    const turnId = await scene.startTurn(57)
    for (const step of getSaveSteps(scene)) await step()

    await scene.endTurn(turnId, { percent: 58 })
    await scene.startTurn(58)
    const call = await callOnce(scene, AGENT, 58)

    await scene.end('clear')

    expect(scene.world.runs).toEqual([])
    expect(scene.world.getStage(STAGE_FILE)).toMatchObject({ stage: 'saved', reason: 'manual', save_round: 1 })
    expect(call.deny).toBe(undefined)
  })

  test('the window passing both thresholds in one turn waits without a warning, and never warns after', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.start()
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    const turnId = await scene.startTurn(10)
    scene.setSnapshot({ tasks: HOLDERS })
    await scene.endTurn(turnId, { percent: 56 })

    await scene.startTurn(57)
    const out = await scene.callTool(57, READ)
    const call = await callOnce(scene, AGENT, 57)

    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', save_round: 1, warn_round: 0 })
    expect(out.context ?? []).toEqual([])
    expect(call.deny).toBe(DENY_TEXT)
  })

  test('a reload while waiting: interrupted and the line', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    scene.world.setFile(STAGE_FILE, JSON.stringify({ session: SESSION, stage: 'waiting', warn_round: 1, save_round: 1, percent: 56 }))

    await scene.start()

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: 'plugin reloaded', save_round: 1 })
    expect(scene.world.logs).toEqual([RELOADED_WAIT_LINE])
  })

  test('a session change while waiting, with session.end: interrupted, nothing else', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)

    await scene.end('clear')

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: 'session changed', save_round: 1 })
    expect(scene.world.runs).toEqual([])
  })

  test('a session change while waiting, without session.end: interrupted at the next event', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    scene.world.sessionId = OTHER_SESSION

    await scene.startTurn(57)

    expect(scene.world.getStage(STAGE_FILE)).toMatchObject({ stage: 'interrupted', reason: 'session changed', save_round: 1 })
    expect(scene.world.runs).toEqual([])
  })

  test('a session change while the snapshot is awaited: no wait and no request', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.world.clock.sleep(1000).then(() => {
      scene.world.sessionId = OTHER_SESSION
    })

    await waitOutSnapshot(scene, turnId, 56)

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([])
  })
})

describe('the gaps the matrix check found', () => {
  test('no refusal once the request is given, nor after the anchor turn when the anchor threshold is armed again', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    await endTurnWith(scene, { percent: 57, tasks: OTHERS })
    await scene.startTurn(57)
    const asked = await callOnce(scene, AGENT, 57)
    await scene.runAnchorTurn({ steps: getSaveSteps(scene) })

    await scene.startTurn(58)
    await scene.callTool(50, READ)
    const armed = await callOnce(scene, AGENT, 50)

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(asked).toEqual({ deny: undefined, isAnswered: true })
    expect(armed).toEqual({ deny: undefined, isAnswered: true })
  })

  test('a failed drain check in the anchor turn lets the call go and fails the anchor as a plugin hook failure', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    await endTurnWith(scene, { percent: 57, tasks: OTHERS })
    const calls: any[] = []
    const failing = async () => {
      scene.world.sessionIdDenials = 1
      calls.push(await callOnce(scene, AGENT, 57))
    }

    await scene.runAnchorTurn({ steps: [failing, ...getSaveSteps(scene)] })

    expect(calls).toEqual([{ deny: undefined, isAnswered: true }])
    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'a plugin hook failed', save_round: 1 })
  })

  test('entering the wait drops the warning text not yet told', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await scene.start()
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 10 })
    const warned = await scene.startTurn(10)
    await scene.endTurn(warned, { percent: 47 })
    await scene.prompt('/compact', { name: 'compact', args: '' })
    const turnId = await scene.startTurn(47)
    scene.setSnapshot({ tasks: HOLDERS })
    await scene.endTurn(turnId, { percent: 56 })

    await scene.prompt('go on')

    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', warn_round: 1, save_round: 1 })
    expect(scene.world.prompts.at(-1).context ?? []).toEqual([])
  })

  test('a cancelled wait forgets its deadline: the next wait starts its own', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    useFile(scene, { save_percent: 70 })
    await endTurnWith(scene, { percent: 57, tasks: HOLDERS })

    await endTurnWith(scene, { percent: 71, tasks: HOLDERS, waitMs: 6 * MINUTE })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', save_round: 2 })
    expect(scene.world.logs).toEqual([
      getWaitLine(2, 5),
      getWaitLine(2, 5),
    ])
  })

  test('a session change while a waiting session awaits its snapshot: no request, interrupted at the next event', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    const turnId = await scene.startTurn(57)
    scene.world.clock.sleep(1000).then(() => {
      scene.world.sessionId = OTHER_SESSION
    })

    await waitOutSnapshot(scene, turnId, 57)
    await scene.startTurn(10)

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([getWaitLine(2, 5)])
    expect(scene.world.getStage(STAGE_FILE)).toMatchObject({ stage: 'interrupted', reason: 'session changed', save_round: 1 })
  })

  test('a snapshot over 64 KB cannot be checked: the request at once and the line', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.setSnapshot({ tasks: [{ ...HOLDERS[0], description: 'x'.repeat(70000) }] })

    await waitOutSnapshot(scene, turnId, 56)

    expect(scene.world.runs).toEqual(['hats:anchor'])
    expect(scene.world.logs).toEqual([
      UNCHECKED_LINE,
      REQUEST_56,
    ])
  })

  test('an idle session past its deadline: nothing happens until the next turn ends', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)

    await scene.world.clock.advance(6 * MINUTE)
    await scene.world.clock.settle()
    const idle = { runs: [...scene.world.runs], logs: [...scene.world.logs] }
    await endTurnWith(scene, { percent: 57, tasks: HOLDERS })

    expect(idle).toEqual({ runs: [], logs: [getWaitLine(2, 5)] })
    expect(scene.world.runs).toEqual(['hats:anchor'])
  })

  test('the list goes to the first result of the anchor turn that is not refused', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    await startWaiting(scene)
    await endTurnWith(scene, { percent: 57, tasks: OTHERS })
    const outs: any[] = []
    const refused = async () => {
      scene.world.nextToolAnswer = { deny: 'refused below' }
      outs.push(await scene.callTool(57, READ))
    }
    const plain = async () => outs.push(await scene.callTool(57, READ))

    await scene.runAnchorTurn({ steps: [refused, plain, plain] })

    expect(outs.map(out => [out.deny, out.context ?? []])).toEqual([
      ['refused below', []],
      [undefined, [getList(OTHERS)]],
      [undefined, []],
    ])
  })

  test('an Esc refusal of the own request gives back the waiting round, its deadline and its minutes', () => {
    const round = { isWaiting: true, deadline: 1794935700000, minutes: 5 }
    const previous = {
      stage: 'waiting',
      reason: null,
      marker: null,
      saveRound: 1,
      percent: 56,
      thresholds: { warn: 45, save: 55, after: 'tell', drain: true, drainMinutes: 5 },
      drainMinutes: 5,
      drain: round,
    }

    const outcome = findRefusalOutcome(`hats: $.command.run: ${STOPPED}`, previous)

    expect(outcome).toEqual({ kind: 'stopped', fields: previous, isSaveArmed: true })
    expect(outcome.kind === 'stopped' && outcome.fields.drain).toBe(round)
  })
})

describe('the review findings', () => {
  test('a subagent call ending after the snapshot does not make it stale: the session waits', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene)
    const turnId = await startWarned(scene)
    scene.setSnapshot({ tasks: [{ id: 'sub1', type: 'subagent', status: 'running', description: 'review' }] })
    await scene.world.clock.advance(100)
    await scene.callTool(47, { tool: 'Bash', command: 'echo hi', agentId: 'agent-1' })

    await waitOutSnapshot(scene, turnId, 56)

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([getWaitLine(1, 5)])
    expect(scene.world.getStage()).toMatchObject({ stage: 'waiting', save_round: 1 })
  })

  test('a call that reads the window below the lowest threshold is not refused, in the session and in a subagent', async ($, on) => {
    const main = createScene($, { on })
    useFile(main)
    await startWarned(main)

    const inSession = await callOnce(main, AGENT, 30)
    await main.callTool(47, READ)
    await main.callTool(47, READ)
    const inSubagent = await callOnce(main, { ...AGENT, agentId: 'agent-1' }, 30)

    expect(inSession).toEqual({ deny: undefined, isAnswered: true })
    expect(inSubagent).toEqual({ deny: undefined, isAnswered: true })
  })

  test('the request keeps the waiting round, so an Esc refusal gives back its deadline and minutes', () => {
    const round = { isWaiting: true, deadline: 1794935700000, minutes: 5 }
    const state = {
      stage: 'waiting',
      reason: null,
      marker: null,
      saveRound: 1,
      percent: 56,
      thresholds: { warn: 45, save: 55, after: 'tell', drain: true, drainMinutes: 5 },
      drainMinutes: 5,
      drain: round,
    }

    const outcome = findRefusalOutcome(STOPPED, createPrevious(state))

    expect(outcome.kind).toBe('stopped')
    expect(outcome.kind === 'stopped' && outcome.fields.drain).toBe(round)
    expect(outcome.kind === 'stopped' && outcome.fields.drainMinutes).toBe(5)
    expect(round).toEqual({ isWaiting: true, deadline: 1794935700000, minutes: 5 })
  })
})

describe('the drain with the automatic clear', () => {
  test('after the wait the note names the listed work and the session clears', async ($, on) => {
    const scene = createScene($, { on })
    useFile(scene, { after_save: 'clear' })
    await startWaiting(scene)
    await endTurnWith(scene, { percent: 57, tasks: HOLDERS, waitMs: 6 * MINUTE })
    const note = `${NOTE_TEXT}\nrunning: b1shell, a2agent\n`
    const steps = [
      ...getSaveSteps(scene, note),
      async () => scene.setSnapshot({ tasks: HOLDERS }),
    ]

    await scene.runAnchorTurn({ steps })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'clear',
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'cleared', save_round: 1 })
    expect(scene.world.files.has(`${STAGES}/${NEXT_SESSION}.json`)).toBe(false)
  })

  test('the pause after an own clear drops the warning when both thresholds pass in one turn', async ($, on) => {
    const scene = createScene($, { on })
    await clearOnce(scene)
    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 30 })
    const high = await scene.startTurn(30)
    await scene.endTurn(high, { percent: 56 })

    await scene.startTurn(57)
    const out = await scene.callTool(57, READ)

    expect(scene.world.logs.at(-1)).toContain('not anchoring within 10 minutes of the last automatic clear')
    expect(out.context ?? []).toEqual([])
    expect(scene.world.getStage(`${STAGES}/${NEXT_SESSION}.json`)).toBe(null)
  })

  test('the pause after an own clear drops the unsaid warning', async ($, on) => {
    const scene = createScene($, { on })
    await clearOnce(scene)
    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 30 })
    const warned = await scene.startTurn(30)
    await scene.endTurn(warned, { percent: 47 })
    await scene.prompt('/compact', { name: 'compact', args: '' })
    const paused = await scene.startTurn(47)
    await scene.endTurn(paused, { percent: 56 })

    await scene.prompt('go on')

    expect(scene.world.logs.at(-1)).toContain('not anchoring within 10 minutes of the last automatic clear')
    expect(scene.world.prompts.at(-1).context ?? []).toEqual([])
  })

  test('the pause after an own clear ends the round: no refusal once the anchor threshold is armed again', async ($, on) => {
    const scene = createScene($, { on })
    await clearOnce(scene)
    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 30 })
    const turnId = await scene.startTurn(30)
    await scene.callTool(47, READ)
    await scene.endTurn(turnId, { percent: 56 })
    await scene.startTurn(56)

    await scene.callTool(50, READ)
    const call = await callOnce(scene, AGENT, 50)

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'clear',
    ])
    expect(call.deny).toBe(undefined)
  })
})
