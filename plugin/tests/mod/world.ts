import { mock } from 'claude-code/testing'

export const HOME = '/home/u'
export const CONFIG = `${HOME}/.claude`
export const MEMORY = `${CONFIG}/projects/-w/memory`
export const NOTE = `${MEMORY}/resume-task.md`
export const HANDOFF = `${CONFIG}/state/handoff`
export const MARKER = `${HANDOFF}/42-Sat-Nov-14-12-00-00-2026.json`
export const STATE = '/hats-state'
export const STAGES = `${STATE}/session-thresholds`
export const THRESHOLDS = `${STATE}/window-thresholds.json`
export const PLUGIN = '/plugin'
export const SESSION = 'ba964b9a-a7bd-4974-a8c5-951037faae99'
export const OTHER_SESSION = '0f1e2d3c-4b5a-4968-8778-695a4b3c2d1e'
export const START = Date.parse('2026-11-14T12:00:00Z')
export const NOTE_TEXT = '# Task\n\n## NOW\n\nnext step\n'
export const STAGE_FILE = `${STAGES}/${SESSION}.json`
export const SNAPSHOTS = `${STATE}/stop-snapshots`
export const SNAPSHOT = `${SNAPSHOTS}/${SESSION}.json`
export const NEXT_SESSION = '7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f'
export const HANDED = `${CONFIG}/state/handoff/42-Sat-Nov-14-12-00-00-2026.handed`

type Entry = { text: string; mtimeMs: number; kind: 'file' | 'dir' | 'other' }

type SceneOptions = { on: any; hasRunHook?: boolean; hasStateHome?: boolean; configDir?: string; configRoot?: string }

type Ending = { percent?: number; reason?: string; agentId?: string }

type AnchorTurn = { steps: (() => Promise<unknown>)[]; endPercent?: number; reason?: string }

export const createPaths = (config: string) => {
  const memory = `${config}/projects/-w/memory`
  const note = `${memory}/resume-task.md`
  const handoff = `${config}/state/handoff`

  return {
    config,
    memory,
    note,
    handoff,
    marker: `${handoff}/42-Sat-Nov-14-12-00-00-2026.json`,
    newCommand: `sh "${PLUGIN}/scripts/py.sh" "${PLUGIN}/scripts/handoff.py" new --slug task --memory "${memory}"`,
    stepsCommand: `sh "${PLUGIN}/scripts/py.sh" "${PLUGIN}/scripts/anchor-steps.py"`,
    saveCommand: `sh "${PLUGIN}/scripts/py.sh" "${PLUGIN}/scripts/handoff.py" save --note "${note}" --topic "task"`,
  }
}

const getFolders = (paths: ReturnType<typeof createPaths>) => [
  HOME,
  paths.config,
  `${paths.config}/projects`,
  `${paths.config}/projects/-w`,
  paths.memory,
  `${paths.config}/state`,
  paths.handoff,
  STATE,
  STAGES,
  SNAPSHOTS,
]

const getStamp = (ms: number) => `${new Date(ms).toISOString().slice(0, 19)}Z`

export const createBashResult = (stdout: string) => ({
  result: { stdout, stderr: '', interrupted: false, isImage: false, noOutputExpected: false },
  text: stdout,
})

