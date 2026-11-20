#!/usr/bin/env bash
# Матрица для window-fill.py: заполненность окна сессии из хвоста её переписки — файлом на сессию
# в <корень>/session-windows, где корень — HATS_STATE_HOME, иначе ~/Library/Application Support/Hats.
# Переписки составлены здесь; хук ничего не печатает и всегда выходит с кодом 0.
#   bash plugin/tests/window-fill.test.sh
#   PATH="/usr/bin:$PATH" bash plugin/tests/window-fill.test.sh      # под системным Python
#   HOOK_UNDER_TEST=/path/to/candidate.py bash plugin/tests/window-fill.test.sh
set -uo pipefail
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK_UNDER_TEST:-$plugin_root/scripts/window-fill.py}"
export CLAUDE_CODE_SESSION_ATTENDED=1
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_DISABLE_1M_CONTEXT CLAUDE_CODE_MAX_CONTEXT_TOKENS HATS_STATE_HOME \
  WINDOW_FILL_TEST WINDOW_FILL_TEST_PAUSE WINDOW_FILL_TEST_READ WINDOW_FILL_TEST_FAIL
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/window-fill-test.XXXXXX")
holder=""
trap '[ -n "$holder" ] && kill "$holder" 2>/dev/null; rm -rf "$work"' EXIT INT TERM

root="$work/state"
folder="$root/session-windows"
tr="$work/t.jsonl"
sid="5a32129e-d019-41df-9337-4ad4bb17292a"
own="$folder/$sid.json"
T0="2026-11-13T10:00:00.000Z"
T1="2026-11-13T10:05:00.000Z"
T2="2026-11-13T10:10:00.000Z"

ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }

ANSWER='{"parentUuid":"p","isSidechain":false,"type":"assistant","uuid":"a-%s","timestamp":"%s",'
ANSWER+='"message":{"model":"%s","id":"%s","type":"message","role":"assistant",'
ANSWER+='"content":[{"type":"text","text":"done"}],"stop_reason":"end_turn","usage":{"input_tokens":%s,'
ANSWER+='"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":9%s}}}\n'
ans() {  # ans <id> <input> <cache_creation> <cache_read> [model] [time] [,"iterations":[...] и прочее в usage]
  printf "$ANSWER" "$1" "${6:-$T0}" "${5:-claude-opus-5-5}" "$1" "$2" "$3" "$4" "${7:-}"
}
FIRST_TEXT='{"type":"assistant","uuid":"a-%s","timestamp":"%s","message":{"model":"%s","id":"%s",'
FIRST_TEXT+='"content":[{"type":"text","text":"%s"}],"usage":{"input_tokens":5,"cache_creation_input_tokens":0,'
FIRST_TEXT+='"cache_read_input_tokens":0,"output_tokens":1}}%s}\n'
first_text() {  # first_text <id> <text> [model] [extra top-level] — ответ с заданным первым блоком
  printf "$FIRST_TEXT" "$1" "$T2" "${3:-claude-opus-5-5}" "$1" "$2" "${4:-}"
}
user() { printf '{"type":"user","message":{"role":"user","content":"%s"},"uuid":"u","timestamp":"%s"}\n' "$1" "$T1"; }
BOUNDARY='{"parentUuid":null,"isSidechain":false,"type":"system","subtype":"compact_boundary",'
BOUNDARY+='"content":"Conversation compacted","level":"info",'
BOUNDARY+='"compactMetadata":{"trigger":"auto","preTokens":967090,"postTokens":23709},"uuid":"%s","timestamp":"%s"}\n'
boundary() { printf "$BOUNDARY" "$1" "${2:-$T1}"; }
SUMMARY='{"type":"user","message":{"role":"user","content":"summary"},"isVisibleInTranscriptOnly":true,'
SUMMARY+='"isCompactSummary":true,"uuid":"s-%s","timestamp":"%s"}\n'
summary() { printf "$SUMMARY" "$1" "${2:-$T1}"; }
iteration() {  # iteration <type> <input> <output> <cache_creation> <cache_read>
  printf '{"type":"%s","input_tokens":%s,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}' "$@"
}

input() {  # input [event] [,"поле":значение...] [transcript]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s"%s}' \
    "$sid" "${3-$tr}" "$work/proj" "${1:-PostToolUse}" "${2:-}"
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
field() {  # field <поле> [файл] — значение, null или <нет файла>
  python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
v = d.get(sys.argv[2], "<нет поля>")
print("null" if v is None else (v if isinstance(v, str) else json.dumps(v)))' "${2:-$own}" "$1" 2>/dev/null || echo "<нет файла>"
}
expect() {  # expect <название> <поле> <ожидается> [файл]
  local got; got=$(field "$2" "${4:-}")
  if [ "$got" = "$3" ]; then ok; else bad "$1" "$2: ждали $3, получили $got"; fi
}
expect_many() {  # expect_many <название> <поле>=<значение>...
  local name=$1 pair; shift
  for pair in "$@"; do expect "$name" "${pair%%=*}" "${pair#*=}"; done
}
no_file() {
  if [ ! -e "$own" ]; then ok; else bad "$1" "файл есть: $(cat "$own")"; fi
}
inode() { stat -f %i "$own" 2>/dev/null || echo none; }
reset() { rm -rf "$root" "$work/proj" "$tr"; mkdir -p "$work/proj" "$root"; }
fresh_root() { rm -rf "$root"; mkdir -p "$root"; }
measure() {  # measure <название> <ожидаемые поля...> — один прогон после сброса папки
  local name=$1; shift
  fresh_root
  quiet_run "$name" "$(input)"
  expect_many "$name" "$@"
}

# --- ответ ---
reset; ans m1 2 1035 448622 >"$tr"
measure "ответ без итераций" tokens=449659 window=1000000 percent=45 state=read message=m1 \
  measured_at="$T0" model=claude-opus-5-5 session="$sid" cwd="$work/proj" event=PostToolUse compactions=0 \
  compaction=null compacted_at=null title=null
if [ "$(stat -f %Lp "$folder")" = 700 ]; then ok; else bad "папка 700" "$(stat -f %Lp "$folder")"; fi
if [ "$(stat -f %Lp "$own")" = 600 ]; then ok; else bad "файл 600" "$(stat -f %Lp "$own")"; fi
if ls -a "$folder" | grep -q '^\.tmp-'; then bad "временный файл убран" "$(ls -a "$folder")"; else ok; fi
written=$(field written_at)
if printf '%s' "$written" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then ok
else bad "written_at — время записи" "$written"; fi

# --- итерации ---
reset
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 10 5 20 30)]" >"$tr"
measure "итерации: последняя message" tokens=60
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 10 5 20 30),$(iteration compaction 900 1 900 900)]" >"$tr"
measure "итерации: compaction в конце пропускается" tokens=60
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 10 5 20 30),$(iteration advisor_message 900 1 900 900)]" >"$tr"
measure "итерации: advisor_message в конце пропускается" tokens=60
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 10 5 20 30),$(iteration fallback_message 1 1 1 1)]" >"$tr"
measure "итерации: fallback_message считается" tokens=3
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 10 5 20 30),$(iteration tool_call 1 1 1 1)]" >"$tr"
measure "итерации: последняя иного типа — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 10 5 -20 30)]" >"$tr"
measure "итерации: отрицательное число — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 0 5 0 0)]" >"$tr"
measure "итерации: сумма входа ноль — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" \
  ',"iterations":[{"type":"message","input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30}]' >"$tr"
