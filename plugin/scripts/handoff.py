#!/usr/bin/env python3
"""Hand a session's resume note to the next session: a save request leaves a marker for this
Claude process, and the SessionStart hook gives the note back after /clear, or lists the notes
of closed sessions when a new session starts in the same folder.

  handoff.py start                      SessionStart hook (matcher startup|clear), stdin = hook input
  handoff.py took                       PostToolUse hook (matcher Read): who else reads this note
  handoff.py save --note P --topic T    after a save request: marker + check of the note + resume index
  handoff.py check P                    the check alone
  handoff.py new --slug S [--memory D]  creates an empty note resume-S.md under a free name, prints its path
  handoff.py where                      creates and prints the notes folder of the working folder

The marker is keyed to the Claude process (pid + start time read in UTC), not to the folder:
two sessions run in one folder at once (measured 2026-11-09), and /clear keeps the process (a
session after /clear ran in the process started the day before, measured 2026-11-09). After /clear
the process alone finds the note, whatever folder the session moved to; a new session lists the
notes of closed processes launched in its folder. The hook never deletes a marker: SessionStart
can fire twice or for a session that never opens; `save` retires markers of closed processes
that point at the same note. After /clear a save is handed to one session: the hook records the
receiving session id beside the marker (`<marker>.handed`, keyed to the save's time and note,
so the marker itself is never rewritten under a concurrent `save`), gives the note again to that
same session and stays silent for a later session of the process until the next `save`. An input
without a usable session id gets the note and records nothing. A process whose state `ps`
cannot tell in time is treated as alive: its note is neither listed nor retired. Every external
call in the hook shares one time budget, under the hook's 5-second timeout.

The note must sit in one of two folders: the notes folder, or Claude Code's memory. The hook prints
the note's head into the model's context, and any other path would let a marker print an arbitrary
file. `save` and the start hook check it with one function, `allowed_note`, against the working
folder of the save (`save` its own, the hook the marker's).

Memory comes first (user, 2026-11-12: the line in MEMORY.md is backward compatibility — the plugin
may be removed, Claude Code's memory comes with Claude Code). A new note goes into Claude Code's
memory folder of the project, `resume-index.md` beside it lists the saved sessions, and one line of
MEMORY.md points to that index, so a session finds the note even without the plugin. With memory
switched off, or a memory folder `new` refuses, the note goes into the notes folder, without an index
(the user's choice of 2026-11-12). Measured on Claude Code 2.1.322, 2026-11-12:
  1. With memory off (CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 or autoMemoryEnabled false) a session is
     given neither MEMORY.md nor the path of the memory folder.
  2. With the plugin disabled, a session asked to continue read MEMORY.md's line, the index and the
     note, 2 runs of 2.
  3. Claude Code loads the first 200 lines of MEMORY.md, then cuts at the last newline before 25,000
     characters, counted as JavaScript counts a string's length (UTF-16 units). So the index line
     goes first, and it is looked for only in that loaded part.
  4. The memory folder is <config>/projects/<name>/memory unless a setting moves it, and a worktree
     shares the one of its main repository. So `new` takes the folder from the session, whose
     instructions name it, and never computes it.
  5. Write overwrites an existing file of the memory folder that the session never read, with no
     refusal. So a name the session picks itself protects nothing; `new` creates the file only if the
     name is free.
`new --slug S [--memory D]`: S is [a-z0-9]+(-[a-z0-9]+)*, up to 60 characters, not "index". D must
resolve to exactly <real <config>/projects>/<name>/memory, a folder that exists (Claude Code creates
it when a session starts, measured 2026-11-12); without D the note goes into the notes folder that
`where` prints. The name is resume-S.md, then resume-S-2.md up to -99 while the name is taken, and
the file is created with O_CREAT|O_EXCL|O_NOFOLLOW, mode 600. The path is joined without normpath
and printed through D as the session gave it, so it matches the memory folder in its instructions;
the created path must pass `allowed_note` as the very file created (its answer equals the real path),
else the file is removed and refused. `where` stays: a copy of the skill loaded before an update
still calls it.

The index: `save` rewrites `resume-index.md` only for a note whose real path sits directly in a
memory folder under <config>/projects, and in that same folder. A header line marks it as the
plugin's, a paragraph tells the session to ask the user before continuing a listed task (its session
may still be at work), and one line per note follows, newest first, at most 20:
`- [<topic>](<<file>>) — saved <time>, folder <working folder>`. The topic, cut to 120 characters for
the marker already, loses [ ] ( ) < > `, control characters and runs of spaces; the working folder
loses control characters. A note whose name holds <, >, / or a
control character is not indexed. An old line stays only when it parses, its file is a plain .md
name, not a service file, not this note, a regular file of that folder, and saved within 30 days. The
rewrite, from reading the index to os.replace of a temporary file in the same folder, runs under flock
on <config>/state/handoff/index-<16 hex digits of the sha256 of the folder's real path>.lock, waited
for up to 10 seconds: one lock per memory folder, so projects never wait for each other. An existing
index is touched only when it is a regular file, not a link, up to 64 KB, UTF-8, with the plugin's
header; otherwise, and when the lock stays busy, `save` prints `index not updated: <reason>`. Then,
under the same lock, MEMORY.md: absent — created with the index line (O_EXCL|O_NOFOLLOW); empty — the
line appended; a link or not a regular file — not checked; otherwise read (O_NOFOLLOW|O_NONBLOCK, up
to 100 KB, UTF-8) and searched, in the part Claude Code loads, for a line that starts with "- [" and
links to resume-index.md. Without one, `save` asks the session to put the line first with Edit: the
script never changes a MEMORY.md that has content. A marker written means exit 0, whatever happens
to the index and MEMORY.md. `allowed_note` refuses a note named resume-index.md or MEMORY.md, in any
letter case. With HANDOFF_TEST=1, HANDOFF_TEST_PAUSE also widens the window between choosing a name
in `new` and creating the file and the one between reading the index and replacing it, and
HANDOFF_TEST_INDEX_WAIT=<s> shortens the wait for the lock.

Known gaps of the index: memory of any project under <config>/projects is accepted, as before, and
`save` now writes resume-index.md there and may create its MEMORY.md; a memory folder that is a link
gets no index (`save` says so: "index: none (the memory folder is a link)"), a quote of it is not
caught (below), and `new` refuses such a folder, so a new note goes into the notes folder; two config
folders that share one memory take different locks; two sessions that continue one note both edit
it — races are closed only for new files and the index; a failure between `new` and `save` leaves an
empty note, and the next `new` takes -2.

The notes folder is the plugin's own (user, 2026-11-11 and 2026-11-12): ~/Library/Application
Support/Hats/notes/<project>/<name>.md, where <project> is the first 16 hex digits of the sha256 of
the real path of the working folder, so /a/b-c and /a-b/c get different folders. It works with
Claude Code's memory switched off, survives the plugin's removal, and needs no running Hats. `where`
creates it with mode 700 (a folder that exists is left as it is) and prints it; `where` and `save`
take the working folder from one function. The root is computed here, the same for `save` and
`start`, and never taken from the command line or a variable of the plugin's own: the agent writes
the command. Like any `~`, it follows HOME (the tests rely on that), and a `save` run under another
HOME is checked again by the start hook under its own. A note there is accepted only when its real
path is exactly
<real root>/<project of the working folder>/<name>.md and a regular file, and that real path is
what is read: a subfolder, `..`, a link out, or the folder of another project is refused. Letter
case is compared as written: a path typed in another case than `where` printed is refused by
`save`, loudly.

The memory note is <config>/projects/<folder>/memory/<name>.md, where <config> is
$CLAUDE_CONFIG_DIR when it is an absolute path or else ~/.claude; old markers and notes written there are still accepted. The
memory folder (or the project folder above it) may be a link to somewhere else; then the note must
sit directly in the folder the link points at, `..` is resolved before the check, a note that is
itself a link out of that folder is refused, and the path read is the one the check returned. Known
gap: a quote of a file in such a linked memory folder is not recognised as a quote of memory.

What the check guards against is a marker whose path points outside both folders. It does not guard
against a process of the same user that writes into them: swapping the note for a link between the
check and the read, a hard link to a file elsewhere (verification 2026-11-11, both already true
before the linked-folder change), or a root swapped for a link gets past it. Such a process can read
any file of the user itself, so the hook adds nothing it lacks. Nor does it stop the anchor skill:
its Write and Edit rules let the agent, while an anchor runs, write into the notes of any project,
and the start hook then prints such a note into that project's session. A quote counts as a quote
of the notes folder when one of the folders above the cited file is the notes root itself (the same
file system object), so another letter case or another path to the same disk does not make it a
source.

Environment (measured 2026-11-11): Claude Code gives hooks and Bash commands CLAUDE_PID, the pid of
its own process, so the Claude process is that ancestor whatever its binary is called; without it,
the nearest ancestor named `claude`. The process folder is read from /proc/<pid>/cwd where /proc
exists (Linux), else from lsof. Without fcntl (Windows) the run log is written without its lock. Repository
state is compared with local refs only — no fetch: a fetch runs commands from the named
repository's config and needs the network, and a failed fetch made an old origin ref read as
current (verification 2026-11-11). A fact about a remote-tracking ref (origin/ or any other remote)
says so. GIT_* variables of the environment do not reach these git calls, so GIT_DIR cannot point
the check at another repository.

The check: a number taken from another file goes into the note only inside a quote
`(cite: <path>:<line> "exact text")`, with «», "" or “” as the quote marks, compared with that
line of a regular file at number boundaries; a quote of the note itself, of Claude's memory or of
any file in the notes folder is not a source; the note and the memory folder are matched as file
system objects, so another letter case does not make them a source. `N of M (P%)` is recomputed on every line. A figure read off a command carries
`(cmd: <command>)` in the same clause. A percent, "N percent", `N of M` or `N/M` outside all
three — inline code included, fenced code (``` or ~~~, three marks or more, closed by the same
mark at least as long) not — is reported as not verified; a code block left open is reported, since
the lines after it are not checked; a `(cite:` that does
not parse is reported too, unless it sits in inline code. Numbers written in words are not
caught, and the check cannot tell whether the words next to a quote mean what the quote says.

Language: the tool is used in more languages than Russian (user, 2026-11-11). The markers above
and the `## NOW` heading are English, and everything the hook prints is English — the session
answers in the user's language anyway. The Russian forms the notes were written in first —
`(цит. …)`, `(система: …)`, `N из M`, «процент», `## СЕЙЧАС` — are still read, so older notes
keep checking. Codex agreed with this set on 2026-11-11 and asked for paired quote marks only and
for `## NOW` to be a whole heading (a qualifier after a dash, colon or bracket, or a date, is fine).
`## СЕЙЧАС` keeps its old, looser match (`## СЕЙЧАС-2 …`, `## СЕЙЧАС 2026-…`): a verifier found the
stricter rule made an older hats note hand over its 09.11 section instead of its 11.11 one, and on
all 771 memory notes the printed section is now the same as before. `cite` and `cmd` are read in any
case, and a `(cmd: …)` span is kept whole when a clause is split, so " and " inside a command does
not cut it.

What `start` prints is one JSON object or nothing (user, 2026-11-13: after a start or /clear the hook
says that it ran and which anchor it took). `systemMessage` is a line for the user: Claude Code shows it
under its logo as `SessionStart:startup says: …` (`SessionStart:clear says: …` after /clear) and never
gives it to the model. `hookSpecificOutput` carries `hookEventName` SessionStart and `additionalContext`,
the model's text — character for character what the hook printed before, without the last newline
(measured on Claude Code 2.1.323 in tmux). A run that gives the model a note or a list prints both. A
run with nothing for the model prints `systemMessage` alone: no anchor saved in this Claude process, an
anchor already given to another session, no Claude process found, no notes of closed sessions, notes
that could not be checked in time, and an error raised before anything was printed. A note that could
not be checked is one of this folder, saved within 30 days, whose process `ps` could not tell in time
or that the loop never reached because the budget ran out: it is counted, never reported as absent;
once the budget is out, a marker's folder is compared with the session's as written, without resolving
links, as the loop did not resolve them before it stopped there. Off, a start without a person,
another event, a bad input and a bad folder print nothing; after /clear without a person the model's
text goes out with no line for the user. The line is English and starts with "Hats handoff:"; the
topic, the note path and the session id lose control characters, line and paragraph separators, unpaired
surrogates and the bidirectional embedding and isolate controls (U+202A–U+202E, U+2066–U+2069) — a
set of its own, so zero-width joiners of Persian, Devanagari and emoji stay; the topic is cut to 120
characters, a session id shows only when it is a whole id (else "another session"), and the line stays
within 2,000 UTF-16 units. The first line of a list counts every closed note found; notes beyond the
five listed and notes that do not fit are counted together as "and N more", a note never cut in the
middle. An error line points to `runs.log`, which holds the error's type and text. The object is
written as UTF-8 bytes, so Cyrillic is not escaped into six-character sequences and the output does
not depend on the encoding of stdout. After /clear it is written and flushed before the hand-over is
recorded, as before.

Every `start` run appends one JSON line to `runs.log` beside the markers: time, how long it took,
source, session, folder, Claude process and the decision — `off`, `bad-input`, `skipped`,
`unattended`, `no-process`, `no-own-marker`, `handed-elsewhere`, `gave-note` (receiver `new`, `same`
or `none`), `not-printed` (the note could not be written to stdout under the mark lock, task 8c),
`no-closed`, `unchecked`, `listed`, `error` (with `error`, the exception's type, and
`message`, its text); a start in a new session also records `unchecked`, the number of notes it could
not check. A run that prints nothing leaves nothing in the transcript
(measured 2026-11-11: 11 Bash calls with five hooks each, and only the one run that printed was
recorded), so this line is the only proof that the hook ran and why it stayed silent. It is
written on the way out, whatever the exit; a run killed by the timeout writes nothing, and a log
that cannot be written never costs the note. Over 256 KB the log moves to `runs.log.1`.
Concurrent runs (measured 2026-11-11, 20 rounds of 30 parallel runs, before the lock): appends
never broke a line, but rotation lost lines in 1 round and the previous history in 5 — two runs
both saw a big log and both moved it. So the size check, the move and the append run under
`flock` on `runs.lock`; a run that cannot take it within half a second appends without moving,
so a line is never dropped for the lock. `save` writes its marker through a temporary file named
by its own pid: with one shared name, parallel saves failed with FileNotFoundError in 14 rounds
of 20. With HANDOFF_TEST=1, HANDOFF_TEST_PAUSE=<s> widens both windows so the tests can hit them.

`save` writes a marker only where the start hook is registered: in the folder's
.claude/settings.local.json or .claude/settings.json, in <config>/settings.json, or, when this script
sits in a plugin (`.claude-plugin/plugin.json` two folders above it), in the plugin's
hooks/hooks.json. A copy outside a plugin never reads a hooks.json.

Who reads a note (task 8c, user decisions of 2026-11-13). Two new sessions of one folder see one list
of closed notes and may take the same one: the start hook knows whether the process that saved a note
lives, not who continues it. So `took`, a PostToolUse hook on Read, records the reading Claude process
in a mark file and, on its first read only, warns once when other sessions read the note; the start
list marks such notes, and /clear takes the process off. To take a note is to read its file with Read
(user, "1) а"): a read made only to describe the note counts too, and cat is not caught. Measured on
Claude Code 2.1.323 in tmux: the input of a PostToolUse hook on Read carries cwd, duration_ms, effort,
hook_event_name, permission_mode, prompt_id, scratchpad_dir, session_id, tool_input ({"file_path"}),
tool_name, tool_response ({"file", "type"}), tool_use_id and transcript_path; `systemMessage` shows
under the call as `PostToolUse:Read says: …` and never reaches the model, `additionalContext` does;
starting the hook (py.sh, python3 -I, importing this file) takes a median of 58 ms over 15 runs.

The note of `took` is the file in the `note` field of any marker that passes `allowed_note` with that
marker's cwd and is the same file as the path read (os.path.samestat); a partial or an empty read
counts, and markers are not filtered by folder, age or whether their process closed (user, "4) да").
Before any marker is read, a path that is not .md, has a service name (MEMORY.md, resume-index.md, in
any case), or sits neither directly in a memory folder under <config>/projects (seen as typed, so a
memory folder that is a link counts) nor in a project folder of the notes root is not a note. Markers
are read in name order, as load_markers reads them, each through get_small_text (64 KB, O_NONBLOCK: a
FIFO never hangs), the deadline checked between files; markers still unread at the deadline make the
outcome `incomplete`. The note's group is every such marker whose note is that same file; a mark file
is <markers>/taken/<sha256 of the real path of the marker's note>.json, one per distinct real path, so
a memory folder behind a link, another letter case and a hard link all reach the group.

A mark file is {"note": <real path>, "readers": [{"pid", "started", "session", "at"}]} (user, "2) в"):
a reader is a Claude process (pid and start time, as in markers), the session id of its first read
(a whole id, else null) and the time of that read; another read by the same process changes nothing.
A reader goes into every file of the group, and the facts are the union of readers by (pid, started)
with the earliest at. The process's own list, taken/<pid>-<started>.reads ({"pid", "started", "keys"}),
names the files it reads: written under the same lock before the mark files, at most 500 keys and
64 KB, so /clear finds its own records without walking taken/. A reader is removed only when seen dead
— os.kill finds no such process, or ps shows another start time — and its .reads goes with it; ps
saying "no" (code 1, empty output, which a failing ps also prints) while os.kill finds a process makes
that reader "could not check", never dead and never live. There is no age limit (user, "4) да"): a
file with no readers left is removed, and `save` never writes into taken/. Mark files and .reads are
read through get_small_text, at most 64 KB and 100 readers, else unreadable and never rewritten; a bad
reader (pid not a positive int, started empty, at not a marker timestamp) is dropped, and a bad file
(not JSON, another shape, another note) counts as empty.

`took` runs in this order: a deadline of 1.5 s from entry, the filter by name and place, the markers,
the group, the own process, a snapshot of the group's files without the lock, the other readers checked
outside the lock (os.kill, then ps, once per pid, until 0.3 s before the deadline), flock on
taken/.lock (waited for until 0.1 s before the deadline), the files read again and merged (those seen
dead dropped, those that appeared kept; a reader written after this run's snapshot counts as live),
temporary files, the print, os.replace (.reads first), runs.log. The print under the lock is a
non-blocking write to stdout of at most 0.3 s and never past the deadline; a write not finished is
`not-printed`, its temporary files are removed and a fragment may have gone out. A reader owed a warning
is recorded only if the warning printed, and nothing checks the deadline between the print and the
replace. taken/.lock is a file of its own, never replaced or removed, and ps never runs under it; only
a run that records a reader (`took`, and /clear with `gave-note`) creates taken/ (700) and .lock (600),
opened with O_NOFOLLOW|O_NONBLOCK and checked by fstat. Capacity is 100 readers per file once the dead
are dropped: a reader already there stays (`again`); a new one at 100 is not recorded (`full`), and the
warning prints by the facts of the file. The same reason=full also stops a reader whose own .reads would
then pass 500 keys or 64 KB: it is not recorded either.

The matrix of `took`; runs.log gets a line only on the paths that name an outcome, and the others write
nothing, create no state folder and never wait for runs.lock:
  not a note — not .md, a service name, outside both folders, no marker on the file: silent
  quiet — HANDOFF_OFF=1, a subagent (agent_id on the input), a session without a person: silent
  bad input — not a JSON object, hook_event_name not PostToolUse, tool_name not Read, tool_input.file_path
    not an absolute path: silent, `bad-input`
  markers not read by the deadline: silent, `incomplete`
  first reader — no other reader, or all of them dead: recorded, the dead removed, `took`
  already a reader: only the dead removed, `again`
  others — live and/or not checked: the user gets "Hats handoff: <facts>", the model "[handoff] <facts>.
    Another session may be continuing this task: continue it only if the user confirms."; recorded after
    the print, `took-shared` with `live` and `unknown`
  full — 100 readers after the dead, this process not among them: warned, nothing written, `not-recorded`
    reason=full
  not recorded — the lock not taken in time or not opened, no fcntl, taken a link or not a folder, a
    temporary file not created, os.replace failed after the print: warned by the last state read when
    others read the note, nothing written, the next read warns again; `not-recorded` with `reason`, `warned`
  unreadable — a mark file or the own .reads a link, not a regular file, over 64 KB or 100 entries, a read
    error: silent, untouched, `not-recorded` reason=unreadable
  no Claude process: silent, `no-process`; stdout not taking the output: `not-printed`; an exception:
    `error` with its type and text
<facts> is "<N> other live session(s) reading this note: <list>" or "could not check <M> other
session(s) that read this note: <list>", both joined as "…; could not check <M> more: <list>"; <list>
is "session <id> (pid <pid>, since <at>)" joined by ", ", <id> only a whole session id, else "a
session", cut with "and <K> more" to 2,000 UTF-16 units for the user and 9,500 for the model. The output
is one JSON object with hookEventName PostToolUse, or nothing, written as UTF-8 bytes; the exit code is
0 and stderr empty. A runs.log line of `took` carries "command": "took", session, pid, note, outcome,
live, unknown, reason and warned.

The start list marks a listed note that live or unchecked sessions read, after the text of before is
built, in the time left until 0.2 s before the deadline and in a try of its own. The model gets, after
the note's line, "   <facts>. If the user picks it, say so and continue only if the user confirms.",
only while the whole text stays within 9,500 units (else `marks_dropped`); the user gets "   <facts>"
under the note's entry, the readers of one note cut to 600 characters with "and <K> more", and notes
dropped for the 2,000 limit end as "and <N> more, <K> of them being read by another session". Here
<facts> reads "<N> live session(s) reading it: …", "could not check <M> session(s) that read it: …",
and for an unreadable file "could not check whether another session is reading it". No mark file, all
readers dead or a broken file leave the text of before character for character; an exception in the
marks drops them (`listed`, marks_error=<type>). `startup` reads without the lock and never creates or
writes taken/.

/clear with a person and an identified process first takes the process off, on all three paths: by its
own .reads, out of the files of its keys, except the keys of the group of the note this /clear gives
it; an empty file is removed, .reads is rewritten or removed, and a key leaves .reads only once its
file was rewritten. The lock is waited for 0.5 s; no taken/ — nothing; a failure — clear_error. When
/clear gives the process its note (`gave-note`; user decision "8c-1 а": the session counts as reading
it at once, without a Read), the group, the snapshot, the readers' check and render_own run until 0.3 s
before the deadline; then the lock, the merge, the temporary files, one JSON with the facts in both
fields printed as `took` prints, os.replace, and only then record_handed. Not printed (`not-printed`):
neither reader nor hand-over; the lock not taken: printed by the snapshot, no reader. When others read
the note, the model's text starts with "[handoff] <facts>. Another session may be continuing this task:
continue it only if the user confirms." and the whole is cut to 9,500 units from the end, so the tail
of render_own suffers, not the mark; the user line gets "   <facts>" under "continuing anchor …". A
runs.log line of start adds marks, marks_dropped, marks_error, cleared and clear_error, and after
`gave-note` reader (with reason). A subagent and a session without a person record nothing and get no
line of 8c: after /clear without a person the text is that of before.

Known gaps of the marks: a file whose readers all left without /clear stays until a `took` of the same
note; the .reads of such a process stays until a `took` sees it dead; the .tmp of a killed run stays;
a process that read a note and dropped it without /clear stays a reader until it exits; a memory note
behind a link, read by its real path outside <config>/projects, is not caught; cat is not caught.

HANDOFF_OFF=1 silences the hook. With HANDOFF_TEST=1, HANDOFF_PROCESS=<pid>:<start> stands in
for the claude process and HANDOFF_TEST_BUDGET for the time budget (of `took` too). HANDOFF_TEST_PAUSE
also pauses under taken/.lock before the replace, HANDOFF_TEST_TAKEN_SIGNAL=<folder> gets <pid>.waiting
before the wait for that lock and <pid>.locked once it is held, and HANDOFF_TEST_FAIL=replace makes
os.replace of the mark files fail.
"""
import argparse
import hashlib
import json
import os
import re
import select
import signal
import stat
import subprocess
import sys
import time
import unicodedata
from datetime import datetime, timedelta, timezone

