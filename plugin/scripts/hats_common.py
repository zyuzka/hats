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
get_field: a string cut to 80 characters, anything else None — the fields of a failure line.
get_state_root: the Hats folder, the one rule for every script of the plugin. An empty or unset
HATS_STATE_HOME gives ~/Library/Application Support/Hats (following HOME, the folder Hats calls
StateDirectory.url); an absolute value without a null byte gives that value as written (no ~ is
expanded, as Hats itself does not); any other value gives None: there is no root, and a caller writes
nothing rather than into the folder it was started in or into the default one.
sweep: removes from a folder the regular files whose name fully matches one of the given patterns
and whose time of change is older than the age paired with that pattern, at most limit files when a
limit is given; a file that vanishes or cannot be removed is passed over.
record_hook_failure: record_failure into <root>/<folder name>, only when that folder already exists
and is not a link; without a root it writes nothing.
"""
import json
import os
import stat
import tempfile
import time

FAILURE_LOG = "failures.log"
FAILURE_LOG_LIMIT = 64 * 1024
FAILURE_FIELD_LIMIT = 80
STATE_HOME = "HATS_STATE_HOME"


def get_state_root():
    custom = os.environ.get(STATE_HOME, "")
    if not custom:
        return os.path.join(
            os.path.expanduser("~"),
            "Library",
            "Application Support",
            "Hats",
        )
    if "\x00" in custom or not os.path.isabs(custom):
        return None

    return custom


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


def record_hook_failure(
    folder_name,
    script,
    data,
    error,
):
    try:
        root = get_state_root()
        if root is None:
            return
        folder = os.path.join(root, folder_name)
        if not stat.S_ISDIR(os.lstat(folder).st_mode):
            return
    except Exception:
        return
    record_failure(
        folder,
        script,
        data.get("hook_event_name"),
        error,
    )


def is_swept(
    name,
    info,
    now,
    ages,
):
    if not stat.S_ISREG(info.st_mode):
        return False

    return any(pattern.fullmatch(name) and now - info.st_mtime > age for pattern, age in ages)


def sweep(
    folder,
    ages,
    limit=None,
):
    now = time.time()
    removed = 0
    for name in os.listdir(folder):
        if limit is not None and removed >= limit:
            return
        path = os.path.join(folder, name)
        try:
            if is_swept(
                name,
                os.lstat(path),
                now,
                ages,
            ):
                os.unlink(path)
                removed += 1
        except OSError:
            continue
