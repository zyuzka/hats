import {
  HANDED_STEP_MS,
  HANDED_WAIT_MS,
  KEPT,
  SNAPSHOT_FOLDER,
  SNAPSHOT_STEP_MS,
  SNAPSHOT_WAIT_MS,
  findMissingIds,
  findSnapshot,
  getMissingReason,
  getSha256,
  getWakeReason,
  isBoxShape,
  isHandedTo,
  isSessionId,
} from './thresholds.js'
import {
  findSmallText,
  getStateRoot,
} from './files.js'
import { findNoteText } from './anchor-check.js'

function pause($, ms) {
  return new Promise(resolve => {
    $.clock.after(ms, resolve)
  })
}

async function findSnapshotPath($, id) {
  const root = await getStateRoot($)
  if (root === null || !isSessionId(id)) return null
  const folder = await $.fs.stat(`${root}/${SNAPSHOT_FOLDER}`).catch(() => null)

  return folder === null || folder.isLink || folder.kind !== 'dir' ? null : `${root}/${SNAPSHOT_FOLDER}/${id}.json`
}

async function findSnapshotAfter($, want) {
  const path = await findSnapshotPath($, want.id)
  const text = path === null ? null : await findSmallText($, path)
  const snapshot = text === null ? { kind: 'none' } : findSnapshot(text, want.id)
  if (snapshot.kind === 'none') return snapshot
  if (snapshot.kind === 'snapshot') return snapshot.at <= want.getAfter() ? { kind: 'none' } : snapshot
  const stat = await $.fs.stat(path).catch(() => null)

  return stat !== null && stat.mtimeMs > want.getAfter() ? snapshot : { kind: 'none' }
}

export async function waitForSnapshot($, want) {
  const deadline = (await $.clock.now()) + SNAPSHOT_WAIT_MS
  for (;;) {
    const snapshot = await findSnapshotAfter($, want)
    if (snapshot.kind !== 'none' || (await $.clock.now()) >= deadline) return snapshot
    await pause($, SNAPSHOT_STEP_MS)
  }
}

export const getSnapshotReason = (snapshot, noteText) => {
  if (snapshot.kind === 'bad') return KEPT.unexpected
  if (snapshot.kind === 'none' || !snapshot.ok) return KEPT.noSnapshot
  if (snapshot.crons > 0) return getWakeReason(snapshot.crons)
  const missing = findMissingIds(noteText, snapshot.ids)

  return missing.length === 0 ? null : getMissingReason(missing)
}

export async function waitForHanded($, handed) {
  const deadline = (await $.clock.now()) + HANDED_WAIT_MS
  for (;;) {
    const text = await findSmallText($, handed.path)
    if (text !== null && isHandedTo(text, handed)) return true
    if ((await $.clock.now()) >= deadline) return false
    await pause($, HANDED_STEP_MS)
  }
}

export async function findNoteState($, facts) {
  const text = facts === null ? null : await findNoteText($, facts.notePath)
  if (text === null) return { reason: KEPT.noteUnread, text: '' }

  return { reason: (await getSha256(text)) === facts.own ? null : KEPT.noteChanged, text }
}

export async function isPluginInPlace($) {
  return $.fs.exists(`${$.plugin.root}/scripts/handoff.py`).catch(() => false)
}

export async function findPromptReason($) {
  const box = await $.prompt.read().catch(() => null)
  if (!isBoxShape(box)) return KEPT.unexpected

  return box.text.trim() === '' ? null : KEPT.draft
}

export async function findSessionReason($, id) {
  const now = await $.session.id()
  if (typeof now !== 'string') return KEPT.unexpected

  return now === id ? null : KEPT.sessionChanged
}
