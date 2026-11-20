"""The save, check, where and new commands.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import os
from datetime import datetime, timezone

from handoff_check import checked_counted, get_verdict_line, problem_lines
from handoff_clock import test_pause
from handoff_consts import MAX_AGE, NAME_TRIES, SLUG, SLUG_LIMIT, SOURCE_SIZE_LIMIT, TOPIC_LIMIT
from handoff_files import read_regular, same_path, usable
from handoff_index import set_index
from handoff_markers import enabled, handed_file, load_markers, marker_file, saved_time
from handoff_paths import allowed_note, get_notes_root, get_project_folder, is_memory_folder, memory_root, state_dir
from handoff_proc import claude_process, find_work_folder, liveness
from hats_common import get_no_root_line, write_text_whole


def cmd_save(args):
    proc = claude_process()
    if not proc:
        print("handoff: no Claude process above this command — marker not written")
        return 1
    pid, started = proc
    cwd = find_work_folder(args.cwd, proc)
    if not enabled(cwd):
        print(f"handoff is off for {cwd} — marker not written")
        return 0
    given = os.path.normpath(os.path.abspath(os.path.expanduser(args.note)))
    note = allowed_note(given, cwd)
    if note is None:
        print(get_refused_note_line(cwd, given))
        return 1
    text = read_regular(note, SOURCE_SIZE_LIMIT)
    if text is None:
        print(f"handoff: could not read the note {note}")
        return 1
    marker = {
        "pid": pid,
        "started": started,
        "cwd": cwd,
        "note": note,
        "topic": " ".join(args.topic.split())[:TOPIC_LIMIT],
        "saved_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    path = os.path.join(state_dir(), marker_file(pid, started))
    try:
        os.makedirs(state_dir(), exist_ok=True)
        write_text_whole(
            state_dir(),
            os.path.basename(path),
            json.dumps(marker, ensure_ascii=False, indent=1),
            before_replace=test_pause,
        )
    except (OSError, ValueError) as error:
        print(f"handoff: marker not written: {error}")
        return 1
    retired = 0
    expired = 0
    now = datetime.now(timezone.utc)
    for other in load_markers():
        if other["_path"] == path:
            continue
        when = saved_time(other)
        old = when is None or now - when > MAX_AGE
        if not (old or same_path(other["note"], note)) or liveness(other) != "closed":
            continue
        try:
            os.remove(other["_path"])
        except OSError:
            continue
        if old:
            expired += 1
        else:
            retired += 1
        try:
            os.remove(handed_file(other))
        except OSError:
            pass
    print(f"marker: {path}")
    if retired:
        print(f"removed markers of closed sessions with the same note: {retired}")
    if expired:
        print(f"removed markers of closed sessions saved more than {MAX_AGE.days} days ago "
              f"or at an unreadable time: {expired}")
    print("\n".join(set_index(note, marker)))
    problems, claims = checked_counted(text, cwd, os.path.realpath(note))
    if problems:
        print("not verified in the note:")
        print("\n".join(problem_lines(problems)))
    else:
        print(get_verdict_line(claims))
    return 0


def get_refused_note_line(cwd, given):
    root = get_notes_root()
    memory = f"<Claude config>/projects/<folder>/memory/<name>.md, and {given} is not; marker not written"
    if root is None:
        return f"{get_no_root_line('handoff')}: the note must be a file {memory}"
    own = os.path.join(root, get_project_folder(cwd))

    return f"handoff: the note must be a file {own}/<name>.md (the folder `where` prints) or {memory}"


def create_notes_folder(cwd):
    root = get_notes_root()
    if root is None:
        return None, get_no_root_line("handoff")
    path = os.path.join(root, get_project_folder(cwd))
    try:
        os.makedirs(root, 0o700, exist_ok=True)
        os.makedirs(path, 0o700, exist_ok=True)
    except OSError as error:
        return None, f"handoff: could not create the notes folder {path}: {error}"

    return path, None


def cmd_where(args):
    cwd = find_work_folder(args.cwd, None if args.cwd else claude_process())
    path, error = create_notes_folder(cwd)
    if error:
        print(error)
        return 1
    print(path)

    return 0


def find_memory_folder(given):
    if not usable(given):
        return None, f"handoff: {given!r} is not an existing memory folder — no note created"
    folder = os.path.expanduser(given)
    if not is_memory_folder(folder):
        return None, (f"handoff: {given!r} is not an existing memory folder: its real path "
                      f"{os.path.realpath(folder)} is not an existing folder {memory_root()}/<project>/memory "
                      f"— no note created")

    return folder, None


def create_note(folder, slug):
    for number in range(1, NAME_TRIES + 1):
        name = f"resume-{slug}.md" if number == 1 else f"resume-{slug}-{number}.md"
        path = os.path.join(folder, name)
        if os.path.lexists(path):
            continue
        test_pause()
        try:
            fd = os.open(
                path,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
            )
            os.close(fd)
        except FileExistsError:
            continue
        except OSError as error:
            return None, f"handoff: could not create the note {path}: {error}"
        return path, None

    return None, f"handoff: resume-{slug}.md and -2 to -{NAME_TRIES} are all taken in {folder} — no note created"


def is_good_slug(slug):
    return (
        SLUG.fullmatch(slug) is not None
        and len(slug) <= SLUG_LIMIT
        and slug != "index"
    )


def cmd_new(args):
    if not is_good_slug(args.slug):
        print(f"handoff: the slug must be lowercase latin letters and digits, words joined by single hyphens, "
              f"up to {SLUG_LIMIT} characters, and not \"index\"; {args.slug!r} is not — no note created")
        return 1
    cwd = find_work_folder(args.cwd, None if args.cwd else claude_process())
    if args.memory is None:
        folder, error = create_notes_folder(cwd)
    else:
        folder, error = find_memory_folder(args.memory)
    if error:
        print(error)
        return 1
    path, error = create_note(folder, args.slug)
    if error:
        print(error)
        return 1
    if allowed_note(path, cwd) != os.path.realpath(path):
        try:
            os.remove(path)
            removed = "removed"
        except OSError as error:
            removed = f"not removed: {error.strerror or error}"
        print(f"handoff: the created note {path} did not pass the note check — {removed}; no note created")
        return 1
    print(path)

    return 0


def cmd_check(args):
    note = os.path.realpath(os.path.expanduser(args.note))
    text = read_regular(note, SOURCE_SIZE_LIMIT)
    if text is None:
        print(f"handoff: could not read {args.note}")
        return 1
    problems, claims = checked_counted(text, os.path.realpath(os.path.expanduser(args.cwd or os.getcwd())), note)
    if not problems:
        print(get_verdict_line(claims))
        return 0
    print("\n".join(problem_lines(problems)))
    return 1
