#!/usr/bin/env bash
# Матрица для anchor-steps.py: свои шаги anchor из общего файла в папке Hats и из файла проекта,
# «до» и «после», общие раньше проектных; файл проекта — только для путей из projects общего.
# Файлы лежат во временной папке, общий находится через HOME; рабочая папка — --cwd или подставной /proc.
#   bash plugin/tests/anchor-steps.test.sh
#   STEPS_UNDER_TEST=/path/to/candidate.py bash plugin/tests/anchor-steps.test.sh   (рядом с ним — handoff.py)
set -uo pipefail
unset CLAUDE_CONFIG_DIR CLAUDE_PID HANDOFF_TEST HANDOFF_PROCESS HANDOFF_TEST_PROC HATS_STATE_HOME
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${STEPS_UNDER_TEST:-$plugin_root/scripts/anchor-steps.py}"
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/anchor-steps-test.XXXXXX"); work=$(cd "$work" && pwd -P)
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT INT TERM

hats="$work/Library/Application Support/Hats"
general="$hats/anchor-steps.json"
proj="$work/proj"
project="$proj/.claude/anchor-steps.json"

reset() {
  chmod -R u+rwx "$work" 2>/dev/null
  rm -rf "$work/Library" "$proj" "$work/link" "$work/fakeproc" "$work/other"
  mkdir -p "$hats" "$proj/.claude"
}
put()   { printf '%s' "$2" >"$1"; }
steps() { env HOME="$work" python3 -I "$SCRIPT" --cwd "${1:-$proj}" 2>&1; }
ok()    { pass=$((pass+1)); }
bad()   { fail=$((fail+1)); failures="$failures
  $1: $2"; }
is()    { if [ "$3" = "$2" ]; then ok; else bad "$1" "ждали:
$2
--- получили:
$3"; fi; }
has()   { case "$3" in *"$2"*) ok ;; *) bad "$1" "ждали «$2», получили: ${3:0:600}" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "не ждали «$2», получили: ${3:0:600}" ;; *) ok ;; esac; }
calm()  {  # calm <имя> — после out=$(…); rc=$?: код 0 и без трассировки
  case "$out" in *Traceback*) bad "$1: без трассировки" "${out:0:600}" ;; *) ok ;; esac
  if [ "$rc" -eq 0 ]; then ok; else bad "$1: код 0" "rc=$rc"; fi
}
marked() { printf '"projects":["%s"]' "$proj"; }

# --- нет файлов
reset; rm -rf "$proj/.claude"
out=$(steps); rc=$?
is "нет файлов — одна строка «no own steps»" "no own steps" "$out"; calm "нет файлов"
reset
is "папка .claude есть, файлов нет — «no own steps»" "no own steps" "$(steps)"
reset; put "$general" '{}'
is "общий файл без списков — «no own steps»" "no own steps" "$(steps)"

# --- общий файл в HATS_STATE_HOME, когда путь абсолютный; иначе в папке Hats
reset; mkdir -p "$work/xs"; put "$work/xs/anchor-steps.json" '{"before":["из временной"]}'; put "$general" '{"before":["из живой"]}'
out=$(env HOME="$work" HATS_STATE_HOME="$work/xs" python3 -I "$SCRIPT" --cwd "$proj" 2>&1)
has "HATS_STATE_HOME: общий файл — из него" "1. [general] из временной" "$out"
lacks "HATS_STATE_HOME: живой общий файл не читается" "из живой" "$out"
out=$(env HOME="$work" HATS_STATE_HOME="relative/xs" python3 -I "$SCRIPT" --cwd "$proj" 2>&1)
has "относительный HATS_STATE_HOME — общий файл папки Hats" "1. [general] из живой" "$out"
rm -rf "$work/xs"