measure "итерации: нет output_tokens — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" ',"iterations":[{"type":"message","input_tokens":"10","output_tokens":1,'\
'"cache_creation_input_tokens":20,"cache_read_input_tokens":30}]' >"$tr"
measure "итерации: число строкой — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" ',"iterations":[{"type":"message","input_tokens":true,"output_tokens":1,'\
'"cache_creation_input_tokens":20,"cache_read_input_tokens":30}]' >"$tr"
measure "итерации: true вместо числа — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 10 5 20 30),5]" >"$tr"
measure "итерации: последняя не объект — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" ',"iterations":[]' >"$tr"
measure "итерации: пустой список — верхние поля" tokens=150
ans m1 50 50 50 claude-opus-5-5 "$T0" ",\"iterations\":{\"type\":\"message\"}" >"$tr"
measure "итерации: не список — верхние поля" tokens=150
ans m1 0 0 0 claude-opus-5-5 "$T0" ",\"iterations\":[$(iteration message 100 5 100 100)]" >"$tr"
measure "сумма ноль — верхние поля (ноль)" tokens=0 percent=0
printf '{"type":"assistant","timestamp":"%s","message":{"model":"claude-opus-5-5","id":"m1","content":[],'\
'"usage":{"cache_read_input_tokens":70}}}\n' "$T0" >"$tr"
measure "нет полей — нули, как ?? 0" tokens=70
ans m1 50 50 50 claude-opus-5-5 "$T0" ',"iterations":[{"type":["message"],"input_tokens":10,"output_tokens":1,'\
'"cache_creation_input_tokens":20,"cache_read_input_tokens":30}]' >"$tr"
measure "итерации: type списком — не считается, верхние поля" tokens=150 message=m1
ans m1 50 50 50 claude-opus-5-5 "$T0" ',"iterations":[{"type":{"kind":"message"},"input_tokens":10,"output_tokens":1,'\
'"cache_creation_input_tokens":20,"cache_read_input_tokens":30}]' >"$tr"
measure "итерации: type объектом — не считается, верхние поля" tokens=150 message=m1

# --- не ответ ---
reset; { ans m1 2 1035 448622; first_text m2 "No response requested."; } >"$tr"
measure "синтетический текст первым блоком — пропускается" message=m1 tokens=449659
for text in "[Request interrupted by user]" "[Request interrupted by user for tool use]"; do
  { ans m1 2 1035 448622; first_text m2 "$text"; } >"$tr"
  measure "синтетический «${text}» — пропускается" message=m1
done
{ ans m1 2 1035 448622; first_text m2 "ordinary"; } >"$tr"
measure "обычный текст первым блоком — ответ" message=m2 tokens=5
{ ans m1 2 1035 448622; first_text m2 "ordinary" "<synthetic>"; } >"$tr"
measure "модель <synthetic> — пропускается" message=m1
{ ans m1 2 1035 448622; first_text m2 "ordinary" claude-opus-5-5 ',"isUnmetered":true'; } >"$tr"
measure "isUnmetered — пропускается" message=m1
{ ans m1 2 1035 448622; first_text m2 "ordinary" claude-opus-5-5 ',"isUnmetered":false'; } >"$tr"
measure "isUnmetered false — ответ" message=m2
{ ans m1 2 1035 448622
  printf '{"type":"assistant","timestamp":"%s","message":{"model":"claude-opus-5-5","id":"m2",'\
'"content":[{"type":"text","text":"x"}]}}\n' "$T2"; } >"$tr"
measure "строка без usage — не ответ" message=m1

# --- ответ в несколько строк ---
reset
{ ans m1 2 1035 448622 claude-opus-5-5 "$T0"; ans m1 2 1035 448622 claude-opus-5-5 "$T1"; } >"$tr"
measure "строки одного ответа — одно число" tokens=449659 percent=45 message=m1 measured_at="$T1"

# --- округление ---
reset; ans m1 0 0 89000 claude-haiku-4-5 >"$tr"
measure "ровно 44,5% при 200 тыс. — 45" percent=45 window=200000
ans m1 0 0 445000 >"$tr"
measure "ровно 44,5% при 1 млн — 45" percent=45
ans m1 0 0 444999 >"$tr"
measure "44,4999% — 44" percent=44
ans m1 0 0 250000 claude-haiku-4-5 >"$tr"
measure "больше окна — 100" percent=100 tokens=250000

# --- тот же ответ ---
reset; ans m1 2 1035 448622 claude-opus-5-5 "$T0" >"$tr"
quiet_run "тот же ответ: первый прогон" "$(input)"
before=$(inode)
user "ещё вопрос" >>"$tr"
quiet_run "тот же ответ: событие без нового ответа" "$(input UserPromptSubmit)"
expect "тот же ответ: measured_at прежний" measured_at "$T0"
if [ "$(inode)" = "$before" ]; then ok; else bad "тот же ответ: файл не переписан" "inode $before → $(inode)"; fi
ans m1 2 1035 448622 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "тот же ответ новой строкой" "$(input)"
expect "тот же ответ новой строкой: measured_at прежний" measured_at "$T0"
ans m2 2 1035 500000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "новый ответ" "$(input)"
expect_many "новый ответ" message=m2 measured_at="$T2" tokens=501037 percent=50
printf '{"session":"%s","state":"read","message":"m2","measured_at":"yesterday"}' "$sid" >"$own"
quiet_run "прежнее measured_at не время" "$(input)"
expect "тот же ответ, прежнее measured_at не время — берётся время строки" measured_at "$T2"

# --- сжатие ---
reset; { ans m1 2 1035 448622; boundary b1 "$T1"; summary 1 "$T1"; } >"$tr"
measure "сжатие после ответа" state=compacted tokens=null window=null percent=null model=null message=null \
  compactions=1 compaction=b1 compacted_at="$T1" measured_at="$T1"
