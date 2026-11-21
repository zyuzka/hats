import {
  REASONS,
  findHandoffCommand,
  findNewNote,
  findNoteVerdict,
  findSaveOutcome,
  findStepsOutcome,
  getMemoryLinkPaths,
  getNormalPath,
  getSha256,
  isMarkerFresh,
  isMarkerPlace,
  isMarkerShape,
  isMemoryLinkNote,
  isExactStepsCommand,
  isNoteCandidate,
  isStepsCommand,
} from './thresholds.js'
import {
  findRealPath,
  findSmallText,
  findTargetPath,
  findTextState,
  getConfigRoot,
  getNotesRoot,
} from './files.js'

export const createTurn = (id, startedAt) => ({
  id,
  startedAt,
  snapshots: new Map(),
  ownWrites: new Map(),
  save: null,
  steps: [],
})

const isReadableStepsCall = call =>
  call.out.deny === undefined &&
  call.out.isError !== true &&
  isExactStepsCommand(call.command)

export const recordStepsOutput = (turn, call) => {
  if (!isStepsCommand(call.command)) return
  turn.steps.push(isReadableStepsCall(call) ? findStepsOutcome(call.out.result?.stdout ?? call.out.text) : 'unread')
}

async function findNoteRoots($) {
  const notes = await getNotesRoot($)
  const config = await getConfigRoot($)
  const memoryRoot = config === null ? null : await findRealPath($, `${config}/projects`)
  const notesRoot = notes === null ? null : await findRealPath($, notes)

  return { memoryRoot, notesRoot }
}

async function isLinkedMemoryNote($, note) {
  const lexical = getNormalPath(note.path)
  const paths = getMemoryLinkPaths(lexical)

  return isMemoryLinkNote({
    lexical,
    real: note.real,
    memoryRoot: note.roots.memoryRoot,
    folderReal: await findRealPath($, paths.folder),
    projectsReal: await findRealPath($, paths.projects),
  })
}

async function findNoteTarget($, path) {
  const real = await findTargetPath($, path)
  if (real === null) return null
  const roots = await findNoteRoots($)
  if (isNoteCandidate(real, roots)) return real

  return (await isLinkedMemoryNote($, { path, real, roots })) ? real : null
}

export async function recordSnapshot($, write) {
  const { turn, path } = write
  const target = await findNoteTarget($, path)
  if (target === null || turn.snapshots.has(target)) return target
  const before = await findTextState($, target)
  if (before !== null && !turn.snapshots.has(target)) turn.snapshots.set(target, before)

  return target
}

export async function recordOwnWrite($, write) {
  const sha = await findTextState($, write.target)
  if (sha === null || sha === 'absent') return
  write.turn.ownWrites.set(write.target, sha)
}

export async function recordHandoffOutput($, call) {
  const { turn, command, out } = call
  const kind = findHandoffCommand(command)
  const stdout = out.result?.stdout ?? out.text
  if (kind === 'save') {
    const outcome = findSaveOutcome(stdout)
    if (outcome !== null) turn.save = outcome
    return
  }
  const created = kind === 'new' ? findNewNote(stdout) : null
  const target = created === null ? null : await findNoteTarget($, created)
  if (target !== null && !turn.snapshots.has(target)) turn.snapshots.set(target, 'absent')
}

async function findMarker($, path) {
  const text = await findSmallText($, path)
  if (text === null) return null
  try {
    const marker = JSON.parse(text)

    return isMarkerShape(marker) ? marker : null
  } catch {
    return null
  }
}

async function findNote($, path) {
  const stat = await $.fs.stat(path, { resolve: true }).catch(() => null)
  if (stat === null || stat.kind !== 'file') return null
  const text = await $.fs.read(path).catch(() => null)

  return text === null ? null : { stat, text }
}

export async function findAnchorFacts($, turn) {
  const marker = turn.save?.kind === 'marker' ? await findMarker($, turn.save.path) : null
  if (marker === null) return null
  const note = await findNote($, marker.note)
  const key = note?.stat.realPath ?? marker.note

  return { markerPath: turn.save.path, marker, notePath: marker.note, own: turn.ownWrites.get(key) }
}

export async function recordAcceptedNote($, turn) {
  const marker = turn.save?.kind === 'marker' ? await findMarker($, turn.save.path) : null
  const note = marker === null ? null : await findNote($, marker.note)
  if (note === null) return
  const key = note.stat.realPath ?? marker.note
  if (!turn.ownWrites.has(key)) turn.ownWrites.set(key, await getSha256(note.text))
}

export async function findNoteText($, path) {
  const note = await findNote($, path)

  return note === null ? null : note.text
}

export async function findVerdict($, check) {
  const { turn, askedAt } = check
  if (turn === null || turn.save === null) return REASONS.noMarker
  if (turn.save.kind === 'off') return REASONS.off
  const config = await getConfigRoot($)
  if (config === null || !isMarkerPlace(turn.save.path, `${config}/state/handoff`)) return REASONS.unreadable
  const marker = await findMarker($, turn.save.path)
  if (marker === null) return REASONS.unreadable
  if (!isMarkerFresh(marker.saved_at, askedAt)) return REASONS.stale
  const note = await findNote($, marker.note)
  if (note === null) return REASONS.notRewritten
  const key = note.stat.realPath ?? marker.note
  const own = turn.ownWrites.get(key)

  return findNoteVerdict({
    kind: note.stat.kind,
    size: note.stat.size,
    mtimeMs: note.stat.mtimeMs,
    askedAtMs: askedAt,
    text: note.text,
    before: turn.snapshots.get(key),
    own,
    sha: await getSha256(note.text),
    isNotePlace: own !== undefined || (await findNoteTarget($, marker.note)) !== null,
  })
}
