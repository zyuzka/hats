"""The took hook: a Read of a note marks the session as its reader.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import os
import sys
import time

import handoff_state
from handoff_clock import out_of_time, test_pause, time_budget
from handoff_consts import CHECK_SPARE_S, LOCK_SPARE_S, MARKER_LIMIT, TOOK_BUDGET_S
from handoff_facts import get_reader_states, get_took_output, has_mark
from handoff_files import get_file_id, get_small_text, usable
from handoff_markers import is_marker_shape, session_id
from handoff_marks import get_others, get_reader_key
from handoff_output import say, say_within
from handoff_paths import allowed_note, is_note_place, state_dir
from handoff_proc import claude_process, get_pid_state, get_verdict
from handoff_runlog import write_trace
from handoff_taken import (
    find_plan,
    find_plan_temps,
    find_snapshot,
    get_snapshot_mark,
    get_taken_lock,
    is_reader_in,
    remove_dead_reads,
    remove_temps,
    set_replaced_all,
)
from handoff_text import clip
from hats_common import unattended


def get_took_input():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except (ValueError, RecursionError):
        return None

    return data if isinstance(data, dict) else None


def is_read_input(data):
    return data.get("hook_event_name") == "PostToolUse" and data.get("tool_name") == "Read"


def get_read_path(data):
    tool_input = data.get("tool_input")
    path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if not is_read_input(data) or not usable(path) or not os.path.isabs(path):
        return None

    return path


def find_marker_real(path, read_id):
    text, error = get_small_text(path, MARKER_LIMIT)
    if error:
        return None
    try:
        marker = json.loads(text)
    except (ValueError, RecursionError):
        return None
    if not is_marker_shape(marker) or get_file_id(os.path.expanduser(marker["note"])) != read_id:
        return None
    kept = allowed_note(marker["note"], marker["cwd"])
    if kept is None or get_file_id(kept) != read_id:
        return None

    return os.path.realpath(kept), (marker["pid"], marker["started"])


def find_took_group(read_id):
    folder = state_dir()
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return [], []
    reals = []
    authors = []
    for name in names:
        if out_of_time():
            return None
        if not name.endswith(".json"):
            continue
        found = find_marker_real(os.path.join(folder, name), read_id)
        if found is None:
            continue
        if found[0] not in reals:
            reals.append(found[0])
        if found[1] not in authors:
            authors.append(found[1])

    return reals, authors


def find_live_authors(
    authors,
    proc,
    until,
    cache,
):
    live = []
    for pid, started in authors:
        if (pid, started) == proc:
            continue
        if pid not in cache:
            cache[pid] = get_pid_state(pid, until)
        if get_verdict(cache[pid], {"started": started}) == "alive":
            live.append((pid, started))

    return live


def get_unread_authors(authors, mark):
    live = {get_reader_key(reader) for reader in mark["live"]}

    return [author for author in authors if author not in live]


def set_took_locked(given, seen):
    plan = find_plan(
        given["reals"],
        given["proc"],
        given["session"],
        given["snapshot"]["union"],
        given["states"],
    )
    if plan is None:
        seen.update(outcome="not-recorded", reason="unreadable")
        return
    mark = plan["mark"]
    authors = get_unread_authors(given["authors"], mark)
    warn = (has_mark(mark) or bool(authors)) and not plan["again"]
    seen.update(live=len(mark["live"]), unknown=len(mark["unknown"]), authors=len(authors), warned=warn)
    pairs, reason = find_plan_temps(plan, given["proc"])
    if warn and not say_within(*get_took_output(mark, authors), "PostToolUse"):
        remove_temps(pairs)
        seen.update(outcome="not-printed", warned=False)
        return
    if reason:
        seen.update(outcome="again" if plan["again"] else "not-recorded", reason=reason)
        return
    test_pause()
    reason = set_replaced_all(pairs)
    if reason:
        seen.update(outcome="not-recorded", reason=reason)
        return
    remove_dead_reads(plan["dead"])
    seen["outcome"] = "again" if plan["again"] else ("took-shared" if warn else "took")


def set_took(given, seen):
    snapshot = find_snapshot(given["reals"], given["proc"])
    if snapshot["unreadable"] or snapshot["reads_unreadable"]:
        seen.update(outcome="not-recorded", reason="unreadable")
        return
    others = get_others(snapshot["union"], given["proc"])
    cache = {}
    given.update(snapshot=snapshot, states=get_reader_states(others, handoff_state.deadline - CHECK_SPARE_S, cache))
    given["authors"] = find_live_authors(given["authors"], given["proc"], handoff_state.deadline - CHECK_SPARE_S, cache)
    lock, reason = get_taken_lock(True, handoff_state.deadline - LOCK_SPARE_S)
    if lock is None:
        mark = get_snapshot_mark(snapshot, given["states"], given["proc"])
        authors = get_unread_authors(given["authors"], mark)
        warn = (has_mark(mark) or bool(authors)) and not is_reader_in(snapshot["union"], given["proc"])
        if warn:
            say(*get_took_output(mark, authors), "PostToolUse")
        seen.update(outcome="not-recorded", reason=reason, warned=warn, live=len(mark["live"]), unknown=len(mark["unknown"]),
                    authors=len(authors))
        return
    try:
        set_took_locked(given, seen)
    finally:
        os.close(lock)


def cmd_took(seen):
    handoff_state.deadline = time.monotonic() + time_budget(TOOK_BUDGET_S)
    if os.environ.get("HANDOFF_OFF") == "1" or unattended():
        return
    data = get_took_input()
    if data is None:
        seen["outcome"] = "bad-input"
        return
    if data.get("agent_id") is not None:
        return
    session = session_id(data)
    path = get_read_path(data)
    if path is None:
        seen.update(outcome="bad-input", session=session)
        return
    read_id = get_file_id(path) if is_note_place(path) else None
    group = find_took_group(read_id) if read_id is not None else ([], [])
    if group is None:
        seen.update(outcome="incomplete", session=session)
        return
    reals, authors = group
    if not reals:
        return
    seen.update(session=session, note=clip(reals[0]))
    proc = claude_process()
    if not proc:
        seen["outcome"] = "no-process"
        return
    seen["pid"] = proc[0]
    handoff_state.tell = True
    given = {
        "reals": reals,
        "proc": proc,
        "session": session,
        "authors": authors,
    }
    set_took(given, seen)


def run_took():
    began = time.monotonic()
    seen = {}
    try:
        cmd_took(seen)
    except Exception as error:
        seen.update(outcome="error", error=type(error).__name__, message=clip(str(error)))
    finally:
        if seen.get("outcome"):
            write_trace(dict({"command": "took"}, **seen), began)

    return 0
