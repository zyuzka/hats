import { describe, expect, test } from 'claude-code/testing'
import {
  CANCELLED_LINE,
  DEFAULTS,
  REASONS,
  RELOADED_LINE,
  STOPPED_SAVED_LINE,
  STOPPED_UNCHECKED_LINE,
  createArm,
  createStageRecord,
  findHandoffCommand,
  findNewNote,
  findNoteVerdict,
  findRefusalOutcome,
  findMissingIds,
  findRounds,
  findSaveOutcome,
  findSnapshot,
  findStepsOutcome,
  findStepsReason,
  findThresholds,
  getClearRefusal,
  getHandedKey,
  getHandedPath,
  getInputKind,
  getFailedLine,
  getPercent,
  getRequestLine,
  getSavedLine,
  getStoppedFailedLine,
  getSha256,
  getStamp,
  getStampSeconds,
  getTurnFailure,
  getWarningText,
  hasNowHeading,
  isMarkerFresh,
  isMarkerPlace,
  isHandedTo,
  isMarkerShape,
  isNoteCandidate,
  isSaveDue,
  isExactStepsCommand,
  isSessionId,
  isStepsCommand,
  isWarnDue,
  setArm,
} from '../../hooks/thresholds.js'
import {
  CONTINUE_ID_LIMIT,
  CONTINUE_OUTPUT_LIMIT,
  CONTINUE_STATUS_LIMIT,
  CONTINUE_TASKS_HEAD,
  CONTINUE_TASK_LIMIT,
  getContinueText,
} from '../../hooks/continue-text.js'

const ROOT = '/p'
const SAVE = `sh "${ROOT}/scripts/py.sh" "${ROOT}/scripts/handoff.py" save --note "/n.md" --topic "t"`
const NEW = `sh "${ROOT}/scripts/py.sh" "${ROOT}/scripts/handoff.py" new --slug a --memory "/m"`
const ROOTS = {
  memoryRoot: '/c/projects',
  notesRoot: '/h/Library/Application Support/Hats/notes',
}
const MARKER = {
  pid: 7,
  started: 'Sat Nov 14 16:30:56 2026',
  cwd: '/w',
  note: '/c/projects/-w/memory/resume-a.md',
  topic: 'a',
  saved_at: '2026-11-14T16:33:17Z',
}
const NOTE = {
  kind: 'file',
  size: 10,
  mtimeMs: 2000,
  askedAtMs: 1000,
  text: '# A\n\n## NOW\n\nnext',
  before: 'absent',
  own: 'x',
  sha: 'x',
}
const DRAIN_OFF = { drain: false, drainMinutes: 10 }
const BOTH = { warn: 45, save: 55, after: 'offer_clear', ...DRAIN_OFF }
const ONLY_SAVE = { warn: null, save: 55, after: 'tell', ...DRAIN_OFF }
const ONLY_WARN = { warn: 45, save: null, after: 'tell', ...DRAIN_OFF }
const NONE = { warn: null, save: null, after: 'tell', ...DRAIN_OFF }
const ASKED_AT = Date.parse('2026-11-14T16:33:17.900Z')
const HEADINGS = [
  { line: '## NOW', isHeading: true },
  { line: '## Now — x', isHeading: true },
  { line: '##  NOW:', isHeading: true },
  { line: '## NOW- x', isHeading: true },
  { line: '## NOW2', isHeading: true },
  { line: '## now', isHeading: true },
  { line: '## NOW (x)', isHeading: true },
  { line: '## NOW,', isHeading: true },
  { line: '## NOW\r', isHeading: true },
  { line: '## СЕЙЧАС', isHeading: true },
  { line: '## СЕЙЧАС-2', isHeading: true },
  { line: '## СЕЙЧАС —', isHeading: true },
  { line: '## NOWHERE', isHeading: false },
  { line: '## NOW-x', isHeading: false },
  { line: '## СЕЙЧАСx', isHeading: false },
  { line: '## СЕЙЧАСА', isHeading: false },
  { line: '## СЕЙЧАС_', isHeading: false },
  { line: '## СЕЙЧАС1', isHeading: false },
  { line: '## сейчас', isHeading: false },
  { line: '# NOW', isHeading: false },
  { line: 'text ## NOW', isHeading: false },
  { line: '##NOW', isHeading: false },
]

