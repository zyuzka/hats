#!/usr/bin/env python3
"""The user's own steps for the anchor skill: the ones it runs before its core and the ones after it.

  anchor-steps.py [--cwd <folder>]

Two optional files, each a JSON object with the lists "before" and "after":
  <Hats folder>/anchor-steps.json                        general, beside the notes folder
  <working folder>/.claude/anchor-steps.json              the project's own
<Hats folder> is $HATS_STATE_HOME when it is an absolute path as written (no ~ is expanded),
~/Library/Application Support/Hats when it is empty or not set: the folder above handoff.py's notes
root. Any other value, a relative path included, leaves no Hats folder: then the script prints one
line "anchor-steps: HATS_STATE_HOME=<value> is not an absolute path, so there is no Hats folder" and
exits 1.
The general file may also hold "projects", a list of absolute paths (trimmed, a leading ~ expanded).
The project file counts only when the working folder is the same folder as one of them, compared by
device and inode, so a link, ~ or another letter case still match and a path that cannot be read
does not: steps are each user's own, so a repository brings none by itself (user, 2026-11-12). In
both lists the general steps come first. JSON and not TOML: the system Python 3.9 reads no TOML.

A step is a string, trimmed, without a control, format or line-break character, up to 500 characters,
and up to 20 in a list. "skill:<name>" (the prefix in any letter case; the name letters, digits, ".",
"_", "-", ":") is a call of that skill, anything else an instruction. "skill:anchor" and
"skill:hats:anchor", in any letter case, are dropped and named: the skill would call itself. A call
of anchor through another skill or an instruction is left to the skill's own rule.

Both files may hold "note", who writes the resume note: "anchor", the skill itself, or "steps", an own
step before the core that prints "resume note: <absolute path>". The value is exactly one of the two,
letter case and spaces included. The project file's value, when that file counts, wins over the
general one; with "note" nowhere the owner is anchor.

A file that is not a regular file, cannot be read, is over 16 KB, is not UTF-8 (a leading BOM is
fine), is not JSON or has another shape, a wrong "note" included, is skipped whole, named with the
reason; the other file still counts, and a skipped general file marks no project. The output is
English: "no own steps", or the two numbered lists with the source of each step, then one line per
skipped file or dropped step, and a line naming why project steps were skipped: no general file, a
skipped one, or a folder not in its projects. With the owner "steps" the first line is
"note: written by own steps", "no own steps" is never printed, and when no before step is left after
the dropped ones the second line is "note: no before step to write it"; with "anchor" there is no
"note:" line. Every line is printed with those characters escaped. The exit code is 0 whatever the files
hold, 2 for a wrong argument, and 1 with one line "anchor-steps: <type>: <message>" for an error of
the script itself.

The working folder comes from handoff.py, as for `where` and `save`: --cwd, else the folder of the
Claude process, else this command's own. The folder of this script goes onto sys.path by hand, since
python3 -I leaves it out, and no bytecode is written into the plugin.
"""
import argparse
import json
import os
import re
import sys
import unicodedata

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

import handoff
import handoff_files
from hats_common import STATE_HOME

FILE_NAME = "anchor-steps.json"
SIZE_LIMIT = 16 * 1024
STEP_LIMIT = 20
LENGTH_LIMIT = 500
LISTS = (
    "before",
    "after",
)
PROJECTS = "projects"
NOTE = "note"
ANCHOR = "anchor"
STEPS = "steps"
OWNERS = (
    ANCHOR,
    STEPS,
)
GENERAL_KEYS = (
    *LISTS,
    NOTE,
    PROJECTS,
)
PROJECT_KEYS = (
    *LISTS,
    NOTE,
)
SKILL = "skill:"
SKILL_NAME = re.compile(r"[A-Za-z0-9._:-]+")
ITSELF = {
    "anchor",
    "hats:anchor",
}
FORBIDDEN = {
    "Cc",
    "Cf",
    "Cs",
    "Zl",
    "Zp",
}
BOM = b"\xef\xbb\xbf"


