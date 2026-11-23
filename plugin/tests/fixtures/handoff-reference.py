#!/usr/bin/env python3
"""Hand a session's resume note to the next session: a save request leaves a marker for this
Claude process, and the SessionStart hook gives the note back after /clear, or lists the notes
of closed sessions when a new session starts in the same folder.

  handoff.py start                      SessionStart hook (matcher startup|clear), stdin = hook input
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
$CLAUDE_CONFIG_DIR or else ~/.claude; old markers and notes written there are still accepted. The
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
current (verification 2026-11-11).

The check: a number taken from another file goes into the note only inside a quote
`(cite: <path>:<line> "exact text")`, with «», "" or “” as the quote marks, compared with that
line of a regular file at number boundaries; a quote of the note itself, of Claude's memory or of
any file in the notes folder is not a source. `N of M (P%)` is recomputed on every line. A figure read off a command carries
`(cmd: <command>)` in the same clause. A percent, "N percent", `N of M` or `N/M` outside all
three — inline code included, fenced code not — is reported as not verified; a `(cite:` that does
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

Every `start` run appends one JSON line to `runs.log` beside the markers: time, how long it took,
source, session, folder, Claude process and the decision — `off`, `bad-input`, `skipped`,
`no-process`, `no-own-marker`, `handed-elsewhere`, `gave-note` (receiver `new`, `same` or `none`),
`no-closed`, `listed`, `error`. A run that prints nothing leaves nothing in the transcript
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

HANDOFF_OFF=1 silences the hook. With HANDOFF_TEST=1, HANDOFF_PROCESS=<pid>:<start> stands in
for the claude process and HANDOFF_TEST_BUDGET for the time budget.
"""
import argparse
import hashlib
import json
import os
import re
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
ALL_VERIFIED = "quotes and numbers: all verified"
NOTHING_CHECKED = "quotes and numbers: none outside code and the header — nothing checked"
STATE_FACT_LIMIT = 4
TIME_BUDGET_S = 3.5
CALL_TIMEOUT_S = 2.0
SOURCE_SIZE_LIMIT = 2_000_000
LINE_LENGTH_LIMIT = 5000
TOPIC_LIMIT = 120
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
FENCE = re.compile(r"^\s*```[^`]*$")
GIT_FACT = re.compile(
    r"^\s*-\s+git\s+(?P<repo>\S+)\s+(?P<ref>[A-Za-z0-9_][A-Za-z0-9._/-]*)\s+=\s+(?P<sha>[0-9a-f]{7,40})\b"
)
NOW_HEADING = re.compile(r"^##\s+(?:СЕЙЧАС\b|(?i:NOW)\s*(?:$|[—–:(,]|-\s|\d))")
MARKER_FIELDS = {"pid": int, "started": str, "cwd": str, "note": str, "topic": str, "saved_at": str}
SESSION_ID = re.compile(r"[0-9A-Za-z_-]{1,128}")

_deadline = None
_check_errors = []


def time_left(default):
    if _deadline is None:
        return default
    return max(0.0, min(default, _deadline - time.monotonic()))


def out_of_time():
    return _deadline is not None and time.monotonic() >= _deadline


def config_root():
    custom = os.environ.get("CLAUDE_CONFIG_DIR")
    if usable(custom):
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
    env = dict(os.environ, LC_ALL="C", TZ="UTC")
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


