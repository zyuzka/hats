#!/usr/bin/env bash
# Матрица для handoff.py. Одна строка итога, подробности только по упавшим.
#
#   bash plugin/tests/handoff.test.sh
#   HOOK_UNDER_TEST=/path/to/candidate.py bash plugin/tests/handoff.test.sh
#   0 — все прошли, 1 — есть падения
#
# Хук гоняется из копии вне плагина: на своём месте он видит hooks/hooks.json плагина и
# включён в любой папке. Плагин собирается во временной папке только в случаях подключения.
set -uo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SOURCE="${HOOK_UNDER_TEST:-$plugin_root/scripts/handoff.py}"
export CLAUDE_CODE_SESSION_ATTENDED=1; unset CLAUDE_CODE_ENTRYPOINT CLAUDE_PID CLAUDE_CONFIG_DIR
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/loose"; HOOK="$work/loose/handoff.py"; cp "$HOOK_SOURCE" "$HOOK"

proj="$work/proj"
other="$work/other"
mem="$work/.claude/projects/-proj/memory"
note="$mem/note.md"
markers="$work/.claude/state/handoff"
me_pid=$$
me_started=$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | xargs)
dead_pid=99990
dead_started="Thu Jan  1 00:00:00 2026"
own="4242:Mon Nov  9 10:00:00 2026"
own_started="Mon Nov  9 10:00:00 2026"

reset() {
  sid=s
  rm -rf "$work/.claude" "$proj" "$other" "$work/repo" "$work/bin" "$work/PWNED" "$work/fakepid" "$work/Library"
  mkdir -p "$markers" "$mem" "$proj/.claude" "$other/.claude"
  printf '{"hooks":{"SessionStart":[{"matcher":"startup|clear","hooks":[{"type":"command","command":"python3 handoff.py start"}]}]}}' >"$proj/.claude/settings.local.json"
  printf '# Записка\n\n## СЕЙЧАС\n\nстрока сейчас\n\n## Прошлое\n\nстрока прошлого\n' >"$note"
}
now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
marker() {  # marker <файл> <pid> <started> <cwd> <note> <topic> [saved_at]
  python3 -I -c 'import json,sys; a=sys.argv; json.dump({"pid":int(a[2]),"started":" ".join(a[3].split()),"cwd":a[4],"note":a[5],"topic":a[6],"saved_at":a[7]},open(a[1],"w"),ensure_ascii=False)' \
    "$markers/$1.json" "$2" "$3" "$4" "$5" "$6" "${7:-$(now)}"
}
mine() { marker "${1:-a}" 4242 "$own_started" "${2:-$proj}" "${3:-$note}" "${4:-задача А}"; }
start() {  # start <source> [cwd] [env...]
  local src="$1" cwd="${2:-$proj}"; shift; shift || true
  printf '{"session_id":"%s","cwd":"%s","source":"%s"}' "$sid" "$cwd" "$src" |
    env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" "$@" python3 -I "$HOOK" start 2>&1
}
save() { env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$1" --note "$2" --topic "$3" 2>&1; }
check() { env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$1" 2>&1; }
checkline() { printf '%s\n' "$1" >"$proj/n.md"; check "$proj/n.md"; }
has()   { case "$3" in *"$2"*) ok ;; *) bad "$1" "ждали «$2», получили: ${3:0:300}" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "не ждали «$2», получили: ${3:0:300}" ;; *) ok ;; esac; }
empty() { if [ -z "$2" ]; then ok; else bad "$1" "ждали тишину, получили: ${2:0:300}"; fi; }
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }
count() { printf '%s\n' "$2" | grep -c -- "$1"; }

# --- хук старта: после /clear
reset; mine
out=$(start clear); has "clear: своя отметка подгружает записку" "continues the note \"задача А\"" "$out"
has "clear: печатается «СЕЙЧАС»" "строка сейчас" "$out"
lacks "clear: следующий раздел не печатается" "строка прошлого" "$out"
reset; printf '# T\n\n## Контекст\n\nстрока контекста\n\n## СЕЙЧАС\n\nстрока сейчас\n\n## Старое\n\nстарое\n' >"$note"; mine
out=$(start clear); has "clear: «СЕЙЧАС» ищется по имени" "строка сейчас" "$out"
lacks "clear: «Контекст» не печатается" "строка контекста" "$out"; lacks "clear: раздел после «СЕЙЧАС» не печатается" "старое" "$out"
reset; marker a 4242 "Tue Nov 10 10:00:00 2026" "$proj" "$note" "задача А"
empty "clear: тот же номер, другое время запуска — молчит" "$(start clear)"
reset; marker a "$me_pid" "$me_started" "$proj" "$note" "чужая живая"
empty "clear: отметка другой живой сессии в той же папке — молчит" "$(start clear)"
reset; empty "clear: отметок нет — молчит" "$(start clear)"
reset; mine
has "clear: своя отметка находится и после смены папки сессией" "continues the note" "$(start clear "$other")"
reset; mine; printf '{"pid":1,"started":"x","cwd":null,"note":"%s","topic":"t","saved_at":"%s"}' "$note" "$(now)" >"$markers/bad.json"
has "clear: испорченная отметка рядом не глушит свою" "continues the note" "$(start clear)"

# --- после /clear одно сохранение уходит одной сессии
t1="2026-11-11T10:00:00Z"; t2="2026-11-11T11:00:00Z"
reset; marker a 4242 "$own_started" "$proj" "$note" "задача А" "$t1"; before=$(cat "$markers/a.json")
sid=n1; has "передача: первая сессия после сохранения получает записку" "continues the note" "$(start clear)"
has "передача: повторный хук той же сессии снова получает" "continues the note" "$(start clear)"
if [ "$(cat "$markers/a.json")" = "$before" ]; then ok; else bad "передача: хук не переписывает отметку" "изменилась"; fi
sid=n2; empty "передача: следующая сессия без нового сохранения — молчит" "$(start clear)"
if [ -f "$markers/a.json" ]; then ok; else bad "передача: после молчания отметка цела" "пропала"; fi
marker a 4242 "$own_started" "$proj" "$note" "задача Б" "$t2"
sid=n2; has "передача: новое сохранение снова отдаёт записку" "continues the note \"задача Б\"" "$(start clear)"
sid=n3; empty "передача: и после него следующая сессия молчит" "$(start clear)"
reset; marker a 4242 "$own_started" "$proj" "$note" "задача А" "$t1"
out=$(printf '{"cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1)
has "передача: без номера сессии записка отдаётся" "continues the note" "$out"
if [ ! -e "$markers/a.handed" ]; then ok; else bad "передача: без номера сессии ничего не записано" "a.handed есть"; fi
sid='a/b'; has "передача: негодный номер сессии — записка отдаётся" "continues the note" "$(start clear)"
if [ ! -e "$markers/a.handed" ]; then ok; else bad "передача: негодный номер — ничего не записано" "a.handed есть"; fi
sid=n1; has "передача: после них первая сессия с номером получает" "continues the note" "$(start clear)"
reset; marker a 4242 "$own_started" "$proj" "$note" "задача А" "$t2"
printf '{"key":"%s|%s","session":"old"}' "$t1" "$note" >"$markers/a.handed"
sid=n1; has "передача: отметка о прошлом сохранении не глушит новое" "continues the note" "$(start clear)"
printf 'not json' >"$markers/a.handed"
sid=n2; has "передача: испорченный файл передачи не глушит" "continues the note" "$(start clear)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
printf '{"key":"x","session":"n1"}' >"$markers/a.handed"
has "передача: файл передачи не трогает список новой сессии" "\"закрытая\"" "$(start startup)"
reset; save "$proj" "$note" "задача А" >/dev/null
sid=n1; start clear >/dev/null; sid=n2; empty "передача через save: вторая сессия молчит" "$(start clear)"
sleep 1; save "$proj" "$note" "задача Б" >/dev/null
has "передача через save: новое сохранение отдаёт снова" "continues the note \"задача Б\"" "$(start clear)"

# --- хук старта: новая сессия
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
out=$(start startup); has "startup: закрытая сессия в списке" "\"закрытая\"" "$out"
has "startup: не задерживает просьбу пользователя" "Do not hold up the user's request" "$out"
has "startup: упомянуть записки одной строкой на языке пользователя" "in one short line, in the user's language" "$out"
has "startup: продолжать записку — только по выбору пользователя" "Continue a note only if the user picks it" "$out"
lacks "startup: больше не велит сначала спрашивать" "не начинай работу" "$out"
reset; marker a "$me_pid" "$me_started" "$proj" "$note" "живая"
empty "startup: живая сессия в той же папке не предлагается" "$(start startup)"
reset; marker a "$dead_pid" "$dead_started" "$other" "$note" "закрытая"
empty "startup: закрытая сессия другой папки — молчит" "$(start startup)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$mem/gone.md" "без файла"
empty "startup: записки нет на диске — молчит" "$(start startup)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "старая" "2020-01-01T00:00:00Z"
empty "startup: отметка старше 30 дней — молчит" "$(start startup)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "первая" "2026-11-01T10:00:00Z"
marker b 99989 "$dead_started" "$proj" "$note" "вторая"
out=$(start startup); has "startup: две закрытые — обе в списке (1)" "\"первая\"" "$out"; has "startup: две закрытые — обе в списке (2)" "\"вторая\"" "$out"
reset; for i in 1 2 3 4 5 6 7; do marker "m$i" $((99980 + i)) "$dead_started" "$proj" "$note" "тема $i"; done
out=$(start startup); n=$(count '^[0-9]\. "' "$out")
if [ "$n" -eq 5 ]; then ok; else bad "startup: в списке не больше пяти" "строк $n"; fi
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
start startup >/dev/null
if [ -f "$markers/a.json" ]; then ok; else bad "хук не стирает отметку" "файл пропал"; fi

# --- путь записки
reset; printf 'API_TOKEN=secret\n' >"$proj/.env"; marker a "$dead_pid" "$dead_started" "$proj" "$proj/.env" "секрет"
empty "startup: записка вне памяти Claude не показывается" "$(start startup)"
reset; mine a "$proj" "$proj/.env"; printf 'API_TOKEN=secret\n' >"$proj/.env"
empty "clear: записка вне памяти Claude не печатается" "$(start clear)"
reset; printf 'x\n' >"$proj/note.md"; out=$(save "$proj" "$proj/note.md" "задача А"); rc=$?
has "save: записка вне памяти — отказ" "the note must be a file" "$out"
if [ $rc -ne 0 ] && [ -z "$(ls "$markers")" ]; then ok; else bad "save: вне памяти — код не 0 и без отметки" "rc=$rc $(ls "$markers")"; fi

# --- хук старта: прочие причины и ввод
reset; mine
empty "compact — молчит" "$(start compact)"
empty "resume — молчит" "$(start resume)"
empty "выключатель HANDOFF_OFF=1" "$(start clear "$proj" HANDOFF_OFF=1)"
out=$(printf 'not json' | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1); rc=$?
empty "битый ввод — тишина" "$out"
if [ $rc -eq 0 ]; then ok; else bad "битый ввод — код 0" "код $rc"; fi
empty "подмена процесса без HANDOFF_TEST не действует" "$(printf '{"cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1)"

