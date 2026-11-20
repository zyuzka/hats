#!/usr/bin/env python3
"""How full the context window of a Claude Code session is, written for Hats, one file per session.

Runs on UserPromptSubmit, PostToolUse, Stop, SessionStart after a compaction and SessionEnd, in the
background ("async": true) through `py.sh --quiet`. It never blocks, never prints, and on any failure
exits 0 without writing its file. A failure nobody expected — an exception that is not one of the
skips listed below — leaves one JSON line {"at", "script", "event", "error" (the exception's type)}
in <root>/session-windows/failures.log (record_failure of hats_common.py: mode 600, not through a
link, over 64 KiB moved to failures.log.1), when that folder already exists and is not a link; bad
input is a skip and writes nothing. It does not run for an idle agent: none of these events fires without a
turn, a compaction or the session's end.

Why a hook reads the transcript: Claude Code 2.1.322 gives a hook neither the model nor the window
fill (input of a SessionStart hook, measured 2026-11-13 over three models: model None); the number
is only in the session's transcript, whose path comes on the hook's input. How it is counted lives in
window_fill_count.py beside this script; the folder of this script goes onto sys.path by hand, since
python3 -I leaves it out, and no bytecode is written into the plugin.

The file: <root>/session-windows/<session_id>.json, where <root> is $HATS_STATE_HOME when it is set
and not empty, else ~/Library/Application Support/Hats — the folder Hats calls StateDirectory.url,
the same root handoff.py takes for its notes. The hook makes only session-windows (700) inside a root
that already exists; where Hats never ran there is no root, and nothing is written. Fields: session,
cwd, title, tokens, window, percent, state ("read" or "compacted"), model, message, measured_at,
compactions, compaction, compacted_at, event, written_at. Each file is written whole or not at all (a
temporary .tmp-*.json beside it, mode 600, then os.replace). Reading the tail of the transcript and
writing the file happen under one lock, <root>/session-windows/.lock (flock, wait at most 2 s, never
removed: a removed lock file lets two hooks hold "the same" lock), so the last writer is the last
reader.

SessionEnd, whatever its reason, removes this session's own file under the lock and writes nothing:
a closed session, and the one before /clear, leaves the menu at once rather than after an hour.
SessionStart with the source compact measures as usual, so a manual /compact shows at once.

Not written: a subagent (agent_id on the input), a session without a person
(CLAUDE_CODE_SESSION_ATTENDED=0, else CLAUDE_CODE_ENTRYPOINT starting with sdk — the rule of
handoff.py), bad input, a transcript that is not a regular file or whose path leads nowhere (missing,
through a file, too long, a loop of links, a socket), a session id that is not
[A-Za-z0-9-]{1,80}, a missing root, a session-windows that is a link or not a folder, a lock busy for
2 s, a tail with no answer and no boundary. The same rules hold for SessionEnd. On Stop and
SessionEnd, under the lock, <id>.json files older than 30 days and .tmp-*.json files older than 10
minutes (left by a hook killed mid-write) are removed.

Stop waits for the turn to land before it reads: Claude Code starts the Stop hook before it appends
the turn's last answer (probe 2026-11-13, 2.1.323: that line reached the transcript 43 ms after this
hook had already written the answer before it, then stop_hook_summary and turn_duration followed), and
the Stop input carries the answer's text, not its usage. So on Stop the hook watches the transcript's
size: once it has grown and then stayed still for 0.3 s, or after 1.5 s at most, it takes the lock
and reads. Other events read at once.

`window-fill.py where` prints the folder and writes nothing (for the test that holds this path equal
to the one Hats computes). WINDOW_FILL_TEST=1 with WINDOW_FILL_TEST_PAUSE=<seconds> and
WINDOW_FILL_TEST_READ=<file> pauses between reading and writing and marks that the read is done; tests
use it to race two hooks. WINDOW_FILL_TEST=1 with WINDOW_FILL_TEST_FAIL=1 raises inside record_window
once the folder is ready, for the test of failures.log. Without WINDOW_FILL_TEST all three are
ignored.
"""
import errno
import fcntl
import json
import os
import re
import signal
import stat
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