before=$(inode)
quiet_run "та же граница ещё раз" "$(input)"
expect "та же граница ещё раз: без +1" compactions 1
if [ "$(inode)" = "$before" ]; then ok; else bad "та же граница: файл не переписан" "inode $before → $(inode)"; fi
ans m2 2 1035 30000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "после сжатия ответ" "$(input)"
expect_many "после сжатия ответ" state=read tokens=31037 percent=3 compactions=1 compaction=b1 compacted_at="$T1"
boundary b2 "2026-11-13T12:00:00.000Z" >>"$tr"
quiet_run "вторая граница" "$(input)"
expect_many "вторая граница" state=compacted compactions=2 compaction=b2 compacted_at=2026-11-13T12:00:00.000Z
reset; { ans m1 2 1035 448622; summary 1 "$T1"; } >"$tr"
measure "без границы — isCompactSummary" state=compacted tokens=null compactions=0 compaction=null measured_at="$T1"
reset; { ans m1 2 1035 448622; boundary b1 "$T1"; summary 1; ans m2 2 1035 30000 claude-opus-5-5 "$T2"; } >"$tr"
measure "граница и ответ вместе" state=read tokens=31037 compactions=1 compaction=b1 compacted_at="$T1"
reset; { boundary b1 "$T0"; ans m1 1 1 1; boundary b2 "$T1"; summary 2; ans m2 2 1035 30000 claude-opus-5-5 "$T2"; } >"$tr"
measure "две новые границы за одно чтение — +1, последняя" compactions=1 compaction=b2 compacted_at="$T1"
reset; { user "x"; boundary b1 "$T1"; summary 1; } >"$tr"
measure "граница без ответа" state=compacted compactions=1 compaction=b1

# --- ответа нет ---
reset; { user "a"; user "b"; } >"$tr"
quiet_run "ответа нет" "$(input)"; no_file "ответа нет — файла нет"
ans m1 2 1035 448622 >"$tr"; quiet_run "ответ появился" "$(input)"
before=$(inode); { user "a"; user "b"; } >"$tr"
quiet_run "ответа нет при файле" "$(input)"
if [ "$(inode)" = "$before" ] && [ "$(field message)" = m1 ]; then ok; else bad "ответа нет — файл не меняется" "$(cat "$own")"; fi

# --- обрыв ---
reset; { ans m1 2 1035 448622
  printf '{"type":"assistant","timestamp":"%s","message":{"model":"claude-opus-5-5","id":"m9","usage":{"input_tokens":1' "$T2"
} >"$tr"
measure "последняя строка — неполный JSON" message=m1 tokens=449659
reset; { ans m1 2 1035 448622; printf 'не json\n\xff\xfe\n[1,2]\n'; } >"$tr"
measure "строки не JSON и не объект — пропускаются" message=m1

# --- далеко ---
filler() {  # filler <байт> — строки пользователя, всего не меньше заданного
  python3 -I -c 'import sys
line = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"" + "x" * 900 + "\"}}\n"
n = int(sys.argv[1]) // len(line) + 1
sys.stdout.write(line * n)' "$1"
}
reset; { ans m1 2 1035 448622; filler 300000; } >"$tr"
measure "ответ в 300 КБ от конца — хвост растёт" message=m1 tokens=449659
{ ans m1 2 1035 448622; filler 5000000; } >"$tr"
measure "ответ в 5 МБ от конца — найден" message=m1
reset; { ans m1 2 1035 448622; filler 8500000; } >"$tr"
quiet_run "ответ дальше 8 МБ" "$(input)"; no_file "ответ дальше 8 МБ — файла нет"
reset; { ans m1 2 1035 448622; filler 7000000; } >"$tr"; quiet_run "ответ в 7 МБ" "$(input)"
before=$(inode); filler 2000000 >>"$tr"
quiet_run "ответ ушёл дальше 8 МБ" "$(input)"
if [ "$(inode)" = "$before" ]; then ok; else bad "ответ ушёл дальше 8 МБ — файл не меняется" "inode $before → $(inode)"; fi

# --- окно ---
window_is() {  # window_is <название> <модель> <окно> [VAR=value ...]
  local name=$1 model=$2 want=$3; shift 3
  ans m1 0 0 100000 "$model" >"$tr"
  fresh_root
  quiet_run "$name" "$(input)" "$@"
  expect "$name" window "$want"
  if [ "$want" = null ]; then expect "$name: без окна нет процента" percent null; expect "$name: tokens есть" tokens 100000
  else expect "$name: процент от окна" percent $((100000 * 100 / want)); fi
}
reset
for model in claude-fable-5-2 claude-fable-5 claude-opus-4-7 claude-opus-4-8 claude-opus-4-9-20260101 \
  claude-opus-5 claude-opus-5-5 claude-sonnet-5-1 claude-haiku-5-5-20261101 \
  claude-mythos-5 claude-mythos-5-1 claude-mythos-5-2; do
  window_is "окно 1 млн: $model" "$model" 1000000
done
window_is "1 млн при CLAUDE_CODE_DISABLE_1M_CONTEXT=1" claude-opus-5-5 200000 CLAUDE_CODE_DISABLE_1M_CONTEXT=1
window_is "1 млн при CLAUDE_CODE_DISABLE_1M_CONTEXT=true" claude-fable-5-2 200000 CLAUDE_CODE_DISABLE_1M_CONTEXT=true
window_is "1 млн при CLAUDE_CODE_DISABLE_1M_CONTEXT=0" claude-opus-5-5 1000000 CLAUDE_CODE_DISABLE_1M_CONTEXT=0
for model in claude-3-5-sonnet-20241022 claude-3-opus-20240229 claude-haiku-4-5 claude-haiku-4-5-20251001; do
  window_is "окно 200 тыс.: $model" "$model" 200000
done
window_is "200 тыс. и CLAUDE_CODE_DISABLE_1M_CONTEXT=1" claude-haiku-4-5 200000 CLAUDE_CODE_DISABLE_1M_CONTEXT=1
for model in claude-opus-4-6 claude-opus-4-5 claude-opus-4-1 claude-sonnet-4-6 claude-sonnet-4-5 claude-sonnet-4 \
  claude-opus-6-0 claude-sonnet-6 claude-opus-50 claude-opus-4-70 claude-mythos-6 claude-mythos-50 gpt-5 opus \
  "claude-opus-4-6[1m]"; do
  window_is "окно неизвестно: $model" "$model" null
done
window_is "CLAUDE_CODE_MAX_CONTEXT_TOKENS задана" claude-opus-5-5 null CLAUDE_CODE_MAX_CONTEXT_TOKENS=500000
window_is "CLAUDE_CODE_MAX_CONTEXT_TOKENS пустая — не задана" claude-opus-5-5 1000000 CLAUDE_CODE_MAX_CONTEXT_TOKENS=

# --- название и папка ---
reset; ans m1 2 1035 448622 >"$tr"
quiet_run "название" "$(input UserPromptSubmit ',"session_title":"Fix the login"')"
expect_many "название из session_title" title="Fix the login" event=UserPromptSubmit
ans m2 2 1035 500000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "без названия на входе" "$(input PostToolUse)"
expect_many "без названия — прежнее" title="Fix the login" message=m2
ans m3 2 1035 600000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "пустое название" "$(input UserPromptSubmit ',"session_title":"  "')"
expect "пустое название — прежнее" title "Fix the login"
long=$(python3 -I -c 'print("t" * 500)')
ans m4 2 1035 610000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "длинное название" "$(input UserPromptSubmit ",\"session_title\":\"$long\"")"
expect "длинное название — 200 знаков" title "$(python3 -I -c 'print("t" * 200)')"
ans m5 2 1035 620000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "без cwd на входе" "$(printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop"}' "$sid" "$tr")"
expect_many "без cwd — прежняя" cwd="$work/proj" event=Stop message=m5

