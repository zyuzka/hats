"""The window fill of one transcript, counted the way Claude Code's status line counts it.

Imported by window-fill.py from the same folder; it reads a transcript and builds the record, and
writes nothing.

The number is the one Claude Code's status line shows (2.1.322): the usage of the last answer (eF —
an assistant line with usage, not a synthetic text first, model not <synthetic>, isUnmetered not
true); when that usage carries iterations and its top-level sum is not zero, the last iteration that
is neither advisor_message nor compaction, if it is a message or fallback_message with four finite
non-negative numbers and a positive input sum (Bce); tokens = input + cache creation + cache read,
and percent = Math.round(tokens / window * 100) held in 0..100 (sHr). The lines of one answer share
its message.id and usage, so an answer split over several lines counts once. An iteration whose type
is not a string is neither skipped nor counted, as in Bce: the top-level numbers stand.

The window is not guessed. A transcript names the API model (claude-opus-5-5) even when the settings
say opus[1m], so a 1M window is known only for models that have no other: claude-fable-*,
claude-opus-4-7..9 and claude-{opus,sonnet,haiku,mythos}-5 give 1 000 000 (200 000 under
CLAUDE_CODE_DISABLE_1M_CONTEXT), claude-3-* and claude-haiku-4-* give 200 000. Any other model, and
any model while CLAUDE_CODE_MAX_CONTEXT_TOKENS is set, leaves window and percent empty; tokens stay.

Compaction: a compact_boundary after the last answer (without one, an isCompactSummary line) makes
the state "compacted" with no numbers — the number before it is wrong until the next answer. The last
compact_boundary read, wherever it stands, counts once by its uuid: compactions + 1, compaction = its
uuid, compacted_at = its time; the count survives later writes.

The tail starts at 256 KB from the end and doubles up to 8 MB.
"""
import json
import math
import os
import re
import stat
from datetime import datetime, timezone

