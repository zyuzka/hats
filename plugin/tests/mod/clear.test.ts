import { describe, expect, test } from 'claude-code/testing'
import {
  HANDED,
  MARKER,
  NEXT_SESSION,
  NOTE,
  NOTE_TEXT,
  OTHER_SESSION,
  SESSION,
  SNAPSHOT,
  SNAPSHOTS,
  STAGES,
  THRESHOLDS,
  createScene,
} from './world.ts'

const REQUEST_56 = 'context 56% (anchor threshold 55%) — anchoring this session.'
const CLEARING = 'anchored at 56% — clearing the context; the session goes on from its note.'
const CONTINUE =
  'Hats: this session reached 56% of its context window, was anchored and cleared. ' +
  'Continue the task from the resume note the plugin gave you after /clear: read the whole note with the Read tool, ' +
  'tell the user in one short line, in their language, which note you picked up, then go on with its next step.'
const NOT_BACK = `cleared, but the note did not come back to this session; it is at ${NOTE}.`
const SEND_YOURS = 'cleared; the note is in context — send your message.'
const PAUSED =
  'context 56% (anchor threshold 55%): not anchoring within 10 minutes of the last automatic clear. Say "anchor" to save.'
const AFTER_STEPS = 'before anchor:\n1. [general] say hi\nafter anchor:\n1. [general] push the branch\n'
const NO_AFTER_STEPS = 'before anchor:\n1. [general] say hi\nafter anchor: none\n'
const ANCHOR_AND_CLEAR = [
  'hats:anchor',
  'clear',
]
const ANCHOR_ONLY = [
  'hats:anchor',
]
const OTHER_ORIGINS = [
  { kind: 'scheduled-trigger' },
  { kind: 'peer' },
  { kind: 'channel', server: 'slack' },
]
const ANCHORED = 'anchored at 56% of the context window (threshold 55%).'
const OTHER_ACTIONS = [
  { after: 'tell', line: ANCHORED },
  { after: 'offer_exit', line: `${ANCHORED} Type /exit and start claude again in this folder: the new session lists this note.` },
]
const TWO_UNNAMED = [
  { id: 'b7x3k9', type: 'shell', status: 'running', description: 'sleep 300' },
  { id: 'c8y4l0', type: 'subagent', status: 'running', description: 'review' },
]
const PENDING = [
  { id: 'p1q2r3', type: 'shell', status: 'pending', description: 'queued' },
]
const BACKGROUND = [
  {
    id: 'b7x3k9',
    type: 'shell',
    status: 'running',
    description: 'sleep 300',
  },
]

const PIPED_TAILS = [
  ' | grep -v after',
  ' > /tmp/steps.txt',
  '; echo done',
]
const KEPT_WRITES = [
  'requested',
  'saved',
  'kept',
]

const getStageOrder = (scene: any) => scene.world.getStageWrites().map((write: any) => write.stage)

const getKept = (reason: string) =>
  `anchored at 56%, not cleared: ${reason}. Type /clear when ready: the plugin gives the note back.`

const useClear = (scene: any, fields: Record<string, unknown> = {}) =>
  scene.world.setFile(THRESHOLDS, JSON.stringify({ warn_percent: 45, save_percent: 55, after_save: 'clear', ...fields }))

const getSaveSteps = (scene: any, note = NOTE_TEXT) => [
  () => scene.runSteps(),
  scene.createNote,
  () => scene.writeNote(note),
  scene.runSave,
  () => scene.runSteps(),
]

const getClearSteps = (scene: any, snapshot: Record<string, unknown> = {}) => [
  ...getSaveSteps(scene),
  async () => scene.setSnapshot(snapshot),
]

const getContinuations = (scene: any) => scene.world.prompts.filter((prompt: any) => prompt.text === CONTINUE)

const clearWith = async (scene: any, steps: (() => Promise<unknown>)[]) => {
  useClear(scene)
  await scene.askToAnchor()
  await scene.runAnchorTurn({ steps })
}

