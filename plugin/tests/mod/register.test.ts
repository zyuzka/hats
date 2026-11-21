import { describe, expect, test } from 'claude-code/testing'
import {
  MARKER,
  NOTE,
  NOTE_TEXT,
  OTHER_SESSION,
  STAGES,
  STAGE_FILE,
  THRESHOLDS,
  createBashResult,
  HOME,
  PLUGIN,
  SESSION,
  STATE,
  createScene as createWorldScene,
} from './world.ts'
import { onRunRefused, setCurrentGetter } from '../../hooks/requests.js'
import { STOPPED } from '../../hooks/thresholds.js'
import { createLimits } from '../../hooks/limit-rules.js'

const FILE_45_55 = { warn_percent: 45, save_percent: 55, after_save: 'offer_clear' }

const createScene = ($: any, options: any) => {
  const scene = createWorldScene($, options)
  if (options.hasStateHome !== false) scene.world.setFile(THRESHOLDS, JSON.stringify(FILE_45_55))

  return scene
}

const WARNING_47 =
  "Hats context threshold: this session's context window is at 47% (warning threshold 45%). " +
  'It anchors itself at the end of a turn once it reaches 55%. ' +
  'Tell the user so in one short line in your reply, in their language, and go on with the task.'
const REQUEST_56 = 'context 56% (anchor threshold 55%) — anchoring this session.'
const SAVED_CLEAR =
  'anchored at 56% of the context window (threshold 55%). ' +
  'Type /clear to go on from the note in an empty context: the plugin gives it back.'
const READ = { tool: 'Read', file_path: '/w/README.md' }
const ONE_RUN = [
  'hats:anchor',
]
const TWO_RUNS = [
  'hats:anchor',
  'hats:anchor',
]
const WITH_WARNING = [
  WARNING_47,
]
const OLD_NOTE = '# Task\n\n## NOW\n\nold step\n'
const OTHER_TEXT = `${NOTE_TEXT}\nanother session\n`

const getContext = (out: any) => out.context ?? []

const getFailedLine = (reason: string) => `the session was not anchored: ${reason}. Say "anchor" to try again.`

const getRetryLine = (reason: string) =>
  `the session was not anchored: ${reason}. It tries again at the end of the next turn; say "anchor" to save now.`

const setThresholds = (scene: any, value: unknown) => scene.world.setFile(THRESHOLDS, JSON.stringify(value))

const writeByShell = async (scene: any, text: string) => {
  await scene.callTool(57, { tool: 'Bash', command: `python3 -c 'write' "${NOTE}"` })
  scene.world.setFile(NOTE, text)
}

const anchorOnceMore = async (scene: any) => {
  await scene.askToAnchor()
  await scene.runAnchorTurn({ steps: getFullSave(scene) })
  const turnId = await scene.startTurn(40)
  await scene.endTurn(turnId, { percent: 56 })
}

const getFullSave = (scene: any) => [
  scene.createNote,
  () => scene.writeNote(),
  scene.runSave,
]

const createRefusalPlugin = () => {
  const logs: string[] = []
  const $ = {
    session: { id: async () => SESSION },
    ui: { log: async (text: string) => logs.push(text) },
    env: { get: async () => undefined },
  }

  return { $, logs }
}

const FINAL_REASONS = [
  'handoff is off',
  'unreadable marker',
]

const getFirstFailedLine = (reason: string) => (FINAL_REASONS.includes(reason) ? getFailedLine(reason) : getRetryLine(reason))

const failsWith = async (scene: any, failure: { steps: (() => Promise<unknown>)[]; reason: string }) => {
  await scene.askToAnchor()
  await scene.runAnchorTurn({ steps: failure.steps })
  expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: failure.reason })
  expect(scene.world.logs).toEqual([
    REQUEST_56,
    getFirstFailedLine(failure.reason),
  ])
}

describe('the warning threshold', () => {
  test('arms below it and warns once in the result of the next tool call past it', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)

    const out = await scene.callTool(47, READ)
    const again = await scene.callTool(47, READ)

    expect(getContext(out)).toEqual(WITH_WARNING)
    expect(getContext(again)).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', warn_round: 1, save_round: 0, percent: 47 })
    expect(scene.world.getStageWrites().length).toBe(1)
    await scene.endTurn(turnId, { percent: 47 })
    expect(scene.world.runs).toEqual([])
  })

  test('says nothing in a session first seen above the lowest threshold, however far the window grows', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(50)

    const out = await scene.callTool(60, READ)
    await scene.endTurn(turnId, { percent: 70 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([])
    expect(scene.world.writeAttempts).toBe(0)
    const later = await scene.startTurn(40)
    expect(getContext(await scene.callTool(47, READ))).toEqual(WITH_WARNING)
    await scene.endTurn(later, { percent: 47 })
  })

  test('leaves a denied result alone and puts the text into the next result that is not denied', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    await scene.startTurn(10)
    scene.world.nextToolAnswer = { deny: 'not now' }

    const denied = await scene.callTool(47, READ)
    const next = await scene.callTool(47, READ)

    expect(denied).toEqual({ deny: 'not now' })
    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', warn_round: 1 })
    expect(getContext(next)).toEqual(WITH_WARNING)
  })

  test('crossed at the end of a turn goes to the next prompt of the user, not to a command or a plugin prompt', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)
    await scene.endTurn(turnId, { percent: 47 })

    await scene.prompt('/compact', { name: 'compact', args: '' })
    await scene.pluginPrompt('other')
    await scene.prompt('go on')

    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', warn_round: 1 })
    expect(scene.world.prompts.map((prompt: any) => prompt.context ?? [])).toEqual([
      [],
      [],
      WITH_WARNING,
    ])
  })

  test('past the save threshold mid-turn says the session anchors at the end of this turn', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)

    const out = await scene.callTool(56, READ)
    const runsBeforeEnd = [...scene.world.runs]
    await scene.endTurn(turnId, { percent: 56 })

    expect(getContext(out)[0]).toContain('(warning threshold 45%). It anchors itself at the end of this turn. Tell the user')
    expect(runsBeforeEnd).toEqual([])
    expect(scene.world.runs).toEqual(ONE_RUN)
  })

  test('fires again after the window drops below it, with the next round, when the save threshold is off', async ($, on) => {
    const scene = createScene($, { on })
    setThresholds(scene, { warn_percent: 45, save_percent: null, after_save: 'tell' })
    await scene.start()
    const turnId = await scene.startTurn(10)

    const first = await scene.callTool(47, READ)
    await scene.callTool(30, READ)
    const second = await scene.callTool(47, READ)
    await scene.endTurn(turnId, { percent: 60 })

    expect(getContext(first)[0]).toContain('(warning threshold 45%). Tell the user')
    expect(getContext(second).length).toBe(1)
    expect(scene.world.getStageWrites().map((stage: any) => stage.warn_round)).toEqual([
      1,
      2,
    ])
    expect(scene.world.runs).toEqual([])
  })
})