const json = (value: unknown) => JSON.stringify(value)

const getPercentOf = (percent: unknown) => getPercent({ context: { window: 1, percent } })

const findFile = (warn: unknown, save: unknown) => findThresholds(json({ warn_percent: warn, save_percent: save, after_save: 'tell' }))

const getFlags = (arm: any) => ({ warn: arm.warn, save: arm.save })

describe('the window percent', () => {
  test('is a whole number from 0 to 100, else nothing', () => {
    expect(getPercentOf(47)).toBe(47)
    expect(getPercentOf(0)).toBe(0)
    expect(getPercentOf(100)).toBe(100)
    expect(getPercentOf(47.5)).toBe(null)
    expect(getPercentOf(-1)).toBe(null)
    expect(getPercentOf(101)).toBe(null)
    expect(getPercentOf('47')).toBe(null)
    expect(getPercent({ context: { window: 1 } })).toBe(null)
    expect(getPercent(null)).toBe(null)
  })
})

describe('the thresholds file', () => {
  test('is replaced, when there is none, by 60%, 70% and the /clear offer', () => {
    expect(DEFAULTS).toEqual({ warn: 60, save: 70, after: 'offer_clear', ...DRAIN_OFF })
  })

  test('holds two thresholds and the action after the save', () => {
    expect(findThresholds(json({ warn_percent: 60, save_percent: 70, after_save: 'offer_clear' }))).toEqual(DEFAULTS)
    expect(findThresholds(json({ warn_percent: null, save_percent: 55, after_save: 'tell' }))).toEqual(ONLY_SAVE)
    expect(findThresholds(json({ warn_percent: 45, save_percent: null, after_save: 'tell' }))).toEqual(ONLY_WARN)
    expect(findThresholds(json({ warn_percent: null, save_percent: null, after_save: 'tell' }))).toEqual(NONE)
    expect(findThresholds(json({ warn_percent: 45, save_percent: 55, after_save: 'offer_exit' }))?.after).toBe('offer_exit')
  })

  test('takes the warning threshold from 10 to 94 and the save threshold from 11 to 95', () => {
    expect(findFile(10, 11)?.warn).toBe(10)
    expect(findFile(94, 95)?.save).toBe(95)
    expect(findFile(9, 55)).toBe(null)
    expect(findFile(95, null)).toBe(null)
    expect(findFile(null, 10)).toBe(null)
    expect(findFile(null, 96)).toBe(null)
  })

  test('is refused when the warning is not below the save', () => {
    expect(findFile(55, 55)).toBe(null)
    expect(findFile(60, 55)).toBe(null)
  })

  test('is refused when it is not JSON or a value is not a whole number or null', () => {
    expect(findThresholds('not json')).toBe(null)
    expect(findThresholds('[45, 55]')).toBe(null)
    expect(findThresholds('null')).toBe(null)
    expect(findFile(45.5, 55)).toBe(null)
    expect(findFile('45', 55)).toBe(null)
    expect(findFile(true, 55)).toBe(null)
    expect(findThresholds(json({ save_percent: 55, after_save: 'tell' }))).toBe(null)
  })

  test('reads an unknown action as tell', () => {
    expect(findThresholds(json({ warn_percent: 45, save_percent: 55, after_save: 'clear_now' }))?.after).toBe('tell')
    expect(findThresholds(json({ warn_percent: 45, save_percent: 55 }))?.after).toBe('tell')
  })
})

