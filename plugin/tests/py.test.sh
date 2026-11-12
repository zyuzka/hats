#!/usr/bin/env bash
# Матрица для py.sh: когда обёртка запускает python3 -I, а когда отказывается.
# Системный Python и xcode-select подменяются через HATS_SYSTEM_PYTHON и HATS_XCODE_SELECT,
# uname — через PATH; /usr/bin не трогается. Подставной python3 пишет, с чем его запустили.
#   bash plugin/tests/py.test.sh
set -uo pipefail
WRAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/py.sh"
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/py-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

fake() {  # fake <файл> <тело>
  mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n%s\n' "$2" >"$1"; chmod +x "$1"
}
python_body='printf "%s\n" "$@" >"$PY_LOG"; cat >"$PY_LOG.stdin"; echo ran; exit "${FAKE_RC:-0}"'
fake "$work/sys/python3" "$python_body"
fake "$work/own/python3" "$python_body"
fake "$work/darwin/uname" 'echo Darwin'
fake "$work/linux/uname" 'echo Linux'
fake "$work/xs-ok" 'echo "$@" >>"$XS_LOG"; echo /Library/Developer/CommandLineTools'
fake "$work/xs-fail" 'echo "$@" >>"$XS_LOG"; echo "xcode-select: error: unable to get active developer directory" >&2; exit 2'
printf 'print("ran")\n' >"$work/script.py"

run() {  # run <PATH> <xcode-select> [аргументы обёртки...]; системный Python — подставной из $work/sys
  local path="$1" xs="$2"; shift 2
  launch "$path" HATS_SYSTEM_PYTHON="$work/sys/python3" HATS_XCODE_SELECT="$xs" -- "$@"
}
launch() {  # launch <PATH> [VAR=значение...] -- [аргументы обёртки...]
  local path="$1"; shift
  local vars=()
  while [ "$1" != "--" ]; do vars+=("$1"); shift; done; shift
  rm -rf "$work/py.log" "$work/py.log.stdin" "$work/xs.log" "$work/home"
  printf 'input' | env -i PATH="$path" HOME="$work/home" PY_LOG="$work/py.log" XS_LOG="$work/xs.log" "${vars[@]}" /bin/sh "$WRAP" "$@" \
    >"$work/out" 2>"$work/err"
  rc=$?; out=$(cat "$work/out"); err=$(cat "$work/err")
}
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }
started() {  # started <случай> — подставной python3 запущен с -I, скриптом и аргументами, код 0
  local want; want=$(printf '%s\n' -I "$work/script.py" a "b c")
  if [ $rc -eq 0 ] && [ "$out" = ran ] && [ "$(cat "$work/py.log" 2>/dev/null)" = "$want" ]; then ok
  else bad "$1" "rc=$rc out=${out:0:200} err=${err:0:200} args=$(cat "$work/py.log" 2>/dev/null)"; fi
}
quiet_refusal() {  # quiet_refusal <случай> — Python не запущен, вывода нет, код 0
  if [ $rc -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] && [ ! -e "$work/py.log" ]; then ok
  else bad "$1" "rc=$rc out=${out:0:200} err=${err:0:200} python=$([ -e "$work/py.log" ] && echo запущен)"; fi
}
loud_refusal() {  # loud_refusal <случай> <ожидаемые слова> — Python не запущен, фраза про python3, код 1
  if [ $rc -eq 1 ] && [ -z "$out" ] && [ ! -e "$work/py.log" ] && case "$err" in *"python3 is required"*"$2"*) true ;; *) false ;; esac
  then ok
  else bad "$1" "rc=$rc out=${out:0:200} err=${err:0:200} python=$([ -e "$work/py.log" ] && echo запущен)"; fi
}

