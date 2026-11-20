"""Low-level file reads, file identity and locks; fcntl is None where the system lacks it.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import os
import stat


try:
    import fcntl
except ImportError:
    fcntl = None


def usable(path):
    return isinstance(path, str) and path != "" and "\x00" not in path


def same_path(a, b):
    return os.path.realpath(a) == os.path.realpath(b)


def read_regular(path, limit):
    try:
        if not usable(path) or not os.path.isfile(path) or os.path.getsize(path) > limit:
            return None
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except (OSError, ValueError):
        return None


def is_same_folder(folder, root):
    try:
        return os.path.samestat(os.stat(folder), root)
    except (OSError, ValueError):
        return False


def get_file_id(path):
    try:
        info = os.stat(path)
    except (OSError, ValueError):
        return None

    return info.st_dev, info.st_ino


def get_cached_id(path, ids):
    if path not in ids:
        ids[path] = get_file_id(path)

    return ids[path]


def get_small_json(path, limit):
    if not os.path.lexists(path):
        return "absent", None
    text, error = get_small_text(path, limit)
    if error == "is not UTF-8":
        return "bad", None
    if error:
        return "unreadable", None
    try:
        return "ok", json.loads(text)
    except (ValueError, RecursionError):
        return "bad", None


def remove_quietly(path):
    try:
        os.remove(path)
    except OSError:
        pass


def is_same_place(path, other):
    found = get_file_id(path)

    return found is not None and found == get_file_id(other)


def is_regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except (OSError, ValueError):
        return False


def try_lock(fd):
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return False

    return True


def get_regular_bytes(fd, limit):
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        return None, "is not a regular file"
    data = b""
    while len(data) <= limit:
        chunk = os.read(fd, limit + 1 - len(data))
        if not chunk:
            break
        data += chunk
    if len(data) > limit:
        return None, f"is larger than {limit // 1024} KB"

    return data, None


def get_small_text(path, limit):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        return None, f"cannot be read: {error.strerror or error}"
    try:
        data, error = get_regular_bytes(fd, limit)
    except OSError as error:
        return None, f"cannot be read: {error.strerror or error}"
    finally:
        os.close(fd)
    if error:
        return None, error
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError:
        return None, "is not UTF-8"


def is_same_file(a, b):
    try:
        return os.path.samestat(os.stat(a), os.stat(b))
    except (OSError, ValueError):
        return False