describe('the save threshold', () => {
  test('at the end of a turn shows the line, runs /hats:anchor, records the request and drops an unsaid warning', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)
    scene.world.nextToolAnswer = { deny: 'no' }
    await scene.callTool(47, READ)

    await scene.endTurn(turnId, { percent: 56 })
    await scene.prompt('next')

    expect(scene.world.logs).toEqual([
      REQUEST_56,
    ])
    expect(scene.world.runs).toEqual(ONE_RUN)
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 1, warn_round: 1, after_save: 'offer_clear' })
    expect(scene.world.prompts[0].context ?? []).toEqual([])
  })

  test('saved by the anchor turn shows the line of the chosen action and records the marker', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      SAVED_CLEAR,
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', save_round: 1, reason: null, marker: MARKER })
  })

  test('does not ask again in the next turn without a new arming', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    const turnId = await scene.startTurn(60)
    await scene.callTool(61, READ)
    await scene.endTurn(turnId, { percent: 62 })

    expect(scene.world.runs).toEqual(ONE_RUN)
    expect(scene.world.logs.length).toBe(2)
  })

  test('asks again at 56% after a compaction to 50% that follows a save', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    const turnId = await scene.startTurn(50)
    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.runs).toEqual(TWO_RUNS)
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 2 })
  })

  test('checks as usual when the window falls below both thresholds during the anchor turn', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene), endPercent: 12 })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('takes an anchor the user said in a turn that ended past it as the save: no request and no line', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)

    await scene.writeNote()
    await scene.runSave()
    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', reason: 'manual', save_round: 0, marker: MARKER })
  })

  test('asks anyway when the anchor the user said did not rewrite the note', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, NOTE_TEXT)
    await scene.world.clock.advance(1000)
    await scene.start()
    const turnId = await scene.startTurn(10)

    await scene.runSave()
    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.runs).toEqual(ONE_RUN)
  })

  test('says nothing at the end of an interrupted turn and asks at the end of the next one', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)
    await scene.endTurn(turnId, { percent: 56, reason: 'aborted' })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.writeAttempts).toBe(0)
    const next = await scene.startTurn(56)
    await scene.endTurn(next, { percent: 56 })
    expect(scene.world.runs).toEqual(ONE_RUN)
  })

  test('says nothing while the window has no figure, and keeps the arming', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)

    await scene.endTurn(turnId, {})

    expect(scene.world.runs).toEqual([])
    const next = await scene.startTurn(undefined)
    await scene.endTurn(next, { percent: 56 })
    expect(scene.world.runs).toEqual(ONE_RUN)
  })
})

