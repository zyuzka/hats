#!/usr/bin/env python3
"""The background work and wake-ups of a Claude Code session at the end of its turn, written for the mod.

Runs on Stop through `py.sh --quiet`, synchronously (no "async"): Claude Code waits for it before
the turn goes on or ends, so the snapshot of an early Stop is written before any work the model
starts after it. It never prints and exits 0 on any failure without writing. The whole run is cut
at 3.5 s, inside the 5-second timeout of the hook.

Why a hook: `background_tasks` and `session_crons` reach only the input of a settings Stop hook; the
mod's own Stop hook does not run where Claude Code's guard is loaded. The mod reads this file before
it clears the session after an anchor on the threshold: a running work whose id the note does not
name, or a wake-up, keeps the session uncleared.

The file: <root>/stop-snapshots/<session_id>.json, where <root> is $HATS_STATE_HOME when it is set
and not empty, else ~/Library/Application Support/Hats — the root window-fill.py takes. The hook makes
only stop-snapshots (700) inside a root that already exists. Fields: session, at_ms (the time this
run started, in milliseconds), ok, tasks (records with id, type, status and description cut to 200
characters) and crons (the number of wake-ups). ok is false, with no tasks and no wake-ups, when
either field is missing, is not a list, holds more than 200 entries, or a task is not an object with
a string id and type. The file is written whole: a temporary .tmp-*.json beside it, mode 600, then
os.replace.

Not written: a subagent (agent_id on the input), a session without a person
(CLAUDE_CODE_SESSION_ATTENDED=0, else CLAUDE_CODE_ENTRYPOINT starting with sdk), bad input, a session
id that is not [A-Za-z0-9-]{1,80}, a missing root, a stop-snapshots that is a link or not a folder.
After writing, at most 50 files older than 7 days are removed from the folder, own snapshots and
temporary files left by a killed run alike.

STOP_SNAPSHOT_TEST=1 with STOP_SNAPSHOT_TEST_PAUSE=<seconds> and STOP_SNAPSHOT_TEST_MARK=<file>
marks that the temporary file is written and pauses before os.replace; tests use it to stop the hook
there. Without STOP_SNAPSHOT_TEST both are ignored.
"""
import json
import os
import re
import signal
import stat
import sys
import tempfile
import time

sys.dont_write_bytecode = True

FOLDER = "stop-snapshots"
SESSION = re.compile(r"[A-Za-z0-9-]{1,80}")
OWN_FILE = re.compile(r"[A-Za-z0-9-]{1,80}\.json")
LEFT_TEMPORARY = re.compile(r"\.tmp-[A-Za-z0-9_-]{1,64}\.json")
LIST_LIMIT = 200
DESCRIPTION_LIMIT = 200
MAX_AGE_S = 7 * 24 * 3600
SWEEP_LIMIT = 50
RUN_LIMIT_S = 3.5


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


def is_unattended():
    attended = os.environ.get("CLAUDE_CODE_SESSION_ATTENDED")
    if attended is not None:
        return attended.strip() == "0"
    return os.environ.get("CLAUDE_CODE_ENTRYPOINT", "").startswith("sdk")


def is_testing():
    return os.environ.get("STOP_SNAPSHOT_TEST") == "1"


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


def write_whole(
    folder,
    name,
    record,
):
    fd, temporary = tempfile.mkstemp(
        prefix=".tmp-",
        suffix=".json",
        dir=folder,
    )
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(
            fd,
            "w",
            encoding="utf-8",
        ) as out:
            fd = None
            json.dump(
                record,
                out,
                sort_keys=True,
            )
            out.write("\n")
        pause_for_test()
        os.replace(temporary, os.path.join(folder, name))
        temporary = None
    finally:
        if fd is not None:
            os.close(fd)
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def is_swept(
    name,
    info,
    now,
):
    if not stat.S_ISREG(info.st_mode) or now - info.st_mtime <= MAX_AGE_S:
        return False
    return bool(OWN_FILE.fullmatch(name) or LEFT_TEMPORARY.fullmatch(name))


def sweep(folder):
    now = time.time()
    removed = 0
    for name in os.listdir(folder):
        if removed >= SWEEP_LIMIT:
            return
        path = os.path.join(folder, name)
        try:
            if is_swept(name, os.lstat(path), now):
                os.unlink(path)
                removed += 1
        except OSError:
            continue


def record_snapshot(data, started_ms):
    session = data.get("session_id")
    if data.get("agent_id") is not None or is_unattended():
        return
    if not isinstance(session, str) or not SESSION.fullmatch(session):
        return
    folder = get_prepared_folder(get_state_root())
    if folder is None:
        return
    write_whole(
        folder,
        session + ".json",
        create_snapshot(
            data,
            session,
            started_ms,
        ),
    )
    sweep(folder)


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
        if isinstance(data, dict):
            record_snapshot(data, started_ms)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
