#!/usr/bin/env python3
"""How full a Codex session's context window is, and the request for a resume note before Codex compacts it.

Runs on UserPromptSubmit and Stop. The fill is the input of the session's last answer over the model's
window, both from the last token_count event with usage in the session file (transcript_path on the hook's
input): last_token_usage.input_tokens / model_context_window. It lags one answer behind, since the file
gets an answer's count only after the answer; that is why the request comes at the start of a turn and
not after each tool call. The file is read from its end, at most its last 16 MiB.

Thresholds: warn_percent and save_percent of window-thresholds.json in the Hats folder (hats_codex.py),
60 and 70 without a usable file. Hats asks Codex to compact at the save threshold through the
model_auto_compact_token_limit line in ~/.codex/config.toml, where it can; the texts do not promise it.

On UserPromptSubmit, at or past the warning threshold, the hook adds a text for the model
(hookSpecificOutput.additionalContext): on the first turn of an arming, to write the note to
$TMPDIR/hats-codex-notes/<session id>.md and tell the user so in one line; while the note has not been
written in this arming — its file is missing, or unchanged since that first request, as a note left by an
earlier arming is — the same request again on the next turns, at most LOUD_LIMIT requests in all, so a
turn cut short before the note does not cost the user the line; on every other turn, to update the note
without telling the user — also when the note is still not written after the limit, which goes to the
journal as note-missing. Below the warning threshold, and after a compaction (note_back.py), the warning
is armed again and the count starts over. The state lives beside the note, <session id>.state.json
({"announced": bool, "loud": the loud requests given in this arming, "before": the note's st_mtime_ns at
the first request, or null without a note}); a state written by an earlier version counts one loud
request when announced and has no "before", so the note as it is now becomes the one to change.
With either threshold off (null) the hook asks for nothing: without a save threshold Codex does not
compact by Hats' line, and without a warning threshold there is no point at which to ask.

On both events, when the Hats folder exists, the hook writes <Hats folder>/codex-windows/<session id>.json
(session, window, tokens, percent, end_percent, cwd, event, written_at; mode 600, whole or not at all), from
which Hats takes the model window and, by event "Stop", sees that the session ended a turn. end_percent is
the fill after the last answer, last_token_usage.total_tokens / model_context_window (input and output), or
null without a usable total: the answer is in the window when the next request goes out, and Codex
compacts by its line before any request whose input would pass it, so a turn can end past the save
threshold only by its last answer, which percent does not count yet; a failed
write goes to the journal as window-not-recorded and the hook goes on. On Stop it removes such files
older than 30 days and temporary files older than 10 minutes, and in the notes folder notes, state files
and temporary files older than 30 days.

It never fails a turn: bad input, a session file without a usable token_count, an unexpected session id
or any error leaves it silent with exit code 0; errors and requests go to the journal (hats_codex.py).
"""
import json
import os
import re
import stat
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hats_codex as hats

SCRIPT = "window"
BLOCK = 1 << 20
READ_LIMIT = 16 << 20
MAX_AGE_S = 30 * 24 * 3600
TEMPORARY_AGE_S = 10 * 60
OWN_FILE = re.compile(r"[A-Za-z0-9-]{1,80}\.json")
LEFT_TEMPORARY = re.compile(r"\.tmp-[A-Za-z0-9_-]{1,64}\.json")
NOTES_FILE = re.compile(r"(?:[A-Za-z0-9-]{1,80}\.(?:md|state\.json)|\.tmp-[A-Za-z0-9_-]{1,64}\.(?:json|log))")
CWD_LIMIT = 1024
LOUD_LIMIT = 3


def get_count(line):
    if b'"token_count"' not in line:
        return None
    try:
        payload = json.loads(line.decode("utf-8")).get("payload")
    except (ValueError, AttributeError):
        return None
    if not isinstance(payload, dict) or payload.get("type") != "token_count":
        return None
    info = payload.get("info")
    if not isinstance(info, dict):
        return None
    last = info.get("last_token_usage")
    tokens = last.get("input_tokens") if isinstance(last, dict) else None
    window = info.get("model_context_window")
    if type(tokens) is not int or type(window) is not int or tokens < 0 or window <= 0:
        return None
    total = last.get("total_tokens")
    if type(total) is not int or total < tokens:
        total = None
    return tokens, window, total


def find_last_count(path):
    """(tokens, window, total or None) of the last usable token_count in the last 16 MiB of the file, block by block."""
    if not isinstance(path, str) or not path:
        return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    with os.fdopen(fd, "rb") as f:
        info = os.fstat(f.fileno())
        if not stat.S_ISREG(info.st_mode):
            return None
        end = info.st_size
        floor = max(0, end - READ_LIMIT)
        carry = b""
        while end > floor:
            start = max(floor, end - BLOCK)
            f.seek(start)
            lines = (f.read(end - start) + carry).split(b"\n")
            carry = lines.pop(0) if start > 0 else b""
            for line in reversed(lines):
                found = get_count(line)
                if found is not None:
                    return found
            end = start
    return None


def is_swept(name, info, now):
    if OWN_FILE.fullmatch(name):
        return now - info.st_mtime > MAX_AGE_S
    return bool(LEFT_TEMPORARY.fullmatch(name)) and now - info.st_mtime > TEMPORARY_AGE_S


