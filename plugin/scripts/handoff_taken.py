"""Writing the taken/ folder: its lock, whole-file writes, the plan and the unlisting.

Part of handoff.py, which holds the contract of the whole hook."""
import os
import stat
import time

from handoff_clock import testing
from handoff_consts import (
    LOCK_STEP_S,
    NAME_TRIES,
    READER_LIMIT,
    READS_KEY_LIMIT,
    TAKEN_LIMIT,
    TAKEN_LOCK,
    UNLIST_LOCK_S,
)
from handoff_facts import create_mark
from handoff_files import fcntl, remove_quietly, try_lock
from handoff_marks import (
    create_reader,
    get_mark_bytes,
    get_mark_file,
    get_mark_path,
    get_merged_readers,
    get_note_key,
    get_others,
    get_reader_key,
    get_reads_bytes,
    get_reads_file,
    get_reads_name,
    get_reads_path,
    get_taken_folder,
    get_taken_kind,
)


def set_signal(kind):
    folder = os.environ.get("HANDOFF_TEST_TAKEN_SIGNAL") if testing() else None
    if not folder:
        return
    fd = os.open(
        os.path.join(folder, f"{os.getpid()}.{kind}"),
        os.O_WRONLY | os.O_CREAT,
        0o600,
    )
    os.close(fd)


def hold_for_test(until):
    path = os.environ.get("HANDOFF_TEST_TAKEN_HOLD") if testing() else None
    while path and not os.path.exists(path) and time.monotonic() < until:
        time.sleep(LOCK_STEP_S)


def create_taken_folder():
    try:
        os.mkdir(get_taken_folder(), 0o700)
    except FileExistsError:
        pass
    except OSError:
        return "taken-not-created"
    kind = get_taken_kind()
    if kind != "folder":
        return "taken-not-folder"

    return None


def get_lock_flags(create):
    flags = os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC

    return flags | os.O_CREAT if create else flags


def get_taken_lock(create, until):
    if fcntl is None:
        return None, "no-locking"
    error = create_taken_folder() if create else None
    if error:
        return None, error
    try:
        fd = os.open(
            os.path.join(get_taken_folder(), TAKEN_LOCK),
            get_lock_flags(create),
            0o600,
        )
    except OSError:
        return None, "lock-not-opened"
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        return None, "lock-not-file"
    if time.monotonic() >= until:
        os.close(fd)
        return None, "no-time"
    set_signal("waiting")
    while not try_lock(fd):
        if time.monotonic() >= until:
            os.close(fd)
            return None, "lock-busy"
        time.sleep(LOCK_STEP_S)
    set_signal("locked")
    hold_for_test(until)

    return fd, None


def set_written(
    fd,
    path,
    data,
):
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
    except OSError:
        remove_quietly(path)
        raise


def create_temp_file(data):
    folder = get_taken_folder()
    for number in range(NAME_TRIES):
        path = os.path.join(folder, f".tmp-{os.getpid()}-{number}.json")
        try:
            fd = os.open(
                path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
            )
        except FileExistsError:
            continue
        set_written(
            fd,
            path,
            data,
        )
        return path

    raise FileExistsError(f"no free temporary name in {folder}")


def set_replaced(tmp, path):
    if testing() and os.environ.get("HANDOFF_TEST_FAIL") == "replace":
        raise OSError("os.replace failed on purpose (HANDOFF_TEST_FAIL=replace)")
    os.replace(tmp, path)


def remove_temps(pairs):
    for tmp, _ in pairs or ():
        remove_quietly(tmp)


def set_replaced_all(pairs):
    for index, (tmp, path) in enumerate(pairs):
        try:
            set_replaced(tmp, path)
        except OSError:
            remove_temps(pairs[index:])
            return "replace"

    return None


def remove_dead_reads(dead):
    for pid, started in dead:
        remove_quietly(os.path.join(get_taken_folder(), get_reads_name(pid, started)))


def find_snapshot(reals, proc):
    snapshot = {
        "union": [],
        "unreadable": False,
        "reads_unreadable": False,
    }
    if get_taken_kind() != "folder":
        return snapshot
    lists = []
    for real in reals:
        state, readers, _ = get_mark_file(get_note_key(real))
        snapshot["unreadable"] = snapshot["unreadable"] or state == "unreadable"
        lists.append(readers or [])
    snapshot["union"] = get_merged_readers(lists)
    snapshot["reads_unreadable"] = get_reads_file(proc)[0] == "unreadable"

    return snapshot


def get_snapshot_mark(
    snapshot,
    states,
    proc,
):
    others = get_others(snapshot["union"], proc)

    return create_mark(
        others,
        states,
        others,
        snapshot["unreadable"],
    )


def is_reader_in(readers, proc):
    return any(get_reader_key(reader) == proc for reader in readers)