describe('the check of the anchor turn', () => {
  test('fails with no marker line in the turn', async ($, on) => {
    const scene = createScene($, { on })
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote(),
      ],
      reason: 'no marker this turn',
    })
  })

  test('fails when handoff is off', async ($, on) => {
    const scene = createScene($, { on })
    const off = () => {
      scene.world.nextToolAnswer = createBashResult('handoff is off for /w — marker not written')
      return scene.callTool(57, { tool: 'Bash', command: scene.world.paths.saveCommand })
    }
    await failsWith(scene, {
      steps: [
        () => scene.writeNote(),
        off,
      ],
      reason: 'handoff is off',
    })
  })

  test('fails with a marker saved a second before the request', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.savedAt = '2026-11-14T12:00:00Z'
    await failsWith(scene, { steps: getFullSave(scene), reason: 'stale marker' })
  })

  test('fails with a marker that is not JSON', async ($, on) => {
    const scene = createScene($, { on })
    const broken = async () => {
      await scene.runSave()
      scene.world.setFile(MARKER, '{not json')
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote(),
        broken,
      ],
      reason: 'unreadable marker',
    })
  })

  test('fails with a marker that lacks a field', async ($, on) => {
    const scene = createScene($, { on })
    const partial = async () => {
      await scene.runSave()
      const marker = JSON.parse(scene.world.files.get(MARKER)!.text)
      delete marker.topic
      scene.world.setFile(MARKER, JSON.stringify(marker))
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote(),
        partial,
      ],
      reason: 'unreadable marker',
    })
  })

  test('fails with a marker outside the handoff state folder', async ($, on) => {
    const scene = createScene($, { on })
    const elsewhere = async () => {
      await scene.runSave()
      scene.world.setFile('/tmp/1.json', scene.world.files.get(MARKER)!.text)
      scene.world.nextToolAnswer = createBashResult('marker: /tmp/1.json')
      await scene.callTool(58, { tool: 'Bash', command: scene.world.paths.saveCommand })
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote(),
        elsewhere,
      ],
      reason: 'unreadable marker',
    })
  })

  test('fails with a fresh marker and a note not changed since before the request', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, NOTE_TEXT)
    await failsWith(scene, {
      steps: [
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('fails when new made an empty note, the write was denied and save passed', async ($, on) => {
    const scene = createScene($, { on })
    const denied = () => {
      scene.world.nextToolAnswer = { deny: 'no' }
      return scene.writeNote()
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        denied,
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('passes a note new made that could not be read just before the write: new already said it was not there', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    const unreadable = () => {
      scene.world.unreadableUntilWrite = NOTE
      return scene.writeNote()
    }

    await scene.runAnchorTurn({
      steps: [
        scene.createNote,
        unreadable,
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('does not count a denied write as a write of this session after another writer changed the note', async ($, on) => {
    const scene = createScene($, { on })
    const otherThenDenied = async () => {
      scene.world.setFile(NOTE, OTHER_TEXT)
      scene.world.nextToolAnswer = { deny: 'no' }
      await scene.writeNote(`${NOTE_TEXT}\nmine again\n`)
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote(),
        otherThenDenied,
        scene.runSave,
      ],
      reason: 'the note changed after this session wrote it',
    })
  })

  test('does not count a write that ended in an error as a write of this session', async ($, on) => {
    const scene = createScene($, { on })
    const otherThenError = async () => {
      scene.world.setFile(NOTE, OTHER_TEXT)
      scene.world.nextToolAnswer = { isError: true, result: 'disk full', text: 'disk full' }
      await scene.writeNote(`${NOTE_TEXT}\nmine again\n`)
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote(),
        otherThenError,
        scene.runSave,
      ],
      reason: 'the note changed after this session wrote it',
    })
  })

  test('passes a note from the start list, never saved in this process, rewritten by Write', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, OLD_NOTE)
    await scene.askToAnchor()

    await scene.runAnchorTurn({
      steps: [
        () => scene.writeNote(),
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('fails for a note from the start list when its Write was denied', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, OLD_NOTE)
    const denied = () => {
      scene.world.nextToolAnswer = { deny: 'no' }
      return scene.writeNote()
    }
    await failsWith(scene, {
      steps: [
        denied,
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('passes a note new made after the request and the shell wrote', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({
      steps: [
        scene.createNote,
        () => writeByShell(scene, NOTE_TEXT),
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', marker: MARKER })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      SAVED_CLEAR,
    ])
  })

  test('passes a note the marker of this process named at the request, rewritten by the shell in a later anchor', async ($, on) => {
    const scene = createScene($, { on })
    await anchorOnceMore(scene)

    await scene.runAnchorTurn({
      steps: [
        () => writeByShell(scene, `${NOTE_TEXT}\nsecond\n`),
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', save_round: 2, marker: MARKER })
  })

  test('fails for a note the marker of this process named, rewritten by the shell with the same text', async ($, on) => {
    const scene = createScene($, { on })
    await anchorOnceMore(scene)

    await scene.runAnchorTurn({
      steps: [
        () => writeByShell(scene, NOTE_TEXT),
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the note was not rewritten in this anchor' })
  })

  test('takes no snapshot of an earlier note over the size limit: unknown, not absent, and the save still runs', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await scene.runAnchorTurn({ steps: getFullSave(scene) })
    scene.world.setFile(NOTE, `${NOTE_TEXT}${'x'.repeat(2_000_001)}`)
    const turnId = await scene.startTurn(40)
    await scene.endTurn(turnId, { percent: 56 })

    await scene.runAnchorTurn({
      steps: [
        () => writeByShell(scene, `${NOTE_TEXT}\nsecond\n`),
        scene.runSave,
      ],
    })

    expect(scene.world.runs).toEqual(TWO_RUNS)
    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the note was not rewritten in this anchor' })
  })

  test('fails for a note the marker of this process named, only touched after the request', async ($, on) => {
    const scene = createScene($, { on })
    await anchorOnceMore(scene)
    const touch = async () => {
      await scene.callTool(57, { tool: 'Bash', command: `touch "${NOTE}"` })
      scene.world.setFile(NOTE, NOTE_TEXT)
    }

    await scene.runAnchorTurn({
      steps: [
        touch,
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the note was not rewritten in this anchor' })
  })

  test('fails for a note from the start list that only the shell rewrote: nothing shows its text before the request', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, OLD_NOTE)
    await failsWith(scene, {
      steps: [
        () => writeByShell(scene, NOTE_TEXT),
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('fails for a note left as it was before the request when nothing wrote it', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, NOTE_TEXT)
    await scene.world.clock.advance(1000)
    await failsWith(scene, {
      steps: [
        async () => scene.callTool(57, { tool: 'Bash', command: `touch "${NOTE}.other"` }),
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('fails for a note rewritten by the shell with the text it had when new made it', async ($, on) => {
    const scene = createScene($, { on })
    const emptyAgain = async () => {
      await scene.callTool(57, { tool: 'Bash', command: `: > "${NOTE}"` })
      scene.world.setFile(NOTE, '')
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        emptyAgain,
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('fails for a note the shell rewrote without a NOW section', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, OLD_NOTE)
    const byShell = async () => {
      await scene.callTool(57, { tool: 'Bash', command: `python3 -c 'write' "${NOTE}"` })
      scene.world.setFile(NOTE, '# Task\n\n## Later\n')
    }
    await failsWith(scene, {
      steps: [
        byShell,
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('fails for a note without a NOW section', async ($, on) => {
    const scene = createScene($, { on })
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote('# Task\n\n## Later\n'),
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('fails for a note rewritten with the same text', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, NOTE_TEXT)
    await failsWith(scene, {
      steps: [
        () => scene.writeNote(),
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('passes a note with a СЕЙЧАС section rewritten by Edit', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, '# Задача\n\n## СЕЙЧАС\n\nстарый шаг\n')
    await scene.askToAnchor()
    const edit = () => scene.callTool(57, { tool: 'Edit', file_path: NOTE, old_string: 'старый', new_string: 'новый' })

    await scene.runAnchorTurn({
      steps: [
        edit,
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('fails for a note another writer changed after this session wrote it', async ($, on) => {
    const scene = createScene($, { on })
    const other = async () => {
      await scene.runSave()
      scene.world.setFile(NOTE, OTHER_TEXT)
    }
    await failsWith(scene, {
      steps: [
        scene.createNote,
        () => scene.writeNote(),
        other,
      ],
      reason: 'the note changed after this session wrote it',
    })
  })

  test('records an interrupted anchor turn without a marker and says the save could not be checked', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({
      steps: [
        scene.createNote,
      ],
      reason: 'aborted',
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: null })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      'anchoring was stopped; whether the note was saved could not be checked. Say "anchor" to save.',
    ])
  })

  test('Esc after a save whose marker is unreadable: the save could not be checked, not "not saved"', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    const broken = async () => {
      await scene.runSave()
      scene.world.setFile(MARKER, '{not json')
    }

    await scene.runAnchorTurn({ steps: [scene.createNote, () => scene.writeNote(), broken], reason: 'aborted' })

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      'anchoring was stopped; whether the note was saved could not be checked. Say "anchor" to save.',
    ])
  })

  test('Esc after a full save in a turn where a plugin hook failed: the save could not be checked', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    const failing = async () => {
      scene.world.sessionIdDenials = 1
      await scene.callTool(57, READ)
    }

    await scene.runAnchorTurn({ steps: [failing, ...getFullSave(scene)], reason: 'aborted' })

    expect(scene.world.logs).toEqual([
      REQUEST_56,
      'anchoring was stopped; whether the note was saved could not be checked. Say "anchor" to save.',
    ])
  })

  test('Esc after a checked save: saved, still interrupted, and no /clear even with after clear', async ($, on) => {
    const scene = createScene($, { on })
    setThresholds(scene, { ...FILE_45_55, after_save: 'clear' })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene), reason: 'aborted' })

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: null })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      'anchoring was stopped; the note was saved.',
    ])
    expect(scene.world.runs).toEqual(ONE_RUN)
  })

  test('Esc after a save whose check fails: not saved, with the reason and no promise', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: [scene.createNote, scene.runSave], reason: 'aborted' })

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted' })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      'anchoring was stopped; the note was not saved: the note was not rewritten in this anchor. Say "anchor" to save.',
    ])
  })

  test('the own anchor command refused as stopped before it ran: the line says the context was not saved', async () => {
    const plugin = createRefusalPlugin()
    const request = { sessionId: SESSION, isWindow: false, limits: [], previous: null }
    const state = { id: SESSION, request, limits: createLimits() }
    setCurrentGetter(() => state)

    await onRunRefused(plugin.$, { state, request, error: new Error(`hats: $.command.run: ${STOPPED}`) })

    expect(state.request).toBe(null)
    expect(plugin.logs).toEqual([
      'anchoring was cancelled before it started; the context was not saved.',
    ])
  })

  test('the own anchor command refused for another reason: the failed line, no line about a cancel', async () => {
    const plugin = createRefusalPlugin()
    const request = { sessionId: SESSION, isWindow: false, limits: [], previous: null }
    const state = { id: SESSION, request, limits: createLimits(), stage: null }
    setCurrentGetter(() => state)

    await onRunRefused(plugin.$, { state, request, error: new Error('hats: $.command.run: busy') })

    expect(plugin.logs).toEqual([
      'the session was not anchored: the anchor command was refused: hats: $.command.run: busy. Say "anchor" to try again.',
    ])
  })

  test('fails an anchor turn that ended in an error', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene), reason: 'error' })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the anchor turn ended in an error' })
  })

  test('fails an anchor turn that ended in a refusal', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene), reason: 'refusal' })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the anchor turn was refused' })
  })
})

const OWN_FOLDER = '0123456789abcdef'
const HATS_HOME = `${HOME}/Library/Application Support/Hats`

const getOwnNoteSave = (scene: any, root: string) => {
  const folder = `${root}/notes/${OWN_FOLDER}`
  const note = `${folder}/resume-task.md`
  const script = `sh "${PLUGIN}/scripts/py.sh" "${PLUGIN}/scripts/handoff.py"`
  scene.world.setFolder(`${root}/notes`)
  scene.world.setFolder(folder)

  return [
    () => {
      scene.world.nextToolAnswer = createBashResult(`${note}\n`)
      return scene.callTool(57, { tool: 'Bash', command: `${script} new --slug task` })
    },
    () => scene.callTool(57, { tool: 'Write', file_path: note, content: NOTE_TEXT }),
    () => {
      const savedAt = `${new Date(scene.world.clock.now()).toISOString().slice(0, 19)}Z`
      const marker = { pid: 42, started: 'Sat Nov 14 12:00:00 2026', cwd: '/w', note, topic: 'task', saved_at: savedAt }
      scene.world.setFile(scene.world.paths.marker, JSON.stringify(marker))
      scene.world.nextToolAnswer = createBashResult(`marker: ${scene.world.paths.marker}\nquotes and numbers: all verified`)
      return scene.callTool(58, { tool: 'Bash', command: `${script} save --note "${note}" --topic "task"` })
    },
  ]
}

describe('the notes folder of the plugin', () => {
  test('follows HATS_STATE_HOME: a note in <HATS_STATE_HOME>/notes/<project> passes the check', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getOwnNoteSave(scene, STATE) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      SAVED_CLEAR,
    ])
  })

  test('with HATS_STATE_HOME set, a note in the default folder is not a note of this anchor', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getOwnNoteSave(scene, HATS_HOME) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the note was not rewritten in this anchor' })
  })

  for (const value of ['~/hats-tilde', 'relative/state']) {
    test(`HATS_STATE_HOME "${value}" is not absolute: the notes go to the default folder`, async ($, on) => {
      const scene = createScene($, { on, hasStateHome: false, env: { HATS_STATE_HOME: value } })
      await scene.start()
      const turnId = await scene.startTurn(10)
      await scene.endTurn(turnId, { percent: 71 })

      await scene.runAnchorTurn({ steps: getOwnNoteSave(scene, HATS_HOME) })

      expect(scene.world.logs).toEqual([
        'context 71% (anchor threshold 70%) — anchoring this session.',
        'anchored at 71% of the context window (threshold 70%). ' +
          'Type /clear to go on from the note in an empty context: the plugin gives it back.',
      ])
    })
  }
})

describe('the request command', () => {
  test('refused for another reason gives failed and a line', async ($, on) => {
    const scene = createScene($, { on, hasRunHook: false })
    await scene.askToAnchor()
    await scene.world.clock.settle()

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed' })
    expect(scene.world.getStage().reason).toContain('the anchor command was refused: ')
    expect(scene.world.logs.length).toBe(2)
  })
})

describe('sessions', () => {
  test('a resume between the request and the end of the turn ends the chain without a line or a save', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.end('resume')
    scene.world.sessionId = OTHER_SESSION
    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: 'session changed' })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
    ])
    expect(scene.world.files.has(`${STAGES}/${OTHER_SESSION}.json`)).toBe(false)
  })

  test('a new session id seen without session.end ends the chain the same way', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    scene.world.sessionId = OTHER_SESSION
    await scene.ownAnchor()

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: 'session changed' })
  })

  test('a new session starts unarmed and takes its rounds from its own stage file', async ($, on) => {
    const scene = createScene($, { on })
    const otherFile = `${STAGES}/${OTHER_SESSION}.json`
    scene.world.setFile(otherFile, JSON.stringify({ session: OTHER_SESSION, stage: 'warned', warn_round: 3, save_round: 2 }))
    await scene.start()
    await scene.end('clear')
    scene.world.sessionId = OTHER_SESSION

    const first = await scene.startTurn(60)
    await scene.endTurn(first, { percent: 60 })
    const second = await scene.startTurn(10)
    await scene.callTool(47, READ)
    await scene.endTurn(second, { percent: 47 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.getStage(otherFile)).toMatchObject({ warn_round: 4, save_round: 2 })
  })

  test('a reload with a request on file records it interrupted and tells the user', async ($, on) => {
    const scene = createScene($, { on })
    const requested = { session: scene.world.sessionId, stage: 'requested', warn_round: 1, save_round: 1 }
    scene.world.setFile(STAGE_FILE, JSON.stringify(requested))

    await scene.start()

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: 'plugin reloaded', warn_round: 1, save_round: 1 })
    expect(scene.world.logs).toEqual([
      'anchoring was not checked: the plugin reloaded. Say "anchor" to save again.',
    ])
  })

  test('a reload after a save says nothing', async ($, on) => {
    const scene = createScene($, { on })
    const saved = { session: scene.world.sessionId, stage: 'saved', warn_round: 1, save_round: 1 }
    scene.world.setFile(STAGE_FILE, JSON.stringify(saved))

    await scene.start()

    expect(scene.world.logs).toEqual([])
    expect(scene.world.writeAttempts).toBe(0)
  })

  test('a session without a person does nothing for the whole process', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start(false)
    const turnId = await scene.startTurn(10)

    const out = await scene.callTool(47, READ)
    await scene.endTurn(turnId, { percent: 56 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual([])
    expect(scene.world.writeAttempts).toBe(0)
  })

  test('a subagent neither arms nor fires', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const main = await scene.startTurn(10)
    const sub = await scene.startTurn(10, 'agent-1')

    const out = await scene.callTool(47, { ...READ, agentId: 'agent-1' })
    await scene.endTurn(sub, { percent: 56, agentId: 'agent-1' })

    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual([])
    expect(scene.world.writeAttempts).toBe(0)
    await scene.endTurn(main, { percent: 56 })
    expect(scene.world.runs).toEqual(ONE_RUN)
  })
})

