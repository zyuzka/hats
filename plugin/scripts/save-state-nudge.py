#!/usr/bin/env python3
"""UserPromptSubmit reminder: once the save-state skill has run in this session, every later prompt
carries one line telling the session to call the skill again if that prompt asks to save — in any
language. The session, not a word list, decides whether the prompt is such a request. Never blocks.

Why: measured 2026-11-11 over 399 transcripts since 2026-11-02 — the first save request in a session
called the skill 39 of 43 times (all four misses false or deferred), a repeated one 0 of 3. A repeated
save follows the copy loaded at the first call, so a skill changed in between runs in its old form:
a session in another project had loaded save-state on 10.11, before step 6 (the handoff marker)
existed, saved again on 11.11 without it, and the handoff trial there found no marker. Compaction is not
the cause: in 3 of 3 compactions after a skill call Claude Code re-attached the skill in full.

Language: the user's words are never matched — the tool is used in more languages than Russian (user,
2026-11-11). The signal is the session's own transcript: a Skill call of save-state (with or without a
plugin prefix), or /save-state typed by the user — Claude Code writes a typed skill command as
`"content":"<command-message>NAME</command-message>\\n<command-name>/NAME</command-name>` at the start
of the message (52 typed /loop and /bmad-build by 2026-11-11), unescaped. The same pair quoted inside a
longer text does not count; a text field that itself begins with exactly this pair would. The line is English so
it reads the same for everyone; the session still answers in the user's language.

Cost: of 48 sessions that called the skill by 2026-11-11, 45 had no prompt after it and three had 2, 3
and 5 — 10 extra lines in all.

Every reminder leaves one row in ~/.claude/state/save-state-nudge.tsv: UTC time, session id,
"reminded". Never the prompt text. A failed write does not stop the reminder.
"""
import json
import mmap
import os
import re
import sys
from datetime import datetime, timezone

SAVED = re.compile(
    rb'"name":"Skill","input":\{"skill":"(?:[\w.-]+:)?save-state"'
    rb'|"(?:content|text)":"<command-message>(?:[\w.-]+:)?save-state</command-message>'
    rb'\\n<command-name>/(?:[\w.-]+:)?save-state</command-name>'
)
REMINDER = (
    "The save-state skill already ran in this session. If this message asks to save the session's "
    "state or asks whether it was saved, in any language, call the save-state skill again with the "
    "Skill tool and follow its current text, not the copy loaded earlier: that copy may be outdated "
    "and miss a step. Otherwise ignore this note."
)
LOG = "save-state-nudge.tsv"


def saved_before(transcript):
    try:
        with open(transcript, "rb") as f:
            if os.fstat(f.fileno()).st_size == 0:
                return False
            with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as view:
                return SAVED.search(view) is not None
    except (OSError, ValueError):
        return False


def log_row(session):
    try:
        state = os.path.join(os.path.expanduser("~"), ".claude", "state")
        os.makedirs(state, exist_ok=True)
        clean = "".join(ch for ch in str(session) if ch.isalnum() or ch in "-_")[:80] or "-"
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(os.path.join(state, LOG), "a", encoding="utf-8") as f:
            f.write(f"{stamp}\t{clean}\treminded\n")
    except OSError:
        pass


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    if not isinstance(data, dict):
        return 0
    transcript = data.get("transcript_path")
    if not isinstance(transcript, str) or not transcript or not saved_before(transcript):
        return 0
    log_row(data.get("session_id", ""))
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": REMINDER}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