# --- оба файла, проект отмечен: «до» — общие, затем проекта; «после» — так же
reset
put "$general" '{"before":["a"],"after":["c"],'"$(marked)"'}'
put "$project" '{"before":["b"],"after":["d"]}'
out=$(steps); rc=$?
is "оба файла: до — a, b; после — c, d" "before anchor:
1. [general] a
2. [project] b
after anchor:
1. [general] c
2. [project] d" "$out"
calm "оба файла"
reset
put "$general" '{"before":["a1","a2"],"after":["c1","c2"],'"$(marked)"'}'
put "$project" '{"after":["d1","d2"],"before":["b1","b2"]}'
is "оба файла: порядок внутри списка сохранён, ключи в любом порядке" "before anchor:
1. [general] a1
2. [general] a2
3. [project] b1
4. [project] b2
after anchor:
1. [general] c1
2. [general] c2
3. [project] d1
4. [project] d2" "$(steps)"
reset
put "$general" '{"before":["  a  "],'"$(marked)"'}'
put "$project" '{"after":["Commit the vault files you wrote, by explicit path."]}'
is "пробелы по краям обрезаются, текст указания выдаётся как есть" "before anchor:
1. [general] a
after anchor:
1. [project] Commit the vault files you wrote, by explicit path." "$(steps)"

# --- проект не отмечен
reset
put "$general" '{"before":["a"],"projects":["'"$work/other"'"]}'
put "$project" '{"before":["b"]}'
out=$(steps); rc=$?
is "проект не в projects — только общие шаги и строка о пропуске" "before anchor:
1. [general] a
after anchor: none
project steps skipped: $proj is not in projects of $general" "$out"
calm "проект не отмечен"
reset; put "$project" '{"before":["b"]}'
out=$(steps); rc=$?
is "общего файла нет — шаги проекта пропущены, строка называет причину: нет общего файла" "before anchor: none
after anchor: none
project steps skipped: $proj is not marked: there is no $general" "$out"
calm "общего файла нет"
reset; put "$general" '{"before":["a"]}'; put "$project" '{"before":["b"]}'
has "в общем файле нет projects — проект не отмечен" "project steps skipped: $proj is not in projects of $general" "$(steps)"
reset; put "$general" '{"before":["a"],"projects":["'"$work"'"]}'; put "$project" '{"before":["b"]}'
has "в projects папка выше проекта — проект не отмечен" "project steps skipped: $proj" "$(steps)"
reset; mkdir -p "$proj/sub/.claude"; put "$general" '{"before":["a"],'"$(marked)"'}'
put "$proj/sub/.claude/anchor-steps.json" '{"before":["b"]}'
out=$(steps "$proj/sub")
has "рабочая папка внутри отмеченной — сама не отмечена" "project steps skipped: $proj/sub is not in projects" "$out"
lacks "рабочая папка внутри отмеченной — её шаги не выданы" "[project]" "$out"
reset; put "$general" '{"before":["a"],"projects":["'"$work/other"'"]}'
is "файла проекта нет — строки о пропуске нет" "before anchor:
1. [general] a
after anchor: none" "$(steps)"

# --- отметка через ссылку или ~: сравниваются настоящие пути
reset; ln -s "$proj" "$work/link"
put "$general" '{"projects":["'"$work/link"'"]}'; put "$project" '{"before":["b"]}'
has "в projects ссылка на проект — отмечен" "1. [project] b" "$(steps)"
reset; put "$general" '{"projects":["~/proj"]}'; put "$project" '{"before":["b"]}'
has "в projects путь с ~ — отмечен" "1. [project] b" "$(steps)"
reset; put "$general" '{"projects":["~"]}'; mkdir -p "$work/.claude"; put "$work/.claude/anchor-steps.json" '{"before":["h"]}'
has "в projects просто ~ — отмечена домашняя папка" "1. [project] h" "$(steps "$work")"
rm -rf "$work/.claude"
reset; ln -s "$proj" "$work/link"; put "$general" '{'"$(marked)"'}'; put "$project" '{"before":["b"]}'
has "рабочая папка через ссылку, в projects настоящий путь — отмечен" "1. [project] b" "$(steps "$work/link")"
reset; put "$general" '{"projects":["'"$proj"'/","'"$proj"'/../proj"]}'; put "$project" '{"before":["b"]}'
has "в projects путь с / в конце и с .. — отмечен" "1. [project] b" "$(steps)"
reset; put "$general" '{"projects":["  '"$proj"'  "]}'; put "$project" '{"before":["b"]}'
has "в projects путь с пробелами по краям — обрезан, отмечен" "1. [project] b" "$(steps)"
reset; put "$general" '{"projects":["'"$work/PROJ"'"]}'; put "$project" '{"before":["b"]}'
out=$(steps)
if [ -d "$work/PROJ" ]; then
  has "в projects та же папка в другом регистре — отмечена (файловая система без регистра)" "1. [project] b" "$out"