describe('the thresholds file', () => {
  const isSilentAt56 = async (scene: any) => {
    await scene.start()
    const turnId = await scene.startTurn(10)
    const out = await scene.callTool(47, READ)
    await scene.endTurn(turnId, { percent: 56 })
    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual([])
    expect(scene.world.writeAttempts).toBe(0)
  }

  test('a link makes the mod silent', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile('/elsewhere/thresholds.json', JSON.stringify({ warn_percent: 45, save_percent: 55, after_save: 'tell' }))
    scene.world.setLink(THRESHOLDS, '/elsewhere/thresholds.json')
    await isSilentAt56(scene)
  })

  test('a file over 64 KB makes the mod silent', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(THRESHOLDS, `{"warn_percent":45,"save_percent":55,"after_save":"tell","x":"${'a'.repeat(70000)}"}`)
    await isSilentAt56(scene)
  })

  test('a file that is not JSON makes the mod silent', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(THRESHOLDS, 'warn=45')
    await isSilentAt56(scene)
  })

  test('a warning threshold not below the save makes the mod silent', async ($, on) => {
    const scene = createScene($, { on })
    setThresholds(scene, { warn_percent: 55, save_percent: 55, after_save: 'tell' })
    await isSilentAt56(scene)
  })

  test('the save threshold off: a warning and no request', async ($, on) => {
    const scene = createScene($, { on })
    setThresholds(scene, { warn_percent: 45, save_percent: null, after_save: 'tell' })
    await scene.start()
    const turnId = await scene.startTurn(10)

    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'warned', save_percent: null })
  })

  test('the warning threshold off: a request and no warning', async ($, on) => {
    const scene = createScene($, { on })
    setThresholds(scene, { warn_percent: null, save_percent: 55, after_save: 'tell' })
    await scene.start()
    const turnId = await scene.startTurn(10)

    const out = await scene.callTool(50, READ)
    await scene.endTurn(turnId, { percent: 56 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.runs).toEqual(ONE_RUN)
  })

  test('an unknown action is told as tell', async ($, on) => {
    const scene = createScene($, { on })
    setThresholds(scene, { warn_percent: 45, save_percent: 55, after_save: 'clear_now' })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.logs[1]).toBe('anchored at 56% of the context window (threshold 55%).')
  })

  test('no file in the Hats folder: the warning at 60%', async ($, on) => {
    const scene = createScene($, { on, hasStateHome: false })
    await scene.start()
    await scene.startTurn(10)

    const below = await scene.callTool(59, READ)
    const past = await scene.callTool(61, READ)

    expect(getContext(below)).toEqual([])
    expect(getContext(past)).toEqual([
      "Hats context threshold: this session's context window is at 61% (warning threshold 60%). " +
        'It anchors itself at the end of a turn once it reaches 70%. ' +
        'Tell the user so in one short line in your reply, in their language, and go on with the task.',
    ])
  })

  test('no file in the Hats folder: the anchor at 70% and offer_clear', async ($, on) => {
    const scene = createScene($, { on, hasStateHome: false })
    await scene.start()
    const below = await scene.startTurn(10)
    await scene.endTurn(below, { percent: 69 })
    const past = await scene.startTurn(69)

    await scene.endTurn(past, { percent: 71 })

    expect(scene.world.logs).toEqual([
      'context 71% (anchor threshold 70%) — anchoring this session.',
    ])
    expect(scene.world.runs).toEqual(ONE_RUN)
  })
})

