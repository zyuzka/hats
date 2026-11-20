#!/bin/sh
# Runs `python3 -I` with the remaining arguments, unless no python3 can run here:
#   sh py.sh [--quiet] <script.py> [arguments...]
# On a Mac without the Command Line Tools, /usr/bin/python3 is only a placeholder that opens
# their installer window, and `xcode-select -p` fails. That Python is never started; the check
# runs before it, so no window opens on every session start. The placeholder is recognised as the
# same file, so /usr//bin/python3 or a link to it counts too. Linux, and a python3 found anywhere
# else (Homebrew and the like), run as they always did.
# --quiet is for hooks: when Python cannot run, say nothing, append one JSON line with outcome
# "no-python" to <config>/state/handoff/runs.log (<config> is $CLAUDE_CONFIG_DIR when it is an
# absolute path after ~ is expanded, or else ~/.claude; a failed write is ignored) and exit 0. Without it one English line says python3 is required, and
# the exit code is 1.
# HATS_SYSTEM_PYTHON and HATS_XCODE_SELECT stand in for /usr/bin/python3 and /usr/bin/xcode-select
# in tests, so /usr/bin is never edited.
quiet=
if [ "${1-}" = "--quiet" ]; then
  quiet=1
  shift
fi
script=${1-}
script=${script##*/}
case $script in
  "" | *[!A-Za-z0-9._-]*) script=- ;;
esac

refuse() {
  if [ -n "$quiet" ]; then
    config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
    case $config in
      "~" | "~/"*) config=$HOME${config#\~} ;;
    esac
    case $config in
      /*) ;;
      *) config=$HOME/.claude ;;
    esac
    {
      mkdir -p "$config/state/handoff" &&
        printf '{"at": "%s", "outcome": "no-python", "script": "%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$script" \
          >>"$config/state/handoff/runs.log"
    } 2>/dev/null
    exit 0
  fi
  printf 'hats: %s; the command did not run\n' "$1" >&2
  exit 1
}

python=$(command -v python3 2>/dev/null) || python=
[ -n "$python" ] || refuse "python3 is required and was not found"
if [ "$python" -ef "${HATS_SYSTEM_PYTHON:-/usr/bin/python3}" ] && [ "$(uname 2>/dev/null)" = Darwin ] &&
  ! "${HATS_XCODE_SELECT:-/usr/bin/xcode-select}" -p >/dev/null 2>&1; then
  refuse "python3 is required: $python only offers to install the Xcode Command Line Tools (xcode-select --install)"
fi
exec "$python" -I "$@"