const createWorld = (options: SceneOptions) => {
  const { on } = options
  const clock = mock.clock(on, { now: START })
  const isStateHome = options.hasStateHome !== false
  const configEnv = options.configDir === undefined ? {} : { CLAUDE_CONFIG_DIR: options.configDir }
  mock.env(on, isStateHome ? { HOME, HATS_STATE_HOME: STATE, ...configEnv } : { HOME, ...configEnv })
  const files = new Map<string, Entry>()
  const links = new Map<string, string>()
  const paths = createPaths(options.configRoot ?? CONFIG)
  const resolve = (path: string) => {
    let real = path.replace(/\/{2,}/g, '/')
    for (let hop = 0; hop < 8; hop += 1) {
      const link = [...links.keys()].find(from => real === from || real.startsWith(`${from}/`))
      if (link === undefined) return real
      real = `${links.get(link)}${real.slice(link.length)}`
    }

    return real
  }
  const world = {
    clock,
    files,
    links,
    paths,
    resolve,
    percent: undefined as number | undefined,
    sessionId: SESSION,
    runs: [] as string[],
    logs: [] as string[],
    writes: [] as { path: string; text: string }[],
    writeAttempts: 0,
    isWriteDenied: false,
    isStatDenied: false,
    unreadableUntilWrite: null as string | null,
    otherReads: 0,
    sessionIdDenials: 0,
    dropNextPrompt: null as string | null,
    pendingRuns: [] as ((value: unknown) => void)[],
    prompts: [] as any[],
    nextToolAnswer: null as any,
    box: { text: '', cursor: 0 } as unknown,
    boxes: [] as unknown[],
    boxReads: 0,
    onBoxRead: null as null | ((count: number) => Promise<unknown>),
    isPluginGone: false,
    isExistsDenied: false,
    existsAsked: [] as string[],
    idReads: 0,
    onIdRead: null as null | ((count: number) => Promise<unknown>),
    handedAfterMs: 0,
    onStageWrite: null as null | ((stage: string) => Promise<unknown>),
    isHandedBack: true,
    clearAnswer: 'clear' as 'clear' | 'throw' | 'same',
    nextSessionId: NEXT_SESSION,
    onClear: null as null | (() => Promise<unknown>),
    endSession: async (_reason: string) => {},
    savedAt: null as string | null,
    setFile: (path: string, text: string, extra: Partial<Entry> = {}) => {
      files.set(resolve(path), { text, mtimeMs: clock.now(), kind: 'file', ...extra })
    },
    setFolder: (path: string) => {
      files.set(resolve(path), { text: '', mtimeMs: clock.now(), kind: 'dir' })
    },
    setLink: (path: string, target: string) => {
      for (const [key, entry] of [...files.entries()]) {
        if (key !== path && !key.startsWith(`${path}/`)) continue
        files.delete(key)
        files.set(`${target}${key.slice(path.length)}`, entry)
      }
      if (!files.has(target)) world.setFolder(target)
      links.set(path, target)
    },
    releaseRuns: () => {
      for (const release of world.pendingRuns.splice(0)) release({ text: '' })
    },
    getStage: (path = STAGE_FILE) => {
      const entry = files.get(path)

      return entry === undefined ? null : JSON.parse(entry.text)
    },
    getStageWrites: () => world.writes.filter(write => write.path === STAGE_FILE).map(write => JSON.parse(write.text)),
  }
  for (const folder of getFolders(paths)) world.setFolder(folder)

  return world
}

type World = ReturnType<typeof createWorld>

const answerFiles = (world: World, on: any) => {
  const { files } = world
  on('fs.exists', (_: any, e: any) => {
    world.existsAsked.push(e.path)
    const isPluginFile = e.path.endsWith('/plugin/scripts/handoff.py') && !world.isPluginGone
    if (isPluginFile && world.isExistsDenied) return { deny: 'EACCES: permission denied' }

    return { value: files.has(world.resolve(e.path)) || isPluginFile }
  })
  on('fs.stat', (_: any, e: any) => {
    const real = world.resolve(e.path)
    const entry = files.get(real)
    const isDenied = entry === undefined || (world.isStatDenied && e.path === STAGES)
    if (isDenied) return { deny: `ENOENT: no such file or directory, stat '${e.path}'` }
    const size = new TextEncoder().encode(entry.text).length
    const isLink = world.links.has(e.path.replace(/\/{2,}/g, '/'))
    const stat = { kind: entry.kind, size, mtimeMs: entry.mtimeMs, isLink }

    return { value: e.resolve ? { ...stat, realPath: real } : stat }
  })
  on('fs.read', (_: any, e: any) => {
    const entry = files.get(world.resolve(e.path))
    if (entry?.kind === 'other') world.otherReads += 1
    const isReadable = entry !== undefined && entry.kind === 'file' && world.unreadableUntilWrite !== e.path

    return isReadable ? { value: entry.text } : { deny: `ENOENT: no such file or directory, open '${e.path}'` }
  })
  on('fs.write', async (_: any, e: any) => {
    world.writeAttempts += 1
    if (world.isWriteDenied) return { deny: 'EACCES: permission denied' }
    world.writes.push({ path: e.path, text: e.text })
    world.setFile(e.path, e.text)
    if (e.path === STAGE_FILE && world.onStageWrite !== null) await world.onStageWrite(JSON.parse(e.text).stage)

    return { value: undefined }
  })
}

