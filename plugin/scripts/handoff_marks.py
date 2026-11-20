"""Names, shapes and reads of the taken/ mark files and their readers.

Part of handoff.py, which holds the contract of the whole hook."""
import hashlib
import os
import stat
from datetime import datetime, timezone

from handoff_consts import NOTE_KEY, READER_LIMIT, READS_KEY_LIMIT, STAMP, TAKEN_FOLDER, TAKEN_LIMIT
from handoff_files import get_cached_id, get_small_json, usable
from handoff_markers import marker_file
from handoff_paths import state_dir
from handoff_text import get_json_bytes


def find_group_reals(
    note,
    markers,
    ids=None,
):
    ids = {} if ids is None else ids
    want = get_cached_id(note, ids)
    reals = []
    for marker in markers:
        if want is None or get_cached_id(marker["note"], ids) != want:
            continue
        real = os.path.realpath(marker["note"])
        if real not in reals:
            reals.append(real)

    return reals


def get_taken_folder():
    return os.path.join(state_dir(), TAKEN_FOLDER)


def get_taken_kind():
    try:
        info = os.lstat(get_taken_folder())
    except FileNotFoundError:
        return "absent"
    except OSError:
        return "other"

    return "folder" if stat.S_ISDIR(info.st_mode) else "other"


def get_note_key(real):
    return hashlib.sha256(os.fsencode(real)).hexdigest()


def is_key_of(note, key):
    try:
        return isinstance(note, str) and get_note_key(note) == key
    except (UnicodeError, ValueError):
        return False


def get_mark_path(key):
    return os.path.join(get_taken_folder(), key + ".json")


def get_reads_name(pid, started):
    return marker_file(pid, started)[:-len(".json")] + ".reads"


def get_reads_path(proc):
    return os.path.join(get_taken_folder(), get_reads_name(proc[0], proc[1]))


def is_stamp(value):
    try:
        datetime.strptime(value, STAMP)
    except (TypeError, ValueError):
        return False

    return True


def is_pid(value):
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and value > 0
    )


def is_reader(entry):
    return (
        isinstance(entry, dict)
        and is_pid(entry.get("pid"))
        and usable(entry.get("started"))
        and (entry.get("session") is None or isinstance(entry.get("session"), str))
        and is_stamp(entry.get("at"))
    )


def get_reader_key(reader):
    return reader["pid"], reader["started"]


def get_clean_reader(entry):
    return {
        "pid": entry["pid"],
        "started": entry["started"],
        "session": entry.get("session"),
        "at": entry["at"],
    }


def create_reader(proc, session):
    return {
        "pid": proc[0],
        "started": proc[1],
        "session": session,
        "at": datetime.now(timezone.utc).strftime(STAMP),
    }


def get_merged_readers(lists):
    found = {}
    for reader in [reader for readers in lists for reader in readers]:
        key = get_reader_key(reader)
        if key not in found or reader["at"] < found[key]["at"]:
            found[key] = reader

    return sorted(found.values(), key=lambda reader: (reader["at"], reader["pid"]))


def get_others(readers, proc):
    return [reader for reader in readers if get_reader_key(reader) != proc]


def is_mark_shape(data, key):
    return (
        isinstance(data, dict)
        and is_key_of(data.get("note"), key)
        and isinstance(data.get("readers"), list)
    )


def get_mark_file(key):
    state, data = get_small_json(get_mark_path(key), TAKEN_LIMIT)
    if state == "unreadable":
        return state, None, None
    if state != "ok" or not is_mark_shape(data, key):
        return "absent" if state == "absent" else "bad", [], None
    if len(data["readers"]) > READER_LIMIT:
        return "unreadable", None, None
    readers = [get_clean_reader(entry) for entry in data["readers"] if is_reader(entry)]

    return "ok", get_merged_readers([readers]), data["note"]


def is_reads_shape(data, proc):
    return (
        isinstance(data, dict)
        and data.get("pid") == proc[0]
        and data.get("started") == proc[1]
        and isinstance(data.get("keys"), list)
    )


def get_reads_file(proc):
    state, data = get_small_json(get_reads_path(proc), TAKEN_LIMIT)
    if state == "unreadable":
        return state, None
    if state != "ok" or not is_reads_shape(data, proc):
        return "absent" if state == "absent" else "bad", []
    if len(data["keys"]) > READS_KEY_LIMIT:
        return "unreadable", None
    keys = [key for key in data["keys"] if isinstance(key, str) and NOTE_KEY.fullmatch(key)]

    return "ok", list(dict.fromkeys(keys))


def get_mark_bytes(note, readers):
    return get_json_bytes({
        "note": note,
        "readers": readers,
    })


def get_reads_bytes(proc, keys):
    return get_json_bytes({
        "pid": proc[0],
        "started": proc[1],
        "keys": keys,
    })
