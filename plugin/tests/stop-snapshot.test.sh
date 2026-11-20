#!/usr/bin/env bash
# Матрица для stop-snapshot.py: снимок фоновых работ и пробуждений сессии в конце хода — файлом на
# сессию в <корень>/stop-snapshots, где корень — HATS_STATE_HOME, иначе ~/Library/Application Support/Hats.
# Хук ничего не печатает и всегда выходит с кодом 0.
#   bash plugin/tests/stop-snapshot.test.sh
#   PATH="/usr/bin:$PATH" bash plugin/tests/stop-snapshot.test.sh      # под системным Python
set -uo pipefail
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK_UNDER_TEST:-$plugin_root/scripts/stop-snapshot.py}"
PY_SH="$plugin_root/scripts/py.sh"
export CLAUDE_CODE_SESSION_ATTENDED=1
unset CLAUDE_CODE_ENTRYPOINT HATS_STATE_HOME STOP_SNAPSHOT_TEST STOP_SNAPSHOT_TEST_PAUSE STOP_SNAPSHOT_TEST_MARK STOP_SNAPSHOT_TEST_FAIL
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/stop-snapshot-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

root="$work/state"
folder="$root/stop-snapshots"
sid="5a32129e-d019-41df-9337-4ad4bb17292a"
own="$folder/$sid.json"
TASK='{"id":"b7x3k9","type":"shell","status":"running","description":"sleep 300","command":"sleep 300"}'

ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }

input() {  # input [поля background_tasks и session_crons, как в JSON] [,"поле":значение...]
  printf '{"session_id":"%s","transcript_path":"/t.jsonl","cwd":"/w","hook_event_name":"Stop","stop_hook_active":false%s%s}' \
    "$sid" "${1-,\"background_tasks\":[],\"session_crons\":[]}" "${2:-}"
}
hook() {  # hook <input> [VAR=value ...] — HATS_STATE_HOME уже задан
  local data=$1; shift
  printf '%s' "$data" | env HATS_STATE_HOME="$root" "$@" python3 -I "$HOOK" 2>&1
}
quiet_run() {  # quiet_run <name> <input> [VAR=value ...] — хук молчит и выходит с 0
  local name=$1 out rc; shift
  out=$(hook "$@"); rc=$?
  if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "$name: молча и код 0" "rc=$rc out=${out:0:300}"; fi
}
reset() { rm -rf "$root"; mkdir -p "$root"; }
field() {  # field <поле> [файл] — значение как JSON или <нет файла>
  python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(d.get(sys.argv[2], "<нет поля>"), ensure_ascii=False, sort_keys=True))' "${2:-$own}" "$1" 2>/dev/null || echo "<нет файла>"
}
expect() {  # expect <название> <поле> <ожидается JSON> [файл]
  local got; got=$(field "$2" "${4:-}")
  if [ "$got" = "$3" ]; then ok; else bad "$1" "$2: ждали $3, получили $got"; fi
}
absent() {  # absent <название> [путь]
  if [ ! -e "${2:-$own}" ]; then ok; else bad "$1: файла нет" "$(cat "${2:-$own}")"; fi
}
mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
left_tmp() { find "$folder" -name '.tmp-*' 2>/dev/null | wc -l | tr -d ' '; }
now_ms() { python3 -I -c 'import time; print(int(time.time() * 1000))'; }
own_ms() {  # own_ms [файл] — собственное время хука: от at_ms (начало запуска) до записи файла
  python3 -I -c 'import json, os, sys
path = sys.argv[1]
print(int(os.stat(path).st_mtime * 1000) - json.load(open(path))["at_ms"])' "${1:-$own}" 2>/dev/null || echo -1
}
python3 --version >/dev/null 2>&1 || { echo "stop-snapshot: python3 не найден"; exit 2; }