const answerBash = (world: World, command: string) => {
  const { paths } = world
  if (command === paths.newCommand) {
    if (!world.files.has(world.resolve(paths.note))) world.setFile(paths.note, '')
    return createBashResult(`${paths.note}\n`)
  }
  if (command !== paths.saveCommand) return createBashResult('')
  const marker = {
    pid: 42,
    started: 'Sat Nov 14 12:00:00 2026',
    cwd: '/w',
    note: paths.note,
    topic: 'task',
    saved_at: world.savedAt ?? getStamp(world.clock.now()),
  }
  world.setFile(paths.marker, JSON.stringify(marker, null, 1))

  return createBashResult(`marker: ${paths.marker}\nindex: updated\nMEMORY.md: has the index line\nquotes and numbers: all verified`)
}

const applyEdits = (text: string, edits: { old_string: string; new_string: string }[]) =>
  edits.reduce((result, edit) => result.replace(edit.old_string, edit.new_string), text)

const answerTool = (world: World, e: any) => {
  const answer = world.nextToolAnswer
  world.nextToolAnswer = null
  if (answer !== null) return answer
  if (world.unreadableUntilWrite === e.file_path) world.unreadableUntilWrite = null
  if (e.tool === 'Write') world.setFile(e.file_path, e.content)
  const before = world.files.get(world.resolve(e.file_path ?? ''))?.text ?? ''
  if (e.tool === 'Edit') world.setFile(e.file_path, before.replace(e.old_string, e.new_string))
  if (e.tool === 'MultiEdit') world.setFile(e.file_path, applyEdits(before, e.edits))

  return e.tool === 'Bash' ? answerBash(world, e.command) : { result: {} }
}

const runClear = async (world: World) => {
  if (world.clearAnswer === 'throw') throw new Error('the test refuses /clear')
  if (world.onClear !== null) await world.onClear()
  if (world.clearAnswer === 'same') return { text: '' }
  await world.endSession('clear')
  world.sessionId = world.nextSessionId
  const marker = world.files.get(world.resolve(world.paths.marker))
  if (world.isHandedBack && marker !== undefined) {
    const { saved_at, note } = JSON.parse(marker.text)
    const handed = { key: `${saved_at}|${note}`, session: world.sessionId }
    const writeHanded = () => world.setFile(world.paths.marker.replace(/\.json$/, '.handed'), JSON.stringify(handed))
    if (world.handedAfterMs === 0) writeHanded()
    else world.clock.sleep(world.handedAfterMs).then(writeHanded)
  }

  return { text: '' }
}