describe('arming', () => {
  test('arms both thresholds below the lowest and fires each once', () => {
    const arm = createArm()
    setArm(arm, { thresholds: BOTH, percent: 10 })
    expect(getFlags(arm)).toEqual({ warn: true, save: true })
    const past = { thresholds: BOTH, percent: 56 }
    setArm(arm, past)
    expect(isWarnDue(arm, past)).toBe(true)
    expect(isSaveDue(arm, past)).toBe(true)
    arm.warn = false
    arm.save = false
    setArm(arm, { thresholds: BOTH, percent: 50 })
    expect(getFlags(arm)).toEqual({ warn: false, save: true })
  })

  test('arms nothing while the window was never seen below the lowest threshold', () => {
    const arm = createArm()
    setArm(arm, { thresholds: BOTH, percent: 50 })
    const past = { thresholds: BOTH, percent: 60 }
    setArm(arm, past)
    expect(isWarnDue(arm, past)).toBe(false)
    expect(isSaveDue(arm, past)).toBe(false)
    setArm(arm, { thresholds: BOTH, percent: 44 })
    expect(getFlags(arm)).toEqual({ warn: true, save: true })
  })

  test('takes the remaining threshold as the lowest when one is off', () => {
    const arm = createArm()
    setArm(arm, { thresholds: ONLY_SAVE, percent: 50 })
    expect(getFlags(arm)).toEqual({ warn: false, save: true })
    expect(isWarnDue({ ...arm, warn: true }, { thresholds: ONLY_SAVE, percent: 60 })).toBe(false)
  })

  test('arms nothing when both thresholds are off', () => {
    const arm = createArm()
    setArm(arm, { thresholds: NONE, percent: 1 })
    expect(arm).toEqual(createArm())
  })
})

describe('the texts', () => {
  test('tell the model the warning and when the session anchors itself', () => {
    expect(getWarningText({ thresholds: BOTH, percent: 47 })).toBe(
      "Hats context threshold: this session's context window is at 47% (warning threshold 45%). " +
        'It anchors itself at the end of a turn once it reaches 55%. ' +
        'Tell the user so in one short line in your reply, in their language, and go on with the task.',
    )
    expect(getWarningText({ thresholds: BOTH, percent: 56 })).toContain(
      '(warning threshold 45%). It anchors itself at the end of this turn. Tell',
    )
    expect(getWarningText({ thresholds: ONLY_WARN, percent: 47 })).toContain('(warning threshold 45%). Tell the user')
  })

  test('tell the user the request, the save and the failure', () => {
    expect(getRequestLine(56, 55)).toBe('context 56% (anchor threshold 55%) — anchoring this session.')
    expect(getSavedLine({ percent: 56, save: 55, after: 'tell' })).toBe('anchored at 56% of the context window (threshold 55%).')
    expect(getSavedLine({ percent: 56, save: 55, after: 'offer_clear' })).toBe(
      'anchored at 56% of the context window (threshold 55%). ' +
        'Type /clear to go on from the note in an empty context: the plugin gives it back.',
    )
    expect(getSavedLine({ percent: 56, save: 55, after: 'offer_exit' })).toBe(
      'anchored at 56% of the context window (threshold 55%). ' +
        'Type /exit and start claude again in this folder: the new session lists this note.',
    )
    expect(getFailedLine(REASONS.stale)).toBe('the session was not anchored: stale marker. Say "anchor" to try again.')
    expect(CANCELLED_LINE).toBe('anchoring was cancelled before it started; the context was not saved.')
    expect(STOPPED_SAVED_LINE).toBe('anchoring was stopped; the note was saved.')
    expect(STOPPED_UNCHECKED_LINE).toBe(
      'anchoring was stopped; whether the note was saved could not be checked. Say "anchor" to save.',
    )
    expect(getStoppedFailedLine(REASONS.notRewritten)).toBe(
      'anchoring was stopped; the note was not saved: the note was not rewritten in this anchor. Say "anchor" to save.',
    )
    expect(RELOADED_LINE).toBe('anchoring was not checked: the plugin reloaded. Say "anchor" to save again.')
  })
})

