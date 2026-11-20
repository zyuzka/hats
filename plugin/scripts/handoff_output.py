"""Printing the hook's answer within the time left, and the failure line.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import os
import select
import sys
import time

import handoff_state
from handoff_consts import PRINT_LIMIT_S, USER_LINE_LIMIT, USER_LINE_START
from handoff_runlog import trace_file
from handoff_text import cap_utf16, get_shown


def get_payload(user, model, event):
    payload = {}
    if user is not None and handoff_state.tell:
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
    data = get_payload(user, model, event)
    if data is None:
        return
    handoff_state.printed = True
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
    end = min(time.monotonic() + PRINT_LIMIT_S, handoff_state.deadline)
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
    while view:
        left = end - time.monotonic()
        if left <= 0:
            return False
        try:
            count = os.write(fd, view)
        except BlockingIOError:
            select.select([], [fd], [], left)
            continue
        handoff_state.printed = True
        view = view[count:]

    return True


def tell_failure(kind):
    if handoff_state.printed:
        return
    try:
        say(f"{USER_LINE_START} failed ({kind}), see {get_shown(trace_file())}", None)
    except Exception:
        pass
