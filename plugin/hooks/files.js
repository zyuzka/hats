import {
  DEFAULTS,
  FILE_LIMIT,
  HATS_FOLDER,
  STAGE_FOLDER,
  THRESHOLDS_FILE,
  createStageRecord,
  findRounds,
  findThresholds,
  getPercent,
  getSha256,
  isSessionId,
} from './thresholds.js'

export async function getHome($) {
  return (await $.env.get('HOME')) || null
}

export async function getStateRoot($) {
  const override = await $.env.get('HATS_STATE_HOME')
  if (override) return override
  const home = await getHome($)

  return home === null ? null : `${home}/${HATS_FOLDER}`
}

export async function getConfigRoot($) {
  const custom = await $.env.get('CLAUDE_CONFIG_DIR')
  const home = await getHome($)
  if (!custom || custom.includes('\0')) return home === null ? null : `${home}/.claude`
  const isHomeRelative = (custom === '~' || custom.startsWith('~/')) && home !== null
  const path = isHomeRelative ? `${home}${custom.slice(1)}` : custom

  return path.replace(/\/+$/, '') || '/'
}

export async function findRealPath($, path) {
  const stat = await $.fs.stat(path, { resolve: true }).catch(() => null)

  return stat?.realPath ?? null
}

export async function findTargetPath($, path) {
  if (typeof path !== 'string' || !path.startsWith('/')) return null
  const own = await findRealPath($, path)
  if (own !== null) return own
  const cut = path.lastIndexOf('/')
  const folder = await findRealPath($, path.slice(0, cut) || '/')

  return folder === null ? null : `${folder.replace(/\/$/, '')}/${path.slice(cut + 1)}`
}

export async function findTextState($, path) {
  const stat = await $.fs.stat(path).catch(() => null)
  if (stat === null) return (await $.fs.exists(path).catch(() => true)) ? null : 'absent'
  const text = stat.kind === 'file' ? await $.fs.read(path).catch(() => null) : null

  return text === null ? null : getSha256(text)
}

export async function findSmallText($, path) {
  const stat = await $.fs.stat(path).catch(() => null)
  if (stat === null || stat.isLink || stat.kind !== 'file' || stat.size > FILE_LIMIT) return null

  return $.fs.read(path).catch(() => null)
}

async function findCurrentThresholds($) {
  const root = await getStateRoot($)
  if (root === null) return { ...DEFAULTS }
  const path = `${root}/${THRESHOLDS_FILE}`
  if (!(await $.fs.exists(path).catch(() => true))) return { ...DEFAULTS }
  const text = await findSmallText($, path)

  return text === null ? null : findThresholds(text)
}

export async function findReading($) {
  const usage = await $.session.usage().catch(() => null)
  const percent = getPercent(usage)
  const thresholds = percent === null ? null : await findCurrentThresholds($)

  return thresholds === null ? null : { thresholds, percent }
}

export async function findStageFile($, id) {
  const root = await getStateRoot($)
  if (root === null || !isSessionId(id)) return null
  const text = await findSmallText($, `${root}/${STAGE_FOLDER}/${id}.json`)

  return text === null ? null : findRounds(text, id)
}

async function isWritablePlace($, place) {
  const folder = await $.fs.stat(place.folder).catch(() => null)
  if (folder === null || folder.isLink || folder.kind !== 'dir') return false
  const own = await $.fs.stat(place.file).catch(() => null)

  return own === null || (!own.isLink && own.kind === 'file')
}

export async function writeStage($, record) {
  if (!isSessionId(record.id)) return
  const root = await getStateRoot($)
  if (root === null) return
  const folder = `${root}/${STAGE_FOLDER}`
  const file = `${folder}/${record.id}.json`
  if (!(await isWritablePlace($, { folder, file }))) return
  const now = await $.clock.now()
  await $.fs.write(file, `${JSON.stringify(createStageRecord(record, now), null, 1)}\n`)
}
