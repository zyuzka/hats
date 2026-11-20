#!/usr/bin/env python3
"""The background work and wake-ups of a Claude Code session at the end of its turn, written for the mod.

Runs on Stop through `py.sh --quiet`, synchronously (no "async"): Claude Code waits for it before
the turn goes on or ends, so the snapshot of an early Stop is written before any work the model
starts after it. It never prints and exits 0 on any failure without writing its snapshot. A failure
nobody expected — an exception that is not one of the skips listed below — leaves one JSON line
{"at", "script", "event", "error" (the exception's type)} in <root>/stop-snapshots/failures.log
(record_failure of hats_common.py: mode 600, not through a link, over 64 KiB moved to
failures.log.1), when that folder already exists and is not a link; bad input is a skip and writes
nothing. The whole run is cut
at 3.5 s, inside the 5-second timeout of the hook.

Why a hook: `background_tasks` and `session_crons` reach only the input of a settings Stop hook; the
mod's own Stop hook does not run where Claude Code's guard is loaded. The mod reads this file before
it clears the session after an anchor on the threshold: a running work whose id the note does not
name, or a wake-up, keeps the session uncleared.

The file: <root>/stop-snapshots/<session_id>.json, where <root> is get_state_root of hats_common.py,
the root window-fill.py takes: $HATS_STATE_HOME when it is an absolute path, ~/Library/Application
Support/Hats when it is empty or not set, and no root at all for any other value, a relative path
included: then nothing is written. The hook makes
only stop-snapshots (700) inside a root that already exists. Fields: session, at_ms (the time this
run started, in milliseconds), ok, tasks (records with id, type, status and description cut to 200
characters) and crons (the number of wake-ups). ok is false, with no tasks and no wake-ups, when
either field is missing, is not a list, holds more than 200 entries, or a task is not an object with
a string id and type. The file is written whole: a temporary .tmp-*.json beside it, mode 600, then
os.replace.

Not written: a subagent (agent_id on the input), a session without a person
(CLAUDE_CODE_SESSION_ATTENDED=0, else CLAUDE_CODE_ENTRYPOINT starting with sdk), bad input, a session
id that is not [A-Za-z0-9-]{1,80}, a missing root or none at all, a stop-snapshots that is a link or not a folder.
After writing, sweep of hats_common.py removes from the folder at most 50 regular files older than 7
days, own snapshots and temporary files left by a killed run alike.

STOP_SNAPSHOT_TEST=1 with STOP_SNAPSHOT_TEST_PAUSE=<seconds> and STOP_SNAPSHOT_TEST_MARK=<file>
marks that the temporary file is written and pauses before os.replace; tests use it to stop the hook
there. STOP_SNAPSHOT_TEST=1 with STOP_SNAPSHOT_TEST_FAIL=1 raises inside record_snapshot once the
folder is ready, for the test of failures.log. Without STOP_SNAPSHOT_TEST all three are ignored.
"""
import json
import os
import re
import signal
import stat
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from hats_common import get_state_root, record_hook_failure, sweep, unattended, write_whole

FOLDER = "stop-snapshots"
SESSION = re.compile(r"[A-Za-z0-9-]{1,80}")
OWN_FILE = re.compile(r"[A-Za-z0-9-]{1,80}\.json")
LEFT_TEMPORARY = re.compile(r"\.tmp-[A-Za-z0-9_-]{1,64}\.json")
LIST_LIMIT = 200
DESCRIPTION_LIMIT = 200
MAX_AGE_S = 7 * 24 * 3600
SWEEP_LIMIT = 50
RUN_LIMIT_S = 3.5
SWEPT_AGES = (
    (
        OWN_FILE,
        MAX_AGE_S,
    ),
    (
        LEFT_TEMPORARY,
        MAX_AGE_S,
    ),
)


def is_testing():
    return os.environ.get("STOP_SNAPSHOT_TEST") == "1"


def get_prepared_folder(root):
    if root is None or not os.path.isdir(root):
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


def is_short_list(value):
    return isinstance(value, list) and len(value) <= LIST_LIMIT


def is_task(value):
    return isinstance(value, dict) and isinstance(value.get("id"), str) and isinstance(value.get("type"), str)


def get_text(value):
    return value if isinstance(value, str) else ""


def get_task(task):
    return {
        "id": task["id"],
        "type": task["type"],
        "status": get_text(task.get("status")),
        "description": get_text(task.get("description"))[:DESCRIPTION_LIMIT],
    }


def create_snapshot(
    data,
    session,
    started_ms,
):
    record = {
        "session": session,
        "at_ms": started_ms,
        "ok": False,
        "tasks": [],
        "crons": 0,
    }
    tasks = data.get("background_tasks")
    crons = data.get("session_crons")
    if not is_short_list(tasks) or not is_short_list(crons) or not all(is_task(task) for task in tasks):
        return record
    record["ok"] = True
    record["tasks"] = [get_task(task) for task in tasks]
    record["crons"] = len(crons)
    return record


def pause_for_test():
    if not is_testing() or not os.environ.get("STOP_SNAPSHOT_TEST_PAUSE"):
        return
    mark = os.environ.get("STOP_SNAPSHOT_TEST_MARK")
    if mark:
        with open(
            mark,
            "w",
            encoding="utf-8",
        ):
            pass
    time.sleep(float(os.environ["STOP_SNAPSHOT_TEST_PAUSE"]))


def record_snapshot(data, started_ms):
    session = data.get("session_id")
    if data.get("agent_id") is not None or unattended():
        return
    if not isinstance(session, str) or not SESSION.fullmatch(session):
        return
    folder = get_prepared_folder(get_state_root())
    if folder is None:
        return
    if is_testing() and os.environ.get("STOP_SNAPSHOT_TEST_FAIL") == "1":
        raise RuntimeError("STOP_SNAPSHOT_TEST_FAIL")
    write_whole(
        folder,
        session + ".json",
        create_snapshot(
            data,
            session,
            started_ms,
        ),
        before_replace=pause_for_test,
    )
    sweep(
        folder,
        SWEPT_AGES,
        SWEEP_LIMIT,
    )


def stop_now(signum, frame):
    raise SystemExit(0)


def main(argv):
    started_ms = int(time.time() * 1000)
    if len(argv) > 1:
        return 0
    signal.signal(signal.SIGTERM, stop_now)
    signal.signal(signal.SIGALRM, stop_now)
    signal.setitimer(signal.ITIMER_REAL, RUN_LIMIT_S)
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except (ValueError, RecursionError):
        return 0
    except Exception as error:
        record_hook_failure(
            FOLDER,
            "stop-snapshot.py",
            {},
            error,
        )
        return 0
    if not isinstance(data, dict):
        return 0
    try:
        record_snapshot(data, started_ms)
    except Exception as error:
        record_hook_failure(
            FOLDER,
            "stop-snapshot.py",
            data,
            error,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
