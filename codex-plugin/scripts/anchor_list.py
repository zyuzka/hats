#!/usr/bin/env python3
"""Shows a new Codex session the anchors of closed sessions in its folder, the list Claude Code shows.

Runs on SessionStart with the source startup (the matcher in hooks.json; the source is checked here too).
Codex fires it with the user's first message, not when the window opens (measured 2026-11-20, Codex
0.170.0). The list is built only by the Claude plugin of Hats, the one that writes the anchors: this hook
runs its `handoff.py list --cwd <cwd>` and passes its output on as it is — systemMessage, which Codex shows
as `↳ Hook · <text>`, and hookSpecificOutput.additionalContext, which reaches the model.

Where handoff.py is: <config>/plugins/installed_plugins.json, entry "hats@hats", the first install of scope
user or of a project whose folder is the session's folder; <config> is $CLAUDE_CONFIG_DIR when it is an
absolute path, else ~/.claude. The plugin counts as switched off by the first explicit true or false for
"hats@hats" in enabledPlugins of <cwd>/.claude/settings.local.json, then <cwd>/.claude/settings.json, then
<config>/settings.json, as Claude Code reads them; disableAllHooks true in any of those three files stops it
as it stops Claude Code's own hooks. The entry counts only when the marketplace "hats" in
<config>/plugins/known_marketplaces.json comes from GitHub zyuzka/hats or from a folder (a developer's
install) — the rule the app applies — so a plugin of the same name from elsewhere is never run. The real
path of <installPath>/scripts/handoff.py must lie inside the real <config>/plugins/cache and be a regular file of this user; anything else is refused and
never run. It runs as `python3 -I`, stdin closed, in a process group of its own, for at most 6 seconds (the
list keeps to 3.5 seconds after its own start-up); past that the group is killed and its pipes closed
unread. The child gets the environment without HANDOFF_PROCESS and HANDOFF_TEST*, so nothing there
stretches its budget. HANDOFF_OFF=1 silences the hook before anything runs.

It never fails a turn: whatever goes wrong, it prints nothing, exits 0 and writes one journal line
(hats_codex.journal) — bad-input, handoff-off, no-claude-plugin, foreign-plugin, claude-plugin-off,
hooks-off, refused-path,
no-list-command (a Claude plugin older than `list`), list-failed, timeout, bad-output, no-output,
bad-session, bad-cwd, failed. A list passed on is `shown`, journalled after it is written. `shown` and
`timeout` carry ms, the whole run of list.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hats_codex as hats

SCRIPT = "anchor_list"
EVENT = "SessionStart"
PLUGIN = "hats@hats"
MARKETPLACE = "hats"
REPOSITORY = "zyuzka/hats"
LIST_TIMEOUT_S = 6.0
CHILD_DROPPED = ("HANDOFF_PROCESS",)
CHILD_DROPPED_PREFIX = "HANDOFF_TEST"
FILE_LIMIT = 1024 * 1024
OUTPUT_KEYS = {"systemMessage", "hookSpecificOutput"}


class Refused(Exception):
    def __init__(self, outcome, **details):
        super().__init__(outcome)
        self.outcome = outcome
        self.details = details


def get_config_root():
    custom = os.environ.get("CLAUDE_CONFIG_DIR")
    if custom and "\x00" not in custom and os.path.isabs(os.path.expanduser(custom)):
        return os.path.expanduser(custom)
    return os.path.join(os.path.expanduser("~"), ".claude")


def is_inside(path, folder):
    return path.startswith(folder.rstrip(os.sep) + os.sep)


def find_install(config, cwd):
    data = hats.read_json(os.path.join(config, "plugins", "installed_plugins.json"), FILE_LIMIT)
    entries = data.get("plugins", {}).get(PLUGIN) if data is not None and isinstance(data.get("plugins"), dict) else None
    if not isinstance(entries, list):
        raise Refused("no-claude-plugin")
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("installPath"), str):
            continue
        project = entry.get("projectPath")
        if entry.get("scope") == "user" or (isinstance(project, str) and os.path.realpath(project) == os.path.realpath(cwd)):
            return entry["installPath"]
    raise Refused("no-claude-plugin")


def is_marketplace_ours(config):
    data = hats.read_json(os.path.join(config, "plugins", "known_marketplaces.json"), FILE_LIMIT)
    entry = data.get(MARKETPLACE) if data is not None else None
    source = entry.get("source") if isinstance(entry, dict) else None
    if not isinstance(source, dict):
        return False
    repo = source.get("repo")
    if source.get("source") == "github":
        return isinstance(repo, str) and repo.lower() == REPOSITORY

    return source.get("source") == "directory"


def get_settings_paths(config, cwd):
    return (
        os.path.join(cwd, ".claude", "settings.local.json"),
        os.path.join(cwd, ".claude", "settings.json"),
        os.path.join(config, "settings.json"),
    )


def has_hooks_disabled(config, cwd):
    for path in get_settings_paths(config, cwd):
        settings = hats.read_json(path, FILE_LIMIT)
        if settings is not None and settings.get("disableAllHooks") is True:
            return True

    return False


def is_switched_off(config, cwd):
    for path in get_settings_paths(config, cwd):
        settings = hats.read_json(path, FILE_LIMIT)
        plugins = settings.get("enabledPlugins") if settings is not None else None
        if isinstance(plugins, dict) and isinstance(plugins.get(PLUGIN), bool):
            return not plugins[PLUGIN]

    return False


def get_child_environment():
    return {
        name: value
        for name, value in os.environ.items()
        if name not in CHILD_DROPPED and not name.startswith(CHILD_DROPPED_PREFIX)
    }


def get_script(config, install):
    if "\x00" in install or not os.path.isabs(install):
        raise Refused("refused-path", reason="installPath not absolute")
    cache = os.path.realpath(os.path.join(config, "plugins", "cache"))
    real = os.path.realpath(os.path.join(install, "scripts", "handoff.py"))
    if not is_inside(real, cache):
        raise Refused("refused-path", reason="outside plugins/cache")
    try:
        info = os.lstat(real)
    except OSError:
        raise Refused("no-claude-plugin", reason="no handoff.py")
    if not stat.S_ISREG(info.st_mode):
        raise Refused("refused-path", reason="not a regular file")
    if info.st_uid != os.getuid():
        raise Refused("refused-path", reason="another owner")
    return real


def get_ms(began):
    return int((time.monotonic() - began) * 1000)


def run_list(script, cwd):
    began = time.monotonic()
    proc = subprocess.Popen(
        [sys.executable, "-I", script, "list", "--cwd", cwd],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        env=get_child_environment(),
    )
    try:
        out, err = proc.communicate(timeout=LIST_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.stdout.close()
        proc.stderr.close()
        proc.wait()
        raise Refused("timeout", ms=get_ms(began))
    if proc.returncode == 2 and b"invalid choice" in err:
        raise Refused("no-list-command")
    if proc.returncode != 0:
        raise Refused("list-failed", code=proc.returncode, stderr=err.decode("utf-8", "replace")[-300:])
    return out, get_ms(began)


def is_answer(value):
    if not isinstance(value, dict) or not value or not set(value) <= OUTPUT_KEYS:
        return False
    if "systemMessage" in value and not isinstance(value["systemMessage"], str):
        return False
    context = value.get("hookSpecificOutput")
    if context is None:
        return "hookSpecificOutput" not in value
    return (
        isinstance(context, dict)
        and set(context) == {"hookEventName", "additionalContext"}
        and context["hookEventName"] == EVENT
        and isinstance(context["additionalContext"], str)
    )


def check_output(out):
    try:
        value = json.loads(out.decode("utf-8"))
    except (ValueError, RecursionError):
        raise Refused("bad-output")
    if not is_answer(value):
        raise Refused("bad-output")
    return value


def run(data):
    if data.get("hook_event_name") != EVENT or data.get("source") != "startup":
        return None
    if not hats.is_session(data.get("session_id")):
        raise Refused("bad-session")
    cwd = data.get("cwd")
    if not isinstance(cwd, str) or "\x00" in cwd or not os.path.isabs(cwd) or not os.path.isdir(cwd):
        raise Refused("bad-cwd")
    if os.environ.get("HANDOFF_OFF") == "1":
        raise Refused("handoff-off")
    config = get_config_root()
    install = find_install(config, cwd)
    if not is_marketplace_ours(config):
        raise Refused("foreign-plugin")
    if is_switched_off(config, cwd):
        raise Refused("claude-plugin-off")
    if has_hooks_disabled(config, cwd):
        raise Refused("hooks-off")
    out, ms = run_list(get_script(config, install), cwd)
    if not out.strip():
        raise Refused("no-output")
    value = check_output(out)
    return out, {"user": "systemMessage" in value, "model": "hookSpecificOutput" in value, "ms": ms}


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
        if not isinstance(data, dict):
            raise Refused("bad-input")
        answer = run(data)
        if answer is not None:
            sys.stdout.buffer.write(answer[0])
            sys.stdout.buffer.flush()
            hats.journal(SCRIPT, EVENT, "shown", **answer[1])
    except Refused as refused:
        hats.journal(SCRIPT, EVENT, refused.outcome, **refused.details)
    except Exception as error:
        hats.journal(SCRIPT, EVENT, "failed", error=type(error).__name__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
