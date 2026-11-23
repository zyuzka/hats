const getContinueHead = percent =>
  `Hats: this session reached ${percent}% of its context window, was anchored and cleared. ` +
  'Continue the task from the resume note the plugin gave you after /clear: read the whole note with the Read tool, ' +
  'tell the user in one short line, in their language, which note you picked up, then go on with its next step.'

export const CONTINUE_TASK_LIMIT = 10
export const CONTINUE_ID_LIMIT = 64
export const CONTINUE_STATUS_LIMIT = 32
export const CONTINUE_OUTPUT_LIMIT = 300
export const CONTINUE_TASKS_HEAD =
  'These background tasks ended before the clear, even where the note calls them running; ' +
  'their notifications were read in the old session. ' +
  'Do not wait for them; read the output of a task only if the next step needs it:'

const getField = (value, limit) => Array.from(String(value).replace(/\s+/g, ' ').trim()).slice(0, limit).join('')

const getTaskLine = task =>
  `- ${getField(task.id, CONTINUE_ID_LIMIT)}: ${getField(task.status, CONTINUE_STATUS_LIMIT)}; ` +
  `output: ${task.output === null ? 'none' : getField(task.output, CONTINUE_OUTPUT_LIMIT)}`

export const getContinueText = (percent, tasks = []) => {
  const head = getContinueHead(percent)
  if (tasks.length === 0) return head
  const lines = tasks.slice(0, CONTINUE_TASK_LIMIT).map(getTaskLine)
  const rest = tasks.length - CONTINUE_TASK_LIMIT
  const more = rest > 0 ? [`and ${rest} more not listed`] : []

  return [
    `${head}\n\n${CONTINUE_TASKS_HEAD}`,
    ...lines,
    ...more,
  ].join('\n')
}