else
  has "в projects другой регистр на файловой системе с регистром — другая папка" "project steps skipped: $proj is not in projects" "$out"
fi

# --- неверный projects: общий файл пропущен целиком, проект не отмечен
bad_projects() {  # bad_projects <имя> <значение projects> <причина>
  reset; put "$general" '{"before":["a"],"projects":'"$2"'}'; put "$project" '{"before":["b"]}'
  out=$(steps); rc=$?
  has "projects $1: общий файл пропущен с причиной" "skipped $general: $3" "$out"
  lacks "projects $1: шаги общего файла не выданы" "[general]" "$out"
  lacks "projects $1: шаги проекта не выданы" "[project]" "$out"
  has "projects $1: проект не отмечен, причина — общий файл пропущен" "project steps skipped: $proj is not marked: $general was skipped" "$out"
  calm "projects $1"
}
bad_projects "строка" '"'"$proj"'"' "projects is a string, not an array"
bad_projects "объект" '{"p":"'"$proj"'"}' "projects is an object, not an array"
bad_projects "null" 'null' "projects is null, not an array"
bad_projects "элемент число" '[1]' "projects, item 1 is a number, not a string"
bad_projects "второй элемент — список" '["'"$proj"'",["x"]]' "projects, item 2 is an array, not a string"
bad_projects "пустой элемент" '[""]' "projects, item 1 is empty"
bad_projects "элемент из пробелов" '["   "]' "projects, item 1 is empty"
bad_projects "знак U+202E в пути" '["'"$proj"'‮"]' "projects, item 1 holds U+202E"
bad_projects "относительный путь" '["proj"]' 'projects, item 1 is not an absolute path: "proj"'
bad_projects "~ неизвестного пользователя" '["~nosuchuser4242/proj"]' 'projects, item 1 is not an absolute path: "~nosuchuser4242/proj"'
bad_projects "перевод строки в пути" '["'"$proj"'\n"]' "projects, item 1 holds U+000A"
bad_projects "нулевой знак в пути" '["'"$proj"'\u0000"]' "projects, item 1 holds U+0000"

# --- только «после»
reset; put "$general" '{"after":["skill:daily-journal"]}'
out=$(steps); rc=$?
is "только «после» — до: ничего, после: daily-journal" "before anchor: none
after anchor:
1. [general] skill:daily-journal" "$out"
calm "только «после»"

# --- петля: прямой самовызов не выдаётся
reset
put "$general" '{"before":["skill:anchor","a"],"after":["skill:hats:anchor"],'"$(marked)"'}'
put "$project" '{"before":["skill:HATS:Anchor"],"after":["d"," skill:anchor "]}'
out=$(steps); rc=$?
is "петля: skill:anchor и skill:hats:anchor в любом списке и регистре не выданы, названы" "before anchor:
1. [general] a
after anchor:
1. [project] d
dropped before, item 1 of $general: skill:anchor calls anchor itself
dropped before, item 1 of $project: skill:HATS:Anchor calls anchor itself
dropped after, item 1 of $general: skill:hats:anchor calls anchor itself
dropped after, item 2 of $project: skill:anchor calls anchor itself" "$out"
calm "петля"
reset; put "$general" '{"before":["skill:anchor"]}'
is "петля: единственный шаг выброшен — списки пусты, строка есть" "before anchor: none
after anchor: none
dropped before, item 1 of $general: skill:anchor calls anchor itself" "$(steps)"
reset; put "$general" '{"before":["Skill:anchor","a"],"after":["SKILL:hats:anchor"]}'
is "петля: приставка skill: в другом регистре — тоже выброшен" "before anchor:
1. [general] a
after anchor: none
dropped before, item 1 of $general: Skill:anchor calls anchor itself
dropped after, item 1 of $general: SKILL:hats:anchor calls anchor itself" "$(steps)"

