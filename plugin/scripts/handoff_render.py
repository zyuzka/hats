"""The text the model gets: the note's head, its excerpt and the list of closed sessions.

Part of handoff.py, which holds the contract of the whole hook."""
import os

from handoff_check import checked, problem_lines, state_lines
from handoff_consts import (
    CUT_LINE,
    HEAD_LIMIT,
    MARK_INDENT,
    NOW_HEADING,
    OWN_LIMIT,
    SESSION_ID,
    SOURCE_SIZE_LIMIT,
    UNREADABLE_NOTE,
    USER_LINE_LIMIT,
    USER_LINE_START,
)
from handoff_files import read_regular
from handoff_text import body_start, cap_utf16, get_note_noun, get_shown, get_topic, get_units


def note_head(text):
    lines = text.split("\n")
    lines = lines[body_start(lines):]
    now = next((i for i, line in enumerate(lines) if NOW_HEADING.match(line)), None)
    kept = []
    size = 0
    headings = 0
    for i, line in enumerate(lines[now or 0:]):
        if line.startswith("## "):
            headings += 1
            if (now is not None and i > 0) or headings == 2:
                break
        if size + len(line) + 1 > HEAD_LIMIT:
            kept.append(CUT_LINE)
            break
        kept.append(line)
        size += len(line) + 1
    return "\n".join(kept).strip("\n")


def fetch_hint(facts):
    if any("no fetch" in fact for fact in facts):
        if all(" origin/" in fact for fact in facts if "no fetch" in fact):
            return ["origin/* refs were compared with local refs; what the server has now needs `git fetch`."]
        return ["Remote refs were compared with local refs; what the server has now needs `git fetch`."]
    return []


def get_fitted_excerpt(excerpt, limit):
    if get_units(excerpt) <= limit:
        return excerpt
    kept = cap_utf16(excerpt, max(0, limit - get_units(CUT_LINE) - 1))
    if "\n" in kept:
        kept = kept[:kept.rfind("\n")]
    if not kept:
        return CUT_LINE

    return f"{kept}\n{CUT_LINE}"


def render_own(marker, text):
    head = [
        f"[handoff] This session continues the note \"{marker['topic']}\", saved "
        f"{marker['saved_at']} by this same Claude process: {marker['note']}",
        "Below is the NOW section (or the start of the note); read the rest in the file.",
        "--- note ---",
    ]
    tail = ["--- end of excerpt ---"]
    problems = checked(text, marker["cwd"], os.path.realpath(marker["note"]))
    if problems:
        tail.append("Not verified (check against the source before relying on it):")
        tail.extend(problem_lines(problems))
    facts = state_lines(text)
    if facts:
        tail.append("State compared with the system:")
        tail.extend(facts)
        tail.extend(fetch_hint(facts))
    room = OWN_LIMIT - get_units("\n".join(head + tail)) - 2
    return "\n".join(head + [get_fitted_excerpt(note_head(text), room)] + tail)


def get_list_blocks(markers):
    blocks = [[
        "[handoff] Sessions that already closed left notes in this folder. Do not hold up the user's "
        "request for them: do what the user asks, and in your first reply mention these notes in one "
        "short line, in the user's language, so the user can pick one. Continue a note only if the user "
        "picks it; if the user asks to continue earlier work, offer these notes and wait for the choice:"
    ]]
    all_facts = []
    for index, marker in enumerate(markers, 1):
        text = read_regular(marker["note"], SOURCE_SIZE_LIMIT)
        out = [f"{index}. \"{marker['topic']}\" — saved {marker['saved_at']}: {marker['note']}"]
        if text is None:
            out.append(f"   {UNREADABLE_NOTE}: no permission, over the size limit or not a regular file")
            blocks.append(out)
            continue
        problems = checked(text, marker["cwd"], os.path.realpath(marker["note"]))
        if problems and problems[0][0] is None:
            out.append(f"   {problems[0][1]}")
        elif problems:
            out.append(f"   unverified lines: {len(problems)}")
        facts = state_lines(text)
        all_facts.extend(facts)
        out.extend("   " + fact for fact in facts)
        blocks.append(out)
    blocks.append(fetch_hint(all_facts))
    return blocks


def get_joined(blocks, marks=None):
    lines = []
    for index, block in enumerate(blocks):
        mark = marks[index - 1] if marks and 0 < index <= len(marks) else None
        lines.extend(block[:1] + ([mark] if mark else []) + block[1:])

    return "\n".join(lines)


def get_receiver(session):
    return f"session {session}" if SESSION_ID.fullmatch(session) else "another session"


def get_unlisted_line(unchecked):
    if unchecked:
        return f"{USER_LINE_START} could not check {unchecked} {get_note_noun(unchecked)} in time, none listed"

    return f"{USER_LINE_START} no notes from closed sessions in this folder"


def get_list_line(
    markers,
    hidden,
    unchecked,
    marks=(),
):
    found = len(markers) + hidden
    head = f"{USER_LINE_START} {found} {get_note_noun(found)} from closed sessions in this folder:"
    items = [f"{index}. \"{get_topic(marker)}\" — {get_shown(marker['note'])}" for index, marker in enumerate(markers, 1)]
    items = [item + (f"\n{MARK_INDENT}{mark}" if mark else "") for item, mark in zip(items, list(marks) + [None] * len(items))]
    tail = f"\ncould not check {unchecked} more {get_note_noun(unchecked)} in time" if unchecked else ""
    for kept in range(len(items), -1, -1):
        dropped = len(items) - kept + hidden
        more = f"\nand {dropped} more" if dropped else ""
        read = sum(1 for mark in marks[kept:] if mark)
        more += f", {read} of them being read by another session" if read else ""
        text = head + "".join("\n" + item for item in items[:kept]) + more + tail
        if len(text.encode("utf-16-le")) // 2 <= USER_LINE_LIMIT:
            return text

    return text