const keptWith = async (scene: any, failure: { steps: (() => Promise<unknown>)[]; reason: string }) => {
  await clearWith(scene, failure.steps)
  expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: failure.reason, save_round: 1 })
  expect(scene.world.logs).toEqual([
    REQUEST_56,
    getKept(failure.reason),
  ])
  expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  expect(getContinuations(scene)).toEqual([])
}

const holdWithoutSnapshot = async (scene: any) => {
  useClear(scene)
  await scene.askToAnchor()

  return scene.holdAnchorTurn({ steps: getSaveSteps(scene) })
}

describe('clearing after an anchor on the threshold', () => {
  test('all checks pass: the line, cleared in the old file, /clear, then the plugin prompt as the user', async ($, on) => {
    const scene = createScene($, { on })

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
    ])
    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
    expect(scene.world.getStage()).toMatchObject({ stage: 'cleared', save_round: 1, after_save: 'clear', session: SESSION })
    expect(getContinuations(scene).map((prompt: any) => prompt.origin)).toEqual([
      { kind: 'plugin', name: 'hats', asUser: true },
    ])
    expect(scene.world.files.has(`${STAGES}/${NEXT_SESSION}.json`)).toBe(false)
  })

  test('the stage goes saved, then cleared, in the old session file', async ($, on) => {
    const scene = createScene($, { on })

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.getStageWrites().map((write: any) => write.stage)).toEqual([
      'requested',
      'saved',
      'cleared',
    ])
  })

  test('a manual anchor past the threshold saves and never clears', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.start()
    const turnId = await scene.startTurn(10)
    for (const step of getClearSteps(scene)) await step()

    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', reason: 'manual' })
    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([])
  })

  test('the offer_clear action only offers', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene, { after_save: 'offer_clear' })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  for (const action of OTHER_ACTIONS) {
    test(`the ${action.after} action says its line and never clears`, async ($, on) => {
      const scene = createScene($, { on })
      useClear(scene, { after_save: action.after })
      await scene.askToAnchor()

      await scene.runAnchorTurn({ steps: getClearSteps(scene) })

      expect(scene.world.runs).toEqual(ANCHOR_ONLY)
      expect(scene.world.logs).toEqual([
        REQUEST_56,
        action.line,
      ])
      expect(scene.world.getStage()).toMatchObject({ stage: 'saved', after_save: action.after })
    })
  }

  test('a failed save does not clear: new made an empty note, the Write was denied, save passed', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    const denied = async () => {
      scene.world.nextToolAnswer = { deny: 'no' }
      await scene.writeNote()
    }

    const steps = [
      () => scene.runSteps(),
      scene.createNote,
      denied,
      scene.runSave,
      async () => scene.setSnapshot(),
    ]

    await scene.runAnchorTurn({ steps })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the note was not rewritten in this anchor' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })
})