# --- чужой anchor и похожие имена — обычные шаги
reset; put "$general" '{"before":["skill:other:anchor","skill:anchors","skill:hats:anchor-2","skill:my.skill_1"]}'
is "skill:other:anchor и похожие имена выданы как шаги" "before anchor:
1. [general] skill:other:anchor
2. [general] skill:anchors
3. [general] skill:hats:anchor-2
4. [general] skill:my.skill_1
after anchor: none" "$(steps)"
reset; put "$general" '{"before":["Skill:daily-journal"]}'
has "Skill: в другом регистре с верным именем — выдан как шаг" "1. [general] Skill:daily-journal" "$(steps)"
reset; put "$general" '{"before":["Run /hats:anchor again"]}'
has "текст с anchor — указание, не самовызов" "1. [general] Run /hats:anchor again" "$(steps)"

# --- владелец записки: поле note
writer="Write the resume note and print resume note: <path>."
reset; put "$general" '{"note":"steps","before":["'"$writer"'"],"after":["c"]}'
out=$(steps); rc=$?
is "note steps в общем — первая строка о владельце, списки как прежде" "note: written by own steps
before anchor:
1. [general] $writer
after anchor:
1. [general] c" "$out"
calm "note steps"
reset; put "$general" '{"note":"anchor","before":["a"]}'
is "note anchor — вывод прежний, строки note: нет" "before anchor:
1. [general] a
after anchor: none" "$(steps)"
reset; put "$general" '{"note":"anchor"}'
is "note anchor и шагов нет — «no own steps»" "no own steps" "$(steps)"
reset; put "$general" '{"before":["a"],'"$(marked)"'}'; put "$project" '{"after":["d"]}'
lacks "поля note нет нигде — владелец anchor, строки note: нет" "note:" "$(steps)"
reset; put "$general" '{"note":"anchor","before":["a"],'"$(marked)"'}'; put "$project" '{"note":"steps","before":["b"]}'
is "проект steps при общем anchor — steps" "note: written by own steps
before anchor:
1. [general] a
2. [project] b
after anchor: none" "$(steps)"
reset; put "$general" '{"note":"steps","before":["a"],'"$(marked)"'}'; put "$project" '{"note":"anchor","before":["b"]}'
lacks "проект anchor при общем steps — anchor" "note:" "$(steps)"
reset; put "$general" '{"note":"steps","before":["a"],'"$(marked)"'}'; put "$project" '{"after":["d"]}'
has "в проекте поля нет — действует steps общего" "note: written by own steps" "$(steps)"
reset; put "$general" '{"before":["a"],"projects":["'"$work/other"'"]}'; put "$project" '{"note":"steps","before":["b"]}'
out=$(steps)
lacks "файл проекта не отмечен — его note не действует" "note:" "$out"
has "файл проекта не отмечен — строка о пропуске есть" "project steps skipped: $proj is not in projects" "$out"
reset; put "$general" '{"note":"steps","before":["a"],"projects":["'"$work/other"'"]}'; put "$project" '{"note":"anchor"}'
has "файл проекта не отмечен — действует steps общего" "note: written by own steps" "$(steps)"
reset; put "$general" '{"note":"steps","before":["a"],'"$(marked)"'}'; put "$project" '{"note":"anchor","before": ["b"'
out=$(steps)
has "файл проекта пропущен — действует note общего" "note: written by own steps" "$out"
has "файл проекта пропущен — причина названа" "skipped $project: not JSON:" "$out"
reset; put "$general" '{"note":"steps","before":["a"],"projects":"x"}'
out=$(steps); rc=$?
lacks "общий файл пропущен — его note не действует" "note:" "$out"
calm "общий файл с note пропущен"
reset; put "$general" '{"note":"steps"}'
out=$(steps); rc=$?
is "steps без шагов — две строки о владельце, «no own steps» нет" "note: written by own steps
note: no before step to write it
before anchor: none
after anchor: none" "$out"
calm "steps без шагов"
reset; put "$general" '{"note":"steps","after":["c"]}'
is "steps, только «после» — нет шага «до» для записки" "note: written by own steps
note: no before step to write it
before anchor: none
after anchor:
1. [general] c" "$(steps)"
reset; put "$general" '{"note":"steps","before":["skill:hats:anchor"]}'
is "steps, единственный шаг «до» выброшен как вызов anchor — before пуст" "note: written by own steps
note: no before step to write it
before anchor: none
after anchor: none
dropped before, item 1 of $general: skill:hats:anchor calls anchor itself" "$(steps)"
reset; put "$general" '{"note":"anchor",'"$(marked)"'}'; put "$project" '{"note":"steps","before":["skill:anchor"]}'
is "steps в проекте, его единственный шаг «до» выброшен — before пуст" "note: written by own steps
note: no before step to write it
before anchor: none
after anchor: none
dropped before, item 1 of $project: skill:anchor calls anchor itself" "$(steps)"
reset; put "$general" '{"note":"steps","before":["a"],'"$(marked)"'}'; put "$project" '{"note":"steps"}'
lacks "steps, шаг «до» есть только в общем — строки «no before step» нет" "no before step" "$(steps)"
bad_note() {  # bad_note <имя> <файл> <значение note> <причина>
  reset; put "$general" '{"before":["a"],'"$(marked)"'}'
  if [ "$2" = "$project" ]; then put "$project" '{"before":["b"],"note":'"$3"'}'
  else put "$general" '{"before":["a"],"note":'"$3"','"$(marked)"'}'; put "$project" '{"before":["b"]}'; fi
  out=$(steps); rc=$?
  has "note $1: файл пропущен с причиной" "skipped $2: note is $4, not \"anchor\" or \"steps\"" "$out"
  lacks "note $1: ни одного шага этого файла" "[$( [ "$2" = "$project" ] && echo project || echo general )]" "$out"
  lacks "note $1: владелец не steps" "note: written" "$out"
  calm "note $1"
}
bad_note "STEPS" "$general" '"STEPS"' '"STEPS"'
bad_note "Anchor" "$project" '"Anchor"' '"Anchor"'
bad_note "пробел впереди" "$general" '" steps"' '" steps"'
bad_note "пробел в конце" "$project" '"steps "' '"steps "'
bad_note "пустая строка" "$general" '""' '""'
bad_note "другое слово" "$project" '"own"' '"own"'
bad_note "число" "$general" '1' 'a number'
bad_note "true" "$project" 'true' 'a boolean'
bad_note "null" "$general" 'null' 'null'
bad_note "список" "$project" '["steps"]' 'an array'
bad_note "объект" "$general" '{"steps":1}' 'an object'
reset; put "$general" '{"note":"steps","note":"steps"}'
has "note повторён — файл пропущен" "skipped $general: key note is repeated" "$(steps)"
skill_text=$(cat "$plugin_root/skills/anchor/SKILL.md")
reset; put "$general" '{"note":"steps"}'
seen=0
while IFS= read -r line; do
  case "$line" in note:*) seen=$((seen+1)); has "скилл узнаёт строку «${line}», которую печатает скрипт" "\`$line\`" "$skill_text" ;; esac