# --- заглушка macOS: системный python3, xcode-select -p не отвечает
run "$work/sys:$work/darwin:/bin" "$work/xs-fail" --quiet "$work/script.py" a "b c"
quiet_refusal "заглушка, хук: Python не запущен, тишина, код 0"
if grep -qx -- '-p' "$work/xs.log" 2>/dev/null; then ok; else bad "заглушка: спрошен xcode-select -p" "$(cat "$work/xs.log" 2>/dev/null)"; fi
run "$work/sys:$work/darwin:/bin" "$work/xs-fail" "$work/script.py" a "b c"
loud_refusal "заглушка, скилл: фраза про python3 и Command Line Tools" "Xcode Command Line Tools"
launch "$work/darwin:/usr/bin:/bin" HATS_XCODE_SELECT="$work/xs-fail" -- --quiet "$work/script.py"
quiet_refusal "заглушка: по умолчанию системный — /usr/bin/python3"
launch "$work/darwin:/usr/bin:/bin" HATS_XCODE_SELECT="$work/xs-fail" -- "$work/script.py"
loud_refusal "заглушка: фраза называет /usr/bin/python3" "/usr/bin/python3"
run "$work//sys:$work/darwin:/bin" "$work/xs-fail" --quiet "$work/script.py"
quiet_refusal "заглушка под путём с двойной косой: Python не запущен"
mkdir -p "$work/link"; ln -s "$work/sys/python3" "$work/link/python3"
run "$work/link:$work/darwin:/bin" "$work/xs-fail" --quiet "$work/script.py"
quiet_refusal "заглушка через ссылку на неё: Python не запущен"

# --- инструменты разработчика есть
run "$work/sys:$work/darwin:/bin" "$work/xs-ok" --quiet "$work/script.py" a "b c"
started "инструменты есть, хук: запущен, --quiet не передаётся дальше"
if [ "$(cat "$work/py.log.stdin" 2>/dev/null)" = input ]; then ok; else bad "инструменты есть: ввод доходит до Python" "$(cat "$work/py.log.stdin" 2>/dev/null)"; fi
run "$work/sys:$work/darwin:/bin" "$work/xs-ok" "$work/script.py" a "b c"
started "инструменты есть, скилл: запущен"
launch "$work/sys:$work/darwin:/bin" HATS_SYSTEM_PYTHON="$work/sys/python3" HATS_XCODE_SELECT="$work/xs-ok" FAKE_RC=3 -- "$work/script.py"
if [ $rc -eq 3 ]; then ok; else bad "код выхода Python возвращается как есть" "rc=$rc"; fi
printf 'input' | env -i PATH="$work/sys:$work/darwin:/bin" HOME="$work/home" PY_LOG="$work/py.log" HATS_SYSTEM_PYTHON="$work/sys/python3" \
  /bin/sh -x "$WRAP" --quiet "$work/script.py" >/dev/null 2>"$work/trace"
if grep -qE '^\++ /usr/bin/xcode-select -p$' "$work/trace"; then ok
else bad "по умолчанию спрашивается /usr/bin/xcode-select -p" "$(grep -i xcode "$work/trace")"; fi

# --- свой Python: не /usr/bin/python3 — без проверки xcode-select
run "$work/own:$work/darwin:/bin" "$work/xs-fail" --quiet "$work/script.py" a "b c"
started "свой python3: запущен при неотвечающем xcode-select"
if [ ! -e "$work/xs.log" ]; then ok; else bad "свой python3: xcode-select не спрашивается" "$(cat "$work/xs.log")"; fi

# --- не macOS
run "$work/sys:$work/linux:/bin" "$work/xs-fail" --quiet "$work/script.py" a "b c"
started "не macOS: запущен при неотвечающем xcode-select"

# --- python3 нет
run "$work/darwin" "$work/xs-fail" --quiet "$work/script.py"
quiet_refusal "python3 нет, хук: тишина, код 0"
run "$work/darwin" "$work/xs-fail" "$work/script.py"
loud_refusal "python3 нет, скилл: фраза про python3" "not found"