describe('input during anchoring', () => {
  test('the user wrote during the anchor turn: kept, with the kind', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getClearSteps(scene),
      () => scene.prompt('and one more thing'),
    ]

    await keptWith(scene, { steps, reason: 'input arrived during anchoring (composer)' })
  })

  test('input before the request does not count', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.start()
    await scene.prompt('do the task')
    const turnId = await scene.startTurn(10)
    await scene.endTurn(turnId, { percent: 56 })

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
  })

  test('a background notice between the request and the anchor turn: kept', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    await $.prompt.submit({ text: '<task-notification/>', wait: false, origin: { kind: 'task-notification' } })

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'input arrived during anchoring (task-notification)' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getKept('input arrived during anchoring (task-notification)'),
    ])
  })

  for (const origin of OTHER_ORIGINS) {
    test(`input of the kind ${origin.kind} during the anchor turn: kept, with the kind`, async ($, on) => {
      const scene = createScene($, { on })
      const steps = [
        ...getClearSteps(scene),
        () => $.prompt.submit({ text: 'from elsewhere', wait: false, origin }),
      ]

      await keptWith(scene, { steps, reason: `input arrived during anchoring (${origin.kind})` })
    })
  }

  test('another plugin counts as input', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getClearSteps(scene),
      () => scene.pluginPrompt('other'),
    ]

    await keptWith(scene, { steps, reason: 'input arrived during anchoring (plugin)' })
  })

  test('an origin of another shape: kept as unexpected input', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getClearSteps(scene),
      () => $.prompt.submit({ text: 'x', wait: false, origin: { kind: 7 } }),
    ]

    await keptWith(scene, { steps, reason: 'unexpected input from Claude Code' })
  })

  test('a draft in the prompt: kept', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.box = { text: 'half a thought', cursor: 14 }

    await keptWith(scene, { steps: getClearSteps(scene), reason: 'a draft is in the prompt' })
  })

  test('a prompt of spaces is no draft', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.box = { text: '  \n ', cursor: 0 }

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
  })

  test('the prompt read as {}: kept as unexpected input', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.box = {}

    await keptWith(scene, { steps: getClearSteps(scene), reason: 'unexpected input from Claude Code' })
  })

  test('the prompt read with a text that is a number: kept as unexpected input', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.box = { text: 5 }

    await keptWith(scene, { steps: getClearSteps(scene), reason: 'unexpected input from Claude Code' })
  })

  test('a session id that is not a string: kept as unexpected input', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onBoxRead = async () => {
      scene.world.sessionId = undefined as unknown as string
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'unexpected input from Claude Code' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getKept('unexpected input from Claude Code'),
    ])
  })
})

describe('own steps', () => {
  test('after steps in the anchor: kept', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getClearSteps(scene),
      () => scene.runSteps(AFTER_STEPS),
    ]

    await keptWith(scene, { steps, reason: 'own after-steps ran' })
  })

  test('after anchor: none clears', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      () => scene.runSteps(NO_AFTER_STEPS),
      ...getClearSteps(scene).slice(1),
    ]

    await clearWith(scene, steps)

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
  })

  test('no output of the steps command in the anchor turn: kept', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      scene.createNote,
      () => scene.writeNote(),
      scene.runSave,
      async () => scene.setSnapshot(),
    ]

    await keptWith(scene, { steps, reason: 'own steps could not be read' })
  })

  for (const tail of PIPED_TAILS) {
    test(`the steps command with "${tail.trim()}" after it: kept`, async ($, on) => {
      const scene = createScene($, { on })
      const steps = [
        ...getClearSteps(scene),
        () => scene.runSteps(NO_AFTER_STEPS, tail),
      ]

      await keptWith(scene, { steps, reason: 'own steps could not be read' })
    })
  }

  test('the steps command failed: kept', async ($, on) => {
    const scene = createScene($, { on })
    const failed = () => scene.runSteps('anchor-steps: OSError: boom\n')
    const steps = [
      ...getClearSteps(scene),
      failed,
    ]

    await keptWith(scene, { steps, reason: 'own steps could not be read' })
  })

  test('the steps command ended in an error: kept, whatever it printed', async ($, on) => {
    const scene = createScene($, { on })
    const errored = async () => {
      scene.world.nextToolAnswer = { result: { stdout: 'no own steps\n', stderr: 'boom' }, isError: true, text: 'Exit code 1' }
      await scene.callTool(58, { tool: 'Bash', command: scene.world.paths.stepsCommand })
    }
    const steps = [
      ...getClearSteps(scene),
      errored,
    ]

    await keptWith(scene, { steps, reason: 'own steps could not be read' })
  })
})