# --- снимок
reset
before=$(now_ms)
quiet_run "снимок" "$(input ",\"background_tasks\":[$TASK],\"session_crons\":[]")"
after=$(now_ms)
expect "снимок: сессия" session "\"$sid\""
expect "снимок: годен" ok true
expect "снимок: работа без команды и лишних полей" tasks \
  '[{"description": "sleep 300", "id": "b7x3k9", "status": "running", "type": "shell"}]'
expect "снимок: пробуждений нет" crons 0
at=$(field at_ms)
if [ "$at" -ge "$before" ] 2>/dev/null && [ "$at" -le "$after" ]; then ok
else bad "снимок: at_ms — время запуска" "$before <= $at <= $after"; fi
if [ "$(mode "$folder")" = 700 ] && [ "$(mode "$own")" = 600 ]; then ok
else bad "снимок: папка 700, файл 600" "$(mode "$folder") $(mode "$own")"; fi
if [ "$(left_tmp)" = 0 ]; then ok; else bad "снимок: временных файлов нет" "$(ls -a "$folder")"; fi
expect_keys=$(python3 -I -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$own")
if [ "$expect_keys" = "['at_ms', 'crons', 'ok', 'session', 'tasks']" ]; then ok; else bad "снимок: ровно пять полей" "$expect_keys"; fi

quiet_run "пробуждения" "$(input ',"background_tasks":[],"session_crons":[{"id":"c1"},{"id":"c2"}]')"
expect "пробуждения: число" crons 2
expect "пробуждения: снимок переписан целиком" tasks '[]'

long=$(python3 -I -c 'import json; print(json.dumps([{"id": "a", "type": "subagent", "status": "running", "description": "ж" * 250}]))')
quiet_run "длинное описание" "$(input ",\"background_tasks\":$long,\"session_crons\":[]")"
got=$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["tasks"][0]["description"]))' "$own")
if [ "$got" = 200 ]; then ok; else bad "длинное описание: до 200 знаков" "$got"; fi
quiet_run "статус не строка" "$(input ',"background_tasks":[{"id":"a","type":"shell","status":5}],"session_crons":[]')"
expect "статус не строка: пусто" tasks '[{"description": "", "id": "a", "status": "", "type": "shell"}]'

two_hundred=$(python3 -I -c 'import json; print(json.dumps([{"id": "t%d" % i, "type": "shell"} for i in range(200)]))')
quiet_run "200 работ" "$(input ",\"background_tasks\":$two_hundred,\"session_crons\":[]")"
expect "200 работ: годен" ok true
quiet_run "200 пробуждений" "$(input ",\"background_tasks\":[],\"session_crons\":$two_hundred")"
expect "200 пробуждений: годен" ok true
expect "200 пробуждений: число" crons 200

reset
quiet_run "время начала" "$(input)" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_PAUSE=1
after=$(now_ms); at=$(field at_ms)
if [ $((after - at)) -ge 1000 ] 2>/dev/null; then ok
else bad "время начала: at_ms — до секундной паузы перед заменой файла, не время записи" "at_ms $at, хук кончился к $after"; fi
reset
data=$(input)
{ python3 -I -c 'import time; time.sleep(3)'; now_ms >"$work/fed"; printf '%s' "$data"; } | env HATS_STATE_HOME="$root" python3 -I "$HOOK"
at=$(field at_ms); fed=$(cat "$work/fed")
if [ "$at" -lt "$fed" ] 2>/dev/null; then ok
else bad "время начала: at_ms — раньше, чем пришёл вход" "at_ms $at, вход подан в $fed"; fi

