"""Text helpers: cutting, UTF-16 units, hidden characters, the shown topic.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import re
import unicodedata

from handoff_consts import CONTROL, TOPIC_LIMIT, TRACE_FIELD_LIMIT, USER_LINE_CONTROL


def clip(value):
    return value[:TRACE_FIELD_LIMIT] if isinstance(value, str) else None


def body_start(lines):
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return i + 1
    return 0


def bounded_in(want, have):
    left = ""
    if want[0].isdigit():
        left = r"(?<![\w.,\-−])"
    elif want[0].isalnum():
        left = r"(?<!\w)"
    right = r"(?!\w)(?![.,]\d)" if want[-1].isalnum() else ""
    return re.search(left + re.escape(want) + right, have) is not None


def cap_utf16(text, limit):
    encoded = text.encode("utf-16-le")
    if len(encoded) // 2 <= limit:
        return text
    return encoded[:limit * 2].decode("utf-16-le", errors="ignore")


def is_hidden_char(ch):
    code = ord(ch)
    return (
        unicodedata.category(ch) in USER_LINE_CONTROL
        or 0x202A <= code <= 0x202E
        or 0x2066 <= code <= 0x2069
    )


def get_shown(text):
    return "".join(ch for ch in text if not is_hidden_char(ch))


def get_topic(marker):
    return get_shown(marker["topic"])[:TOPIC_LIMIT]


def get_note_noun(count):
    return "note" if count == 1 else "notes"


def get_units(text):
    return len(text.encode("utf-16-le")) // 2


def get_json_bytes(data):
    return json.dumps(data, ensure_ascii=False).encode("utf-8") + b"\n"


def get_plain(text):
    return "".join(ch for ch in text if unicodedata.category(ch) not in CONTROL)


def is_indexable(name):
    return not any(ch in "<>/" for ch in name) and get_plain(name) == name