describe('the marker', () => {
  test('has the fields of handoff.py, pid a whole number', () => {
    expect(isMarkerShape(MARKER)).toBe(true)
    expect(isMarkerShape({ ...MARKER, pid: true })).toBe(false)
    expect(isMarkerShape({ ...MARKER, pid: '7' })).toBe(false)
    expect(isMarkerShape({ ...MARKER, topic: undefined })).toBe(false)
    expect(isMarkerShape({ ...MARKER, note: '' })).toBe(false)
    expect(isMarkerShape({ ...MARKER, cwd: 'a\0b' })).toBe(false)
    expect(isMarkerShape(null)).toBe(false)
  })

  test('is fresh when saved in the second of the request or later', () => {
    expect(isMarkerFresh('2026-11-14T16:33:17Z', ASKED_AT)).toBe(true)
    expect(isMarkerFresh('2026-11-14T16:33:18Z', ASKED_AT)).toBe(true)
    expect(isMarkerFresh('2026-11-14T16:33:16Z', ASKED_AT)).toBe(false)
    expect(isMarkerFresh('2026-11-14 16:33:17', ASKED_AT)).toBe(false)
  })

  test('stamps round-trip and refuse an impossible date', () => {
    expect(getStamp(ASKED_AT)).toBe('2026-11-14T16:33:17Z')
    expect(getStampSeconds('2026-11-14T16:33:17Z')).toBe(Date.parse('2026-11-14T16:33:17Z') / 1000)
    expect(getStampSeconds('2026-02-30T00:00:00Z')).toBe(null)
  })

  test('lies directly in the handoff state folder', () => {
    expect(isMarkerPlace('/c/state/handoff/1-x.json', '/c/state/handoff')).toBe(true)
    expect(isMarkerPlace('/c/state/handoff/sub/1-x.json', '/c/state/handoff')).toBe(false)
    expect(isMarkerPlace('/c/state/other/1-x.json', '/c/state/handoff')).toBe(false)
    expect(isMarkerPlace('state/handoff/1-x.json', 'state/handoff')).toBe(false)
  })
})

describe('the NOW heading, as handoff.py reads it', () => {
  for (const { line, isHeading } of HEADINGS) {
    test(`${JSON.stringify(line)} is ${isHeading ? '' : 'not '}a heading`, () => {
      expect(hasNowHeading(`# Note\n\n${line}\n\nrest`)).toBe(isHeading)
    })
  }
})

describe('the handoff commands of the skill', () => {
  test('are new and save through py.sh of one plugin root', () => {
    expect(findHandoffCommand(SAVE)).toBe('save')
    expect(findHandoffCommand(NEW)).toBe('new')
    expect(findHandoffCommand(`sh "/a/scripts/py.sh" "/b/scripts/handoff.py" save --note "/n.md"`)).toBe(null)
    expect(findHandoffCommand(`sh "${ROOT}/scripts/py.sh" "${ROOT}/scripts/handoff.py" saved`)).toBe(null)
    expect(findHandoffCommand(`sh "${ROOT}/scripts/py.sh" "${ROOT}/scripts/handoff.py" start`)).toBe(null)
    expect(findHandoffCommand(`echo x; ${SAVE}`)).toBe(null)
    expect(findHandoffCommand(undefined)).toBe(null)
  })

  test('save prints the last marker line or that handoff is off', () => {
    expect(findSaveOutcome('marker: /c/state/handoff/1-x.json\nindex: updated\nMEMORY.md: has the index line')).toEqual({
      kind: 'marker',
      path: '/c/state/handoff/1-x.json',
    })
    expect(findSaveOutcome('marker: /a.json\nmarker: /b.json')).toEqual({ kind: 'marker', path: '/b.json' })
    expect(findSaveOutcome('handoff is off for /w — marker not written')).toEqual({ kind: 'off' })
    expect(findSaveOutcome('handoff: could not read the note /n.md')).toBe(null)
    expect(findSaveOutcome(undefined)).toBe(null)
  })

  test('new prints one absolute note path', () => {
    expect(findNewNote('/c/projects/-w/memory/resume-a.md\n')).toBe('/c/projects/-w/memory/resume-a.md')
    expect(findNewNote('handoff: the slug must be lowercase')).toBe(null)
    expect(findNewNote('resume-a.md')).toBe(null)
    expect(findNewNote('/a.md\n/b.md')).toBe(null)
  })
})