# --- не проверить: ok false, работ нет
unchecked() {  # unchecked <название> <поля>
  reset
  quiet_run "$1" "$(input "$2")"
  expect "$1: ok false" ok false
  expect "$1: работ нет" tasks '[]'
  expect "$1: пробуждений нет" crons 0
}
many=$(python3 -I -c 'import json; print(json.dumps([{"id": "t%d" % i, "type": "shell"} for i in range(201)]))')
unchecked "нет background_tasks" ',"session_crons":[]'
unchecked "нет session_crons" ",\"background_tasks\":[$TASK]"
unchecked "нет обоих" ''
unchecked "background_tasks не список" ',"background_tasks":{"id":"a"},"session_crons":[]'
unchecked "session_crons не список" ",\"background_tasks\":[$TASK],\"session_crons\":3"
unchecked "201 работа" ",\"background_tasks\":$many,\"session_crons\":[]"
unchecked "201 пробуждение" ",\"background_tasks\":[],\"session_crons\":$many"
unchecked "работа не объект" ',"background_tasks":["b1"],"session_crons":[]'
unchecked "id не строка" ',"background_tasks":[{"id":7,"type":"shell"}],"session_crons":[]'
unchecked "type не строка" ',"background_tasks":[{"id":"a","type":null}],"session_crons":[]'
unchecked "нет id" ',"background_tasks":[{"type":"shell"}],"session_crons":[]'

# --- не своё: ничего
reset
quiet_run "без человека" "$(input)" CLAUDE_CODE_SESSION_ATTENDED=0
absent "без человека"
printf '%s' "$(input)" | env -u CLAUDE_CODE_SESSION_ATTENDED HATS_STATE_HOME="$root" CLAUDE_CODE_ENTRYPOINT=sdk-ts python3 -I "$HOOK"
absent "вход SDK"
printf '%s' "$(input)" | env HATS_STATE_HOME="$root" CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=sdk-ts python3 -I "$HOOK"
expect "вход SDK, но с человеком (CLAUDE_CODE_SESSION_ATTENDED=1): снимок есть" ok true
rm -f "$own"
long_id=$(printf 'a%.0s' $(seq 1 80))
printf '{"session_id":"%s","background_tasks":[],"session_crons":[]}' "$long_id" | env HATS_STATE_HOME="$root" python3 -I "$HOOK"
expect "id ровно в 80 знаков: снимок есть" session "\"$long_id\"" "$folder/$long_id.json"
rm -f "$folder/$long_id.json"
quiet_run "подагент" "$(input '' ',"agent_id":"a1"')"
absent "подагент"
for bad_id in 'a/b' '' "$(printf 'a%.0s' $(seq 1 81))" '../x'; do
  printf '{"session_id":"%s","background_tasks":[],"session_crons":[]}' "$bad_id" | env HATS_STATE_HOME="$root" python3 -I "$HOOK"
done
printf '{"session_id":7,"background_tasks":[],"session_crons":[]}' | env HATS_STATE_HOME="$root" python3 -I "$HOOK"
if [ ! -e "$folder" ] || [ -z "$(ls -A "$folder")" ]; then ok; else bad "плохой id: ничего" "$(ls -A "$folder")"; fi
rm -rf "$root"
quiet_run "корня нет" "$(input)"
if [ ! -e "$root" ]; then ok; else bad "корня нет: корень не создан" "$(ls -la "$root")"; fi
reset; mkdir -p "$work/elsewhere"; ln -s "$work/elsewhere" "$folder"
quiet_run "папка — ссылка" "$(input)"
if [ -z "$(ls -A "$work/elsewhere")" ]; then ok; else bad "папка — ссылка: сквозь неё не пишется" "$(ls -A "$work/elsewhere")"; fi
reset; printf 'x' >"$folder"
quiet_run "папка — файл" "$(input)"
if [ "$(cat "$folder")" = x ]; then ok; else bad "папка — файл: файл цел" "$(cat "$folder")"; fi
reset
for data in '' 'not json' '[1]' '"s"' 'null'; do
  quiet_run "вход: ${data:-пусто}" "$data"
done
if [ ! -e "$folder" ] || [ -z "$(ls -A "$folder")" ]; then ok; else bad "негодный вход: ничего" "$(ls -A "$folder")"; fi
out=$(printf '%s' "$(input)" | env HATS_STATE_HOME="$root" python3 -I "$HOOK" where 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ] && [ ! -e "$own" ]; then ok; else bad "лишний аргумент: молча, ничего" "rc=$rc out=$out"; fi

