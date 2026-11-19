---
name: anchor
description: Save this session's state for the next session — a resume note and a handoff marker — when the user's message is itself the anchor command, in any language («анкор», "anchor", «якорь») or typed as /hats:anchor, or when the user asks whether the session is anchored. Call it again on every later anchor command in the session. A message that only contains the word, such as "anchor the regex", is not the command, and other requests to save the session are not this skill's.
allowed-tools:
  - Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" *)
  - Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/anchor-steps.py")
  - Write(~/Library/Application Support/Hats/notes/**)
  - Edit(~/Library/Application Support/Hats/notes/**)
  - Read(~/Library/Application Support/Hats/notes/**)
---

# Anchor

Saves where this session stands, so the next one can pick it up: after `/clear` the plugin's start
hook gives this session's note back, and a new session started in the same folder lists the notes of
closed sessions. With Claude Code's memory on, the note sits in the memory folder, and
`resume-index.md` beside it, named by a line of `MEMORY.md`, lists it, so a session finds it even
without the plugin.
Every step is a command, and its output goes into the summary. The user's own steps,
if they have any, run before steps 1–4 and after them, on the anchor command only, and the user may
let one of them write the resume note instead of this skill.

## Steps

0. **Own steps before** — run exactly this command, also when the user only asks whether the session
   is anchored; it prints the user's own steps, from a general file in the Hats folder and from this
   project's `.claude/anchor-steps.json`, and who writes the resume note:

   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/anchor-steps.py"`

   Asked only whether the session is anchored, run it for its `note:` lines alone (step 3): carry out
   none of its steps and go on with step 1. On the anchor command, carry out the steps listed under
   `before anchor:` now, one by one in their order, keeping what each one printed, then go on with
   step 1; the `after anchor:` list is for step 5. A step `skill:<name>` (the prefix in any letter
   case) is a call of that skill with the Skill tool; any other step is an instruction to carry out.
   Never call anchor from a step, by any name or through another skill: this skill is already
   running. A step that fails — a skill call or a command that errs, an instruction you cannot carry
   out — stops nothing: note it for the summary and go on with the next step. A failed step that
   writes the resume note gives no note path, and then there is no handoff (step 3). If the command itself
   fails, note its first line and go on with step 1: the core never waits for own steps.
   `no own steps` means there are none.
1. **Each repository this session touched** — the working folder, if it is a repository, and any
   other repository you wrote to. In the working folder run the plain commands, each as its own call
   and written exactly so — Claude Code asks for approval of `@{u}`, quoted or not, and of `git cherry`:
   - `git status -sb` — uncommitted files, and on its first line the branch and its upstream,
     `## <branch>...<upstream> [ahead <n>]`.
   - `git log --oneline <upstream>..` — commits not pushed, `<upstream>` as that line names it (for
     example `origin/main`); only when the line says `ahead`.
   - `git stash list` — a stash you made is named, never left silent.

   If the first line names no upstream (`## <branch>` alone) or ends in `[gone]`, report "no upstream"
   and the branch's commits not on its base branch (`git log --oneline <base>..`); `## HEAD (no branch)`
   is a detached HEAD, say so. For another repository run the same three as `git -C <its literal absolute path> …`, one
   repository per command. Commit or push only what this session's work already called for and the
   project's rules allow; name everything else in the summary.
2. **Background work** — list the background tasks, monitors and subagents still running, in this
   turn, not from memory. Do not stop them to save. For each one note its id exactly as the task list shows it, what it is for
   and what it waits for: background commands and subagents outlive `/clear`, and the next session is
   told when one ends but not what it was for. A monitor ends with the session — note what it watched.
3. **Resume note** — one note per task: two sessions in one folder work on different tasks and would
   overwrite one shared note.
   - Who writes it, first: the `note:` lines the command of step 0 printed in this turn.
     - `note: written by own steps` — an own step writes the note, and this skill never writes to it
       or moves it, also after step 4: skip every other point of step 3. On the anchor command the
       note's path is the line `resume note: <path>` that a before step of this anchor command
       printed; a step that failed gives no path. Take that path exactly as printed, if there is
       exactly one (the same path printed twice is one) and it is absolute and holds none of `"`,
       `$`, a backquote, a backslash or a line break — it goes into a shell command. Otherwise skip
       step 4 and put the reason under "Not saved":
       `own steps write the note and printed no path` (adding `note: no before step to write it`
       when the command printed that line), `own steps printed several note paths: <paths>`,
       `the note path from own steps is not absolute: <path>` or
       `the note path from own steps holds <the character>: <path>`.
       Asked only whether the session is anchored, use the path this skill took at the latest
       anchor command of this session that took one; if none did, skip step 4 and put
       `Not saved: own steps run only on the anchor command`.
     - No `note:` line — this skill writes the note: go on with the points below.
     - The command of step 0 failed — the owner is unknown: this skill writes the note as below, and
       the summary says this task may now have two notes.
   - Which file, in this order:
     1. This task already has a note of its own — update it in place. Its own note is one the start
        hook gave this session (after `/clear`, or from its list when the user picked it), one the
        user picked from `resume-index.md`, one a line of `MEMORY.md` points to directly and that is
        about this task, or one this session already wrote. Write to no other note.
     2. Otherwise create the note with exactly this command. `<slug>` is the task's topic in
        lowercase latin letters and digits, words joined by single hyphens, up to 60 characters and
        not `index`; `<memory folder>` is the memory folder your instructions name for this working
        folder (Claude Code's memory):

        `sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" new --slug <slug> --memory "<memory folder>"`

        Output that starts with `handoff: the slug must be` refuses the slug: correct the slug and run
        the same command again, with the folder. Only when the command refuses the folder itself, or
        your instructions name no memory folder, run it without the folder and keep the refusal's
        first line for the summary:

        `sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" new --slug <slug>`

        It creates an empty note under a free name — never pick or create the file name yourself —
        and prints its path. Read that file with the Read tool, then write the note into it with
        Write. If the command fails otherwise, write no note, skip step 4, and report its first line
        in the summary: `needs python3` on the handoff line when it says `python3` is required,
        otherwise under "Not saved".
   - Contents: what is done (with commits), what is open, the next step, every decision taken without
     the user, and every background task and subagent from step 2 with what it is for. The current
     state goes under a `## NOW` heading — the start hook prints that section.
   - Read each fact off the system before writing it — branch, SHA, pull request state — not from the
     conversation.
   - A number or result from another file goes in only as a quote,
     `(cite: <absolute path>:<line> "exact text")` (quote marks «», "" or “”), with the number inside
     the quote; the source is a primary file, never a resume note or a memory note. Your own
     arithmetic goes in as `N of M (P%)`; a figure read off a command carries `(cmd: <command>)` in
     the same clause. Your own decisions are retold in your words.
   - Repository state as lines the next session can compare: `- git <absolute repo path> <ref> = <sha>`.
   - Write the note in the user's language; the markers above stay in English.
   - A task moved out of a shared resume note into its own: in the same save, replace its state and
     next step in the shared note with one line naming the new note, and rewrite the shared note's
     line in `MEMORY.md` so it no longer describes the task.
   - If `MEMORY.md` already has a line pointing to this note, keep that line accurate.
   - Then read the note back with the Read tool and check the lines you wrote.
4. **Handoff** — run exactly this command, with the note's absolute path and a short topic:

   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" save --note "<note path>" --topic "<task topic>"`

   It records a marker for this Claude process and checks the note. For a note in the memory folder
   it also rewrites `resume-index.md` and checks `MEMORY.md`: its `index` line and, after it, its
   `MEMORY.md` line go into the summary as printed. When it prints `MEMORY.md: add the index line`,
   read `MEMORY.md` with the Read tool — Edit refuses a file not read — then insert the line it gives
   at the very start of the file with the Edit tool: replace the start of the file, taken long enough
   to occur only once (the first line can be empty or repeat further down), with the index line, a
   newline and that same start. Read the first line back with Read and check it is the index line;
   if the line could not be inserted, say so in the summary. Never write `MEMORY.md` with Write, and
   never edit `resume-index.md`: the plugin alone writes it. Fix every line it lists as not verified
   and run
   it again, or leave them — the next session gets them marked "not verified". In a note own steps
   wrote, leave them: that note is not this skill's to fix. If it says the handoff
   is off, nothing was written. If it says `python3` is required, nothing ran: tell the user the
   handoff needs `python3` — on a Mac, the Xcode Command Line Tools (`xcode-select --install`) or
   another Python. If it fails otherwise — exit code 1: no Claude process found, the note cannot be
   read, the marker cannot be written — report its first line in the summary.
5. **Own steps after** — on the anchor command only, never when the user only asks whether the
   session is anchored. Run the command of step 0 again, also when it failed
   there, and carry out the steps it lists under `after anchor:`, in their order and the way step 0
   says, also when step 4 was skipped or failed. An after step that wrote to a repository makes step 1
   stale for it: run step 1's three commands for that repository again and put their result on its
   line of the summary.

## Summary — one block, nothing else

Written in the user's language; the labels below give the structure. The `own steps` line starts with
`not run` when the user only asked whether the session is anchored, with `none` when the command of
step 0 printed `no own steps`, and otherwise with the counts of steps carried out,
`before <n>, after <n>` — `before 0, after 0` when every file was skipped. Then, each after `; `,
come every failed step as `failed: <step> — <first line of its error>`, the command of step 0 as
`failed: own steps command — <its first line>` when it failed in both step 0 and step 5, and every
line it printed that starts with `skipped`, `dropped` or `project steps skipped`, as printed. One full
line, for example:

`own steps: before 1, after 0; failed: skill:daily-journal — Unknown skill: daily-journal; skipped /work/app/.claude/anchor-steps.json: not JSON: Expecting value: line 1 column 1 (char 0)`

The `index` and `MEMORY.md` lines are `not run` when step 4 was skipped or failed, and the `handoff`
line when step 4 was skipped; `MEMORY.md` is
`none` when `save` printed no `MEMORY.md` line, as for a note outside the memory folder. The
`resume note` line is `<path> (written by own steps)` for the note an own step wrote, and `none`
when no note was written or taken; when the command of step 0 failed, it ends with
`; owner unknown: own steps command failed — this task may now have two notes`.

```
Saved:
- <repo>: clean | uncommitted: <files> | unpushed: <n> (<why>) | no upstream: <n> not on <base> | detached HEAD
- background: none | <task> — <what it is for>, waits for <what>
- resume note: <path> (read back)[; not in memory: <first line of the refusal> | no memory folder][; owner unknown: …] | <path> (written by own steps) | none
- handoff: <marker path>, unverified lines: <n> | off | needs python3 | failed: <first line of its output> | not run
- index: updated | not updated: <reason> | none (<reason as printed>) | not run
- MEMORY.md: <as save printed it> | index line added first, checked | index line not added: <reason> | none | not run
- own steps: not run | none | before <n>, after <n>[; failed: <step> — <first line>]…[; <line of step 0>]…
Not saved: <what and why> | nothing
```

Every anchor command is a fresh call of this skill through the Skill tool, also the second one in a
session: the copy loaded at the first call may be older than this file. Once this skill has run, the
plugin adds a one-line reminder to every later prompt. Asked whether the session is anchored, run
the command of step 0 for its `note:` lines and steps 1–4 again instead of recalling that they ran;
the own steps themselves, before and after, are carried out on the anchor command only.