describe('the stage file', () => {
  const isNotWritten = async (scene: any) => {
    await scene.askToAnchor()
    expect(scene.world.writeAttempts).toBe(0)
    expect(scene.world.runs).toEqual(ONE_RUN)
  }

  test('is not written when its folder is missing', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.files.delete(STAGES)
    await isNotWritten(scene)
  })

  test('is not written when its folder is a link', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setLink(STAGES, '/elsewhere/stages')
    await isNotWritten(scene)
  })

  test('is not written when its folder is a file', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(STAGES, 'x')
    await isNotWritten(scene)
  })

  test('is not written when the folder cannot be looked at', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.isStatDenied = true
    await isNotWritten(scene)
  })

  test('a refused stage write is not retried; the next change of the stage writes again', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.isWriteDenied = true
    await scene.askToAnchor()

    expect(scene.world.writeAttempts).toBe(1)
    scene.world.isWriteDenied = false
    await scene.runAnchorTurn({ steps: getFullSave(scene) })
    expect(scene.world.writeAttempts).toBe(2)
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', save_round: 1 })
  })
})

describe('the request and the anchor turn', () => {
  test('the end of the turn does not wait for /hats:anchor to run', async ($, on) => {
    const scene = createScene($, { on, hasRunHook: false })
    const queued: string[] = []
    on('command.run', (_: any, e: any) => {
      queued.push(e.command)
      return new Promise(() => {})
    })

    await scene.askToAnchor()

    expect(queued).toEqual(ONE_RUN)
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested' })
  })

  test('a request disarms the warning threshold without a warning', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    const turnId = await scene.startTurn(50)
    const out = await scene.callTool(50, READ)
    await scene.endTurn(turnId, { percent: 50 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', warn_round: 0 })
  })

  test('a prompt of the plugin without the command does not start the anchor turn', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.pluginPrompt('hats')
    const turnId = await scene.startTurn(56)
    for (const step of getFullSave(scene)) await step()
    await scene.endTurn(turnId, { percent: 58 })

    expect(scene.world.getStage()).toMatchObject({ stage: 'requested' })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
    ])
  })

  test('another command of the plugin does not start the anchor turn', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    const compact = { name: 'compact', args: '' }
    await $.prompt.submit({ text: '/compact', wait: false, origin: { kind: 'plugin', name: 'hats' }, command: compact })
    const turnId = await scene.startTurn(56)
    for (const step of getFullSave(scene)) await step()
    await scene.endTurn(turnId, { percent: 58 })

    expect(scene.world.getStage()).toMatchObject({ stage: 'requested' })
  })

  test('a turn of the user between the request and the command is not the anchor turn', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.prompt('one more thing')
    const userTurn = await scene.startTurn(56)
    await scene.callTool(57, READ)
    await scene.endTurn(userTurn, { percent: 57 })
    const stageBetween = scene.world.getStage().stage
    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(stageBetween).toBe('requested')
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('/clear with an open request ends its chain at once, without a line', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.end('clear')

    expect(scene.world.getStage()).toMatchObject({ stage: 'interrupted', reason: 'session changed' })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
    ])
  })

  test('after a reload the thresholds are unarmed: a turn past them asks nothing', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const first = await scene.startTurn(10)
    await scene.endTurn(first, { percent: 20 })

    await scene.start()
    const second = await scene.startTurn(56)
    await scene.endTurn(second, { percent: 56 })

    expect(scene.world.runs).toEqual([])
  })
})