describe('the note and the plugin', () => {
  test('the note cannot be read after the save was checked: kept', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    scene.world.unreadableUntilWrite = NOTE
    scene.setSnapshot()
    await scene.world.clock.advance(300)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the note could not be read' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the note changed while the mod waited for the snapshot: kept', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await scene.world.clock.advance(300)
    scene.world.setFile(NOTE, `${NOTE_TEXT}\nanother writer\n`)
    scene.setSnapshot()
    await scene.world.clock.advance(300)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the note changed after this session wrote it' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the plugin files are asked for under the plugin root the engine names', async ($, on) => {
    const scene = createScene($, { on })

    await clearWith(scene, getClearSteps(scene))

    const asked = scene.world.existsAsked.filter((path: string) => path.endsWith('/scripts/handoff.py'))
    expect(asked.length).toBe(1)
    expect(asked[0].endsWith('/plugin/scripts/handoff.py')).toBe(true)
    expect(asked[0]).not.toBe('/plugin/scripts/handoff.py')
  })

  test('the plugin files cannot be looked at: kept', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.isExistsDenied = true

    await keptWith(scene, { steps: getClearSteps(scene), reason: 'the plugin files are not in place' })
  })

  test('the session runs with HANDOFF_OFF=1, so the note would not come back: kept, no /clear', async ($, on) => {
    const scene = createScene($, { on, env: { HANDOFF_OFF: '1' } })

    await keptWith(scene, { steps: getClearSteps(scene), reason: 'HANDOFF_OFF=1 keeps the note from coming back after /clear' })
  })

  test('the plugin files are gone: kept', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.isPluginGone = true

    await keptWith(scene, { steps: getClearSteps(scene), reason: 'the plugin files are not in place' })
  })
})

describe('the background work at the end of the anchor turn', () => {
  test('work the note names: the clear goes on', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getSaveSteps(scene, `${NOTE_TEXT}\n- b7x3k9: sleep 300, waits for nothing\n`),
      async () => scene.setSnapshot({ tasks: BACKGROUND }),
    ]

    await clearWith(scene, steps)

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
  })

  test('work the note does not name: kept, with its id', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getSaveSteps(scene),
      async () => scene.setSnapshot({ tasks: BACKGROUND }),
    ]

    await keptWith(scene, { steps, reason: 'background work not in the note: b7x3k9' })
  })

  test('the id x_1 is not named by x_10 in the note', async ($, on) => {
    const scene = createScene($, { on })
    const tasks = [
      { id: 'x_1', type: 'shell', status: 'running', description: '' },
    ]
    const steps = [
      ...getSaveSteps(scene, `${NOTE_TEXT}\n- x_10 runs\n`),
      async () => scene.setSnapshot({ tasks }),
    ]

    await keptWith(scene, { steps, reason: 'background work not in the note: x_1' })
  })

  test('two works the note does not name: kept, with both ids', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getSaveSteps(scene),
      async () => scene.setSnapshot({ tasks: TWO_UNNAMED }),
    ]

    await keptWith(scene, { steps, reason: 'background work not in the note: b7x3k9, c8y4l0' })
  })

  test('work in flight that is not running yet counts like running work', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getSaveSteps(scene),
      async () => scene.setSnapshot({ tasks: PENDING }),
    ]

    await keptWith(scene, { steps, reason: 'background work not in the note: p1q2r3' })
  })

  test('a scheduled wake-up: kept, with the count', async ($, on) => {
    const scene = createScene($, { on })

    await keptWith(scene, { steps: getClearSteps(scene, { crons: 2 }), reason: 'scheduled wake-ups: 2' })
  })

  test('a snapshot that could not check the work: kept', async ($, on) => {
    const scene = createScene($, { on })

    await keptWith(scene, { steps: getClearSteps(scene, { ok: false }), reason: 'background work could not be checked' })
  })

  test('a snapshot of another shape: kept as unexpected input', async ($, on) => {
    const scene = createScene($, { on })

    await keptWith(scene, { steps: getClearSteps(scene, { tasks: 'none' }), reason: 'unexpected input from Claude Code' })
  })

  test('no snapshot within 2 seconds: kept', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await scene.world.clock.advance(1900)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
    ])
    await scene.world.clock.advance(200)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'background work could not be checked' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a snapshot written within the 2 seconds is taken', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await scene.world.clock.advance(800)
    scene.setSnapshot()
    await scene.world.clock.advance(200)
    await held.done

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
  })

  test('a snapshot taken at the very end of the last tool call is not taken', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    const steps = [
      ...getSaveSteps(scene),
      async () => scene.setSnapshot({ at_ms: scene.world.clock.now() - 200 }),
    ]

    const held = await scene.holdAnchorTurn({ steps })
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'background work could not be checked' })
  })

  test('a snapshot one millisecond after the last tool call is taken', async ($, on) => {
    const scene = createScene($, { on })
    const steps = [
      ...getSaveSteps(scene),
      async () => scene.setSnapshot({ at_ms: scene.world.clock.now() - 199 }),
    ]

    await clearWith(scene, steps)

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
  })

  test('a subagent tool call that ends while the mod waits moves the bound: an older snapshot is not taken', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await scene.callTool(58, { tool: 'Read', file_path: '/w/a', agentId: 'agent-1' })
    scene.setSnapshot({ at_ms: scene.world.clock.now() - 201 })
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'background work could not be checked' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a broken snapshot left from an earlier turn does not stop the wait for the fresh one', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.setFile(SNAPSHOT, '{')

    const held = await scene.holdAnchorTurn({ steps: getSaveSteps(scene) })
    await scene.world.clock.advance(300)
    scene.setSnapshot()
    await scene.world.clock.advance(300)
    await held.done

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
  })

  test('a snapshot folder that is a link is not read through', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setLink(SNAPSHOTS, '/elsewhere/stop-snapshots')
    const held = await holdWithoutSnapshot(scene)

    scene.setSnapshot()
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'background work could not be checked' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('a snapshot folder that is a file is not read', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(SNAPSHOTS, 'not a folder')
    const held = await holdWithoutSnapshot(scene)

    scene.setSnapshot()
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'background work could not be checked' })
  })

  test('a Stop held back, new work, the last snapshot not written: the older snapshot is not taken', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    const steps = [
      ...getClearSteps(scene),
      () => scene.callTool(58, { tool: 'Bash', command: 'sleep 3' }),
    ]

    const held = await scene.holdAnchorTurn({ steps })
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'background work could not be checked' })
  })

  test('a tool call of a subagent after the snapshot makes it too old', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    const steps = [
      ...getClearSteps(scene),
      () => scene.callTool(58, { tool: 'Read', file_path: '/w/a', agentId: 'agent-1' }),
    ]

    const held = await scene.holdAnchorTurn({ steps })
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'background work could not be checked' })
  })
})