# --- конец хода: последняя строка ответа ложится в переписку после запуска Stop ---
# Проба 2026-11-13 (2.1.323): строка последнего ответа записана через 43 мс после того, как хук
# Stop уже записал файл, за ней stop_hook_summary и turn_duration.
STOP_SUMMARY='{"type":"system","subtype":"stop_hook_summary","timestamp":"%s"}\n'
reset; { user "q"; ans m1 2 1035 448622 claude-opus-5-5 "$T0"; } >"$tr"
(hook "$(input Stop)" >/dev/null) &
stopper=$!
python3 -I -c 'import time; time.sleep(0.3)'
{ ans m2 2 1035 500000 claude-opus-5-5 "$T2"; printf "$STOP_SUMMARY" "$T2"; } >>"$tr"
wait "$stopper"
expect_many "Stop: ответ, дописанный после запуска хука, — в файле" message=m2 tokens=501037 event=Stop
reset; { user "q"; ans m1 2 1035 448622 claude-opus-5-5 "$T0"; } >"$tr"
(hook "$(input Stop)" >/dev/null) &
stopper=$!
python3 -I -c 'import sys, time
time.sleep(0.3)
with open(sys.argv[1], "a", encoding="utf-8") as out:
    out.write(sys.argv[2] + "\n")
    out.flush()
    time.sleep(0.15)
    out.write(sys.argv[3] + "\n")' "$tr" "{\"type\":\"progress\",\"timestamp\":\"$T2\"}" "$(ans m2 2 1035 500000 claude-opus-5-5 "$T2")"
wait "$stopper"
expect "Stop: строки идут одна за другой — ждёт, пока переписка затихнет" message m2
reset; ans m1 2 1035 448622 >"$tr"
started=$(python3 -I -c 'import time; print(time.time())')
quiet_run "Stop без новых строк" "$(input Stop)"
took=$(python3 -I -c 'import sys, time; print(round(time.time() - float(sys.argv[1]), 1))' "$started")
expect "Stop без новых строк — пишет то, что есть" message m1
if python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 3 else 1)' "$took"; then ok
else bad "Stop без новых строк: ожидание ограничено" "ждал $took с"; fi
started=$(python3 -I -c 'import time; print(time.time())')
ans m2 2 1035 500000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "PostToolUse не ждёт" "$(input PostToolUse)"
took=$(python3 -I -c 'import sys, time; print(round(time.time() - float(sys.argv[1]), 1))' "$started")
if python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) < 1 else 1)' "$took"; then ok
else bad "PostToolUse не ждёт переписку" "ждал $took с"; fi

# --- порядок: два хука одной сессии ---
reset; ans m1 2 1035 448622 >"$tr"
mkdir -p "$folder"
rm -f "$work/read-mark"
(hook "$(input)" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_PAUSE=1.2 WINDOW_FILL_TEST_READ="$work/read-mark" >/dev/null) &
first=$!
for _ in $(seq 1 100); do [ -e "$work/read-mark" ] && break; python3 -I -c 'import time; time.sleep(0.05)'; done
ans m2 2 1035 500000 claude-opus-5-5 "$T2" >>"$tr"
quiet_run "второй хук ждёт блокировку" "$(input UserPromptSubmit)"
wait "$first"
if [ -e "$work/read-mark" ]; then ok; else bad "гонка: первый хук дошёл до паузы" "метки нет"; fi
expect_many "порядок: в файле чтение последнего держателя блокировки" message=m2 event=UserPromptSubmit
reset; ans m1 2 1035 448622 >"$tr"
quiet_run "пауза без WINDOW_FILL_TEST не действует" "$(input)" WINDOW_FILL_TEST_PAUSE=5 WINDOW_FILL_TEST_READ="$work/never"
if [ ! -e "$work/never" ]; then ok; else bad "пауза без WINDOW_FILL_TEST" "метка появилась"; fi

# --- блокировка занята ---
reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$folder"; rm -f "$work/held"
python3 -I -c 'import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(float(sys.argv[3]))' "$folder/.lock" "$work/held" 4 &
holder=$!
for _ in $(seq 1 100); do [ -e "$work/held" ] && break; python3 -I -c 'import time; time.sleep(0.05)'; done
started=$(python3 -I -c 'import time; print(time.time())')
quiet_run "блокировка занята" "$(input)"
took=$(python3 -I -c 'import sys, time; print(round(time.time() - float(sys.argv[1]), 1))' "$started")
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; holder=""
no_file "блокировка занята дольше 2 с — файл не меняется"
if python3 -I -c 'import sys; sys.exit(0 if 1.9 <= float(sys.argv[1]) < 3.5 else 1)' "$took"; then ok
else bad "блокировка: ожидание около 2 с" "ждал $took с"; fi
quiet_run "блокировка свободна" "$(input)"
expect "блокировка свободна — пишет" message m1
if [ -f "$folder/.lock" ]; then ok; else bad ".lock остаётся" "$(ls -a "$folder")"; fi