class Skipped(Exception):
    pass


class Pairs(list):
    pass


def get_type(value):
    if isinstance(value, Pairs):
        return "an object"
    if isinstance(value, list):
        return "an array"
    if isinstance(value, str):
        return "a string"
    if isinstance(value, bool):
        return "a boolean"
    if value is None:
        return "null"

    return "a number"


def find_forbidden(text):
    return next((ch for ch in text if unicodedata.category(ch) in FORBIDDEN), None)


def get_clean(line):
    return "".join("\\u%04x" % ord(ch) if unicodedata.category(ch) in FORBIDDEN else ch for ch in line)


def is_absent(path):
    try:
        os.lstat(path)
    except (FileNotFoundError, NotADirectoryError):
        return True
    except OSError:
        return False

    return False


def get_bytes(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError as error:
        raise Skipped(f"cannot be read: {error.strerror or error}") from None
    try:
        data, reason = handoff_files.get_regular_bytes(fd, SIZE_LIMIT)
    except OSError as error:
        raise Skipped(f"cannot be read: {error.strerror or error}") from None
    finally:
        os.close(fd)
    if data is None:
        raise Skipped("not a regular file" if reason == handoff_files.NOT_REGULAR else f"larger than {SIZE_LIMIT} bytes")

    return data


def get_document(data):
    skip = len(BOM) if data.startswith(BOM) else 0
    try:
        text = data[skip:].decode("utf-8")
    except UnicodeDecodeError as error:
        raise Skipped(f"not UTF-8: byte 0x{data[skip + error.start]:02x} at offset {skip + error.start}") from None
    try:
        return json.loads(text, object_pairs_hook=Pairs)
    except (ValueError, RecursionError) as error:
        raise Skipped(f"not JSON: {error}") from None


def get_fields(document, keys):
    if not isinstance(document, Pairs):
        raise Skipped(f"the top level is {get_type(document)}, not an object")
    fields = {}
    for key, value in document:
        if key not in keys:
            raise Skipped(f"key {json.dumps(key, ensure_ascii=False)} is not one of {', '.join(keys)}")
        if key in fields:
            raise Skipped(f"key {key} is repeated")
        fields[key] = value

    return fields


def get_list(fields, key):
    value = fields.get(key, [])
    if isinstance(value, Pairs) or not isinstance(value, list):
        raise Skipped(f"{key} is {get_type(value)}, not an array")

    return value


def get_string(item, label):
    if not isinstance(item, str):
        raise Skipped(f"{label} is {get_type(item)}, not a string")
    bad = find_forbidden(item)
    if bad:
        raise Skipped(f"{label} holds U+{ord(bad):04X}, a control, format or line-break character")

    return item


def is_skill(step):
    return step[:len(SKILL)].lower() == SKILL


def get_step(item, label):
    step = get_string(item, label).strip()
    if not step:
        raise Skipped(f"{label} is empty")
    if len(step) > LENGTH_LIMIT:
        raise Skipped(f"{label} is {len(step)} characters long, over {LENGTH_LIMIT}")
    if is_skill(step) and not SKILL_NAME.fullmatch(step[len(SKILL):]):
        shown = json.dumps(step, ensure_ascii=False)
        raise Skipped(f'{label} names no skill: {shown}; a skill name is letters, digits, ".", "_", "-" and ":"')

    return step


def get_steps(fields, key):
    items = get_list(fields, key)
    if len(items) > STEP_LIMIT:
        raise Skipped(f"{key} holds {len(items)} steps, over {STEP_LIMIT}")

    return [get_step(item, f"{key}, item {number}") for number, item in enumerate(items, 1)]


def get_project(item, label):
    entry = get_string(item, label).strip()
    if not entry:
        raise Skipped(f"{label} is empty")
    path = os.path.expanduser(entry)
    if not os.path.isabs(path):
        raise Skipped(f"{label} is not an absolute path: {json.dumps(item, ensure_ascii=False)}")

    return path


def get_projects(fields):
    items = get_list(fields, PROJECTS)

    return [get_project(item, f"{PROJECTS}, item {number}") for number, item in enumerate(items, 1)]


def find_owner(fields):
    if NOTE not in fields:
        return None
    value = fields[NOTE]
    if value in OWNERS:
        return value
    shown = json.dumps(value, ensure_ascii=False) if isinstance(value, str) else get_type(value)
    raise Skipped(f'{NOTE} is {shown}, not "{ANCHOR}" or "{STEPS}"')


def find_file(
    path,
    keys,
    notes,
):
    if is_absent(path):
        return None
    try:
        fields = get_fields(get_document(get_bytes(path)), keys)
        found = {key: get_steps(fields, key) for key in LISTS}
        found[NOTE] = find_owner(fields)
        found[PROJECTS] = get_projects(fields)
    except Skipped as reason:
        notes.append(f"skipped {path}: {reason}")
        return None

    return found


def is_anchor_itself(step):
    return is_skill(step) and step[len(SKILL):].lower() in ITSELF


def get_unmarked_reason(general, shared):
    if shared:
        return f"is not in projects of {general}"
    if is_absent(general):
        return f"is not marked: there is no {general}"

    return f"is not marked: {general} was skipped"


def find_kept(
    files,
    key,
    notes,
):
    kept = []
    for label, path, found in files:
        steps = list(enumerate(found[key], 1)) if found else []
        notes.extend(f"dropped {key}, item {n} of {path}: {s} calls anchor itself" for n, s in steps if is_anchor_itself(s))
        kept.extend((label, s) for n, s in steps if not is_anchor_itself(s))

    return kept


def get_owner(files):
    owners = [found[NOTE] for _, _, found in files if found and found[NOTE]]

    return owners[-1] if owners else ANCHOR


def get_lines(
    owner,
    steps,
    notes,
):
    lines = []
    if owner == STEPS:
        lines.append("note: written by own steps")
        if not steps["before"]:
            lines.append("note: no before step to write it")
    elif not any(steps.values()) and not notes:
        return [
            "no own steps",
        ]
    for key in LISTS:
        lines.append(f"{key} anchor:" if steps[key] else f"{key} anchor: none")
        lines.extend(f"{number}. [{label}] {step}" for number, (label, step) in enumerate(steps[key], 1))

    return lines + notes


def print_steps(given):
    notes_root = handoff.get_notes_root()
    if notes_root is None:
        custom = os.environ.get(STATE_HOME)
        print(get_clean(f"anchor-steps: {STATE_HOME}={custom!r} is not an absolute path, so there is no Hats folder"))
        return 1
    cwd = handoff.find_work_folder(given, None if given else handoff.claude_process())
    general = os.path.join(os.path.dirname(notes_root), FILE_NAME)
    project = os.path.join(
        cwd,
        ".claude",
        FILE_NAME,
    )
    notes = []
    shared = find_file(
        general,
        GENERAL_KEYS,
        notes,
    )
    files = [
        (
            "general",
            general,
            shared,
        ),
    ]
    if shared and any(handoff_files.is_same_file(cwd, path) for path in shared[PROJECTS]):
        files.append((
            "project",
            project,
            find_file(
                project,
                PROJECT_KEYS,
                notes,
            ),
        ))
    elif not is_absent(project):
        notes.append(f"project steps skipped: {cwd} {get_unmarked_reason(general, shared)}")
    steps = {
        key: find_kept(
            files,
            key,
            notes,
        )
        for key in LISTS
    }
    for line in get_lines(
        get_owner(files),
        steps,
        notes,
    ):
        print(get_clean(line))

    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog="anchor-steps.py", description="Prints the own steps of the anchor skill.")
    parser.add_argument("--cwd")
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(errors="backslashreplace")
    try:
        return print_steps(args.cwd)
    except Exception as error:
        print(get_clean(f"anchor-steps: {type(error).__name__}: {error}"))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
