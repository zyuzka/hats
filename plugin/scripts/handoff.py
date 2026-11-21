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
  handoff.py allow                      PreToolUse hook (matcher Write|Edit|Read): allows a call on a note
                                        of the notes folder, silent on anything else

The marker is keyed to the Claude process (pid + start time read in UTC), not to the folder:
two sessions run in one folder at once (measured 2026-11-09), and /clear keeps the process (a
session after /clear ran in the process started the day before, measured 2026-11-09). After /clear
the process alone finds the note, whatever folder the session moved to; a new session lists the
notes of closed processes launched in its folder. The hook never deletes a marker: SessionStart
can fire twice or for a session that never opens; `save` retires markers of closed processes
that point at the same note, and those saved more than 30 days ago or at an unreadable time, with
their `.handed`. After /clear a save is handed to one session: the hook records the
receiving session id beside the marker (`<marker>.handed`, keyed to the save's time and note,
so the marker itself is never rewritten under a concurrent `save`), gives the note again to that
same session and stays silent for a later session of the process until the next `save`. An input
without a usable session id gets the note and records nothing. A process whose state `ps`
cannot tell in time is treated as alive: its note is neither listed nor retired. Every external
call in the hook shares one time budget, under the hook's 5-second timeout. A call past its time
has its process group killed and its pipe closed unread: a grandchild that left the group would
hold the pipe open (31.3 s against a 3.5-second budget, measured 2026-11-20). Such a grandchild is
left running after the hook returns.

