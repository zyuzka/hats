"""Who else reads a note: reader states, mark lookups and the lines about them.

Part of handoff.py, which holds the contract of the whole hook."""
from datetime import datetime

import handoff_state
from handoff_consts import (
    AUTHOR_WORDS,
    LIST_ASK,
    LSTART,
    MARKS_SPARE_S,
    MARK_INDENT,
    MARK_LIST_LIMIT,
    MARK_WORDS,
    MORE_WORDS,
    OUTPUT_LIMIT,
    SESSION_ID,
    STAMP,
    TOOK_ASK,
    TOOK_WORDS,
    UNREADABLE_MARK,
    USER_LINE_LIMIT,
    USER_LINE_START,
)
from handoff_marks import (
    find_group_reals,
    get_mark_file,
    get_merged_readers,
    get_note_key,
    get_reader_key,
    get_taken_kind,
)
from handoff_proc import get_pid_state, get_verdict
from handoff_render import get_joined, get_list_line
from handoff_text import cap_utf16, get_shown, get_topic, get_units


def get_reader_states(
    readers,
    until,
    cache,
):
    states = {}
    for reader in readers:
        if reader["pid"] not in cache:
            cache[reader["pid"]] = get_pid_state(reader["pid"], until)
        states[get_reader_key(reader)] = get_verdict(cache[reader["pid"]], reader)

    return states


def create_mark(
    others,
    states,
    known,
    unreadable,
):
    seen = {get_reader_key(reader) for reader in known}

    return {
        "live": [r for r in others if get_reader_key(r) not in seen or states.get(get_reader_key(r)) == "alive"],
        "unknown": [r for r in others if get_reader_key(r) in seen and states.get(get_reader_key(r)) == "unknown"],
        "unreadable": unreadable,
    }


def has_mark(mark):
    return bool(mark) and bool(mark["live"] or mark["unknown"] or mark["unreadable"])


def get_reader_item(reader):
    session = reader["session"]
    who = f"session {session}" if isinstance(session, str) and SESSION_ID.fullmatch(session) else "a session"

    return f"{who} (pid {reader['pid']}, since {reader['at']})"


def get_reader_list(readers, shown):
    listed = ", ".join(get_reader_item(reader) for reader in readers[:shown])
    more = len(readers) - shown
    if not more:
        return listed

    return f"{listed}, and {more} more" if listed else f"and {more} more"


def get_facts(
    mark,
    words,
    shown=None,
):
    live, unknown = mark["live"], mark["unknown"]
    shown = len(live) + len(unknown) if shown is None else shown
    text = words[0].format(len(live)) + get_reader_list(live, min(shown, len(live))) if live else ""
    if unknown:
        lead = MORE_WORDS if live else words[1]
        text += lead.format(len(unknown)) + get_reader_list(unknown, max(0, shown - len(live)))
    if mark["unreadable"]:
        text += ("; " if text else "") + UNREADABLE_MARK

    return text


def find_fitting(
    mark,
    words,
    frame,
    limit,
):
    prefix, suffix = frame
    text = ""
    for shown in range(len(mark["live"]) + len(mark["unknown"]), -1, -1):
        text = prefix + get_facts(
            mark,
            words,
            shown,
        ) + suffix
        if get_units(text) <= limit:
            return text

    return cap_utf16(text, limit)


def get_short_facts(mark):
    return find_fitting(
        mark,
        MARK_WORDS,
        ("", ""),
        MARK_LIST_LIMIT,
    )


def get_since(started):
    try:
        return datetime.strptime(started, LSTART).strftime(STAMP)
    except ValueError:
        return started


def get_author_line(authors):
    return AUTHOR_WORDS + ", ".join(f"pid {pid} (since {get_since(started)})" for pid, started in authors)


def get_took_output(mark, authors):
    user = [f"{USER_LINE_START} {get_author_line(authors)}"] if authors else []
    model = [f"[handoff] {get_author_line(authors)}."] if authors else []
    if not has_mark(mark):
        return cap_utf16(user[0], USER_LINE_LIMIT), cap_utf16(f"{model[0]} {TOOK_ASK}", OUTPUT_LIMIT)
    user = find_fitting(
        mark,
        TOOK_WORDS,
        ("".join(line + "\n" for line in user) + f"{USER_LINE_START} ", ""),
        USER_LINE_LIMIT,
    )
    model = find_fitting(
        mark,
        TOOK_WORDS,
        ("".join(line + "\n" for line in model) + "[handoff] ", f". {TOOK_ASK}"),
        OUTPUT_LIMIT,
    )

    return user, model


def get_clear_output(
    marker,
    body,
    mark,
):
    user = f"{USER_LINE_START} continuing anchor \"{get_topic(marker)}\" — {get_shown(marker['note'])}"
    if not has_mark(mark):
        return user, cap_utf16(body, OUTPUT_LIMIT)
    facts = get_short_facts(mark)

    return f"{user}\n{MARK_INDENT}{facts}", cap_utf16(f"[handoff] {facts}. {TOOK_ASK}\n{body}", OUTPUT_LIMIT)


def find_mark(
    reals,
    kind,
    until,
    cache,
):
    if kind != "folder":
        return create_mark(
            [],
            {},
            [],
            True,
        )
    lists, unreadable = [], False
    for real in reals:
        state, readers, _ = get_mark_file(get_note_key(real))
        unreadable = unreadable or state == "unreadable"
        lists.append(readers or [])
    union = get_merged_readers(lists)
    mark = create_mark(
        union,
        get_reader_states(
            union,
            until,
            cache,
        ),
        union,
        unreadable,
    )

    return mark if has_mark(mark) else None


def find_marks(shown, markers):
    kind = get_taken_kind()
    if kind == "absent":
        return [None] * len(shown)
    until = handoff_state.deadline - MARKS_SPARE_S
    ids, cache = {}, {}

    return [find_mark(
        find_group_reals(
            marker["note"],
            markers,
            ids,
        ),
        kind,
        until,
        cache,
    ) for marker in shown]


def find_model_marks(blocks, found):
    marks = [None] * len(found)
    dropped = 0
    for index, mark in enumerate(found):
        if not mark:
            continue
        marks[index] = f"{MARK_INDENT}{get_facts(mark, MARK_WORDS)}. {LIST_ASK}"
        if get_units(get_joined(blocks, marks)) > OUTPUT_LIMIT:
            marks[index] = None
            dropped += 1

    return marks, dropped


def find_marked_list(
    shown,
    hidden,
    unchecked,
    blocks,
    markers,
    seen,
):
    plain = get_list_line(shown, hidden, unchecked), cap_utf16(get_joined(blocks), OUTPUT_LIMIT)
    seen.update(marks=0, marks_dropped=0)
    try:
        found = find_marks(shown, markers)
        if not any(found):
            return plain
        model_marks, dropped = find_model_marks(blocks, found)
        user_marks = [get_short_facts(mark) if mark else None for mark in found]
        seen.update(marks=sum(1 for mark in found if mark), marks_dropped=dropped)
        user = get_list_line(
            shown,
            hidden,
            unchecked,
            user_marks,
        )
        return user, cap_utf16(get_joined(blocks, model_marks), OUTPUT_LIMIT)
    except Exception as error:
        seen.update(marks=0, marks_dropped=0, marks_error=type(error).__name__)
        return plain
