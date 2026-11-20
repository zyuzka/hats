"""The run state of one hook call, shared by every handoff module.

Read and write it as handoff_state.<name>, never through `from handoff_state import`: such an import
copies the value once and does not see later writes."""
deadline = None
check_errors = []
tell = False
printed = False