# --- отказ хука оставляет строку в <config>/state/handoff/runs.log, иначе строк нет
logged() {  # logged <случай> <файл журнала> — ровно одна строка no-python с именем скрипта
  if [ "$(wc -l <"$2" 2>/dev/null | tr -d ' ')" = 1 ] &&
    grep -qE '^\{"at": "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", "outcome": "no-python", "script": "script.py"\}$' "$2"
  then ok
  else bad "$1" "$(cat "$2" 2>&1 | head -3)"; fi
}
runs="$work/home/.claude/state/handoff/runs.log"
run "$work/sys:$work/darwin:/bin" "$work/xs-fail" --quiet "$work/script.py"
logged "заглушка, хук: строка в ~/.claude/state/handoff/runs.log" "$runs"
run "$work/darwin:/bin" "$work/xs-fail" --quiet "$work/script.py"
logged "python3 нет, хук: строка в ~/.claude/state/handoff/runs.log" "$runs"
rm -rf "$work/cfg"
launch "$work/sys:$work/darwin:/bin" HATS_SYSTEM_PYTHON="$work/sys/python3" HATS_XCODE_SELECT="$work/xs-fail" CLAUDE_CONFIG_DIR="$work/cfg" \
  -- --quiet "$work/script.py"
logged "заглушка, хук: строка в \$CLAUDE_CONFIG_DIR/state/handoff/runs.log" "$work/cfg/state/handoff/runs.log"
if [ ! -e "$work/home/.claude" ]; then ok; else bad "CLAUDE_CONFIG_DIR: в ~/.claude ничего не пишется" "$(ls -R "$work/home")"; fi
cd "$work" || exit 1
launch "$work/sys:$work/darwin:/bin" HATS_SYSTEM_PYTHON="$work/sys/python3" HATS_XCODE_SELECT="$work/xs-fail" CLAUDE_CONFIG_DIR="~/cfg" \
  -- --quiet "$work/script.py"
logged "CLAUDE_CONFIG_DIR с ~ — раскрывается в HOME" "$work/home/cfg/state/handoff/runs.log"
if [ ! -e "$work/~" ]; then ok; else bad "CLAUDE_CONFIG_DIR с ~ — папки «~» в текущей нет" "$(ls -R "$work/~" | head -3)"; fi
rm -rf "$work/cfg"; mkdir -p "$work/cfg"; printf 'x' >"$work/cfg/state"
launch "$work/sys:$work/darwin:/bin" HATS_SYSTEM_PYTHON="$work/sys/python3" HATS_XCODE_SELECT="$work/xs-fail" CLAUDE_CONFIG_DIR="$work/cfg" \
  -- --quiet "$work/script.py"
quiet_refusal "журнал не создать (state — файл): тишина, код 0"
rm -rf "$work/cfg"; mkdir -p "$work/cfg/state/handoff/runs.log"
launch "$work/sys:$work/darwin:/bin" HATS_SYSTEM_PYTHON="$work/sys/python3" HATS_XCODE_SELECT="$work/xs-fail" CLAUDE_CONFIG_DIR="$work/cfg" \
  -- --quiet "$work/script.py"
quiet_refusal "журнал не дописать (runs.log — папка): тишина, код 0"
run "$work/sys:$work/darwin:/bin" "$work/xs-fail" "$work/script.py"
if [ ! -e "$runs" ]; then ok; else bad "отказ скилла (без --quiet) журнал не пишет" "$(cat "$runs")"; fi
run "$work/sys:$work/darwin:/bin" "$work/xs-ok" --quiet "$work/script.py" a "b c"
if [ ! -e "$runs" ]; then ok; else bad "запуск Python журнал не пишет" "$(cat "$runs")"; fi

total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "py: $pass/$total прошли"; exit 0; fi
echo "py: $pass/$total прошли, $fail упало$failures"; exit 1
