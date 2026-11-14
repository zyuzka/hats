import {
  NOTES_FOLDER,
  REASONS,
  findHandoffCommand,
  findNewNote,
  findNoteVerdict,
  findSaveOutcome,
  getMemoryLinkPaths,
  getNormalPath,
  getSha256,
  isMarkerFresh,
  isMarkerPlace,
  isMarkerShape,
  isMemoryLinkNote,
  isNoteCandidate,
} from './thresholds.js'
import {
  findRealPath,
  findSmallText,
  findTargetPath,
  findTextState,
  getConfigRoot,
  getHome,
} from './files.js'

export const createTurn = (id, startedAt) => ({
  id,
  startedAt,
  snapshots: new Map(),
  ownWrites: new Map(),
  save: null,
})

async function findNoteRoots($) {
  const home = await getHome($)
  const config = await getConfigRoot($)
  const memoryRoot = config === null ? null : await findRealPath($, `${config}/projects`)
  const notesRoot = home === null ? null : await findRealPath($, `${home}/${NOTES_FOLDER}`)

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

  return findNoteVerdict({
    kind: note.stat.kind,
    size: note.stat.size,
    mtimeMs: note.stat.mtimeMs,
    askedAtMs: askedAt,
    text: note.text,
    before: turn.snapshots.get(key),
    own: turn.ownWrites.get(key),
    sha: await getSha256(note.text),
  })
}