done <<<"$(steps)"
is "скрипт печатает две строки note: для сверки со скиллом" "2" "$seen"
has "скилл велит записать id фоновой работы как в списке задач — очистка сравнивает id текстом" "note its id exactly as the task list shows it" "$skill_text"
lacks "скилл не разрешает записать фоновую работу одним именем" "id or name" "$skill_text"

# --- не JSON: файл пропущен, другой действует
reset; put "$general" '{"before":["a"],'"$(marked)"'}'; put "$project" '{"before": ["b"'
out=$(steps); rc=$?
has "файл проекта не JSON — пропущен с причиной" "skipped $project: not JSON:" "$out"
has "файл проекта не JSON — общие шаги действуют" "1. [general] a" "$out"
lacks "файл проекта не JSON — его шагов нет" "[project]" "$out"
calm "файл проекта не JSON"
reset; put "$general" 'not json'
out=$(steps); rc=$?
has "общий файл не JSON — пропущен с причиной" "skipped $general: not JSON: Expecting value" "$out"
lacks "общий файл не JSON — вывод не «no own steps»" "no own steps" "$out"
calm "общий файл не JSON"
reset; put "$general" ''
has "общий файл пуст — не JSON" "skipped $general: not JSON:" "$(steps)"
reset; head -c 16000 /dev/zero | tr '\0' '[' >"$general"
out=$(steps); rc=$?
has "16 000 вложенных скобок — не JSON, без падения" "skipped $general: not JSON:" "$out"
calm "глубокая вложенность"

