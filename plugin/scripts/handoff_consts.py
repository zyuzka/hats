"""The limits, patterns and fixed texts of handoff.py.

Part of handoff.py, which holds the contract of the whole hook."""
import re
from datetime import timedelta

HEAD_LIMIT = 6500
OUTPUT_LIMIT = 9500
LIST_LIMIT = 5
MAX_AGE = timedelta(days=30)
PROBLEM_LIMIT = 10
STATE_FACT_LIMIT = 4
TIME_BUDGET_S = 3.5
CALL_TIMEOUT_S = 2.0
REAP_TIMEOUT_S = 0.5
SOURCE_SIZE_LIMIT = 2_000_000
LINE_LENGTH_LIMIT = 5000
TOPIC_LIMIT = 120
USER_LINE_LIMIT = 2000
USER_LINE_START = "Hats handoff:"
ANCESTOR_LIMIT = 8
TRACE_LIMIT = 256_000
TRACE_FIELD_LIMIT = 500
TRACE_LOCK_S = 0.5
NOTES_NAME = "notes"
PROJECT_NAME = re.compile(r"[0-9a-f]{16}")
ALLOW_TOOLS = {
    "Write",
    "Edit",
    "Read",
}
WRITE_TOOLS = {
    "Write",
    "Edit",
}
ALLOW_REASON = "Hats handoff: a resume note in the Hats notes folder"
PROJECT_FOLDER_LENGTH = 16
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
SLUG_LIMIT = 60
NAME_TRIES = 99
INDEX_NAME = "resume-index.md"
MEMORY_NAME = "MEMORY.md"
SERVICE_NAMES = {
    "resume-index.md",
    "memory.md",
}
INDEX_HEADER = "# Resume index — written by the Hats plugin; do not edit"
INDEX_ABOUT = (
    "One line per saved session, newest first. A session may still be working on a task listed here: "
    "ask the user before continuing one."
)
INDEX_LINE = re.compile(
    r"- \[(?P<topic>[^\[\]()<>`]*)\]\(<(?P<name>[^<>/\n]+)>\) — saved "
    r"(?P<saved>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ), folder (?P<folder>.*)"
)
INDEX_TOPIC_DROP = "[]()<>`"
INDEX_ENTRY_LIMIT = 20
INDEX_SIZE_LIMIT = 64 * 1024
INDEX_LOCK_S = 10.0
MEMORY_LINE = (
    "- [Resume index](resume-index.md) — sessions saved for the next one; "
    "read it when the user asks to continue earlier work"
)
MEMORY_SIZE_LIMIT = 100 * 1024
MEMORY_LOADED_LINES = 200
MEMORY_LOADED_UNITS = 25_000
MEMORY_SKIPPED = "MEMORY.md: not checked: index not updated"
CONTROL = {
    "Cc",
    "Cf",
    "Cs",
    "Zl",
    "Zp",
}
USER_LINE_CONTROL = {
    "Cc",
    "Cs",
    "Zl",
    "Zp",
}

CITE = re.compile(
    r"\((?:(?i:cite):|цит\.)\s+(?P<path>[^«»“”\"()\n]{1,300}?):(?P<line>\d{1,7})\s+"
    r"(?:«(?P<t1>[^»\n]{1,500})»|“(?P<t2>[^”\n]{1,500})”|\"(?P<t3>[^\n]{1,500}?)\")\)"
)
CITE_START = re.compile(r"\((?:(?i:cite):|цит\.)")
INLINE_CODE = re.compile(r"`[^`\n]*`")
SYSTEM_SOURCE = re.compile(r"\((?:(?i:cmd)|система):\s*[^)\n]{1,300}\)")
RATIO_PERCENT = re.compile(r"(?<!\d)(?P<n>\d+)\s+(?:of|из)\s+(?P<m>\d+)\D{0,6}?(?P<p>\d+(?:[.,]\d+)?)\s?%")
NUMBER_CLAIM = re.compile(
    r"(?<!\d)\d+(?:[.,]\d+)?\s?(?:%|percent|процент)|(?<!\d)\d+\s+(?:of|из)\s+\d+|(?<![\w/.])\d+\s?/\s?\d+(?![\w/])",
    re.IGNORECASE,
)
CLAUSE_BREAK = re.compile(r";|\||\s—\s|\.\s|,\s|\sи\s|\sand\s")
FENCE = re.compile(r"^\s*(?P<fence>`{3,}(?=[^`]*$)|~{3,})(?P<info>.*)$")
GIT_FACT = re.compile(
    r"^\s*-\s+git\s+(?P<repo>\S+)\s+(?P<ref>[A-Za-z0-9_][A-Za-z0-9._/-]*)\s+=\s+(?P<sha>[0-9a-f]{7,40})\b"
)
NOW_HEADING = re.compile(r"^##\s+(?:СЕЙЧАС\b|(?i:NOW)\s*(?:$|[—–:(,]|-\s|\d))")
MARKER_FIELDS = {"pid": int, "started": str, "cwd": str, "note": str, "topic": str, "saved_at": str}
SESSION_ID = re.compile(r"[0-9A-Za-z_-]{1,128}")
TOOK_BUDGET_S = 1.5
CHECK_SPARE_S = 0.3
LOCK_SPARE_S = 0.1
PRINT_LIMIT_S = 0.3
MARKS_SPARE_S = 0.2
UNLIST_LOCK_S = 0.5
LOCK_STEP_S = 0.01
TAKEN_FOLDER = "taken"
TAKEN_LOCK = ".lock"
TAKEN_LIMIT = 64 * 1024
MARKER_LIMIT = 64 * 1024
READER_LIMIT = 100
READS_KEY_LIMIT = 500
MARK_LIST_LIMIT = 600
NOTE_KEY = re.compile(r"[0-9a-f]{64}")
STAMP = "%Y-%m-%dT%H:%M:%SZ"
TOOK_ASK = "Another session may be continuing this task: continue it only if the user confirms."
OWN_LIMIT = OUTPUT_LIMIT - MARK_LIST_LIMIT - len(f"[handoff] . {TOOK_ASK}\n")
CUT_LINE = "[… cut, the rest is in the file]"
UNREADABLE_NOTE = "could not read the note"
ALL_VERIFIED = "quotes and numbers: all verified"
NOTHING_CHECKED = "quotes and numbers: none outside code and the header — nothing checked"
AUTHOR_WORDS = "the session that saved this note is still open: "
LSTART = "%a %b %d %H:%M:%S %Y"
LIST_ASK = "If the user picks it, say so and continue only if the user confirms."
TOOK_WORDS = (
    "{} other live session(s) reading this note: ",
    "could not check {} other session(s) that read this note: ",
)
MARK_WORDS = (
    "{} live session(s) reading it: ",
    "could not check {} session(s) that read it: ",
)
MORE_WORDS = "; could not check {} more: "
UNREADABLE_MARK = "could not check whether another session is reading it"
MARK_INDENT = "   "