# --- проверка записки
reset; printf 'строка один\n| 2 слова или решения | 22 | 73%% |\n' >"$proj/src.md"
has "цитата совпала" "all verified" "$(checkline "итог (цит. $proj/src.md:2 «| 22 | 73% |»)")"
has "цитата не совпала" "text not found" "$(checkline "итог (цит. $proj/src.md:2 «| 22 | 74% |»)")"
has "цитата: нет строки" "has no line 9" "$(checkline "итог (цит. $proj/src.md:9 «| 22 |»)")"
has "цитата: нет файла" "no regular file" "$(checkline "итог (цит. $proj/nope.md:1 «x»)")"
printf '| 22 | 173%% |\n' >"$proj/src2.md"
has "цитата: 73%% не совпадает с 173%%" "text not found" "$(checkline "итог (цит. $proj/src2.md:1 «73%»)")"
printf 'было 73.5%%\n' >"$proj/src3.md"
has "цитата: 73 не совпадает с 73.5" "text not found" "$(checkline "итог (цит. $proj/src3.md:1 «было 73»)")"
printf 'x (цит. %s:1 «x»)\n' "$mem/n2.md" >"$mem/n2.md"
has "цитата на саму записку — не источник" "the note itself" "$(env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$mem/n2.md" 2>&1)"
printf 'правила — 73%%\n' >"$note"
has "цитата на память Claude — не источник" "Claude's memory" "$(checkline "итог (цит. $note:1 «правила — 73%»)")"
mkfifo "$proj/pipe"; printf 'итог (цит. %s:1 «x»)\n' "$proj/pipe" >"$proj/n.md"
out=$(timeout 5 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
has "цитата на канал не вешает проверку" "no regular file" "$out"; lacks "цитата на канал — не убита по сроку" "rc=124" "$out"
python3 -I -c 'print("(цит. a:1 «" * 1300)' >"$proj/n.md"
out=$(timeout 2 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
lacks "длинная строка с цитатами разбирается быстро" "rc=124" "$out"
has "случай пробы: процент без источника" "no source" "$(checkline '73% потерь — постоянные правила')"
has "случай пробы в обратных кавычках" "no source" "$(checkline '`73%` — постоянные правила')"
has "своя арифметика сходится" "all verified" "$(checkline 'правила — 13 из 30 (43%)')"
has "своя арифметика не сходится" "arithmetic" "$(checkline 'правила — 22 из 30 (43%)')"
has "число с командой-источником" "all verified" "$(checkline 'неделя 98% (система: cat weekly.json)')"
has "команда-источник освобождает только свою часть" "no source" "$(checkline 'правила 73%; неделя 98% (система: cat x)')"
has "команда-источник не отменяет арифметику" "arithmetic" "$(checkline 'правила — 22 из 30 (43%) (система: wc -l x)')"
has "числа в блоке кода не проверяются" "all verified" "$(printf '```\n41%%\n```\n' >"$proj/n.md"; check "$proj/n.md")"
has "шапка записки не проверяется" "all verified" "$(printf -- '---\nname: x 50%%\n---\nтекст\n' >"$proj/n.md"; check "$proj/n.md")"
out=$(for i in $(seq 1 15); do echo "строка $i: $i%"; done >"$proj/n.md"; check "$proj/n.md")
has "замечаний сверх десяти — счётом" "and 5 more" "$out"
n=$(count '^- line' "$out")
if [ "$n" -eq 10 ]; then ok; else bad "замечаний не больше десяти" "строк $n"; fi

# --- сверка состояния
reset; mkdir -p "$work/repo"
git -C "$work/repo" init -q
git -C "$work/repo" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m one
first=$(git -C "$work/repo" rev-parse --short=7 HEAD)
git -C "$work/repo" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m two
second=$(git -C "$work/repo" rev-parse --short=7 HEAD)
branch=$(git -C "$work/repo" symbolic-ref --short HEAD)
git -C "$work/repo" update-ref refs/remotes/origin/main "$second"
git -C "$work/repo" config remote.origin.url "$work/nowhere"
git -C "$work/repo" config remote.origin.uploadpack "touch $work/PWNED; git-upload-pack"
git -C "$work/repo" config core.fsmonitor "touch $work/PWNED; true"
printf '## СЕЙЧАС\n\n- git %s %s = %s\n' "$work/repo" "$branch" "$second" >"$note"; mine
has "состояние совпало" "= $second: matches" "$(start clear)"
printf '## СЕЙЧАС\n\n- git `%s` `%s` = `%s`\n' "$work/repo" "$branch" "$first" >"$note"
has "состояние сдвинулось" "was $first, now $second" "$(start clear)"
printf '## СЕЙЧАС\n\n- git %s origin/main = %s\n' "$work/repo" "$second" >"$note"
out=$(start clear); has "origin сверяется локально и так и подписано" "no fetch" "$out"
if [ ! -e "$work/PWNED" ]; then ok; else bad "хук не запускает команды из настроек репозитория" "PWNED создан"; fi
printf '## СЕЙЧАС\n\n- git %s -x = %s\n' "$work/repo" "$second" >"$note"
lacks "ссылка с минусом не разбирается как факт" "matches" "$(start clear)"
printf '## СЕЙЧАС\n\n- git %s %s = %s\n' "$work/repo" "$branch" "$second" >"$note"
has "срок вышел — факт состояния «не успел проверить»" "no time to check" "$(start clear "$proj" HANDOFF_TEST_BUDGET=0)"
{ printf '## СЕЙЧАС\n\n'; for i in 1 2 3 4 5 6; do printf -- '- git %s %s = %s\n' "$work/repo" "$branch" "$second"; done; } >"$note"
has "фактов не больше четырёх" "more than four" "$(start clear)"
printf '## СЕЙЧАС\n\nпроцент 50%%\n' >"$note"
has "непроверенная строка приходит с пометкой" "Not verified" "$(start clear)"

# --- пределы вывода
reset; python3 -I -c 'import sys; print("## СЕЙЧАС\n"); print("\n".join("слово " * 20 for _ in range(200)))' >"$note"; mine
has "длинная «СЕЙЧАС» обрезается" "cut, the rest is in the file" "$(start clear)"
python3 -I -c 'import sys; p=sys.argv[1]; print("## СЕЙЧАС\n"); print("\n".join("слово " * 20 for _ in range(200))); print("\n".join("x (цит. /%s/%d.md:1 «%s»)" % ("d" * 250, i, "q" * 80) for i in range(12)))' "$work" >"$note"
out=$(start clear); len=$(printf '%s' "$out" | python3 -I -c 'import sys; print(len(sys.stdin.read()))')
if [ "$len" -le 9501 ]; then ok; else bad "вывод не длиннее 9 500 знаков" "$len"; fi

# --- сохранение
reset; out=$(save "$proj" "$note" "задача А")
has "save: отметка записана" "marker:" "$out"
if [ -f "$markers/4242-Mon-Nov-9-10-00-00-2026.json" ]; then ok; else bad "save: файл отметки по процессу" "$(ls "$markers")"; fi
reset; out=$(save "$other" "$note" "задача А")
has "save: папка без хука — выключено" "handoff is off" "$out"
if [ -z "$(ls "$markers")" ]; then ok; else bad "save: в выключенной папке отметки нет" "$(ls "$markers")"; fi
reset; printf '{"permissions":{"allow":["Bash(python3 ~/.claude/hooks/handoff.py save:*)"]}}' >"$work/.claude/settings.json"
has "save: правило разрешения не включает передачу" "handoff is off" "$(save "$other" "$note" "задача А")"
reset; marker dead "$dead_pid" "$dead_started" "$proj" "$note" "та же"
marker live "$me_pid" "$me_started" "$proj" "$note" "та же, живая"
printf 'x\n' >"$mem/other.md"; marker deadother 99997 "$dead_started" "$proj" "$mem/other.md" "другая"
printf '{"pid":1,"started":"x","cwd":"%s","note":null,"topic":"t","saved_at":"%s"}' "$proj" "$(now)" >"$markers/bad.json"
printf '{}' >"$markers/dead.handed"; printf '{}' >"$markers/live.handed"
out=$(save "$proj" "$note" "задача А"); rc=$?
if [ $rc -eq 0 ]; then ok; else bad "save: испорченная отметка не роняет" "rc=$rc ${out:0:200}"; fi
if [ ! -f "$markers/dead.json" ]; then ok; else bad "save: снимает закрытую с той же запиской" "осталась"; fi
if [ ! -f "$markers/dead.handed" ]; then ok; else bad "save: снимает и файл передачи закрытой" "остался"; fi
if [ -f "$markers/live.json" ]; then ok; else bad "save: живую с той же запиской не трогает" "пропала"; fi
if [ -f "$markers/live.handed" ]; then ok; else bad "save: файл передачи живой не трогает" "пропал"; fi
if [ -f "$markers/deadother.json" ]; then ok; else bad "save: закрытую с другой запиской не трогает" "пропала"; fi
reset; printf '73%% без источника\n' >"$note"
has "save: сообщает непроверенное" "not verified in the note" "$(save "$proj" "$note" "задача А")"
reset; out=$(save "$proj" "$mem/none.md" "задача А"); rc=$?
has "save: нет файла записки" "the note must be a file" "$out"
if [ $rc -ne 0 ]; then ok; else bad "save: нет файла записки — код не 0" "код 0"; fi

# --- правила пути записки, регистрация, испорченные отметки
reset; printf 'x\n' >"$mem/note.txt"
has "записка не .md — отказ" "the note must be a file" "$(save "$proj" "$mem/note.txt" t)"
mkdir -p "$work/.claude/projects/-proj/notes"; printf 'x\n' >"$work/.claude/projects/-proj/notes/x.md"
has "записка не в memory — отказ" "the note must be a file" "$(save "$proj" "$work/.claude/projects/-proj/notes/x.md" t)"
mkdir -p "$mem/sub"; printf 'x\n' >"$mem/sub/x.md"
has "записка во вложенной папке memory — отказ" "the note must be a file" "$(save "$proj" "$mem/sub/x.md" t)"
reset; printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"python3 handoff.py start"}]}]}}' >"$work/.claude/settings.json"
has "регистрация в общих настройках включает передачу" "marker:" "$(save "$other" "$note" t)"
reset; mine
python3 -I -c 'import json,sys; json.dump({"pid":1,"started":"x","cwd":"/a\u0000b","note":sys.argv[2],"topic":"t","saved_at":sys.argv[3]},open(sys.argv[1],"w"))' "$markers/nul.json" "$note" "$(now)"
has "отметка с нулевым байтом не глушит свою" "continues the note" "$(start clear)"
has "save не падает на отметке с нулевым байтом" "marker:" "$(save "$proj" "$note" t)"
printf 'итог (цит. /a\0b:1 «x»)\n' >"$proj/n.md"
has "нулевой байт в пути цитаты" "bad path" "$(check "$proj/n.md")"
printf '## СЕЙЧАС\n\n- git /a\0b main = abcdef1\n' >"$note"
has "нулевой байт в пути репозитория" "bad path" "$(start clear)"

