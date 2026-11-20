"""The save markers of sessions, the handed files and whether the handoff is on.

Part of handoff.py, which holds the contract of the whole hook."""
import json
import os
import re
from datetime import datetime, timezone

from handoff_consts import MARKER_FIELDS, SESSION_ID
from handoff_files import usable
from handoff_paths import allowed_note, config_root, state_dir


def checked_markers():
    out = []
    for marker in load_markers():
        kept = allowed_note(marker["note"], marker["cwd"])
        if kept is not None:
            marker["note"] = kept
            out.append(marker)
    return out


def marker_file(pid, started):
    return f"{pid}-{re.sub(r'[^0-9A-Za-z]+', '-', started).strip('-')}.json"


def is_marker_shape(marker):
    return (
        isinstance(marker, dict)
        and all(isinstance(marker.get(k), t) and not isinstance(marker.get(k), bool) for k, t in MARKER_FIELDS.items())
        and all(usable(marker[k]) for k in ("started", "cwd", "note"))
    )


def load_markers():
    folder = state_dir()
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    markers = []
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(folder, name)
        try:
            with open(path, encoding="utf-8") as f:
                marker = json.load(f)
        except (OSError, ValueError, RecursionError):
            continue
        if not is_marker_shape(marker):
            continue
        marker["_path"] = path
        markers.append(marker)
    return markers


def handed_file(marker):
    return marker["_path"][:-len(".json")] + ".handed"


def handed_key(marker):
    return f"{marker['saved_at']}|{marker['note']}"


def handed_session(marker):
    try:
        with open(handed_file(marker), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("key") != handed_key(marker):
        return None
    session = data.get("session")
    return session if isinstance(session, str) else None


def record_handed(marker, session):
    path = handed_file(marker)
    tmp = f"{path}.{os.getpid()}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"key": handed_key(marker), "session": session}, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass


def session_id(data):
    value = data.get("session_id")
    return value if isinstance(value, str) and SESSION_ID.fullmatch(value) else None


def saved_time(marker):
    try:
        return datetime.strptime(marker["saved_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def registered(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return False
    hooks = data.get("hooks") if isinstance(data, dict) else None
    groups = hooks.get("SessionStart") if isinstance(hooks, dict) else None
    for group in groups if isinstance(groups, list) else ():
        entries = group.get("hooks") if isinstance(group, dict) else None
        for entry in entries if isinstance(entries, list) else ():
            command = entry.get("command") if isinstance(entry, dict) else None
            if isinstance(command, str) and "handoff.py" in command and "start" in command:
                return True
    return False


def find_plugin_hooks():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if not os.path.isfile(os.path.join(root, ".claude-plugin", "plugin.json")):
        return ()
    return (
        os.path.join(root, "hooks", "hooks.json"),
    )


def enabled(cwd):
    return any(registered(path) for path in (
        os.path.join(cwd, ".claude", "settings.local.json"),
        os.path.join(cwd, ".claude", "settings.json"),
        os.path.join(config_root(), "settings.json"),
    ) + find_plugin_hooks())