describe('a note save would take', () => {
  test('lies in a memory folder or in a project folder of the Hats notes', () => {
    expect(isNoteCandidate('/c/projects/-w/memory/resume-a.md', ROOTS)).toBe(true)
    expect(isNoteCandidate(`${ROOTS.notesRoot}/0123456789abcdef/a.md`, ROOTS)).toBe(true)
    expect(isNoteCandidate('/c/projects/-w/memory/resume-index.md', ROOTS)).toBe(false)
    expect(isNoteCandidate('/c/projects/-w/memory/MEMORY.md', ROOTS)).toBe(false)
    expect(isNoteCandidate('/c/projects/-w/memory/a.txt', ROOTS)).toBe(false)
    expect(isNoteCandidate('/c/projects/-w/other/a.md', ROOTS)).toBe(false)
    expect(isNoteCandidate('/elsewhere/-w/memory/a.md', ROOTS)).toBe(false)
    expect(isNoteCandidate(`${ROOTS.notesRoot}/project/a.md`, ROOTS)).toBe(false)
    expect(isNoteCandidate('/w/README.md', ROOTS)).toBe(false)
    expect(isNoteCandidate(null, ROOTS)).toBe(false)
  })
})

describe('the note verdict', () => {
  test('passes a non-empty note with a NOW section that this session rewrote after the request', () => {
    expect(findNoteVerdict(NOTE)).toBe(null)
    expect(findNoteVerdict({ ...NOTE, before: 'y' })).toBe(null)
  })

  test('refuses a note that was not rewritten in this anchor', () => {
    expect(findNoteVerdict({ ...NOTE, mtimeMs: 999 })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...NOTE, size: 0 })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...NOTE, kind: 'other' })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...NOTE, text: '# A\n\n## Later\n' })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...NOTE, before: undefined })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...NOTE, own: undefined, before: undefined })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...NOTE, before: 'x' })).toBe(REASONS.notRewritten)
  })

  test('refuses a note another writer changed after this session wrote it', () => {
    expect(findNoteVerdict({ ...NOTE, sha: 'z' })).toBe(REASONS.changed)
  })

  test('passes a note with no own write that was absent or different before the request, by any writer', () => {
    const unowned = { ...NOTE, own: undefined }
    expect(findNoteVerdict(unowned)).toBe(null)
    expect(findNoteVerdict({ ...unowned, before: 'y' })).toBe(null)
  })

  test('refuses a note with no own write and no state before the request, or the same, old, or without NOW', () => {
    const unowned = { ...NOTE, own: undefined }
    expect(findNoteVerdict({ ...unowned, before: undefined })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...unowned, before: 'x' })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...unowned, mtimeMs: 999 })).toBe(REASONS.notRewritten)
    expect(findNoteVerdict({ ...unowned, text: '# A\n\n## Later\n' })).toBe(REASONS.notRewritten)
  })

  test('with an own write keeps the old checks', () => {
    expect(findNoteVerdict({ ...NOTE, sha: 'z' })).toBe(REASONS.changed)
    expect(findNoteVerdict({ ...NOTE, before: undefined })).toBe(REASONS.notRewritten)
  })
})

describe('the stage file', () => {
  test('carries the stage, the rounds, the thresholds and the time', () => {
    const state = {
      id: 's1',
      cwd: '/w',
      stage: 'requested',
      warnRound: 1,
      saveRound: 2,
      percent: 56,
      thresholds: BOTH,
      reason: null,
      marker: null,
    }
    const record = {
      session: 's1',
      cwd: '/w',
      stage: 'requested',
      warn_round: 1,
      save_round: 2,
      percent: 56,
      warn_percent: 45,
      save_percent: 55,
      after_save: 'offer_clear',
      drain_minutes: null,
      reason: null,
      marker: null,
      at: '2026-11-14T16:33:17Z',
      limits: { five_hour: null, seven_day: null },
    }
    expect(json(createStageRecord(state, ASKED_AT))).toBe(json(record))
  })

  test('gives back its rounds only for the same session', () => {
    const text = json({ session: 's1', stage: 'warned', warn_round: 2, save_round: 1, percent: 47 })
    expect(findRounds(text, 's1')).toEqual({ warnRound: 2, saveRound: 1, stage: 'warned', percent: 47 })
    expect(findRounds(json({ session: 's1', warn_round: 0, save_round: 1, percent: 101 }), 's1')?.percent).toBe(null)
    expect(findRounds(text, 's2')).toBe(null)
    expect(findRounds(json({ session: 's1', warn_round: -1, save_round: 0 }), 's1')).toBe(null)
    expect(findRounds('{', 's1')).toBe(null)
  })

  test('is named by a whole session id only', () => {
    expect(isSessionId('ba964b9a-a7bd-4974-a8c5-951037faae99')).toBe(true)
    expect(isSessionId('../x')).toBe(false)
    expect(isSessionId('')).toBe(false)
  })
})

