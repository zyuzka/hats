"""Time left of the hook's run, the test switches and the test pause.

Part of handoff.py, which holds the contract of the whole hook."""
import os
import time

import handoff_state
from handoff_consts import TIME_BUDGET_S


def time_left(default):
    if handoff_state.deadline is None:
        return default
    return max(0.0, min(default, handoff_state.deadline - time.monotonic()))


def out_of_time():
    return handoff_state.deadline is not None and time.monotonic() >= handoff_state.deadline


def testing():
    return os.environ.get("HANDOFF_TEST") == "1"


def time_budget(default=TIME_BUDGET_S):
    if testing() and os.environ.get("HANDOFF_TEST_BUDGET"):
        return float(os.environ["HANDOFF_TEST_BUDGET"])
    return default


def test_pause():
    if testing() and os.environ.get("HANDOFF_TEST_PAUSE"):
        time.sleep(float(os.environ["HANDOFF_TEST_PAUSE"]))