describe('a session change before the own /clear', () => {
  test('/resume while the mod waits for the snapshot: kept, and the own /clear never runs', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await scene.end('resume')
    scene.world.sessionId = OTHER_SESSION
    scene.setSnapshot()
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the session changed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getKept('the session changed'),
    ])
  })

  test('a /clear of the user while the mod waits for the snapshot: kept', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await scene.end('clear')
    scene.world.sessionId = OTHER_SESSION
    await scene.world.clock.advance(2100)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the session changed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getKept('the session changed'),
    ])
  })

  test('another session id seen without session.end while the mod waits: kept, no clearing line', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    scene.world.sessionId = OTHER_SESSION
    scene.setSnapshot()
    await scene.world.clock.advance(300)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the session changed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getKept('the session changed'),
    ])
  })
})

describe('the last check, when /clear runs', () => {
  test('input of the user after the checks and before /clear runs: /clear does not run', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onBoxRead = async count => {
      if (count === 2) await scene.prompt('wait, one more thing')
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'input arrived during anchoring (composer)' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      getKept('input arrived during anchoring (composer)'),
    ])
  })

  test('a draft typed after the checks: /clear does not run', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.boxes = [
      { text: '', cursor: 0 },
      { text: 'late', cursor: 4 },
    ]

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'a draft is in the prompt' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the check of the own /clear throws: /clear does not run, no prompt follows', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onBoxRead = async count => {
      if (count === 2) scene.world.sessionIdDenials = 1
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'a plugin hook failed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getContinuations(scene)).toEqual([])
  })

  test('the prompt read of another shape at the own /clear: /clear does not run', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.boxes = [
      { text: '', cursor: 0 },
      { text: 5 },
    ]

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'unexpected input from Claude Code' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the session is the same after the own /clear: kept', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.clearAnswer = 'same'

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the session did not change after /clear' })
    expect(getContinuations(scene)).toEqual([])
  })

  test('/clear refused beneath: kept with the refusal', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.clearAnswer = 'throw'

    await clearWith(scene, getClearSteps(scene))

    const reason = scene.world.getStage().reason
    expect(scene.world.getStage().stage).toBe('kept')
    expect(reason).toContain('the clear command was refused: ')
    expect(getContinuations(scene)).toEqual([])
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      getKept(reason),
    ])
  })

  test('the session changed without session.end when /clear runs: /clear does not run', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onBoxRead = async count => {
      if (count === 2) scene.world.sessionId = OTHER_SESSION
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the session changed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      getKept('the session changed'),
    ])
  })

  test('a /resume that lands when /clear runs: /clear does not run', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onBoxRead = async count => {
      if (count !== 2) return
      await scene.end('resume')
      scene.world.sessionId = OTHER_SESSION
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'the session changed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(getContinuations(scene)).toEqual([])
  })

  test('a /clear that ends the session while the own /clear waits leaves the decision to the run', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onStageWrite = async stage => {
      if (stage !== 'cleared') return
      scene.world.onStageWrite = null
      await scene.end('clear')
      scene.world.sessionId = OTHER_SESSION
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      getKept('the session changed'),
    ])
  })

  test('a reload of the mod before its /clear runs: the /clear is not run, a line says so, the stage is kept', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onStageWrite = async stage => {
      if (stage !== 'cleared') return
      scene.world.onStageWrite = null
      await scene.start()
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      getKept('plugin reloaded'),
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'plugin reloaded', percent: 56, save_round: 1 })
  })

  test('the own /clear the own hook never saw: a line after it, and no request within 10 minutes', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene, { warn_percent: null })
    await scene.askToAnchor()
    scene.world.onBoxRead = async count => {
      if (count === 1) await scene.start(false)
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })
    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      SEND_YOURS,
    ])
    await scene.start()
    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 52 })
    const high = await scene.startTurn(52)
    await scene.endTurn(high, { percent: 56 })

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
    expect(scene.world.logs.at(-1)).toBe(PAUSED)
  })

  test('the own /clear the own hook never saw left the session as it was: kept', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.clearAnswer = 'same'
    scene.world.onBoxRead = async count => {
      if (count === 1) await scene.start(false)
    }

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      getKept('the session did not change after /clear'),
    ])
  })

  test('a /clear raised by another, even with the plugin named in its origin, is not taken for the own one', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()

    await $.command.run({ command: 'clear', args: '', origin: { kind: 'plugin', name: 'hats' } })

    expect(scene.world.runs).toEqual([
      'clear',
    ])
  })

  test('a /clear of the user passes through', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()

    await $.command.run({ command: 'clear', args: '', origin: { kind: 'composer' } })

    expect(scene.world.runs).toEqual([
      'clear',
    ])
  })
})

