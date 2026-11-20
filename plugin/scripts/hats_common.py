"""Helpers that several plugin scripts share, kept in one place so a fix reaches every script.

unattended: the session has no person — CLAUDE_CODE_SESSION_ATTENDED=0, else, when that variable
is not set, CLAUDE_CODE_ENTRYPOINT starting with sdk.
write_text_whole: writes a text file whole — a temporary .tmp-*<suffix> beside the target, mode 600,
then os.replace; the temporary file is removed when the write fails, and the error goes up to the
caller. before_replace, when given, is called between the write and os.replace: the tests pause
there. The suffix is ".tmp" by default, so a reader that takes only *.json from the folder never
reads a half-written file.
write_whole: a JSON record through write_text_whole with the suffix ".json" (sorted keys, one
line, a newline at the end) — the files of window-fill.py and stop-snapshot.py, whose sweeps know
the name .tmp-*.json.
record_failure: one JSON line {"at", "script", "event", "error"} — the time in UTC, the script, the
hook event and the type of the exception — appended to failures.log in the given folder, mode 600.
It is for an error nobody expected: a skip the script describes (bad input, no root, a subagent, a
session without a person) is not one. It opens the log with O_APPEND, O_NOFOLLOW and O_NONBLOCK, so a
link or a pipe in its place is not followed and does not hang the hook; over 64 KiB the log first
moves to failures.log.1. It never raises and never prints: the hook must not fall over its own log.
"""
import json
import os
import stat
import tempfile
import time

FAILURE_LOG = "failures.log"
FAILURE_LOG_LIMIT = 64 * 1024
FAILURE_FIELD_LIMIT = 80


def unattended():
    attended = os.environ.get("CLAUDE_CODE_SESSION_ATTENDED")
    if attended is not None:
        return attended.strip() == "0"
    return os.environ.get("CLAUDE_CODE_ENTRYPOINT", "").startswith("sdk")


def write_text_whole(
    folder,
    name,
    text,
    before_replace=None,
    suffix=".tmp",
):
    fd, temporary = tempfile.mkstemp(
        prefix=".tmp-",
        suffix=suffix,
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
            out.write(text)
        if before_replace is not None:
            before_replace()
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


def write_whole(
    folder,
    name,
    record,
    before_replace=None,
):
    write_text_whole(
        folder,
        name,
        json.dumps(record, sort_keys=True) + "\n",
        before_replace=before_replace,
        suffix=".json",
    )


def get_field(value):
    return value[:FAILURE_FIELD_LIMIT] if isinstance(value, str) else None


def rotate_failures(path):
    try:
        info = os.lstat(path)
    except OSError:
        return
    if stat.S_ISREG(info.st_mode) and info.st_size > FAILURE_LOG_LIMIT:
        try:
            os.replace(path, path + ".1")
        except OSError:
            pass


def record_failure(
    folder,
    script,
    event,
    error,
):
    try:
        line = json.dumps(
            {
                "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "script": get_field(script),
                "event": get_field(event),
                "error": type(error).__name__,
            },
            sort_keys=True,
        ) + "\n"
        path = os.path.join(folder, FAILURE_LOG)
        rotate_failures(path)
        fd = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK,
            0o600,
        )
        try:
            if stat.S_ISREG(os.fstat(fd).st_mode):
                os.write(fd, line.encode("utf-8"))
        finally:
            os.close(fd)
    except Exception:
        pass