const answerEngine = (world: World, options: SceneOptions) => {
  const { on } = options
  on('session.usage', () => {
    const fill = world.percent === undefined ? {} : { tokens: world.percent * 10000, percent: world.percent }

    return { value: { startedAt: 0, context: { window: 1000000, ...fill }, rateLimits: [] } }
  })
  on('session.id', async () => {
    world.idReads += 1
    if (world.onIdRead !== null) await world.onIdRead(world.idReads)
    if (world.sessionIdDenials === 0) return { value: world.sessionId }
    world.sessionIdDenials -= 1

    return { deny: 'session.id refused for the test' }
  })
  on('ui.log', (_: any, e: any) => {
    world.logs.push(e.text)
    return { value: undefined }
  })
  if (options.hasRunHook !== false) {
    on('command.run', (_: any, e: any) => {
      world.runs.push(e.command)
      if (e.command === 'clear') return runClear(world)
      return new Promise(release => world.pendingRuns.push(release))
    })
  }
  on('prompt.read', async () => {
    world.boxReads += 1
    if (world.onBoxRead !== null) await world.onBoxRead(world.boxReads)

    return { value: world.boxes.length > 0 ? world.boxes.shift() : world.box }
  })
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('session.end', (_: any, e: any) => ({ sessionId: e.sessionId }))
  on('turn.start', (_: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('prompt.submit', (_: any, e: any) => {
    world.prompts.push(e)
    const drop = world.dropNextPrompt
    world.dropNextPrompt = null

    return drop === null ? { text: e.text, context: e.context, origin: e.origin } : { drop }
  })
  on('tool.call', (_: any, e: any) => answerTool(world, e))
}

let turnCount = 0

const completeTurn = ($: any, turnId: string, ending: Ending) => {
  const reason = ending.reason ?? 'answer'

  return $.turn.complete({
    answer: '',
    durationMs: 1000,
    isAborted: reason === 'aborted',
    turnId,
    reason,
    ...(reason === 'refusal' ? { refusal: { category: null, explanation: null } } : {}),
    ...(ending.agentId === undefined ? {} : { agentId: ending.agentId }),
  })
}

export const createScene = ($: any, options: SceneOptions) => {
  const world = createWorld(options)
  world.endSession = reason => $.session.end({ reason, sessionId: world.sessionId, resume: { id: world.sessionId } })
  answerFiles(world, options.on)
  answerEngine(world, options)
  const scene = {
    world,
    start: (isInteractive = true) => $.session.start({ cwd: '/w', surface: isInteractive ? 'terminal' : null, isInteractive }),
    end: (reason: string) => $.session.end({ reason, sessionId: world.sessionId, resume: { id: world.sessionId } }),
    startTurn: async (percent: number | undefined, agentId?: string) => {
      turnCount += 1
      const turnId = `turn-${turnCount}`
      world.percent = percent
      await $.turn.start({ text: 'go', turnId, ...(agentId === undefined ? {} : { agentId }) })
      await world.clock.advance(500)

      return turnId
    },
    endTurn: async (turnId: string, ending: Ending) => {
      world.percent = ending.percent
      await world.clock.advance(500)
      await completeTurn($, turnId, ending)
      await world.clock.settle()
    },
    callTool: async (percent: number | undefined, input: any) => {
      world.percent = percent
      const out = await $.tool.call(input)
      await world.clock.advance(200)

      return out
    },
    prompt: (text: string, command?: { name: string; args: string }) =>
      $.prompt.submit({ text, wait: false, origin: { kind: 'composer' }, ...(command === undefined ? {} : { command }) }),
    pluginPrompt: (name: string) => $.prompt.submit({ text: 'x', wait: false, origin: { kind: 'plugin', name } }),
    ownAnchor: () =>
      $.prompt.submit({
        text: '/hats:anchor',
        wait: false,
        origin: { kind: 'plugin', name: 'hats' },
        command: { name: 'hats:anchor', args: '' },
      }),
    askToAnchor: async () => {
      await scene.start()
      const turnId = await scene.startTurn(10)
      await scene.endTurn(turnId, { percent: 56 })
    },
    holdTurnEnd: async (turnId: string, ending: Ending) => {
      world.percent = ending.percent
      await world.clock.advance(500)
      const done = completeTurn($, turnId, ending)
      await world.clock.settle()

      return { done }
    },
    holdAnchorTurn: async (anchor: AnchorTurn) => {
      await scene.ownAnchor()
      world.releaseRuns()
      await world.clock.settle()
      const turnId = await scene.startTurn(56)
      for (const step of anchor.steps) await step()

      return scene.holdTurnEnd(turnId, { percent: anchor.endPercent ?? 58 })
    },
    runAnchorTurn: async (anchor: AnchorTurn) => {
      await scene.ownAnchor()
      world.releaseRuns()
      await world.clock.settle()
      const turnId = await scene.startTurn(56)
      for (const step of anchor.steps) await step()
      await scene.endTurn(turnId, { percent: anchor.endPercent ?? 58, reason: anchor.reason })
    },
    createNote: () => scene.callTool(57, { tool: 'Bash', command: world.paths.newCommand }),
    writeNote: (text = NOTE_TEXT) => scene.callTool(57, { tool: 'Write', file_path: world.paths.note, content: text }),
    runSave: () => scene.callTool(58, { tool: 'Bash', command: world.paths.saveCommand }),
    runSteps: (stdout = 'no own steps\n', tail = '') => {
      world.nextToolAnswer = createBashResult(stdout)

      return scene.callTool(58, { tool: 'Bash', command: `${world.paths.stepsCommand}${tail}` })
    },
    setSnapshot: (fields: Record<string, unknown> = {}) => {
      const snapshot = { session: SESSION, at_ms: world.clock.now(), ok: true, tasks: [], crons: 0, ...fields }
      world.setFile(SNAPSHOT, JSON.stringify(snapshot))
    },
  }

  return scene
}