describe('after the own /clear', () => {
  test('the note did not come back within 5 seconds: no prompt, a line with the path', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.isHandedBack = false
    await clearWith(scene, getClearSteps(scene))

    await scene.world.clock.advance(4900)
    expect(scene.world.logs.length).toBe(2)
    await scene.world.clock.advance(200)

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      NOT_BACK,
    ])
    expect(getContinuations(scene)).toEqual([])
  })

  test('the note came back to an older session only: no prompt', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onClear = async () => {
      scene.world.isHandedBack = false
      scene.world.setFile(HANDED, JSON.stringify({ key: 'x', session: NEXT_SESSION }))
    }
    await clearWith(scene, getClearSteps(scene))

    await scene.world.clock.advance(5200)

    expect(scene.world.logs.at(-1)).toBe(NOT_BACK)
    expect(getContinuations(scene)).toEqual([])
  })

  test('the note handed with the right key to the old session: no prompt', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onClear = async () => {
      scene.world.isHandedBack = false
      const { saved_at, note } = JSON.parse(scene.world.files.get(MARKER).text)
      scene.world.setFile(HANDED, JSON.stringify({ key: `${saved_at}|${note}`, session: SESSION }))
    }
    await clearWith(scene, getClearSteps(scene))

    await scene.world.clock.advance(5200)

    expect(scene.world.logs.at(-1)).toBe(NOT_BACK)
    expect(getContinuations(scene)).toEqual([])
  })

  test('the note handed a second after /clear: the prompt follows it', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.handedAfterMs = 1000
    await clearWith(scene, getClearSteps(scene))
    expect(getContinuations(scene)).toEqual([])

    await scene.world.clock.advance(1300)

    expect(getContinuations(scene).length).toBe(1)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
    ])
  })

  test('a draft after the clear: no prompt, a line', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.boxes = [
      { text: '', cursor: 0 },
      { text: '', cursor: 0 },
      { text: 'typed after', cursor: 11 },
    ]

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      SEND_YOURS,
    ])
    expect(getContinuations(scene)).toEqual([])
  })

  test('a message of the user after /clear and before the prompt: no prompt', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onClear = () => scene.prompt('hello after clear')

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.logs.at(-1)).toBe(SEND_YOURS)
    expect(getContinuations(scene)).toEqual([])
  })

  test('the plugin prompt dropped beneath: nothing more', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onClear = async () => {
      scene.world.dropNextPrompt = 'Esc'
    }

    await clearWith(scene, getClearSteps(scene))

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'cleared' })
  })

  test('the own prompt hook fails on the plugin prompt: dropped', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onBoxRead = async count => {
      if (count === 3) scene.world.sessionIdDenials = 1
    }

    await clearWith(scene, getClearSteps(scene))

    expect(getContinuations(scene)).toEqual([])
  })

  test('input that lands while the own prompt hook checks the plugin prompt: dropped, nothing more', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onBoxRead = async count => {
      if (count !== 3) return
      scene.world.onIdRead = async () => {
        scene.world.onIdRead = null
        await scene.prompt('typed just now')
      }
    }

    await clearWith(scene, getClearSteps(scene))

    expect(getContinuations(scene)).toEqual([])
    expect(scene.world.prompts.map((prompt: any) => prompt.text)).toContain('typed just now')
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
    ])
  })

  test('another hook of the mod fails between /clear and the prompt: no prompt, a line', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onClear = async () => {
      scene.world.sessionIdDenials = 1
      await $.tool.call({ tool: 'Read', file_path: '/w/a' })
    }

    await clearWith(scene, getClearSteps(scene))

    expect(getContinuations(scene)).toEqual([])
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      SEND_YOURS,
    ])
  })

  test('the own run hook fails once /clear ran: the note came back, a line, and no request within 10 minutes', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene, { warn_percent: null })
    await scene.askToAnchor()
    scene.world.onClear = async () => {
      scene.world.sessionIdDenials = 1
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })
    expect(getContinuations(scene)).toEqual([])
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      SEND_YOURS,
    ])
    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 52 })
    const high = await scene.startTurn(52)
    await scene.endTurn(high, { percent: 56 })

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
    expect(scene.world.logs.at(-1)).toBe(PAUSED)
  })

  test('the own run hook fails once /clear ran and the note did not come back: the line with the path', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.isHandedBack = false
    scene.world.onClear = async () => {
      scene.world.sessionIdDenials = 1
    }
    await clearWith(scene, getClearSteps(scene))

    await scene.world.clock.advance(5200)

    expect(getContinuations(scene)).toEqual([])
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
      NOT_BACK,
    ])
  })

  test('the session changes before the own prompt hook reads it: the plugin prompt is dropped', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.onBoxRead = async count => {
      if (count === 3) scene.world.sessionId = OTHER_SESSION
    }

    await clearWith(scene, getClearSteps(scene))

    expect(getContinuations(scene)).toEqual([])
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
    ])
  })

  test('a plugin prompt with no clear waiting is dropped', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()

    const out = await $.prompt.submit({ text: CONTINUE, wait: false, origin: { kind: 'plugin', name: 'hats', asUser: true } })

    expect(out.drop).toBe('hats: no clear of this plugin is waiting to go on')
    expect(scene.world.prompts).toEqual([])
  })

  test('a new session first seen past both thresholds stays unarmed', async ($, on) => {
    const scene = createScene($, { on })
    await clearWith(scene, getClearSteps(scene))

    const first = await scene.startTurn(undefined)
    await scene.endTurn(first, { percent: 58 })
    const next = await scene.startTurn(58)
    await scene.endTurn(next, { percent: 60 })

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      CLEARING,
    ])
    expect(scene.world.files.has(`${STAGES}/${NEXT_SESSION}.json`)).toBe(false)
  })

  test('the next turns of the new session repeat nothing', async ($, on) => {
    const scene = createScene($, { on })
    await clearWith(scene, getClearSteps(scene))

    const next = await scene.startTurn(undefined)
    await scene.endTurn(next, { percent: 30 })
    const later = await scene.startTurn(30)
    await scene.endTurn(later, { percent: 31 })

    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
    expect(scene.world.logs.length).toBe(2)
    expect(scene.world.files.has(`${STAGES}/${NEXT_SESSION}.json`)).toBe(false)
  })
})