# --- кто не пишет ---
reset; ans m1 2 1035 448622 >"$tr"
quiet_run "подагент" "$(input PostToolUse ',"agent_id":"a1b2"')"; no_file "подагент не пишет"
quiet_run "подагент с пустым id" "$(input PostToolUse ',"agent_id":""')"; no_file "agent_id пустой — всё равно подагент"
quiet_run "agent_id null" "$(input PostToolUse ',"agent_id":null')"
expect "agent_id null — главная сессия" message m1
attended_case() {  # attended_case <пишет: yes|no> <VAR=value ...>
  local want=$1; shift
  fresh_root
  printf '%s' "$(input)" | env -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_ENTRYPOINT HATS_STATE_HOME="$root" "$@" \
    python3 -I "$HOOK" >/dev/null 2>&1
  local got=no; [ -e "$own" ] && got=yes
  local handoff
  handoff=$(env -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_ENTRYPOINT "$@" python3 -I -B -c 'import importlib.util, sys
spec = importlib.util.spec_from_file_location("handoff", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print("no" if module.unattended() else "yes")' "$plugin_root/scripts/handoff.py" 2>&1)
  local snapshot=no common
  rm -rf "$work/snap"; mkdir -p "$work/snap"
  printf '{"session_id":"s1","background_tasks":[],"session_crons":[]}' |
    env -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_ENTRYPOINT -u STOP_SNAPSHOT_TEST -u STOP_SNAPSHOT_TEST_PAUSE \
      -u STOP_SNAPSHOT_TEST_MARK HATS_STATE_HOME="$work/snap" "$@" \
    python3 -I "$plugin_root/scripts/stop-snapshot.py" >/dev/null 2>&1
  [ -e "$work/snap/stop-snapshots/s1.json" ] && snapshot=yes
  common=$(env -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_ENTRYPOINT "$@" python3 -I -B -c 'import sys
sys.path.insert(0, sys.argv[1])
import hats_common
print("no" if hats_common.unattended() else "yes")' "$plugin_root/scripts" 2>&1)
  if [ "$got" = "$want" ] && [ "$handoff" = "$want" ] && [ "$snapshot" = "$want" ] && [ "$common" = "$want" ]; then ok
  else bad "без человека: $* — пишут $want window-fill, handoff, stop-snapshot и hats_common" \
    "window-fill: $got, handoff: $handoff, stop-snapshot: $snapshot, hats_common: $common"; fi
}
attended_case no CLAUDE_CODE_SESSION_ATTENDED=0
attended_case no "CLAUDE_CODE_SESSION_ATTENDED= 0 "
attended_case yes CLAUDE_CODE_SESSION_ATTENDED=1
attended_case no CLAUDE_CODE_ENTRYPOINT=sdk-ts
attended_case no CLAUDE_CODE_ENTRYPOINT=sdk-py
attended_case yes CLAUDE_CODE_ENTRYPOINT=cli
attended_case yes CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=sdk-ts
attended_case no CLAUDE_CODE_SESSION_ATTENDED=0 CLAUDE_CODE_ENTRYPOINT=cli
attended_case yes

# --- плохой вход ---
reset; ans m1 2 1035 448622 >"$tr"
bad_input() {  # bad_input <название> <вход>
  fresh_root
  quiet_run "$1" "$2"
  if [ ! -d "$folder" ] || [ -z "$(ls "$folder" | grep -v '^\.lock$')" ]; then ok; else bad "$1: не пишет" "$(ls -a "$folder")"; fi
}
bad_input "не JSON" "не json"
bad_input "JSON не объект" "[1]"
bad_input "пустой вход" ""
bad_input "transcript_path пуст" "$(input PostToolUse "" "")"
bad_input "transcript_path нет" "$(printf '{"session_id":"%s","hook_event_name":"Stop"}' "$sid")"
bad_input "transcript_path не строка" "$(printf '{"session_id":"%s","transcript_path":5}' "$sid")"
bad_input "transcript_path — папка" "$(input PostToolUse "" "$work")"
bad_input "transcript_path — нет файла" "$(input PostToolUse "" "$work/nope.jsonl")"
mkfifo "$work/fifo"
started=$(python3 -I -c 'import time; print(time.time())')
bad_input "transcript_path — именованный канал" "$(input PostToolUse "" "$work/fifo")"
if python3 -I -c 'import sys, time; sys.exit(0 if time.time() - float(sys.argv[1]) < 2 else 1)' "$started"; then ok
else bad "именованный канал не ждёт писателя" "дольше 2 с"; fi
for bad_sid in "" "../x" "a b" "a/b" "abc.json" "$(python3 -I -c 'print("a" * 81)')" "ид"; do
  bad_input "session_id «${bad_sid:0:20}»" \
    "$(printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop"}' "$bad_sid" "$tr")"
done
bad_input "session_id не строка" "$(printf '{"session_id":5,"transcript_path":"%s"}' "$tr")"
fresh_root
long_ok=$(python3 -I -c 'print("A1-" * 26 + "z9")')
quiet_run "session_id 80 знаков" "$(printf '{"session_id":"%s","transcript_path":"%s"}' "$long_ok" "$tr")"
if [ -f "$folder/$long_ok.json" ]; then ok; else bad "session_id 80 знаков — пишет" "$(ls -a "$folder" 2>&1)"; fi

# --- неожиданная ошибка: строка в failures.log, а не тишина ---
failures_log="$folder/failures.log"
failure_line() {  # failure_line [файл] — поля последней строки журнала ошибок
  python3 -I -c 'import json,sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
d = json.loads(lines[-1])
print(len(lines), sorted(d), d["script"], d["event"], d["error"], len(d["at"]))' "${1:-$failures_log}" 2>&1
}
reset_failures() { reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$folder"; }
reset_failures
quiet_run "неожиданная ошибка" "$(input)" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_FAIL=1
got=$(failure_line)
if [ "$got" = "1 ['at', 'error', 'event', 'script'] window-fill.py PostToolUse RuntimeError 20" ]; then ok
else bad "неожиданная ошибка: одна строка {at, script, event, error}" "$got"; fi
if [ "$(stat -f '%Lp' "$failures_log" 2>/dev/null || stat -c '%a' "$failures_log")" = 600 ]; then ok
else bad "неожиданная ошибка: журнал 600" "$(ls -l "$failures_log")"; fi
if [ ! -e "$own" ]; then ok; else bad "неожиданная ошибка: своего файла нет" "$(cat "$own")"; fi
reset_failures
quiet_run "ошибка без WINDOW_FILL_TEST не включается" "$(input)" WINDOW_FILL_TEST_FAIL=1
if [ ! -e "$failures_log" ] && [ -f "$own" ]; then ok; else bad "WINDOW_FILL_TEST_FAIL без WINDOW_FILL_TEST: пишет файл, журнала нет" "$(ls -A "$folder")"; fi
long_path="$work/$(python3 -I -c 'print("n" * 300)').jsonl"
for case_ in "нет файла|$work/nope.jsonl" "путь сквозь файл|$tr/x.jsonl" "имя длиннее предела|$long_path"; do
  reset_failures
  quiet_run "переписка: ${case_%%|*}" "$(input PostToolUse "" "${case_#*|}")"
  if [ ! -e "$failures_log" ] && [ ! -e "$own" ]; then ok
  else bad "переписка: ${case_%%|*} — пропуск, журнала ошибок нет" "$(ls -A "$folder")"; fi
done
for case_ in "нулевой байт в пути переписки|$(input PostToolUse "" "$tr\\u0000x")" \
  "событие — список|$(printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":["Stop"]}' "$sid" "$tr")"; do
  reset_failures
  quiet_run "${case_%%|*}" "${case_#*|}"
  if [ ! -e "$failures_log" ] && [ ! -e "$own" ]; then ok
  else bad "${case_%%|*} — плохой ввод: ни записи, ни журнала ошибок" "$(ls -A "$folder")"; fi
done
if [ "$(id -u)" -ne 0 ]; then
  reset_failures; chmod 000 "$tr"
  quiet_run "переписку не прочитать" "$(input)"
  got=$(failure_line)
  if [ "$got" = "1 ['at', 'error', 'event', 'script'] window-fill.py PostToolUse PermissionError 20" ]; then ok
  else bad "переписку не прочитать: строка в журнале ошибок, а не тишина" "$got"; fi
  chmod 600 "$tr"
fi
for data in 'не json' '[1]' ''; do
  reset_failures
  quiet_run "битый ввод «${data}» при готовой папке" "$data" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_FAIL=1
  if [ ! -e "$failures_log" ]; then ok; else bad "битый ввод «${data}»: журнала ошибок нет" "$(cat "$failures_log")"; fi
done
reset_failures
python3 -I -c 'import sys; open(sys.argv[1], "w").write("x" * 70000)' "$failures_log"
quiet_run "ротация журнала ошибок" "$(input)" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_FAIL=1
if [ "$(wc -c <"$failures_log.1" | tr -d ' ')" = 70000 ] && [ "$(failure_line | cut -d' ' -f1)" = 1 ]; then ok
else bad "ротация: старый журнал в .1, новый с одной строкой" "$(ls -l "$folder")"; fi
reset_failures
quiet_run "журнал ниже предела не ротируется" "$(input)" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_FAIL=1
quiet_run "журнал ниже предела не ротируется" "$(input)" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_FAIL=1
if [ ! -e "$failures_log.1" ] && [ "$(failure_line | cut -d' ' -f1)" = 2 ]; then ok
else bad "журнал ниже предела: две строки, без .1" "$(ls -l "$folder")"; fi
reset_failures; ln -s "$work/fail-target" "$failures_log"; printf 'keep\n' >"$work/fail-target"
quiet_run "журнал ошибок — ссылка" "$(input)" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_FAIL=1
if [ "$(cat "$work/fail-target")" = keep ] && [ -L "$failures_log" ]; then ok
else bad "журнал ошибок — ссылка: цель не тронута" "$(cat "$work/fail-target") $(ls -l "$folder")"; fi
reset_failures; mkfifo "$failures_log"
out=$(printf '%s' "$(input)" | timeout 3 env HATS_STATE_HOME="$root" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_FAIL=1 python3 -I "$HOOK" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then ok; else bad "журнал ошибок — канал: хук не ждёт и молчит, код 0" "rc=$rc out=${out:0:300}"; fi
reset; mkdir -p "$work/elsewhere-f"; ln -s "$work/elsewhere-f" "$folder"
got=$(env HATS_STATE_HOME="$root" python3 -I -c 'import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("hook", sys.argv[1])
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
hook.record_hook_failure(
    hook.FOLDER,
    "window-fill.py",
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
    "window-fill.py",
    {},
    RuntimeError("t"),
)
print("ok")' "$HOOK" 2>&1)
if [ "$got" = ok ] && [ ! -e "$root" ]; then ok; else bad "корня нет: журнал ошибок не пишется, корень не создан" "$got"; fi


# --- папка ---
reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$root" "$work/elsewhere"
ln -s "$work/elsewhere" "$folder"
quiet_run "папка — ссылка" "$(input)"
if [ -z "$(ls -A "$work/elsewhere")" ]; then ok; else bad "папка — ссылка: не пишет" "$(ls -a "$work/elsewhere")"; fi
rm -f "$folder"; printf 'x' >"$folder"
quiet_run "папка — файл" "$(input)"
if [ "$(cat "$folder")" = x ]; then ok; else bad "папка — файл: не трогается" "$(ls -la "$root")"; fi
reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$folder"; printf '{"x":1}' >"$work/target.json"
ln -s "$work/target.json" "$own"
quiet_run "свой файл — ссылка" "$(input)"
if [ "$(cat "$work/target.json")" = '{"x":1}' ] && [ -f "$own" ] && [ ! -L "$own" ]; then ok
else bad "свой файл — ссылка: цель не тронута, ссылка заменена файлом" "$(ls -la "$folder")"; fi
reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$folder"
printf '{"session":"other","compactions":7,"compaction":"b0","title":"чужое"}' >"$own"
quiet_run "чужой файл под своим именем" "$(input)"
expect_many "чужой файл не переносится" compactions=0 compaction=null title=null message=m1
printf '{"session":"%s","compactions":3,"compaction":"b0","compacted_at":"%s","title":"моё"}' "$sid" "$T0" >"$own"
quiet_run "свой прежний файл" "$(input)"
expect_many "свой прежний файл переносится" compactions=3 compaction=b0 compacted_at="$T0" title="моё"

# --- корень ---
reset; ans m1 2 1035 448622 >"$tr"
mkdir -p "$work/home/Library/Application Support/Hats" "$work/home2/Library/Application Support/Hats"
printf '%s' "$(input)" | env -u HATS_STATE_HOME HOME="$work/home" python3 -I "$HOOK" >/dev/null 2>&1
if [ -f "$work/home/Library/Application Support/Hats/session-windows/$sid.json" ]; then ok
else bad "без HATS_STATE_HOME — ~/Library/Application Support/Hats" "$(find "$work/home" 2>&1 | head -5)"; fi
printf '%s' "$(input)" | env HATS_STATE_HOME= HOME="$work/home2" python3 -I "$HOOK" >/dev/null 2>&1
if [ -f "$work/home2/Library/Application Support/Hats/session-windows/$sid.json" ]; then ok
else bad "пустой HATS_STATE_HOME — как без него" "$(find "$work/home2" 2>&1 | head -5)"; fi
where=$(env HATS_STATE_HOME="$work/x y" python3 -I "$HOOK" where 2>&1)
if [ "$where" = "$work/x y/session-windows" ]; then ok; else bad "where с HATS_STATE_HOME" "$where"; fi
where=$(env -u HATS_STATE_HOME HOME="$work/home" python3 -I "$HOOK" where 2>&1)
notes=$(env -u HATS_STATE_HOME HOME="$work/home" python3 -I -B -c 'import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("handoff", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(os.path.dirname(module.get_notes_root()))' "$plugin_root/scripts/handoff.py" 2>&1)
if [ "$where" = "$work/home/Library/Application Support/Hats/session-windows" ] && [ "$where" = "$notes/session-windows" ]; then ok
else bad "where без HATS_STATE_HOME — корень записок handoff.py" "where=$where handoff=$notes"; fi
if [ ! -e "$work/x y" ]; then ok; else bad "where ничего не пишет" "$(ls -a "$work/x y")"; fi
printf '%s' "$(input)" | env -u HATS_STATE_HOME HOME="$work/home3" python3 -I "$HOOK" >/dev/null 2>&1
if [ ! -e "$work/home3" ]; then ok; else bad "Hats ни разу не запускался — ничего не создаётся" "$(find "$work/home3" | head -5)"; fi
printf '%s' "$(input)" | env HATS_STATE_HOME="$work/missing-root" python3 -I "$HOOK" >/dev/null 2>&1
if [ ! -e "$work/missing-root" ]; then ok
else bad "HATS_STATE_HOME нет на диске — ничего не создаётся" "$(find "$work/missing-root" | head -5)"; fi
if [ -z "$(find "$(dirname "$HOOK")/__pycache__" -name '*.pyc' 2>/dev/null)" ]; then ok
else bad "байт-код соседей хука не пишется в плагин" "$(ls "$(dirname "$HOOK")/__pycache__")"; fi

# --- одно правило корня на четырёх скриптах: window-fill.py, stop-snapshot.py, handoff.py (get_state_root
# в hats_common.py) и window.py плагина Codex (своя копия, hats_codex.get_hats_root). Абсолютный —
# в нём; пустой или не задан — ~/Library/Application Support/Hats; любой другой — корня нет, ничего не пишется
CODEX_WINDOW="$plugin_root/../codex-plugin/scripts/window.py"
rr="$work/rr"
rr_hats="$rr/home/Library/Application Support/Hats"
CODEX_COUNT='{"timestamp":"t","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":'
CODEX_COUNT+='{"input_tokens":190000,"cached_input_tokens":0,"output_tokens":7,"total_tokens":190000},'
CODEX_COUNT+='"model_context_window":475000},"rate_limits":null}}\n'
rr_run() {  # rr_run <скрипт> <HATS_STATE_HOME | -unset> — запуск из $rr/run с HOME=$rr/home; вывод — в $rr/out
  local script=$1 value=$2 set_root=()
  if [ "$value" = -unset ]; then set_root=(-u HATS_STATE_HOME); else set_root=(HATS_STATE_HOME="$value"); fi
  case $script in
    window-fill) printf '%s' "$(input UserPromptSubmit)" | (cd "$rr/run" && env "${set_root[@]}" HOME="$rr/home" python3 -I "$HOOK") ;;
    stop-snapshot) printf '{"session_id":"s1","background_tasks":[],"session_crons":[]}' |
      (cd "$rr/run" && env -u STOP_SNAPSHOT_TEST "${set_root[@]}" HOME="$rr/home" python3 -I "$plugin_root/scripts/stop-snapshot.py") ;;
    handoff) (cd "$rr/run" && env "${set_root[@]}" HOME="$rr/home" python3 -I "$plugin_root/scripts/handoff.py" where --cwd "$rr/run") ;;
    codex) printf '{"session_id":"%s","transcript_path":"%s","cwd":"/w","hook_event_name":"UserPromptSubmit"}' "$sid" "$rr/codex.jsonl" |
      (cd "$rr/run" && env "${set_root[@]}" HOME="$rr/home" TMPDIR="$rr/tmp" python3 -I "$CODEX_WINDOW") ;;
  esac >"$rr/out" 2>&1
  echo $? >"$rr/rc"
}
rr_made() {  # rr_made <скрипт> <корень> — файл, который скрипт оставляет в корне
  case $1 in
    window-fill) printf '%s' "$2/session-windows/$sid.json" ;;
    stop-snapshot) printf '%s' "$2/stop-snapshots/s1.json" ;;
    handoff) printf '%s' "$(find "$2/notes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)" ;;
    codex) printf '%s' "$2/codex-windows/$sid.json" ;;
  esac
}
rr_listing() { find "$rr" -mindepth 1 -not -path "$rr/out" -not -path "$rr/rc" 2>/dev/null | sort; }
rr_said() {  # rr_said <скрипт> <ждём> <HATS_STATE_HOME> <файл в корне> — ожидаемые «код вывод»
  if [ "$1" != handoff ]; then printf '0 '; return; fi
  if [ "$2" = none ]; then printf "1 handoff: HATS_STATE_HOME='%s' is not an absolute path, so there is no Hats folder" "$3"
  else printf '0 %s' "$4"; fi
}
root_rule() {  # root_rule <HATS_STATE_HOME | -unset | -abs> <ждём: abs | default | none>
  local value=$1 want=$2 script made extra value_now base before said want_said
  for script in window-fill stop-snapshot handoff codex; do
    rm -rf "$rr"; mkdir -p "$rr/run/rel" "$rr/run/x" "$rr/run/~/x" "$rr/home/x" "$rr_hats" "$rr/abs" "$rr/tmp"
    ans m1 2 1035 448622 >"$tr"; printf "$CODEX_COUNT" >"$rr/codex.jsonl"
    if [ "$value" = -abs ]; then value_now="$rr/abs"; else value_now=$value; fi
    case $want in
      abs) base="$rr/abs" ;;
      default) base=$rr_hats ;;
      none) base="$rr/no-root" ;;
    esac
    before=$(rr_listing)
    rr_run "$script" "$value_now"
    extra=$(diff <(printf '%s\n' "$before") <(rr_listing) | grep -vF -- "> $base/" | grep '^[<>]')
    if [ "$want" = none ]; then made="$rr"; else made=$(rr_made "$script" "$base"); fi
    said="$(cat "$rr/rc") $(cat "$rr/out")"
    want_said=$(rr_said "$script" "$want" "$value_now" "$made")
    if [ -n "$made" ] && [ -e "$made" ] && [ -z "$extra" ] && [ "$said" = "$want_said" ]; then ok
    else bad "правило корня: $script, HATS_STATE_HOME «${value}» — ${want}" \
      "made=$made extra=${extra:0:300} ждали «${want_said}» получили «${said:0:300}»"; fi
  done
}
root_rule -abs abs
root_rule -unset default
root_rule "" default
root_rule rel none
root_rule ./x none
root_rule "~/x" none
where=$(cd "$rr/run" && env HATS_STATE_HOME=rel python3 -I "$HOOK" where 2>&1); rc=$?
if [ $rc -eq 1 ] && [ "$where" = "window-fill: HATS_STATE_HOME='rel' is not an absolute path, so there is no Hats folder" ]; then ok
else bad "правило корня: window-fill.py where без корня — одна строка, код 1" "rc=$rc $where"; fi
got=$(env HATS_STATE_HOME=rel HOME="$rr/home" python3 -I -c 'import importlib.util, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("hook", sys.argv[1])
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)
hook.record_hook_failure(
    hook.FOLDER,
    "window-fill.py",
    {},
    RuntimeError("t"),
)
print("ok")' "$HOOK" 2>&1)
if [ "$got" = ok ] && [ -z "$(find "$rr_hats" -mindepth 1)" ]; then ok
else bad "правило корня: журнал ошибок без корня не пишется" "$got $(find "$rr_hats" -mindepth 1 | head -3)"; fi