try:
    import fcntl
except ImportError:
    fcntl = None

HEAD_LIMIT = 6500
OUTPUT_LIMIT = 9500
LIST_LIMIT = 5
MAX_AGE = timedelta(days=30)
PROBLEM_LIMIT = 10
STATE_FACT_LIMIT = 4
TIME_BUDGET_S = 3.5
CALL_TIMEOUT_S = 2.0
SOURCE_SIZE_LIMIT = 2_000_000
LINE_LENGTH_LIMIT = 5000
TOPIC_LIMIT = 120
USER_LINE_LIMIT = 2000
USER_LINE_START = "Hats handoff:"
ANCESTOR_LIMIT = 8
TRACE_LIMIT = 256_000
TRACE_FIELD_LIMIT = 500
TRACE_LOCK_S = 0.5
NOTES_ROOT = "~/Library/Application Support/Hats/notes"
PROJECT_FOLDER_LENGTH = 16
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
SLUG_LIMIT = 60
NAME_TRIES = 99
INDEX_NAME = "resume-index.md"
MEMORY_NAME = "MEMORY.md"
SERVICE_NAMES = {
    "resume-index.md",
    "memory.md",
}
INDEX_HEADER = "# Resume index — written by the Hats plugin; do not edit"
INDEX_ABOUT = (
    "One line per saved session, newest first. A session may still be working on a task listed here: "
    "ask the user before continuing one."
)
INDEX_LINE = re.compile(
    r"- \[(?P<topic>[^\[\]()<>`]*)\]\(<(?P<name>[^<>/\n]+)>\) — saved "
    r"(?P<saved>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ), folder (?P<folder>.*)"
)
INDEX_TOPIC_DROP = "[]()<>`"
INDEX_ENTRY_LIMIT = 20
INDEX_SIZE_LIMIT = 64 * 1024
INDEX_LOCK_S = 10.0
MEMORY_LINE = (
    "- [Resume index](resume-index.md) — sessions saved for the next one; "
    "read it when the user asks to continue earlier work"
)
MEMORY_SIZE_LIMIT = 100 * 1024
MEMORY_LOADED_LINES = 200
MEMORY_LOADED_UNITS = 25_000
MEMORY_SKIPPED = "MEMORY.md: not checked: index not updated"
CONTROL = {
    "Cc",
    "Cf",
    "Cs",
    "Zl",
    "Zp",
}
USER_LINE_CONTROL = {
    "Cc",
    "Cs",
    "Zl",
    "Zp",
}