describe('a failed hook while a clear is open', () => {
  test('a hook of the mod fails on input of the user while the mod waits: kept as a failed hook', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    scene.world.sessionIdDenials = 1
    await scene.prompt('x')
    scene.setSnapshot()
    await scene.world.clock.advance(300)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'a plugin hook failed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getKept('a plugin hook failed'),
    ])
    expect(getStageOrder(scene)).toEqual(KEPT_WRITES)
  })

  test('input of the user while the mod waits: kept before the clearing line, cleared never written', async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await scene.prompt('one more thing')
    scene.setSnapshot()
    await scene.world.clock.advance(300)
    await held.done

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'input arrived during anchoring (composer)' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getKept('input arrived during anchoring (composer)'),
    ])
    expect(getStageOrder(scene)).toEqual(KEPT_WRITES)
  })

  test('the end of the anchor turn outlasts its time waiting for the snapshot: kept, no /clear', { timeoutMs: 30000 }, async ($, on) => {
    const scene = createScene($, { on })
    const held = await holdWithoutSnapshot(scene)

    await held.done
    await scene.world.clock.settle()

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'a plugin hook failed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })

  test('the end of the anchor turn throws during the checks: kept, no /clear', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene)
    await scene.askToAnchor()
    scene.world.onBoxRead = async () => {
      scene.world.sessionIdDenials = 1
    }

    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'kept', reason: 'a plugin hook failed' })
    expect(scene.world.runs).toEqual(ANCHOR_ONLY)
  })
})