# --- неожиданная ошибка: строка в failures.log, а не тишина ---
failures_log="$folder/failures.log"
failure_line() {  # failure_line [файл] — поля последней строки журнала ошибок
  python3 -I -c 'import json,sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
d = json.loads(lines[-1])
print(len(lines), sorted(d), d["script"], d["event"], d["error"], len(d["at"]))' "${1:-$failures_log}" 2>&1
}
reset_failures() { reset; :; mkdir -p "$folder"; }
reset_failures
quiet_run "неожиданная ошибка" "$(input)" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_FAIL=1
got=$(failure_line)
if [ "$got" = "1 ['at', 'error', 'event', 'script'] stop-snapshot.py Stop RuntimeError 20" ]; then ok
else bad "неожиданная ошибка: одна строка {at, script, event, error}" "$got"; fi
if [ "$(stat -f '%Lp' "$failures_log" 2>/dev/null || stat -c '%a' "$failures_log")" = 600 ]; then ok
else bad "неожиданная ошибка: журнал 600" "$(ls -l "$failures_log")"; fi
if [ ! -e "$own" ]; then ok; else bad "неожиданная ошибка: своего файла нет" "$(cat "$own")"; fi
reset_failures
quiet_run "ошибка без STOP_SNAPSHOT_TEST не включается" "$(input)" STOP_SNAPSHOT_TEST_FAIL=1
if [ ! -e "$failures_log" ] && [ -f "$own" ]; then ok; else bad "STOP_SNAPSHOT_TEST_FAIL без STOP_SNAPSHOT_TEST: пишет файл, журнала нет" "$(ls -A "$folder")"; fi
for data in 'не json' '[1]' ''; do
  reset_failures
  quiet_run "битый ввод «${data}» при готовой папке" "$data" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_FAIL=1
  if [ ! -e "$failures_log" ]; then ok; else bad "битый ввод «${data}»: журнала ошибок нет" "$(cat "$failures_log")"; fi