TAIL_START = 256 * 1024
TAIL_LIMIT = 8 * 1024 * 1024
READ_STEP = 1024 * 1024
SYNTHETIC_MODEL = "<synthetic>"
SYNTHETIC_TEXTS = {
    "[Request interrupted by user]",
    "[Request interrupted by user for tool use]",
    "The user doesn't want to take this action right now. STOP what you are doing and wait for the "
    "user to tell you how to proceed.",
    "The user doesn't want to proceed with this tool use. The tool use was rejected (eg. if it was a "
    "file edit, the new_string was NOT written to the file). STOP what you are doing and wait for the "
    "user to tell you how to proceed.",
    "No response requested.",
}
NOT_COUNTED_ITERATIONS = {
    "advisor_message",
    "compaction",
}
COUNTED_ITERATIONS = {
    "message",
    "fallback_message",
}
MILLION = 1_000_000
TWO_HUNDRED_THOUSAND = 200_000
MILLION_MODELS = re.compile(r"claude-(?:fable-.+|opus-4-[789](?:-.*)?|(?:opus|sonnet|haiku|mythos)-5(?:-.*)?)")
SMALL_MODELS = re.compile(r"claude-(?:3-.+|haiku-4-.+)")
TRUTHY = {
    "1",
    "true",
    "yes",
    "on",
}
STAMP = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z")
CARRIED_ON_SAME_ANSWER = (
    "measured_at",
)
USAGE_KEYS = (
    "input_tokens",
    "output_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)


def get_now_stamp():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def is_truthy(value):
    return isinstance(value, str) and value.strip().lower() in TRUTHY


def get_whole(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value >= 0 else None
    if isinstance(value, float) and math.isfinite(value) and value >= 0 and value.is_integer():
        return int(value)
    return None


def get_window(model):
    if os.environ.get("CLAUDE_CODE_MAX_CONTEXT_TOKENS", "").strip():
        return None
    if not isinstance(model, str):
        return None
    if MILLION_MODELS.fullmatch(model):
        return TWO_HUNDRED_THOUSAND if is_truthy(os.environ.get("CLAUDE_CODE_DISABLE_1M_CONTEXT")) else MILLION
    if SMALL_MODELS.fullmatch(model):
        return TWO_HUNDRED_THOUSAND
    return None


def get_percent(tokens, window):
    share = tokens / window * 100
    floor = math.floor(share)
    rounded = floor + 1 if share - floor >= 0.5 else floor

    return min(100, max(0, rounded))


def get_iteration_type(item):
    kind = item.get("type") if isinstance(item, dict) else None
    return kind if isinstance(kind, str) else None


def is_counted_iteration(item):
    if get_iteration_type(item) not in COUNTED_ITERATIONS:
        return False
    numbers = [get_whole(item.get(key)) for key in USAGE_KEYS]
    if any(number is None for number in numbers):
        return False
    return numbers[0] + numbers[2] + numbers[3] > 0


def get_input_sum(source):
    return (get_whole(source.get("input_tokens")) + get_whole(source.get("cache_creation_input_tokens"))
            + get_whole(source.get("cache_read_input_tokens")))


def get_window_tokens(usage):
    top = {}
    for key in USAGE_KEYS:
        value = usage.get(key)
        top[key] = 0 if value is None else get_whole(value)
        if top[key] is None:
            return None
    tokens = get_input_sum(top)
    iterations = usage.get("iterations")
    if tokens == 0 or not isinstance(iterations, list):
        return tokens
    last = None
    for item in reversed(iterations):
        if get_iteration_type(item) not in NOT_COUNTED_ITERATIONS:
            last = item
            break
    if not is_counted_iteration(last):
        return tokens

    return get_input_sum(last)


def find_answer_usage(entry):
    if not isinstance(entry, dict) or entry.get("type") != "assistant":
        return None
    message = entry.get("message")
    if not isinstance(message, dict) or "usage" not in message:
        return None
    content = message.get("content")
    first = content[0] if isinstance(content, list) and content else None
    if isinstance(first, dict) and first.get("type") == "text":
        text = first.get("text")
        if isinstance(text, str) and text in SYNTHETIC_TEXTS:
            return None
    if message.get("model") == SYNTHETIC_MODEL or entry.get("isUnmetered") is True:
        return None
    usage = message["usage"]

    return usage if isinstance(usage, dict) else None


def is_boundary(entry):
    return isinstance(entry, dict) and entry.get("type") == "system" and entry.get("subtype") == "compact_boundary"


def is_summary(entry):
    return isinstance(entry, dict) and entry.get("isCompactSummary") is True


def get_parsed(line):
    try:
        entry = json.loads(line)
    except ValueError:
        return None
    return entry if isinstance(entry, dict) else None


def find_last_parts(lines):
    answer = boundary = summary = None
    for index in reversed(range(len(lines))):
        line = lines[index]
        if answer is None and b'"assistant"' in line:
            entry = get_parsed(line)
            usage = find_answer_usage(entry)
            if usage is not None:
                answer = (index, entry, usage)
        if boundary is None and b"compact_boundary" in line:
            entry = get_parsed(line)
            if is_boundary(entry):
                boundary = (index, entry)
        if summary is None and answer is None and b"isCompactSummary" in line:
            entry = get_parsed(line)
            if is_summary(entry):
                summary = (index, entry)
        if answer is not None and boundary is not None:
            break

    return answer, boundary, summary


def get_tail_lines(
    fd,
    size,
    length,
):
    start = max(0, size - length)
    chunks = []
    offset = start
    while offset < size:
        chunk = os.pread(
            fd,
            min(READ_STEP, size - offset),
            offset,
        )
        if not chunk:
            break
        chunks.append(chunk)
        offset += len(chunk)
    lines = b"".join(chunks).split(b"\n")

    return lines[1:] if start > 0 else lines


def get_regular_descriptor(path, flags):
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | flags)
    try:
        info = os.fstat(fd)
    except OSError:
        os.close(fd)
        raise
    if not stat.S_ISREG(info.st_mode):
        os.close(fd)
        return None, None
    return fd, info


def find_in_transcript(path):
    fd, info = get_regular_descriptor(path, 0)
    if fd is None:
        return None
    try:
        length = TAIL_START
        while True:
            lines = get_tail_lines(
                fd,
                info.st_size,
                length,
            )
            found = find_last_parts(lines)
            if any(part is not None for part in found) or length >= info.st_size or length >= TAIL_LIMIT:
                return found
            length = min(length * 2, TAIL_LIMIT)
    finally:
        os.close(fd)


def get_stamp(entry):
    value = entry.get("timestamp")
    return value if isinstance(value, str) and STAMP.fullmatch(value) else get_now_stamp()


def get_text(value):
    return value if isinstance(value, str) else None


def create_record(found, old):
    answer, boundary, summary = found
    if answer is None and boundary is None and summary is None:
        return None
    answer_index = answer[0] if answer else -1
    record = {
        "compactions": get_whole(old.get("compactions")) or 0,
        "compaction": get_text(old.get("compaction")),
        "compacted_at": get_text(old.get("compacted_at")),
    }
    if boundary is not None:
        uuid = boundary[1].get("uuid")
        if isinstance(uuid, str) and uuid and uuid != record["compaction"]:
            record["compactions"] += 1
            record["compaction"] = uuid
            record["compacted_at"] = get_stamp(boundary[1])
    after = [part for part in (boundary, summary) if part is not None and part[0] > answer_index]
    if after:
        latest = max(after, key=lambda part: part[0])
        record.update(
            state="compacted",
            tokens=None,
            window=None,
            percent=None,
            model=None,
            message=None,
            measured_at=get_stamp(latest[1]),
        )
        return record
    tokens = get_window_tokens(answer[2])
    if tokens is None:
        return None
    message = answer[1]["message"]
    model = get_text(message.get("model"))
    window = get_window(model)
    record.update(
        state="read",
        tokens=tokens,
        window=window,
        percent=None if window is None else get_percent(tokens, window),
        model=model,
        message=get_text(message.get("id")),
        measured_at=get_stamp(answer[1]),
    )
    if record["message"] is not None and old.get("state") == "read" and old.get("message") == record["message"]:
        for key in CARRIED_ON_SAME_ANSWER:
            carried = old.get(key)
            if isinstance(carried, str) and STAMP.fullmatch(carried):
                record[key] = carried

    return record
