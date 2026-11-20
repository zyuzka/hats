#!/bin/sh
# PreToolUse hook on Write|Edit|Read: hands the input to `handoff.py allow` only when it names a path
# with "/notes/" in it. Every Read, Write and Edit of every session runs this hook, and starting Python
# cost 111-172 ms a call; a note of the notes folder always has "/notes/" in its path, so any other
# input exits 0 here, silently, without Python. handoff.py does the real check.
#   sh allow.sh < hook input
input=$(cat)
case $input in
  *"/notes/"*) ;;
  *) exit 0 ;;
esac
dir=$(dirname "$0")
printf '%s' "$input" | sh "$dir/py.sh" --quiet "$dir/handoff.py" allow