def process_start(pid):
    code, out = run(["ps", "-o", "lstart=", "-p", str(pid)], time_left(CALL_TIMEOUT_S))
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
    if not real.startswith(root):
        return False
    parts = real[len(root):].split(os.sep)
    return len(parts) == 3 and parts[1] == "memory"


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
        if not isinstance(marker, dict):
            continue
        if not all(isinstance(marker.get(k), t) and not isinstance(marker.get(k), bool)
                   for k, t in MARKER_FIELDS.items()):
            continue
        if not all(usable(marker[k]) for k in ("started", "cwd", "note")):
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
    if note_real and real == note_real:
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
    claims = 0
    cache = {}
    lines = text.split("\n")
    in_fence = False
    for i in range(body_start(lines), len(lines)):
        number = i + 1
        if out_of_time():
            problems.append((number, "check ran out of time before the end of the note"))
            break
        line = lines[i]
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if len(line) > LINE_LENGTH_LIMIT:
            problems.append((number, "line longer than 5,000 characters — not checked"))
            continue
        for match in CITE.finditer(line):
            if out_of_time():
                break
            claims += 1
            reason = verify_cite(match, base_dir, note_real, cache)
            if reason:
                problems.append((number, reason))
        rest = CITE.sub(" ", line)
        if CITE_START.search(INLINE_CODE.sub(" ", rest)):
            problems.append((number, "quote not parsed — write (cite: <path>:<line> \"<exact text>\")"))
        for match in RATIO_PERCENT.finditer(rest):
            claims += 1
            n, m = int(match.group("n")), int(match.group("m"))
            p = float(match.group("p").replace(",", "."))
            if m == 0 or abs(n * 100 / m - p) > 1:
                share = "—" if m == 0 else f"{n * 100 / m:.1f}%"
                problems.append((number, f"arithmetic: {n} of {m} is {share}, written {match.group('p')}%"))
        for clause in CLAUSE_BREAK.split(SYSTEM_SOURCE.sub("(cmd: -)", RATIO_PERCENT.sub(" ", rest))):
            if not NUMBER_CLAIM.search(clause):
                continue
            claims += 1
            if not SYSTEM_SOURCE.search(clause):
                problems.append((number, "number with no quote and no source"))
                break
    return problems, claims


def checked_counted(text, base_dir, note_real):
    try:
        return check_text(text, base_dir, note_real)
    except Exception as error:
        _check_errors.append(type(error).__name__)
        return [(None, f"note check failed ({type(error).__name__}) — check the note yourself")], 0


def checked(text, base_dir, note_real):
    return checked_counted(text, base_dir, note_real)[0]


def get_verdict_line(claims):
    return NOTHING_CHECKED if claims == 0 else ALL_VERIFIED


def problem_lines(problems):
    out = [f"- line {number}: {reason}" if number else f"- {reason}" for number, reason in problems[:PROBLEM_LIMIT]]
    if len(problems) > PROBLEM_LIMIT:
        out.append(f"- and {len(problems) - PROBLEM_LIMIT} more")
    return out


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
        local = " (local ref, no fetch)" if ref.startswith("origin/") else ""
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
            out.append(f"- git {repo} {ref} = {noted}: matches{local}")
        else:
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
        return ["origin/* refs were compared with local refs; what the server has now needs `git fetch`."]
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
    problems, claims = checked_counted(text, marker["cwd"], os.path.realpath(marker["note"]))
    if problems:
        out.append("Not verified (check against the source before relying on it):")
        out.extend(problem_lines(problems))
    else:
        out.append(get_verdict_line(claims))
    facts = state_lines(text)
    if facts:
        out.append("State compared with the system:")
        out.extend(facts)
        out.extend(fetch_hint(facts))
    return "\n".join(out)


def render_list(markers):
    out = [
        "[handoff] Sessions that already closed left notes in this folder. Do not hold up the user's "
        "request for them: do what the user asks, and in your first reply mention these notes in one "
        "short line, in the user's language, so the user can pick one. Continue a note only if the user "
        "picks it; if the user asks to continue earlier work, offer these notes and wait for the choice:"
    ]
    all_facts = []
    for index, marker in enumerate(markers, 1):
        raw = read_regular(marker["note"], SOURCE_SIZE_LIMIT)
        text = raw or ""
        out.append(f"{index}. \"{marker['topic']}\" — saved {marker['saved_at']}: {marker['note']}")
        problems, claims = checked_counted(text, marker["cwd"], os.path.realpath(marker["note"]))
        if not problems:
            if raw is not None:
                out.append(f"   {get_verdict_line(claims)}")
        elif problems[0][0] is None:
            out.append(f"   {problems[0][1]}")
        else:
            out.append(f"   unverified lines: {len(problems)}")
        facts = state_lines(text)
        all_facts.extend(facts)
        out.extend("   " + fact for fact in facts)
    out.extend(fetch_hint(all_facts))
    return "\n".join(out)