import window_fill_count as count
from hats_common import record_failure, unattended, write_whole

FOLDER = "session-windows"
LOCK_NAME = ".lock"
SESSION = re.compile(r"[A-Za-z0-9-]{1,80}")
OWN_FILE = re.compile(r"[A-Za-z0-9-]{1,80}\.json")
LEFT_TEMPORARY = re.compile(r"\.tmp-[A-Za-z0-9_-]{1,64}\.json")
BAD_TRANSCRIPT_PATH = frozenset((
    errno.ENOENT,
    errno.ENOTDIR,
    errno.ENAMETOOLONG,
    errno.ELOOP,
    errno.ENXIO,
))
ENDED_PREFIX = ".ended-"
ENDED_FILE = re.compile(r"\.ended-[A-Za-z0-9-]{1,80}")
LOCK_WAIT_S = 2.0
LOCK_STEP_S = 0.02
SETTLE_LIMIT_S = 1.5
SETTLE_QUIET_S = 0.3
SETTLE_STEP_S = 0.05
OWN_FILE_LIMIT = 64 * 1024
MAX_AGE_S = 30 * 24 * 3600
TEMPORARY_AGE_S = 10 * 60
TITLE_LIMIT = 200
EVENT_LIMIT = 40
SWEEPING_EVENTS = {
    "Stop",
    "SessionEnd",
}
REVIVING_EVENTS = {
    "SessionStart",
    "UserPromptSubmit",
}
NOT_COMPARED = (
    "event",
    "written_at",
)


def get_state_root():
    override = os.environ.get("HATS_STATE_HOME", "")
    if override:
        return override

    return os.path.join(
        os.path.expanduser("~"),
        "Library",
        "Application Support",
        "Hats",
    )


def is_testing():
    return os.environ.get("WINDOW_FILL_TEST") == "1"


def get_own_record(path, session):
    try:
        fd, info = count.get_regular_descriptor(path, os.O_NOFOLLOW)
    except OSError:
        return {}
    if fd is None:
        return {}
    try:
        if info.st_size > OWN_FILE_LIMIT:
            return {}
        data = os.read(fd, OWN_FILE_LIMIT + 1)
    except OSError:
        return {}
    finally:
        os.close(fd)
    entry = count.get_parsed(data)
    if entry is None or entry.get("session") != session:
        return {}
    return entry


def get_prepared_folder(root):
    if not os.path.isdir(root):
        return None
    folder = os.path.join(root, FOLDER)
    try:
        info = os.lstat(folder)
    except FileNotFoundError:
        try:
            os.mkdir(folder, 0o700)
        except FileExistsError:
            pass
        info = os.lstat(folder)
    return folder if stat.S_ISDIR(info.st_mode) else None


def get_size(path):
    try:
        return os.stat(path).st_size
    except OSError:
        return None


def wait_for_the_turn(transcript):
    deadline = time.monotonic() + SETTLE_LIMIT_S
    last = get_size(transcript)
    grew_at = None
    while time.monotonic() < deadline:
        time.sleep(SETTLE_STEP_S)
        size = get_size(transcript)
        if size != last:
            last = size
            grew_at = time.monotonic()
        elif grew_at is not None and time.monotonic() - grew_at >= SETTLE_QUIET_S:
            return


def get_lock(folder):
    fd = os.open(
        os.path.join(folder, LOCK_NAME),
        os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
        0o600,
    )
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        return None
    deadline = time.monotonic() + LOCK_WAIT_S
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except OSError:
            if time.monotonic() >= deadline:
                os.close(fd)
                return None
            time.sleep(LOCK_STEP_S)


def is_swept(name, info, now):
    if stat.S_ISDIR(info.st_mode):
        return False
    if OWN_FILE.fullmatch(name):
        return now - info.st_mtime > MAX_AGE_S
    is_short_lived = LEFT_TEMPORARY.fullmatch(name) or ENDED_FILE.fullmatch(name)
    return bool(is_short_lived) and now - info.st_mtime > TEMPORARY_AGE_S


def sweep(folder):
    now = time.time()
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        try:
            if is_swept(name, os.lstat(path), now):
                os.unlink(path)
        except OSError:
            continue


