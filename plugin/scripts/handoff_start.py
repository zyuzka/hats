"""The start hook: the note after /clear or the list of closed sessions.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import os
import sys
import time
from datetime import datetime, timezone

import handoff_state
from handoff_clock import out_of_time, test_pause, time_budget
from handoff_consts import (
    CHECK_SPARE_S,
    LIST_LIMIT,
    LOCK_SPARE_S,
    MAX_AGE,
    OUTPUT_LIMIT,
    SOURCE_SIZE_LIMIT,
    UNREADABLE_NOTE,
    USER_LINE_START,
)
from handoff_facts import find_marked_list, get_clear_output, get_reader_states
from handoff_files import read_regular, same_path, usable
from handoff_markers import checked_markers, handed_session, record_handed, saved_time, session_id
from handoff_marks import find_group_reals, get_others
from handoff_output import say, say_within
from handoff_proc import claude_process, liveness
from handoff_render import get_list_blocks, get_receiver, get_unlisted_line, render_own
from handoff_taken import (
    find_plan,
    find_plan_temps,
    find_snapshot,
    get_snapshot_mark,
    get_taken_lock,
    remove_dead_reads,
    remove_temps,
    set_replaced_all,
    set_unlisted,
)
from handoff_text import cap_utf16, clip, get_shown, get_topic
from hats_common import unattended


def cmd_start(seen):
    if os.environ.get("HANDOFF_OFF") == "1":
        seen["outcome"] = "off"
        return 0
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except (ValueError, RecursionError):
        seen["outcome"] = "bad-input"
        return 0
    if not isinstance(data, dict):
        seen["outcome"] = "bad-input"
        return 0
    source, cwd = data.get("source"), data.get("cwd")
    session = session_id(data)
    seen.update(source=clip(source), session=session, cwd=clip(cwd) if usable(cwd) else None)
    if source not in ("clear", "startup") or not usable(cwd):
        seen["outcome"] = "skipped"
        return 0
    if source == "startup" and unattended():
        seen["outcome"] = "unattended"
        return 0
    handoff_state.tell = not unattended()
    handoff_state.deadline = time.monotonic() + time_budget()
    markers = checked_markers()
    if source == "clear":
        proc = claude_process()
        if not proc:
            seen["outcome"] = "no-process"
            say(f"{USER_LINE_START} could not identify this Claude process, no anchor given", None)
            return 0
        seen["pid"] = proc[0]
        own = [m for m in markers if m["pid"] == proc[0] and m["started"] == proc[1]]
        given = handed_session(own[0]) if own and session else None
        if handoff_state.tell:
            set_unlisted(
                proc,
                find_kept_reals(
                    own,
                    given,
                    session,
                    markers,
                ),
                seen,
            )
        if not own:
            seen["outcome"] = "no-own-marker"
            say(f"{USER_LINE_START} no anchor saved in this Claude process", None)
            return 0
        if given is not None and given != session:
            seen.update(outcome="handed-elsewhere", handed_to=clip(given))
            say(f"{USER_LINE_START} anchor \"{get_topic(own[0])}\" was already given to {get_receiver(given)}", None)
            return 0
        text = read_regular(own[0]["note"], SOURCE_SIZE_LIMIT)
        if text is None:
            seen["outcome"] = "note-unreadable"
            say(
                f"{USER_LINE_START} {UNREADABLE_NOTE} of anchor \"{get_topic(own[0])}\", not given — "
                f"{get_shown(own[0]['note'])}",
                None,
            )
            return 0
        if not handoff_state.tell:
            say(
                f"{USER_LINE_START} continuing anchor \"{get_topic(own[0])}\" — {get_shown(own[0]['note'])}",
                cap_utf16(render_own(own[0], text), OUTPUT_LIMIT),
            )
        elif not set_given_note(
            own[0],
            text,
            proc,
            markers,
            session,
            seen,
        ):
            seen["outcome"] = "not-printed"
            return 0
        if session and given is None:
            record_handed(own[0], session)
        receiver = "none" if not session else ("new" if given is None else "same")
        seen.update(outcome="gave-note", receiver=receiver)
        return 0
    else:
        now = datetime.now(timezone.utc)
        closed = []
        unchecked = 0
        for marker in markers:
            late = out_of_time()
            here = marker["cwd"] == cwd if late else same_path(marker["cwd"], cwd)
            if not here:
                continue
            when = saved_time(marker)
            if when is None or now - when > MAX_AGE:
                continue
            state = "unknown" if late else liveness(marker)
            if state == "unknown":
                unchecked += 1
            if state != "closed":
                continue
            closed.append((when, marker))
        seen["unchecked"] = unchecked
        if not closed:
            seen["outcome"] = "unchecked" if unchecked else "no-closed"
            say(get_unlisted_line(unchecked), None)
            return 0
        closed.sort(key=lambda pair: pair[0], reverse=True)
        shown = [marker for _, marker in closed[:LIST_LIMIT]]
        blocks = get_list_blocks(shown)
    user, model = find_marked_list(
        shown,
        len(closed) - len(shown),
        unchecked,
        blocks,
        markers,
        seen,
    )
    say(user, model)
    seen.update(outcome="listed", listed=len(shown))
    return 0


def is_handed_elsewhere(given, session):
    return given is not None and given != session


def find_kept_reals(
    own,
    given,
    session,
    markers,
):
    if not own or is_handed_elsewhere(given, session):
        return []

    return find_group_reals(own[0]["note"], markers)


def find_checked_snapshot(given, seen):
    try:
        snapshot = find_snapshot(given["reals"], given["proc"])
        others = get_others(snapshot["union"], given["proc"])
        given.update(snapshot=snapshot, states=get_reader_states(others, handoff_state.deadline, {}))
        return True
    except Exception as error:
        seen.update(reader="error", marks_error=type(error).__name__)
        return False


def set_given_locked(given, seen):
    plan = find_plan(
        given["reals"],
        given["proc"],
        given["session"],
        given["snapshot"]["union"],
        given["states"],
    )
    mark = plan["mark"] if plan else dict(get_snapshot_mark(given["snapshot"], given["states"], given["proc"]), unreadable=True)
    pairs, reason = find_plan_temps(plan, given["proc"])
    user, model = get_clear_output(given["marker"], given["body"], mark)
    if not say_within(user, model, "SessionStart"):
        remove_temps(pairs)
        seen["reader"] = "not-printed"
        return False
    if reason:
        seen.update(reader="not-recorded", reason=reason)
        return True
    test_pause()
    reason = set_replaced_all(pairs)
    if reason:
        seen.update(reader="not-recorded", reason=reason)
        return True
    remove_dead_reads(plan["dead"])
    seen["reader"] = "again" if plan["again"] else "took"

    return True


def set_given_note(
    marker,
    text,
    proc,
    markers,
    session,
    seen,
):
    deadline = handoff_state.deadline
    given = {
        "marker": marker,
        "reals": find_group_reals(marker["note"], markers),
        "proc": proc,
        "session": session,
    }
    handoff_state.deadline = deadline - CHECK_SPARE_S
    try:
        checked_ok = find_checked_snapshot(given, seen)
        given["body"] = render_own(marker, text)
    finally:
        handoff_state.deadline = deadline
    if not checked_ok:
        say(*get_clear_output(marker, given["body"], None))
        return True
    lock, reason = get_taken_lock(True, handoff_state.deadline - LOCK_SPARE_S)
    if lock is None:
        say(*get_clear_output(marker, given["body"], get_snapshot_mark(given["snapshot"], given["states"], proc)))
        seen.update(reader="not-recorded", reason=reason)
        return True
    try:
        return set_given_locked(given, seen)
    finally:
        os.close(lock)
