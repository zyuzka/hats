"""Where the notes, the state and the memory folders are, and which note paths are allowed.

Part of handoff.py, which holds the contract of the whole hook."""
import hashlib
import os

from handoff_consts import NOTES_NAME, NOTES_ROOT, PROJECT_FOLDER_LENGTH, PROJECT_NAME, SERVICE_NAMES
from handoff_files import is_same_folder, is_same_place, usable
from handoff_proc import claude_process, find_work_folder
from hats_common import get_state_root


def config_root():
    custom = os.environ.get("CLAUDE_CONFIG_DIR")
    if usable(custom) and os.path.isabs(os.path.expanduser(custom)):
        return os.path.expanduser(custom)
    return os.path.join(os.path.expanduser("~"), ".claude")


def state_dir():
    return os.path.join(config_root(), "state", "handoff")


def memory_root():
    return os.path.realpath(os.path.join(config_root(), "projects"))


def get_notes_root():
    root = get_state_root()

    return None if root is None else os.path.join(root, NOTES_NAME)


def get_cited_notes_roots():
    roots = [get_notes_root(), os.path.expanduser(NOTES_ROOT)]

    return list(dict.fromkeys(root for root in roots if root is not None))


def get_project_folder(cwd):
    try:
        real = os.fsencode(os.path.realpath(cwd))
    except ValueError:
        return None

    return hashlib.sha256(real).hexdigest()[:PROJECT_FOLDER_LENGTH]


def in_memory(real):
    root = memory_root() + os.sep
    if not real.startswith(root):
        return False
    parts = real[len(root):].split(os.sep)
    return len(parts) == 3 and parts[1] == "memory"


def cite_in_memory(real):
    if in_memory(real):
        return True
    folder = os.path.dirname(real)
    project = os.path.dirname(folder)
    try:
        projects = os.stat(memory_root())
        memory = os.stat(os.path.join(project, "memory"))
    except (OSError, ValueError):
        return False
    return is_same_folder(os.path.dirname(project), projects) and is_same_folder(folder, memory)


def note_in_memory(path):
    lexical = os.path.normpath(os.path.abspath(os.path.expanduser(path)))
    real = os.path.realpath(lexical)
    if in_memory(real):
        return real
    folder = os.path.dirname(lexical)
    if os.path.basename(folder) != "memory":
        return None
    if os.path.realpath(os.path.dirname(os.path.dirname(folder))) != memory_root():
        return None
    if os.path.dirname(real) != os.path.realpath(folder):
        return None
    return lexical


def is_own_note(real, folder):
    root = get_notes_root()

    return (
        root is not None
        and os.path.dirname(real) == os.path.join(os.path.realpath(root), folder)
        and real.endswith(".md")
        and os.path.isfile(real)
    )


def find_own_note(path, cwd):
    folder = get_project_folder(cwd)
    if folder is None:
        return None
    real = os.path.realpath(os.path.expanduser(path))

    return real if is_own_note(real, folder) else None


def is_service_name(path):
    return os.path.basename(path).lower() in SERVICE_NAMES


def allowed_note(path, cwd):
    if not usable(path) or is_service_name(path):
        return None
    kept = find_allowed_note(path, cwd)
    if kept is None or is_service_name(os.path.realpath(kept)):
        return None

    return kept


def find_allowed_note(path, cwd):
    kept = note_in_memory(path)
    if kept is None:
        return find_own_note(path, cwd)
    real = os.path.realpath(kept)
    return kept if kept.endswith(".md") and real.endswith(".md") and os.path.isfile(real) else None


def is_memory_folder(folder):
    real = os.path.realpath(folder)

    return (
        os.path.isabs(folder)
        and os.path.basename(real) == "memory"
        and os.path.dirname(os.path.dirname(real)) == memory_root()
        and os.path.isdir(real)
    )


def is_in_notes_folder(real):
    roots = []
    for path in get_cited_notes_roots():
        try:
            roots.append(os.stat(path))
        except OSError:
            continue
    folders = [os.path.dirname(real)]
    while folders[-1] != os.path.dirname(folders[-1]):
        folders.append(os.path.dirname(folders[-1]))

    return any(is_same_folder(folder, root) for folder in folders for root in roots)


def is_note_place(path):
    name = os.path.basename(path)
    if not name.lower().endswith(".md") or is_service_name(name):
        return False
    folder = os.path.dirname(os.path.normpath(path))
    in_memory_folder = os.path.basename(folder).lower() == "memory"
    if in_memory_folder and is_same_place(os.path.dirname(os.path.dirname(folder)), memory_root()):
        return True

    root = get_notes_root()

    return root is not None and is_same_place(os.path.dirname(folder), root)


def is_notes_file(path):
    real = os.path.realpath(path)
    folder = os.path.dirname(real)
    notes = get_notes_root()
    if notes is None:
        return False
    try:
        root = os.stat(os.path.realpath(notes))
    except (OSError, ValueError):
        return False

    return (
        path.endswith(".md")
        and real.endswith(".md")
        and PROJECT_NAME.fullmatch(os.path.basename(folder)) is not None
        and os.path.isdir(folder)
        and is_same_folder(os.path.dirname(folder), root)
        and not os.path.isdir(real)
    )


def is_single_link(real):
    try:
        return os.lstat(real).st_nlink == 1
    except FileNotFoundError:
        return True
    except (OSError, ValueError):
        return False


def is_own_project_file(real):
    folder = get_project_folder(find_work_folder(None, claude_process()))

    return folder is not None and os.path.basename(os.path.dirname(real)) == folder and is_single_link(real)
