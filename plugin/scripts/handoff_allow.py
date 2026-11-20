"""The allow hook: Write, Edit and Read of a note in the notes folder go without a prompt.

Part of handoff.py, which holds the contract of the whole hook."""
import os
import sys

from handoff_consts import ALLOW_REASON, ALLOW_TOOLS, WRITE_TOOLS
from handoff_files import usable
from handoff_paths import is_notes_file, is_own_project_file
from handoff_text import get_json_bytes
from handoff_took import get_took_input


def is_allowed_input(data):
    tool_input = data.get("tool_input")
    path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if data.get("hook_event_name") != "PreToolUse" or data.get("tool_name") not in ALLOW_TOOLS:
        return False
    if not usable(path) or not os.path.isabs(path) or not is_notes_file(path):
        return False

    return data["tool_name"] not in WRITE_TOOLS or is_own_project_file(os.path.realpath(path))


def cmd_allow():
    if os.environ.get("HANDOFF_OFF") == "1":
        return 0
    try:
        data = get_took_input()
        if data is None or not is_allowed_input(data):
            return 0
        sys.stdout.buffer.write(get_json_bytes({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": ALLOW_REASON,
            },
        }))
        sys.stdout.buffer.flush()
    except Exception:
        return 0

    return 0