CITE = re.compile(
    r"\((?:(?i:cite):|цит\.)\s+(?P<path>[^«»“”\"()\n]{1,300}?):(?P<line>\d{1,7})\s+"
    r"(?:«(?P<t1>[^»\n]{1,500})»|“(?P<t2>[^”\n]{1,500})”|\"(?P<t3>[^\n]{1,500}?)\")\)"
)
CITE_START = re.compile(r"\((?:(?i:cite):|цит\.)")
INLINE_CODE = re.compile(r"`[^`\n]*`")
SYSTEM_SOURCE = re.compile(r"\((?:(?i:cmd)|система):\s*[^)\n]{1,300}\)")
RATIO_PERCENT = re.compile(r"(?<!\d)(?P<n>\d+)\s+(?:of|из)\s+(?P<m>\d+)\D{0,6}?(?P<p>\d+(?:[.,]\d+)?)\s?%")
NUMBER_CLAIM = re.compile(
    r"(?<!\d)\d+(?:[.,]\d+)?\s?(?:%|percent|процент)|(?<!\d)\d+\s+(?:of|из)\s+\d+|(?<![\w/.])\d+\s?/\s?\d+(?![\w/])",
    re.IGNORECASE,
)
CLAUSE_BREAK = re.compile(r";|\||\s—\s|\.\s|,\s|\sи\s|\sand\s")
FENCE = re.compile(r"^\s*(?P<fence>`{3,}(?=[^`]*$)|~{3,})(?P<info>.*)$")
GIT_FACT = re.compile(
    r"^\s*-\s+git\s+(?P<repo>\S+)\s+(?P<ref>[A-Za-z0-9_][A-Za-z0-9._/-]*)\s+=\s+(?P<sha>[0-9a-f]{7,40})\b"
)
NOW_HEADING = re.compile(r"^##\s+(?:СЕЙЧАС\b|(?i:NOW)\s*(?:$|[—–:(,]|-\s|\d))")
MARKER_FIELDS = {"pid": int, "started": str, "cwd": str, "note": str, "topic": str, "saved_at": str}
SESSION_ID = re.compile(r"[0-9A-Za-z_-]{1,128}")
TOOK_BUDGET_S = 1.5
CHECK_SPARE_S = 0.3
LOCK_SPARE_S = 0.1
PRINT_LIMIT_S = 0.3
MARKS_SPARE_S = 0.2
UNLIST_LOCK_S = 0.5
LOCK_STEP_S = 0.01
TAKEN_FOLDER = "taken"
TAKEN_LOCK = ".lock"
TAKEN_LIMIT = 64 * 1024
MARKER_LIMIT = 64 * 1024
READER_LIMIT = 100
READS_KEY_LIMIT = 500
MARK_LIST_LIMIT = 600
NOTE_KEY = re.compile(r"[0-9a-f]{64}")
STAMP = "%Y-%m-%dT%H:%M:%SZ"
TOOK_ASK = "Another session may be continuing this task: continue it only if the user confirms."
LIST_ASK = "If the user picks it, say so and continue only if the user confirms."
TOOK_WORDS = (
    "{} other live session(s) reading this note: ",
    "could not check {} other session(s) that read this note: ",
)
MARK_WORDS = (
    "{} live session(s) reading it: ",
    "could not check {} session(s) that read it: ",
)
MORE_WORDS = "; could not check {} more: "
UNREADABLE_MARK = "could not check whether another session is reading it"
MARK_INDENT = "   "

_deadline = None
_check_errors = []
_tell = False
_printed = False


def time_left(default):
    if _deadline is None:
        return default
    return max(0.0, min(default, _deadline - time.monotonic()))


def out_of_time():
    return _deadline is not None and time.monotonic() >= _deadline


def config_root():
    custom = os.environ.get("CLAUDE_CONFIG_DIR")
    if usable(custom) and os.path.isabs(os.path.expanduser(custom)):
        return os.path.expanduser(custom)
    return os.path.join(os.path.expanduser("~"), ".claude")


def state_dir():
    return os.path.join(config_root(), "state", "handoff")


def memory_root():
    return os.path.realpath(os.path.join(config_root(), "projects"))


def get_notes_root():
    return os.path.expanduser(NOTES_ROOT)


def get_project_folder(cwd):
    try:
        real = os.fsencode(os.path.realpath(cwd))
    except ValueError:
        return None

    return hashlib.sha256(real).hexdigest()[:PROJECT_FOLDER_LENGTH]


def usable(path):
    return isinstance(path, str) and path != "" and "\x00" not in path


def run(cmd, timeout):
    if timeout <= 0:
        return None, None
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(LC_ALL="C", TZ="UTC")
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True, env=env, start_new_session=True)
    except OSError:
        return None, None
    try:
        out, _ = proc.communicate(timeout=max(0.05, timeout))
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        return None, None
    return proc.returncode, out


def process_start(pid, until=None):
    timeout = time_left(CALL_TIMEOUT_S)
    if until is not None:
        timeout = min(timeout, until - time.monotonic())
    code, out = run(["ps", "-o", "lstart=", "-p", str(pid)], timeout)
    if code is None:
        return "unknown", None
    started = " ".join((out or "").split())
    if code == 0 and started:
        return "ok", started
    if code == 1 and not started:
        return "absent", None
    return "unknown", None


def testing():
    return os.environ.get("HANDOFF_TEST") == "1"


def claude_process():
    override = os.environ.get("HANDOFF_PROCESS")
    if override and testing():
        pid, _, started = override.partition(":")
        return int(pid), " ".join(started.split())
    hinted = os.environ.get("CLAUDE_PID", "")
    hint = int(hinted) if hinted.isascii() and hinted.isdigit() and len(hinted) <= 10 else None
    pid = os.getppid()
    for _ in range(ANCESTOR_LIMIT):
        if pid <= 1:
            return None
        if pid == hint:
            status, started = process_start(pid)
            return (pid, started) if status == "ok" else None
        code, out = run(["ps", "-o", "ppid=,comm=", "-p", str(pid)], time_left(CALL_TIMEOUT_S))
        parts = (out or "").strip().split(None, 1)
        if code != 0 or len(parts) < 2:
            return None
        if os.path.basename(parts[1].strip()) == "claude":
            status, started = process_start(pid)
            return (pid, started) if status == "ok" else None
        pid = int(parts[0])
    return None


def find_work_folder(given, proc):
    if given:
        return os.path.realpath(os.path.expanduser(given))
    found = process_cwd(proc[0]) if proc else None

    return os.path.realpath(found or os.getcwd())


def process_cwd(pid):
    proc = os.environ.get("HANDOFF_TEST_PROC", "/proc") if testing() else "/proc"
    try:
        target = os.readlink(os.path.join(proc, str(pid), "cwd"))
        if target:
            return target
    except OSError:
        pass
    code, out = run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], CALL_TIMEOUT_S)
    for line in (out or "").splitlines() if code == 0 else ():
        if line.startswith("n"):
            return line[1:]
    return None


def liveness(marker):
    status, started = process_start(marker["pid"])
    if status == "unknown":
        return "unknown"
    if status == "ok" and started == marker["started"]:
        return "alive"
    return "closed"


def same_path(a, b):
    return os.path.realpath(a) == os.path.realpath(b)


def in_memory(real):
    root = memory_root() + os.sep
    if real.startswith(root):
        parts = real[len(root):].split(os.sep)
        if len(parts) == 3 and parts[1] == "memory":
            return True
    folder = os.path.dirname(real)
    project = os.path.dirname(folder)
    try:
        projects = os.stat(memory_root())
        memory = os.stat(os.path.join(project, "memory"))
    except (OSError, ValueError):
        return False
    return is_same_folder(os.path.dirname(project), projects) and is_same_folder(folder, memory)


def note_in_memory(path):
    lexical = os.path.normpath(os.path.abspath(os.path.expanduser(path)))
    real = os.path.realpath(lexical)
    if in_memory(real):
        return real
    folder = os.path.dirname(lexical)
    if os.path.basename(folder) != "memory":
        return None
    if os.path.realpath(os.path.dirname(os.path.dirname(folder))) != memory_root():
        return None
    if os.path.dirname(real) != os.path.realpath(folder):
        return None
    return lexical


def is_own_note(real, folder):
    return (
        os.path.dirname(real) == os.path.join(os.path.realpath(get_notes_root()), folder)
        and real.endswith(".md")
        and os.path.isfile(real)
    )


def find_own_note(path, cwd):
    folder = get_project_folder(cwd)
    if folder is None:
        return None
    real = os.path.realpath(os.path.expanduser(path))

    return real if is_own_note(real, folder) else None


def is_service_name(path):
    return os.path.basename(path).lower() in SERVICE_NAMES


def allowed_note(path, cwd):
    if not usable(path) or is_service_name(path):
        return None
    kept = find_allowed_note(path, cwd)
    if kept is None or is_service_name(os.path.realpath(kept)):
        return None

    return kept


def find_allowed_note(path, cwd):
    kept = note_in_memory(path)
    if kept is None:
        return find_own_note(path, cwd)
    real = os.path.realpath(kept)
    return kept if kept.endswith(".md") and real.endswith(".md") and os.path.isfile(real) else None


def is_memory_folder(folder):
    real = os.path.realpath(folder)

    return (
        os.path.isabs(folder)
        and os.path.basename(real) == "memory"
        and os.path.dirname(os.path.dirname(real)) == memory_root()
        and os.path.isdir(real)
    )


def checked_markers():
    out = []
    for marker in load_markers():
        kept = allowed_note(marker["note"], marker["cwd"])
        if kept is not None:
            marker["note"] = kept
            out.append(marker)
    return out


def marker_file(pid, started):
    return f"{pid}-{re.sub(r'[^0-9A-Za-z]+', '-', started).strip('-')}.json"


def is_marker_shape(marker):
    return (
        isinstance(marker, dict)
        and all(isinstance(marker.get(k), t) and not isinstance(marker.get(k), bool) for k, t in MARKER_FIELDS.items())
        and all(usable(marker[k]) for k in ("started", "cwd", "note"))
    )