describe('the anchor the user said', () => {
  test('disarms the save threshold: the next turn past it asks nothing', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)
    await scene.writeNote()
    await scene.runSave()
    await scene.endTurn(turnId, { percent: 56 })

    const next = await scene.startTurn(60)
    await scene.endTurn(next, { percent: 62 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.logs).toEqual([])
  })

  test('does not count with a marker saved before the turn began', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.savedAt = '2026-11-14T11:59:00Z'
    await scene.start()
    const turnId = await scene.startTurn(10)

    await scene.writeNote()
    await scene.runSave()
    await scene.endTurn(turnId, { percent: 56 })

    expect(scene.world.runs).toEqual(ONE_RUN)
  })
})

describe('the writes of the anchor turn', () => {
  test('MultiEdit is a write of the note', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, OLD_NOTE)
    await scene.askToAnchor()
    const edits = [
      { old_string: 'old', new_string: 'new' },
    ]
    const multiEdit = () => scene.callTool(57, { tool: 'MultiEdit', file_path: NOTE, edits })

    await scene.runAnchorTurn({
      steps: [
        multiEdit,
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('the state before the first write of the turn counts: two writes back to the old text are no rewrite', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, OLD_NOTE)
    await failsWith(scene, {
      steps: [
        () => scene.writeNote(),
        () => scene.writeNote(OLD_NOTE),
        scene.runSave,
      ],
      reason: 'the note was not rewritten in this anchor',
    })
  })

  test('the last of two own writes is the one the note must equal', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({
      steps: [
        scene.createNote,
        () => scene.writeNote(),
        () => scene.writeNote(`${NOTE_TEXT}\nsecond write\n`),
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })
})

describe('the settings folder of Claude Code', () => {
  test('CLAUDE_CONFIG_DIR with ~ holds the markers and the memory', async ($, on) => {
    const scene = createScene($, { on, configDir: '~/altcfg', configRoot: '/home/u/altcfg' })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', marker: scene.world.paths.marker })
  })

  test('CLAUDE_CONFIG_DIR with a slash at its end holds the markers and the memory', async ($, on) => {
    const scene = createScene($, { on, configDir: '/alt/', configRoot: '/alt' })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', marker: scene.world.paths.marker })
  })

  test('a relative CLAUDE_CONFIG_DIR is not taken: ~/.claude holds the markers and the memory, as in handoff.py', async ($, on) => {
    const scene = createScene($, { on, configDir: 'rel/cfg' })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', marker: scene.world.paths.marker })
  })

  test('a marker outside the folder CLAUDE_CONFIG_DIR names is not read', async ($, on) => {
    const scene = createScene($, { on, configDir: '/alt' })
    await failsWith(scene, { steps: getFullSave(scene), reason: 'unreadable marker' })
  })
})

describe('subagents', () => {
  test('a subagent does not arm the main session', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const main = await scene.startTurn(50)
    const sub = await scene.startTurn(10, 'agent-1')
    await scene.callTool(10, { ...READ, agentId: 'agent-1' })
    await scene.endTurn(sub, { percent: 10, agentId: 'agent-1' })

    await scene.endTurn(main, { percent: 56 })

    expect(scene.world.runs).toEqual([])
  })

  test('a subagent turn does not take the place of the main turn', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const main = await scene.startTurn(10)
    await scene.writeNote()
    await scene.startTurn(10, 'agent-1')

    await scene.runSave()
    await scene.endTurn(main, { percent: 56 })

    expect(scene.world.runs).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', reason: 'manual' })
  })
})

const REQUEST_58 = 'context 58% (anchor threshold 55%) — anchoring this session.'
const NO_MARKER = 'no marker this turn'

const failAnchorTurn = (scene: any) => scene.runAnchorTurn({ steps: [] })

const endUserTurn = async (scene: any, percent: { start: number; end: number }) => {
  const turnId = await scene.startTurn(percent.start)
  await scene.endTurn(turnId, { percent: percent.end })
}

describe('a failed anchor on the threshold', () => {
  test('arms the threshold again: the next turn past it asks again', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await failAnchorTurn(scene)

    await endUserTurn(scene, { start: 58, end: 58 })

    expect(scene.world.runs).toEqual(TWO_RUNS)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getRetryLine(NO_MARKER),
      REQUEST_58,
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 2 })
  })

  test('a reason no later turn can change does not arm it again: handoff is off', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    const off = () => {
      scene.world.nextToolAnswer = createBashResult('handoff is off for /w — marker not written')
      return scene.callTool(57, { tool: 'Bash', command: scene.world.paths.saveCommand })
    }
    await scene.runAnchorTurn({ steps: [off] })

    await endUserTurn(scene, { start: 58, end: 58 })

    expect(scene.world.runs).toEqual(ONE_RUN)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getFailedLine('handoff is off'),
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'handoff is off', save_round: 1 })
  })

  test('a retry that saves goes on as a save', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await failAnchorTurn(scene)
    await endUserTurn(scene, { start: 58, end: 58 })

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', save_round: 2, marker: MARKER })
  })

  test('after three failures in a row stops arming until the window falls below the threshold', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await failAnchorTurn(scene)
    await endUserTurn(scene, { start: 58, end: 58 })
    await failAnchorTurn(scene)
    await endUserTurn(scene, { start: 58, end: 58 })
    await failAnchorTurn(scene)

    await endUserTurn(scene, { start: 58, end: 58 })

    expect(scene.world.runs.length).toBe(3)
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getRetryLine(NO_MARKER),
      REQUEST_58,
      getRetryLine(NO_MARKER),
      REQUEST_58,
      getFailedLine(NO_MARKER),
    ])
    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: NO_MARKER, save_round: 3 })
    await endUserTurn(scene, { start: 40, end: 56 })
    await failAnchorTurn(scene)
    expect(scene.world.runs.length).toBe(4)
    expect(scene.world.logs.slice(-1)).toEqual([
      getRetryLine(NO_MARKER),
    ])
  })
})