# --- не та форма: файл пропущен целиком, названы ключ, номер и причина
shape() {  # shape <имя> <файл> <содержимое> <причина>
  reset; put "$general" '{"before":["a"],'"$(marked)"'}'
  [ "$2" = "$project" ] || put "$general" "$3"
  [ "$2" = "$project" ] && put "$project" "$3"
  out=$(steps); rc=$?
  has "$1: пропущен с причиной" "skipped $2: $4" "$out"
  lacks "$1: ни одного шага этого файла" "[$( [ "$2" = "$project" ] && echo project || echo general )]" "$out"
  calm "$1"
}
shape "верх — список" "$general" '["a"]' "the top level is an array, not an object"
shape "верх — строка" "$general" '"a"' "the top level is a string, not an object"
shape "верх — null" "$general" 'null' "the top level is null, not an object"
shape "лишний ключ в общем" "$general" '{"before":["a"],"befor":["b"]}' 'key "befor" is not one of before, after, note, projects'
shape "projects в файле проекта" "$project" '{"before":["b"],"projects":["/x"]}' 'key "projects" is not one of before, after, note'
shape "повтор ключа" "$general" '{"before":["a"],"before":["b"]}' "key before is repeated"
shape "повтор ключа в файле проекта" "$project" '{"after":["b"],"after":["c"]}' "key after is repeated"
shape "значение — строка" "$general" '{"before":"a"}' "before is a string, not an array"
shape "значение — объект" "$project" '{"after":{"a":1}}' "after is an object, not an array"
shape "значение — null" "$general" '{"before":null}' "before is null, not an array"
shape "элемент — число" "$general" '{"before":["a",1]}' "before, item 2 is a number, not a string"
shape "элемент — true" "$project" '{"after":[true]}' "after, item 1 is a boolean, not a string"
shape "элемент — список" "$general" '{"before":["a",["b"]]}' "before, item 2 is an array, not a string"
shape "элемент — объект" "$general" '{"before":[{"a":1}]}' "before, item 1 is an object, not a string"
shape "элемент — null" "$general" '{"after":[null]}' "after, item 1 is null, not a string"
shape "пустой шаг" "$general" '{"before":[""]}' "before, item 1 is empty"
shape "шаг из пробелов" "$project" '{"before":["   "]}' "before, item 1 is empty"
shape "перевод строки в шаге" "$general" '{"before":["a\nb"]}' "before, item 1 holds U+000A"
shape "перевод строки в конце шага" "$general" '{"before":["a\n"]}' "before, item 1 holds U+000A"
shape "возврат каретки" "$project" '{"after":["a\rb"]}' "after, item 1 holds U+000D"
shape "табуляция" "$general" '{"before":["a\tb"]}' "before, item 1 holds U+0009"
shape "знак ESC" "$general" '{"before":["a\u001bb"]}' "before, item 1 holds U+001B"
shape "NEL" "$general" '{"before":["a\u0085b"]}' "before, item 1 holds U+0085"
shape "разделитель строк U+2028" "$general" '{"before":["a b"]}' "before, item 1 holds U+2028"
shape "одинокий суррогат" "$general" '{"before":["\ud800"]}' "before, item 1 holds U+D800"
shape "skill: без имени" "$general" '{"before":["skill:"]}' 'before, item 1 names no skill: "skill:"'
shape "skill: с пробелом в имени" "$general" '{"before":["skill:daily journal"]}' 'before, item 1 names no skill: "skill:daily journal"'
shape "skill: пробел после двоеточия" "$project" '{"after":["skill: daily-journal"]}' 'after, item 1 names no skill'
shape "skill: косая черта" "$general" '{"before":["skill:a/b"]}' 'before, item 1 names no skill'
shape "skill: не латиница" "$general" '{"before":["skill:журнал"]}' 'before, item 1 names no skill'
shape "Skill: с пробелом в имени" "$general" '{"before":["Skill:daily journal"]}' 'before, item 1 names no skill: "Skill:daily journal"'
shape "SKILL: без имени" "$project" '{"after":["SKILL:"]}' 'after, item 1 names no skill: "SKILL:"'
shape "знак U+202E в шаге" "$general" '{"before":["a‮b"]}' "before, item 1 holds U+202E"
shape "знак U+200B в шаге" "$general" '{"before":["a​b"]}' "before, item 1 holds U+200B"
shape "знак U+2066 в шаге" "$project" '{"after":["a⁦b"]}' "after, item 1 holds U+2066"
shape "знак U+FEFF внутри шага" "$general" '{"before":["a﻿b"]}' "before, item 1 holds U+FEFF"

# --- не UTF-8
reset; printf '{"before":["\xff"]}' >"$general"
out=$(steps); rc=$?
has "не UTF-8 — пропущен с причиной" "skipped $general: not UTF-8: byte 0xff at offset 12" "$out"
calm "не UTF-8"
reset; printf '\xef\xbb\xbf{"before":["a"]}' >"$general"
is "метка BOM в начале — читается" "before anchor:
1. [general] a
after anchor: none" "$(steps)"
reset; printf '\xef\xbb\xbf{"before":["\xc3"]}' >"$general"
has "BOM и не UTF-8 — смещение считается от начала файла" "not UTF-8: byte 0xc3 at offset 15" "$(steps)"
reset; put "$general" '{"before":["Закоммить файлы волта, по явному пути."]}'
has "кириллица в шаге — выдаётся как есть" "1. [general] Закоммить файлы волта, по явному пути." "$(steps)"

# --- слишком большой
pad() {  # pad <файл> <json> <размер>: json плюс пробелы до ровно <размер> байт
  { printf '%s' "$2"; head -c $(( $3 - ${#2} )) /dev/zero | tr '\0' ' '; } >"$1"
}
reset; pad "$general" '{"before":["a"]}' 16384
has "ровно 16 384 байта — читается" "1. [general] a" "$(steps)"
reset; pad "$general" '{"before":["a"]}' 16385
out=$(steps); rc=$?
has "16 385 байт — пропущен, превышение названо" "skipped $general: larger than 16384 bytes" "$out"
calm "больше 16 КБ"
reset; head -c 2000000 /dev/zero | tr '\0' ' ' >"$general"
has "файл в 2 МБ — пропущен по размеру" "skipped $general: larger than 16384 bytes" "$(steps)"
list_of() {  # list_of <n>: ["s1",…,"sn"]
  local i items=""; for ((i = 1; i <= $1; i++)); do items="$items${items:+,}\"s$i\""; done; printf '[%s]' "$items"
}
reset; put "$general" '{"before":'"$(list_of 20)"'}'
has "20 шагов — читается" "20. [general] s20" "$(steps)"
reset; put "$project" '{"after":'"$(list_of 21)"'}'; put "$general" '{'"$(marked)"'}'
out=$(steps)
has "21 шаг — пропущен, превышение названо" "skipped $project: after holds 21 steps, over 20" "$out"
lacks "21 шаг — ни одного шага файла" "[project]" "$out"
long=$(head -c 500 /dev/zero | tr '\0' 'x')
reset; put "$general" '{"before":["'"$long"'"]}'
has "шаг в 500 знаков — читается" "1. [general] $long" "$(steps)"
reset; put "$general" '{"before":["  '"$long"'  "]}'
has "500 знаков и пробелы по краям — читается" "1. [general] $long" "$(steps)"
reset; put "$general" '{"before":["'"${long}y"'"]}'
has "шаг в 501 знак — пропущен, превышение названо" "skipped $general: before, item 1 is 501 characters long, over 500" "$(steps)"
cyr=$(printf 'ж%.0s' $(seq 500))
reset; put "$general" '{"before":["'"$cyr"'"]}'
has "500 знаков кириллицы (1000 байт) — считаются знаки, читается" "1. [general] $cyr" "$(steps)"

# --- не читается
reset; mkdir -p "$general"
out=$(steps); rc=$?
has "папка вместо общего файла — пропущена с причиной" "skipped $general: not a regular file" "$out"
calm "папка вместо файла"
reset; put "$general" '{'"$(marked)"'}'; mkdir -p "$project"
has "папка вместо файла проекта — пропущена с причиной" "skipped $project: not a regular file" "$(steps)"
reset; ln -s "$work/nope.json" "$general"
has "ссылка в никуда — пропущена, а не «файла нет»" "skipped $general: cannot be read: No such file or directory" "$(steps)"
reset; put "$work/real.json" '{"before":["a"]}'; ln -s "$work/real.json" "$general"
has "ссылка на файл — читается" "1. [general] a" "$(steps)"
rm -f "$work/real.json"
reset; mkfifo "$general"
out=$(timeout 10 env HOME="$work" python3 -I "$SCRIPT" --cwd "$proj" 2>&1); rc=$?
has "канал вместо файла — не ждёт, пропущен" "skipped $general: not a regular file" "$out"
calm "канал вместо файла"
if [ "$(id -u)" -ne 0 ]; then
  reset; put "$general" '{"before":["a"]}'; chmod 000 "$general"
  out=$(steps); rc=$?
  has "нет прав на общий файл — пропущен с причиной" "skipped $general: cannot be read: Permission denied" "$out"
  calm "нет прав на файл"
  reset; put "$general" '{"before":["a"],'"$(marked)"'}'; put "$project" '{"before":["b"]}'; chmod 000 "$proj/.claude"
  out=$(steps); rc=$?
  has "нет прав на папку .claude — файл проекта пропущен, а не «нет файла»" "skipped $project: cannot be read: Permission denied" "$out"
  has "нет прав на папку .claude — общие шаги действуют" "1. [general] a" "$out"
  chmod 700 "$proj/.claude"
fi

# --- без --cwd: рабочая папка — папка процесса Claude
reset; mkdir -p "$work/fakeproc/4242"; ln -s "$proj" "$work/fakeproc/4242/cwd"
put "$general" '{"before":["a"],'"$(marked)"'}'; put "$project" '{"after":["d"]}'
from_proc() {
  (cd "$work" && env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="4242:Mon Nov  9 10:00:00 2026" \
    HANDOFF_TEST_PROC="$work/fakeproc" python3 -I "$SCRIPT" 2>&1)
}
out=$(from_proc); rc=$?
is "без --cwd: файл проекта берётся из папки процесса Claude" "before anchor:
1. [general] a
after anchor:
1. [project] d" "$out"
calm "без --cwd"
put "$general" '{"before":["a"],"projects":["'"$work"'"]}'
has "без --cwd: отметка сравнивается с папкой процесса, а не своей" "project steps skipped: $proj is not in projects" "$(from_proc)"

# --- вывод: одна строка на запись, что бы ни было в пути
odd="$work/a
b"
reset; mkdir -p "$odd/.claude"; put "$odd/.claude/anchor-steps.json" '{"before":["b"]}'
out=$(steps "$odd"); rc=$?
is "перевод строки в пути папки — экранирован, строк столько же" "before anchor: none
after anchor: none
project steps skipped: $work/a\\u000ab is not marked: there is no $general" "$out"
calm "перевод строки в пути"
rm -rf "$odd"
latin=$(env LC_ALL=en_US.ISO8859-1 python3 -I -c 'import sys; print(sys.stdout.encoding.lower())' 2>/dev/null)
if [ "$(uname)" != Darwin ] || [ "$latin" = utf-8 ] || [ -z "$latin" ]; then
  echo "  пропущено: «кодировка терминала без кириллицы» — при LC_ALL=en_US.ISO8859-1 вывод Python здесь «${latin:-неизвестна}», не латиница"
else
  reset; put "$general" '{"before":["Шаг"]}'
  out=$(env LC_ALL=en_US.ISO8859-1 HOME="$work" python3 -I "$SCRIPT" --cwd "$proj" 2>&1); rc=$?
  has "кодировка терминала без кириллицы — шаг экранирован, не падает" "1. [general] \\u0428\\u0430\\u0433" "$out"
  calm "кодировка без кириллицы"
fi

# --- ошибка аргументов
out=$(env HOME="$work" python3 -I "$SCRIPT" --nope 2>&1); rc=$?
if [ $rc -eq 2 ]; then ok; else bad "неизвестный аргумент — код 2" "rc=$rc ${out:0:300}"; fi

# --- сбой самого скрипта: одна строка с типом и сообщением, код 1
reset; mkdir -p "$work/gone"
out=$( (cd "$work/gone" && rmdir "$work/gone" && env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="99999999:x" \
  HANDOFF_TEST_PROC="$work/fakeproc" python3 -I "$SCRIPT" 2>&1) ); rc=$?
case "$out" in
  "anchor-steps: FileNotFoundError: "*) ok ;;
  *) bad "рабочая папка удалена — строка «anchor-steps: FileNotFoundError: …»" "${out:0:600}" ;;
esac
if [ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ]; then ok
else bad "рабочая папка удалена — код 1 и одна строка" "rc=$rc ${out:0:600}"; fi

total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "anchor-steps: $pass/$total прошли"; exit 0; fi
echo "anchor-steps: $pass/$total прошли, $fail упало$failures"; exit 1