# --- новые случаи проверки чисел
reset
has "запятая — граница фразы" "no source" "$(checkline 'правила 73%, неделя 98% (система: cat x)')"
has "«и» — граница фразы" "no source" "$(checkline 'правила 73% и неделя 98% (система: cat x)')"
printf 'было 0.73%%\nбыло 1,73%%\nбыло -73%%\n' >"$proj/src4.md"
has "цитата: 73%% не совпадает с 0.73%%" "text not found" "$(checkline "x (цит. $proj/src4.md:1 «73%»)")"
has "цитата: 73%% не совпадает с 1,73%%" "text not found" "$(checkline "x (цит. $proj/src4.md:2 «73%»)")"
has "цитата: 73%% не совпадает с -73%%" "text not found" "$(checkline "x (цит. $proj/src4.md:3 «73%»)")"
has "«73 процента» ловится" "no source" "$(checkline 'правила — 73 процента')"
has "«13/30» ловится" "no source" "$(checkline 'правила — 13/30')"
lacks "путь с цифрами — не дробь" "no source" "$(checkline 'файл `v2/src/a.md` открыт')"
has "строка «\`\`\`73%%\`\`\`» не открывает ограду" "line 2" "$(printf '```73%%```\nправила 73%%\n' >"$proj/n.md"; check "$proj/n.md")"
python3 -I -c 'print("\n".join("1" * 4999 for _ in range(30)))' >"$proj/n.md"
out=$(timeout 3 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
lacks "длинные строки цифр разбираются быстро" "rc=124" "$out"
python3 -I -c 'print("1" * 1500000)' >"$proj/big.txt"
python3 -I -c 'import sys; print(" ".join("(цит. %s:1 «1»)" % sys.argv[1] for _ in range(30)))' "$proj/big.txt" >"$proj/n.md"
out=$(timeout 3 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
lacks "тридцать цитат в большой файл — быстро" "rc=124" "$out"

# --- медленные ps и git, уборка процессов
reset; mkdir -p "$work/fakebin" "$work/repo"
printf '#!/bin/bash\nsleep 10\n' >"$work/fakebin/ps"; chmod +x "$work/fakebin/ps"
marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"; marker b 99989 "$dead_started" "$proj" "$note" "вторая"; marker c 99988 "$dead_started" "$proj" "$note" "третья"
s=$(date +%s); out=$(start startup "$proj" PATH="$work/fakebin:$PATH"); e=$(date +%s)
empty "ps молчит — закрытые не показываются" "$out"
if [ $((e - s)) -le 5 ]; then ok; else bad "ps молчит — хук укладывается в 5 с" "$((e - s)) с"; fi
env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" PATH="$work/fakebin:$PATH" python3 -I "$HOOK" save --cwd "$proj" --note "$note" --topic t >/dev/null 2>&1
if [ -f "$markers/a.json" ]; then ok; else bad "ps молчит — save не снимает отметку" "снята"; fi
ms=$(IN="{\"cwd\":\"$proj\",\"source\":\"startup\"}" python3 -I -c 'import subprocess,sys,time,os; t=time.monotonic(); subprocess.run(sys.argv[1:], input=os.environ["IN"].encode(), capture_output=True); print(int((time.monotonic()-t)*1000))' \
  env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_BUDGET=1 PATH="$work/fakebin:$PATH" python3 -I "$HOOK" start)
if [ "$ms" -le 1700 ]; then ok; else bad "ps молчит — общий срок на все вызовы ps" "${ms} мс при сроке 1000"; fi
reset; marker good "$dead_pid" "$dead_started" "$proj" "$note" "живая записка"
python3 -I -c 'import json,sys; json.dump({"pid":99987,"started":"x","cwd":"/a\u0000b","note":sys.argv[2],"topic":"t","saved_at":sys.argv[3]},open(sys.argv[1],"w"))' "$markers/nul.json" "$note" "$(now)"
has "отметка с нулевым байтом в папке не глушит список" "\"живая записка\"" "$(start startup)"
reset; mkdir -p "$work/fakebin" "$work/repo"
printf '#!/bin/bash\nsh -c '"'"'echo $$ >"%s/childpid"; exec sleep 30'"'"' &\nsleep 30\n' "$work" >"$work/fakebin/git"; chmod +x "$work/fakebin/git"
printf '## СЕЙЧАС\n\n- git %s main = abcdef1\n' "$work/repo" >"$note"; mine
out=$(start clear "$proj" PATH="$work/fakebin:$PATH" HANDOFF_TEST_BUDGET=2)
has "медленный git — «не успел проверить»" "no time to check" "$out"
sleep 0.5; child=$(cat "$work/childpid" 2>/dev/null)
if [ -n "$child" ] && ! kill -0 "$child" 2>/dev/null; then ok; else bad "после срока дочерних процессов git не остаётся" "pid ${child:-нет} жив"; kill "$child" 2>/dev/null; fi

# --- предел вывода в единицах UTF-16
reset; python3 -I -c 'print("## СЕЙЧАС\n"); print("\n".join("😀" * 60 for _ in range(110)))' >"$note"; mine
units=$(start clear | python3 -I -c 'import sys; print(len(sys.stdin.read().encode("utf-16-le")) // 2)')
if [ "$units" -le 9501 ]; then ok; else bad "вывод не длиннее 9 500 единиц UTF-16" "$units"; fi

# --- настоящий поиск процесса claude по предкам (без подмены), глубина 2 и папка из lsof
reset; mkdir -p "$work/bin"; ln -s /bin/bash "$work/bin/claude"
printf '{"session_id":"s","cwd":"%s","source":"clear"}' "$other" >"$work/in.json"
out=$( (cd "$proj" && env HOME="$work" "$work/bin/claude" -c 'echo $$ >"$1/fakepid"; bash -c "python3 -I \"\$0\" save --note \"\$1\" --topic реальный >/dev/null; true" "$2" "$3"; python3 -I "$2" start <"$1/in.json"; true' _ "$work" "$HOOK" "$note") 2>&1)
has "настоящий поиск: после /clear своя записка" "continues the note \"реальный\"" "$out"
fake=$(cat "$work/fakepid" 2>/dev/null)
fields=$(python3 -I -c 'import json,glob,sys; m=json.load(open(glob.glob(sys.argv[1]+"/*.json")[0])); print(m["pid"], m["cwd"], "|", m["started"])' "$markers" 2>/dev/null)
real_proj=$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$proj")
case "$fields" in "$fake $real_proj | "*" 20"[0-9][0-9]) ok ;; *) bad "настоящий поиск: отметка на процесс claude через два уровня, папка из lsof" "ждали «${fake} ${real_proj} | …», получили «${fields}»" ;; esac

# --- журнал запусков: каждый выход хука старта оставляет строку с решением
trace="$markers/runs.log"
tl() { python3 -I -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); print(" ".join(f"{k}={d.get(k)}" for k in sys.argv[2:]))' "$trace" "$@" 2>&1; }
tlines() { if [ -f "$trace" ]; then grep -c . "$trace"; else echo 0; fi; }
reset; mine; sid=n1; start clear >/dev/null
has "журнал: отдал записку новой сессии" "outcome=gave-note receiver=new session=n1 source=clear pid=4242" "$(tl outcome receiver session source pid)"
start clear >/dev/null
has "журнал: та же сессия получила снова" "outcome=gave-note receiver=same" "$(tl outcome receiver)"
sid=n2; empty "журнал: случай «отдано другой» молчит в выводе" "$(start clear)"
has "журнал: отдано другой сессии" "outcome=handed-elsewhere handed_to=n1 session=n2" "$(tl outcome handed_to session)"
if [ "$(tlines)" -eq 3 ]; then ok; else bad "журнал: одна строка на запуск" "строк $(tlines)"; fi
reset; mine
printf '{"cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start >/dev/null 2>&1
has "журнал: без номера сессии" "outcome=gave-note receiver=none session=None" "$(tl outcome receiver session)"
reset; start clear >/dev/null
has "журнал: своей отметки нет" "outcome=no-own-marker pid=4242" "$(tl outcome pid)"
reset; mkdir -p "$work/fakebin"; printf '#!/bin/bash\nexit 1\n' >"$work/fakebin/ps"; chmod +x "$work/fakebin/ps"; mine
start clear "$proj" HANDOFF_TEST=0 PATH="$work/fakebin:$PATH" >/dev/null
has "журнал: процесс claude не найден" "outcome=no-process" "$(tl outcome)"
reset; mine; start clear "$proj" HANDOFF_PROCESS="x:y" >/dev/null; rc=$?
has "журнал: падение записано с типом" "outcome=error error=ValueError" "$(tl outcome error)"
if [ $rc -eq 0 ]; then ok; else bad "журнал: падение — код 0" "код $rc"; fi
reset; mine; start clear "$proj" HANDOFF_OFF=1 >/dev/null
has "журнал: выключатель" "outcome=off" "$(tl outcome)"
reset; printf 'not json' | env HOME="$work" python3 -I "$HOOK" start >/dev/null 2>&1
has "журнал: битый ввод" "outcome=bad-input" "$(tl outcome)"
reset; printf '[]' | env HOME="$work" python3 -I "$HOOK" start >/dev/null 2>&1
has "журнал: ввод не словарь" "outcome=bad-input" "$(tl outcome)"
reset; mine; start compact >/dev/null
has "журнал: не тот повод запуска" "outcome=skipped source=compact" "$(tl outcome source)"
reset; start startup >/dev/null
has "журнал: новая сессия, закрытых нет" "outcome=no-closed source=startup" "$(tl outcome source)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"; start startup >/dev/null
has "журнал: новая сессия, список" "outcome=listed listed=1" "$(tl outcome listed)"
has "журнал: папка сессии записана" "cwd=$proj" "$(tl cwd)"
case "$(tl at)" in "at=20"[0-9][0-9]-[01][0-9]-[0-3][0-9]T*Z) ok ;; *) bad "журнал: время в UTC" "$(tl at)" ;; esac
reset; mine; python3 -I -c 'import sys; open(sys.argv[1],"w").write("x" * 300000 + "\n")' "$trace"
sid=n1; start clear >/dev/null
if [ -f "$trace.1" ] && [ "$(tlines)" -eq 1 ]; then ok; else bad "журнал: больше 256 КБ — уходит в runs.log.1" "$(ls "$markers") строк $(tlines)"; fi
reset; mine; mkdir -p "$trace"; sid=n1; out=$(start clear); rc=$?
has "журнал не пишется — записка всё равно отдаётся" "continues the note" "$out"
if [ $rc -eq 0 ]; then ok; else bad "журнал не пишется — код 0" "код $rc"; fi
reset; mine; sid=n1; start clear >/dev/null
has "журнал не считается отметкой" "continues the note" "$(start clear)"

