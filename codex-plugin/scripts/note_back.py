#!/usr/bin/env python3
"""Hands the resume note back to a Codex session after Codex compacted its context window.

Runs on SessionStart with the source compact (the matcher in hooks.json; the source is checked here too).
With the session's note, $TMPDIR/hats-codex-notes/<session id>.md (hats_codex.py), the hook returns it as
hookSpecificOutput.additionalContext, which Codex puts into the window as a developer message, and the turn
goes on by itself. Without it, the text says that no note was found. Either way one line goes to the
journal, and the warning of window.py is armed again for the session. The note is read only from a notes
folder that belongs to this user with mode 700 (hats_codex.get_notes), and never through a link; a refused
folder counts as no note and goes to the journal as notes-folder-refused. A note longer than 24 000 characters is cut at that length, and the text says so.

It never fails a turn: bad input or any error leaves it silent with exit code 0 and a journal line.
"""
import json
import os
import stat
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hats_codex as hats

SCRIPT = "note_back"
NOTE_LIMIT = 24000


def read_note(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        data = os.read(fd, NOTE_LIMIT * 4 + 4)
    finally:
        os.close(fd)
    text = data.decode("utf-8", errors="replace").strip()
    return text or None


def get_text(path, note):
    if note is None:
        return (
            "Hats: Codex compacted this session's context window, and no resume note was found for this session "
            "at %s. Go on with the task from the summary above." % path
        )
    cut = len(note) > NOTE_LIMIT
    body = note[:NOTE_LIMIT] + ("\n\n[cut at %d characters]" % NOTE_LIMIT if cut else "")
    return (
        "Hats handoff: Codex compacted this session's context window. Below is the resume note this session "
        "wrote before the compaction, kept at %s. Go on with the task from where the note says it stands, and "
        "keep the note up to date when asked.\n\n%s" % (path, body)
    )


def run(data):
    session = data.get("session_id")
    if data.get("hook_event_name") != "SessionStart" or data.get("source") != "compact":
        return None
    if not hats.is_session(session):
        hats.journal(SCRIPT, "SessionStart", "bad-session")
        return None
    path = hats.get_note_path(session)
    notes = hats.get_notes(create=False)
    if notes is None and os.path.lexists(hats.get_notes_folder()):
        hats.journal(SCRIPT, "SessionStart", "notes-folder-refused")
    note = read_note(os.path.join(notes, session + ".md")) if notes is not None else None
    if notes is not None:
        hats.write_whole(notes, session + ".state.json", {"announced": False})
    hats.journal(SCRIPT, "SessionStart", "handed-back" if note is not None else "no-note",
                 characters=len(note) if note is not None else 0)
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": get_text(path, note)}}


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
        if not isinstance(data, dict):
            return 0
        out = run(data)
        if out is not None:
            sys.stdout.write(json.dumps(out) + "\n")
    except Exception as error:
        hats.journal(SCRIPT, "SessionStart", "failed", error=type(error).__name__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