def load_markers():
    folder = state_dir()
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    markers = []
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(folder, name)
        try:
            with open(path, encoding="utf-8") as f:
                marker = json.load(f)
        except (OSError, ValueError, RecursionError):
            continue
        if not is_marker_shape(marker):
            continue
        marker["_path"] = path
        markers.append(marker)
    return markers


def handed_file(marker):
    return marker["_path"][:-len(".json")] + ".handed"


def handed_key(marker):
    return f"{marker['saved_at']}|{marker['note']}"


def handed_session(marker):
    try:
        with open(handed_file(marker), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("key") != handed_key(marker):
        return None
    session = data.get("session")
    return session if isinstance(session, str) else None


def record_handed(marker, session):
    path = handed_file(marker)
    tmp = f"{path}.{os.getpid()}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"key": handed_key(marker), "session": session}, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass


def session_id(data):
    value = data.get("session_id")
    return value if isinstance(value, str) and SESSION_ID.fullmatch(value) else None


def clip(value):
    return value[:TRACE_FIELD_LIMIT] if isinstance(value, str) else None


def trace_file():
    return os.path.join(state_dir(), "runs.log")


def trace_lock():
    try:
        if fcntl is None:
            return None
        fd = os.open(os.path.join(state_dir(), "runs.lock"), os.O_RDWR | os.O_CREAT, 0o600)
    except OSError:
        return None
    wait_until = time.monotonic() + TRACE_LOCK_S
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except OSError:
            if time.monotonic() >= wait_until:
                os.close(fd)
                return None
            time.sleep(0.01)


def rotate_trace(path):
    try:
        if os.path.isfile(path) and os.path.getsize(path) > TRACE_LIMIT:
            test_pause()
            os.replace(path, path + ".1")
    except OSError:
        pass


def write_trace(seen, began):
    try:
        entry = {
            "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "ms": int((time.monotonic() - began) * 1000),
        }
        entry.update(seen)
        os.makedirs(state_dir(), exist_ok=True)
        path = trace_file()
        lock = trace_lock()
        try:
            if lock is not None:
                rotate_trace(path)
            with open(path, "a", encoding="utf-8", errors="backslashreplace") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        finally:
            if lock is not None:
                os.close(lock)
    except Exception:
        pass


def saved_time(marker):
    try:
        return datetime.strptime(marker["saved_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def registered(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return False
    hooks = data.get("hooks") if isinstance(data, dict) else None
    groups = hooks.get("SessionStart") if isinstance(hooks, dict) else None
    for group in groups if isinstance(groups, list) else ():
        entries = group.get("hooks") if isinstance(group, dict) else None
        for entry in entries if isinstance(entries, list) else ():
            command = entry.get("command") if isinstance(entry, dict) else None
            if isinstance(command, str) and "handoff.py" in command and "start" in command:
                return True
    return False


def find_plugin_hooks():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if not os.path.isfile(os.path.join(root, ".claude-plugin", "plugin.json")):
        return ()
    return (
        os.path.join(root, "hooks", "hooks.json"),
    )


def enabled(cwd):
    return any(registered(path) for path in (
        os.path.join(cwd, ".claude", "settings.local.json"),
        os.path.join(cwd, ".claude", "settings.json"),
        os.path.join(config_root(), "settings.json"),
    ) + find_plugin_hooks())


def read_regular(path, limit):
    try:
        if not usable(path) or not os.path.isfile(path) or os.path.getsize(path) > limit:
            return None
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except (OSError, ValueError):
        return None


def body_start(lines):
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return i + 1
    return 0


def bounded_in(want, have):
    left = ""
    if want[0].isdigit():
        left = r"(?<![\w.,\-−])"
    elif want[0].isalnum():
        left = r"(?<!\w)"
    right = r"(?!\w)(?![.,]\d)" if want[-1].isalnum() else ""
    return re.search(left + re.escape(want) + right, have) is not None


def is_same_folder(folder, root):
    try:
        return os.path.samestat(os.stat(folder), root)
    except (OSError, ValueError):
        return False


def is_in_notes_folder(real):
    try:
        root = os.stat(get_notes_root())
    except OSError:
        return False
    folders = [os.path.dirname(real)]
    while folders[-1] != os.path.dirname(folders[-1]):
        folders.append(os.path.dirname(folders[-1]))

    return any(is_same_folder(folder, root) for folder in folders)


def verify_cite(match, base_dir, note_real, cache):
    raw = match.group("path").strip().strip("`")
    if not usable(raw):
        return "quote: bad path"
    path = os.path.expanduser(raw)
    if not os.path.isabs(path):
        path = os.path.join(base_dir, path)
    real = os.path.realpath(path)
    if note_real and (real == note_real or is_same_file(real, note_real)):
        return "quote of the note itself is not a source"
    if in_memory(real):
        return f"quote of Claude's memory is not a source: {raw}"
    if is_in_notes_folder(real):
        return f"quote of the notes folder is not a source: {raw}"
    if real not in cache:
        text = read_regular(real, SOURCE_SIZE_LIMIT)
        cache[real] = None if text is None else text.split("\n")
    lines = cache[real]
    if lines is None:
        return f"quote: no regular file up to 2 MB: {raw}"
    number = int(match.group("line"))
    if number < 1 or number > len(lines):
        return f"quote: {raw} has no line {number}"
    key = (real, number)
    if key not in cache:
        cache[key] = " ".join(lines[number - 1].split())
    quoted = next(t for t in (match.group("t1"), match.group("t2"), match.group("t3")) if t is not None)
    want = " ".join(quoted.split())
    if not want:
        return "quote is empty — nothing to compare"
    if not bounded_in(want, cache[key]):
        return f"quote: text not found at {raw}:{number}: \"{want[:60]}\""
    return None


def check_text(text, base_dir, note_real):
    problems = []
    cache = {}
    lines = text.split("\n")
    fence = None
    fence_line = 0
    for i in range(body_start(lines), len(lines)):
        number = i + 1
        if out_of_time():
            problems.append((number, "check ran out of time before the end of the note"))
            fence = None
            break
        line = lines[i]
        found = FENCE.match(line)
        if fence is None and found:
            fence, fence_line = found.group("fence"), number
            continue
        if fence is not None:
            if found and found.group("fence")[0] == fence[0] and len(found.group("fence")) >= len(fence) \
                    and not found.group("info").strip():
                fence = None
            continue
        if len(line) > LINE_LENGTH_LIMIT:
            problems.append((number, "line longer than 5,000 characters — not checked"))
            continue
        for match in CITE.finditer(line):
            if out_of_time():
                break
            reason = verify_cite(match, base_dir, note_real, cache)
            if reason:
                problems.append((number, reason))
        rest = CITE.sub(" ", line)
        if CITE_START.search(INLINE_CODE.sub(" ", rest)):
            problems.append((number, "quote not parsed — write (cite: <path>:<line> \"<exact text>\")"))
        for match in RATIO_PERCENT.finditer(rest):
            n, m = int(match.group("n")), int(match.group("m"))
            p = float(match.group("p").replace(",", "."))
            if m == 0 or abs(n * 100 / m - p) > 1:
                share = "—" if m == 0 else f"{n * 100 / m:.1f}%"
                problems.append((number, f"arithmetic: {n} of {m} is {share}, written {match.group('p')}%"))
        for clause in CLAUSE_BREAK.split(SYSTEM_SOURCE.sub("(cmd: -)", RATIO_PERCENT.sub(" ", rest))):
            if NUMBER_CLAIM.search(clause) and not SYSTEM_SOURCE.search(clause):
                problems.append((number, "number with no quote and no source"))
                break
    if fence is not None:
        problems.append((fence_line, "code block not closed — the lines after it were not checked"))
    return problems


def checked(text, base_dir, note_real):
    try:
        return check_text(text, base_dir, note_real)
    except Exception as error:
        _check_errors.append(type(error).__name__)
        return [(None, f"note check failed ({type(error).__name__}) — check the note yourself")]


def problem_lines(problems):
    out = [f"- line {number}: {reason}" if number else f"- {reason}" for number, reason in problems[:PROBLEM_LIMIT]]
    if len(problems) > PROBLEM_LIMIT:
        out.append(f"- and {len(problems) - PROBLEM_LIMIT} more")
    return out


def remote_mark(repo, ref):
    mark = " (local ref, no fetch)"
    if ref.startswith("origin/"):
        return mark
    code, name = run(["git", "-c", "core.fsmonitor=false", "-C", repo, "rev-parse", "--verify", "--quiet",
                      "--symbolic-full-name", "--end-of-options", ref], time_left(1.0))
    return mark if code == 0 and (name or "").startswith("refs/remotes/") else ""


def state_lines(text):
    out = []
    for line in text.split("\n"):
        match = GIT_FACT.match(line.replace("`", ""))
        if not match:
            continue
        if len(out) >= STATE_FACT_LIMIT:
            out.append("- further state facts not checked: more than four")
            break
        raw, ref, noted = match.group("repo"), match.group("ref"), match.group("sha")
        if not usable(raw):
            out.append(f"- git: bad path, {ref} not checked")
            continue
        repo = os.path.realpath(os.path.expanduser(raw))
        if out_of_time():
            out.append(f"- git {repo} {ref}: no time to check")
            continue
        if not os.path.isdir(repo):
            out.append(f"- git {repo} {ref}: no such folder")
            continue
        code, current = run(["git", "-c", "core.fsmonitor=false", "-C", repo, "rev-parse", "--verify",
                             "--quiet", "--end-of-options", ref + "^{commit}"], time_left(1.0))
        current = (current or "").strip()
        if code is None:
            out.append(f"- git {repo} {ref}: no time to check")
        elif code != 0 or not current:
            out.append(f"- git {repo} {ref}: not found")
        elif current.startswith(noted):
            local = remote_mark(repo, ref)
            out.append(f"- git {repo} {ref} = {noted}: matches{local}")
        else:
            local = remote_mark(repo, ref)
            out.append(f"- git {repo} {ref}: was {noted}, now {current[:len(noted)]}{local}")
    return out


def note_head(text):
    lines = text.split("\n")
    lines = lines[body_start(lines):]
    now = next((i for i, line in enumerate(lines) if NOW_HEADING.match(line)), None)
    kept = []
    size = 0
    headings = 0
    for i, line in enumerate(lines[now or 0:]):
        if line.startswith("## "):
            headings += 1
            if (now is not None and i > 0) or headings == 2:
                break
        if size + len(line) + 1 > HEAD_LIMIT:
            kept.append("[… cut, the rest is in the file]")
            break
        kept.append(line)
        size += len(line) + 1
    return "\n".join(kept).strip("\n")


def fetch_hint(facts):
    if any("no fetch" in fact for fact in facts):
        if all(" origin/" in fact for fact in facts if "no fetch" in fact):
            return ["origin/* refs were compared with local refs; what the server has now needs `git fetch`."]
        return ["Remote refs were compared with local refs; what the server has now needs `git fetch`."]
    return []


def render_own(marker):
    text = read_regular(marker["note"], SOURCE_SIZE_LIMIT) or ""
    out = [
        f"[handoff] This session continues the note \"{marker['topic']}\", saved "
        f"{marker['saved_at']} by this same Claude process: {marker['note']}",
        "Below is the NOW section (or the start of the note); read the rest in the file.",
        "--- note ---",
        note_head(text),
        "--- end of excerpt ---",
    ]
    problems = checked(text, marker["cwd"], os.path.realpath(marker["note"]))
    if problems:
        out.append("Not verified (check against the source before relying on it):")
        out.extend(problem_lines(problems))
    facts = state_lines(text)
    if facts:
        out.append("State compared with the system:")
        out.extend(facts)
        out.extend(fetch_hint(facts))
    return "\n".join(out)


def get_list_blocks(markers):
    blocks = [[
        "[handoff] Sessions that already closed left notes in this folder. Do not hold up the user's "
        "request for them: do what the user asks, and in your first reply mention these notes in one "
        "short line, in the user's language, so the user can pick one. Continue a note only if the user "
        "picks it; if the user asks to continue earlier work, offer these notes and wait for the choice:"
    ]]
    all_facts = []
    for index, marker in enumerate(markers, 1):
        text = read_regular(marker["note"], SOURCE_SIZE_LIMIT) or ""
        out = [f"{index}. \"{marker['topic']}\" — saved {marker['saved_at']}: {marker['note']}"]
        problems = checked(text, marker["cwd"], os.path.realpath(marker["note"]))
        if problems and problems[0][0] is None:
            out.append(f"   {problems[0][1]}")
        elif problems:
            out.append(f"   unverified lines: {len(problems)}")
        facts = state_lines(text)
        all_facts.extend(facts)
        out.extend("   " + fact for fact in facts)
        blocks.append(out)
    blocks.append(fetch_hint(all_facts))
    return blocks


def get_joined(blocks, marks=None):
    lines = []
    for index, block in enumerate(blocks):
        mark = marks[index - 1] if marks and 0 < index <= len(marks) else None
        lines.extend(block[:1] + ([mark] if mark else []) + block[1:])

    return "\n".join(lines)


def cap_utf16(text, limit):
    encoded = text.encode("utf-16-le")
    if len(encoded) // 2 <= limit:
        return text
    return encoded[:limit * 2].decode("utf-16-le", errors="ignore")


def get_payload(user, model, event):
    payload = {}
    if user is not None and _tell:
        payload["systemMessage"] = cap_utf16(user, USER_LINE_LIMIT)
    if model is not None:
        payload["hookSpecificOutput"] = {
            "hookEventName": event,
            "additionalContext": model,
        }
    if not payload:
        return None

    return json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n"


def say(user, model, event="SessionStart"):
    global _printed
    data = get_payload(user, model, event)
    if data is None:
        return
    _printed = True
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def say_within(
    user,
    model,
    event,
):
    data = get_payload(user, model, event)
    if data is None:
        return True
    end = min(time.monotonic() + PRINT_LIMIT_S, _deadline)
    try:
        fd = sys.stdout.fileno()
        blocking = os.get_blocking(fd)
        os.set_blocking(fd, False)
    except (OSError, ValueError):
        return False
    try:
        return is_written(fd, memoryview(data), end)
    except OSError:
        return False
    finally:
        set_blocking_back(fd, blocking)


def set_blocking_back(fd, blocking):
    try:
        os.set_blocking(fd, blocking)
    except OSError:
        pass


def is_written(fd, view, end):
    global _printed
    while view:
        left = end - time.monotonic()
        if left <= 0:
            return False
        try:
            count = os.write(fd, view)
        except BlockingIOError:
            select.select([], [fd], [], left)
            continue
        _printed = True
        view = view[count:]

    return True


def tell_failure(kind):
    if _printed:
        return
    try:
        say(f"{USER_LINE_START} failed ({kind}), see {get_shown(trace_file())}", None)
    except Exception:
        pass


def is_hidden_char(ch):
    code = ord(ch)
    return (
        unicodedata.category(ch) in USER_LINE_CONTROL
        or 0x202A <= code <= 0x202E
        or 0x2066 <= code <= 0x2069
    )


def get_shown(text):
    return "".join(ch for ch in text if not is_hidden_char(ch))


def get_topic(marker):
    return get_shown(marker["topic"])[:TOPIC_LIMIT]


def get_receiver(session):
    return f"session {session}" if SESSION_ID.fullmatch(session) else "another session"


def get_note_noun(count):
    return "note" if count == 1 else "notes"


def get_unlisted_line(unchecked):
    if unchecked:
        return f"{USER_LINE_START} could not check {unchecked} {get_note_noun(unchecked)} in time, none listed"

    return f"{USER_LINE_START} no notes from closed sessions in this folder"


def get_list_line(
    markers,
    hidden,
    unchecked,
    marks=(),
):
    found = len(markers) + hidden
    head = f"{USER_LINE_START} {found} {get_note_noun(found)} from closed sessions in this folder:"
    items = [f"{index}. \"{get_topic(marker)}\" — {get_shown(marker['note'])}" for index, marker in enumerate(markers, 1)]
    items = [item + (f"\n{MARK_INDENT}{mark}" if mark else "") for item, mark in zip(items, list(marks) + [None] * len(items))]
    tail = f"\ncould not check {unchecked} more {get_note_noun(unchecked)} in time" if unchecked else ""
    for kept in range(len(items), -1, -1):
        dropped = len(items) - kept + hidden
        more = f"\nand {dropped} more" if dropped else ""
        read = sum(1 for mark in marks[kept:] if mark)
        more += f", {read} of them being read by another session" if read else ""
        text = head + "".join("\n" + item for item in items[:kept]) + more + tail
        if len(text.encode("utf-16-le")) // 2 <= USER_LINE_LIMIT:
            return text

    return text


def time_budget(default=TIME_BUDGET_S):
    if testing() and os.environ.get("HANDOFF_TEST_BUDGET"):
        return float(os.environ["HANDOFF_TEST_BUDGET"])
    return default


def test_pause():
    if testing() and os.environ.get("HANDOFF_TEST_PAUSE"):
        time.sleep(float(os.environ["HANDOFF_TEST_PAUSE"]))


def unattended():
    attended = os.environ.get("CLAUDE_CODE_SESSION_ATTENDED")
    if attended is not None:
        return attended.strip() == "0"
    return os.environ.get("CLAUDE_CODE_ENTRYPOINT", "").startswith("sdk")


def cmd_start(seen):
    global _deadline, _tell
    if os.environ.get("HANDOFF_OFF") == "1":
        seen["outcome"] = "off"
        return 0
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except (ValueError, RecursionError):
        seen["outcome"] = "bad-input"
        return 0
    if not isinstance(data, dict):
        seen["outcome"] = "bad-input"
        return 0
    source, cwd = data.get("source"), data.get("cwd")
    session = session_id(data)
    seen.update(source=clip(source), session=session, cwd=clip(cwd) if usable(cwd) else None)
    if source not in ("clear", "startup") or not usable(cwd):
        seen["outcome"] = "skipped"
        return 0
    if source == "startup" and unattended():
        seen["outcome"] = "unattended"
        return 0
    _tell = not unattended()
    _deadline = time.monotonic() + time_budget()
    markers = checked_markers()
    if source == "clear":
        proc = claude_process()
        if not proc:
            seen["outcome"] = "no-process"
            say(f"{USER_LINE_START} could not identify this Claude process, no anchor given", None)
            return 0
        seen["pid"] = proc[0]
        own = [m for m in markers if m["pid"] == proc[0] and m["started"] == proc[1]]
        given = handed_session(own[0]) if own and session else None
        if _tell:
            set_unlisted(
                proc,
                find_kept_reals(
                    own,
                    given,
                    session,
                    markers,
                ),
                seen,
            )
        if not own:
            seen["outcome"] = "no-own-marker"
            say(f"{USER_LINE_START} no anchor saved in this Claude process", None)
            return 0
        if given is not None and given != session:
            seen.update(outcome="handed-elsewhere", handed_to=clip(given))
            say(f"{USER_LINE_START} anchor \"{get_topic(own[0])}\" was already given to {get_receiver(given)}", None)
            return 0
        if not _tell:
            say(
                f"{USER_LINE_START} continuing anchor \"{get_topic(own[0])}\" — {get_shown(own[0]['note'])}",
                cap_utf16(render_own(own[0]), OUTPUT_LIMIT),
            )
        elif not set_given_note(
            own[0],
            proc,
            markers,
            session,
            seen,
        ):
            seen["outcome"] = "not-printed"
            return 0
        if session and given is None:
            record_handed(own[0], session)
        receiver = "none" if not session else ("new" if given is None else "same")
        seen.update(outcome="gave-note", receiver=receiver)
        return 0
    else:
        now = datetime.now(timezone.utc)
        closed = []
        unchecked = 0
        for marker in markers:
            late = out_of_time()
            here = marker["cwd"] == cwd if late else same_path(marker["cwd"], cwd)
            if not here:
                continue
            when = saved_time(marker)
            if when is None or now - when > MAX_AGE:
                continue
            state = "unknown" if late else liveness(marker)
            if state == "unknown":
                unchecked += 1
            if state != "closed":
                continue
            closed.append((when, marker))
        seen["unchecked"] = unchecked
        if not closed:
            seen["outcome"] = "unchecked" if unchecked else "no-closed"
            say(get_unlisted_line(unchecked), None)
            return 0
        closed.sort(key=lambda pair: pair[0], reverse=True)
        shown = [marker for _, marker in closed[:LIST_LIMIT]]
        blocks = get_list_blocks(shown)
    user, model = find_marked_list(
        shown,
        len(closed) - len(shown),
        unchecked,
        blocks,
        markers,
        seen,
    )
    say(user, model)
    seen.update(outcome="listed", listed=len(shown))
    return 0


def get_units(text):
    return len(text.encode("utf-16-le")) // 2


def get_file_id(path):
    try:
        info = os.stat(path)
    except (OSError, ValueError):
        return None

    return info.st_dev, info.st_ino


def get_cached_id(path, ids):
    if path not in ids:
        ids[path] = get_file_id(path)

    return ids[path]


def find_group_reals(
    note,
    markers,
    ids=None,
):
    ids = {} if ids is None else ids
    want = get_cached_id(note, ids)
    reals = []
    for marker in markers:
        if want is None or get_cached_id(marker["note"], ids) != want:
            continue
        real = os.path.realpath(marker["note"])
        if real not in reals:
            reals.append(real)

    return reals


def is_handed_elsewhere(given, session):
    return given is not None and given != session


def find_kept_reals(
    own,
    given,
    session,
    markers,
):
    if not own or is_handed_elsewhere(given, session):
        return []

    return find_group_reals(own[0]["note"], markers)


def get_taken_folder():
    return os.path.join(state_dir(), TAKEN_FOLDER)


def get_taken_kind():
    try:
        info = os.lstat(get_taken_folder())
    except FileNotFoundError:
        return "absent"
    except OSError:
        return "other"

    return "folder" if stat.S_ISDIR(info.st_mode) else "other"


def get_note_key(real):
    return hashlib.sha256(os.fsencode(real)).hexdigest()


def is_key_of(note, key):
    try:
        return isinstance(note, str) and get_note_key(note) == key
    except (UnicodeError, ValueError):
        return False


def get_mark_path(key):
    return os.path.join(get_taken_folder(), key + ".json")


def get_reads_name(pid, started):
    return marker_file(pid, started)[:-len(".json")] + ".reads"


def get_reads_path(proc):
    return os.path.join(get_taken_folder(), get_reads_name(proc[0], proc[1]))


def get_small_json(path, limit):
    if not os.path.lexists(path):
        return "absent", None
    text, error = get_small_text(path, limit)
    if error == "is not UTF-8":
        return "bad", None
    if error:
        return "unreadable", None
    try:
        return "ok", json.loads(text)
    except (ValueError, RecursionError):
        return "bad", None


def is_stamp(value):
    try:
        datetime.strptime(value, STAMP)
    except (TypeError, ValueError):
        return False

    return True


def is_pid(value):
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and value > 0
    )


def is_reader(entry):
    return (
        isinstance(entry, dict)
        and is_pid(entry.get("pid"))
        and usable(entry.get("started"))
        and (entry.get("session") is None or isinstance(entry.get("session"), str))
        and is_stamp(entry.get("at"))
    )


def get_reader_key(reader):
    return reader["pid"], reader["started"]


def get_clean_reader(entry):
    return {
        "pid": entry["pid"],
        "started": entry["started"],
        "session": entry.get("session"),
        "at": entry["at"],
    }


def create_reader(proc, session):
    return {
        "pid": proc[0],
        "started": proc[1],
        "session": session,
        "at": datetime.now(timezone.utc).strftime(STAMP),
    }


def get_merged_readers(lists):
    found = {}
    for reader in [reader for readers in lists for reader in readers]:
        key = get_reader_key(reader)
        if key not in found or reader["at"] < found[key]["at"]:
            found[key] = reader

    return sorted(found.values(), key=lambda reader: (reader["at"], reader["pid"]))


def get_others(readers, proc):
    return [reader for reader in readers if get_reader_key(reader) != proc]


def is_mark_shape(data, key):
    return (
        isinstance(data, dict)
        and is_key_of(data.get("note"), key)
        and isinstance(data.get("readers"), list)
    )


def get_mark_file(key):
    state, data = get_small_json(get_mark_path(key), TAKEN_LIMIT)
    if state == "unreadable":
        return state, None, None
    if state != "ok" or not is_mark_shape(data, key):
        return "absent" if state == "absent" else "bad", [], None
    if len(data["readers"]) > READER_LIMIT:
        return "unreadable", None, None
    readers = [get_clean_reader(entry) for entry in data["readers"] if is_reader(entry)]

    return "ok", get_merged_readers([readers]), data["note"]


def is_reads_shape(data, proc):
    return (
        isinstance(data, dict)
        and data.get("pid") == proc[0]
        and data.get("started") == proc[1]
        and isinstance(data.get("keys"), list)
    )


def get_reads_file(proc):
    state, data = get_small_json(get_reads_path(proc), TAKEN_LIMIT)
    if state == "unreadable":
        return state, None
    if state != "ok" or not is_reads_shape(data, proc):
        return "absent" if state == "absent" else "bad", []
    if len(data["keys"]) > READS_KEY_LIMIT:
        return "unreadable", None
    keys = [key for key in data["keys"] if isinstance(key, str) and NOTE_KEY.fullmatch(key)]

    return "ok", list(dict.fromkeys(keys))


def get_json_bytes(data):
    return json.dumps(data, ensure_ascii=False).encode("utf-8") + b"\n"


def get_mark_bytes(note, readers):
    return get_json_bytes({
        "note": note,
        "readers": readers,
    })


def get_reads_bytes(proc, keys):
    return get_json_bytes({
        "pid": proc[0],
        "started": proc[1],
        "keys": keys,
    })


def get_pid_state(pid, until):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return "gone", None
    except (OverflowError, ValueError):
        return "gone", None
    except OSError:
        pass
    if time.monotonic() >= until:
        return "unknown", None

    return process_start(pid, until)


def get_verdict(state, reader):
    status, started = state
    if status == "gone":
        return "dead"
    if status == "ok":
        return "alive" if started == reader["started"] else "dead"

    return "unknown"


def get_reader_states(
    readers,
    until,
    cache,
):
    states = {}
    for reader in readers:
        if reader["pid"] not in cache:
            cache[reader["pid"]] = get_pid_state(reader["pid"], until)
        states[get_reader_key(reader)] = get_verdict(cache[reader["pid"]], reader)

    return states


def create_mark(
    others,
    states,
    known,
    unreadable,
):
    seen = {get_reader_key(reader) for reader in known}

    return {
        "live": [r for r in others if get_reader_key(r) not in seen or states.get(get_reader_key(r)) == "alive"],
        "unknown": [r for r in others if get_reader_key(r) in seen and states.get(get_reader_key(r)) == "unknown"],
        "unreadable": unreadable,
    }


def has_mark(mark):
    return bool(mark) and bool(mark["live"] or mark["unknown"] or mark["unreadable"])


def get_reader_item(reader):
    session = reader["session"]
    who = f"session {session}" if isinstance(session, str) and SESSION_ID.fullmatch(session) else "a session"

    return f"{who} (pid {reader['pid']}, since {reader['at']})"


def get_reader_list(readers, shown):
    listed = ", ".join(get_reader_item(reader) for reader in readers[:shown])
    more = len(readers) - shown
    if not more:
        return listed

    return f"{listed}, and {more} more" if listed else f"and {more} more"


def get_facts(
    mark,
    words,
    shown=None,
):
    live, unknown = mark["live"], mark["unknown"]
    shown = len(live) + len(unknown) if shown is None else shown
    text = words[0].format(len(live)) + get_reader_list(live, min(shown, len(live))) if live else ""
    if unknown:
        lead = MORE_WORDS if live else words[1]
        text += lead.format(len(unknown)) + get_reader_list(unknown, max(0, shown - len(live)))
    if mark["unreadable"]:
        text += ("; " if text else "") + UNREADABLE_MARK

    return text


def find_fitting(
    mark,
    words,
    frame,
    limit,
):
    prefix, suffix = frame
    text = ""
    for shown in range(len(mark["live"]) + len(mark["unknown"]), -1, -1):
        text = prefix + get_facts(
            mark,
            words,
            shown,
        ) + suffix
        if get_units(text) <= limit:
            return text

    return cap_utf16(text, limit)


def get_short_facts(mark):
    return find_fitting(
        mark,
        MARK_WORDS,
        ("", ""),
        MARK_LIST_LIMIT,
    )


def get_took_output(mark):
    user = find_fitting(
        mark,
        TOOK_WORDS,
        (f"{USER_LINE_START} ", ""),
        USER_LINE_LIMIT,
    )
    model = find_fitting(
        mark,
        TOOK_WORDS,
        ("[handoff] ", f". {TOOK_ASK}"),
        OUTPUT_LIMIT,
    )

    return user, model


def get_clear_output(
    marker,
    body,
    mark,
):
    user = f"{USER_LINE_START} continuing anchor \"{get_topic(marker)}\" — {get_shown(marker['note'])}"
    if not has_mark(mark):
        return user, cap_utf16(body, OUTPUT_LIMIT)
    facts = get_short_facts(mark)

    return f"{user}\n{MARK_INDENT}{facts}", cap_utf16(f"[handoff] {facts}. {TOOK_ASK}\n{body}", OUTPUT_LIMIT)


def find_mark(
    reals,
    kind,
    until,
    cache,
):
    if kind != "folder":
        return create_mark(
            [],
            {},
            [],
            True,
        )
    lists, unreadable = [], False
    for real in reals:
        state, readers, _ = get_mark_file(get_note_key(real))
        unreadable = unreadable or state == "unreadable"
        lists.append(readers or [])
    union = get_merged_readers(lists)
    mark = create_mark(
        union,
        get_reader_states(
            union,
            until,
            cache,
        ),
        union,
        unreadable,
    )

    return mark if has_mark(mark) else None


def find_marks(shown, markers):
    kind = get_taken_kind()
    if kind == "absent":
        return [None] * len(shown)
    until = _deadline - MARKS_SPARE_S
    ids, cache = {}, {}

    return [find_mark(
        find_group_reals(
            marker["note"],
            markers,
            ids,
        ),
        kind,
        until,
        cache,
    ) for marker in shown]


def find_model_marks(blocks, found):
    marks = [None] * len(found)
    dropped = 0
    for index, mark in enumerate(found):
        if not mark:
            continue
        marks[index] = f"{MARK_INDENT}{get_facts(mark, MARK_WORDS)}. {LIST_ASK}"
        if get_units(get_joined(blocks, marks)) > OUTPUT_LIMIT:
            marks[index] = None
            dropped += 1

    return marks, dropped


def find_marked_list(
    shown,
    hidden,
    unchecked,
    blocks,
    markers,
    seen,
):
    plain = get_list_line(shown, hidden, unchecked), cap_utf16(get_joined(blocks), OUTPUT_LIMIT)
    seen.update(marks=0, marks_dropped=0)
    try:
        found = find_marks(shown, markers)
        if not any(found):
            return plain
        model_marks, dropped = find_model_marks(blocks, found)
        user_marks = [get_short_facts(mark) if mark else None for mark in found]
        seen.update(marks=sum(1 for mark in found if mark), marks_dropped=dropped)
        user = get_list_line(
            shown,
            hidden,
            unchecked,
            user_marks,
        )
        return user, cap_utf16(get_joined(blocks, model_marks), OUTPUT_LIMIT)
    except Exception as error:
        seen.update(marks=0, marks_dropped=0, marks_error=type(error).__name__)
        return plain


def set_signal(kind):
    folder = os.environ.get("HANDOFF_TEST_TAKEN_SIGNAL") if testing() else None
    if not folder:
        return
    fd = os.open(
        os.path.join(folder, f"{os.getpid()}.{kind}"),
        os.O_WRONLY | os.O_CREAT,
        0o600,
    )
    os.close(fd)


def create_taken_folder():
    try:
        os.mkdir(get_taken_folder(), 0o700)
    except FileExistsError:
        pass
    except OSError:
        return "taken-not-created"
    kind = get_taken_kind()
    if kind != "folder":
        return "taken-not-folder"

    return None


def get_lock_flags(create):
    flags = os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC

    return flags | os.O_CREAT if create else flags


def get_taken_lock(create, until):
    if fcntl is None:
        return None, "no-locking"
    error = create_taken_folder() if create else None
    if error:
        return None, error
    try:
        fd = os.open(
            os.path.join(get_taken_folder(), TAKEN_LOCK),
            get_lock_flags(create),
            0o600,
        )
    except OSError:
        return None, "lock-not-opened"
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        return None, "lock-not-file"
    if time.monotonic() >= until:
        os.close(fd)
        return None, "no-time"
    set_signal("waiting")
    while not try_lock(fd):
        if time.monotonic() >= until:
            os.close(fd)
            return None, "lock-busy"
        time.sleep(LOCK_STEP_S)
    set_signal("locked")

    return fd, None


def remove_quietly(path):
    try:
        os.remove(path)
    except OSError:
        pass


def set_written(
    fd,
    path,
    data,
):
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
    except OSError:
        remove_quietly(path)
        raise


def create_temp_file(data):
    folder = get_taken_folder()
    for number in range(NAME_TRIES):
        path = os.path.join(folder, f".tmp-{os.getpid()}-{number}.json")
        try:
            fd = os.open(
                path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
            )
        except FileExistsError:
            continue
        set_written(
            fd,
            path,
            data,
        )
        return path

    raise FileExistsError(f"no free temporary name in {folder}")


def set_replaced(tmp, path):
    if testing() and os.environ.get("HANDOFF_TEST_FAIL") == "replace":
        raise OSError("os.replace failed on purpose (HANDOFF_TEST_FAIL=replace)")
    os.replace(tmp, path)


def remove_temps(pairs):
    for tmp, _ in pairs or ():
        remove_quietly(tmp)


def set_replaced_all(pairs):
    for index, (tmp, path) in enumerate(pairs):
        try:
            set_replaced(tmp, path)
        except OSError:
            remove_temps(pairs[index:])
            return "replace"

    return None


def remove_dead_reads(dead):
    for pid, started in dead:
        remove_quietly(os.path.join(get_taken_folder(), get_reads_name(pid, started)))


def find_snapshot(reals, proc):
    snapshot = {
        "union": [],
        "unreadable": False,
        "reads_unreadable": False,
    }
    if get_taken_kind() != "folder":
        return snapshot
    lists = []
    for real in reals:
        state, readers, _ = get_mark_file(get_note_key(real))
        snapshot["unreadable"] = snapshot["unreadable"] or state == "unreadable"
        lists.append(readers or [])
    snapshot["union"] = get_merged_readers(lists)
    snapshot["reads_unreadable"] = get_reads_file(proc)[0] == "unreadable"

    return snapshot


def get_snapshot_mark(
    snapshot,
    states,
    proc,
):
    others = get_others(snapshot["union"], proc)

    return create_mark(
        others,
        states,
        others,
        snapshot["unreadable"],
    )


def is_reader_in(readers, proc):
    return any(get_reader_key(reader) == proc for reader in readers)


def set_plan_content(
    plan,
    files,
    kept,
    reader,
):
    proc = get_reader_key(reader)
    for real, readers in kept.items():
        mine = is_reader_in(readers, proc)
        if not mine and len(readers) >= READER_LIMIT:
            plan["full"] = True
        content = readers if mine else get_merged_readers([readers, [reader]])
        if content != files[real]:
            plan["files"][real] = content


def set_plan_reads(
    plan,
    proc,
    keys,
    wanted,
):
    keys_after = keys + [key for key in wanted if key not in keys]
    if keys_after == keys:
        return
    data = get_reads_bytes(proc, keys_after)
    if len(keys_after) > READS_KEY_LIMIT or len(data) > TAKEN_LIMIT:
        plan["full"] = True
    plan["reads"] = data


def find_plan(
    reals,
    proc,
    session,
    snapshot,
    states,
):
    files = {}
    for real in reals:
        state, readers, _ = get_mark_file(get_note_key(real))
        if state == "unreadable":
            return None
        files[real] = readers
    reads_state, keys = get_reads_file(proc)
    if reads_state == "unreadable":
        return None
    dead = {key for key, verdict in states.items() if verdict == "dead"}
    kept = {real: [r for r in readers if get_reader_key(r) not in dead] for real, readers in files.items()}
    union = get_merged_readers(kept.values())
    mine = [reader for reader in union if get_reader_key(reader) == proc]
    plan = {
        "again": bool(mine),
        "mark": create_mark(
            get_others(union, proc),
            states,
            snapshot,
            False,
        ),
        "dead": {get_reader_key(r) for readers in files.values() for r in readers if get_reader_key(r) in dead},
        "full": False,
        "files": {},
        "reads": None,
    }
    set_plan_content(
        plan,
        files,
        kept,
        mine[0] if mine else create_reader(proc, session),
    )
    set_plan_reads(
        plan,
        proc,
        keys,
        [get_note_key(real) for real in reals],
    )

    return plan


def create_plan_temps(plan, proc):
    pairs = []
    try:
        if plan["reads"] is not None:
            pairs.append((create_temp_file(plan["reads"]), get_reads_path(proc)))
        for real, readers in plan["files"].items():
            pairs.append((create_temp_file(get_mark_bytes(real, readers)), get_mark_path(get_note_key(real))))
    except (OSError, ValueError):
        remove_temps(pairs)
        return None, "temp"

    return pairs, None


def find_plan_temps(plan, proc):
    if plan is None:
        return None, "unreadable"
    if plan["full"]:
        return None, "full"

    return create_plan_temps(plan, proc)


def get_took_input():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except (ValueError, RecursionError):
        return None

    return data if isinstance(data, dict) else None


def is_read_input(data):
    return data.get("hook_event_name") == "PostToolUse" and data.get("tool_name") == "Read"


def get_read_path(data):
    tool_input = data.get("tool_input")
    path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if not is_read_input(data) or not usable(path) or not os.path.isabs(path):
        return None

    return path


def is_same_place(path, other):
    found = get_file_id(path)

    return found is not None and found == get_file_id(other)


def is_note_place(path):
    name = os.path.basename(path)
    if not name.lower().endswith(".md") or is_service_name(name):
        return False
    folder = os.path.dirname(os.path.normpath(path))
    in_memory_folder = os.path.basename(folder).lower() == "memory"
    if in_memory_folder and is_same_place(os.path.dirname(os.path.dirname(folder)), memory_root()):
        return True

    return is_same_place(os.path.dirname(folder), get_notes_root())


def find_marker_real(path, read_id):
    text, error = get_small_text(path, MARKER_LIMIT)
    if error:
        return None
    try:
        marker = json.loads(text)
    except (ValueError, RecursionError):
        return None
    if not is_marker_shape(marker) or get_file_id(os.path.expanduser(marker["note"])) != read_id:
        return None
    kept = allowed_note(marker["note"], marker["cwd"])
    if kept is None or get_file_id(kept) != read_id:
        return None

    return os.path.realpath(kept)


def find_took_group(read_id):
    folder = state_dir()
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    reals = []
    for name in names:
        if out_of_time():
            return None
        if not name.endswith(".json"):
            continue
        real = find_marker_real(os.path.join(folder, name), read_id)
        if real is not None and real not in reals:
            reals.append(real)

    return reals


def set_took_locked(given, seen):
    plan = find_plan(
        given["reals"],
        given["proc"],
        given["session"],
        given["snapshot"]["union"],
        given["states"],
    )
    if plan is None:
        seen.update(outcome="not-recorded", reason="unreadable")
        return
    mark = plan["mark"]
    warn = has_mark(mark) and not plan["again"]
    seen.update(live=len(mark["live"]), unknown=len(mark["unknown"]), warned=warn)
    pairs, reason = find_plan_temps(plan, given["proc"])
    if warn and not say_within(*get_took_output(mark), "PostToolUse"):
        remove_temps(pairs)
        seen.update(outcome="not-printed", warned=False)
        return
    if reason:
        seen.update(outcome="again" if plan["again"] else "not-recorded", reason=reason)
        return
    test_pause()
    reason = set_replaced_all(pairs)
    if reason:
        seen.update(outcome="not-recorded", reason=reason)
        return
    remove_dead_reads(plan["dead"])
    seen["outcome"] = "again" if plan["again"] else ("took-shared" if warn else "took")


def set_took(given, seen):
    snapshot = find_snapshot(given["reals"], given["proc"])
    if snapshot["unreadable"] or snapshot["reads_unreadable"]:
        seen.update(outcome="not-recorded", reason="unreadable")
        return
    others = get_others(snapshot["union"], given["proc"])
    given.update(snapshot=snapshot, states=get_reader_states(others, _deadline - CHECK_SPARE_S, {}))
    lock, reason = get_taken_lock(True, _deadline - LOCK_SPARE_S)
    if lock is None:
        mark = get_snapshot_mark(snapshot, given["states"], given["proc"])
        warn = has_mark(mark) and not is_reader_in(snapshot["union"], given["proc"])
        if warn:
            say(*get_took_output(mark), "PostToolUse")
        seen.update(outcome="not-recorded", reason=reason, warned=warn, live=len(mark["live"]), unknown=len(mark["unknown"]))
        return
    try:
        set_took_locked(given, seen)
    finally:
        os.close(lock)


def cmd_took(seen):
    global _deadline, _tell
    _deadline = time.monotonic() + time_budget(TOOK_BUDGET_S)
    if os.environ.get("HANDOFF_OFF") == "1" or unattended():
        return
    data = get_took_input()
    if data is None:
        seen["outcome"] = "bad-input"
        return
    if data.get("agent_id") is not None:
        return
    session = session_id(data)
    path = get_read_path(data)
    if path is None:
        seen.update(outcome="bad-input", session=session)
        return
    read_id = get_file_id(path) if is_note_place(path) else None
    reals = find_took_group(read_id) if read_id is not None else []
    if reals is None:
        seen.update(outcome="incomplete", session=session)
        return
    if not reals:
        return
    seen.update(session=session, note=clip(reals[0]))
    proc = claude_process()
    if not proc:
        seen["outcome"] = "no-process"
        return
    seen["pid"] = proc[0]
    _tell = True
    given = {
        "reals": reals,
        "proc": proc,
        "session": session,
    }
    set_took(given, seen)


def find_checked_snapshot(given, seen):
    try:
        snapshot = find_snapshot(given["reals"], given["proc"])
        others = get_others(snapshot["union"], given["proc"])
        given.update(snapshot=snapshot, states=get_reader_states(others, _deadline, {}))
        return True
    except Exception as error:
        seen.update(reader="error", marks_error=type(error).__name__)
        return False


def set_given_locked(given, seen):
    plan = find_plan(
        given["reals"],
        given["proc"],
        given["session"],
        given["snapshot"]["union"],
        given["states"],
    )
    mark = plan["mark"] if plan else dict(get_snapshot_mark(given["snapshot"], given["states"], given["proc"]), unreadable=True)
    pairs, reason = find_plan_temps(plan, given["proc"])
    user, model = get_clear_output(given["marker"], given["body"], mark)
    if not say_within(user, model, "SessionStart"):
        remove_temps(pairs)
        seen["reader"] = "not-printed"
        return False
    if reason:
        seen.update(reader="not-recorded", reason=reason)
        return True
    test_pause()
    reason = set_replaced_all(pairs)
    if reason:
        seen.update(reader="not-recorded", reason=reason)
        return True
    remove_dead_reads(plan["dead"])
    seen["reader"] = "again" if plan["again"] else "took"

    return True


def set_given_note(
    marker,
    proc,
    markers,
    session,
    seen,
):
    global _deadline
    deadline = _deadline
    given = {
        "marker": marker,
        "reals": find_group_reals(marker["note"], markers),
        "proc": proc,
        "session": session,
    }
    _deadline = deadline - CHECK_SPARE_S
    try:
        checked_ok = find_checked_snapshot(given, seen)
        given["body"] = render_own(marker)
    finally:
        _deadline = deadline
    if not checked_ok:
        say(*get_clear_output(marker, given["body"], None))
        return True
    lock, reason = get_taken_lock(True, _deadline - LOCK_SPARE_S)
    if lock is None:
        say(*get_clear_output(marker, given["body"], get_snapshot_mark(given["snapshot"], given["states"], proc)))
        seen.update(reader="not-recorded", reason=reason)
        return True
    try:
        return set_given_locked(given, seen)
    finally:
        os.close(lock)


def set_unlisted_reader(key, proc):
    state, readers, note = get_mark_file(key)
    if state == "unreadable":
        return "unreadable"
    left = get_others(readers, proc)
    if state != "ok" or len(left) == len(readers):
        return None
    path = get_mark_path(key)
    tmp = None
    try:
        if not left:
            os.remove(path)
            return None
        tmp = create_temp_file(get_mark_bytes(note, left))
        set_replaced(tmp, path)
    except (OSError, ValueError):
        remove_temps([(tmp, path)] if tmp else [])
        return "write"

    return None


def set_reads_keys(proc, keys):
    path = get_reads_path(proc)
    tmp = None
    try:
        if not keys:
            os.remove(path)
            return None
        tmp = create_temp_file(get_reads_bytes(proc, keys))
        set_replaced(tmp, path)
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        remove_temps([(tmp, path)] if tmp else [])
        return "write"

    return None


def set_unlisted_files(proc, keep):
    state, keys = get_reads_file(proc)
    if state == "unreadable":
        return 0, "unreadable"
    left, cleared, error = [], 0, None
    for key in keys:
        failure = None if key in keep else set_unlisted_reader(key, proc)
        if key in keep or failure:
            left.append(key)
        else:
            cleared += 1
        error = failure or error
    if state != "ok" or left != keys:
        error = set_reads_keys(proc, left) or error

    return cleared, error


def set_unlisted_keys(proc, keep):
    kind = get_taken_kind()
    if kind == "absent":
        return 0, None
    if kind != "folder":
        return 0, "taken-not-folder"
    if not os.path.lexists(get_reads_path(proc)):
        return 0, None
    lock, reason = get_taken_lock(False, time.monotonic() + UNLIST_LOCK_S)
    if lock is None:
        return 0, reason
    try:
        return set_unlisted_files(proc, keep)
    finally:
        os.close(lock)


def set_unlisted(
    proc,
    reals,
    seen,
):
    keep = {get_note_key(real) for real in reals}
    try:
        cleared, error = set_unlisted_keys(proc, keep)
    except Exception as failure:
        cleared, error = 0, type(failure).__name__
    seen["cleared"] = cleared
    if error:
        seen["clear_error"] = error


def get_plain(text):
    return "".join(ch for ch in text if unicodedata.category(ch) not in CONTROL)


def is_indexable(name):
    return not any(ch in "<>/" for ch in name) and get_plain(name) == name


def is_regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except (OSError, ValueError):
        return False


def get_index_wait():
    if testing() and os.environ.get("HANDOFF_TEST_INDEX_WAIT"):
        return float(os.environ["HANDOFF_TEST_INDEX_WAIT"])
    return INDEX_LOCK_S


def try_lock(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return False

    return True


def get_index_lock(folder):
    if fcntl is None:
        return None, "no file locking here"
    digest = hashlib.sha256(os.fsencode(folder)).hexdigest()[:PROJECT_FOLDER_LENGTH]
    path = os.path.join(state_dir(), f"index-{digest}.lock")
    try:
        fd = os.open(
            path,
            os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
            0o600,
        )
    except OSError as error:
        return None, f"lock cannot be opened: {error.strerror or error}"
    wait_until = time.monotonic() + get_index_wait()
    while not try_lock(fd):
        if time.monotonic() >= wait_until:
            os.close(fd)
            return None, "lock busy"
        time.sleep(0.05)

    return fd, None


def get_regular_bytes(fd, limit):
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        return None, "is not a regular file"
    data = b""
    while len(data) <= limit:
        chunk = os.read(fd, limit + 1 - len(data))
        if not chunk:
            break
        data += chunk
    if len(data) > limit:
        return None, f"is larger than {limit // 1024} KB"

    return data, None


def get_small_text(path, limit):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        return None, f"cannot be read: {error.strerror or error}"
    try:
        data, error = get_regular_bytes(fd, limit)
    except OSError as error:
        return None, f"cannot be read: {error.strerror or error}"
    finally:
        os.close(fd)
    if error:
        return None, error
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError:
        return None, "is not UTF-8"


def get_index_text(path):
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return "", None
    except OSError as error:
        return None, f"{INDEX_NAME} cannot be read: {error.strerror or error}"
    if stat.S_ISLNK(info.st_mode):
        return None, f"{INDEX_NAME} is a link"
    text, error = get_small_text(path, INDEX_SIZE_LIMIT)
    if error:
        return None, f"{INDEX_NAME} {error}"
    if text.split("\n", 1)[0] != INDEX_HEADER:
        return None, f"{INDEX_NAME} has another first line, so the plugin did not write it"

    return text, None


def is_same_file(a, b):
    try:
        return os.path.samestat(os.stat(a), os.stat(b))
    except (OSError, ValueError):
        return False


def is_kept_entry(
    match,
    folder,
    name,
    now,
):
    other = match.group("name")
    try:
        saved = datetime.strptime(match.group("saved"), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return False

    return (
        other.endswith(".md")
        and not is_same_file(os.path.join(folder, other), os.path.join(folder, name))
        and is_indexable(other)
        and not is_service_name(other)
        and now - saved <= MAX_AGE
        and is_regular_file(os.path.join(folder, other))
    )


def get_index_entry(name, marker):
    topic = " ".join("".join(ch for ch in get_plain(marker["topic"]) if ch not in INDEX_TOPIC_DROP).split())

    return f"- [{topic}](<{name}>) — saved {marker['saved_at']}, folder {get_plain(marker['cwd'])}"


def set_index_file(
    folder,
    name,
    marker,
):
    path = os.path.join(folder, INDEX_NAME)
    text, error = get_index_text(path)
    if error:
        return error
    now = datetime.now(timezone.utc)
    kept = []
    for line in text.split("\n")[1:]:
        match = INDEX_LINE.fullmatch(line)
        if match and is_kept_entry(
            match,
            folder,
            name,
            now,
        ):
            kept.append(line)
    lines = [
        INDEX_HEADER,
        "",
        INDEX_ABOUT,
        "",
        get_index_entry(name, marker),
        *kept[:INDEX_ENTRY_LIMIT - 1],
    ]
    tmp = f"{path}.{os.getpid()}.tmp"
    try:
        fd = os.open(
            tmp,
            os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW,
            0o600,
        )
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        test_pause()
        os.replace(tmp, path)
    except (OSError, ValueError) as error:
        try:
            os.remove(tmp)
        except OSError:
            pass
        return f"{INDEX_NAME} cannot be written: {error}"

    return None


def get_loaded_memory(text):
    head = "\n".join(text.split("\n")[:MEMORY_LOADED_LINES])
    cut = cap_utf16(head, MEMORY_LOADED_UNITS)
    if cut == head:
        return head
    end = cut.rfind("\n")

    return cut[:end] if end > 0 else cut


def is_index_link(line):
    return line.startswith("- [") and (
        "](resume-index.md)" in line
        or "](<resume-index.md>)" in line
    )


def create_memory_file(path):
    try:
        fd = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(MEMORY_LINE + "\n")
    except OSError as error:
        return f"not checked: {error.strerror or error}"

    return "created with the index line"


def is_still_empty(fd):
    info = os.fstat(fd)

    return stat.S_ISREG(info.st_mode) and info.st_size == 0


def set_empty_memory_file(path):
    try:
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        return f"not checked: {error.strerror or error}"
    try:
        if not is_still_empty(fd):
            return f"not checked: {MEMORY_NAME} changed while it was checked"
        os.write(fd, (MEMORY_LINE + "\n").encode("utf-8"))
    except OSError as error:
        return f"not checked: {error.strerror or error}"
    finally:
        os.close(fd)

    return "was empty, the index line written"


def find_memory_line(path):
    text, error = get_small_text(path, MEMORY_SIZE_LIMIT)
    if error:
        return f"not checked: {MEMORY_NAME} {error}"
    if any(is_index_link(line) for line in get_loaded_memory(text).split("\n")):
        return "has the index line"

    return f"add the index line: insert it with Edit before the current first line: {MEMORY_LINE}"


def set_memory_line(folder):
    path = os.path.join(folder, MEMORY_NAME)
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return create_memory_file(path)
    except OSError as error:
        return f"not checked: {error.strerror or error}"
    if stat.S_ISLNK(info.st_mode):
        return f"not checked: {MEMORY_NAME} is a link"
    if not stat.S_ISREG(info.st_mode):
        return f"not checked: {MEMORY_NAME} is not a regular file"
    if info.st_size == 0:
        return set_empty_memory_file(path)

    return find_memory_line(path)


def set_index(note, marker):
    real = os.path.realpath(note)
    if not in_memory(real):
        reason = "the memory folder is a link" if note_in_memory(note) is not None else "note not in Claude Code's memory"
        return [f"index: none ({reason})"]
    folder, name = os.path.dirname(real), os.path.basename(real)
    if not is_indexable(name):
        return ["index not updated: note name cannot be indexed", MEMORY_SKIPPED]
    lock, error = get_index_lock(folder)
    if error:
        return [f"index not updated: {error}", MEMORY_SKIPPED]
    try:
        error = set_index_file(
            folder,
            name,
            marker,
        )
        if error:
            return [f"index not updated: {error}", MEMORY_SKIPPED]
        return ["index: updated", f"MEMORY.md: {set_memory_line(folder)}"]
    finally:
        os.close(lock)


def cmd_save(args):
    proc = claude_process()
    if not proc:
        print("handoff: no Claude process above this command — marker not written")
        return 1
    pid, started = proc
    cwd = find_work_folder(args.cwd, proc)
    if not enabled(cwd):
        print(f"handoff is off for {cwd} — marker not written")
        return 0
    given = os.path.normpath(os.path.abspath(os.path.expanduser(args.note)))
    note = allowed_note(given, cwd)
    if note is None:
        own = os.path.join(get_notes_root(), get_project_folder(cwd))
        print(f"handoff: the note must be a file {own}/<name>.md (the folder `where` prints) or "
              f"<Claude config>/projects/<folder>/memory/<name>.md, and {given} is not; marker not written")
        return 1
    text = read_regular(note, SOURCE_SIZE_LIMIT)
    if text is None:
        print(f"handoff: could not read the note {note}")
        return 1
    marker = {
        "pid": pid,
        "started": started,
        "cwd": cwd,
        "note": note,
        "topic": " ".join(args.topic.split())[:TOPIC_LIMIT],
        "saved_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    path = os.path.join(state_dir(), marker_file(pid, started))
    tmp = f"{path}.{os.getpid()}.tmp"
    try:
        os.makedirs(state_dir(), exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(marker, f, ensure_ascii=False, indent=1)
        test_pause()
        os.replace(tmp, path)
    except (OSError, ValueError) as error:
        try:
            os.remove(tmp)
        except OSError:
            pass
        print(f"handoff: marker not written: {error}")
        return 1
    retired = 0
    expired = 0
    now = datetime.now(timezone.utc)
    for other in load_markers():
        if other["_path"] == path:
            continue
        when = saved_time(other)
        old = when is not None and now - when > MAX_AGE
        if not (old or same_path(other["note"], note)) or liveness(other) != "closed":
            continue
        try:
            os.remove(other["_path"])
        except OSError:
            continue
        if old:
            expired += 1
        else:
            retired += 1
        try:
            os.remove(handed_file(other))
        except OSError:
            pass
    print(f"marker: {path}")
    if retired:
        print(f"removed markers of closed sessions with the same note: {retired}")
    if expired:
        print(f"removed markers of closed sessions saved more than 30 days ago: {expired}")
    print("\n".join(set_index(note, marker)))
    problems = checked(text, cwd, os.path.realpath(note))
    if problems:
        print("not verified in the note:")
        print("\n".join(problem_lines(problems)))
    else:
        print("quotes and numbers: all verified")
    return 0


def create_notes_folder(cwd):
    root = get_notes_root()
    path = os.path.join(root, get_project_folder(cwd))
    try:
        os.makedirs(root, 0o700, exist_ok=True)
        os.makedirs(path, 0o700, exist_ok=True)
    except OSError as error:
        return None, f"handoff: could not create the notes folder {path}: {error}"

    return path, None


def cmd_where(args):
    cwd = find_work_folder(args.cwd, None if args.cwd else claude_process())
    path, error = create_notes_folder(cwd)
    if error:
        print(error)
        return 1
    print(path)

    return 0


def find_memory_folder(given):
    if not usable(given):
        return None, f"handoff: {given!r} is not an existing memory folder — no note created"
    folder = os.path.expanduser(given)
    if not is_memory_folder(folder):
        return None, (f"handoff: {given!r} is not an existing memory folder: its real path "
                      f"{os.path.realpath(folder)} is not an existing folder {memory_root()}/<project>/memory "
                      f"— no note created")

    return folder, None


def create_note(folder, slug):
    for number in range(1, NAME_TRIES + 1):
        name = f"resume-{slug}.md" if number == 1 else f"resume-{slug}-{number}.md"
        path = os.path.join(folder, name)
        if os.path.lexists(path):
            continue
        test_pause()
        try:
            fd = os.open(
                path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
            )
            os.close(fd)
        except FileExistsError:
            continue
        except OSError as error:
            return None, f"handoff: could not create the note {path}: {error}"
        return path, None

    return None, f"handoff: resume-{slug}.md and -2 to -{NAME_TRIES} are all taken in {folder} — no note created"


def is_good_slug(slug):
    return (
        SLUG.fullmatch(slug) is not None
        and len(slug) <= SLUG_LIMIT
        and slug != "index"
    )


def cmd_new(args):
    if not is_good_slug(args.slug):
        print(f"handoff: the slug must be lowercase latin letters and digits, words joined by single hyphens, "
              f"up to {SLUG_LIMIT} characters, and not \"index\"; {args.slug!r} is not — no note created")
        return 1
    cwd = find_work_folder(args.cwd, None if args.cwd else claude_process())
    if args.memory is None:
        folder, error = create_notes_folder(cwd)
    else:
        folder, error = find_memory_folder(args.memory)
    if error:
        print(error)
        return 1
    path, error = create_note(folder, args.slug)
    if error:
        print(error)
        return 1
    if allowed_note(path, cwd) != os.path.realpath(path):
        try:
            os.remove(path)
            removed = "removed"
        except OSError as error:
            removed = f"not removed: {error.strerror or error}"
        print(f"handoff: the created note {path} did not pass the note check — {removed}; no note created")
        return 1
    print(path)

    return 0


def cmd_check(args):
    note = os.path.realpath(os.path.expanduser(args.note))
    text = read_regular(note, SOURCE_SIZE_LIMIT)
    if text is None:
        print(f"handoff: could not read {args.note}")
        return 1
    problems = checked(text, os.path.realpath(os.path.expanduser(args.cwd or os.getcwd())), note)
    if not problems:
        print("quotes and numbers: all verified")
        return 0
    print("\n".join(problem_lines(problems)))
    return 1


def run_took():
    began = time.monotonic()
    seen = {}
    try:
        cmd_took(seen)
    except Exception as error:
        seen.update(outcome="error", error=type(error).__name__, message=clip(str(error)))
    finally:
        if seen.get("outcome"):
            write_trace(dict({"command": "took"}, **seen), began)

    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog="handoff.py")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("start")
    commands.add_parser("took")
    save = commands.add_parser("save")
    save.add_argument("--note", required=True)
    save.add_argument("--topic", required=True)
    save.add_argument("--cwd")
    check = commands.add_parser("check")
    check.add_argument("note")
    check.add_argument("--cwd")
    where = commands.add_parser("where")
    where.add_argument("--cwd")
    new = commands.add_parser("new")
    new.add_argument("--slug", required=True)
    new.add_argument("--memory")
    new.add_argument("--cwd")
    args = parser.parse_args(argv)
    if args.command == "start":
        began = time.monotonic()
        seen = {}
        try:
            return cmd_start(seen)
        except Exception as error:
            seen.update(outcome="error", error=type(error).__name__, message=clip(str(error)))
            tell_failure(type(error).__name__)
            return 0
        finally:
            if _check_errors:
                seen["check_error"] = ",".join(sorted(set(_check_errors)))
            write_trace(seen, began)
    if args.command == "took":
        return run_took()
    if args.command == "save":
        return cmd_save(args)
    if args.command == "where":
        return cmd_where(args)
    if args.command == "new":
        return cmd_new(args)
    return cmd_check(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
