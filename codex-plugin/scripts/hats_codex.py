"""Shared parts of the Codex hooks of Hats: folders, thresholds, the note path, files written whole, the journal.

The Hats folder is $HATS_STATE_HOME when it is an absolute path without a null byte, as written (no ~ is
expanded), ~/Library/Application Support/Hats when it is empty or not set — the folder Hats calls
StateDirectory.url — and none at all for any other value, a relative path included. This is the rule of
get_state_root in the Claude plugin's hats_common.py; the Codex plugin has its own folder, so this module
holds its own copy, and window-fill.test.sh checks both copies against one table. The hooks never create
the Hats folder: where Hats never ran, or where there is none, the hooks still work with the thresholds 60
and 70, but write no window file for Hats and no journal line into it.

The notes folder is $TMPDIR/hats-codex-notes (/tmp when TMPDIR is not set): a folder the Codex sandbox may
write to by default, so the model can write the note with its shell tool. Per session it holds the note,
<session id>.md, and the state of the warning, <session id>.state.json. It is used only when it belongs to
this user and has mode 700 (get_notes).

The journal is one JSON line per hook outcome, in codex-hooks.log of the Hats folder, else in hooks.log of
the notes folder; past 256 KiB it keeps its last 500 lines. A line carries "session", the session id of the
hook's input, once the hook has read an input whose session_id is a valid id (set_journal_session), so the
lines of one session can be counted apart from another's; bad input leaves it out.
"""
import json
import os
import re
import stat
import tempfile
import time

SESSION = re.compile(r"[A-Za-z0-9-]{1,80}")
THRESHOLDS_FILE = "window-thresholds.json"
WINDOWS_FOLDER = "codex-windows"
NOTES_FOLDER = "hats-codex-notes"
JOURNAL_IN_HATS = "codex-hooks.log"
JOURNAL_IN_NOTES = "hooks.log"
JOURNAL_LIMIT = 256 * 1024
JOURNAL_KEPT = 500
JOURNAL_SESSION = {"session": None}
THRESHOLDS_LIMIT = 64 * 1024
DEFAULT_WARN = 60
DEFAULT_SAVE = 70
WARN_RANGE = range(10, 95)
SAVE_RANGE = range(11, 96)


def get_hats_root():
    custom = os.environ.get("HATS_STATE_HOME", "")
    if not custom:
        return os.path.join(os.path.expanduser("~"), "Library", "Application Support", "Hats")
    if "\x00" in custom or not os.path.isabs(custom):
        return None
    return custom


def get_existing_hats_root():
    root = get_hats_root()
    return root if root is not None and os.path.isdir(root) else None


def get_notes_folder():
    return os.path.join(os.environ.get("TMPDIR") or "/tmp", NOTES_FOLDER)


def get_note_path(session):
    return os.path.join(get_notes_folder(), session + ".md")


def get_notes(create):
    """The notes folder when it is this user's own folder with mode 700, else None.

    With create, a missing folder is made with mode 700 first. A link, a folder of another user or a
    folder others may enter is refused, because with TMPDIR unset the folder sits in the shared /tmp,
    where another user could plant a note for a session.
    """
    path = get_notes_folder()
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        if not create:
            return None
        try:
            os.mkdir(path, 0o700)
        except FileExistsError:
            pass
        try:
            info = os.lstat(path)
        except OSError:
            return None
    except OSError:
        return None
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        return None
    return path


def is_session(value):
    return isinstance(value, str) and SESSION.fullmatch(value) is not None


def get_folder(path):
    """The folder at path, made with mode 700 when missing; None when it is a link or not a folder."""
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        try:
            os.mkdir(path, 0o700)
        except FileExistsError:
            pass
        info = os.lstat(path)
    return path if stat.S_ISDIR(info.st_mode) else None


def get_now_stamp():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def is_threshold(value, allowed):
    return value is None or (type(value) is int and value in allowed)


def get_thresholds():
    """(warn, save, origin): from window-thresholds.json of the Hats folder, 60 and 70 without a usable one.

    origin is "default" without the file, "file" when it was used, and "unreadable: <what>" when it was not:
    the caller records that reason, so a fall back to 60 and 70 is never silent.
    """
    root = get_hats_root()
    if root is None:
        return DEFAULT_WARN, DEFAULT_SAVE, "default"
    path = os.path.join(root, THRESHOLDS_FILE)
    if not os.path.lexists(path):
        return DEFAULT_WARN, DEFAULT_SAVE, "default"
    data = read_json(path, THRESHOLDS_LIMIT)
    if data is None:
        return DEFAULT_WARN, DEFAULT_SAVE, "unreadable: not a JSON object in a regular file"
    warn = data.get("warn_percent", DEFAULT_WARN)
    save = data.get("save_percent", DEFAULT_SAVE)
    if not is_threshold(warn, WARN_RANGE):
        return DEFAULT_WARN, DEFAULT_SAVE, f"unreadable: warn_percent={json.dumps(warn)}"
    if not is_threshold(save, SAVE_RANGE):
        return DEFAULT_WARN, DEFAULT_SAVE, f"unreadable: save_percent={json.dumps(save)}"
    if warn is not None and save is not None and warn >= save:
        return DEFAULT_WARN, DEFAULT_SAVE, f"unreadable: warn_percent={warn} not below save_percent={save}"
    return warn, save, "file"


def write_whole(folder, name, record):
    fd, temporary = tempfile.mkstemp(prefix=".tmp-", suffix=".json", dir=folder)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            fd = None
            json.dump(record, out, sort_keys=True)
            out.write("\n")
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


def read_json(path, limit=64 * 1024):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        data = os.read(fd, limit + 1)
    except OSError:
        return None
    finally:
        os.close(fd)
    if len(data) > limit:
        return None
    try:
        value = json.loads(data.decode("utf-8"))
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def get_journal_path():
    root = get_existing_hats_root()
    if root is not None:
        return os.path.join(root, JOURNAL_IN_HATS)
    folder = get_notes(create=False)
    return os.path.join(folder, JOURNAL_IN_NOTES) if folder is not None else None


def shorten(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size <= JOURNAL_LIMIT:
            return
        with os.fdopen(fd, "r", encoding="utf-8", errors="replace") as f:
            fd = None
            kept = f.read().splitlines()[-JOURNAL_KEPT:]
    finally:
        if fd is not None:
            os.close(fd)
    folder = os.path.dirname(path)
    handle, temporary = tempfile.mkstemp(prefix=".tmp-", suffix=".log", dir=folder)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write("\n".join(kept) + "\n")
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def set_journal_session(value):
    JOURNAL_SESSION["session"] = value if is_session(value) else None


def journal(script, event, outcome, **details):
    try:
        path = get_journal_path()
        if path is None:
            return
        record = {"at": get_now_stamp(), "script": script, "event": event, "outcome": outcome}
        if JOURNAL_SESSION["session"] is not None:
            record["session"] = JOURNAL_SESSION["session"]
        record.update(details)
        line = json.dumps(record, sort_keys=True, ensure_ascii=False) + "\n"
        try:
            shorten(path)
        except OSError:
            pass
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass
