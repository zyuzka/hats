#!/usr/bin/env bash
# Матрица для anchor-nudge.py: если в переписке сессии скилл anchor уже вызывался —
# напоминание к каждому следующему сообщению, на любом языке; если нет — тишина.
# Вызов чужого скилла сохранения (save-state) — не вызов anchor.
# Текст сообщения пользователя не важен и в журнал не попадает. Журнал — в <config>/state,
# где <config> — $CLAUDE_CONFIG_DIR или ~/.claude; здесь — во временной папке.
#   bash plugin/tests/anchor-nudge.test.sh
#   HOOK_UNDER_TEST=/path/to/candidate.py bash plugin/tests/anchor-nudge.test.sh
set -uo pipefail
unset CLAUDE_CONFIG_DIR
HOOK="${HOOK_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/anchor-nudge.py}"
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/anchor-nudge-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

tr="$work/t.jsonl"
call='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"%s"}}]}}\n'
typed='{"type":"user","message":{"content":"<command-message>%s</command-message>\\n<command-name>/%s</command-name>"}}\n'
line() { printf '{"type":"user","message":{"content":"%s"}}\n' "$1"; }
input() { python3 -I -c 'import json,sys; print(json.dumps({"session_id":"s1","prompt":sys.argv[1],"transcript_path":sys.argv[2],"hook_event_name":"UserPromptSubmit"}))' "$1" "$2"; }
run() {  # run <prompt> [transcript]
  input "$1" "${2:-$tr}" | env HOME="$work" python3 -I "$HOOK" 2>&1
}
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }
names_anchor() {
  printf '%s' "$1" | python3 -I -c 'import json,sys
d = json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"] == "UserPromptSubmit"
assert "anchor" in d["additionalContext"] and "save-state" not in d["additionalContext"]' 2>/dev/null
}
reminded() {
  local out; out=$(run "$2")
  if names_anchor "$out"; then ok; else bad "напоминание: $1" "получили: ${out:0:200}"; fi
}
silent() {
  local out; out=$(run "$2" "${3:-$tr}"); rc=$?
  if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "тишина: $1" "rc=$rc получили: ${out:0:200}"; fi
}

{ line "анкор"; printf "$call" "hats:anchor"; } >"$tr"
reminded "после вызова скилла — по-русски" "анкор"
reminded "после вызова скилла — по-английски" "anchor"
reminded "после вызова скилла — по-украински" "якір"
reminded "после вызова скилла — любое сообщение" "что дальше?"
reminded "после вызова скилла — пустое сообщение" ""
{ line "x"; printf "$call" "anchor"; } >"$tr"
reminded "скилл без приставки плагина" "anchor"
printf "$typed" "hats:anchor" "hats:anchor" >"$tr"
reminded "набранная команда /hats:anchor" "anchor"
printf "$typed" "anchor" "anchor" >"$tr"
reminded "набранная команда без приставки" "anchor"

{ line "сохранись"; printf "$call" "save-state"; } >"$tr"
silent "вызывался только save-state" "сохранись"
printf "$typed" "save-state" "save-state" >"$tr"
silent "набран только /save-state" "сохранись"
{ line "сохранись"; printf "$call" "slack"; } >"$tr"
silent "вызывался другой скилл" "анкор"
{ line "x"; printf "$call" "anchors"; } >"$tr"
silent "скилл с похожим именем" "anchor"
{ line "x"; printf "$call" "hats:anchored"; } >"$tr"
silent "скилл плагина с похожим именем" "anchor"
{ line "x"; printf "$call" "other:anchor"; } >"$tr"
silent "other:anchor — скилл чужого плагина" "anchor"
printf "$typed" "other:anchor" "other:anchor" >"$tr"
silent "набранная /other:anchor — команда чужого плагина" "anchor"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"grep \\"name\\":\\"Skill\\",\\"input\\":{\\"skill\\":\\"hats:anchor\\"}"}]}}\n' >"$tr"
silent "строка вызова внутри текста (экранированная) — не вызов" "anchor"
printf '{"type":"user","message":{"content":"см. <command-name>/hats:anchor</command-name>"}}\n' >"$tr"
silent "команда, упомянутая в середине текста, — не вызов" "anchor"
printf '{"type":"user","message":{"content":"<command-name>/hats:anchor</command-name> и дальше текст"}}\n' >"$tr"
silent "один тег команды в начале текста — не вызов" "anchor"
printf '{"type":"user","message":{"content":"см. <command-message>hats:anchor</command-message>\\n<command-name>/hats:anchor</command-name>"}}\n' >"$tr"
silent "пара тегов в середине текста — не вызов" "anchor"
printf '{"type":"user","message":{"content":"<command-message>hats:anchor</command-message> пример, а дальше <command-name>/hats:anchor</command-name>"}}\n' >"$tr"
silent "между тегами другой текст — не вызов" "anchor"
line "анкор" >"$tr"
silent "скилл ещё не вызывался — первая команда" "анкор"
: >"$tr"; silent "пустая переписка" "анкор"
silent "переписки нет на диске" "anchor" "$work/nope.jsonl"
silent "путь — папка" "anchor" "$work"

out=$(printf '{"session_id":"s1","prompt":"anchor"}' | env HOME="$work" python3 -I "$HOOK" 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "нет transcript_path — тишина и код 0" "rc=$rc out=${out:0:200}"; fi
out=$(printf 'не json' | env HOME="$work" python3 -I "$HOOK" 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "битый ввод — тишина и код 0" "rc=$rc out=${out:0:200}"; fi
out=$(printf '[1]' | env HOME="$work" python3 -I "$HOOK" 2>&1); rc=$?
if [ -z "$out" ] && [ $rc -eq 0 ]; then ok; else bad "ввод не объект — тишина и код 0" "rc=$rc out=${out:0:200}"; fi

rm -rf "$work/.claude"; { line "x"; printf "$call" "hats:anchor"; } >"$tr"
run "секрет-123" >/dev/null; line "x" >"$work/clean.jsonl"; run "привет" "$work/clean.jsonl" >/dev/null
log="$work/.claude/state/anchor-nudge.tsv"
rows=$(wc -l <"$log" 2>/dev/null | tr -d ' ')
if [ "${rows:-0}" -eq 1 ]; then ok; else bad "журнал: одна строка на одно напоминание" "строк ${rows:-нет файла}"; fi
if grep -q $'\ts1\treminded' "$log" 2>/dev/null; then ok; else bad "журнал: строка несёт номер сессии" "$(cat "$log" 2>/dev/null)"; fi
if grep -q 'секрет' "$log" 2>/dev/null; then bad "журнал: без текста сообщения" "$(cat "$log")"; else ok; fi
mkdir -p "$work/ro/.claude"; printf 'x' >"$work/ro/.claude/state"
out=$(input "anchor" "$tr" | env HOME="$work/ro" python3 -I "$HOOK" 2>&1); rc=$?
if [ $rc -eq 0 ] && names_anchor "$out"; then ok; else bad "журнал не записать — напоминание всё равно есть" "rc=$rc out=${out:0:200}"; fi

rm -rf "$work/.claude" "$work/cfg"
out=$(input "anchor" "$tr" | env HOME="$work" CLAUDE_CONFIG_DIR="$work/cfg" python3 -I "$HOOK" 2>&1); rc=$?
if [ $rc -eq 0 ] && names_anchor "$out"; then ok; else bad "CLAUDE_CONFIG_DIR: напоминание есть" "rc=$rc out=${out:0:200}"; fi
if grep -q $'\ts1\treminded' "$work/cfg/state/anchor-nudge.tsv" 2>/dev/null; then ok
else bad "CLAUDE_CONFIG_DIR: строка журнала в \$CLAUDE_CONFIG_DIR/state" "$(ls -R "$work/cfg" 2>&1 | head -5)"; fi
if [ ! -e "$work/.claude" ]; then ok; else bad "CLAUDE_CONFIG_DIR: в ~/.claude ничего не пишется" "$(ls -R "$work/.claude" | head -5)"; fi
rm -rf "$work/.claude"
input "anchor" "$tr" | env HOME="$work" CLAUDE_CONFIG_DIR= python3 -I "$HOOK" >/dev/null 2>&1
if [ -f "$work/.claude/state/anchor-nudge.tsv" ]; then ok; else bad "пустой CLAUDE_CONFIG_DIR — журнал в ~/.claude/state" "$(ls -R "$work" | head -5)"; fi
rm -rf "$work/cfg"; mkdir -p "$work/cfg"; printf 'x' >"$work/cfg/state"
out=$(input "anchor" "$tr" | env HOME="$work" CLAUDE_CONFIG_DIR="$work/cfg" python3 -I "$HOOK" 2>&1); rc=$?
if [ $rc -eq 0 ] && names_anchor "$out"; then ok; else bad "CLAUDE_CONFIG_DIR: журнал не записать — напоминание всё равно есть" "rc=$rc out=${out:0:200}"; fi

rm -rf "$work/.claude"; mkdir -p "$work/.claude/state"; log="$work/.claude/state/anchor-nudge.tsv"
head -c 256000 /dev/zero | tr '\0' 'a' >"$log"
run "anchor" >/dev/null
if [ ! -e "$log.1" ] && [ "$(wc -c <"$log" | tr -d ' ')" -gt 256000 ]; then ok
else bad "журнал ровно 256 000 байт — не переносится" "$(ls -l "$work/.claude/state")"; fi
size=$(wc -c <"$log" | tr -d ' ')
run "anchor" >/dev/null
if [ "$(wc -c <"$log.1" 2>/dev/null | tr -d ' ')" = "$size" ] && [ "$(wc -l <"$log" | tr -d ' ')" -eq 1 ] && grep -q $'\ts1\treminded' "$log"; then ok
else bad "журнал больше 256 000 байт — переносится в .1, новая строка в чистый файл" "$(ls -l "$work/.claude/state")"; fi

total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "anchor-nudge: $pass/$total прошли"; exit 0; fi
echo "anchor-nudge: $pass/$total прошли, $fail упало$failures"; exit 1