def cap_utf16(text, limit):
    encoded = text.encode("utf-16-le")
    if len(encoded) // 2 <= limit:
        return text
    return encoded[:limit * 2].decode("utf-16-le", errors="ignore")


def time_budget():
    if testing() and os.environ.get("HANDOFF_TEST_BUDGET"):
        return float(os.environ["HANDOFF_TEST_BUDGET"])
    return TIME_BUDGET_S


def test_pause():
    if testing() and os.environ.get("HANDOFF_TEST_PAUSE"):
        time.sleep(float(os.environ["HANDOFF_TEST_PAUSE"]))


def unattended():
    attended = os.environ.get("CLAUDE_CODE_SESSION_ATTENDED")
    if attended is not None:
        return attended.strip() == "0"
    return os.environ.get("CLAUDE_CODE_ENTRYPOINT", "").startswith("sdk")


def cmd_start(seen):
    global _deadline
    if os.environ.get("HANDOFF_OFF") == "1":
        seen["outcome"] = "off"
        return 0
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
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
    _deadline = time.monotonic() + time_budget()
    markers = checked_markers()
    if source == "clear":
        proc = claude_process()
        if not proc:
            seen["outcome"] = "no-process"
            return 0
        seen["pid"] = proc[0]
        own = [m for m in markers if m["pid"] == proc[0] and m["started"] == proc[1]]
        if not own:
            seen["outcome"] = "no-own-marker"
            return 0
        given = handed_session(own[0]) if session else None
        if given is not None and given != session:
            seen.update(outcome="handed-elsewhere", handed_to=clip(given))
            return 0
        sys.stdout.write(cap_utf16(render_own(own[0]), OUTPUT_LIMIT) + "\n")
        sys.stdout.flush()
        if session and given is None:
            record_handed(own[0], session)
        receiver = "none" if not session else ("new" if given is None else "same")
        seen.update(outcome="gave-note", receiver=receiver)
        return 0
    else:
        now = datetime.now(timezone.utc)
        closed = []
        for marker in markers:
            if out_of_time():
                break
            if not same_path(marker["cwd"], cwd):
                continue
            when = saved_time(marker)
            if when is None or now - when > MAX_AGE:
                continue
            if liveness(marker) != "closed":
                continue
            closed.append((when, marker))
        if not closed:
            seen["outcome"] = "no-closed"
            return 0
        closed.sort(key=lambda pair: pair[0], reverse=True)
        shown = [marker for _, marker in closed[:LIST_LIMIT]]
        text = render_list(shown)
    sys.stdout.write(cap_utf16(text, OUTPUT_LIMIT) + "\n")
    seen.update(outcome="listed", listed=len(shown))
    return 0


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
    for other in load_markers():
        if other["_path"] == path or not same_path(other["note"], note) or liveness(other) != "closed":
            continue
        try:
            os.remove(other["_path"])
            retired += 1
        except OSError:
            continue
        try:
            os.remove(handed_file(other))
        except OSError:
            pass
    print(f"marker: {path}")
    if retired:
        print(f"removed markers of closed sessions with the same note: {retired}")
    print("\n".join(set_index(note, marker)))
    problems, claims = checked_counted(text, cwd, os.path.realpath(note))
    if problems:
        print("not verified in the note:")
        print("\n".join(problem_lines(problems)))
    else:
        print(get_verdict_line(claims))
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
    problems, claims = checked_counted(text, os.path.realpath(os.path.expanduser(args.cwd or os.getcwd())), note)
    if not problems:
        print(get_verdict_line(claims))
        return 0
    print("\n".join(problem_lines(problems)))
    return 1


def main(argv):
    parser = argparse.ArgumentParser(prog="handoff.py")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("start")
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
            seen.update(outcome="error", error=type(error).__name__)
            return 0
        finally:
            if _check_errors:
                seen["check_error"] = ",".join(sorted(set(_check_errors)))
            write_trace(seen, began)
    if args.command == "save":
        return cmd_save(args)
    if args.command == "where":
        return cmd_where(args)
    if args.command == "new":
        return cmd_new(args)
    return cmd_check(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
