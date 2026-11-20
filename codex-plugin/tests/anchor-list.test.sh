#!/usr/bin/env bash
# Matrix for anchor_list.py, the Codex startup hook that shows the anchors of closed sessions in the
# folder — the list the Claude plugin's handoff.py builds. The Claude config is made up in a temporary
# folder: installed_plugins.json points at a copy of plugin/ from this repository inside plugins/cache.
#   bash codex-plugin/tests/anchor-list.test.sh
#   PATH="/usr/bin:$PATH" bash codex-plugin/tests/anchor-list.test.sh      # under the system Python
set -uo pipefail
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$plugin_root/.." && pwd)"
HOOK="$plugin_root/scripts/anchor_list.py"
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_PID HANDOFF_OFF HANDOFF_TEST
pass=0; fail=0; failures=""; skipped=""
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-anchor-list-test.XXXXXX")
trap 'kill $(cat "$work"/*.pid 2>/dev/null) 2>/dev/null; rm -rf "$work"' EXIT INT TERM
work=$(cd "$work" && pwd -P)

home="$work/home"
cfg="$work/claude"
state="$work/state"
cache="$cfg/plugins/cache"
real_plugin="$cache/hats/hats/0.2.0"
proj="$work/proj"
mem="$cfg/projects/p/memory"
note="$mem/note.md"
markers="$cfg/state/handoff"
journal="$state/codex-hooks.log"
sid="019a1f04-577c-7210-a55d-85432c05d145"
dead_started="Thu Jan  1 00:00:00 2026"
mkdir -p "$home" "$state" "$proj" "$mem" "$markers" "$real_plugin"
cp -R "$repo_root/plugin/scripts" "$repo_root/plugin/hooks" "$repo_root/plugin/.claude-plugin" "$real_plugin/"
printf '# Note\n\n## NOW\n\nthe line of now\n' >"$note"

ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }
equal() { if [ "$2" = "$3" ]; then ok; else bad "$1" "expected «${3:0:400}», got «${2:0:400}»"; fi; }
has() { case $2 in *"$3"*) ok ;; *) bad "$1" "no «$3» in: ${2:0:400}" ;; esac; }