def set_plan_content(
    plan,
    files,
    kept,
    reader,
):
    proc = get_reader_key(reader)
    for real, readers in kept.items():
        mine = is_reader_in(readers, proc)
        if not mine and len(readers) >= READER_LIMIT:
            plan["full"] = True
        content = readers if mine else get_merged_readers([readers, [reader]])
        if content != files[real]:
            plan["files"][real] = content


def set_plan_reads(
    plan,
    proc,
    keys,
    wanted,
):
    keys_after = keys + [key for key in wanted if key not in keys]
    if keys_after == keys:
        return
    data = get_reads_bytes(proc, keys_after)
    if len(keys_after) > READS_KEY_LIMIT or len(data) > TAKEN_LIMIT:
        plan["full"] = True
    plan["reads"] = data


def find_plan(
    reals,
    proc,
    session,
    snapshot,
    states,
):
    files = {}
    for real in reals:
        state, readers, _ = get_mark_file(get_note_key(real))
        if state == "unreadable":
            return None
        files[real] = readers
    reads_state, keys = get_reads_file(proc)
    if reads_state == "unreadable":
        return None
    dead = {key for key, verdict in states.items() if verdict == "dead"}
    kept = {real: [r for r in readers if get_reader_key(r) not in dead] for real, readers in files.items()}
    union = get_merged_readers(kept.values())
    mine = [reader for reader in union if get_reader_key(reader) == proc]
    plan = {
        "again": bool(mine),
        "mark": create_mark(
            get_others(union, proc),
            states,
            snapshot,
            False,
        ),
        "dead": {get_reader_key(r) for readers in files.values() for r in readers if get_reader_key(r) in dead},
        "full": False,
        "files": {},
        "reads": None,
    }
    set_plan_content(
        plan,
        files,
        kept,
        mine[0] if mine else create_reader(proc, session),
    )
    set_plan_reads(
        plan,
        proc,
        keys,
        [get_note_key(real) for real in reals],
    )

    return plan


def create_plan_temps(plan, proc):
    pairs = []
    try:
        if plan["reads"] is not None:
            pairs.append((create_temp_file(plan["reads"]), get_reads_path(proc)))
        for real, readers in plan["files"].items():
            pairs.append((create_temp_file(get_mark_bytes(real, readers)), get_mark_path(get_note_key(real))))
    except (OSError, ValueError):
        remove_temps(pairs)
        return None, "temp"

    return pairs, None


def find_plan_temps(plan, proc):
    if plan is None:
        return None, "unreadable"
    if plan["full"]:
        return None, "full"

    return create_plan_temps(plan, proc)


def set_unlisted_reader(key, proc):
    state, readers, note = get_mark_file(key)
    if state == "unreadable":
        return "unreadable"
    left = get_others(readers, proc)
    if state != "ok" or len(left) == len(readers):
        return None
    path = get_mark_path(key)
    tmp = None
    try:
        if not left:
            os.remove(path)
            return None
        tmp = create_temp_file(get_mark_bytes(note, left))
        set_replaced(tmp, path)
    except (OSError, ValueError):
        remove_temps([(tmp, path)] if tmp else [])
        return "write"

    return None


def set_reads_keys(proc, keys):
    path = get_reads_path(proc)
    tmp = None
    try:
        if not keys:
            os.remove(path)
            return None
        tmp = create_temp_file(get_reads_bytes(proc, keys))
        set_replaced(tmp, path)
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        remove_temps([(tmp, path)] if tmp else [])
        return "write"

    return None


def set_unlisted_files(proc, keep):
    state, keys = get_reads_file(proc)
    if state == "unreadable":
        return 0, "unreadable"
    left, cleared, error = [], 0, None
    for key in keys:
        failure = None if key in keep else set_unlisted_reader(key, proc)
        if key in keep or failure:
            left.append(key)
        else:
            cleared += 1
        error = failure or error
    if state != "ok" or left != keys:
        error = set_reads_keys(proc, left) or error

    return cleared, error


def set_unlisted_keys(proc, keep):
    kind = get_taken_kind()
    if kind == "absent":
        return 0, None
    if kind != "folder":
        return 0, "taken-not-folder"
    if not os.path.lexists(get_reads_path(proc)):
        return 0, None
    lock, reason = get_taken_lock(False, time.monotonic() + UNLIST_LOCK_S)
    if lock is None:
        return 0, reason
    try:
        return set_unlisted_files(proc, keep)
    finally:
        os.close(lock)


def set_unlisted(
    proc,
    reals,
    seen,
):
    keep = {get_note_key(real) for real in reals}
    try:
        cleared, error = set_unlisted_keys(proc, keep)
    except Exception as failure:
        cleared, error = 0, type(failure).__name__
    seen["cleared"] = cleared
    if error:
        seen["clear_error"] = error