The note must sit in one of two folders: the notes folder, or Claude Code's memory. The hook prints
the note's head into the model's context, and any other path would let a marker print an arbitrary
file. `save` and the start hook check it with one function, `allowed_note` (handoff_paths.py), against
the working folder of the save (`save` its own, the hook the marker's).

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

The notes folder is the plugin's own (user, 2026-11-11 and 2026-11-12): <root>/<project>/<name>.md,
where <root> is $HATS_STATE_HOME/notes when HATS_STATE_HOME is an absolute path as written (no ~ is
expanded, as Hats itself does not), ~/Library/Application Support/Hats/notes when it is empty or not
set (user, 2026-11-19: the notes follow the Hats state folder, so a probe with a temporary state folder
writes no note into the live one), and no root at all for any other value, a relative path included
(rule "Б", 2026-11-20, get_state_root of hats_common.py, the one rule of every plugin script): then
`where` and `new` without --memory refuse with get_no_root_line of hats_common.py and exit 1, `save`
accepts only a memory note, and no note of the notes folder is recognised; <project> is the first 16
hex digits of the sha256 of the real path of the working folder, so /a/b-c and /a-b/c get different
folders. It works with Claude Code's memory switched off, survives the plugin's removal, and needs no
running Hats. `where` creates it with mode 700 (a folder that exists is left as it is) and prints it;
`where` and `save` take the working folder from one function.
The root is computed by one function, get_notes_root in handoff_paths.py, the same for `new`, `where`,
`save`, `start`, `took`,
`allow` and anchor-steps.py, and never taken from the command line or a variable of the plugin's own:
the agent writes the command. Without HATS_STATE_HOME, like any `~`, it follows HOME (the tests rely
on that), and a `save` run under another HOME or HATS_STATE_HOME is checked again by the start hook
under its own. Notes in the old folder are neither moved nor removed: with HATS_STATE_HOME set they
are no longer recognised as notes, but a quote of them still does not count as a source (below); the
same holds without a root: the default folder ~/Library/Application Support/Hats/notes still counts as
a cited notes folder (get_cited_notes_roots), so a quote of a note there is never a source. A
note there is accepted only when its real path is exactly
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
and the start hook then prints such a note into that project's session; the `allow` hook (below)
lets it do the same at any time. A quote counts as a quote of the notes folder when one of the
folders above the cited file is a notes root itself (the same file system object), so another letter
case or another path to the same disk does not make it a source.

`allow`, a PreToolUse hook on Write, Edit and Read (user decision 2026-11-20, "А"): the skill's own
rules name only ~/Library/Application Support/Hats/notes and hold only while the skill runs, so a
note in a HATS_STATE_HOME folder, and the Read of a note by the session that continues it, asked the
user. The hook prints {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision":
"allow", ...}} only when tool_input.file_path is an absolute path ending in .md whose real path ends
in .md, is not a folder, and sits directly in an existing folder named by 16 hex digits directly in
the notes root (the same file system object as the root's real path): a link out of the root, a
subfolder, `..` out, a project folder not yet created and any other file get nothing. Read is allowed
in any project folder of the root: after /clear the session continues a note of the folder where it
was saved, wherever it moved since. Write and Edit are allowed only in the project folder of the
Claude process's working folder (found as `where` finds it), and not on an existing file with more
than one hard link, which would change a file elsewhere. Any other input, a bad one, HANDOFF_OFF=1
and an error print nothing; the hook never denies, writes nothing and always exits 0. scripts/allow.sh
runs first and exits without starting Python when the input does not contain "/notes/" (a Python
start cost 111–172 ms per call), so every Read, Write and Edit of every session pays only for sh.
A deny rule of the user's settings wins over the hook's allow (measured 2026-11-20, Claude Code
2.1.328, claude -p in the default permission mode: Write(//<notes root>/**) in deny refused the Write
the hook allowed).

Environment (measured 2026-11-11): Claude Code gives hooks and Bash commands CLAUDE_PID, the pid of
its own process, so the Claude process is that ancestor whatever its binary is called; without it,
the nearest ancestor named `claude`. The process folder is read from /proc/<pid>/cwd where /proc
exists (Linux), else from lsof. Without fcntl (Windows) the run log is written without its lock. Repository
state is compared with local refs only — no fetch: a fetch runs commands from the named
repository's config and needs the network, and a failed fetch made an old origin ref read as
current (verification 2026-11-11). A fact about a remote-tracking ref (origin/ or any other remote)
says so, and so does one whose kind could not be checked in time. GIT_* variables of the environment do not reach these git calls, so GIT_DIR cannot point
the check at another repository.

The check: a number taken from another file goes into the note only inside a quote
`(cite: <path>:<line> "exact text")`, with «», "" or “” as the quote marks, compared with that
line of a regular file at number boundaries; a quote of the note itself, of Claude's memory or of
any file in the notes folder (the current root and ~/Library/Application Support/Hats/notes both) is
not a source; for a quote the note and the memory folder are matched
as file system objects, so another letter case does not make them a source (which notes `save`
accepts is unchanged). `N of M (P%)` is recomputed on every line. A figure read off a command carries
`(cmd: <command>)` in the same clause. A percent, "N percent", `N of M` or `N/M` outside all
three — inline code included, fenced code (``` or ~~~, three marks or more, closed by the same
mark at least as long) not — is reported as not verified; a code block left open is reported, since
the lines after it are not checked, and that problem comes first; a `(cite:` that does
not parse is reported too, unless it sits in inline code. Numbers written in words are not
caught, and the check cannot tell whether the words next to a quote mean what the quote says.
`check` and `save` say "quotes and numbers: all verified" only when the note made at least one claim
— a quote, an `N of M (P%)` or a number outside code, with or without its source — and none failed; a
note with no such claim (empty, only a header, numbers only in code blocks) gets "quotes and numbers:
none outside code and the header — nothing checked" instead, and `check` still exits 0: nothing to check is not an
error of the note, but it is not a verified note either.

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
anchor whose note is gone (the marker of this process is there, nothing is left at its note's path —
deleted, renamed or moved away: "anchor "<topic>" not given — its note is gone: <path>"; a note that is
there but not allowed, or behind a folder this user cannot search, still reads as no anchor saved), an
anchor already given to another session, no
Claude process found, no notes of closed sessions, notes that could not be checked in time, and an
error raised before anything was printed. A note that could
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
middle. A listed note that cannot be read (no permission, over the size limit or not a regular file)
gets the line "could not read the note: no permission, over the size limit or not a regular file"
instead of its check. After /clear the model's text stays within 9,500 UTF-16 units: the line about
other readers keeps 600 units and its request of its own, and only the excerpt of the note is cut, in
UTF-16 units at a line end when one fits, so "--- end of excerpt ---", the "Not
verified" block and the state facts come whole unless they alone pass the limit. An error line points
to `runs.log`, which holds the error's type and text. The object is written as UTF-8 bytes, so
Cyrillic is not escaped into six-character sequences and the output does
not depend on the encoding of stdout. After /clear it is written and flushed before the hand-over is
recorded, as before.

Every `start` run appends one JSON line to `runs.log` beside the markers: time, how long it took,
source, session, folder, Claude process and the decision — `off`, `bad-input`, `skipped`,
`unattended`, `no-process`, `no-own-marker`, `note-gone` (this process has a marker, but nothing is
left at its note's path), `handed-elsewhere`, `note-unreadable` (the own note
could not be read: no permission, over the size limit or not a regular file; the user gets "could not
read the note of anchor …, not given", the model nothing, and nothing is recorded, so the note is given
once it reads again; an empty note is read and given), `gave-note` (receiver `new`, `same`
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
so a line is never dropped for the lock. `save` writes its marker through a temporary file of its
own, never a shared name: with one shared name, parallel saves failed with FileNotFoundError in 14
rounds of 20. The marker, its `.handed` and the resume index are written whole by write_text_whole
(hats_common.py): a temporary `.tmp-*.tmp` beside the file, mode 600, then os.replace, the temporary
file removed when the write fails; it does not end in .json, so load_markers never reads a half-written
marker. With HANDOFF_TEST=1, HANDOFF_TEST_PAUSE=<s> widens both windows so the tests can hit them.

`save` writes a marker only where the start hook is registered: in the folder's
.claude/settings.local.json or .claude/settings.json, in <config>/settings.json, or, when these scripts
sit in a plugin (`.claude-plugin/plugin.json` two folders above handoff_markers.py), in the plugin's
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
starting the hook (python3 -I handoff.py start, its modules imported) takes a median of 130.1 ms under
/usr/bin/python3 and 64.5 ms under Homebrew's python3 (50 runs each, A/B interleaved, 2026-11-20).

The note of `took` is the file in the `note` field of any marker that passes `allowed_note` with that
marker's cwd and is the same file as the path read (os.path.samestat); a partial or an empty read
counts, and markers are not filtered by folder, age or whether their process closed (user, "4) да").
Before any marker is read, a path that is not .md, has a service name (MEMORY.md, resume-index.md, in
any case), or sits neither directly in a memory folder under <config>/projects (seen as typed, so a
memory folder that is a link counts) nor in a project folder of the notes root is not a note. Markers
are read in name order, as load_markers (handoff_markers.py) reads them, each through get_small_text
(handoff_files.py; 64 KB, O_NONBLOCK: a
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

The author of a note (user decision 2026-11-19, the variant of Codex and Mary): the process of every
marker in the note's group (its pid and started), several when several markers point at the note.
`took` checks them together with the other readers, outside the lock and with the same cache per
pid, skips this process itself, and keeps only those found alive — "could not check" says nothing
about an author — and not already named among the live readers (an author that took its own note
back after /clear is a reader, and is named once, as a reader). When one is alive, the first read of this process (the same rule as the readers'
warning: not on `again`, and again on the next read when this one was not recorded) gets a line of its
own before the readers' facts: "Hats handoff: the session that saved this note is still open: pid <pid>
(since <start>)", "pid … (since …)" joined by ", " for several, <start> the process start time as a
marker timestamp when it parses, else as ps printed it; the model gets "[handoff] <the same>." with the
readers' facts on the next line, the confirmation request once at the end. The outcome is then
`took-shared` and the runs.log line carries "authors": <N>. A marker is read only for its note and its
process: an author is not a reader and never goes into a mark file.

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
it at once, without a Read), the group, the snapshot, the readers' check and render_own
(handoff_render.py) run until 0.3 s
before the deadline; then the lock, the merge, the temporary files, one JSON with the facts in both
fields printed as `took` prints, os.replace, and only then record_handed (handoff_markers.py).
Not printed (`not-printed`):
neither reader nor hand-over; the lock not taken: printed by the snapshot, no reader. When others read
the note, the model's text starts with "[handoff] <facts>. Another session may be continuing this task:
continue it only if the user confirms." and the whole is cut to 9,500 units from the end, so the tail
of render_own suffers, not the mark; the user line gets "   <facts>" under "continuing anchor …". A
runs.log line of start adds marks, marks_dropped, marks_error, cleared and clear_error, and after
`gave-note` reader (with reason). A subagent and a session without a person record nothing and get no
line of 8c: after /clear without a person the text is that of before.

Known gaps of the marks: a file whose readers all left without /clear stays until a `took` of the same
note; the .reads of such a process stays until a `took` sees it dead; the .tmp of a killed run stays;
a process that read a note and dropped it without /clear stays a reader until it exits; the
`.tmp-*.tmp` of a run killed while it wrote a marker, a `.handed` or the index stays beside it; a memory note
behind a link, read by its real path outside <config>/projects, is not caught; cat is not caught.

HANDOFF_OFF=1 silences the hook. With HANDOFF_TEST=1, HANDOFF_PROCESS=<pid>:<start> stands in
for the claude process and HANDOFF_TEST_BUDGET for the time budget (of `took` too). HANDOFF_TEST_PAUSE
also pauses under taken/.lock before the replace, HANDOFF_TEST_TAKEN_SIGNAL=<folder> gets <pid>.waiting
before the wait for that lock and <pid>.locked once it is held, and HANDOFF_TEST_FAIL=replace makes
os.replace of the mark files fail.

This file is the entry point: the subcommands and main. The code sits beside it, one module per part:
handoff_state.py    the run state of one call: deadline, check errors, whether to tell the user, printed
handoff_consts.py   limits, patterns and fixed texts
handoff_clock.py    time left, the test switch and the test pause
handoff_text.py     cutting, UTF-16 units, hidden characters, the shown topic
handoff_files.py    small file reads, file identity and locks (fcntl, None where the system lacks it)
handoff_proc.py     commands, the Claude process and its working folder
handoff_paths.py    the notes, state and memory folders; which note paths are allowed (allowed_note)
handoff_check.py    the note check: citations, number claims, git facts, state lines
handoff_render.py   the model's text: the note's head, its excerpt, the list of closed sessions
handoff_output.py   printing the answer within the time left; the failure line
handoff_markers.py  save markers, handed files, whether the handoff is on (registered, find_plugin_hooks)
handoff_runlog.py   runs.log: lock, rotation, one line per run
handoff_marks.py    names, shapes and reads of the taken/ mark files and their readers
handoff_facts.py    who else reads a note and the lines about it
handoff_taken.py    writes in taken/: its lock, whole-file writes, the plan, the unlisting
handoff_start.py    the start hook
handoff_took.py     the took hook
handoff_index.py    resume-index.md and its line in MEMORY.md
handoff_save.py     save, check, where and new
handoff_allow.py    the allow hook
hats_common.py      get_state_root and its default, the no-root line, unattended, write_text_whole,
                    write_whole, record_failure, record_hook_failure and sweep, shared with
                    window-fill.py, stop-snapshot.py and anchor-steps.py
A copy of the hook needs all of them beside handoff.py. anchor-steps.py imports handoff.py and also
needs hats_common.py and handoff_files.py beside it.
"""
import argparse
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

import handoff_state
from handoff_allow import cmd_allow
from handoff_consts import NOW_HEADING
from handoff_output import tell_failure
from handoff_paths import get_notes_root
from handoff_proc import claude_process, find_work_folder
from handoff_runlog import write_trace
from handoff_save import cmd_check, cmd_new, cmd_save, cmd_where
from handoff_start import cmd_start
from handoff_text import clip
from handoff_took import run_took
from hats_common import unattended

__all__ = [
    "find_work_folder",
    "claude_process",
    "get_notes_root",
    "NOW_HEADING",
    "unattended",
]


def main(argv):
    parser = argparse.ArgumentParser(prog="handoff.py")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("start")
    commands.add_parser("took")
    commands.add_parser("allow")
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
            if handoff_state.check_errors:
                seen["check_error"] = ",".join(sorted(set(handoff_state.check_errors)))
            write_trace(seen, began)
    if args.command == "took":
        return run_took()
    if args.command == "allow":
        return cmd_allow()
    if args.command == "save":
        return cmd_save(args)
    if args.command == "where":
        return cmd_where(args)
    if args.command == "new":
        return cmd_new(args)
    return cmd_check(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