installed() {  # installed <installPath> [scope] — installed_plugins.json with one entry hats@hats
  python3 -I -c 'import json,sys; json.dump({"version": 2, "plugins": {"hats@hats": [{"scope": sys.argv[3], "installPath": sys.argv[2]}]}}, open(sys.argv[1], "w"))' \
    "$cfg/plugins/installed_plugins.json" "$1" "${2:-user}"
}
marker() {  # marker <pid> <topic> — a marker of a closed session in proj
  python3 -I -c 'import json,sys,time; json.dump({"pid": int(sys.argv[2]), "started": sys.argv[3], "cwd": sys.argv[4], "note": sys.argv[5], "topic": sys.argv[6], "saved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}, open(sys.argv[1], "w"), ensure_ascii=False)' \
    "$markers/$1.json" "$1" "$dead_started" "$proj" "$note" "$2"
}
fake() {  # fake <name> <python body> — a plugin in cache whose handoff.py is the body; prints its installPath
  mkdir -p "$cache/fake/$1/scripts"
  printf 'import os, sys, time\n%s\n' "$2" >"$cache/fake/$1/scripts/handoff.py"
  printf '%s' "$cache/fake/$1"
}
input() {  # input [source] [cwd] [session]
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "${3-$sid}" "${2-$proj}" "${1:-startup}"
}
run_hook() {  # run_hook <input> [env...] — stdout and stderr of the hook, then rc=<code>
  local data="$1"; shift
  printf '%s' "$data" | env HOME="$home" CLAUDE_CONFIG_DIR="$cfg" HATS_STATE_HOME="$state" "$@" python3 -I "$HOOK" 2>&1; echo "rc=$?"
}
run_start() {  # run_start [cwd] — what the Claude plugin's start prints on startup in that folder
  printf '{"session_id":"%s","cwd":"%s","source":"startup"}' "$sid" "${1:-$proj}" |
    env HOME="$home" CLAUDE_CONFIG_DIR="$cfg" HATS_STATE_HOME="$state" CLAUDE_CODE_SESSION_ATTENDED=1 \
      python3 -I "$real_plugin/scripts/handoff.py" start 2>&1; echo "rc=$?"
}
last_outcome() { python3 -I -c 'import json,sys
lines = open(sys.argv[1]).read().splitlines()
print(json.loads(lines[-1])["outcome"] if lines else "<none>")' "$journal" 2>/dev/null || echo "<none>"; }
silent() {  # silent <name> <output> <outcome> — no output, code 0, one journal line with the outcome
  equal "$1: silent, code 0" "$2" "rc=0"
  equal "$1: journal" "$(last_outcome)" "$3"
}
fields() { printf '%s' "${1%rc=0}" | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.read()); print("user=%d model=%d" % ("systemMessage" in d, "hookSpecificOutput" in d))' 2>/dev/null; }

# 1. Anchors: the same bytes as start of the Claude plugin on startup.
installed "$real_plugin"; marker 99990 "closed task"
out=$(run_hook "$(input)"); expected=$(run_start)
equal "anchors: same output as start on startup" "$out" "$expected"
has "anchors: the topic reaches the list" "$out" "closed task"
equal "anchors: a line for the user and text for the model" "$(fields "$out")" "user=1 model=1"
equal "anchors: journal" "$(last_outcome)" "shown"

# 2. No anchors: what start prints in that case.
rm -f "$markers"/*.json
out=$(run_hook "$(input)"); expected=$(run_start)
equal "no anchors: same output as start on startup" "$out" "$expected"
has "no anchors: the line of start" "$out" "no notes from closed sessions in this folder"

# 3. Another source: silent, nothing run.
marker 99990 "closed task"; : >"$journal"
equal "source clear: silent" "$(run_hook "$(input clear)")" "rc=0"
equal "source compact: silent" "$(run_hook "$(input compact)")" "rc=0"
equal "another source: no journal line" "$(last_outcome)" "<none>"

# 4. No Claude plugin.
rm -f "$cfg/plugins/installed_plugins.json"
silent "no installed_plugins.json" "$(run_hook "$(input)")" no-claude-plugin
printf '{"version":2,"plugins":{"other@x":[{"scope":"user","installPath":"%s"}]}}' "$real_plugin" >"$cfg/plugins/installed_plugins.json"
silent "no hats@hats entry" "$(run_hook "$(input)")" no-claude-plugin
installed "$real_plugin" project
silent "project install of another folder" "$(run_hook "$(input)")" no-claude-plugin

# 5. The Claude plugin switched off.
installed "$real_plugin"
printf '{"enabledPlugins":{"hats@hats":false}}' >"$cfg/settings.json"
silent "plugin switched off" "$(run_hook "$(input)")" claude-plugin-off
printf '{"enabledPlugins":{"hats@hats":true}}' >"$cfg/settings.json"
has "plugin switched on: listed" "$(run_hook "$(input)")" "closed task"
rm -f "$cfg/settings.json"

# 6. A Claude plugin older than list: argparse refuses the command with code 2.
installed "$(fake old 'import argparse
p = argparse.ArgumentParser(); c = p.add_subparsers(dest="command", required=True); c.add_parser("start")
p.parse_args(sys.argv[1:])')"
silent "old plugin without list" "$(run_hook "$(input)")" no-list-command

# 7. A path that is not the plugin's own: refused, never run.
pwned="$work/PWNED"
mkdir -p "$work/elsewhere/scripts"
printf 'open(%s, "w").write("x")\n' "'$pwned'" >"$work/elsewhere/scripts/handoff.py"
installed "$work/elsewhere"
silent "installPath outside plugins/cache" "$(run_hook "$(input)")" refused-path
mkdir -p "$cache/linked/scripts"; ln -s "$work/elsewhere/scripts/handoff.py" "$cache/linked/scripts/handoff.py"
installed "$cache/linked"
silent "handoff.py a link out of plugins/cache" "$(run_hook "$(input)")" refused-path
ln -s "$work/elsewhere" "$cache/folderlink"
installed "$cache/folderlink"
silent "installPath a link out of plugins/cache" "$(run_hook "$(input)")" refused-path
installed "$cache/hats/hats/0.2.0/../../../../../elsewhere"
silent "installPath climbing out with .." "$(run_hook "$(input)")" refused-path
mkdir -p "$cache/dir/scripts/handoff.py"
installed "$cache/dir"
silent "handoff.py not a regular file" "$(run_hook "$(input)")" refused-path
installed "hats/hats/0.2.0"
silent "installPath relative" "$(run_hook "$(input)")" refused-path
if [ ! -e "$pwned" ]; then ok; else bad "refused paths: the script outside was never run" "$pwned exists"; fi
skipped="$skipped
  handoff.py of another owner: needs root to make, not checked here"

# 8. Past 4 seconds: the process group is killed, silent.
installed "$(fake slow "open(os.environ['SLOW_PID'], 'w').write(str(os.getpid()))
time.sleep(30)")"
began=$(date +%s)
out=$(run_hook "$(input)" SLOW_PID="$work/slow.pid"); took=$(( $(date +%s) - began ))
silent "list past its time" "$out" timeout
if [ "$took" -le 7 ]; then ok; else bad "timeout: the hook returns soon after 4 s" "took ${took} s"; fi
slow=$(cat "$work/slow.pid" 2>/dev/null)
if [ -n "$slow" ] && ! kill -0 "$slow" 2>/dev/null; then ok; else bad "timeout: the list process is killed" "pid «$slow» alive"; fi

# 9. Output that is not the answer of start: silent.
installed "$(fake text 'print("not json")')"
silent "output not JSON" "$(run_hook "$(input)")" bad-output
installed "$(fake other 'print("{\"other\": 1}")')"
silent "output another object" "$(run_hook "$(input)")" bad-output
event_body='import json; print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "x"}}))'
installed "$(fake event "$event_body")"
silent "output for another event" "$(run_hook "$(input)")" bad-output
installed "$(fake list 'print("[1]")')"
silent "output a JSON list" "$(run_hook "$(input)")" bad-output
installed "$(fake empty 'pass')"
silent "empty output" "$(run_hook "$(input)")" no-output
installed "$(fake crash 'sys.exit(1)')"
silent "list fails" "$(run_hook "$(input)")" list-failed

# 10. A bad hook input: silent, as note_back.py.
installed "$real_plugin"
equal "input not JSON: silent" "$(run_hook 'not json')" "rc=0"
equal "input not JSON: journal" "$(last_outcome)" failed
equal "input not an object: silent" "$(run_hook '[1]')" "rc=0"
silent "bad session id" "$(run_hook "$(input startup "$proj" 'a/b')")" bad-session
silent "relative cwd" "$(run_hook "$(input startup proj)")" bad-cwd
silent "cwd not a folder" "$(run_hook "$(input startup "$work/nope")")" bad-cwd

# 11. Without CLAUDE_CONFIG_DIR the config is ~/.claude.
mkdir -p "$home/.claude/plugins"; cp "$cfg/plugins/installed_plugins.json" "$home/.claude/plugins/"
out=$(printf '%s' "$(input)" | env -u CLAUDE_CONFIG_DIR HOME="$home" HATS_STATE_HOME="$state" python3 -I "$HOOK" 2>&1; echo "rc=$?")
silent "no CLAUDE_CONFIG_DIR: the plugin under ~/.claude/plugins/cache is the only one accepted" "$out" refused-path
rm -rf "$home/.claude"

# 12. The hook writes no bytecode beside itself.
if [ ! -e "$plugin_root/scripts/__pycache__" ]; then ok; else bad "no bytecode beside the hook" "$(ls "$plugin_root/scripts/__pycache__")"; fi

echo "codex anchor list: $pass passed, $fail failed"
if [ -n "$skipped" ]; then printf 'not checked:%s\n' "$skipped"; fi
if [ "$fail" -gt 0 ]; then
  printf '%s\n' "$failures"
  exit 1
fi