def sweep(folder, is_old):
    now = time.time()
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        try:
            info = os.lstat(path)
            if stat.S_ISREG(info.st_mode) and is_old(name, info, now):
                os.unlink(path)
        except OSError:
            continue


def is_old_note(name, info, now):
    return bool(NOTES_FILE.fullmatch(name)) and now - info.st_mtime > MAX_AGE_S


def record_window(data, session, reading):
    root = hats.get_existing_hats_root()
    if root is None:
        return
    folder = hats.get_folder(os.path.join(root, hats.WINDOWS_FOLDER))
    if folder is None:
        return
    tokens, window, percent, end_percent = reading
    cwd = data.get("cwd")
    hats.write_whole(folder, session + ".json", {
        "session": session,
        "window": window,
        "tokens": tokens,
        "percent": percent,
        "end_percent": end_percent,
        "cwd": cwd[:CWD_LIMIT] if isinstance(cwd, str) else None,
        "event": data.get("hook_event_name"),
        "written_at": hats.get_now_stamp(),
    })
    if data.get("hook_event_name") == "Stop":
        sweep(folder, is_swept)


def get_first_request(path, percent, save):
    return (
        "Hats: this Codex session's context window is %d%% full. Codex compacts the window later; Hats asks it "
        "to do that at %d%% where it can. Before anything else in this turn, write a resume note to the file %s "
        "with your shell tool: what the user asked for, what you are doing now, the decisions made, the files "
        "touched, and the next step. Then tell the user in one line that you saved a resume note to %s, and go "
        "on with the user's request. After the compaction this note is handed back to you."
        % (percent, save, path, path)
    )


def get_update_request(path, percent, save):
    return (
        "Hats: this Codex session's context window is %d%% full. Codex compacts the window later; Hats asks it "
        "to do that at %d%% where it can. Before anything else in this turn, update the resume note in %s (write "
        "it if it is missing) so that it says where the work stands now: what you are doing, the decisions "
        "made, the files touched, and the next step. Do not tell the user about it; go on with the user's "
        "request." % (percent, save, path)
    )


def get_loud_count(state):
    loud = state.get("loud")
    if type(loud) is int and loud >= 0:
        return loud

    return 1 if state.get("announced") is True else 0


def get_mtime(path):
    try:
        return os.stat(path).st_mtime_ns
    except (OSError, ValueError):
        return None


def get_before(state, loud, now):
    if loud == 0 or "before" not in state:
        return now
    before = state.get("before")

    return before if type(before) is int else None


def ask(session, percent, save):
    notes = hats.get_notes(create=True)
    if notes is None:
        hats.journal(SCRIPT, "UserPromptSubmit", "notes-folder-refused")
        return None
    state = hats.read_json(os.path.join(notes, session + ".state.json")) or {}
    note = os.path.join(notes, session + ".md")
    loud = get_loud_count(state)
    now = get_mtime(note)
    before = get_before(state, loud, now)
    is_written = now is not None and now != before
    is_loud = loud == 0 or (loud < LOUD_LIMIT and not is_written)
    hats.write_whole(notes, session + ".state.json", {
        "announced": True,
        "percent": percent,
        "loud": loud + 1 if is_loud else loud,
        "before": before,
    })
    if is_loud:
        hats.journal(SCRIPT, "UserPromptSubmit", "asked-to-write", percent=percent, attempt=loud + 1)
        text = get_first_request(note, percent, save)
    else:
        if not is_written:
            hats.journal(SCRIPT, "UserPromptSubmit", "note-missing", percent=percent)
        hats.journal(SCRIPT, "UserPromptSubmit", "asked-to-update", percent=percent)
        text = get_update_request(note, percent, save)
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}}


def rearm(session):
    notes = hats.get_notes(create=False)
    if notes is None:
        return
    state = hats.read_json(os.path.join(notes, session + ".state.json"))
    if state is None or state.get("announced") is not True:
        return
    hats.write_whole(notes, session + ".state.json", {"announced": False, "loud": 0})


def run(data):
    session = data.get("session_id")
    event = data.get("hook_event_name")
    if not hats.is_session(session) or event not in ("UserPromptSubmit", "Stop"):
        return None
    if event == "Stop":
        notes = hats.get_notes(create=False)
        if notes is not None:
            sweep(notes, is_old_note)
    found = find_last_count(data.get("transcript_path"))
    if found is None:
        return None
    tokens, window, total = found
    percent = tokens * 100 // window
    end_percent = None if total is None else total * 100 // window
    try:
        record_window(data, session, (tokens, window, percent, end_percent))
    except OSError as error:
        hats.journal(SCRIPT, event, "window-not-recorded", error=type(error).__name__)
    warn, save, origin = hats.get_thresholds()
    if origin.startswith("unreadable"):
        hats.journal(SCRIPT, event, "thresholds-unreadable", reason=origin)
    if warn is None or save is None:
        return None
    if percent < warn:
        rearm(session)
        return None
    if event != "UserPromptSubmit":
        return None
    return ask(session, percent, save)


def main():
    event = None
    try:
        data = json.loads(sys.stdin.read() or "{}")
        if not isinstance(data, dict):
            return 0
        hats.set_journal_session(data.get("session_id"))
        event = data.get("hook_event_name")
        out = run(data)
        if out is not None:
            sys.stdout.write(json.dumps(out) + "\n")
    except Exception as error:
        hats.journal(SCRIPT, event, "failed", error=type(error).__name__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