def remove_own(folder, name):
    try:
        os.unlink(os.path.join(folder, name))
    except OSError:
        pass


def mark_ended(folder, session):
    try:
        fd = os.open(
            os.path.join(folder, ENDED_PREFIX + session),
            os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600,
        )
        os.close(fd)
    except OSError:
        pass


def is_same_measurement(record, old):
    return {k: v for k, v in record.items() if k not in NOT_COMPARED} == \
        {k: v for k, v in old.items() if k not in NOT_COMPARED}


def measure(
    data,
    folder,
    name,
):
    session = data["session_id"]
    old = get_own_record(os.path.join(folder, name), session)
    try:
        found = count.find_in_transcript(data["transcript_path"])
    except OSError as error:
        if error.errno not in BAD_TRANSCRIPT_PATH:
            raise
        return
    if is_testing() and os.environ.get("WINDOW_FILL_TEST_PAUSE"):
        with open(
            os.environ["WINDOW_FILL_TEST_READ"],
            "w",
            encoding="utf-8",
        ):
            pass
        time.sleep(float(os.environ["WINDOW_FILL_TEST_PAUSE"]))
    record = None if found is None else count.create_record(found, old)
    if record is None:
        return
    title = data.get("session_title")
    record["session"] = session
    record["title"] = title[:TITLE_LIMIT] if isinstance(title, str) and title.strip() \
        else count.get_text(old.get("title"))
    cwd = data.get("cwd")
    record["cwd"] = cwd if isinstance(cwd, str) and cwd else count.get_text(old.get("cwd"))
    event = data.get("hook_event_name")
    record["event"] = event[:EVENT_LIMIT] if isinstance(event, str) else None
    record["written_at"] = count.get_now_stamp()
    if not is_same_measurement(record, old):
        write_whole(
            folder,
            name,
            record,
        )


def measure_live(data, folder, session):
    if data.get("hook_event_name") in REVIVING_EVENTS:
        remove_own(folder, ENDED_PREFIX + session)
    elif os.path.lexists(os.path.join(folder, ENDED_PREFIX + session)):
        return
    measure(
        data,
        folder,
        session + ".json",
    )


def record_window(data):
    session = data.get("session_id")
    transcript = data.get("transcript_path")
    event = data.get("hook_event_name")
    if data.get("agent_id") is not None or unattended():
        return
    if not isinstance(session, str) or not SESSION.fullmatch(session):
        return
    if not isinstance(transcript, str) or not transcript or "\0" in transcript:
        return
    if event is not None and not isinstance(event, str):
        return
    folder = get_prepared_folder(get_state_root())
    if folder is None:
        return
    if is_testing() and os.environ.get("WINDOW_FILL_TEST_FAIL") == "1":
        raise RuntimeError("WINDOW_FILL_TEST_FAIL")
    if event == "Stop":
        wait_for_the_turn(transcript)
    lock = get_lock(folder)
    if lock is None:
        return
    try:
        if event == "SessionEnd":
            mark_ended(folder, session)
            remove_own(folder, session + ".json")
        else:
            measure_live(data, folder, session)
        if event in SWEEPING_EVENTS:
            sweep(folder)
    finally:
        os.close(lock)


def stop_on_term(signum, frame):
    raise SystemExit(0)


def record_hook_failure(data, error):
    try:
        folder = os.path.join(get_state_root(), FOLDER)
        if not stat.S_ISDIR(os.lstat(folder).st_mode):
            return
    except Exception:
        return
    event = data.get("hook_event_name")
    record_failure(
        folder,
        "window-fill.py",
        event,
        error,
    )


def main(argv):
    if argv[1:] == ["where"]:
        print(os.path.join(get_state_root(), FOLDER))
        return 0
    if len(argv) > 1:
        return 0
    signal.signal(signal.SIGTERM, stop_on_term)
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except (ValueError, RecursionError):
        return 0
    except Exception as error:
        record_hook_failure({}, error)
        return 0
    if not isinstance(data, dict):
        return 0
    try:
        record_window(data)
    except Exception as error:
        record_hook_failure(data, error)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
