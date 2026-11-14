#!/usr/bin/env python3
"""UserPromptSubmit reminder: once the anchor skill has run in this session, every later prompt
carries one line telling the session to call the skill again if that prompt is the anchor command — in
any language. The session, not a word list, decides whether the prompt is that command. Never blocks.

Why: measured 2026-11-11 over 399 transcripts since 2026-11-02, on save-state, the personal save skill
anchor was taken from — the first save request in a session called the skill 39 of 43 times (all four
misses false or deferred), a repeated one 0 of 3. A repeated save follows the copy loaded at the first
call, so a skill changed in between runs in its old form: a session in another project had loaded
save-state on 10.11, before step 6 (the handoff marker) existed, saved again on 11.11 without it, and the
handoff trial there found no marker. Compaction is not the cause: in 3 of 3 compactions after a skill
call Claude Code re-attached the skill in full.

Language: the user's words are never matched — the tool is used in more languages than Russian (user,
2026-11-11). The signal is the session's own transcript: a Skill call of anchor (with or without this
plugin's prefix, hats:anchor; another plugin's anchor is not this skill), or /hats:anchor typed by the
user — Claude Code writes a typed skill
command as `"content":"<command-message>NAME</command-message>\\n<command-name>/NAME</command-name>` at
the start of the message (52 typed /loop and /bmad-build by 2026-11-11), unescaped. The same pair quoted
inside a longer text does not count; a text field that itself begins with exactly this pair would. A
call of another save skill, save-state included, is not anchor and leaves the prompt alone: requests to
save in other words belong to that skill, not to this plugin. The line is English so it reads the same
for everyone; the session still answers in the user's language.

Cost, measured on save-state: of 48 sessions that called the skill by 2026-11-11, 45 had no prompt
after it and three had 2, 3 and 5 — 10 extra lines in all.

A prompt that is itself the command /hats:anchor, after any leading spaces and with or without
arguments, gets no reminder: the command has already loaded the skill's current text. The plugin's
own mod runs that command at its threshold, and Claude Code hands this hook exactly "/hats:anchor"
then; with the reminder there, the session would call the skill again through the Skill tool, which
in the default permission mode asks the user first (measured 2026-11-14, Claude Code 2.1.325: three
automatic anchors with the reminder silent called no Skill and asked nothing about it).

Every reminder leaves one row in <config>/state/anchor-nudge.tsv, where <config> is $CLAUDE_CONFIG_DIR
or else ~/.claude: UTC time, session id, "reminded". Never the prompt text. Past 256 000 bytes the log
moves to anchor-nudge.tsv.1 before the next row. A failed write does not stop the reminder.
"""
import json
import mmap
import os
import re
import sys
from datetime import datetime, timezone

SAVED = re.compile(
    rb'"name":"Skill","input":\{"skill":"(?:hats:)?anchor"'
    rb'|"(?:content|text)":"<command-message>(?:hats:)?anchor</command-message>'
    rb'\\n<command-name>/(?:hats:)?anchor</command-name>'
)
REMINDER = (
    "The anchor skill (hats:anchor) already ran in this session. If this message is the anchor "
    "command on its own, in any language (for example «анкор», \"anchor\", «якорь»), or asks whether "
    "the session was anchored, call the anchor skill again with the Skill tool and follow its current "
    "text, not the copy loaded earlier: that copy may be outdated and miss a step. A request to save "
    "in other words is not this command. Otherwise ignore this note."
)
COMMAND = re.compile(r"\s*/hats:anchor(?:\s.*)?", re.S)
LOG = "anchor-nudge.tsv"
LOG_LIMIT = 256_000


def saved_before(transcript):
    try:
        with open(transcript, "rb") as f:
            if os.fstat(f.fileno()).st_size == 0:
                return False
            with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as view:
                return SAVED.search(view) is not None
    except (OSError, ValueError):
        return False


def get_config_root():
    custom = os.environ.get("CLAUDE_CONFIG_DIR")
    if custom:
        return os.path.expanduser(custom)

    return os.path.join(os.path.expanduser("~"), ".claude")


def log_row(session):
    try:
        state = os.path.join(get_config_root(), "state")
        os.makedirs(state, exist_ok=True)
        clean = "".join(ch for ch in str(session) if ch.isalnum() or ch in "-_")[:80] or "-"
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        log = os.path.join(state, LOG)
        if os.path.isfile(log) and os.path.getsize(log) > LOG_LIMIT:
            os.replace(log, log + ".1")
        with open(log, "a", encoding="utf-8") as f:
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
    prompt = data.get("prompt")
    if isinstance(prompt, str) and COMMAND.fullmatch(prompt):
        return 0
    transcript = data.get("transcript_path")
    if not isinstance(transcript, str) or not transcript or not saved_before(transcript):
        return 0
    log_row(data.get("session_id", ""))
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": REMINDER}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