done
reset_failures
python3 -I -c 'import sys; open(sys.argv[1], "w").write("x" * 70000)' "$failures_log"
quiet_run "ротация журнала ошибок" "$(input)" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_FAIL=1
if [ "$(wc -c <"$failures_log.1" | tr -d ' ')" = 70000 ] && [ "$(failure_line | cut -d' ' -f1)" = 1 ]; then ok
else bad "ротация: старый журнал в .1, новый с одной строкой" "$(ls -l "$folder")"; fi
reset_failures
quiet_run "журнал ниже предела не ротируется" "$(input)" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_FAIL=1
quiet_run "журнал ниже предела не ротируется" "$(input)" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_FAIL=1
if [ ! -e "$failures_log.1" ] && [ "$(failure_line | cut -d' ' -f1)" = 2 ]; then ok
else bad "журнал ниже предела: две строки, без .1" "$(ls -l "$folder")"; fi
reset_failures; ln -s "$work/fail-target" "$failures_log"; printf 'keep\n' >"$work/fail-target"
quiet_run "журнал ошибок — ссылка" "$(input)" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_FAIL=1
if [ "$(cat "$work/fail-target")" = keep ] && [ -L "$failures_log" ]; then ok
else bad "журнал ошибок — ссылка: цель не тронута" "$(cat "$work/fail-target") $(ls -l "$folder")"; fi
reset_failures; mkfifo "$failures_log"
out=$(printf '%s' "$(input)" | timeout 3 env HATS_STATE_HOME="$root" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_FAIL=1 python3 -I "$HOOK" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then ok; else bad "журнал ошибок — канал: хук не ждёт и молчит, код 0" "rc=$rc out=${out:0:300}"; fi
reset; mkdir -p "$work/elsewhere-f"; ln -s "$work/elsewhere-f" "$folder"
got=$(env HATS_STATE_HOME="$root" python3 -I -c 'import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("hook", sys.argv[1])
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
hook.record_hook_failure(
    hook.FOLDER,
    "stop-snapshot.py",
    {"hook_event_name": "x"},
    RuntimeError("t"),
)
print("ok")' "$HOOK" 2>&1)
if [ "$got" = ok ] && [ -z "$(ls -A "$work/elsewhere-f")" ]; then ok; else bad "папка — ссылка: журнал ошибок сквозь неё не пишется" "$got $(ls -A "$work/elsewhere-f")"; fi
rm -f "$folder"; rm -rf "$root"
got=$(env HATS_STATE_HOME="$root" python3 -I -c 'import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("hook", sys.argv[1])
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
hook.record_hook_failure(
    hook.FOLDER,
    "stop-snapshot.py",
    {},
    RuntimeError("t"),
)
print("ok")' "$HOOK" 2>&1)
if [ "$got" = ok ] && [ ! -e "$root" ]; then ok; else bad "корня нет: журнал ошибок не пишется, корень не создан" "$got"; fi


# --- корень по умолчанию
home="$work/home"; mkdir -p "$home/Library/Application Support/Hats"
printf '%s' "$(input)" | env -u HATS_STATE_HOME HOME="$home" python3 -I "$HOOK"
if [ -f "$home/Library/Application Support/Hats/stop-snapshots/$sid.json" ]; then ok
else bad "без HATS_STATE_HOME — папка Hats" "$(ls -R "$home" | head)"; fi
printf '%s' "$(input)" | env HATS_STATE_HOME= HOME="$work/nohome" python3 -I "$HOOK"
if [ ! -e "$work/nohome" ]; then ok; else bad "пустой HATS_STATE_HOME и нет папки Hats — ничего" "$(ls -R "$work/nohome")"; fi

# --- уборка
reset; mkdir -p "$folder"
python3 -I - "$folder" <<'EOF'
import os, sys, time
folder = sys.argv[1]
old = time.time() - 8 * 24 * 3600
for i in range(1000):
    path = os.path.join(folder, "old-%04d.json" % i)
    open(path, "w").write("{}")
    os.utime(path, (old, old))
for name in ("fresh.json", "notes.txt"):
    open(os.path.join(folder, name), "w").write("{}")
os.utime(os.path.join(folder, "notes.txt"), (old, old))
tmp = os.path.join(folder, ".tmp-left_1.json")
open(tmp, "w").write("{")
os.utime(tmp, (old, old))
EOF
quiet_run "уборка" "$(input)"
count=$(ls "$folder" | grep -c '^old-')
if [ "$count" -ge 950 ] && [ "$count" -le 951 ]; then ok; else bad "уборка: не больше 50 за запуск" "осталось $count из 1000"; fi
if [ -e "$folder/fresh.json" ] && [ -e "$folder/notes.txt" ] && [ -e "$own" ]; then ok
else bad "уборка: свежие и чужие на месте" "$(ls "$folder" | grep -v '^old-')"; fi
for _ in $(seq 1 25); do hook "$(input)" >/dev/null; done
count=$(ls "$folder" | grep -c '^old-')
if [ "$count" = 0 ] && [ ! -e "$folder/.tmp-left_1.json" ]; then ok
else bad "уборка: за 25 запусков — все старые" "осталось $count, $(ls -a "$folder" | grep tmp)"; fi
if [ -e "$folder/notes.txt" ] && [ -e "$folder/fresh.json" ]; then ok
else bad "уборка: чужое имя и свежий файл целы и после всех запусков" "$(ls -a "$folder")"; fi

# --- 10 МБ через py.sh
reset
big="$work/big.json"
python3 -I - "$big" "$sid" <<'EOF'
import json, sys
path, sid = sys.argv[1:3]
data = {"session_id": sid, "hook_event_name": "Stop", "stop_hook_active": False,
        "last_assistant_message": "x" * (10 * 1024 * 1024), "background_tasks": [], "session_crons": []}
open(path, "w").write(json.dumps(data))
EOF
out=$(env HATS_STATE_HOME="$root" sh "$PY_SH" --quiet "$HOOK" <"$big" 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ] && [ "$(field ok)" = true ]; then ok
else bad "10 МБ через py.sh: снимок, молча, код 0" "rc=$rc out=${out:0:200} ok=$(field ok)"; fi
spent=$(own_ms)
if [ "$spent" -ge 0 ] && [ "$spent" -lt 3500 ]; then ok
else bad "10 МБ через py.sh: собственное время хука внутри среза 3,5 с" "${spent} мс"; fi

# --- SIGTERM перед os.replace и срез на 3,5 с
reset
rm -f "$work/mark"
printf '%s' "$(input)" | env HATS_STATE_HOME="$root" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_PAUSE=10 \
  STOP_SNAPSHOT_TEST_MARK="$work/mark" python3 -I "$HOOK" >"$work/term-out.txt" 2>&1 &
paused=$!
for _ in $(seq 1 100); do [ -e "$work/mark" ] && break; python3 -I -c 'import time; time.sleep(0.05)'; done
kill -TERM "$paused"; wait "$paused"; rc=$?
if [ -e "$work/mark" ] && [ $rc -eq 0 ] && [ ! -s "$work/term-out.txt" ]; then ok
else bad "SIGTERM: код 0 и молча" "rc=$rc out=$(head -c 300 "$work/term-out.txt")"; fi
absent "SIGTERM: снимка нет"
if [ "$(left_tmp)" = 0 ]; then ok; else bad "SIGTERM: временного файла нет" "$(ls -a "$folder")"; fi

reset
start=$(now_ms)
out=$(printf '%s' "$(input)" | env HATS_STATE_HOME="$root" STOP_SNAPSHOT_TEST=1 STOP_SNAPSHOT_TEST_PAUSE=10 python3 -I "$HOOK" 2>&1); rc=$?
took=$(( $(now_ms) - start ))
if [ -z "$out" ] && [ $rc -eq 0 ] && [ "$took" -ge 3400 ] && [ "$took" -lt 9000 ]; then ok
else bad "срез: сам кончается на 3,5 с, задолго до конца 10-секундной паузы, молча, код 0" "rc=$rc ${took} мс out=${out:0:200}"; fi
absent "срез: снимка нет"
if [ "$(left_tmp)" = 0 ]; then ok; else bad "срез: временного файла нет" "$(ls -a "$folder")"; fi
out=$(printf '%s' "$(input)" | env HATS_STATE_HOME="$root" STOP_SNAPSHOT_TEST_PAUSE=10 python3 -I "$HOOK" 2>&1)
if [ -f "$own" ]; then ok; else bad "пауза без STOP_SNAPSHOT_TEST не действует" "снимка нет"; fi

# --- hooks.json
hooks_ok=$(python3 -I -c 'import json, sys
hooks = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
want = "sh \"${CLAUDE_PLUGIN_ROOT}/scripts/py.sh\" --quiet \"${CLAUDE_PLUGIN_ROOT}/scripts/stop-snapshot.py\""
found = [(event, group, hook) for event, groups in hooks.items() for group in groups for hook in group["hooks"]
         if "stop-snapshot.py" in hook["command"]]
assert len(found) == 1, found
event, group, hook = found[0]
assert event == "Stop", event
assert group.get("matcher") is None, group
assert hook == {"type": "command", "command": want, "timeout": 5}, hook
print("ok")' "$plugin_root/hooks/hooks.json" 2>&1)
if [ "$hooks_ok" = ok ]; then ok; else bad "hooks.json: одна запись на Stop, синхронно, через py.sh --quiet" "$hooks_ok"; fi

if [ ! -e "$(dirname "$HOOK")/__pycache__" ]; then ok
else bad "байт-код не пишется рядом с хуком" "$(ls "$(dirname "$HOOK")/__pycache__")"; fi

total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "stop-snapshot: $pass/$total прошли"; exit 0; fi
echo "stop-snapshot: $pass/$total прошли, $fail упало$failures"; exit 1