# --- одновременные запуски
sessions_in() { python3 -I -c 'import json,sys
seen=[]; bad=0; old=0
for p in sys.argv[1:]:
    try: lines=open(p,encoding="utf-8",errors="replace").read().splitlines()
    except OSError: continue
    for l in lines:
        if l.startswith("OLDTAG"): old+=1; continue
        try: seen.append(json.loads(l)["session"])
        except Exception: bad+=1
print(f"distinct={len(set(seen))} total={len(seen)} bad={bad} old={old}")' "$trace" "$trace.1"; }
reset; for i in $(seq 1 30); do (sid=p$i; start startup >/dev/null) & done; wait
has "одновременно: 30 запусков — 30 целых строк" "distinct=30 total=30 bad=0" "$(sessions_in)"
reset; python3 -I -c 'import sys; open(sys.argv[1],"w").write("OLDTAG " + "x" * 300000 + "\n")' "$trace"
for i in 1 2; do (sid=r$i; start startup "$proj" HANDOFF_TEST_PAUSE=0.2 >/dev/null) & done; wait
has "одновременно: двойная перекладка не стирает историю и строки" "distinct=2 total=2 bad=0 old=1" "$(sessions_in)"
reset; python3 -I -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(4)' "$markers/runs.lock" "$work/locked" &
holder=$!; for _ in $(seq 1 100); do [ -f "$work/locked" ] && break; sleep 0.05; done
s=$(date +%s); sid=w1; start startup >/dev/null; e=$(date +%s); kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
has "занятая блокировка: строка всё равно записана" "distinct=1 total=1" "$(sessions_in)"
if [ $((e - s)) -le 2 ]; then ok; else bad "занятая блокировка: хук не ждёт дольше срока" "$((e - s)) с"; fi
reset; python3 -I -c 'import sys; open(sys.argv[1],"w").write("OLDTAG " + "x" * 300000 + "\n")' "$trace"
python3 -I -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(4)' "$markers/runs.lock" "$work/locked" &
holder=$!; for _ in $(seq 1 100); do [ -f "$work/locked" ] && break; sleep 0.05; done
sid=w3; start startup >/dev/null; kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
if [ ! -e "$trace.1" ]; then ok; else bad "занятая блокировка: без неё журнал не перекладывается" "runs.log.1 есть"; fi
has "занятая блокировка: строка дописана к большому журналу" "distinct=1 total=1 bad=0 old=1" "$(sessions_in)"
reset; mkdir -p "$markers/4242-Mon-Nov-9-10-00-00-2026.json/x"; out=$(save "$proj" "$note" "задача А"); rc=$?
has "save: отметку не записать — так и сказано" "marker not written" "$out"
lacks "save: отметку не записать — без трассировки" "Traceback" "$out"
if [ $rc -ne 0 ]; then ok; else bad "save: отметку не записать — код не 0" "код 0"; fi
left=$(ls "$markers" | grep -c '\.tmp$'); if [ "$left" -eq 0 ]; then ok; else bad "save: отметку не записать — временный файл убран" "$left"; fi
reset; printf '{"session_id":"u1","cwd":"/a\\udc80b","source":"startup"}' | env HOME="$work" python3 -I "$HOOK" start >/dev/null 2>&1
has "журнал: путь с непарным суррогатом — строка всё равно записана" "distinct=1 total=1 bad=0" "$(sessions_in)"
reset; mkdir -p "$markers/runs.lock"; sid=w2; start startup >/dev/null
has "блокировку не открыть: строка всё равно записана" "distinct=1 total=1" "$(sessions_in)"
reset; for i in $(seq 1 20); do HANDOFF_TEST_PAUSE=0.2 save "$proj" "$note" "задача $i" >"$work/save$i.out" & done; wait
failed=$(grep -L "marker:" "$work"/save*.out | wc -l | tr -d ' ')
if [ "$failed" -eq 0 ]; then ok; else bad "одновременно: 20 сохранений — все записали отметку" "не записали $failed: $(cat $(grep -L "marker:" "$work"/save*.out | head -1) | head -c 300)"; fi
if python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$markers/4242-Mon-Nov-9-10-00-00-2026.json" 2>/dev/null; then ok; else bad "одновременно: отметка целая" "битая"; fi
left=$(ls "$markers" | grep -c '\.tmp$'); if [ "$left" -eq 0 ]; then ok; else bad "одновременно: временных файлов не осталось" "$left"; fi

# --- плохая записка не роняет хук и не прячет соседние
empty_cite() { printf '## СЕЙЧАС\n\nитог (цит. %s:1 «%s»)\n' "$proj/src.md" "$1" >"$2"; }
big=$(python3 -I -c 'print("9" * 400)')
reset; printf 'исходная строка\n' >"$proj/src.md"; empty_cite ' ' "$proj/n.md"
out=$(check "$proj/n.md"); rc=$?
has "пустая цитата: check называет её" "quote is empty" "$out"; lacks "пустая цитата: check без трассировки" "Traceback" "$out"
if [ $rc -eq 1 ]; then ok; else bad "пустая цитата: check — код 1" "rc=$rc"; fi
empty_cite $' ' "$proj/n.md"; has "цитата из неразрывного пробела: check называет её" "quote is empty" "$(check "$proj/n.md")"
reset; printf 'исходная строка\n' >"$proj/src.md"; empty_cite ' ' "$note"
out=$(save "$proj" "$note" "задача А"); rc=$?
has "пустая цитата: save пишет отметку" "marker:" "$out"; has "пустая цитата: save называет её" "quote is empty" "$out"
lacks "пустая цитата: save без трассировки" "Traceback" "$out"
if [ $rc -eq 0 ]; then ok; else bad "пустая цитата: save — код 0" "rc=$rc"; fi
reset; printf 'исходная строка\n' >"$proj/src.md"; empty_cite ' ' "$note"; mine
out=$(start clear); has "пустая цитата: после /clear записка отдаётся" "continues the note" "$out"; has "пустая цитата: после /clear помечена" "quote is empty" "$out"
reset; printf 'исходная строка\n' >"$proj/src.md"; empty_cite ' ' "$mem/bad.md"
marker a "$dead_pid" "$dead_started" "$proj" "$note" "хорошая" "2026-11-01T10:00:00Z"
marker b 99989 "$dead_started" "$proj" "$mem/bad.md" "с пустой цитатой"
out=$(start startup); has "пустая цитата: хорошая записка остаётся в списке" "\"хорошая\"" "$out"
has "пустая цитата: плохая записка тоже в списке" "\"с пустой цитатой\"" "$out"
reset; printf '## СЕЙЧАС\n\nправила — %s из 3 (5%%)\n' "$big" >"$mem/crash.md"
marker a "$dead_pid" "$dead_started" "$proj" "$note" "хорошая" "2026-11-01T10:00:00Z"
marker b 99989 "$dead_started" "$proj" "$mem/crash.md" "проверка падает"
out=$(start startup); has "проверка упала: хорошая записка остаётся в списке" "\"хорошая\"" "$out"
has "проверка упала: упавшая записка в списке" "\"проверка падает\"" "$out"; has "проверка упала: это сказано" "note check failed" "$out"
has "проверка упала: журнал запусков называет ошибку (список)" "outcome=listed check_error=OverflowError" "$(tl outcome check_error)"
reset; printf '## СЕЙЧАС\n\nправила — %s из 3 (5%%)\n' "$big" >"$note"; mine
out=$(start clear); has "проверка упала: после /clear записка всё равно отдаётся" "continues the note" "$out"
has "проверка упала: после /clear это сказано" "note check failed" "$out"
has "проверка упала: журнал запусков называет ошибку (/clear)" "outcome=gave-note check_error=OverflowError" "$(tl outcome check_error)"
reset; mine; start clear >/dev/null
has "проверка не падала: в журнале нет ошибки проверки" "outcome=gave-note check_error=None" "$(tl outcome check_error)"
reset; rm -rf "$work/.claude/state"; printf 'x' >"$work/.claude/state"
out=$(save "$proj" "$note" "задача А"); rc=$?
has "каталог состояния не создать: save говорит словами" "marker not written" "$out"; lacks "каталог состояния не создать: без трассировки" "Traceback" "$out"
if [ $rc -eq 1 ]; then ok; else bad "каталог состояния не создать: код 1" "rc=$rc"; fi
reset; out=$(save "$proj" "$note" $'тема \xff'); rc=$?
lacks "тема с байтом не из UTF-8: без трассировки" "Traceback" "$out"
left=$(ls "$markers" | grep -c '\.tmp$'); if [ "$left" -eq 0 ]; then ok; else bad "тема с байтом не из UTF-8: временный файл убран" "$left"; fi
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "хорошая"
python3 -I -c 'import sys; open(sys.argv[1], "w").write("[" * 200000 + "]" * 200000)' "$markers/deep.json"
has "отметка с глубокой вложенностью не прячет список" "\"хорошая\"" "$(start startup)"
out=$(save "$proj" "$note" "задача А"); lacks "отметка с глубокой вложенностью: save без трассировки" "Traceback" "$out"
reset; rm -rf "$work/.claude/state"
out=$(save "$proj" "$note" "задача А"); rc=$?
if [ $rc -eq 0 ] && [ -f "$markers/4242-Mon-Nov-9-10-00-00-2026.json" ]; then ok; else bad "первое сохранение: каталога состояния нет — создаётся, отметка записана" "rc=$rc ${out:0:200}"; fi

# --- запуск без человека (claude -p): списка нет, своя записка после /clear — как раньше
nobody() {  # nobody <source> <ATTENDED или -> <ENTRYPOINT или ->
  local a=() ; [ "$2" = "-" ] && a+=(-u CLAUDE_CODE_SESSION_ATTENDED) || a+=(CLAUDE_CODE_SESSION_ATTENDED="$2")
  [ "$3" = "-" ] || a+=(CLAUDE_CODE_ENTRYPOINT="$3")
  printf '{"session_id":"%s","cwd":"%s","source":"%s"}' "$sid" "$proj" "$1" |
    env "${a[@]}" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1
}
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
empty "без человека: ATTENDED=0 — списка нет" "$(nobody startup 0 sdk-cli)"
has "без человека: в журнале unattended" "outcome=unattended source=startup" "$(tl outcome source)"
empty "без человека: ATTENDED=0 при entrypoint cli — списка нет" "$(nobody startup 0 cli)"
empty "без человека: ATTENDED нет, entrypoint sdk-cli — списка нет" "$(nobody startup - sdk-cli)"
empty "без человека: ATTENDED нет, entrypoint sdk-py — списка нет" "$(nobody startup - sdk-py)"
has "с человеком: ATTENDED нет, entrypoint cli — список есть" "\"закрытая\"" "$(nobody startup - cli)"
has "с человеком: ATTENDED и entrypoint нет — список есть" "\"закрытая\"" "$(nobody startup - -)"
has "с человеком: ATTENDED=1 при entrypoint sdk-ts — список есть" "\"закрытая\"" "$(nobody startup 1 sdk-ts)"
has "незнакомое значение ATTENDED — список показывается" "\"закрытая\"" "$(nobody startup true sdk-cli)"
reset; mine
has "без человека: своя записка после /clear по-прежнему отдаётся" "continues the note" "$(nobody clear 0 sdk-cli)"
reset; printf '## СЕЙЧАС\n\nправила — %s из 3 (5%%)\n' "$big" >"$note"
out=$(save "$proj" "$note" "задача А"); rc=$?
has "проверка упала: save пишет отметку" "marker:" "$out"; lacks "проверка упала: save без трассировки" "Traceback" "$out"
if [ $rc -eq 0 ]; then ok; else bad "проверка упала: save — код 0" "rc=$rc"; fi


# --- метки на английском (основные) и русские (прежние, по-прежнему принимаются)
reset; printf 'first\n| 22 | 73%% |\nhe said "hi" 5 times\n' >"$proj/src.md"
has "cite: прямые кавычки" "all verified" "$(checkline "x (cite: $proj/src.md:2 \"| 22 | 73% |\")")"
has "cite: ёлочки" "all verified" "$(checkline "x (cite: $proj/src.md:2 «| 22 | 73% |»)")"
has "cite: лапки" "all verified" "$(checkline "x (cite: $proj/src.md:2 “| 22 | 73% |”)")"
has "cite: прямые кавычки внутри цитаты" "all verified" "$(checkline "x (cite: $proj/src.md:3 \"he said \"hi\" 5 times\")")"
has "cite: текст не совпал" "text not found" "$(checkline "x (cite: $proj/src.md:2 \"| 22 | 74% |\")")"
has "cite: непарные кавычки — цитата не разобрана" "not parsed" "$(checkline "x (cite: $proj/src.md:2 «| 22 | 73% |\")")"
has "цит.: без номера строки — цитата не разобрана" "not parsed" "$(checkline "x (цит. $proj/src.md «73%»)")"
lacks "метка в обратных кавычках — это не цитата" "not parsed" "$(checkline 'метки: `(cite: …)` и `(цит. …)`')"
has "cmd: число с командой-источником" "all verified" "$(checkline 'week 98% (cmd: cat weekly.json)')"
has "cmd: освобождает только свою часть" "no source" "$(checkline 'rules 73%; week 98% (cmd: cat x)')"
has "and — граница фразы" "no source" "$(checkline 'rules 73% and week 98% (cmd: cat x)')"
has "N of M (P%) сходится" "all verified" "$(checkline 'rules — 13 of 30 (43%)')"
has "N of M (P%) не сходится" "arithmetic" "$(checkline 'rules — 22 of 30 (43%)')"
has "голое N of M — без источника" "no source" "$(checkline 'step 2 of 3 done')"
has "percent — без источника" "no source" "$(checkline 'rules — 73 percent')"
heading() { printf '# T\n\n## Intro\n\nintro line\n\n%s\n\nnow line\n\n## Old\n\nold line\n' "$1" >"$note"; mine; start clear; }
reset; out=$(heading '## NOW'); has "NOW: раздел печатается" "now line" "$out"; lacks "NOW: вступление не печатается" "intro line" "$out"; lacks "NOW: следующий раздел не печатается" "old line" "$out"
reset; has "now — со строчными и уточнением через тире" "now line" "$(heading '## now — 2026-11-11')"
reset; has "NOW: с уточнением в скобках" "now line" "$(heading '## NOW (session abc123)')"
reset; has "СЕЙЧАС с уточнением — прежние записки" "now line" "$(heading '## СЕЙЧАС — 2026-11-09, сессия x')"
reset; out=$(heading '## NOW later'); has "«NOW later» — не заголовок NOW: печатается начало" "intro line" "$out"; lacks "«NOW later» — не заголовок NOW" "now line" "$out"
reset; has "«СЕЙЧАС-2» — прежние записки: раздел печатается, как в HEAD" "now line" "$(heading '## СЕЙЧАС-2 — 2026-11-11')"
reset; has "«СЕЙЧАС 2026-…» — прежние записки" "now line" "$(heading '## СЕЙЧАС 2026-11-09')"
reset; has "NOW: с двоеточием" "now line" "$(heading '## NOW: after the release')"
reset; has "NOW: с дефисом и пробелом" "now line" "$(heading '## NOW - after the release')"
reset; has "NOW: с датой" "now line" "$(heading '## NOW 2026-11-11')"
reset; has "Cite: с заглавной" "all verified" "$(printf 'a 73%%\n' >"$proj/src.md"; checkline "x (Cite: $proj/src.md:1 \"a 73%\")")"
has "Percent с заглавной — без источника" "no source" "$(checkline 'rules — 73 Percent')"
has "and внутри (cmd: …) не режет фразу" "all verified" "$(checkline 'share 73% (cmd: grep a and b x)')"
has "и внутри (система: …) не режет фразу" "all verified" "$(checkline 'доля 73% (система: grep a и b x)')"


# --- другая обстановка: CLAUDE_PID, CLAUDE_CONFIG_DIR, memory-ссылка, /proc вместо lsof, нет fcntl
markerfield() { python3 -I -c 'import json,glob,sys; fs=glob.glob(sys.argv[1]+"/*.json"); m=json.load(open(fs[0])) if fs else {}; print(m.get(sys.argv[2]))' "$1" "$2" 2>&1; }
reset; mkdir -p "$work/bin"; ln -s /bin/bash "$work/bin/claude-work"
( cd "$proj" && env HOME="$work" "$work/bin/claude-work" -c 'echo $$ >"$1/fakepid"; CLAUDE_PID=$$ bash -c "python3 -I \"\$0\" save --note \"\$1\" --topic поимени >/dev/null 2>&1; true" "$2" "$3"; true' _ "$work" "$HOOK" "$note" ) >/dev/null 2>&1
fake=$(cat "$work/fakepid" 2>/dev/null)
if [ -n "$fake" ] && [ "$(markerfield "$markers" pid)" = "$fake" ]; then ok; else bad "CLAUDE_PID: процесс найден, хотя называется не claude" "ждали $fake, получили $(markerfield "$markers" pid)"; fi
reset; mkdir -p "$work/bin"; ln -s /bin/bash "$work/bin/claude"
( cd "$proj" && env HOME="$work" CLAUDE_PID=1 "$work/bin/claude" -c 'echo $$ >"$1/fakepid"; bash -c "python3 -I \"\$0\" save --note \"\$1\" --topic имя >/dev/null 2>&1; true" "$2" "$3"; true' _ "$work" "$HOOK" "$note" ) >/dev/null 2>&1
fake=$(cat "$work/fakepid" 2>/dev/null)
if [ -n "$fake" ] && [ "$(markerfield "$markers" pid)" = "$fake" ]; then ok; else bad "CLAUDE_PID не предок — поиск по имени claude как раньше" "ждали $fake, получили $(markerfield "$markers" pid)"; fi

reset; cfg="$work/cfg"; mkdir -p "$cfg/projects/-proj/memory"; printf '## NOW\n\nconfig note line\n' >"$cfg/projects/-proj/memory/n.md"
rm -f "$proj/.claude/settings.local.json"
printf '{"hooks":{"SessionStart":[{"matcher":"startup|clear","hooks":[{"type":"command","command":"python3 handoff.py start"}]}]}}' >"$cfg/settings.json"
out=$(env CLAUDE_CONFIG_DIR="$cfg" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$proj" --note "$cfg/projects/-proj/memory/n.md" --topic конфиг 2>&1); rc=$?
has "CLAUDE_CONFIG_DIR: подключение в его settings.json видно, отметка пишется" "marker:" "$out"
if [ $rc -eq 0 ] && [ -f "$cfg/state/handoff/4242-Mon-Nov-9-10-00-00-2026.json" ]; then ok; else bad "CLAUDE_CONFIG_DIR: отметка лежит в его state" "rc=$rc $(ls "$cfg/state/handoff" 2>&1)"; fi
out=$(start clear "$proj" CLAUDE_CONFIG_DIR="$cfg"); has "CLAUDE_CONFIG_DIR: после /clear записка отдаётся" "config note line" "$out"
out=$(env CLAUDE_CONFIG_DIR="$cfg" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$proj" --note "$note" --topic чужая 2>&1)
has "CLAUDE_CONFIG_DIR: записка из ~/.claude — не память этого Claude" "the note must be a file" "$out"

reset; mkdir -p "$work/vault" "$work/.claude/projects/-linked"; ln -s "$work/vault" "$work/.claude/projects/-linked/memory"
printf '## NOW\n\nlinked line\n' >"$work/vault/n.md"; linked="$work/.claude/projects/-linked/memory/n.md"
out=$(save "$proj" "$linked" "ссылка"); rc=$?
has "memory-ссылка: save пишет отметку" "marker:" "$out"; if [ $rc -eq 0 ]; then ok; else bad "memory-ссылка: код 0" "rc=$rc"; fi
has "memory-ссылка: после /clear записка отдаётся" "linked line" "$(start clear)"
printf 'secret line\n' >"$work/outside.md"; ln -s "$work/outside.md" "$work/vault/escape.md"
has "memory-ссылка: файл-ссылка наружу — отказ" "the note must be a file" "$(save "$proj" "$work/.claude/projects/-linked/memory/escape.md" "наружу")"
has "memory-ссылка: выход через .. — отказ" "the note must be a file" "$(save "$proj" "$work/.claude/projects/-linked/memory/../../../outside.md" "вверх")"
reset; mkdir -p "$work/vault" "$work/.claude/projects/-linked"; ln -s "$work/vault" "$work/.claude/projects/-linked/memory"
printf '## NOW\n\nlinked line\n' >"$work/vault/n.md"
marker a "$dead_pid" "$dead_started" "$proj" "$work/.claude/projects/-linked/memory/n.md" "по ссылке"
has "memory-ссылка: закрытая записка в списке" "\"по ссылке\"" "$(start startup)"

reset; mkdir -p "$work/proc/4242"; ln -s "$other" "$work/proc/4242/cwd"
printf '{"hooks":{"SessionStart":[{"matcher":"startup|clear","hooks":[{"type":"command","command":"python3 handoff.py start"}]}]}}' >"$other/.claude/settings.local.json"
out=$(env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_PROC="$work/proc" python3 -I "$HOOK" save --note "$note" --topic proc 2>&1)
real_other=$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$other")
if [ "$(markerfield "$markers" cwd)" = "$real_other" ]; then ok; else bad "/proc: папка процесса берётся оттуда, без lsof" "ждали $real_other, получили $(markerfield "$markers" cwd) | ${out:0:150}"; fi

reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "без fcntl"
out=$(printf '{"session_id":"nofcntl","cwd":"%s","source":"startup"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I -c 'import sys; sys.modules["fcntl"] = None; path = sys.argv[1]; sys.argv = [path, "start"]; exec(compile(open(path).read(), path, "exec"))' "$HOOK" 2>&1)
has "нет fcntl (Windows): хук грузится и даёт список" "\"без fcntl\"" "$out"
has "нет fcntl: строка журнала записана" "outcome=listed session=nofcntl" "$(tl outcome session)"


# --- защита: читается ровно тот путь, что прошёл проверку
reset; mkdir -p "$work/elsewhere/dir"; ln -s "$work/elsewhere/dir" "$mem/sub"; printf 'SECRET-KEY-LINE\n' >"$work/elsewhere/x.md"
printf '## NOW\n\nlegit line\n' >"$mem/x.md"
marker a 4242 "$own_started" "$proj" "$mem/sub/../x.md" "обход"
out=$(start clear); lacks "ссылка/..: чужой файл не выводится" "SECRET-KEY-LINE" "$out"
reset; mkdir -p "$proj/~/.claude/projects/-proj/memory"; printf '## NOW\n\nSECRET-TILDE\n' >"$proj/~/.claude/projects/-proj/memory/note.md"
marker a 4242 "$own_started" "$proj" "~/.claude/projects/-proj/memory/note.md" "тильда"
out=$(cd "$proj" && printf '{"session_id":"t","cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1)
lacks "~/ в отметке: папка с именем ~ в текущей папке не читается" "SECRET-TILDE" "$out"
reset; mkdir -p "$work/vault" "$work/.claude/projects/-linked"; ln -s "$work/vault" "$work/.claude/projects/-linked/memory"
linked="$work/.claude/projects/-linked/memory/n.md"; printf '## NOW\n\nself 73%% (cite: %s:3 "self 73%%")\n' "$linked" >"$work/vault/n.md"
has "memory-ссылка: save видит цитату записки на саму себя" "the note itself" "$(save "$proj" "$linked" "сама")"
reset; out=$(env HOME="$work" HANDOFF_TEST=1 CLAUDE_PID='²' python3 -I "$HOOK" save --cwd "$proj" --note "$note" --topic x 2>&1)
lacks "CLAUDE_PID не из цифр ASCII: без трассировки" "Traceback" "$out"
reset; mkdir -p "$work/bin"; ln -s /bin/bash "$work/bin/claude"; sleep 60 & bg=$!
( cd "$proj" && env HOME="$work" CLAUDE_PID="$bg" "$work/bin/claude" -c 'echo $$ >"$1/fakepid"; bash -c "python3 -I \"\$0\" save --note \"\$1\" --topic живой >/dev/null 2>&1; true" "$2" "$3"; true' _ "$work" "$HOOK" "$note" ) >/dev/null 2>&1
{ kill "$bg"; wait "$bg"; } 2>/dev/null; fake=$(cat "$work/fakepid" 2>/dev/null)
if [ -n "$fake" ] && [ "$(markerfield "$markers" pid)" = "$fake" ]; then ok; else bad "CLAUDE_PID живого процесса не из предков — не берётся" "ждали $fake, получили $(markerfield "$markers" pid)"; fi


# --- своя папка записок: ~/Library/Application Support/Hats/notes/<папка проекта>/<имя>.md
notes="$work/Library/Application Support/Hats/notes"
notes_of() { env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" where --cwd "$1" 2>&1; }
mode_of() { python3 -I -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1" 2>&1; }
realp() { python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
markers_n() { ls "$markers" | grep -c '\.json$'; }
reset; own_dir=$(notes_of "$proj"); rc=$?
case "${own_dir##*/}" in *[!0-9a-f]*) hex=no ;; *) hex=yes ;; esac
if [ $rc -eq 0 ] && [ -d "$own_dir" ] && [ "${own_dir%/*}" = "$notes" ] && [ "$hex" = yes ] && [ ${#own_dir} -eq $((${#notes} + 17)) ]; then ok
else bad "where: создаёт и печатает <корень>/<16 знаков hex>" "rc=$rc «${own_dir}»"; fi
has "where: корень записок — права 700" "0o700" "$(mode_of "$notes")"
has "where: папка проекта — права 700" "0o700" "$(mode_of "$own_dir")"
again=$(notes_of "$proj"); if [ "$again" = "$own_dir" ]; then ok; else bad "where: второй вызов — та же папка" "«${again}»"; fi
ln -s "$proj" "$work/projlink"; linked_dir=$(notes_of "$work/projlink"); rm -f "$work/projlink"
if [ "$linked_dir" = "$own_dir" ]; then ok; else bad "where: папка через ссылку — та же, что по настоящему пути" "«${linked_dir}»"; fi
reset; mkdir -p "$notes"; chmod 755 "$notes"; own_dir=$(notes_of "$proj")
has "where: существующий корень не трогает" "0o755" "$(mode_of "$notes")"
has "where: новая папка проекта в прежнем корне — 700" "0o700" "$(mode_of "$own_dir")"
reset; mkdir -p "$work/a/b-c" "$work/a-b/c"; one=$(notes_of "$work/a/b-c"); two=$(notes_of "$work/a-b/c")
if [ -d "$one" ] && [ -d "$two" ] && [ "$one" != "$two" ]; then ok; else bad "where: /a/b-c и /a-b/c — разные папки" "«${one}» «${two}»"; fi
long="$work/long/$(printf 'd%.0s' $(seq 1 100))/$(printf 'e%.0s' $(seq 1 100))/$(printf 'f%.0s' $(seq 1 100))"; mkdir -p "$long"
out=$(notes_of "$long"); rc=$?
if [ ${#long} -ge 300 ] && [ $rc -eq 0 ] && [ -d "$out" ]; then ok; else bad "where: путь проекта длиннее 300 знаков — папка создана" "длина ${#long}, rc=$rc «${out:0:200}»"; fi
rm -rf "$work/a" "$work/a-b" "$work/long"
reset; mkdir -p "${notes%/*}"; printf 'x' >"$notes"; out=$(notes_of "$proj"); rc=$?
has "where: папку не создать — так и сказано" "could not create the notes folder" "$out"; lacks "where: папку не создать — без трассировки" "Traceback" "$out"
if [ $rc -eq 1 ]; then ok; else bad "where: папку не создать — код 1" "rc=$rc"; fi

reset; own_dir=$(notes_of "$proj"); printf '## NOW\n\nown line\n' >"$own_dir/r.md"
out=$(save "$proj" "$own_dir/r.md" "своя"); rc=$?
has "своя папка: save пишет отметку" "marker:" "$out"
if [ $rc -eq 0 ] && [ "$(markerfield "$markers" note)" = "$(realp "$own_dir/r.md")" ]; then ok; else bad "своя папка: код 0, в отметке настоящий путь записки" "rc=$rc $(markerfield "$markers" note)"; fi
has "своя папка: после /clear записка отдаётся" "own line" "$(start clear)"
reset; own_dir=$(notes_of "$proj"); printf '## NOW\n\nown line\n' >"$own_dir/r.md"
marker a "$dead_pid" "$dead_started" "$proj" "$own_dir/r.md" "своя закрытая"
has "своя папка: закрытая записка в списке новой сессии" "\"своя закрытая\"" "$(start startup)"
reset; own_dir=$(notes_of "$proj"); mkdir "$own_dir/dir.md"
has "своя папка: записки нет — отказ" "the note must be a file" "$(save "$proj" "$own_dir/gone.md" "без файла")"
has "своя папка: папка вместо записки — отказ" "the note must be a file" "$(save "$proj" "$own_dir/dir.md" "папка")"
printf 'x\n' >"$own_dir/note.txt"; has "своя папка: записка не .md — отказ" "the note must be a file" "$(save "$proj" "$own_dir/note.txt" "txt")"
marker a "$dead_pid" "$dead_started" "$proj" "$own_dir/gone.md" "без файла"
empty "своя папка: записки нет на диске — список молчит" "$(start startup)"
reset; rm -rf "$work/.claude/projects"; own_dir=$(notes_of "$proj"); printf '## NOW\n\nno memory line\n' >"$own_dir/r.md"
out=$(save "$proj" "$own_dir/r.md" "без памяти"); rc=$?
has "памяти нет: save пишет отметку" "marker:" "$out"
has "памяти нет: после /clear записка отдаётся" "no memory line" "$(start clear)"
if [ $rc -eq 0 ] && [ ! -e "$work/.claude/projects" ]; then ok; else bad "памяти нет: код 0, папка памяти не появилась" "rc=$rc"; fi

escapes() {  # своя записка x.md и пути мимо своей папки; заполняет own_dir, other_dir, bad_cases
  rm -rf "$work/elsewhere" "$work/outside.md"
  own_dir=$(notes_of "$proj"); other_dir=$(notes_of "$other")
  mkdir -p "$own_dir/sub" "$work/elsewhere/dir"; printf '## NOW\n\nlegit line\n' >"$own_dir/x.md"
  printf '## NOW\n\nSECRET-NESTED\n' >"$own_dir/sub/x.md"
  printf '## NOW\n\nSECRET-OUTSIDE\n' >"$work/outside.md"; ln -s "$work/outside.md" "$own_dir/escape.md"
  ln -s "$work/elsewhere/dir" "$own_dir/hop"; printf '## NOW\n\nSECRET-DOTDOT\n' >"$work/elsewhere/x.md"
  printf '## NOW\n\nSECRET-UP\n' >"$notes/up.md"; printf '## NOW\n\nSECRET-FOREIGN\n' >"$other_dir/x.md"
  bad_cases=("вложенная папка|$own_dir/sub/x.md" "файл-ссылка наружу|$own_dir/escape.md" "выход через ..|$own_dir/../up.md"
    "папка чужого проекта|$other_dir/x.md" "вне обеих папок|$work/outside.md")
}
reset; escapes
for case_ in "${bad_cases[@]}"; do
  rm -f "$markers"/*; label=${case_%%|*}; out=$(save "$proj" "${case_#*|}" "мимо"); rc=$?
  has "save: $label — отказ" "the note must be a file" "$out"
  if [ $rc -eq 1 ] && [ "$(markers_n)" -eq 0 ]; then ok; else bad "save: $label — код 1 и без отметки" "rc=$rc $(ls "$markers")"; fi
done
out=$(save "$proj" "$work/outside.md" "мимо")
has "save: отказ называет свою папку" "$own_dir/<name>.md" "$out"; has "save: отказ называет память" "/memory/<name>.md" "$out"
bad_cases+=("папка-ссылка и ..|$own_dir/hop/../x.md")
for case_ in "${bad_cases[@]}"; do
  rm -f "$markers"/*; mine a "$proj" "${case_#*|}" "мимо"
  empty "/clear: отметка руками, ${case_%%|*} — молчит" "$(start clear)"
done
rm -f "$markers"/*; mine a "$proj" "$own_dir/x.md" "своя"
has "/clear: рядом своя записка своей папки отдаётся" "legit line" "$(start clear)"
rm -f "$markers"/*; marker good "$dead_pid" "$dead_started" "$proj" "$own_dir/x.md" "своя"
i=0; for case_ in "${bad_cases[@]}"; do i=$((i + 1)); marker "b$i" $((99970 + i)) "$dead_started" "$proj" "${case_#*|}" "мимо: ${case_%%|*}"; done
out=$(start startup); has "новая сессия: своя записка в списке" "\"своя\"" "$out"
lacks "новая сессия: отметки руками мимо своей папки не в списке" "мимо" "$out"

reset; own_dir=$(notes_of "$proj"); printf '## NOW\n\nx\n' >"$own_dir/r.md"
shouty=$(printf '%s' "$own_dir" | sed 's|/Hats/notes/|/HATS/notes/|'); out=$(save "$proj" "$shouty/r.md" "регистр"); rc=$?
has "регистр букв не тот, что напечатал where: отказ" "the note must be a file" "$out"
if [ "$shouty" != "$own_dir" ] && [ $rc -eq 1 ] && [ "$(markers_n)" -eq 0 ]; then ok; else bad "регистр букв: код 1 и без отметки" "rc=$rc $(ls "$markers")"; fi

reset; own_dir=$(notes_of "$proj")
for i in 1 2 3; do
  printf '## NOW\n\nline of task %s\n' "$i" >"$own_dir/resume-t$i.md"
  env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="424$i:$own_started" python3 -I "$HOOK" save --cwd "$proj" --note "$own_dir/resume-t$i.md" --topic "задача $i" >/dev/null 2>&1
done
n=$(ls "$own_dir" | grep -c '\.md$')
if [ "$(markers_n)" -eq 3 ] && [ "$n" -eq 3 ]; then ok; else bad "три сессии: три отметки, три записки в одной папке проекта" "отметок $(markers_n), записок $n"; fi
for i in 1 2 3; do
  out=$(start clear "$proj" HANDOFF_PROCESS="424$i:$own_started"); has "три сессии: процесс $i после /clear получает свою" "line of task $i" "$out"
  for j in 1 2 3; do [ "$j" = "$i" ] || lacks "три сессии: процесс $i не получает записку $j" "line of task $j" "$out"; done
done
out=$(start startup); for i in 1 2 3; do has "три сессии: новая сессия видит закрытую $i" "\"задача $i\"" "$out"; done

reset; rm -rf "$work/proc"; mkdir -p "$work/proc/4242"; ln -s "$other" "$work/proc/4242/cwd"
printf '{"hooks":{"SessionStart":[{"matcher":"startup|clear","hooks":[{"type":"command","command":"python3 handoff.py start"}]}]}}' >"$other/.claude/settings.local.json"
dir=$(env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_PROC="$work/proc" python3 -I "$HOOK" where 2>&1)
if [ "$dir" = "$(notes_of "$other")" ]; then ok; else bad "where без --cwd: папка процесса Claude (/proc)" "«${dir}»"; fi
printf '## NOW\n\nproc line\n' >"$dir/r.md"
out=$(env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_PROC="$work/proc" python3 -I "$HOOK" save --note "$dir/r.md" --topic proc 2>&1)
has "where и save без --cwd — одна папка: отметка записана" "marker:" "$out"
if [ "$(markerfield "$markers" cwd)" = "$(realp "$other")" ]; then ok; else bad "where и save без --cwd: папка в отметке — из /proc" "$(markerfield "$markers" cwd)"; fi

reset; own_dir=$(notes_of "$proj"); other_dir=$(notes_of "$other")
printf 'share 73%%\n' >"$own_dir/x.md"; printf 'share 73%%\n' >"$other_dir/y.md"; printf 'share 73%%\n' >"$proj/src.md"
has "цитата обычного файла — источник" "all verified" "$(checkline "x (cite: $proj/src.md:1 \"share 73%\")")"
has "цитата своей папки — не источник" "quote of the notes folder is not a source" "$(checkline "x (cite: $own_dir/x.md:1 \"share 73%\")")"
has "цитата записки чужого проекта — не источник" "quote of the notes folder is not a source" "$(checkline "x (cite: $other_dir/y.md:1 \"share 73%\")")"
printf '## NOW\n\nx 73%% (cite: %s:1 "share 73%%")\n' "$own_dir/x.md" >"$own_dir/r.md"
out=$(save "$proj" "$own_dir/r.md" "цитата"); has "цитата своей папки в записке: save пишет отметку" "marker:" "$out"
has "цитата своей папки в записке: строка в «not verified»" "not verified in the note:
- line 3: quote of the notes folder is not a source" "$out"
shouty=$(printf '%s' "$own_dir" | sed 's|/Hats/notes/|/HATS/NOTES/|')
lacks "цитата своей папки в другом регистре — не «all verified»" "all verified" "$(checkline "x (cite: $shouty/x.md:1 \"share 73%\")")"

reset; own_dir=$(notes_of "$proj"); printf '## NOW\n\nx\n' >"$own_dir/r.md"
marker dead "$dead_pid" "$dead_started" "$proj" "$own_dir/r.md" "та же"
marker live "$me_pid" "$me_started" "$proj" "$own_dir/r.md" "та же, живая"
out=$(save "$proj" "$own_dir/r.md" "своя")
has "save: снимает одну закрытую с той же запиской своей папки" "removed markers of closed sessions with the same note: 1" "$out"
if [ ! -f "$markers/dead.json" ]; then ok; else bad "save: закрытая с той же запиской своей папки снята" "осталась"; fi
if [ -f "$markers/live.json" ]; then ok; else bad "save: живую с той же запиской своей папки не трогает" "пропала"; fi

reset; rm -rf "$work/hatsdata"; mkdir -p "$work/hatsdata" "$work/Library/Application Support"
ln -s "$work/hatsdata" "$work/Library/Application Support/Hats"
own_dir=$(notes_of "$proj"); printf '## NOW\n\nlinked root line\n' >"$own_dir/r.md"; printf 'share 73%%\n' >"$own_dir/x.md"
out=$(save "$proj" "$own_dir/r.md" "корень-ссылка"); rc=$?
has "корень записок — ссылка: save пишет отметку" "marker:" "$out"
want="$(realp "$work/hatsdata")/notes/${own_dir##*/}/r.md"
if [ $rc -eq 0 ] && [ "$(markerfield "$markers" note)" = "$want" ]; then ok; else bad "корень записок — ссылка: в отметке путь за ссылкой" "rc=$rc $(markerfield "$markers" note)"; fi
has "корень записок — ссылка: после /clear записка отдаётся" "linked root line" "$(start clear)"
has "корень записок — ссылка: цитата через ссылку — не источник" "quote of the notes folder is not a source" "$(checkline "x (cite: $own_dir/x.md:1 \"share 73%\")")"
has "корень записок — ссылка: цитата по пути за ссылкой — не источник" "quote of the notes folder is not a source" \
  "$(checkline "x (cite: $work/hatsdata/notes/${own_dir##*/}/x.md:1 \"share 73%\")")"
rm -rf "$work/hatsdata"


# --- подключение плагином: hooks/hooks.json своего плагина читается, только если рядом .claude-plugin/plugin.json
plug="$work/plug"
plugin_at() {  # plugin_at <hooks.json или -> <yes|no — класть ли plugin.json>
  rm -rf "$plug"; mkdir -p "$plug/scripts" "$plug/hooks"; cp "$HOOK" "$plug/scripts/handoff.py"; cp "$plugin_root/scripts/py.sh" "$plug/scripts/py.sh"
  [ "$1" = "-" ] || cp "$1" "$plug/hooks/hooks.json"
  [ "$2" = "no" ] || { mkdir -p "$plug/.claude-plugin"; cp "$plugin_root/.claude-plugin/plugin.json" "$plug/.claude-plugin/plugin.json"; }
}
plugsave() { env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$1" save --cwd "$other" --note "$note" --topic плагин 2>&1; }
reset; plugin_at "$plugin_root/hooks/hooks.json" yes; out=$(plugsave "$plug/scripts/handoff.py"); rc=$?
has "плагин: хук старта в hooks.json плагина — отметка записана" "marker:" "$out"
if [ $rc -eq 0 ] && [ -f "$markers/4242-Mon-Nov-9-10-00-00-2026.json" ]; then ok; else bad "плагин: файл отметки есть, код 0" "rc=$rc $(ls "$markers")"; fi
reset; plugin_at "$plugin_root/hooks/hooks.json" no; out=$(plugsave "$plug/scripts/handoff.py"); rc=$?
has "плагин: папка без plugin.json — выключено" "handoff is off" "$out"
if [ $rc -eq 0 ] && [ -z "$(ls "$markers")" ]; then ok; else bad "плагин: без plugin.json — код 0 и без отметки" "rc=$rc $(ls "$markers")"; fi
reset; printf '{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"python3 other.py start"}]}],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"python3 save-state-nudge.py"}]}]}}' >"$work/nostart.json"
plugin_at "$work/nostart.json" yes; out=$(plugsave "$plug/scripts/handoff.py"); rc=$?
has "плагин: в hooks.json нет хука старта — выключено" "handoff is off" "$out"
if [ $rc -eq 0 ] && [ -z "$(ls "$markers")" ]; then ok; else bad "плагин: без хука старта — код 0 и без отметки" "rc=$rc $(ls "$markers")"; fi
reset; plugin_at - yes
has "плагин: hooks.json нет — выключено" "handoff is off" "$(plugsave "$plug/scripts/handoff.py")"
reset; mkdir -p "$work/.claude/hooks"; cp "$HOOK" "$work/.claude/hooks/handoff.py"; cp "$plugin_root/hooks/hooks.json" "$work/.claude/hooks/hooks.json"
has "живая копия: hooks.json рядом без plugin.json не включает" "handoff is off" "$(plugsave "$work/.claude/hooks/handoff.py")"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"python3 ~/.claude/hooks/handoff.py start"}]}]}}' >"$work/.claude/settings.json"
has "живая копия: подключение из settings.json — как раньше" "marker:" "$(plugsave "$work/.claude/hooks/handoff.py")"


# --- поставляемые настройки: hooks.json плагина и каталог маркетплейса в корне репозитория
shipped() {  # shipped matcher|script|command — что говорит hooks.json плагина о хуке старта
  python3 -I -c 'import json,os,re,shlex,sys
what, root = sys.argv[1], sys.argv[2]
groups = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))["hooks"]["SessionStart"]
found = [(g.get("matcher", ""), h["command"]) for g in groups for h in g["hooks"] if "handoff.py" in h.get("command", "")]
if len(found) != 1:
    sys.exit(f"commands with handoff.py under SessionStart: {len(found)}")
matcher, command = found[0]
if what == "matcher":
    every = matcher in ("", "*")
    print(" ".join(f"{s}={every or bool(re.fullmatch(matcher, s))}" for s in ("startup", "clear")))
elif what == "script":
    words = shlex.split(command.replace("${CLAUDE_PLUGIN_ROOT}", root))
    scripts = [w for w in words if w.endswith("handoff.py")]
    script = scripts[0] if scripts else None
    start = words[-1:] == ["start"]
    print(f"script={script} exists={script is not None and os.path.isfile(script)} start={start}")
else:
    print(command)' "$1" "$plugin_root" 2>&1
}
has "hooks.json: matcher хука старта покрывает startup и clear" "startup=True clear=True" "$(shipped matcher)"
has "hooks.json: команда называет scripts/handoff.py плагина, и он есть" "script=$plugin_root/scripts/handoff.py exists=True start=True" "$(shipped script)"
reset; mine; plugin_at "$plugin_root/hooks/hooks.json" yes; command_line=$(shipped command)
out=$(printf '{"session_id":"sh1","cwd":"%s","source":"clear"}' "$proj" | env CLAUDE_PLUGIN_ROOT="$plug" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" sh -c "$command_line" 2>&1)
has "hooks.json: команда как есть через sh -c отдаёт записку после /clear" "continues the note \"задача А\"" "$out"
mkdir -p "$work/darwin"; printf '#!/bin/sh\necho Darwin\n' >"$work/darwin/uname"; chmod +x "$work/darwin/uname"
out=$(printf '{"session_id":"sh1","cwd":"%s","source":"clear"}' "$proj" | env CLAUDE_PLUGIN_ROOT="$plug" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" \
  PATH="$work/darwin:$PATH" HATS_SYSTEM_PYTHON="$(command -v python3)" HATS_XCODE_SELECT=/usr/bin/false sh -c "$command_line" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then ok; else bad "hooks.json: заглушка python3 — команда старта молчит, код 0" "rc=$rc out=${out:0:300}"; fi

# --- поставляемые настройки: обёртка py.sh, напоминание и скилл anchor
hooked() {  # hooked wrapper|nudge|command — что говорит hooks.json плагина об обёртке и напоминании
  python3 -I -c 'import json,os,shlex,sys
what, root = sys.argv[1], sys.argv[2]
hooks = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))["hooks"]
wrapper = os.path.join(root, "scripts", "py.sh")
if what == "wrapper":
    entries = [(event, h["command"]) for event, groups in hooks.items() for g in groups for h in g["hooks"]]
    problems = []
    for event, command in entries:
        words = shlex.split(command.replace("${CLAUDE_PLUGIN_ROOT}", root))
        if words[:3] != ["sh", wrapper, "--quiet"] or len(words) < 4 or not os.path.isfile(words[3]):
            problems.append(event + ": " + command)
    print("; ".join(problems) if problems else "wrapped=%d py.sh=%s" % (len(entries), os.path.isfile(wrapper)))
    sys.exit(0)
found = [(g, h) for g in hooks.get("UserPromptSubmit", []) for h in g["hooks"] if "anchor-nudge.py" in h.get("command", "")]
if len(found) != 1:
    sys.exit("commands with anchor-nudge.py under UserPromptSubmit: %d" % len(found))
group, hook = found[0]
if what == "command":
    print(hook["command"])
    sys.exit(0)
words = shlex.split(hook["command"].replace("${CLAUDE_PLUGIN_ROOT}", root))
script = [w for w in words if w.endswith("anchor-nudge.py")][0]
print("script=%s exists=%s timeout=%s" % (script, os.path.isfile(script), hook.get("timeout")))' "$1" "$plugin_root" 2>&1
}
has "hooks.json: оба хука идут через py.sh --quiet, их скрипты и py.sh есть" "wrapped=2 py.sh=True" "$(hooked wrapper)"
has "hooks.json: UserPromptSubmit запускает scripts/anchor-nudge.py плагина, и он есть" \
  "script=$plugin_root/scripts/anchor-nudge.py exists=True timeout=5" "$(hooked nudge)"
nudge_line=$(hooked command)
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"hats:anchor"}}]}}\n' >"$work/anchor.jsonl"
out=$(printf '{"session_id":"sh2","prompt":"анкор","transcript_path":"%s"}' "$work/anchor.jsonl" | env CLAUDE_PLUGIN_ROOT="$plugin_root" HOME="$work" sh -c "$nudge_line" 2>&1)
has "hooks.json: напоминание как есть через sh -c называет anchor" "The anchor skill (hats:anchor) already ran" "$out"
out=$(printf '{"session_id":"sh2","prompt":"анкор","transcript_path":"%s"}' "$work/anchor.jsonl" | env CLAUDE_PLUGIN_ROOT="$plugin_root" HOME="$work" \
  PATH="$work/darwin:$PATH" HATS_SYSTEM_PYTHON="$(command -v python3)" HATS_XCODE_SELECT=/usr/bin/false sh -c "$nudge_line" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then ok; else bad "hooks.json: заглушка python3 — напоминание молчит, код 0" "rc=$rc out=${out:0:300}"; fi
out=$(python3 -I -c 'import os,re,shlex,sys
root = sys.argv[1]
text = open(os.path.join(root, "skills", "anchor", "SKILL.md"), encoding="utf-8").read()
parts = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
if not parts:
    sys.exit("SKILL.md has no frontmatter")
head, body = parts.groups()
lines = head.splitlines()
fields = dict(line.split(": ", 1) for line in lines if ": " in line and not line.startswith(" "))
if "allowed-tools:" not in lines:
    sys.exit("allowed-tools is not a YAML list: " + fields.get("allowed-tools", ""))
rules = []
for line in lines[lines.index("allowed-tools:") + 1:]:
    if not line.startswith("  - "):
        break
    rules.append(line[4:])
bash = [r for r in rules if r.startswith("Bash(")]
handoff_rules = [r for r in bash if "/scripts/handoff.py" in r]
rule = re.fullmatch(r"Bash\((.+) \*\)", handoff_rules[0]) if len(bash) == 2 and len(handoff_rules) == 1 else None
if not rule:
    sys.exit("allowed-tools has not two Bash rules, one of them Bash(<handoff.py prefix> *): %r" % rules)
prefix = rule.group(1)
spans = re.findall(r"`([^`\n]+)`", body)
saves = [c for c in spans if " save " in c]
same = len(saves) == 1 and saves[0].startswith(prefix + " save ")
wheres = [c for c in spans if c.endswith(" where")]
where = len(wheres) == 1 and wheres[0] == prefix + " where"
words = shlex.split(prefix)
wrapped = words[:2] == ["sh", "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh"] and "--quiet" not in words
files = [w.replace("${CLAUDE_PLUGIN_ROOT}", root) for w in words[1:]]
spaced = shlex.split(prefix.replace("${CLAUDE_PLUGIN_ROOT}", "/a b")) == ["sh", "/a b/scripts/py.sh", "/a b/scripts/handoff.py"]
print("name=%s same=%s where=%s wrapped=%s handoff=%s files=%s spaced=%s" % (
    fields.get("name"), same, where, wrapped, "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" in words,
    bool(files) and all(os.path.isfile(f) for f in files), spaced))
own = [re.fullmatch(r"Bash\((.+)\)", r) for r in bash if "/scripts/anchor-steps.py" in r]
own_line = own[0].group(1) if len(own) == 1 and own[0] else ""
own_words = shlex.split(own_line)
print("steps: same=%s wrapped=%s file=%s spaced=%s" % (
    bool(own_line) and [c for c in spans if "anchor-steps.py" in c] == [own_line],
    own_words == ["sh", "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh", "${CLAUDE_PLUGIN_ROOT}/scripts/anchor-steps.py"],
    len(own_words) == 3 and os.path.isfile(own_words[2].replace("${CLAUDE_PLUGIN_ROOT}", root)),
    shlex.split(own_line.replace("${CLAUDE_PLUGIN_ROOT}", "/a b")) == ["sh", "/a b/scripts/py.sh", "/a b/scripts/anchor-steps.py"]))
folders = [re.fullmatch(r"(Write|Edit|Read)\(~(/.+)/\*\*\)", r) for r in rules if r not in bash]
roots = sorted({m.group(2) for m in folders if m})
print("rules=%d tools=%s roots=%d root=%s|" % (
    len(rules), ",".join(sorted(m.group(1) for m in folders if m)), len(roots), sys.argv[2] + roots[0] if roots else None))' \
  "$plugin_root" "$work" 2>&1)
has "SKILL.md anchor: save и where в теле и правило Bash в allowed-tools — одна команда через py.sh, файлы есть, путь с пробелом цел" \
  "name=anchor same=True where=True wrapped=True handoff=True files=True spaced=True" "$out"
has "SKILL.md anchor: шаг 0 — ровно команда второго правила Bash через py.sh, anchor-steps.py есть, путь с пробелом цел" \
  "steps: same=True wrapped=True file=True spaced=True" "$out"
reset; hook_root=$(notes_of "$proj"); hook_root=${hook_root%/*}
has "SKILL.md anchor: allowed-tools — YAML-список из пяти правил, Write/Edit/Read на корень записок handoff.py" \
  "rules=5 tools=Edit,Read,Write roots=1 root=$hook_root|" "$out"
out=$(python3 -I -c 'import json,os,sys
root = sys.argv[1]
plugins = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json"), encoding="utf-8"))["plugins"]
problems = []
for p in plugins:
    label, source = p.get("name"), p.get("source")
    if not isinstance(source, str):
        problems.append(f"{label}: source is not a path: {source!r}")
        continue
    manifest = os.path.join(root, source, ".claude-plugin", "plugin.json")
    if not os.path.isfile(manifest):
        problems.append(f"{label}: no {manifest}")
        continue
    name = json.load(open(manifest, encoding="utf-8")).get("name")
    if name != label:
        problems.append(f"{label}: plugin.json names {name!r}")
print("; ".join(problems) if problems or not plugins else f"catalog ok: {len(plugins)}")' "$(cd "$plugin_root/.." && pwd)" 2>&1)
has "marketplace.json: каждый источник — папка с plugin.json того же имени" "catalog ok:" "$out"

total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "handoff: $pass/$total прошли"; exit 0; fi
echo "handoff: $pass/$total прошли, $fail упало$failures"; exit 1
