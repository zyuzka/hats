"""Commands, the Claude process of this hook and its working folder.

Part of handoff.py, which holds the contract of the whole hook."""
import os
import signal
import subprocess
import time

from handoff_clock import testing, time_left
from handoff_consts import ANCESTOR_LIMIT, CALL_TIMEOUT_S


def run(cmd, timeout):
    if timeout <= 0:
        return None, None
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(LC_ALL="C", TZ="UTC")
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True, env=env, start_new_session=True)
    except OSError:
        return None, None
    try:
        out, _ = proc.communicate(timeout=max(0.05, timeout))
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.stdout.close()
        proc.wait()
        return None, None
    return proc.returncode, out


def process_start(pid, until=None):
    timeout = time_left(CALL_TIMEOUT_S)
    if until is not None:
        timeout = min(timeout, until - time.monotonic())
    code, out = run(["ps", "-o", "lstart=", "-p", str(pid)], timeout)
    if code is None:
        return "unknown", None
    started = " ".join((out or "").split())
    if code == 0 and started:
        return "ok", started
    if code == 1 and not started:
        return "absent", None
    return "unknown", None


def claude_process():
    override = os.environ.get("HANDOFF_PROCESS")
    if override and testing():
        pid, _, started = override.partition(":")
        return int(pid), " ".join(started.split())
    hinted = os.environ.get("CLAUDE_PID", "")
    hint = int(hinted) if hinted.isascii() and hinted.isdigit() and len(hinted) <= 10 else None
    pid = os.getppid()
    for _ in range(ANCESTOR_LIMIT):
        if pid <= 1:
            return None
        if pid == hint:
            status, started = process_start(pid)
            return (pid, started) if status == "ok" else None
        code, out = run(["ps", "-o", "ppid=,comm=", "-p", str(pid)], time_left(CALL_TIMEOUT_S))
        parts = (out or "").strip().split(None, 1)
        if code != 0 or len(parts) < 2:
            return None
        if os.path.basename(parts[1].strip()) == "claude":
            status, started = process_start(pid)
            return (pid, started) if status == "ok" else None
        pid = int(parts[0])
    return None


def find_work_folder(given, proc):
    if given:
        return os.path.realpath(os.path.expanduser(given))
    found = process_cwd(proc[0]) if proc else None

    return os.path.realpath(found or os.getcwd())


def process_cwd(pid):
    proc = os.environ.get("HANDOFF_TEST_PROC", "/proc") if testing() else "/proc"
    try:
        target = os.readlink(os.path.join(proc, str(pid), "cwd"))
        if target:
            return target
    except OSError:
        pass
    code, out = run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], CALL_TIMEOUT_S)
    for line in (out or "").splitlines() if code == 0 else ():
        if line.startswith("n"):
            return line[1:]
    return None


def liveness(marker):
    status, started = process_start(marker["pid"])
    if status == "unknown":
        return "unknown"
    if status == "ok" and started == marker["started"]:
        return "alive"
    return "closed"


def get_pid_state(pid, until):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return "gone", None
    except (OverflowError, ValueError):
        return "gone", None
    except OSError:
        pass
    if time.monotonic() >= until:
        return "unknown", None

    return process_start(pid, until)


def get_verdict(state, reader):
    status, started = state
    if status == "gone":
        return "dead"
    if status == "ok":
        return "alive" if started == reader["started"] else "dead"

    return "unknown"