# --- get_field: строка обрезается до 80 знаков, не строка — null
fields=$(python3 -I -B -c 'import sys
sys.path.insert(0, sys.argv[1])
import hats_common
print(len(hats_common.get_field("я" * 81)), hats_common.get_field("x" * 80) == "x" * 80, hats_common.get_field("ab"))
print(*(hats_common.get_field(value) for value in (None, 7, ["a"], b"ab")))' "$plugin_root/scripts" 2>&1)
if [ "$fields" = "80 True ab
None None None None" ]; then ok; else bad "get_field: до 80 знаков, не строка — None" "$fields"; fi

# --- уборка ---
ago() { python3 -I -c 'import sys, time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - float(sys.argv[1]))))' "$1"; }
litter() {  # litter — файлы для уборки с нужным возрастом
  for name in old-1.json fresh-1.json notes.txt .lock .tmp-oldone.json .tmp-newone.json .tmp-old.txt; do
    printf '{}' >"$folder/$name"
  done
  mkdir -p "$folder/old-dir.json"
  printf 'keep' >"$work/link-target"; ln -sf "$work/link-target" "$folder/old-link.json"
  touch -h -t "$(ago $((31 * 86400)))" "$folder/old-link.json"
  touch -t "$(ago $((31 * 86400)))" "$folder/old-1.json" "$folder/notes.txt" "$folder/.lock" "$folder/old-dir.json"
  touch -t "$(ago $((29 * 86400)))" "$folder/fresh-1.json"
  touch -t "$(ago 660)" "$folder/.tmp-oldone.json" "$folder/.tmp-old.txt"
  touch -t "$(ago 120)" "$folder/.tmp-newone.json"
}
swept_ok() {  # swept_ok <событие>
  if [ ! -e "$folder/old-1.json" ] && [ ! -e "$folder/.tmp-oldone.json" ]; then ok
  else bad "уборка на $1: файл старше 30 дней и временный старше 10 минут удалены" "$(ls -a "$folder")"; fi
  for kept in fresh-1.json notes.txt .lock old-dir.json old-link.json .tmp-newone.json .tmp-old.txt; do
    if [ -e "$folder/$kept" ] || [ -L "$folder/$kept" ]; then ok; else bad "уборка на $1: $kept остаётся" "$(ls -a "$folder")"; fi
  done
}
reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$folder"; litter
quiet_run "не Stop — без уборки" "$(input PostToolUse)"
if [ -f "$folder/old-1.json" ] && [ -f "$folder/.tmp-oldone.json" ]; then ok
else bad "уборка только на Stop и SessionEnd" "удалено на PostToolUse: $(ls -a "$folder")"; fi
quiet_run "уборка на Stop" "$(input Stop)"
swept_ok Stop
if [ -e "$own" ]; then ok; else bad "уборка на Stop: свой файл остаётся" "$(ls -a "$folder")"; fi
reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$folder"; litter
quiet_run "уборка на SessionEnd" "$(input SessionEnd ',"reason":"other"')"
swept_ok SessionEnd

# --- конец сессии и сжатие по команде ---
reset; ans m1 2 1035 448622 >"$tr"
quiet_run "до конца сессии" "$(input)"
other="$folder/0000-other.json"; printf '{"session":"0000-other"}' >"$other"
quiet_run "SessionEnd, подагент" "$(input SessionEnd ',"reason":"exit","agent_id":"a1"')"
if [ -e "$own" ]; then ok; else bad "SessionEnd подагента не трогает файл сессии" "файла нет"; fi
quiet_run "SessionEnd без человека" "$(input SessionEnd ',"reason":"exit"')" CLAUDE_CODE_SESSION_ATTENDED=0
if [ -e "$own" ]; then ok; else bad "SessionEnd без человека не трогает файл" "файла нет"; fi
quiet_run "SessionEnd, плохой session_id" \
  "$(printf '{"session_id":"../x","transcript_path":"%s","hook_event_name":"SessionEnd"}' "$tr")"
if [ -e "$own" ]; then ok; else bad "SessionEnd с плохим session_id ничего не удаляет" "файла нет"; fi
for reason in clear exit logout other; do
  quiet_run "SessionEnd $reason, первый прогон" "$(input UserPromptSubmit)"
  quiet_run "SessionEnd $reason" "$(input SessionEnd ",\"reason\":\"$reason\"")"
  if [ ! -e "$own" ]; then ok; else bad "SessionEnd $reason: свой файл удалён, ничего не записано" "$(cat "$own")"; fi
done
if [ -e "$other" ] && [ -f "$folder/.lock" ]; then ok; else bad "SessionEnd: чужой файл и .lock остаются" "$(ls -a "$folder")"; fi
reset; ans m1 2 1035 448622 >"$tr"; mkdir -p "$folder"
(hook "$(input Stop)" >/dev/null) &
late=$!
python3 -I -c 'import time; time.sleep(0.3)'
quiet_run "SessionEnd, пока Stop ждёт переписку" "$(input SessionEnd ',"reason":"clear"')"
wait "$late"
no_file "Stop, дождавшийся переписки после SessionEnd, не возвращает файл сессии"
quiet_run "PostToolUse после SessionEnd" "$(input)"
no_file "PostToolUse после SessionEnd не возвращает файл сессии"
quiet_run "UserPromptSubmit после SessionEnd — сессию продолжили" "$(input UserPromptSubmit)"
expect "продолженная сессия снова пишет свой файл" event UserPromptSubmit
quiet_run "SessionEnd снова" "$(input SessionEnd ',"reason":"exit"')"
touch -t "$(ago 660)" "$folder/.ended-$sid"; printf '' >"$folder/.ended-fresh"
quiet_run "уборка отметок конца" "$(input Stop)"
if [ ! -e "$folder/.ended-$sid" ] && [ -e "$folder/.ended-fresh" ]; then ok
else bad "уборка: отметка конца старше 10 минут удалена, свежая остаётся" "$(ls -a "$folder")"; fi
reset; { ans m1 2 1035 448622; boundary b1 "$T1"; summary 1 "$T1"; } >"$tr"
quiet_run "SessionStart после /compact" "$(input SessionStart ',"source":"compact"')"
expect_many "SessionStart compact — мерит как обычно" state=compacted tokens=null compactions=1 event=SessionStart

# --- SIGTERM посреди работы ---
reset; ans m1 2 1035 448622 >"$tr"; rm -f "$work/read-mark"; input >"$work/in.json"
env HATS_STATE_HOME="$root" WINDOW_FILL_TEST=1 WINDOW_FILL_TEST_PAUSE=5 WINDOW_FILL_TEST_READ="$work/read-mark" \
  python3 -I "$HOOK" <"$work/in.json" >"$work/term-out.txt" 2>&1 &
paused=$!
for _ in $(seq 1 100); do [ -e "$work/read-mark" ] && break; python3 -I -c 'import time; time.sleep(0.05)'; done
kill -TERM "$paused"; wait "$paused"; rc=$?
if [ -e "$work/read-mark" ] && [ $rc -eq 0 ] && [ ! -s "$work/term-out.txt" ]; then ok
else bad "SIGTERM: код 0 и молча" "rc=$rc out=$(head -c 300 "$work/term-out.txt")"; fi
if ls -a "$folder" | grep -q '^\.tmp-'; then bad "SIGTERM: временного файла нет" "$(ls -a "$folder")"; else ok; fi

# --- hooks.json ---
hooks_ok=$(python3 -I -c 'import json, sys
hooks = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
want = "sh \"${CLAUDE_PLUGIN_ROOT}/scripts/py.sh\" --quiet \"${CLAUDE_PLUGIN_ROOT}/scripts/window-fill.py\""
found = {}
for event, groups in hooks.items():
    for group in groups:
        for hook in group["hooks"]:
            if "window-fill.py" in hook["command"]:
                found.setdefault(event, []).append(hook)
assert sorted(found) == ["PostToolUse", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"], sorted(found)
for event, entries in found.items():
    assert len(entries) == 1, event
    hook = entries[0]
    assert hook == {"type": "command", "command": want, "async": True, "timeout": 5}, hook
    group = [g for g in hooks[event] if hook in g["hooks"]][0]
    assert group.get("matcher") == ("compact" if event == "SessionStart" else None), (event, group)
print("ok")' "$plugin_root/hooks/hooks.json" 2>&1)
if [ "$hooks_ok" = ok ]; then ok; else bad "hooks.json: пять записей в фоне через py.sh --quiet" "$hooks_ok"; fi

total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "window-fill: $pass/$total прошли"; exit 0; fi
echo "window-fill: $pass/$total прошли, $fail упало$failures"; exit 1
