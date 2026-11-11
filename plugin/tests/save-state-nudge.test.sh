#!/usr/bin/env bash
# Матрица для save-state-nudge.py: если в переписке сессии скилл save-state уже вызывался —
# напоминание к каждому следующему сообщению, на любом языке; если нет — тишина.
# Текст сообщения пользователя не важен и в журнал не попадает. Журнал — во временном HOME.
#   bash plugin/tests/save-state-nudge.test.sh
#   HOOK_UNDER_TEST=/path/to/candidate.py bash plugin/tests/save-state-nudge.test.sh
set -uo pipefail
HOOK="${HOOK_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/save-state-nudge.py}"
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/save-nudge-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

tr="$work/t.jsonl"
call='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"%s"}}]}}\n'
line() { printf '{"type":"user","message":{"content":"%s"}}\n' "$1"; }
run() {  # run <prompt> [transcript]
  python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s1","prompt":sys.argv[1],"transcript_path":sys.argv[2],"hook_event_name":"UserPromptSubmit"}))' "$1" "${2:-$tr}" |
    env HOME="$work" python3 -I "$HOOK" 2>&1
}
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }
reminded() {
  local out; out=$(run "$2")
  if printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="UserPromptSubmit"; assert "save-state" in d["additionalContext"]' 2>/dev/null; then ok
  else bad "напоминание: $1" "получили: ${out:0:200}"; fi
}
silent() {
  local out; out=$(run "$2"); rc=$?
  if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "тишина: $1" "rc=$rc получили: ${out:0:200}"; fi
}

{ line "сохранись"; printf "$call" "save-state"; } >"$tr"
reminded "после вызова скилла — по-русски" "сохранись"
reminded "после вызова скилла — по-английски" "save your state please"
reminded "после вызова скилла — по-украински" "збережись"
reminded "после вызова скилла — любое сообщение" "что дальше?"
reminded "после вызова скилла — пустое сообщение" ""
{ line "x"; printf "$call" "hats:save-state"; } >"$tr"
reminded "скилл из плагина с приставкой" "save"
printf '{"type":"user","message":{"content":"<command-message>save-state</command-message>\\n<command-name>/save-state</command-name>"}}\n' >"$tr"
reminded "набранная команда /save-state" "save"
printf '{"type":"user","message":{"content":"<command-message>hats:save-state</command-message>\\n<command-name>/hats:save-state</command-name>"}}\n' >"$tr"
reminded "набранная команда скилла из плагина" "save"

{ line "сохранись"; printf "$call" "slack"; } >"$tr"
silent "вызывался другой скилл" "сохранись"
{ line "x"; printf "$call" "save-states"; } >"$tr"
silent "скилл с похожим именем" "save"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"grep \\"name\\":\\"Skill\\",\\"input\\":{\\"skill\\":\\"save-state\\"}"}]}}\n' >"$tr"
silent "строка вызова внутри текста (экранированная) — не вызов" "save"
printf '{"type":"user","message":{"content":"см. <command-name>/save-state</command-name>"}}\n' >"$tr"
silent "команда, упомянутая в середине текста, — не вызов" "save"
printf '{"type":"user","message":{"content":"<command-name>/save-state</command-name> и дальше текст"}}\n' >"$tr"
silent "один тег команды в начале текста — не вызов" "save"
printf '{"type":"user","message":{"content":"см. <command-message>save-state</command-message>\\n<command-name>/save-state</command-name>"}}\n' >"$tr"
silent "пара тегов в середине текста — не вызов" "save"
printf '{"type":"user","message":{"content":"<command-message>save-state</command-message> пример, а дальше <command-name>/save-state</command-name>"}}\n' >"$tr"
silent "между тегами другой текст — не вызов" "save"
line "сохранись" >"$tr"
silent "скилл ещё не вызывался — первая просьба" "сохранись"
: >"$tr"; silent "пустая переписка" "сохранись"
silent "переписки нет на диске" "save" "$work/nope.jsonl"
silent "путь — папка" "save" "$work"

out=$(printf '{"session_id":"s1","prompt":"save"}' | env HOME="$work" python3 -I "$HOOK" 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "нет transcript_path — тишина и код 0" "rc=$rc out=${out:0:200}"; fi
out=$(printf 'не json' | env HOME="$work" python3 -I "$HOOK" 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "битый ввод — тишина и код 0" "rc=$rc out=${out:0:200}"; fi
out=$(printf '[1]' | env HOME="$work" python3 -I "$HOOK" 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "ввод не объект — тишина и код 0" "rc=$rc out=${out:0:200}"; fi

rm -rf "$work/.claude"; { line "x"; printf "$call" "save-state"; } >"$tr"
run "секрет-123" >/dev/null; line "x" >"$work/clean.jsonl"; run "привет" "$work/clean.jsonl" >/dev/null
log="$work/.claude/state/save-state-nudge.tsv"
rows=$(wc -l <"$log" 2>/dev/null | tr -d ' ')
if [ "${rows:-0}" -eq 1 ]; then ok; else bad "журнал: одна строка на одно напоминание" "строк ${rows:-нет файла}"; fi
if grep -q $'\ts1\treminded' "$log" 2>/dev/null; then ok; else bad "журнал: строка несёт номер сессии" "$(cat "$log" 2>/dev/null)"; fi
if grep -q 'секрет' "$log" 2>/dev/null; then bad "журнал: без текста сообщения" "$(cat "$log")"; else ok; fi
mkdir -p "$work/ro/.claude"; printf 'x' >"$work/ro/.claude/state"
out=$(python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s1","prompt":"save","transcript_path":sys.argv[1]}))' "$tr" | env HOME="$work/ro" python3 -I "$HOOK" 2>&1); rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'save-state'; then ok; else bad "журнал не записать — напоминание всё равно есть" "rc=$rc out=${out:0:200}"; fi

total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "save-state-nudge: $pass/$total прошли"; exit 0; fi
echo "save-state-nudge: $pass/$total прошли, $fail упало$failures"; exit 1
