"""Helpers that several plugin scripts share, kept in one place so a fix reaches every script.

unattended: the session has no person — CLAUDE_CODE_SESSION_ATTENDED=0, else, when that variable
is not set, CLAUDE_CODE_ENTRYPOINT starting with sdk.
write_whole: writes a JSON record whole — a temporary .tmp-*.json beside the target, mode 600, then
os.replace; the temporary file is removed when the write fails. before_replace, when given, is
called between the write and os.replace: stop-snapshot.py pauses there in its tests.
"""
import json
import os
import tempfile


def unattended():
    attended = os.environ.get("CLAUDE_CODE_SESSION_ATTENDED")
    if attended is not None:
        return attended.strip() == "0"
    return os.environ.get("CLAUDE_CODE_ENTRYPOINT", "").startswith("sdk")


def write_whole(
    folder,
    name,
    record,
    before_replace=None,
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
