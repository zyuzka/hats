---
name: anchor
description: Save this session's state for the next session — a resume note and a handoff marker — when the user's message is itself the anchor command, in any language («анкор», "anchor", «якорь») or typed as /hats:anchor, or when the user asks whether the session is anchored. Call it again on every later anchor command in the session. A message that only contains the word, such as "anchor the regex", is not the command, and other requests to save the session are not this skill's.
allowed-tools:
  - Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" *)
  - Write(~/Library/Application Support/Hats/notes/**)
  - Edit(~/Library/Application Support/Hats/notes/**)
  - Read(~/Library/Application Support/Hats/notes/**)
---

# Anchor

Saves where this session stands, so the next one can pick it up: after `/clear` the plugin's start
hook gives this session's note back, and a new session started in the same folder lists the notes of
closed sessions. Every step is a command, and its output goes into the summary.

## Steps

1. **Each repository this session touched** — the working folder, if it is a repository, and any
   other repository you wrote to. In the working folder run the plain commands, each as its own call
   and written exactly so — Claude Code asks for approval of an unquoted `@{u}..`:
   - `git status --short` — uncommitted files.
   - `git log --oneline '@{u}..'` — commits not pushed.
   - `git stash list` — a stash you made is named, never left silent.

   If `git log` says the branch has no upstream, report "no upstream" and the branch's commits not on
   its base branch (`git log --oneline <base>..`); on a detached HEAD, say so. For another repository run the same three as `git -C <its literal absolute path> …`, one
   repository per command. Commit or push only what this session's work already called for and the
   project's rules allow; name everything else in the summary.
2. **Background work** — list the background tasks, monitors and subagents still running, in this
   turn, not from memory. Do not stop them to save. For each one note its id or name, what it is for
   and what it waits for: background commands and subagents outlive `/clear`, and the next session is
   told when one ends but not what it was for. A monitor ends with the session — note what it watched.
3. **Resume note** — one note per task: two sessions in one folder work on different tasks and would
   overwrite one shared note.
   - Which file: if this task already has a note — the one the start hook gave this session (after
     `/clear`, or from its list when the user picked it), or one this session already wrote — update
     that note in place, whether it sits in the notes folder or in the memory folder Claude Code keeps
     for this working folder (`<config>/projects/<project>/memory/`, where `<config>` is
     `$CLAUDE_CONFIG_DIR` or else `~/.claude`). Otherwise run exactly this command; it creates the
     notes folder of this working folder and prints its path:

     `sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" where`

     and start a new note `<printed folder>/resume-<topic-slug>.md`. If that file already exists, it is
     another session's note: add `-2`, `-3` and so on to the name until it is free. Write only to a
     note this session started or got from the start hook.
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
   - Add no new line to a `MEMORY.md` index. If it already has a line pointing to this note, keep that
     line accurate.
   - Then `test -e` the file and read back the lines you wrote.
4. **Handoff** — run exactly this command, with the note's absolute path and a short topic:

   `sh "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" save --note "<note path>" --topic "<task topic>"`

   It records a marker for this Claude process and checks the note. Fix every line it lists and run
   it again, or leave them — the next session gets them marked "not verified". If it says the handoff
   is off, nothing was written. If it says `python3` is required, nothing ran: tell the user the
   handoff needs `python3` — on a Mac, the Xcode Command Line Tools (`xcode-select --install`) or
   another Python. If it fails otherwise — exit code 1: no Claude process found, the note cannot be
   read, the marker cannot be written — report its first line in the summary. For a note outside
   both folders, move the note into the folder `where` printed and run the command again.

## Summary — one block, nothing else

Written in the user's language; the labels below give the structure.

```
Saved:
- <repo>: clean | uncommitted: <files> | unpushed: <n> (<why>) | no upstream: <n> not on <base> | detached HEAD
- background: none | <task> — <what it is for>, waits for <what>
- resume note: <path> (read back)
- handoff: <marker path>, unverified lines: <n> | off | needs python3 | failed: <first line of its output>
Not saved: <what and why> | nothing
```

Every anchor command is a fresh call of this skill through the Skill tool, also the second one in a
session: the copy loaded at the first call may be older than this file. Once this skill has run, the
plugin adds a one-line reminder to every later prompt. Asked whether the session is anchored, run the
steps again instead of recalling that they ran.