describe('the review round', () => {
  test('a throw in the anchor turn end fails the request with its line, and the next crossing asks again', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await scene.ownAnchor()
    scene.world.releaseRuns()
    const turnId = await scene.startTurn(56)
    scene.world.sessionIdDenials = 1

    await scene.endTurn(turnId, { percent: 58 })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'a plugin hook failed' })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getRetryLine('a plugin hook failed'),
    ])
    const later = await scene.startTurn(40)
    await scene.endTurn(later, { percent: 56 })
    expect(scene.world.runs).toEqual(TWO_RUNS)
  })

  test('a hook that fails inside the anchor turn fails the check', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    const failing = async () => {
      scene.world.sessionIdDenials = 1
      await scene.writeNote()
    }

    await scene.runAnchorTurn({
      steps: [
        scene.createNote,
        failing,
        scene.runSave,
      ],
    })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'a plugin hook failed' })
  })

  test('a hook that fails in a turn of the user before the anchor command does not fail the anchor', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await scene.prompt('one more thing')
    const userTurn = await scene.startTurn(56)
    scene.world.sessionIdDenials = 1
    await scene.callTool(57, READ)
    await scene.endTurn(userTurn, { percent: 57 })

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('/hats:anchor that ran without the own prompt fails the request with its line', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    scene.world.releaseRuns()
    await scene.world.clock.settle()

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the anchor command did not start a turn' })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getRetryLine('the anchor command did not start a turn'),
    ])
  })

  test('the own prompt dropped beneath fails the request, and the next turn of the user is not the anchor turn', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    scene.world.dropNextPrompt = 'held'

    await scene.ownAnchor()
    scene.world.releaseRuns()
    const userTurn = await scene.startTurn(58)
    await scene.endTurn(userTurn, { percent: 58 })

    expect(scene.world.getStage()).toMatchObject({ stage: 'requested', save_round: 2 })
    expect(scene.world.logs).toEqual([
      REQUEST_56,
      getRetryLine('the anchor command did not start a turn'),
      REQUEST_56.replace('56%', '58%'),
    ])
    expect(scene.world.runs).toEqual(TWO_RUNS)
  })

  test('the own prompt with no open request is dropped: after /clear the queued anchor does not run', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await scene.end('clear')
    scene.world.sessionId = OTHER_SESSION

    const out = await scene.ownAnchor()

    expect(out.drop).toBe('hats: no anchor request is open')
    expect(scene.world.prompts.length).toBe(0)
  })

  test('a warning crossed while a request is open writes nothing over requested', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()
    await scene.ownAnchor()
    scene.world.releaseRuns()
    const turnId = await scene.startTurn(56)

    await scene.callTool(30, READ)
    const out = await scene.callTool(47, READ)
    const stageBeforeEnd = scene.world.getStage().stage
    await scene.endTurn(turnId, { percent: 47 })

    expect(getContext(out)).toEqual([])
    expect(stageBeforeEnd).toBe('requested')
  })

  test('a warning on a prompt that a hook beneath drops goes to the next prompt', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)
    await scene.endTurn(turnId, { percent: 47 })
    scene.world.dropNextPrompt = 'held'

    await scene.prompt('first')
    await scene.prompt('second')

    expect(scene.world.prompts.map((prompt: any) => prompt.context ?? [])).toEqual([
      WITH_WARNING,
      WITH_WARNING,
    ])
  })

  test('a stage file that is a link is not written through', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile('/elsewhere/target.json', 'keep')
    scene.world.setLink(STAGE_FILE, '/elsewhere/target.json')

    await scene.askToAnchor()

    expect(scene.world.writeAttempts).toBe(0)
    expect(scene.world.files.get('/elsewhere/target.json')!.text).toBe('keep')
  })

  test('an anchor turn that ended for an unknown reason fails', async ($, on) => {
    const scene = createScene($, { on })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene), reason: 'cancelled' })

    expect(scene.world.getStage()).toMatchObject({ stage: 'failed', reason: 'the anchor turn ended: cancelled' })
  })

  test('a note that is not a regular file is never read', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setFile(NOTE, '', { kind: 'other' })
    await scene.askToAnchor()
    const denied = () => {
      scene.world.nextToolAnswer = { deny: 'no' }
      return scene.writeNote()
    }

    await scene.runAnchorTurn({
      steps: [
        denied,
        scene.runSave,
      ],
    })

    expect(scene.world.otherReads).toBe(0)
    expect(scene.world.getStage()).toMatchObject({ stage: 'failed' })
  })

  test('an anchor the user said below the warning threshold, in a turn that ended past both, clears the warning too', async ($, on) => {
    const scene = createScene($, { on })
    await scene.start()
    const turnId = await scene.startTurn(10)
    await scene.callTool(30, { tool: 'Write', file_path: NOTE, content: NOTE_TEXT })
    await scene.callTool(30, { tool: 'Bash', command: scene.world.paths.saveCommand })
    await scene.endTurn(turnId, { percent: 56 })

    const next = await scene.startTurn(57)
    const out = await scene.callTool(57, READ)
    await scene.endTurn(next, { percent: 57 })

    expect(getContext(out)).toEqual([])
    expect(scene.world.getStage()).toMatchObject({ stage: 'saved', reason: 'manual' })
  })

  test('CLAUDE_CONFIG_DIR with a doubled slash at its end: the marker folder of handoff.py is read', async ($, on) => {
    const scene = createScene($, { on, configDir: '/alt//', configRoot: '/alt/' })
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('the settings folder as a link: a full anchor is saved', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setLink('/home/u/.claude', '/data/claude')
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })

  test('the memory folder as a link: a full anchor is saved', async ($, on) => {
    const scene = createScene($, { on })
    scene.world.setLink(scene.world.paths.memory, '/data/memory')
    await scene.askToAnchor()

    await scene.runAnchorTurn({ steps: getFullSave(scene) })

    expect(scene.world.getStage()).toMatchObject({ stage: 'saved' })
  })
})