describe('SHA-256', () => {
  test('is the hex digest of the UTF-8 text', async () => {
    expect(await getSha256('')).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    expect(await getSha256('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
  })
})

describe('a refused /hats:anchor', () => {
  const previous = { stage: 'warned', reason: null, marker: null, saveRound: 1, percent: 47, thresholds: BOTH }

  test('after Esc, with the text measured in М6, gives back the stage and the round before the request and arms the save again', () => {
    const outcome = findRefusalOutcome('hats: $.command.run: the session was stopped and nobody has sent input since', previous)

    expect(outcome).toEqual({ kind: 'stopped', fields: previous, isSaveArmed: true })
  })

  test('for another text fails with that text', () => {
    expect(findRefusalOutcome('no implementation for command.run', previous)).toEqual({
      kind: 'failed',
      reason: 'the anchor command was refused: no implementation for command.run',
    })
  })
})

describe('an anchor turn that did not answer', () => {
  test('names its reason', () => {
    expect(getTurnFailure('refusal')).toBe('the anchor turn was refused')
    expect(getTurnFailure('error')).toBe('the anchor turn ended in an error')
    expect(getTurnFailure('cancelled')).toBe('the anchor turn ended: cancelled')
  })
})

describe('a refused own /clear', () => {
  test('names the refusal after Esc, with the text measured in М6', () => {
    expect(getClearRefusal('hats: $.command.run: the session was stopped and nobody has sent input since')).toBe(
      'the session was stopped and nobody has sent input since',
    )
  })

  test('names a /clear dropped from the queue, with the text of api.md', () => {
    expect(getClearRefusal('hats: $.command.run: the command was removed from the queue before it ran')).toBe(
      'the command was removed from the queue before it ran',
    )
  })

  test('quotes any other refusal', () => {
    expect(getClearRefusal('no implementation for command.run')).toBe('the clear command was refused: no implementation for command.run')
  })
})

describe('the output of the own steps command', () => {
  const ROOTED = `sh "${ROOT}/scripts/py.sh" "${ROOT}/scripts/anchor-steps.py"`

  test('is the steps command only with one root for both paths', () => {
    expect(isStepsCommand(ROOTED)).toBe(true)
    expect(isStepsCommand(`${ROOTED} --cwd "/w"`)).toBe(true)
    expect(isStepsCommand(`${ROOTED}; echo hi`)).toBe(true)
    expect(isStepsCommand(`sh "/a/scripts/py.sh" "/b/scripts/anchor-steps.py"`)).toBe(false)
    expect(isStepsCommand(SAVE)).toBe(false)
    expect(isStepsCommand(undefined)).toBe(false)
  })

  test('is read only as the exact command: anything after it makes its output unreadable', () => {
    expect(isExactStepsCommand(ROOTED)).toBe(true)
    expect(isExactStepsCommand(`${ROOTED}  `)).toBe(true)
    expect(isExactStepsCommand(`${ROOTED} | grep -v after`)).toBe(false)
    expect(isExactStepsCommand(`${ROOTED} > /tmp/x`)).toBe(false)
    expect(isExactStepsCommand(`${ROOTED}; echo hi`)).toBe(false)
    expect(isExactStepsCommand(`${ROOTED} --cwd "/w"`)).toBe(false)
    expect(isExactStepsCommand(`sh "/a/scripts/py.sh" "/b/scripts/anchor-steps.py"`)).toBe(false)
  })

  test('reads an after list, none, no own steps and anything else', () => {
    expect(findStepsOutcome('before anchor: none\nafter anchor:\n1. [general] push\n')).toBe('after')
    expect(findStepsOutcome('before anchor:\n1. [general] hi\nafter anchor: none\n')).toBe('none')
    expect(findStepsOutcome('no own steps\n')).toBe('none')
    expect(findStepsOutcome('anchor-steps: OSError: boom\n')).toBe('unread')
    expect(findStepsOutcome('')).toBe('unread')
    expect(findStepsOutcome(undefined)).toBe('unread')
  })

  test('keeps the session for an after list or an unread output, and for none at all', () => {
    expect(findStepsReason([
      'none',
      'after',
    ])).toBe('own after-steps ran')
    expect(findStepsReason([
      'none',
      'unread',
    ])).toBe('own steps could not be read')
    expect(findStepsReason([])).toBe('own steps could not be read')
    expect(findStepsReason([
      'none',
      'none',
    ])).toBeNull()
  })
})

describe('the stop snapshot as the mod reads it', () => {
  const TASKS = [
    { id: 'b1', type: 'shell' },
  ]
  const UNNAMED = [
    { type: 'shell' },
  ]
  const SNAP = { session: 's-1', at_ms: 1000, ok: true, tasks: TASKS, crons: 0 }

  test('takes a whole snapshot of its own session', () => {
    expect(findSnapshot(JSON.stringify(SNAP), 's-1')).toMatchObject({ kind: 'snapshot', at: 1000, ok: true, crons: 0 })
    expect(findSnapshot(JSON.stringify(SNAP), 's-1').ids).toEqual(TASKS.map(task => task.id))
  })

  test('calls a snapshot of another session or shape bad', () => {
    expect(findSnapshot(JSON.stringify(SNAP), 's-2')).toEqual({ kind: 'bad' })
    expect(findSnapshot(JSON.stringify({ ...SNAP, crons: -1 }), 's-1')).toEqual({ kind: 'bad' })
    expect(findSnapshot(JSON.stringify({ ...SNAP, at_ms: '1000' }), 's-1')).toEqual({ kind: 'bad' })
    expect(findSnapshot(JSON.stringify({ ...SNAP, tasks: UNNAMED }), 's-1')).toEqual({ kind: 'bad' })
    expect(findSnapshot('{', 's-1')).toEqual({ kind: 'bad' })
  })
})

describe('a background id named in the note', () => {
  const NAMINGS = [
    { note: 'x_10 runs', id: 'x_1', isNamed: false },
    { note: 'b-10 runs', id: 'b-1', isNamed: false },
    { note: 'ab7x and b7xя', id: 'b7x', isNamed: false },
    { note: 'axb', id: 'a.b', isNamed: false },
    { note: 'anything', id: '', isNamed: false },
    { note: 'b7x_2 runs', id: 'b7x', isNamed: false },
    { note: 'old_b7x runs', id: 'b7x', isNamed: false },
    { note: 'b7x-old runs', id: 'b7x', isNamed: false },
    { note: 'pre-b7x runs', id: 'b7x', isNamed: false },
    { note: 'b7x\n- (b7x) and «b7x»', id: 'b7x', isNamed: true },
    { note: '- x_1: sleep', id: 'x_1', isNamed: true },
    { note: 'ends with a.b', id: 'a.b', isNamed: true },
  ]

  test('counts only as a word of its own', () => {
    const found = NAMINGS.map(row => ({ ...row, isNamed: findMissingIds(row.note, Array.of(row.id)).length === 0 }))

    expect(found).toEqual(NAMINGS)
  })
})

describe('the note given back after /clear', () => {
  const MARKER_PATH = '/c/state/handoff/42-Sat.json'
  const HANDED = { path: getHandedPath(MARKER_PATH), key: getHandedKey({ saved_at: '2026-11-14T12:00:00Z', note: '/n.md' }), session: 'n1' }

  test('sits beside the marker and is keyed by the save time and the note, as handoff.py writes it', () => {
    expect(HANDED.path).toBe('/c/state/handoff/42-Sat.handed')
    expect(HANDED.key).toBe('2026-11-14T12:00:00Z|/n.md')
  })

  test('counts only with that key and that session', () => {
    expect(isHandedTo('{"key": "2026-11-14T12:00:00Z|/n.md", "session": "n1"}', HANDED)).toBe(true)
    expect(isHandedTo('{"key": "2026-11-14T12:00:00Z|/n.md", "session": "n0"}', HANDED)).toBe(false)
    expect(isHandedTo('{"key": "x", "session": "n1"}', HANDED)).toBe(false)
    expect(isHandedTo('not json', HANDED)).toBe(false)
    expect(isHandedTo('null', HANDED)).toBe(false)
  })
})

describe('the kind of an input', () => {
  test('is null for the plugin itself and the kind for everyone else', () => {
    expect(getInputKind({ kind: 'plugin', name: 'hats', asUser: true })).toBeNull()
    expect(getInputKind({ kind: 'plugin', name: 'other' })).toBe('plugin')
    expect(getInputKind({ kind: 'composer' })).toBe('composer')
    expect(getInputKind({})).toBe('unexpected')
    expect(getInputKind(null)).toBe('unexpected')
    expect(getInputKind(undefined)).toBe('unexpected')
  })
})

describe('the prompt after the own clear', () => {
  const createTask = (_: unknown, index: number) => ({
    id: `t${index}`,
    status: 'completed',
    output: `/o/t${index}`,
  })

  const getTaskLines = (text: string) => text.split('\n').filter(line => line.startsWith('- '))

  test('names no task when no notice came', () => {
    expect(getContinueText(56, [])).toBe(getContinueText(56))
    expect(getContinueText(56)).not.toContain(CONTINUE_TASKS_HEAD)
  })

  test('names each task by its id, its state and its output, after a line on what to do with them', () => {
    const text = getContinueText(56, [
      createTask(null, 0),
    ])

    expect(text).toBe(`${getContinueText(56)}\n\n${CONTINUE_TASKS_HEAD}\n- t0: completed; output: /o/t0`)
  })

  test('names at most 10 tasks and says how many more were left out', () => {
    const tasks = Array.from({ length: 12 }, createTask)

    const text = getContinueText(56, tasks)

    expect(CONTINUE_TASK_LIMIT).toBe(10)
    expect(getTaskLines(text).length).toBe(10)
    expect(getTaskLines(text)[9]).toBe('- t9: completed; output: /o/t9')
    expect(text.endsWith('\nand 2 more not listed')).toBe(true)
  })

  test('ten tasks need no line about more', () => {
    const text = getContinueText(56, Array.from({ length: 10 }, createTask))

    expect(getTaskLines(text).length).toBe(10)
    expect(text).not.toContain('more not listed')
  })

  test('cuts each field at its limit by characters and keeps it on one line', () => {
    const pair = '\u{1F600}'
    const task = {
      id: `${pair.repeat(70)}`,
      status: `done\nnow ${'s'.repeat(40)}`,
      output: `/o/${'p'.repeat(400)}`,
    }

    const line = getTaskLines(getContinueText(56, [task]))[0]

    expect([CONTINUE_ID_LIMIT, CONTINUE_STATUS_LIMIT, CONTINUE_OUTPUT_LIMIT]).toEqual([64, 32, 300])
    const status = `done now ${'s'.repeat(40)}`.slice(0, 32)
    const output = `/o/${'p'.repeat(400)}`.slice(0, 300)
    expect(line).toBe(`- ${pair.repeat(64)}: ${status}; output: ${output}`)
  })

  test('says what a notice left out', () => {
    const text = getContinueText(56, [{ id: 'a1', status: null, output: null }])

    expect(text.endsWith('\n- a1: no status; output: none')).toBe(true)
  })
})