describe('ten minutes after an own clear', () => {
  test('no new request within 10 minutes, a line; after them, below 55 and at 56 again, a request', async ($, on) => {
    const scene = createScene($, { on })
    useClear(scene, { warn_percent: null })
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getClearSteps(scene) })

    const low = await scene.startTurn(undefined)
    await scene.endTurn(low, { percent: 52 })
    const high = await scene.startTurn(52)
    await scene.endTurn(high, { percent: 56 })
    expect(scene.world.runs).toEqual(ANCHOR_AND_CLEAR)
    expect(scene.world.logs.at(-1)).toBe(PAUSED)
    const again = await scene.startTurn(56)
    await scene.endTurn(again, { percent: 57 })
    expect(scene.world.logs.at(-1)).toBe(PAUSED)
    expect(scene.world.logs.filter((line: string) => line === PAUSED).length).toBe(1)

    await scene.world.clock.advance(10 * 60 * 1000)
    const below = await scene.startTurn(57)
    await scene.endTurn(below, { percent: 54 })
    const past = await scene.startTurn(54)
    await scene.endTurn(past, { percent: 56 })

    expect(scene.world.runs).toEqual([
      'hats:anchor',
      'clear',
      'hats:anchor',
    ])
    expect(scene.world.getStage(`${STAGES}/${NEXT_SESSION}.json`)).toMatchObject({ stage: 'requested', save_round: 1 })
  })
})
