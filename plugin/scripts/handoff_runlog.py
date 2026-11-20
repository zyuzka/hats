"""The runs.log journal of the hook: lock, rotation and one line per run.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import os
import time
from datetime import datetime, timezone

from handoff_clock import test_pause
from handoff_consts import TRACE_LIMIT, TRACE_LOCK_S
from handoff_files import fcntl
from handoff_paths import state_dir


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
