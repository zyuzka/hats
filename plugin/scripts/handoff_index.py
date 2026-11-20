"""The resume index and its line in MEMORY.md.

Part of handoff.py, which holds the contract of the whole hook."""
import hashlib
import os
import stat
import time
from datetime import datetime, timezone

from handoff_clock import test_pause, testing
from handoff_consts import (
    INDEX_ABOUT,
    INDEX_ENTRY_LIMIT,
    INDEX_HEADER,
    INDEX_LINE,
    INDEX_LOCK_S,
    INDEX_NAME,
    INDEX_SIZE_LIMIT,
    INDEX_TOPIC_DROP,
    MAX_AGE,
    MEMORY_LINE,
    MEMORY_LOADED_LINES,
    MEMORY_LOADED_UNITS,
    MEMORY_NAME,
    MEMORY_SIZE_LIMIT,
    MEMORY_SKIPPED,
    PROJECT_FOLDER_LENGTH,
)
from handoff_files import fcntl, get_small_text, is_regular_file, is_same_file, try_lock
from handoff_paths import in_memory, is_service_name, note_in_memory, state_dir
from hats_common import write_text_whole
from handoff_text import cap_utf16, get_plain, is_indexable


def get_index_wait():
    if testing() and os.environ.get("HANDOFF_TEST_INDEX_WAIT"):
        return float(os.environ["HANDOFF_TEST_INDEX_WAIT"])
    return INDEX_LOCK_S


def get_index_lock(folder):
    if fcntl is None:
        return None, "no file locking here"
    digest = hashlib.sha256(os.fsencode(folder)).hexdigest()[:PROJECT_FOLDER_LENGTH]
    path = os.path.join(state_dir(), f"index-{digest}.lock")
    try:
        fd = os.open(
            path,
            os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
            0o600,
        )
    except OSError as error:
        return None, f"lock cannot be opened: {error.strerror or error}"
    wait_until = time.monotonic() + get_index_wait()
    while not try_lock(fd):
        if time.monotonic() >= wait_until:
            os.close(fd)
            return None, "lock busy"
        time.sleep(0.05)

    return fd, None


def get_index_text(path):
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return "", None
    except OSError as error:
        return None, f"{INDEX_NAME} cannot be read: {error.strerror or error}"
    if stat.S_ISLNK(info.st_mode):
        return None, f"{INDEX_NAME} is a link"
    text, error = get_small_text(path, INDEX_SIZE_LIMIT)
    if error:
        return None, f"{INDEX_NAME} {error}"
    if text.split("\n", 1)[0] != INDEX_HEADER:
        return None, f"{INDEX_NAME} has another first line, so the plugin did not write it"

    return text, None


def is_kept_entry(
    match,
    folder,
    name,
    now,
):
    other = match.group("name")
    try:
        saved = datetime.strptime(match.group("saved"), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return False

    return (
        other.endswith(".md")
        and not is_same_file(os.path.join(folder, other), os.path.join(folder, name))
        and is_indexable(other)
        and not is_service_name(other)
        and now - saved <= MAX_AGE
        and is_regular_file(os.path.join(folder, other))
    )


def get_index_entry(name, marker):
    topic = " ".join("".join(ch for ch in get_plain(marker["topic"]) if ch not in INDEX_TOPIC_DROP).split())

    return f"- [{topic}](<{name}>) — saved {marker['saved_at']}, folder {get_plain(marker['cwd'])}"


def set_index_file(
    folder,
    name,
    marker,
):
    path = os.path.join(folder, INDEX_NAME)
    text, error = get_index_text(path)
    if error:
        return error
    now = datetime.now(timezone.utc)
    kept = []
    for line in text.split("\n")[1:]:
        match = INDEX_LINE.fullmatch(line)
        if match and is_kept_entry(
            match,
            folder,
            name,
            now,
        ):
            kept.append(line)
    lines = [
        INDEX_HEADER,
        "",
        INDEX_ABOUT,
        "",
        get_index_entry(name, marker),
        *kept[:INDEX_ENTRY_LIMIT - 1],
    ]
    try:
        write_text_whole(
            os.path.dirname(path),
            os.path.basename(path),
            "\n".join(lines) + "\n",
            before_replace=test_pause,
        )
    except (OSError, ValueError) as error:
        return f"{INDEX_NAME} cannot be written: {error}"

    return None


def get_loaded_memory(text):
    head = "\n".join(text.split("\n")[:MEMORY_LOADED_LINES])
    cut = cap_utf16(head, MEMORY_LOADED_UNITS)
    if cut == head:
        return head
    end = cut.rfind("\n")

    return cut[:end] if end > 0 else cut


def is_index_link(line):
    return line.startswith("- [") and (
        "](resume-index.md)" in line
        or "](<resume-index.md>)" in line
    )


def create_memory_file(path):
    try:
        fd = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(MEMORY_LINE + "\n")
    except OSError as error:
        return f"not checked: {error.strerror or error}"

    return "created with the index line"


def is_still_empty(fd):
    info = os.fstat(fd)

    return stat.S_ISREG(info.st_mode) and info.st_size == 0


def set_empty_memory_file(path):
    try:
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        return f"not checked: {error.strerror or error}"
    try:
        if not is_still_empty(fd):
            return f"not checked: {MEMORY_NAME} changed while it was checked"
        os.write(fd, (MEMORY_LINE + "\n").encode("utf-8"))
    except OSError as error:
        return f"not checked: {error.strerror or error}"
    finally:
        os.close(fd)

    return "was empty, the index line written"


def find_memory_line(path):
    text, error = get_small_text(path, MEMORY_SIZE_LIMIT)
    if error:
        return f"not checked: {MEMORY_NAME} {error}"
    if any(is_index_link(line) for line in get_loaded_memory(text).split("\n")):
        return "has the index line"

    return f"add the index line: insert it with Edit before the current first line: {MEMORY_LINE}"


def set_memory_line(folder):
    path = os.path.join(folder, MEMORY_NAME)
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return create_memory_file(path)
    except OSError as error:
        return f"not checked: {error.strerror or error}"
    if stat.S_ISLNK(info.st_mode):
        return f"not checked: {MEMORY_NAME} is a link"
    if not stat.S_ISREG(info.st_mode):
        return f"not checked: {MEMORY_NAME} is not a regular file"
    if info.st_size == 0:
        return set_empty_memory_file(path)

    return find_memory_line(path)


def set_index(note, marker):
    real = os.path.realpath(note)
    if not in_memory(real):
        reason = "the memory folder is a link" if note_in_memory(note) is not None else "note not in Claude Code's memory"
        return [f"index: none ({reason})"]
    folder, name = os.path.dirname(real), os.path.basename(real)
    if not is_indexable(name):
        return ["index not updated: note name cannot be indexed", MEMORY_SKIPPED]
    lock, error = get_index_lock(folder)
    if error:
        return [f"index not updated: {error}", MEMORY_SKIPPED]
    try:
        error = set_index_file(
            folder,
            name,
            marker,
        )
        if error:
            return [f"index not updated: {error}", MEMORY_SKIPPED]
        return ["index: updated", f"MEMORY.md: {set_memory_line(folder)}"]
    finally:
        os.close(lock)
