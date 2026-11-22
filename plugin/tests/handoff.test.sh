#!/usr/bin/env bash
# Матрица для handoff.py. Одна строка итога, подробности только по упавшим.
#
#   bash plugin/tests/handoff.test.sh
#   HOOK_UNDER_TEST=/path/to/candidate.py bash plugin/tests/handoff.test.sh
#   0 — все прошли, 1 — есть падения
#
# Хук гоняется из копии вне плагина: на своём месте он видит hooks/hooks.json плагина и
# включён в любой папке. Плагин собирается во временной папке только в случаях подключения.
# handoff.py — точка входа, его части лежат рядом (handoff_*.py, hats_common.py): каждая копия
# хука кладётся вместе с ними (put_hook), а подмена функции в запуске через exec идёт через swap —
# она меняет имя в каждом модуле handoff_*, который его держит.
#
# Сверка с образцом. Каждый вызов через помощники start и nobody и вызов команды из hooks.json
# через sh -c проверяются одинаково: stdout — один объект JSON байтами UTF-8 с переводом строки
# или пусто, код 0, stderr пуст. На том же вводе и состоянии прогоняется образец —
# fixtures/handoff-reference.py, handoff.py коммита d5a8185 байт в байт, последний хук, что
# печатал модели простой текст; его записи (runs.log и файл передачи) выключены, чтобы
# состояние осталось тем же для нового. additionalContext нового обязан совпасть со stdout
# образца без последнего перевода строки, а где образец молчал, у нового нет hookSpecificOutput.
# Без сверки (CMP=0) — вызовы, где текст или замер зависит от времени (HANDOFF_TEST_BUDGET,
# медленные ps и git, ожидание блокировки, одновременные запуски), и два, где образец падает по
# замыслу (stdout в Latin-1, одинокий суррогат в теме). Прямые запуски хука мимо помощников
# (битый ввод, exec-обвязки, нет fcntl, поиск настоящего процесса) не сверяются. В конце число
# строк сверки обязано равняться числу вызовов, начавших сверку.
#
# Срок образца: он держит «текст модели не изменился». Задача, которая меняет текст модели
# намеренно, в том же коммите заменяет образец копией своего handoff.py и пишет здесь, с какого
# коммита образец; правка текста модели без замены образца красит набор. Задача 8c образец не
# заменила: её строки модели появляются только при файлах пометки (taken/), а без них текст —
# символ в символ прежний; вызовы с файлами пометки, где текст меняется, идут с CMP=0.
# Запись 47 образец тоже не заменила: выдержка теперь режется, чтобы блок «Not verified» влез,
# а нечитаемая записка не отдаётся; текст меняется только у записок за пределом вывода и у
# нечитаемых, и эти вызовы идут с CMP=0.
#
# Задача 8c: хук took (после Read) гоняется помощниками took и took_raw со входом из замера
# 2026-11-13; его вывод проверяется той же формой с hookEventName PostToolUse, без сверки.
# Читатели — живые процессы: оболочка теста ($$) и фоновые sleep (live), гасятся при выходе.
set -uo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SOURCE="${HOOK_UNDER_TEST:-$plugin_root/scripts/handoff.py}"
export CLAUDE_CODE_SESSION_ATTENDED=1; unset CLAUDE_CODE_ENTRYPOINT CLAUDE_PID CLAUDE_CONFIG_DIR HATS_STATE_HOME
pass=0; fail=0; failures=""; skipped=0; skips=""
work=$(mktemp -d "${TMPDIR:-/tmp}/handoff-test.XXXXXX")
trap 'kill $(cat "$work/sleepers" 2>/dev/null) 2>/dev/null; rm -rf "$work"' EXIT
mkdir -p "$work/loose"; HOOK="$work/loose/handoff.py"; cp "$HOOK_SOURCE" "$HOOK"
copy_parts() {  # copy_parts <откуда> <куда> — модули хука; без handoff_*.py или hats_common.py набор падает сразу
  local part found=0
  for part in "$1"/handoff_*.py; do [ -f "$part" ] && found=1 && cp "$part" "$2/"; done
  if [ $found -eq 0 ]; then echo "handoff: рядом с хуком в $1 нет ни одного handoff_*.py"; exit 1; fi
  if [ ! -f "$1/hats_common.py" ]; then echo "handoff: рядом с хуком нет $1/hats_common.py"; exit 1; fi
  cp "$1/hats_common.py" "$2/"
}
copy_parts "$(dirname "$HOOK_SOURCE")" "$work/loose"
put_hook() {  # put_hook <папка> — копия хука с его модулями в папку
  cp "$HOOK" "$1/handoff.py"; copy_parts "$work/loose" "$1"
}
swap_py='def swap(name, value):
    hits = [module for module in list(sys.modules.values())
            if getattr(module, "__name__", "").startswith("handoff_") and name in vars(module)]
    if not hits:
        raise SystemExit("swap: no handoff module holds " + name)
    old = getattr(hits[0], name)
    for module in hits:
        setattr(module, name, value)
    return old'
mkdir -p "$work/before"; OLD_HOOK="$plugin_root/tests/fixtures/handoff-reference.py"
cat >"$work/before/run.py" <<'EOF'
import sys
path = sys.argv[1]
scope = {
    "__name__": "handoff_reference",
    "__file__": path,
}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), scope)
scope["record_handed"] = lambda *args: None
scope["write_trace"] = lambda *args: None
sys.exit(scope["main"](["start"]))
EOF
cat >"$work/shape.py" <<'EOF'
import json
import sys
import unicodedata

call, label, compare, code, box = sys.argv[1:6]
event = sys.argv[6] if len(sys.argv) > 6 else "SessionStart"
raw = open(call + "/out", "rb").read()
err = open(call + "/err", "rb").read()
problems = []
model = None
user = None
HOOK_FIELDS = {
    "hookEventName",
    "additionalContext",
}
TOP_FIELDS = {
    "systemMessage",
    "hookSpecificOutput",
}
CONTROL = {
    "Cc",
    "Cs",
    "Zl",
    "Zp",
}


def check_hook(hook):
    if not isinstance(hook, dict) or set(hook) != HOOK_FIELDS:
        return None, "hookSpecificOutput не из двух полей: %r" % (hook,)
    if hook["hookEventName"] != event:
        return None, "hookEventName не %s: %r" % (event, hook["hookEventName"])
    if not isinstance(hook["additionalContext"], str) or not hook["additionalContext"]:
        return None, "additionalContext пуст или не строка"
    return hook["additionalContext"], None


def is_hidden(ch):
    return (
        unicodedata.category(ch) in CONTROL
        or 0x202A <= ord(ch) <= 0x202E
        or 0x2066 <= ord(ch) <= 0x2069
    )


def check_user(line):
    if not isinstance(line, str) or not line.startswith("Hats handoff: "):
        return "systemMessage не начинается с «Hats handoff: »: %r" % (line,)
    odd = [ch for ch in line if ch != "\n" and is_hidden(ch)]
    if odd:
        return "в systemMessage управляющие знаки: %r" % (odd[:5],)
    if len(line.encode("utf-16-le")) // 2 > 2000:
        return "systemMessage длиннее 2000 единиц UTF-16"
    return None


def check_output():
    global model, user
    if not raw:
        return
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict) or not data or not set(data) <= TOP_FIELDS:
        problems.append("в stdout не тот объект: %r" % (sorted(data) if isinstance(data, dict) else data,))
        return
    if raw != json.dumps(data, ensure_ascii=False).encode("utf-8") + b"\n":
        problems.append("stdout — не один объект JSON байтами UTF-8 с переводом строки")
    if "hookSpecificOutput" in data:
        model, problem = check_hook(data["hookSpecificOutput"])
        if problem:
            problems.append(problem)
    if "systemMessage" in data:
        problem = check_user(data["systemMessage"])
        if problem:
            problems.append(problem)
        user = data["systemMessage"]


def compare_with_old():
    old = open(call + "/old", "rb").read()
    if model is None and old:
        problems.append("образец напечатал %d байт, у нового нет hookSpecificOutput" % len(old))
        return
    if model is None:
        return
    want = (model + "\n").encode("utf-8")
    if old != want:
        at = next((i for i, pair in enumerate(zip(old, want)) if pair[0] != pair[1]), min(len(old), len(want)))
        problems.append("additionalContext не равен выводу образца: с байта %d, %d байт против %d" % (at, len(want), len(old)))


if code != "0":
    problems.append("код выхода " + code)
if err:
    problems.append("stderr: " + err.decode("utf-8", "replace")[:200])
try:
    check_output()
    if compare == "1":
        compare_with_old()
except Exception as error:
    problems.append("вывод не разобран: %s: %s" % (type(error).__name__, error))
with open(box + "/told", "w", encoding="utf-8", errors="replace") as f:
    f.write(user or "")
with open(box + "/heard", "wb") as f:
    f.write(raw)
with open(box + "/checks.log", "a", encoding="utf-8", errors="replace") as f:
    note = "; ".join(problems).replace("\n", " ").replace("\t", " ")
    f.write("%s\t%s\t%s\t%s\n" % ("bad" if problems else "ok", compare, label, note[:400]))
sys.stdout.buffer.write((model or "").encode("utf-8", "replace"))
EOF

proj="$work/proj"
other="$work/other"
mem="$work/.claude/projects/-proj/memory"
note="$mem/note.md"
real_mem="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$mem")"; real_note="$real_mem/note.md"
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
open_call() {  # open_call <ввод> — печатает новую папку вызова с вводом; told и heard прошлого вызова убраны
  local call
  rm -f "$work/told" "$work/heard"; call=$(mktemp -d "$work/call.XXXXXX"); printf '%s' "$1" >"$call/in"; printf '%s' "$call"
}
run_reference() {  # run_reference <папка вызова> <env...> — образец на том же вводе; код 0 — сверка начата и посчитана
  local call="$1"; shift
  if [ "${CMP:-1}" != 1 ] || [ ! -s "$OLD_HOOK" ]; then return 1; fi
  printf 'begun\n' >>"$work/compares.log"
  env "$@" python3 -I "$work/before/run.py" "$OLD_HOOK" <"$call/in" >"$call/old" 2>/dev/null
  return 0
}
judge() {  # judge <папка вызова> <подпись> <сверка 0|1> <код хука> [событие] — форма и сверка; печатает текст модели
  python3 -I "$work/shape.py" "$1" "$2" "$3" "$4" "$work" "${5:-SessionStart}" ||
    printf 'bad\t%s\t%s\tпроверка формы вышла с кодом %s\n' "$3" "$2" "$?" >>"$work/checks.log"
}
start() {  # start <source> [cwd] [env...] — печатает текст модели; строка пользователю — told, весь stdout — heard; CMP=0 — без сверки
  local src="$1" cwd="${2:-$proj}" call rc compare=0; shift; shift || true
  call=$(open_call "$(printf '{"session_id":"%s","cwd":"%s","source":"%s"}' "$sid" "$cwd" "$src")")
  run_reference "$call" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" "$@" && compare=1
  env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" "$@" python3 -I "$HOOK" start <"$call/in" >"$call/out" 2>"$call/err"; rc=$?
  judge "$call" "start $src, строка ${BASH_LINENO[0]} ${BASH_LINENO[1]:-}" "$compare" "$rc"
  rm -rf "$call"
  return $rc
}
told()  { cat "$work/told" 2>/dev/null; }
heard() { cat "$work/heard" 2>/dev/null; }
model_of() { python3 -I -c 'import json,sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except ValueError:
    data = None
    print(raw, end="")
hook = data.get("hookSpecificOutput") if isinstance(data, dict) else None
print(hook.get("additionalContext", "") if isinstance(hook, dict) else "", end="")'; }
shape_of() { python3 -I -c 'import json,sys
try:
    data = json.loads(sys.stdin.read())
    print("model=%d user=%d" % ("hookSpecificOutput" in data, "systemMessage" in data))
except Exception as error:
    print("не JSON: %s" % error)'; }
told_no_anchor='Hats handoff: no anchor saved in this Claude process'
told_no_closed='Hats handoff: no notes from closed sessions in this folder'
save() { env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$1" --note "$2" --topic "$3" 2>&1; }
check() { env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$1" 2>&1; }
checkline() { printf '%s\n' "$1" >"$proj/n.md"; check "$proj/n.md"; }
has()   { case "$3" in *"$2"*) ok ;; *) bad "$1" "ждали «$2», получили: ${3:0:300}" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "не ждали «$2», получили: ${3:0:300}" ;; *) ok ;; esac; }
empty() { if [ -z "$2" ]; then ok; else bad "$1" "ждали тишину, получили: ${2:0:300}"; fi; }
same()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "ждали «$2», получили «${3:0:400}»"; fi; }
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }
count() { printf '%s\n' "$2" | grep -c -- "$1"; }

# --- хук старта: после /clear
reset; mine
out=$(start clear); has "clear: своя отметка подгружает записку" "continues the note \"задача А\"" "$out"
same "clear: пользователю — какой якорь взят и где его записка" "Hats handoff: continuing anchor \"задача А\" — $real_note" "$(told)"
has "clear: печатается «СЕЙЧАС»" "строка сейчас" "$out"
lacks "clear: следующий раздел не печатается" "строка прошлого" "$out"
reset; printf '# T\n\n## Контекст\n\nстрока контекста\n\n## СЕЙЧАС\n\nстрока сейчас\n\n## Старое\n\nстарое\n' >"$note"; mine
out=$(start clear); has "clear: «СЕЙЧАС» ищется по имени" "строка сейчас" "$out"
lacks "clear: «Контекст» не печатается" "строка контекста" "$out"; lacks "clear: раздел после «СЕЙЧАС» не печатается" "старое" "$out"
reset; marker a 4242 "Tue Nov 10 10:00:00 2026" "$proj" "$note" "задача А"
empty "clear: тот же номер, другое время запуска — модели ничего" "$(start clear)"; same "clear: тот же номер, другое время запуска — пользователю «нет якоря»" "$told_no_anchor" "$(told)"
reset; marker a "$me_pid" "$me_started" "$proj" "$note" "чужая живая"
empty "clear: отметка другой живой сессии в той же папке — модели ничего" "$(start clear)"; same "clear: отметка другой живой сессии — пользователю «нет якоря»" "$told_no_anchor" "$(told)"
reset; empty "clear: отметок нет — модели ничего" "$(start clear)"; same "clear: отметок нет — пользователю «нет якоря»" "$told_no_anchor" "$(told)"
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
sid=n2; empty "передача: следующая сессия без нового сохранения — модели ничего" "$(start clear)"
same "передача: следующая сессия — пользователю, кому отдан якорь" "Hats handoff: anchor \"задача А\" was already given to session n1" "$(told)"
if [ -f "$markers/a.json" ]; then ok; else bad "передача: после молчания отметка цела" "пропала"; fi
marker a 4242 "$own_started" "$proj" "$note" "задача Б" "$t2"
sid=n2; has "передача: новое сохранение снова отдаёт записку" "continues the note \"задача Б\"" "$(start clear)"
sid=n3; empty "передача: и после него следующая сессия — модели ничего" "$(start clear)"
same "передача: и после него — пользователю, кому отдан новый якорь" "Hats handoff: anchor \"задача Б\" was already given to session n2" "$(told)"
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
sid=n1; start clear >/dev/null
handed_form=$(python3 -I -c 'import glob,json,os,sys
handed_path, = glob.glob(os.path.join(sys.argv[1], "*.handed"))
handed = json.load(open(handed_path, encoding="utf-8"))
marker = json.load(open(handed_path[:-len(".handed")] + ".json", encoding="utf-8"))
want = {"key": "%s|%s" % (marker["saved_at"], marker["note"]), "session": "n1"}
print("ok" if handed == want else "%r != %r" % (handed, want))' "$markers" 2>&1)
same "передача через save: файл передачи — ровно ключ «saved_at|note» из файла отметки и номер сессии, их сверяет мод" "ok" "$handed_form"
sid=n2; empty "передача через save: вторая сессия — модели ничего" "$(start clear)"
same "передача через save: вторая сессия — пользователю, кому отдан якорь" "Hats handoff: anchor \"задача А\" was already given to session n1" "$(told)"
sleep 1; save "$proj" "$note" "задача Б" >/dev/null
has "передача через save: новое сохранение отдаёт снова" "continues the note \"задача Б\"" "$(start clear)"

# --- хук старта: новая сессия
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
out=$(start startup); has "startup: закрытая сессия в списке" "\"закрытая\"" "$out"
same "startup: пользователю — сколько записок и какие" "Hats handoff: 1 note from closed sessions in this folder:
1. \"закрытая\" — $real_note" "$(told)"
has "startup: не задерживает просьбу пользователя" "Do not hold up the user's request" "$out"
has "startup: упомянуть записки одной строкой на языке пользователя" "in one short line, in the user's language" "$out"
has "startup: продолжать записку — только по выбору пользователя" "Continue a note only if the user picks it" "$out"
lacks "startup: больше не велит сначала спрашивать" "не начинай работу" "$out"
reset; marker a "$me_pid" "$me_started" "$proj" "$note" "живая"
empty "startup: живая сессия в той же папке не предлагается — модели ничего" "$(start startup)"; same "startup: живая сессия — пользователю «закрытых нет»" "$told_no_closed" "$(told)"
reset; marker a "$dead_pid" "$dead_started" "$other" "$note" "закрытая"
empty "startup: закрытая сессия другой папки — модели ничего" "$(start startup)"; same "startup: закрытая другой папки — пользователю «закрытых нет»" "$told_no_closed" "$(told)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$mem/gone.md" "без файла"
empty "startup: записки нет на диске — модели ничего" "$(start startup)"; same "startup: записки нет на диске — пользователю «закрытых нет»" "$told_no_closed" "$(told)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "старая" "2020-01-01T00:00:00Z"
empty "startup: отметка старше 30 дней — модели ничего" "$(start startup)"; same "startup: старше 30 дней — пользователю «закрытых нет»" "$told_no_closed" "$(told)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "первая" "2026-11-01T10:00:00Z"
marker b 99989 "$dead_started" "$proj" "$note" "вторая"
out=$(start startup); has "startup: две закрытые — обе в списке (1)" "\"первая\"" "$out"; has "startup: две закрытые — обе в списке (2)" "\"вторая\"" "$out"
reset; for i in 1 2 3 4 5 6 7; do marker "m$i" $((99980 + i)) "$dead_started" "$proj" "$note" "тема $i"; done
out=$(start startup); n=$(count '^[0-9]\. "' "$out")
if [ "$n" -eq 5 ]; then ok; else bad "startup: в списке не больше пяти" "строк $n"; fi
seven=$(told | python3 -I -c 'import re,sys
lines = sys.stdin.read().split("\n")
print("head=%s items=%d tail=%s" % (lines[0], sum(bool(re.fullmatch(r"[1-5]\. \"тема \d\" — /.+", line)) for line in lines), lines[-1]))')
same "startup: пользователю — найдено семь, показаны пять, две счётом" "head=Hats handoff: 7 notes from closed sessions in this folder: items=5 tail=and 2 more" "$seven"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
start startup >/dev/null
if [ -f "$markers/a.json" ]; then ok; else bad "хук не стирает отметку" "файл пропал"; fi

# --- путь записки
reset; printf 'API_TOKEN=secret\n' >"$proj/.env"; marker a "$dead_pid" "$dead_started" "$proj" "$proj/.env" "секрет"
empty "startup: записка вне памяти Claude не показывается — модели ничего" "$(start startup)"; same "startup: записка вне памяти — пользователю «закрытых нет»" "$told_no_closed" "$(told)"
reset; mine a "$proj" "$proj/.env"; printf 'API_TOKEN=secret\n' >"$proj/.env"
empty "clear: записка вне памяти Claude не печатается — модели ничего" "$(start clear)"; same "clear: записка вне памяти — пользователю «нет якоря»" "$told_no_anchor" "$(told)"
reset; printf 'x\n' >"$proj/note.md"; out=$(save "$proj" "$proj/note.md" "задача А"); rc=$?
has "save: записка вне памяти — отказ" "the note must be a file" "$out"
if [ $rc -ne 0 ] && [ -z "$(ls "$markers")" ]; then ok; else bad "save: вне памяти — код не 0 и без отметки" "rc=$rc $(ls "$markers")"; fi

# --- хук старта: прочие причины и ввод
reset; mine
start compact >/dev/null; empty "compact — молчит" "$(heard)"
start resume >/dev/null; empty "resume — молчит" "$(heard)"
start clear "$proj" HANDOFF_OFF=1 >/dev/null; empty "выключатель HANDOFF_OFF=1" "$(heard)"
out=$(printf 'not json' | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1); rc=$?
empty "битый ввод — тишина" "$out"
if [ $rc -eq 0 ]; then ok; else bad "битый ввод — код 0" "код $rc"; fi
empty "подмена процесса без HANDOFF_TEST не действует — модели ничего" "$(printf '{"cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1 | model_of)"

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
upper_mem="${mem%/memory}/MEMORY"
printf 'x\n' >"$mem/upper.md"; out=$(save "$proj" "$upper_mem/upper.md" "задача А"); rc=$?
has "save: записка по пути памяти в другом регистре букв — отказ, как до правки цитат" "the note must be a file" "$out"
if [ $rc -eq 1 ] && [ -z "$(ls "$markers" | grep '\.json$')" ]; then ok; else bad "save: путь памяти в другом регистре — код 1 и без отметки" "rc=$rc $(ls "$markers")"; fi
if [ -e "$upper_mem/note.md" ]; then
  has "цитата на память Claude в другом регистре букв — не источник" "Claude's memory" "$(checkline "итог (цит. $upper_mem/note.md:1 «правила — 73%»)")"
  printf 'x (цит. %s:1 «x»)\n' "$upper_mem/n2.md" >"$mem/n2.md"
  has "цитата на саму записку в другом регистре букв — не источник" "the note itself" "$(env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$mem/n2.md" 2>&1)"
else
  skipped=$((skipped+2)); skips="$skips
  пропущено 2: файловая система различает регистр букв — цитаты памяти и записки в другом регистре не проверены"
fi
mkfifo "$proj/pipe"; printf 'итог (цит. %s:1 «x»)\n' "$proj/pipe" >"$proj/n.md"
out=$(timeout 5 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
has "цитата на канал не вешает проверку" "no regular file" "$out"; lacks "цитата на канал — не убита по сроку" "rc=124" "$out"
python3 -I -c 'print("(цит. a:1 «" * 1300)' >"$proj/n.md"
out=$(timeout 2 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
lacks "длинная строка с цитатами разбирается быстро" "rc=124" "$out"
has "длинная строка с цитатами — ответ проверки, а не падение" "line longer than 5,000 characters" "$out"
python3 -I -c 'print("(цит. a:1 «" * 450)' >"$proj/n.md"
out=$(timeout 2 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
has "строка короче предела из незакрытых цитат разбирается быстро и ответом проверки" "quote not parsed" "$out"
has "случай пробы: процент без источника" "no source" "$(checkline '73% потерь — постоянные правила')"
has "случай пробы в обратных кавычках" "no source" "$(checkline '`73%` — постоянные правила')"
has "своя арифметика сходится" "all verified" "$(checkline 'правила — 13 из 30 (43%)')"
has "своя арифметика не сходится" "arithmetic" "$(checkline 'правила — 22 из 30 (43%)')"
has "число с командой-источником" "all verified" "$(checkline 'неделя 98% (система: cat weekly.json)')"
has "команда-источник освобождает только свою часть" "no source" "$(checkline 'правила 73%; неделя 98% (система: cat x)')"
has "команда-источник не отменяет арифметику" "arithmetic" "$(checkline 'правила — 22 из 30 (43%) (система: wc -l x)')"
has "числа в блоке кода не проверяются" "none outside code and the header — nothing checked" "$(printf '```\n41%%\n```\n' >"$proj/n.md"; check "$proj/n.md")"
has "незакрытый блок кода — замечание, а не тишина" "line 1: code block not closed" "$(printf '```\nправила 73%%\n' >"$proj/n.md"; check "$proj/n.md")"
out=$({ for i in $(seq 1 12); do echo "строка $i: $i%"; done; printf '```\nправила 73%%\n'; } >"$proj/n.md"; check "$proj/n.md")
same "незакрытый блок кода — первое замечание, даже когда замечаний больше десяти" "- line 13: code block not closed — the lines after it were not checked" "$(printf '%s\n' "$out" | grep -m1 '^- line')"
has "незакрытый блок кода не уходит в счёт «and N more»" "and 3 more" "$out"
has "числа в блоке ~~~ не проверяются" "none outside code and the header — nothing checked" "$(printf '~~~\nправила 73%%\n~~~\n' >"$proj/n.md"; check "$proj/n.md")"
has "блок из четырёх кавычек закрывается только четырьмя" "none outside code and the header — nothing checked" "$(printf '````\n```\nправила 73%%\n````\n' >"$proj/n.md"; check "$proj/n.md")"
has "после закрытого блока числа снова проверяются" "line 4: number with no quote" "$(printf '~~~\n41%%\n~~~\nправила 73%%\n' >"$proj/n.md"; check "$proj/n.md")"
has "шапка записки не проверяется" "none outside code and the header — nothing checked" "$(printf -- '---\nname: x 50%%\n---\nтекст\n' >"$proj/n.md"; check "$proj/n.md")"
out=$(: >"$proj/n.md"; check "$proj/n.md"); rc=$?
has "пустой файл: проверять нечего — так и сказано" "quotes and numbers: none outside code and the header — nothing checked" "$out"
lacks "пустой файл: не «all verified»" "all verified" "$out"
if [ $rc -eq 0 ]; then ok; else bad "пустой файл: check — код 0" "rc=$rc"; fi
out=$(printf -- '---\nname: x 50%%\n---\n' >"$proj/n.md"; check "$proj/n.md"); rc=$?
has "только шапка: проверять нечего" "none outside code and the header — nothing checked" "$out"; lacks "только шапка: не «all verified»" "all verified" "$out"
if [ $rc -eq 0 ]; then ok; else bad "только шапка: check — код 0" "rc=$rc"; fi
lacks "числа только в блоке кода: не «all verified»" "all verified" "$(printf '```\n41%%\n```\n' >"$proj/n.md"; check "$proj/n.md")"
lacks "текст без чисел: не «all verified»" "all verified" "$(checkline 'просто текст')"
has "одна цитата — уже «all verified»" "quotes and numbers: all verified" "$(printf 'a 73%%\n' >"$proj/src5.md"; checkline "x (cite: $proj/src5.md:1 \"a 73%\")")"
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
mkdir -p "$work/repo2"; git -C "$work/repo2" init -q
git -C "$work/repo2" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit -q --allow-empty -m other
printf '## СЕЙЧАС\n\n- git %s %s = %s\n' "$work/repo" "$branch" "$second" >"$note"
out=$(CMP=0 start clear "$proj" GIT_DIR="$work/repo2/.git" GIT_WORK_TREE="$work/repo2")
has "GIT_DIR и GIT_WORK_TREE окружения не уводят сверку в другой репозиторий" "= $second: matches" "$out"
git -C "$work/repo" update-ref refs/remotes/upstream/main "$second"
printf '## СЕЙЧАС\n\n- git %s upstream/main = %s\n' "$work/repo" "$second" >"$note"
out=$(CMP=0 start clear); has "upstream/main — тоже локальная ссылка без fetch" "upstream/main = $second: matches (local ref, no fetch)" "$out"
has "upstream/main — подсказка про fetch не только об origin" "Remote refs were compared with local refs" "$out"
git -C "$work/repo" branch -q feature/x "$second"
printf '## СЕЙЧАС\n\n- git %s feature/x = %s\n' "$work/repo" "$second" >"$note"
out=$(start clear); has "локальная ветка с косой чертой сверяется" "feature/x = $second: matches" "$out"; lacks "локальная ветка с косой чертой — без пометки fetch" "no fetch" "$out"
real_git=$(command -v git); mkdir -p "$work/slowkind"
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = --symbolic-full-name ] && exec sleep 5; done\nexec "%s" "$@"\n' "$real_git" >"$work/slowkind/git"; chmod +x "$work/slowkind/git"
printf '## СЕЙЧАС\n\n- git %s feature/x = %s\n' "$work/repo" "$second" >"$note"
out=$(CMP=0 start clear "$proj" PATH="$work/slowkind:$PATH")
has "вид ссылки не узнан за срок — пометка fetch остаётся" "feature/x = $second: matches (local ref, no fetch)" "$out"
printf '## СЕЙЧАС\n\n- git %s -x = %s\n' "$work/repo" "$second" >"$note"
lacks "ссылка с минусом не разбирается как факт" "matches" "$(start clear)"
printf '## СЕЙЧАС\n\n- git %s %s = %s\n' "$work/repo" "$branch" "$second" >"$note"
has "срок вышел — факт состояния «не успел проверить»" "no time to check" "$(CMP=0 start clear "$proj" HANDOFF_TEST_BUDGET=0)"
{ printf '## СЕЙЧАС\n\n'; for i in 1 2 3 4 5 6; do printf -- '- git %s %s = %s\n' "$work/repo" "$branch" "$second"; done; } >"$note"
has "фактов не больше четырёх" "more than four" "$(start clear)"
printf '## СЕЙЧАС\n\nпроцент 50%%\n' >"$note"
has "непроверенная строка приходит с пометкой" "Not verified" "$(start clear)"

# --- пределы вывода
reset; python3 -I -c 'import sys; print("## СЕЙЧАС\n"); print("\n".join("слово " * 20 for _ in range(200)))' >"$note"; mine
has "длинная «СЕЙЧАС» обрезается" "cut, the rest is in the file" "$(start clear)"
python3 -I -c 'import sys; p=sys.argv[1]; print("## СЕЙЧАС\n"); print("\n".join("слово " * 20 for _ in range(200))); print("\n".join("x (цит. /%s/%d.md:1 «%s»)" % ("d" * 250, i, "q" * 80) for i in range(12)))' "$work" >"$note"
out=$(CMP=0 start clear); len=$(printf '%s' "$out" | python3 -I -c 'import sys; print(len(sys.stdin.read()))')
if [ "$len" -le 9501 ]; then ok; else bad "вывод не длиннее 9 500 знаков" "$len"; fi

# --- сохранение
reset; out=$(save "$proj" "$note" "задача А")
has "save: отметка записана" "marker:" "$out"
if printf '%s\n' "$out" | python3 -I -c 'import re,sys; m=re.escape(sys.argv[1]); lines=sys.stdin.read().splitlines()
sys.exit(0 if lines and re.fullmatch("marker: " + m + r"/[0-9]+-[^/]+\.json", lines[0]) else 1)' "$markers"; then ok
else bad "save: первая строка — ровно «marker: <config>/state/handoff/<pid>-<время>.json», её читает мод" "${out:0:300}"; fi
if python3 -I -c 'import json,re,sys; m=json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", m["saved_at"]) else 1)' \
  "$markers/4242-Mon-Nov-9-10-00-00-2026.json" 2>/dev/null; then ok
else bad "save: saved_at отметки — YYYY-MM-DDTHH:MM:SSZ, его читает мод" "$(cat "$markers"/*.json 2>&1 | head -5)"; fi
if python3 -I -c 'import hashlib,json,sys; m=json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if m.get("sha256") == hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest() else 1)' \
  "$markers/4242-Mon-Nov-9-10-00-00-2026.json" "$note" 2>/dev/null; then ok
else bad "save: sha256 отметки — sha256 байтов записки, его сверяет мод" "$(cat "$markers"/*.json 2>&1 | head -8)"; fi
out=$(python3 -I - "$HOOK_SOURCE" "$plugin_root/tests/mod/thresholds.test.ts" <<'PYEOF' 2>&1
import importlib.util
import re
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("handoff_under_test", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = open(sys.argv[2], encoding="utf-8").read()
table = re.findall(r"\{ line: '((?:[^'\\]|\\.)*)', isHeading: (true|false) \}", source)
if len(table) < 20:
    sys.exit(f"the heading table of the mod has {len(table)} rows")
wrong = [line for line, flag in table if bool(module.NOW_HEADING.match(line.replace("\\r", "\r"))) != (flag == "true")]
print("disagree: " + repr(wrong) if wrong else f"agree: {len(table)}")
PYEOF
)
case "$out" in "agree: "*) ok ;; *) bad "NOW_HEADING handoff.py и таблица заголовков мода совпадают" "${out:0:300}" ;; esac
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
reset; printf 'x\n' >"$mem/other.md"
marker old "$dead_pid" "$dead_started" "$other" "$mem/other.md" "старая закрытая" "2020-01-01T00:00:00Z"
marker oldlive "$me_pid" "$me_started" "$other" "$mem/other.md" "старая живая" "2020-01-01T00:00:00Z"
marker fresh 99996 "$dead_started" "$other" "$mem/other.md" "свежая закрытая"
printf '{}' >"$markers/old.handed"; printf '{}' >"$markers/oldlive.handed"; printf '{}' >"$markers/fresh.handed"
out=$(save "$proj" "$note" "задача А")
if [ ! -f "$markers/old.json" ] && [ ! -f "$markers/old.handed" ]; then ok; else bad "save: снимает закрытую старше 30 дней с её файлом передачи" "$(ls "$markers")"; fi
has "save: говорит, сколько старых снято" "saved more than 30 days ago or at an unreadable time: 1" "$out"
if [ -f "$markers/oldlive.json" ] && [ -f "$markers/oldlive.handed" ]; then ok; else bad "save: старую живую не трогает" "$(ls "$markers")"; fi
if [ -f "$markers/fresh.json" ] && [ -f "$markers/fresh.handed" ]; then ok; else bad "save: свежую закрытую с другой запиской не трогает" "$(ls "$markers")"; fi
reset; printf 'x\n' >"$mem/other.md"
marker garbled "$dead_pid" "$dead_started" "$other" "$mem/other.md" "время не разобрать" "вчера"
printf '{}' >"$markers/garbled.handed"
save "$proj" "$note" "задача А" >/dev/null
if [ ! -f "$markers/garbled.json" ] && [ ! -f "$markers/garbled.handed" ]; then ok; else bad "save: закрытую с неразборным saved_at снимает, как старую" "$(ls "$markers")"; fi
reset; printf '73%% без источника\n' >"$note"
has "save: сообщает непроверенное" "not verified in the note" "$(save "$proj" "$note" "задача А")"
reset; out=$(cd "$work/loose" && env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" CLAUDE_CONFIG_DIR=rel/cfg python3 -I "$HOOK" save --cwd "$proj" --note "$note" --topic t 2>&1)
has "save: относительный CLAUDE_CONFIG_DIR — берётся ~/.claude" "marker: $markers/" "$out"
if [ ! -e "$work/loose/rel" ]; then ok; else bad "save: относительный CLAUDE_CONFIG_DIR — папки от текущей нет" "$(ls -R "$work/loose/rel" | head -5)"; fi
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
has "длинные строки цифр — ответ проверки, а не падение" "quotes and numbers: none outside code and the header — nothing checked" "$out"
python3 -I -c 'print("1" * 1500000)' >"$proj/big.txt"
python3 -I -c 'import sys; print(" ".join("(цит. %s:1 «1»)" % sys.argv[1] for _ in range(30)))' "$proj/big.txt" >"$proj/n.md"
out=$(timeout 3 env HOME="$work" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1; echo "rc=$?")
lacks "тридцать цитат в большой файл — быстро" "rc=124" "$out"
has "тридцать цитат в большой файл — ответ проверки, а не падение" "big.txt:1: \"1\"" "$out"

# --- медленные ps и git, уборка процессов
reset; mkdir -p "$work/fakebin" "$work/repo"
printf '#!/bin/bash\nsleep 10\n' >"$work/fakebin/ps"; chmod +x "$work/fakebin/ps"
marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"; marker b 99989 "$dead_started" "$proj" "$note" "вторая"; marker c 99988 "$dead_started" "$proj" "$note" "третья"
s=$(date +%s); out=$(CMP=0 start startup "$proj" PATH="$work/fakebin:$PATH"); e=$(date +%s)
empty "ps молчит — закрытые не показываются модели" "$out"
same "ps молчит — пользователю «не успел проверить», а не «записок нет»" "Hats handoff: could not check 3 notes in time, none listed" "$(told)"
if [ $((e - s)) -le 5 ]; then ok; else bad "ps молчит — хук укладывается в 5 с" "$((e - s)) с"; fi
env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" PATH="$work/fakebin:$PATH" python3 -I "$HOOK" save --cwd "$proj" --note "$note" --topic t >/dev/null 2>&1
if [ -f "$markers/a.json" ]; then ok; else bad "ps молчит — save не снимает отметку" "снята"; fi
printf '{"cwd":"%s","source":"startup"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_BUDGET=1 PATH="$work/fakebin:$PATH" python3 -I "$HOOK" start >/dev/null 2>&1
ms=$(python3 -I -c 'import json,sys; print(json.loads(open(sys.argv[1]).read().splitlines()[-1]).get("ms", "нет"))' "$markers/runs.log" 2>&1)
case "$ms" in ''|*[!0-9]*) bad "ps молчит — время хука из runs.log" "ms=$ms" ;; *) if [ "$ms" -le 1700 ]; then ok; else bad "ps молчит — общий срок на все вызовы ps (время хука из runs.log)" "${ms} мс при сроке 1000"; fi ;; esac
reset; marker good "$dead_pid" "$dead_started" "$proj" "$note" "живая записка"
python3 -I -c 'import json,sys; json.dump({"pid":99987,"started":"x","cwd":"/a\u0000b","note":sys.argv[2],"topic":"t","saved_at":sys.argv[3]},open(sys.argv[1],"w"))' "$markers/nul.json" "$note" "$(now)"
has "отметка с нулевым байтом в папке не глушит список" "\"живая записка\"" "$(start startup)"
reset; mkdir -p "$work/fakebin" "$work/repo"
printf '#!/bin/bash\nsh -c '"'"'echo $$ >"%s/childpid"; exec sleep 30'"'"' &\nsleep 30\n' "$work" >"$work/fakebin/git"; chmod +x "$work/fakebin/git"
printf '## СЕЙЧАС\n\n- git %s main = abcdef1\n' "$work/repo" >"$note"; mine
out=$(CMP=0 start clear "$proj" PATH="$work/fakebin:$PATH" HANDOFF_TEST_BUDGET=2)
has "медленный git — «не успел проверить»" "no time to check" "$out"
sleep 0.5; child=$(cat "$work/childpid" 2>/dev/null)
if [ -n "$child" ] && ! kill -0 "$child" 2>/dev/null; then ok; else bad "после срока дочерних процессов git не остаётся" "pid ${child:-нет} жив"; kill "$child" 2>/dev/null; fi

# --- предел вывода в единицах UTF-16
reset; python3 -I -c 'print("## СЕЙЧАС\n"); print("\n".join("😀" * 60 for _ in range(110)))' >"$note"; mine
units=$(CMP=0 start clear | python3 -I -c 'import sys; print(len(sys.stdin.read().encode("utf-16-le")) // 2)')
if [ "$units" -le 9501 ]; then ok; else bad "вывод не длиннее 9 500 единиц UTF-16" "$units"; fi

# --- настоящий поиск процесса claude по предкам (без подмены), глубина 2 и папка из lsof
reset; mkdir -p "$work/bin"; ln -s /bin/bash "$work/bin/claude"
printf '{"session_id":"s","cwd":"%s","source":"clear"}' "$other" >"$work/in.json"
out=$( (cd "$proj" && env HOME="$work" "$work/bin/claude" -c 'echo $$ >"$1/fakepid"; bash -c "python3 -I \"\$0\" save --note \"\$1\" --topic реальный >/dev/null; true" "$2" "$3"; python3 -I "$2" start <"$1/in.json"; true' _ "$work" "$HOOK" "$note") 2>&1)
has "настоящий поиск: после /clear своя записка" "continues the note \"реальный\"" "$(printf '%s' "$out" | model_of)"
fake=$(cat "$work/fakepid" 2>/dev/null)
fields=$(python3 -I -c 'import json,glob,sys; m=json.load(open(glob.glob(sys.argv[1]+"/*.json")[0])); print(m["pid"], m["cwd"], "|", m["started"])' "$markers" 2>/dev/null)
real_proj=$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$proj")
case "$fields" in "$fake $real_proj | "*" 20"[0-9][0-9]) ok ;; *) bad "настоящий поиск: отметка на процесс claude через два уровня, папка из lsof" "ждали «${fake} ${real_proj} | …», получили «${fields}»" ;; esac

# --- журнал запусков: каждый выход хука старта оставляет строку с решением
trace="$markers/runs.log"
tl() { python3 -I -c 'import json,sys; d=json.loads(open(sys.argv[1]).read().splitlines()[-1]); print(" ".join(f"{k}={d.get(k)}" for k in sys.argv[2:]))' "$trace" "$@" 2>&1; }
tlines() { if [ -f "$trace" ]; then grep -c . "$trace"; else echo 0; fi; }
# --- записка своей отметки пропала: свой исход и своя строка, а не «нет якоря»
reset; mine; rm "$note"
empty "записка удалена: модели ничего" "$(start clear)"
same "записка удалена: пользователю — якорь не отдан, записки нет" "Hats handoff: anchor \"задача А\" not given — its note is gone: $note" "$(told)"
has "записка удалена: журнал называет исход" "outcome=note-gone pid=4242" "$(tl outcome pid)"
reset; mine; mv "$note" "$mem/renamed.md"
empty "записка переименована: модели ничего" "$(start clear)"
same "записка переименована: пользователю — якорь не отдан, записки нет" "Hats handoff: anchor \"задача А\" not given — its note is gone: $note" "$(told)"
has "записка переименована: журнал называет исход" "outcome=note-gone" "$(tl outcome)"
reset; marker a 4242 "Tue Nov 10 10:00:00 2026" "$proj" "$mem/nope.md" "чужой запуск"
start clear >/dev/null; same "записки нет у отметки другого запуска — «нет якоря»" "$told_no_anchor" "$(told)"
has "записки нет у отметки другого запуска — журнал no-own-marker" "outcome=no-own-marker" "$(tl outcome)"
if [ "$(id -u)" -ne 0 ]; then
  reset; mine; chmod 000 "$mem"
  start clear >/dev/null; got_told=$(told); got_outcome=$(tl outcome)
  chmod 700 "$mem"
  lacks "папку записки не открыть — это не «записка пропала»" "its note is gone" "$got_told"
  same "папку записки не открыть — журнал no-own-marker" "outcome=no-own-marker" "$got_outcome"
fi
reset; mine; sid=n1; start clear >/dev/null
has "журнал: отдал записку новой сессии" "outcome=gave-note receiver=new session=n1 source=clear pid=4242" "$(tl outcome receiver session source pid)"
start clear >/dev/null
has "журнал: та же сессия получила снова" "outcome=gave-note receiver=same" "$(tl outcome receiver)"
sid=n2; empty "журнал: случай «отдано другой» — модели ничего" "$(start clear)"
same "журнал: случай «отдано другой» — пользователю, кому" "Hats handoff: anchor \"задача А\" was already given to session n1" "$(told)"
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
same "процесс claude не найден — пользователю так и сказано" "Hats handoff: could not identify this Claude process, no anchor given" "$(told)"
reset; mine; start clear "$proj" HANDOFF_PROCESS="x:y" >/dev/null; rc=$?
has "журнал: падение записано с типом" "outcome=error error=ValueError" "$(tl outcome error)"
same "падение до печати — пользователю тип и путь журнала" "Hats handoff: failed (ValueError), see $markers/runs.log" "$(told)"
has "журнал: у падения есть его текст" "message=invalid literal for int() with base 10: 'x'" "$(tl message)"
if [ $rc -eq 0 ]; then ok; else bad "журнал: падение — код 0" "код $rc"; fi
reset; mine; start clear "$proj" HANDOFF_OFF=1 >/dev/null
has "журнал: выключатель" "outcome=off" "$(tl outcome)"
reset; printf 'not json' | env HOME="$work" python3 -I "$HOOK" start >/dev/null 2>&1
has "журнал: битый ввод" "outcome=bad-input" "$(tl outcome)"
reset; python3 -I -c 'print("[" * 100000)' | env HOME="$work" python3 -I -c 'import json, json.scanner, runpy, sys
json.scanner.make_scanner = json.scanner.py_make_scanner
json._default_decoder = json.JSONDecoder()
sys.argv = [sys.argv[1], "start"]
runpy.run_path(sys.argv[0], run_name="__main__")' "$HOOK" >/dev/null 2>&1
has "журнал: глубоко вложенный ввод (RecursionError разбора) — тот же битый ввод" "outcome=bad-input" "$(tl outcome)"
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
reset; for i in $(seq 1 30); do (sid=p$i; CMP=0 start startup >/dev/null) & done; wait
has "одновременно: 30 запусков — 30 целых строк" "distinct=30 total=30 bad=0" "$(sessions_in)"
reset; python3 -I -c 'import sys; open(sys.argv[1],"w").write("OLDTAG " + "x" * 300000 + "\n")' "$trace"
for i in 1 2; do (sid=r$i; CMP=0 start startup "$proj" HANDOFF_TEST_PAUSE=0.2 >/dev/null) & done; wait
has "одновременно: двойная перекладка не стирает историю и строки" "distinct=2 total=2 bad=0 old=1" "$(sessions_in)"
reset; python3 -I -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(4)' "$markers/runs.lock" "$work/locked" &
holder=$!; for _ in $(seq 1 100); do [ -f "$work/locked" ] && break; sleep 0.05; done
s=$(date +%s); sid=w1; CMP=0 start startup >/dev/null; e=$(date +%s); kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
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
left=$(ls -A "$markers" | grep -c '\.tmp$'); if [ "$left" -eq 0 ]; then ok; else bad "save: отметку не записать — временный файл убран" "$left"; fi
reset; printf '{"session_id":"u1","cwd":"/a\\udc80b","source":"startup"}' | env HOME="$work" python3 -I "$HOOK" start >/dev/null 2>&1
has "журнал: путь с непарным суррогатом — строка всё равно записана" "distinct=1 total=1 bad=0" "$(sessions_in)"
reset; mkdir -p "$markers/runs.lock"; sid=w2; start startup >/dev/null
has "блокировку не открыть: строка всё равно записана" "distinct=1 total=1" "$(sessions_in)"
reset; for i in $(seq 1 20); do HANDOFF_TEST_PAUSE=0.2 save "$proj" "$note" "задача $i" >"$work/save$i.out" & done; wait
failed=$(grep -L "marker:" "$work"/save*.out | wc -l | tr -d ' ')
if [ "$failed" -eq 0 ]; then ok; else bad "одновременно: 20 сохранений — все записали отметку" "не записали $failed: $(cat $(grep -L "marker:" "$work"/save*.out | head -1) | head -c 300)"; fi
if python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$markers/4242-Mon-Nov-9-10-00-00-2026.json" 2>/dev/null; then ok; else bad "одновременно: отметка целая" "битая"; fi
left=$(ls -A "$markers" | grep -c '\.tmp$'); if [ "$left" -eq 0 ]; then ok; else bad "одновременно: временных файлов не осталось" "$left"; fi

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
left=$(ls -A "$markers" | grep -c '\.tmp$'); if [ "$left" -eq 0 ]; then ok; else bad "тема с байтом не из UTF-8: временный файл убран" "$left"; fi
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "хорошая"
python3 -I -c 'import sys; open(sys.argv[1], "w").write("[" * 200000 + "]" * 200000)' "$markers/deep.json"
has "отметка с глубокой вложенностью не прячет список" "\"хорошая\"" "$(start startup)"
out=$(save "$proj" "$note" "задача А"); lacks "отметка с глубокой вложенностью: save без трассировки" "Traceback" "$out"
reset; rm -rf "$work/.claude/state"
out=$(save "$proj" "$note" "задача А"); rc=$?
if [ $rc -eq 0 ] && [ -f "$markers/4242-Mon-Nov-9-10-00-00-2026.json" ]; then ok; else bad "первое сохранение: каталога состояния нет — создаётся, отметка записана" "rc=$rc ${out:0:200}"; fi

# --- запуск без человека (claude -p): списка нет, своя записка после /clear — как раньше
nobody() {  # nobody <source> <ATTENDED или -> <ENTRYPOINT или -> — stdout, за ним stderr, как есть; сверка — как у start
  local a=() call rc compare=0; [ "$2" = "-" ] && a+=(-u CLAUDE_CODE_SESSION_ATTENDED) || a+=(CLAUDE_CODE_SESSION_ATTENDED="$2")
  [ "$3" = "-" ] || a+=(CLAUDE_CODE_ENTRYPOINT="$3")
  call=$(open_call "$(printf '{"session_id":"%s","cwd":"%s","source":"%s"}' "$sid" "$proj" "$1")")
  run_reference "$call" "${a[@]}" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" && compare=1
  env "${a[@]}" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start <"$call/in" >"$call/out" 2>"$call/err"; rc=$?
  judge "$call" "nobody $1 $2 $3, строка ${BASH_LINENO[0]}" "$compare" "$rc" >/dev/null
  cat "$call/out" "$call/err"; rm -rf "$call"
  return $rc
}
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
empty "без человека: ATTENDED=0 — списка нет" "$(nobody startup 0 sdk-cli)"
has "без человека: в журнале unattended" "outcome=unattended source=startup" "$(tl outcome source)"
empty "без человека: ATTENDED=0 при entrypoint cli — списка нет" "$(nobody startup 0 cli)"
empty "без человека: ATTENDED нет, entrypoint sdk-cli — списка нет" "$(nobody startup - sdk-cli)"
empty "без человека: ATTENDED нет, entrypoint sdk-py — списка нет" "$(nobody startup - sdk-py)"
has "с человеком: ATTENDED нет, entrypoint cli — список есть" "\"закрытая\"" "$(nobody startup - cli | model_of)"
has "с человеком: ATTENDED и entrypoint нет — список есть" "\"закрытая\"" "$(nobody startup - - | model_of)"
has "с человеком: ATTENDED=1 при entrypoint sdk-ts — список есть" "\"закрытая\"" "$(nobody startup 1 sdk-ts | model_of)"
has "незнакомое значение ATTENDED — список показывается" "\"закрытая\"" "$(nobody startup true sdk-cli | model_of)"
has "с человеком: список — и строка пользователю" "model=1 user=1" "$(nobody startup - cli | shape_of)"
reset; mine
has "без человека: своя записка после /clear по-прежнему отдаётся" "continues the note" "$(nobody clear 0 sdk-cli)"
has "без человека: после /clear модели записка, пользователю ничего" "model=1 user=0" "$(nobody clear 0 sdk-cli | shape_of)"
reset; empty "без человека: /clear без своего якоря — тишина" "$(nobody clear 0 sdk-cli)"
reset; mine; out=$(printf '{"session_id":"s","cwd":"%s","source":"clear"}' "$proj" | env CLAUDE_CODE_SESSION_ATTENDED=0 HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="x:y" python3 -I "$HOOK" start 2>&1)
empty "без человека: падение после /clear — тишина" "$out"; has "без человека: падение после /clear — в журнале" "outcome=error error=ValueError" "$(tl outcome error)"
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
out=$(printf '{"session_id":"nofcntl","cwd":"%s","source":"startup"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I -c 'import sys; sys.modules["fcntl"] = None; path = sys.argv[1]; sys.argv = [path, "start"]; exec(compile(open(path).read(), path, "exec"), {"__name__": "__main__", "__file__": path})' "$HOOK" 2>&1)
has "нет fcntl (Windows): хук грузится и даёт список" "\"без fcntl\"" "$(printf '%s' "$out" | model_of)"
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
empty "своя папка: записки нет на диске — модели ничего" "$(start startup)"; same "своя папка: записки нет на диске — пользователю «закрытых нет»" "$told_no_closed" "$(told)"
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
  empty "/clear: отметка руками, ${case_%%|*} — модели ничего" "$(start clear)"; same "/clear: отметка руками, ${case_%%|*} — пользователю «нет якоря»" "$told_no_anchor" "$(told)"
done
rm -f "$markers"/*; mine a "$proj" "$own_dir/x.md" "своя"
has "/clear: рядом своя записка своей папки отдаётся" "legit line" "$(start clear)"
rm -rf "$markers"/*; marker good "$dead_pid" "$dead_started" "$proj" "$own_dir/x.md" "своя"
i=0; for case_ in "${bad_cases[@]}"; do i=$((i + 1)); marker "b$i" $((99970 + i)) "$dead_started" "$proj" "${case_#*|}" "мимо: ${case_%%|*}"; done
out=$(start startup); has "новая сессия: своя записка в списке" "\"своя\"" "$out"
lacks "новая сессия: отметки руками мимо своей папки не в списке" "мимо" "$out"; lacks "новая сессия: мимо своей папки — и не в строке пользователю" "мимо" "$(told)"

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
rm -f "$markers"/*.json
p=$(env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_PROC="$work/proc" python3 -I "$HOOK" new --slug t 2>&1)
if [ "$p" = "$dir/resume-t.md" ] && [ -f "$p" ]; then ok; else bad "new без --cwd и --memory: папка Hats проекта процесса Claude (/proc), а не оболочки" "«${p}»"; fi
printf '## NOW\n\nnew proc line\n' >"$p" 2>/dev/null
out=$(env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_PROC="$work/proc" python3 -I "$HOOK" save --note "$p" --topic proc 2>&1)
has "new и save без --cwd — одна папка: отметка записана" "marker:" "$out"
if [ "$(markerfield "$markers" note)" = "$(realp "$p")" ]; then ok; else bad "new и save без --cwd: в отметке записка из new" "$(markerfield "$markers" note)"; fi

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


# --- записки в памяти: new, индекс resume-index.md, строка MEMORY.md
index="$mem/resume-index.md"; memmd="$mem/MEMORY.md"
header_line='# Resume index — written by the Hats plugin; do not edit'
about_line='One line per saved session, newest first. A session may still be working on a task listed here: ask the user before continuing one.'
memory_line='- [Resume index](resume-index.md) — sessions saved for the next one; read it when the user asks to continue earlier work'
newnote() { env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" new --cwd "$proj" "$@" 2>&1; }
saveas() {  # saveas <номер процесса> <записка> <тема> [env...]
  local p="$1" n="$2" t="$3"; shift 3
  env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$p:$own_started" "$@" python3 -I "$HOOK" save --cwd "$proj" --note "$n" --topic "$t" 2>&1
}
entries() { if [ -f "$index" ]; then awk '/^- \[/{n++} END{print n+0}' "$index"; else echo 0; fi; }
resumes_in() { ls -A "$1" 2>/dev/null | grep -c '^resume-'; }
entry_at() { sed -n "${1}p" "$index"; }

reset; out=$(newnote --slug t --memory "$mem"); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "$mem/resume-t.md" ] && [ -f "$mem/resume-t.md" ] && [ ! -s "$mem/resume-t.md" ]; then ok
else bad "new: память — пустой resume-t.md, напечатан путь через D" "rc=$rc «${out}»"; fi
has "new: права записки — 600" "0o600" "$(mode_of "$mem/resume-t.md")"
if [ -z "$(ls -A "$work/Library" 2>/dev/null)" ]; then ok; else bad "new с памятью: папка Hats не заводится" "$(ls -A "$work/Library")"; fi
reset; ln -s "$work/.claude" "$work/cfglink"; out=$(newnote --slug t --memory "$work/cfglink/projects/-proj/memory"); rc=$?; rm -f "$work/cfglink"
if [ $rc -eq 0 ] && [ "$out" = "$work/cfglink/projects/-proj/memory/resume-t.md" ] && [ -f "$mem/resume-t.md" ]; then ok
else bad "new: D через ссылку — путь напечатан через D, как дан, а не настоящий" "rc=$rc «${out}»"; fi
reset; out=$(newnote --slug t); rc=$?; own_dir=$(notes_of "$proj")
if [ $rc -eq 0 ] && [ "$out" = "$own_dir/resume-t.md" ] && [ -f "$out" ] && [ "$(resumes_in "$mem")" -eq 0 ]; then ok
else bad "new без --memory: resume-t.md в папке Hats проекта" "rc=$rc «${out}»"; fi
has "new без --memory: папка проекта — права 700" "0o700" "$(mode_of "$own_dir")"

reset; printf 'чужая\n' >"$mem/resume-t.md"; out=$(newnote --slug t --memory "$mem")
if [ "$out" = "$mem/resume-t-2.md" ] && [ "$(cat "$mem/resume-t.md")" = "чужая" ]; then ok; else bad "new: имя занято — resume-t-2.md, чужой файл цел" "«${out}» $(cat "$mem/resume-t.md")"; fi
out=$(newnote --slug t --memory "$mem"); if [ "$out" = "$mem/resume-t-3.md" ]; then ok; else bad "new: заняты оба — resume-t-3.md" "«${out}»"; fi
ln -s "$work/nowhere.md" "$mem/resume-u.md"; out=$(newnote --slug u --memory "$mem")
if [ "$out" = "$mem/resume-u-2.md" ] && [ ! -e "$work/nowhere.md" ]; then ok; else bad "new: ссылка в никуда занимает имя, по ней не пишется" "«${out}»"; fi
reset; : >"$mem/resume-t.md"; for i in $(seq 2 99); do : >"$mem/resume-t-$i.md"; done
out=$(newnote --slug t --memory "$mem"); rc=$?
has "new: заняты все имена до -99 — так и сказано" "are all taken" "$out"
if [ $rc -eq 1 ] && [ "$(resumes_in "$mem")" -eq 99 ]; then ok; else bad "new: заняты все имена — код 1, новых файлов нет" "rc=$rc файлов $(resumes_in "$mem")"; fi
reset; : >"$mem/resume-t.md"; for i in $(seq 2 98); do : >"$mem/resume-t-$i.md"; done
out=$(newnote --slug t --memory "$mem"); if [ "$out" = "$mem/resume-t-99.md" ] && [ -f "$out" ]; then ok; else bad "new: заняты имена до -98 — берётся -99" "«${out:0:200}»"; fi
reset; for i in 1 2 3 4 5; do HANDOFF_TEST_PAUSE=0.3 newnote --slug t --memory "$mem" >"$work/new$i.out" & done; wait
distinct=$(cat "$work"/new*.out | sort -u | grep -c "^$mem/resume-t")
if [ "$distinct" -eq 5 ] && [ "$(resumes_in "$mem")" -eq 5 ]; then ok; else bad "new: пять разом на одну тему — пять разных файлов" "разных путей $distinct, файлов $(resumes_in "$mem"): $(cat "$work"/new*.out | tr '\n' ' ')"; fi
rm -f "$work"/new*.out

reset; long60=$(printf 'a%.0s' $(seq 1 60))
for slug in 'a/b' '..' 'тема' '' "${long60}a" 'index' 'Index' 'T' 'a--b' '-a' 'a-' 'a b' 'a.b' 'a_b'; do
  out=$(newnote "--slug=$slug" --memory "$mem"); rc=$?
  if [ $rc -eq 1 ] && [ "$(resumes_in "$mem")" -eq 0 ]; then ok; else bad "new: плохой slug «${slug}» — код 1, файла нет" "rc=$rc «${out:0:200}» $(ls -A "$mem")"; fi
done
out=$(newnote --slug '..'); rc=$?
if [ $rc -eq 1 ] && [ ! -e "$notes" ]; then ok; else bad "new без --memory: плохой slug — код 1, папки Hats нет" "rc=$rc «${out:0:200}»"; fi
has "new: плохой slug — отказ называет правило" "the slug must be" "$out"
has "new: slug index — отказ правилом slug, а не проверкой записки" "the slug must be" "$(newnote --slug index --memory "$mem")"
out=$(newnote --slug "$long60" --memory "$mem"); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "$mem/resume-$long60.md" ]; then ok; else bad "new: slug ровно 60 знаков принимается" "rc=$rc «${out:0:200}»"; fi
out=$(newnote --slug a1-b2-3 --memory "$mem"); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "$mem/resume-a1-b2-3.md" ]; then ok; else bad "new: slug из слов через дефис принимается" "rc=$rc «${out:0:200}»"; fi

reset; mkdir -p "$mem/sub" "$mem/memory" "$work/.claude/projects/memory" "$work/.claude/projects/-proj/notmemory" "$work/.claude/projects/-file"; printf 'x' >"$work/.claude/projects/-file/memory"
mkdir -p "$work/outer/projects/-proj/memory"
for d in "$proj" "$work/.claude/projects/-nope/memory" "$work/.claude/projects/-proj" "$mem/sub" "$work/.claude/projects" \
         "$work/.claude/projects/-proj/notmemory" "$work/.claude/projects/-file/memory" "$work/outer/projects/-proj/memory" \
         ".claude/projects/-proj/memory" "$work/.claude/projects/memory" "$mem/memory" ""; do
  out=$( (cd "$work" && newnote --memory "$d" --slug t) ); rc=$?
  if [ $rc -eq 1 ] && [ "$(find "$work/.claude/projects" "$work/outer" -name 'resume-*' | wc -l | tr -d ' ')" -eq 0 ] && [ ! -e "$notes" ]; then ok
  else bad "new: не папка памяти «${d}» — код 1, файла нет" "rc=$rc «${out:0:200}»"; fi
  has "new: не папка памяти «${d}» — отказ называет папку памяти" "is not an existing memory folder" "$out"
done
has "new: отказ папке называет папку памяти" "is not an existing memory folder" "$(newnote --memory "$proj" --slug t)"
reset; mkdir -p "$work/.claude/projects/-other/memory/sub"; ln -s "$work/.claude/projects/-other/memory/sub" "$mem/lnk"
out=$(newnote --slug t --memory "$mem/lnk/.."); rc=$?
has "new: созданный путь не прошёл проверку записки — так и сказано" "did not pass the note check" "$out"
if [ $rc -eq 1 ] && [ -z "$(ls -A "$work/.claude/projects/-other/memory" | grep -v '^sub$')" ] && [ "$(resumes_in "$mem")" -eq 0 ]; then ok
else bad "new: ссылка/.. уводит в чужую память — код 1, созданный файл убран" "rc=$rc $(ls -A "$work/.claude/projects/-other/memory")"; fi
printf 'своя\n' >"$mem/resume-t.md"; out=$(newnote --slug t --memory "$mem/lnk/.."); rc=$?
if [ $rc -eq 1 ] && [ -z "$(ls -A "$work/.claude/projects/-other/memory" | grep -v '^sub$')" ] && [ "$(cat "$mem/resume-t.md")" = "своя" ]; then ok
else bad "new: ссылка/.. в чужую память при записке того же имени в лексической папке — код 1, файла нет, своя цела" "rc=$rc «${out:0:200}» $(ls -A "$work/.claude/projects/-other/memory")"; fi
rm -f "$mem/resume-t.md" "$mem/lnk"
mkdir -p "$work/cfg/projects/-proj/memory"
out=$(env CLAUDE_CONFIG_DIR="$work/cfg" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" new --cwd "$proj" --slug t --memory "$mem" 2>&1); rc=$?
if [ $rc -eq 1 ] && [ ! -e "$mem/resume-t.md" ]; then ok; else bad "new: CLAUDE_CONFIG_DIR — память ~/.claude не его, отказ" "rc=$rc «${out:0:200}»"; fi
out=$(env CLAUDE_CONFIG_DIR="$work/cfg" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" new --cwd "$proj" --slug t --memory "$work/cfg/projects/-proj/memory" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "$work/cfg/projects/-proj/memory/resume-t.md" ]; then ok; else bad "new: CLAUDE_CONFIG_DIR — его память принимается" "rc=$rc «${out:0:200}»"; fi
rm -rf "$work/cfg" "$work/outer"

reset; for n in resume-index.md MEMORY.md memory.md RESUME-INDEX.md; do
  rm -f "$mem/$n"; printf '## NOW\n\nx\n' >"$mem/$n"; rm -f "$markers"/*.json
  out=$(save "$proj" "$mem/$n" "служебная"); rc=$?
  has "save: служебное имя $n — отказ" "the note must be a file" "$out"
  if [ $rc -eq 1 ] && [ "$(markers_n)" -eq 0 ]; then ok; else bad "save: служебное имя $n — код 1 и без отметки" "rc=$rc $(ls "$markers")"; fi
  rm -f "$mem/$n"
done
printf '## NOW\n\nx\n' >"$memmd"; ln -s "$memmd" "$mem/x.md"
has "save: записка-ссылка на MEMORY.md — отказ" "the note must be a file" "$(save "$proj" "$mem/x.md" "ссылка")"
reset; printf '## NOW\n\nx\n' >"$mem/r.md"; ln -s "$mem/r.md" "$mem/RESUME-INDEX.md"
has "save: ссылка с именем служебного файла на обычную записку — отказ" "the note must be a file" "$(save "$proj" "$mem/RESUME-INDEX.md" "имя")"
reset; own_dir=$(notes_of "$proj"); printf '## NOW\n\nx\n' >"$own_dir/Resume-Index.md"
has "save: служебное имя в папке Hats — отказ" "the note must be a file" "$(save "$proj" "$own_dir/Resume-Index.md" "служебная")"
reset; printf '## NOW\n\nSERVICE-LINE\n' >"$memmd"; printf '## NOW\n\nlegit line\n' >"$mem/r.md"
marker good "$dead_pid" "$dead_started" "$proj" "$mem/r.md" "обычная"
marker svc 99989 "$dead_started" "$proj" "$memmd" "служебная"
out=$(start startup); has "новая сессия: обычная записка памяти в списке" "\"обычная\"" "$out"; lacks "новая сессия: отметка на MEMORY.md не в списке" "служебная" "$out"
rm -f "$markers"/*.json; printf '%s\n\n- SERVICE-LINE\n' "$header_line" >"$index"; mine a "$proj" "$index" "индекс"
empty "/clear: отметка на resume-index.md — модели ничего" "$(start clear)"; same "/clear: отметка на resume-index.md — пользователю «нет якоря»" "$told_no_anchor" "$(told)"

reset; for n in a b c; do printf '## NOW\n\n%s\n' "$n" >"$mem/resume-$n.md"; done
mkdir "$mem/resume-dir.md" "$mem/sub"; printf 'x\n' >"$mem/sub/x.md"; printf 'x\n' >"$mem/notes.txt"; ln -s "$mem/resume-b.md" "$mem/resume-link.md"
printf '%s\n' "$memory_line" >"$memmd"; fresh=$(now)
{ printf '%s\n\nold paragraph\n\n' "$header_line"
  for pair in "прежняя этой|resume-a.md|$fresh" "живая|resume-b.md|$fresh" "старше 30 дней|resume-c.md|2020-01-01T00:00:00Z" \
              "без файла|resume-gone.md|$fresh" "служебная|MEMORY.md|$fresh" "ссылка|resume-link.md|$fresh" "папка|resume-dir.md|$fresh" \
              "не md|notes.txt|$fresh" "вложенная|sub/x.md|$fresh" "дата не дата|resume-b.md|2026-13-45T99:00:00Z"; do
    IFS='|' read -r t n s <<<"$pair"; printf -- '- [%s](<%s>) — saved %s, folder /x\n' "$t" "$n" "$s"
  done
  printf -- '- [без угловых](resume-b.md) — saved %s, folder /x\nмусорная строка\n' "$fresh"; } >"$index"
out=$(save "$proj" "$mem/resume-a.md" "новая тема"); rc=$?
has "save памяти: индекс обновлён" "index: updated" "$out"
if [ $rc -eq 0 ] && [ "$(markers_n)" -eq 1 ]; then ok; else bad "save памяти: код 0 и отметка" "rc=$rc $(ls "$markers")"; fi
if [ "$(entry_at 1)" = "$header_line" ] && [ -z "$(entry_at 2)" ] && [ "$(entry_at 3)" = "$about_line" ] && [ -z "$(entry_at 4)" ]; then ok
else bad "индекс: первая строка, пустая, абзац, пустая" "$(head -4 "$index")"; fi
want="- [новая тема](<resume-a.md>) — saved $(markerfield "$markers" saved_at), folder $(realp "$proj")"
if [ "$(entry_at 5)" = "$want" ]; then ok; else bad "индекс: новая строка наверху, в формате договора" "ждали «${want}», получили «$(entry_at 5)»"; fi
if [ "$(entry_at 6)" = "- [живая](<resume-b.md>) — saved $fresh, folder /x" ]; then ok; else bad "индекс: живая строка сохранена второй" "«$(entry_at 6)»"; fi
if [ "$(entries)" -eq 2 ]; then ok; else bad "индекс: ровно две строки записок" "$(entries): $(cat "$index")"; fi
idx=$(cat "$index")
for gone in "прежняя этой" "старше 30 дней" "без файла" "служебная" "ссылка" "[папка]" "не md" "вложенная" "дата не дата" "без угловых" "мусорная" "old paragraph"; do
  lacks "индекс: выпала строка «${gone}»" "$gone" "$idx"
done
if [ "$(cat "$memmd")" = "$memory_line" ]; then ok; else bad "save памяти: MEMORY.md со строкой не тронут" "$(cat "$memmd")"; fi
has "save памяти: MEMORY.md — строка есть" "MEMORY.md: has the index line" "$out"
if [ -z "$(ls -A "$mem" | grep '\.tmp$')" ]; then ok; else bad "индекс: временный файл убран" "$(ls -A "$mem")"; fi
has "индекс: права 600" "0o600" "$(mode_of "$index")"
reset; out=$(umask 022; save "$proj" "$note" "задача А")
has "отметка: права 600 и при umask 022" "0o600" "$(mode_of "$markers/4242-Mon-Nov-9-10-00-00-2026.json")"
reset; mine; (umask 022; sid=n1; start clear >/dev/null)
has "файл передачи: права 600 и при umask 022" "0o600" "$(mode_of "$markers/a.handed")"
reset; printf 'x\n' >"$mem/resume-t.md"; (umask 022; save "$proj" "$mem/resume-t.md" t >/dev/null)
has "индекс: права 600 и при umask 022" "0o600" "$(mode_of "$index")"
if [ -z "$(ls -A "$markers" "$mem" | grep '\.tmp')" ]; then ok; else bad "три записи: временных файлов не осталось" "$(ls -A "$markers" "$mem")"; fi

reset; printf 'x\n' >"$mem/resume-t.md"; save "$proj" "$mem/resume-t.md" $'a [b] (c) <d> `e`\x01f   g ( ) h' >/dev/null
case "$(entry_at 5)" in "- [a b c d ef g h](<resume-t.md>) — saved "*) ok ;; *) bad "индекс: из темы убраны скобки, обратная кавычка, управляющие знаки; пробелы схлопнуты" "«$(entry_at 5)»" ;; esac
reset; printf 'x\n' >"$mem/resume-t.md"; save "$proj" "$mem/resume-t.md" "$(printf 'x%.0s' $(seq 1 130))" >/dev/null
topic=$(entry_at 5 | sed -E 's/^- \[([^]]*)\].*/\1/'); if [ ${#topic} -eq 120 ]; then ok; else bad "индекс: тема не длиннее 120 знаков" "${#topic}"; fi
reset; mkdir -p "$work/odd"; printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"python3 handoff.py start"}]}]}}' >"$work/.claude/settings.json"
odd="$work/odd/a"$'\n'"b"; mkdir -p "$odd"; printf 'x\n' >"$mem/resume-t.md"
env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$odd" --note "$mem/resume-t.md" --topic t >/dev/null 2>&1
if [ "$(entries)" -eq 1 ] && [ "$(wc -l <"$index" | tr -d ' ')" -eq 5 ]; then ok; else bad "индекс: управляющий знак в рабочей папке не рвёт строку" "$(cat "$index")"; fi
rm -rf "$work/odd"

reset; { printf '%s\n\n%s\n\n' "$header_line" "$about_line"
  for i in $(seq 1 25); do printf 'x\n' >"$mem/resume-n$i.md"; printf -- '- [n%s](<resume-n%s.md>) — saved %s, folder /x\n' "$i" "$i" "$(now)"; done; } >"$index"
printf 'x\n' >"$mem/resume-t.md"; save "$proj" "$mem/resume-t.md" "свежая" >/dev/null; idx=$(cat "$index")
if [ "$(entries)" -eq 20 ]; then ok; else bad "индекс: строк не больше 20" "$(entries)"; fi
case "$(entry_at 5)" in "- [свежая]"*) ok ;; *) bad "индекс: при 20 строках новая всё равно наверху" "«$(entry_at 5)»" ;; esac
has "индекс: при 20 строках остаётся 19-я прежняя" "- [n19]" "$idx"; lacks "индекс: 20-я прежняя выпала" "- [n20]" "$idx"

for odd_name in 'a<b.md' 'a>b.md' $'a\tb.md'; do
  reset; printf 'x\n' >"$mem/$odd_name"; out=$(save "$proj" "$mem/$odd_name" "странное имя"); rc=$?
  has "индекс: имя «${odd_name}» — не индексируется" "index not updated: note name cannot be indexed" "$out"
  if [ $rc -eq 0 ] && [ "$(markers_n)" -eq 1 ] && [ ! -e "$index" ] && [ ! -e "$memmd" ]; then ok; else bad "индекс: имя «${odd_name}» — код 0, отметка есть, индекса и MEMORY.md нет" "rc=$rc"; fi
done

reset; for i in $(seq 1 10); do printf '## NOW\n\n%s\n' "$i" >"$mem/resume-p$i.md"; done
for i in $(seq 1 10); do saveas "43$i" "$mem/resume-p$i.md" "параллель $i" HANDOFF_TEST_PAUSE=0.3 >"$work/ps$i.out" & done; wait
idx=$(cat "$index" 2>/dev/null)
if [ "$(entries)" -eq 10 ]; then ok; else bad "одновременно: 10 сохранений в одну папку памяти — в индексе все 10" "строк $(entries): $(grep -c 'index: updated' "$work"/ps*.out | tr '\n' ' ')"; fi
for i in $(seq 1 10); do has "одновременно: в индексе записка $i" "- [параллель $i](<resume-p$i.md>)" "$idx"; done
if [ "$(cat "$memmd")" = "$memory_line" ]; then ok; else bad "одновременно: MEMORY.md создан один раз, одна строка" "$(cat "$memmd" 2>&1)"; fi
if [ "$(grep -l 'MEMORY.md: created' "$work"/ps*.out | wc -l | tr -d ' ')" -eq 1 ]; then ok; else bad "одновременно: MEMORY.md создал ровно один save" "$(grep -h 'MEMORY.md' "$work"/ps*.out | sort | uniq -c | tr '\n' ' ')"; fi
rm -f "$work"/ps*.out

reset; printf 'x\n' >"$mem/resume-t.md"; printf '%s\n\n- [прежняя](<resume-t.md>) — saved %s, folder /x\n' "$header_line" "$(now)" >"$index"; cp "$index" "$work/index.before"
lockf="$markers/index-$(python3 -I -c 'import hashlib,os,sys; print(hashlib.sha256(os.fsencode(os.path.realpath(sys.argv[1]))).hexdigest()[:16])' "$mem").lock"
python3 -I -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(6)' "$lockf" "$work/locked" &
holder=$!; for _ in $(seq 1 100); do [ -f "$work/locked" ] && break; sleep 0.05; done
s=$(date +%s); out=$(saveas 4242 "$mem/resume-t.md" t HANDOFF_TEST_INDEX_WAIT=0.5); rc=$?; e=$(date +%s); kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; rm -f "$work/locked"
has "блокировка индекса занята: так и сказано" "index not updated: lock busy" "$out"
has "блокировка индекса занята: MEMORY.md не проверялся" "MEMORY.md: not checked: index not updated" "$out"
if [ $rc -eq 0 ] && [ "$(markers_n)" -eq 1 ] && cmp -s "$index" "$work/index.before" && [ ! -e "$memmd" ]; then ok
else bad "блокировка индекса занята: код 0, отметка есть, индекс цел" "rc=$rc $(ls "$markers")"; fi
if [ $((e - s)) -le 3 ]; then ok; else bad "блокировка индекса: срок ожидания задаётся HANDOFF_TEST_INDEX_WAIT" "$((e - s)) с"; fi

foreign() {  # foreign <случай> — готовит чужой индекс
  rm -rf "$index" "$work/target.md"
  case "$1" in
    no-header) printf '# my own index\n\n- [x](<resume-t.md>) — saved %s, folder /x\n' "$(now)" >"$index" ;;
    link) printf '%s\n' "$header_line" >"$work/target.md"; ln -s "$work/target.md" "$index" ;;
    pipe) mkfifo "$index" ;;
    dir) mkdir "$index" ;;
    big) { printf '%s\n' "$header_line"; python3 -I -c 'print("x" * 70000)'; } >"$index" ;;
    not-utf8) printf '%s\n\xff\n' "$header_line" >"$index" ;;
  esac
}
for case_ in no-header link pipe dir big not-utf8; do
  reset; printf 'x\n' >"$mem/resume-t.md"; foreign "$case_"; [ -f "$index" ] && ! [ -L "$index" ] && cp "$index" "$work/index.before"
  out=$(timeout 10 env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$proj" --note "$mem/resume-t.md" --topic t 2>&1); rc=$?
  has "чужой индекс ($case_): не обновлён, так и сказано" "index not updated: resume-index.md" "$out"
  [ "$case_" = link ] && has "чужой индекс (link): причина — ссылка" "index not updated: resume-index.md is a link" "$out"
  case "$case_" in pipe|dir) has "чужой индекс ($case_): причина — не обычный файл" "index not updated: resume-index.md is not a regular file" "$out" ;; esac
  has "чужой индекс ($case_): MEMORY.md не проверялся" "MEMORY.md: not checked: index not updated" "$out"
  if [ ! -e "$memmd" ]; then ok; else bad "чужой индекс ($case_): MEMORY.md не создан" "$(cat "$memmd")"; fi
  if [ $rc -eq 0 ] && [ "$(markers_n)" -eq 1 ]; then ok; else bad "чужой индекс ($case_): код 0, отметка есть" "rc=$rc ${out:0:200}"; fi
  case "$case_" in
    link) if [ -L "$index" ] && [ "$(cat "$work/target.md")" = "$header_line" ]; then ok; else bad "чужой индекс (link): ссылка и её файл целы" "-"; fi ;;
    pipe) if [ -p "$index" ]; then ok; else bad "чужой индекс (pipe): канал цел" "-"; fi ;;
    dir) if [ -d "$index" ]; then ok; else bad "чужой индекс (dir): папка цела" "-"; fi ;;
    *) if cmp -s "$index" "$work/index.before"; then ok; else bad "чужой индекс ($case_): файл не тронут" "-"; fi ;;
  esac
done

reset; printf 'x\n' >"$mem/resume-t.md"; out=$(save "$proj" "$mem/resume-t.md" t)
has "MEMORY.md нет: создан" "MEMORY.md: created with the index line" "$out"
if [ "$(cat "$memmd")" = "$memory_line" ] && [ "$(wc -l <"$memmd" | tr -d ' ')" -eq 1 ]; then ok; else bad "MEMORY.md нет: создан одной строкой индекса" "$(cat "$memmd")"; fi
reset; printf 'x\n' >"$mem/resume-t.md"; : >"$memmd"; out=$(save "$proj" "$mem/resume-t.md" t)
has "MEMORY.md пустой: дописан" "MEMORY.md: was empty, the index line written" "$out"
if [ "$(cat "$memmd")" = "$memory_line" ]; then ok; else bad "MEMORY.md пустой: в нём строка индекса" "$(cat "$memmd")"; fi
memory_case() {  # memory_case <название> <ждём в выводе> — MEMORY.md уже лежит; проверка, что он не тронут
  printf 'x\n' >"$mem/resume-t.md"; cp "$memmd" "$work/memory.before"
  out=$(save "$proj" "$mem/resume-t.md" t); rc=$?
  has "MEMORY.md, $1" "$2" "$out"
  if [ $rc -eq 0 ] && cmp -s "$memmd" "$work/memory.before"; then ok; else bad "MEMORY.md, $1: код 0, файл не тронут" "rc=$rc"; fi
}
ask="MEMORY.md: add the index line: insert it with Edit before the current first line: $memory_line"
reset; { for i in $(seq 1 15); do printf -- '- [Topic %s](topic-%s.md) — %s\n' "$i" "$i" "$(printf 'w%.0s' $(seq 1 300))"; done; } >"$memmd"
memory_case "15 строк, около 5 КБ, строки нет: просьба поставить её первой" "$ask"
reset; { printf '%s\n' "$memory_line"; printf -- '- [Other](other.md) — x\n'; } >"$memmd"; memory_case "строка первой: есть" "MEMORY.md: has the index line"
reset; printf -- '- [Other](other.md) — x\n- [Index](<resume-index.md>) — x\n' >"$memmd"; memory_case "ссылка в угловых скобках: есть" "MEMORY.md: has the index line"
reset; printf -- '- [Other](other.md) — sessions are in resume-index.md\nResume index: [x](resume-index.md)\n' >"$memmd"
memory_case "имя индекса только в тексте строки: просьба" "$ask"
reset; { for i in $(seq 1 199); do printf -- '- line %s\n' "$i"; done; printf '%s\n' "$memory_line"; } >"$memmd"; memory_case "ссылка на 200-й строке: есть" "MEMORY.md: has the index line"
reset; { for i in $(seq 1 200); do printf -- '- line %s\n' "$i"; done; printf '%s\n' "$memory_line"; } >"$memmd"; memory_case "ссылка на 201-й строке: просьба" "$ask"
reset; python3 -I -c 'import sys; open(sys.argv[1], "w", encoding="utf-8").write(("\U0001F600" * 4500 + "\n") * 3 + sys.argv[2] + "\n")' "$memmd" "$memory_line"
memory_case "ссылка за 25 000 знаков в единицах UTF-16 (13 503 знака Python): просьба" "$ask"
reset; python3 -I -c 'import sys; open(sys.argv[1], "w", encoding="utf-8").write(("\U0001F600" * 4500 + "\n") * 2 + sys.argv[2] + "\n")' "$memmd" "$memory_line"
memory_case "ссылка до 25 000 единиц UTF-16: есть" "MEMORY.md: has the index line"
reset; python3 -I -c 'import sys; open(sys.argv[1], "w", encoding="utf-8").write("a" * 24949 + "\n" + sys.argv[2] + "\n")' "$memmd" "$memory_line"
memory_case "25 000-й знак внутри строки индекса — обрезка по переводу строки: просьба" "$ask"
reset; printf '%s\n' "$memory_line" >"$work/target.md"; ln -s "$work/target.md" "$memmd"; memory_case "ссылка: не проверен" "MEMORY.md: not checked: MEMORY.md is a link"
if [ -L "$memmd" ] && [ "$(cat "$work/target.md")" = "$memory_line" ]; then ok; else bad "MEMORY.md-ссылка: ссылка и её файл целы" "-"; fi
reset; printf -- '- x\n\xff\n' >"$memmd"; memory_case "не UTF-8: не проверен" "MEMORY.md: not checked: MEMORY.md is not UTF-8"
reset; { printf '%s\n' "$memory_line"; python3 -I -c 'print("x" * 110000)'; } >"$memmd"; memory_case "больше 100 КБ: не проверен" "MEMORY.md: not checked: MEMORY.md is larger than 100 KB"
for kind in pipe dir; do
  reset; printf 'x\n' >"$mem/resume-t.md"; if [ "$kind" = pipe ]; then mkfifo "$memmd"; else mkdir "$memmd"; fi
  out=$(timeout 10 env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$proj" --note "$mem/resume-t.md" --topic t 2>&1); rc=$?
  has "MEMORY.md — $kind: не проверен" "MEMORY.md: not checked: MEMORY.md is not a regular file" "$out"
  if [ $rc -eq 0 ] && { [ -p "$memmd" ] || [ -d "$memmd" ]; }; then ok; else bad "MEMORY.md — $kind: код 0, не тронут" "rc=$rc"; fi
done

reset; own_dir=$(notes_of "$proj"); printf '## NOW\n\nx\n' >"$own_dir/r.md"; out=$(save "$proj" "$own_dir/r.md" "в папке Hats"); rc=$?
has "записка папки Hats: индекса нет — так и сказано" "index: none (note not in Claude Code's memory)" "$out"
lacks "записка папки Hats: строки MEMORY.md нет" "MEMORY.md:" "$out"
if [ $rc -eq 0 ] && [ ! -e "$own_dir/resume-index.md" ] && [ ! -e "$index" ] && [ ! -e "$memmd" ]; then ok; else bad "записка папки Hats: ни индекса, ни MEMORY.md" "rc=$rc $(ls -A "$own_dir" "$mem")"; fi
reset; rm -rf "$work/vault"; mkdir -p "$work/vault" "$work/.claude/projects/-linked"; ln -s "$work/vault" "$work/.claude/projects/-linked/memory"
printf '## NOW\n\nx\n' >"$work/vault/n.md"; out=$(save "$proj" "$work/.claude/projects/-linked/memory/n.md" "ссылка")
has "память-ссылка: индекса нет — так и сказано" "index: none (the memory folder is a link)" "$out"
out=$(newnote --slug t --memory "$work/.claude/projects/-linked/memory"); rc=$?
if [ $rc -eq 1 ] && [ ! -e "$work/vault/resume-t.md" ]; then ok; else bad "new: папка памяти — ссылка: код 1, записки нет" "rc=$rc «${out:0:200}»"; fi
has "new: папка памяти — ссылка: отказ называет настоящий путь" "its real path" "$out"
if [ -z "$(ls -A "$work/vault" | grep -v '^n\.md$')" ]; then ok; else bad "память-ссылка: в её папке ни индекса, ни MEMORY.md" "$(ls -A "$work/vault")"; fi
rm -rf "$work/vault"

reset; printf '## NOW\n\na\n' >"$mem/resume-a.md"
if [ -e "$mem/RESUME-A.md" ]; then
  save "$proj" "$mem/resume-a.md" "первый" >/dev/null; save "$proj" "$mem/RESUME-A.md" "второй" >/dev/null
  if [ "$(entries)" -eq 1 ]; then ok; else bad "индекс: та же записка путём в другом регистре — одна строка" "$(cat "$index")"; fi
fi
if [ "$(id -u)" -ne 0 ]; then
  reset; printf '## NOW\n\nx\n' >"$mem/resume-t.md"; chmod 500 "$mem"
  out=$(save "$proj" "$mem/resume-t.md" t); rc=$?; chmod 700 "$mem"
  if [ $rc -eq 0 ] && [ "$(markers_n)" -eq 1 ]; then ok; else bad "индекс не записать: код 0 и одна отметка" "rc=$rc ${out:0:300}"; fi
  has "индекс не записать: так и сказано" "index not updated: resume-index.md cannot be written" "$out"
  has "индекс не записать: MEMORY.md не проверялся" "MEMORY.md: not checked: index not updated" "$out"
  has "индекс не записать: проверка записки на месте" "quotes and numbers: none outside code and the header — nothing checked" "$out"
  lacks "индекс не записать: без трассировки" "Traceback" "$out"
fi
reset; p=$(newnote --slug flow --memory "$mem"); printf '## NOW\n\nflow line\n' >"$p"
out=$(save "$proj" "$p" "поток"); has "new → save: отметка, индекс, MEMORY.md" "index: updated
MEMORY.md: created with the index line" "$out"
has "new → save: после /clear записка отдаётся" "flow line" "$(start clear)"
has "new → save: в индексе записка" "- [поток](<resume-flow.md>)" "$(cat "$index")"


# --- строка пользователю: после /clear — какой якорь взят, в новой сессии — какие записки
reset; mine; start clear >/dev/null
has "строка: кириллица в выводе — байты UTF-8" "задача А" "$(heard)"; lacks "строка: кириллица не экранирована" "$(printf '\\%s' u0437)" "$(heard)"
t3="2026-11-12T10:00:00Z"
reset; marker a 4242 "$own_started" "$proj" "$note" "задача А" "$t3"
printf '{"key":"%s|%s","session":"a/b"}' "$t3" "$real_note" >"$markers/a.handed"
sid=u2; empty "строка: якорь отдан сессии с негодным номером — модели ничего" "$(start clear)"
same "строка: негодный номер сессии не показан" "Hats handoff: anchor \"задача А\" was already given to another session" "$(told)"
printf '{"key":"%s|%s","session":"x\\u0007y"}' "$t3" "$real_note" >"$markers/a.handed"; start clear >/dev/null
same "строка: номер сессии с управляющим знаком не показан" "Hats handoff: anchor \"задача А\" was already given to another session" "$(told)"
reset; mine a "$proj" "$note" "$(printf 'a\001b\tc\nd\342\200\256e'; printf 'я%.0s' $(seq 1 200))"
sid=u3; out=$(start clear); want_topic="abcde$(printf 'я%.0s' $(seq 1 115))"
same "строка: из темы убраны управляющие знаки, тема не длиннее 120" "Hats handoff: continuing anchor \"$want_topic\" — $real_note" "$(told)"
has "строка: модели тема — как прежде" "$(printf 'a\001b\tc\nd')" "$out"
reset; mine a "$proj" "$note" "$(printf 'می\342\200\214خواهم \360\237\221\251\342\200\215\360\237\222\273 \342\201\246x\342\201\251')"
sid=u5; start clear >/dev/null
same "строка: соединители (ZWNJ, ZWJ) остаются, управление направлением убрано" "Hats handoff: continuing anchor \"$(printf 'می\342\200\214خواهم \360\237\221\251\342\200\215\360\237\222\273 x')\" — $real_note" "$(told)"
reset; tabbed="$mem/a"$'\t'"b.md"; printf '## NOW\n\nx\n' >"$tabbed"; mine a "$proj" "$tabbed" "таб"
sid=u4; out=$(start clear)
same "строка: из пути записки убраны управляющие знаки" "Hats handoff: continuing anchor \"таб\" — $real_mem/ab.md" "$(told)"
has "строка: модели путь — как прежде" "$real_mem/a"$'\t'"b.md" "$out"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "старшая" "2026-11-01T10:00:00Z"; marker b 99989 "$dead_started" "$proj" "$note" "свежая"
start startup >/dev/null
same "строка: две записки — по строке, новая сверху" "Hats handoff: 2 notes from closed sessions in this folder:
1. \"свежая\" — $real_note
2. \"старшая\" — $real_note" "$(told)"
reset; long=$(printf 'n%.0s' $(seq 1 240)); ttt=$(printf 't%.0s' $(seq 1 130))
for i in 1 2 3 4 5; do printf 'x\n' >"$mem/$i$long.md"; marker "m$i" $((99980 + i)) "$dead_started" "$proj" "$mem/$i$long.md" "$ttt" "2026-11-0${i}T10:00:00Z"; done
out=$(start startup); same "строка: модели — все пять записок, как прежде" "5" "$(count '^[0-9]\. "' "$out")"
fit=$(told | python3 -I -c 'import re,sys
text = sys.stdin.read()
lines = text.split("\n")
items = [line for line in lines[1:] if re.fullmatch(r"[1-5]\. \"t{120}\" — /.+\.md", line)]
more = re.fullmatch(r"and (\d+) more", lines[-1])
print("units=%s whole=%s all=%s" % (len(text.encode("utf-16-le")) // 2 <= 2000, len(items) == len(lines) - 2, len(items) + int(more.group(1)) if more else None))')
same "строка: не длиннее 2000 единиц UTF-16, лишние записки — целиком и счётом" "units=True whole=True all=5" "$fit"
reset; mkdir -p "$work/fakebin"; printf '#!/bin/bash\ncase "$*" in *" %s") exit 1 ;; esac\nsleep 10\n' "$dead_pid" >"$work/fakebin/ps"; chmod +x "$work/fakebin/ps"
marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"; marker b 99989 "$dead_started" "$proj" "$note" "вторая"; marker c 99988 "$dead_started" "$proj" "$note" "третья"
out=$(CMP=0 start startup "$proj" PATH="$work/fakebin:$PATH" HANDOFF_TEST_BUDGET=1)
has "строка: часть не проверена — модели закрытая" "\"закрытая\"" "$out"; lacks "строка: часть не проверена — непроверенной у модели нет" "\"вторая\"" "$out"
same "строка: список и сколько не успел проверить" "Hats handoff: 1 note from closed sessions in this folder:
1. \"закрытая\" — $real_note
could not check 2 more notes in time" "$(told)"
has "журнал: в списке одна, не проверены две" "outcome=listed listed=1 unchecked=2" "$(tl outcome listed unchecked)"
printf '#!/bin/bash\nsleep 10\n' >"$work/fakebin/ps"
out=$(CMP=0 start startup "$proj" PATH="$work/fakebin:$PATH" HANDOFF_TEST_BUDGET=1)
empty "строка: не проверена ни одна — модели ничего" "$out"
same "строка: не проверена ни одна — «не успел», а не «записок нет»" "Hats handoff: could not check 3 notes in time, none listed" "$(told)"
has "журнал: не проверены все" "outcome=unchecked unchecked=3" "$(tl outcome unchecked)"
reset; start startup >/dev/null
has "журнал: закрытых нет, всё проверено" "outcome=no-closed unchecked=0" "$(tl outcome unchecked)"
reset; ln -s "$proj" "$work/projlink"; marker a "$dead_pid" "$dead_started" "$proj" "$note" "та же строка"; marker b 99989 "$dead_started" "$work/projlink" "$note" "через ссылку"
CMP=0 start startup "$proj" HANDOFF_TEST_BUDGET=0 >/dev/null; rm -f "$work/projlink"
same "строка: после срока папка сравнивается как написана, ссылка не раскрывается" "Hats handoff: could not check 1 note in time, none listed" "$(told)"
reset; printf '{"pid":4242,"started":"%s","cwd":"%s","note":"%s","topic":"x\\udc80","saved_at":"%s"}' "Mon Nov 9 10:00:00 2026" "$proj" "$note" "$(now)" >"$markers/a.json"
out=$(CMP=0 start clear)
empty "строка: текст модели не записать в UTF-8 — модели ничего" "$out"
same "строка: текст модели не записать — пользователю, что упало" "Hats handoff: failed (UnicodeEncodeError), see $markers/runs.log" "$(told)"
reset; mine; start clear "$proj" CLAUDE_CONFIG_DIR="$work/$(printf 'c%.0s' $(seq 1 3000))" HANDOFF_PROCESS="x:y" >/dev/null
has "строка: путь журнала длиннее предела — строка об ошибке всё равно есть" "Hats handoff: failed (ValueError), see $work/ccc" "$(told)"
same "строка: путь журнала длиннее предела — строка ровно 2000 единиц UTF-16" "2000" "$(told | python3 -I -c 'import sys; print(len(sys.stdin.read().encode("utf-16-le")) // 2)')"
reset; mine; out=$(CMP=0 start clear "$proj" LC_ALL=en_US.ISO8859-1)
has "строка: stdout в Latin-1 — записка модели всё равно отдаётся" "continues the note \"задача А\"" "$out"
same "строка: stdout в Latin-1 — и строка пользователю" "Hats handoff: continuing anchor \"задача А\" — $real_note" "$(told)"
harness() {  # harness <сессия> <код на Python, правит scope до запуска> — хук через exec, stdout и stderr вместе
  printf '{"session_id":"%s","cwd":"%s","source":"clear"}' "$1" "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I -c 'import os,sys
'"$swap_py"'
path = sys.argv[1]
scope = {
    "__name__": "hook",
    "__file__": path,
}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), scope)
exec(sys.argv[2], {
    "scope": scope,
    "os": os,
    "swap": swap,
})
sys.exit(scope["main"](["start"]))' "$HOOK" "$2" 2>&1
}
reset; mine; out=$(harness e1 'def broken(*args):
    raise RuntimeError("after the print")
swap("record_handed", broken)')
same "строка: падение после печати — в выводе один объект" "1" "$(printf '%s\n' "$out" | grep -c .)"
has "строка: падение после печати — это записка" "continues the note" "$(printf '%s' "$out" | model_of)"
lacks "строка: падение после печати — строки об ошибке нет" "failed (" "$out"
has "журнал: падение после печати" "outcome=error error=RuntimeError" "$(tl outcome error)"
reset; mine; out=$(harness o1 'def noted(*args):
    os.write(2, b"RECORDED\n")
    record(*args)
record = swap("record_handed", noted)')
has "после /clear сначала вывод и сброс буфера" "continues the note" "$(printf '%s\n' "$out" | sed -n 1p | model_of)"
same "после /clear «отдано» записано после вывода" "RECORDED" "$(printf '%s\n' "$out" | sed -n 2p)"
if [ -f "$markers/a.handed" ]; then ok; else bad "после /clear «отдано» записано" "a.handed нет"; fi
reset; printf 'share 73%%\n' >"$proj/src.md"
printf '## NOW\n\nx (cite: %s:1 "share 73%%") (cite: %s:1 "share 73%%") (cite: %s:1 "share 73%%")\n' "$proj/src.md" "$proj/src.md" "$proj/src.md" >"$note"; mine
out=$(harness t1 'import inspect, sys
check = sys.modules["handoff_check"]
lines, first = inspect.getsourcelines(check.check_text)
target = next(first + i + 1 for i, line in enumerate(lines) if "CITE.finditer" in line)
check.out_of_time = lambda: sys._getframe(1).f_lineno == target')
has "срок вышел среди цитат последней строки — это сказано, а не «проверено»" "check ran out of time before the end of the note" "$(printf '%s' "$out" | model_of)"
reset; printf 'share 73%%\n' >"$proj/src.md"
printf '## NOW\n\nx (cite: %s:1 "share 73%%") (cite: %s:1 "share 73%%")\nпосле\n' "$proj/src.md" "$proj/src.md" >"$note"; mine
out=$(harness t2 'import inspect, sys
check = sys.modules["handoff_check"]
lines, first = inspect.getsourcelines(check.check_text)
target = next(first + i + 1 for i, line in enumerate(lines) if "CITE.finditer" in line)
spent = []
def latched():
    if sys._getframe(1).f_lineno == target:
        spent.append(1)
    return bool(spent)
check.out_of_time = latched')
same "срок вышел среди цитат и не вернулся — предупреждение одно" "1" "$(printf '%s' "$out" | model_of | grep -c 'check ran out of time before the end of the note')"
for cwd_json in null '""' 5; do
  reset; out=$(printf '{"session_id":"s","cwd":%s,"source":"clear"}' "$cwd_json" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1)
  empty "негодная папка ($cwd_json) — тишина" "$out"; has "негодная папка ($cwd_json) — в журнале skipped" "outcome=skipped" "$(tl outcome)"
done
reset; empty "ввод не словарь — тишина" "$(printf '[]' | env HOME="$work" python3 -I "$HOOK" start 2>&1)"
reset; empty "ввод с глубокой вложенностью — тишина" "$(python3 -I -c 'print("[" * 100000 + "]" * 100000)' | env HOME="$work" python3 -I "$HOOK" start 2>&1)"


# --- подключение плагином: hooks/hooks.json своего плагина читается, только если рядом .claude-plugin/plugin.json
plug="$work/plug"
plugin_at() {  # plugin_at <hooks.json или -> <yes|no — класть ли plugin.json>
  rm -rf "$plug"; mkdir -p "$plug/scripts" "$plug/hooks"; put_hook "$plug/scripts"; cp "$plugin_root/scripts/py.sh" "$plug/scripts/py.sh"
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
reset; mkdir -p "$work/.claude/hooks"; put_hook "$work/.claude/hooks"; cp "$plugin_root/hooks/hooks.json" "$work/.claude/hooks/hooks.json"
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
call=$(open_call "$(printf '{"session_id":"sh1","cwd":"%s","source":"clear"}' "$proj")"); compare=0
run_reference "$call" CLAUDE_PLUGIN_ROOT="$plug" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" && compare=1
env CLAUDE_PLUGIN_ROOT="$plug" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" sh -c "$command_line" <"$call/in" >"$call/out" 2>"$call/err"; rc=$?
out=$(judge "$call" "hooks.json через sh -c, строка $LINENO" "$compare" "$rc"); rm -rf "$call"
has "hooks.json: команда как есть через sh -c отдаёт записку после /clear" "continues the note \"задача А\"" "$out"
has "hooks.json: команда как есть через sh -c — и строка пользователю" "Hats handoff: continuing anchor \"задача А\"" "$(told)"
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
        allow_sh = os.path.join(root, "scripts", "allow.sh")
        if words == ["sh", allow_sh] and os.path.isfile(allow_sh) and "py.sh\" --quiet" in open(allow_sh, encoding="utf-8").read():
            continue
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
has "hooks.json: все десять хуков идут через py.sh --quiet (allow — через allow.sh), их скрипты и py.sh есть" "wrapped=10 py.sh=True" "$(hooked wrapper)"
read_hook=$(python3 -I -c 'import json,os,shlex,sys
root = sys.argv[1]
groups = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))["hooks"]["PostToolUse"]
found = [(g, h) for g in groups for h in g["hooks"] if "handoff.py" in h.get("command", "")]
if len(found) != 1:
    sys.exit("commands with handoff.py under PostToolUse: %d" % len(found))
group, hook = found[0]
words = shlex.split(hook["command"].replace("${CLAUDE_PLUGIN_ROOT}", root))
others = [g for g in groups if g is not group]
background = all(h.get("async") is True and "matcher" not in g for g in others for h in g["hooks"])
print("matcher=%s async=%s timeout=%s last=%s hooks=%d groups=%d window=%s" % (
    group.get("matcher"), hook.get("async", False), hook.get("timeout"), words[-1], len(group["hooks"]), len(groups), background))' "$plugin_root" 2>&1)
has "hooks.json: took — своя синхронная группа PostToolUse с matcher Read, рядом фоновая группа window-fill без матчера" \
  "matcher=Read async=False timeout=5 last=took hooks=1 groups=2 window=True" "$read_hook"
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
news = [c for c in spans if " new " in c]
new = len(news) == 2 and all(c.startswith(prefix + " new --slug <slug>") for c in news) and sum(" --memory " in c for c in news) == 1
words = shlex.split(prefix)
wrapped = words[:2] == ["sh", "${CLAUDE_PLUGIN_ROOT}/scripts/py.sh"] and "--quiet" not in words
files = [w.replace("${CLAUDE_PLUGIN_ROOT}", root) for w in words[1:]]
spaced = shlex.split(prefix.replace("${CLAUDE_PLUGIN_ROOT}", "/a b")) == ["sh", "/a b/scripts/py.sh", "/a b/scripts/handoff.py"]
print("name=%s same=%s new=%s wrapped=%s handoff=%s files=%s spaced=%s" % (
    fields.get("name"), same, new, wrapped, "${CLAUDE_PLUGIN_ROOT}/scripts/handoff.py" in words,
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
has "SKILL.md anchor: save и оба new (с --memory и без) в теле и правило Bash в allowed-tools — одна команда через py.sh, файлы есть, путь с пробелом цел" \
  "name=anchor same=True new=True wrapped=True handoff=True files=True spaced=True" "$out"
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

# --- 8c: пометка записки, которую читает другая живая сессия (хук took после Read)
taken="$markers/taken"
took_in() {  # took_in <сессия> <путь> [ещё поля] — вход PostToolUse/Read, поля как в замере 2026-11-13
  printf '{"cwd":"%s","duration_ms":4,"effort":"high","hook_event_name":"PostToolUse","permission_mode":"default","prompt_id":"p-1","scratchpad_dir":"%s","session_id":"%s","tool_input":{"file_path":"%s"},"tool_name":"Read","tool_response":{"file":{"filePath":"%s","content":"x","numLines":1,"startLine":1,"totalLines":1},"type":"text"},"tool_use_id":"toolu_1","transcript_path":"%s"%s}' \
    "$proj" "$work/pad" "$1" "$2" "$2" "$work/t.jsonl" "${3:-}"
}
run_took() {  # run_took <ввод> <pid:started> <папка вызова> [env...] — хук took; stdout, stderr и код — в папку вызова
  local input="$1" p="$2" call="$3"; shift 3
  mkdir -p "$call"; printf '%s' "$input" >"$call/in"
  timeout 10 env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$p" "$@" python3 -I "$HOOK" took <"$call/in" >"$call/out" 2>"$call/err"; echo $? >"$call/rc"
}
judged() {  # judged <папка вызова> <подпись> — форма вывода took (PostToolUse); печатает текст модели, строка пользователю — told
  rm -f "$work/told" "$work/heard"; judge "$1" "$2" 0 "$(cat "$1/rc")" PostToolUse
}
took() {  # took <pid:started> <сессия> <путь> [env...] — печатает текст модели; EXTRA — ещё поля входа
  local call; call=$(mktemp -d "$work/call.XXXXXX")
  run_took "$(took_in "$2" "$3" "${EXTRA:-}")" "$1" "$call" "${@:4}"; judged "$call" "took, строка ${BASH_LINENO[0]}"; rm -rf "$call"
}
raw_took() {  # raw_took <ввод как есть> [env...] — печатает текст модели
  local call; call=$(mktemp -d "$work/call.XXXXXX")
  run_took "$1" "$own" "$call" "${@:2}"; judged "$call" "took, сырой ввод, строка ${BASH_LINENO[0]}"; rm -rf "$call"
}
took_ms() {  # took_ms <pid:started> <сессия> <путь> [env...] — печатает время одного процесса хука в мс; stdout хука — в $work/ms.out; форма и told — как у took, после замера
  local p="$1" s="$2" f="$3" call; shift 3; call=$(mktemp -d "$work/call.XXXXXX"); took_in "$s" "$f" "${EXTRA:-}" >"$call/in"
  CALL="$call" python3 -I -c 'import os,subprocess,sys,time
call = os.environ["CALL"]
t = time.monotonic()
done = subprocess.run(sys.argv[1:], stdin=open(call + "/in", "rb"), capture_output=True)
ms = int((time.monotonic() - t) * 1000)
open(call + "/out", "wb").write(done.stdout)
open(call + "/err", "wb").write(done.stderr)
open(call + "/rc", "w").write("%d\n" % done.returncode)
print(ms)' env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$p" "$@" python3 -I "$HOOK" took
  cp "$call/out" "$work/ms.out"; judged "$call" "took с замером, строка ${BASH_LINENO[0]}" >/dev/null; rm -rf "$call"
}
live() {  # live — фоновый sleep; печатает «pid:время запуска», гасится при выходе из набора
  sleep 300 >/dev/null 2>&1 &
  local p=$!; echo "$p" >>"$work/sleepers"
  printf '%s:%s' "$p" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$p" | xargs)"
}
pid_of() { printf '%s' "${1%%:*}"; }
key_of() { python3 -I -c 'import hashlib,os,sys; print(hashlib.sha256(os.fsencode(sys.argv[1])).hexdigest())' "$1"; }
reads_of() { python3 -I -c 'import re,sys; p, _, s = sys.argv[1].partition(":"); print("%s-%s.reads" % (p, re.sub(r"[^0-9A-Za-z]+", "-", s).strip("-")))' "$1"; }
reader_json() {  # reader_json <pid:started> <сессия> [время] — один читатель
  printf '{"pid":%s,"started":"%s","session":"%s","at":"%s"}' "${1%%:*}" "${1#*:}" "$2" "${3:-2026-11-13T09:41:00Z}"
}
mark_file() {  # mark_file <настоящий путь записки> <JSON-список читателей> — файл пометки как есть
  mkdir -p "$taken"; printf '{"note":"%s","readers":%s}' "$1" "$2" >"$taken/$(key_of "$1").json"
}
mark_of() { printf '%s' "$taken/$(key_of "$1").json"; }
readers_of() {  # readers_of <настоящий путь записки> — «pid/сессия» по порядку; «нет», если файла нет
  python3 -I -c 'import hashlib,json,os,sys
path = os.path.join(sys.argv[2], hashlib.sha256(os.fsencode(sys.argv[1])).hexdigest() + ".json")
if not os.path.lexists(path):
    sys.exit("нет")
print(" ".join("%s/%s" % (r["pid"], r["session"]) for r in json.load(open(path, encoding="utf-8"))["readers"]))' "$1" "$taken" 2>&1
}
at_of() {  # at_of <настоящий путь записки> <pid:started> — время первого чтения этим процессом
  python3 -I -c 'import hashlib,json,os,sys
path = os.path.join(sys.argv[3], hashlib.sha256(os.fsencode(sys.argv[1])).hexdigest() + ".json")
print(next((r["at"] for r in json.load(open(path, encoding="utf-8"))["readers"] if r["pid"] == int(sys.argv[2])), "нет"))' "$1" "${2%%:*}" "$taken" 2>&1
}
keys_of() { python3 -I -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["keys"]))' "$taken/$(reads_of "$1")" 2>&1; }
item_of() { printf 'session %s (pid %s, since %s)' "$2" "$(pid_of "$1")" "${3:-2026-11-13T09:41:00Z}"; }
tmp_left() { ls -A "$taken" 2>/dev/null | grep -c '^\.tmp-'; }
mkps() { mkdir -p "$work/psbin"; printf '#!/bin/bash\n%s\n' "$1" >"$work/psbin/ps"; chmod +x "$work/psbin/ps"; }
wait_for() { local i; for i in $(seq 1 250); do eval "$1" && return 0; sleep 0.02; done; return 1; }
hold_lock() {  # hold_lock <файл> <секунды> — держит flock в фоне; печатает pid держателя, когда блокировка взята
  rm -f "$work/locked"
  python3 -I -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(float(sys.argv[3]))' "$1" "$work/locked" "$2" >/dev/null 2>&1 &
  local h=$!; wait_for '[ -f "$work/locked" ]'; printf '%s' "$h"
}
fill_fifo() {  # fill_fifo <канал> — держит канал открытым и заполненным до отказа, никто не читает; печатает pid
  local fifo="$1"
  rm -f "$fifo" "$fifo.ready"; mkfifo "$fifo"
  python3 -I -c 'import os,sys,time
r = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK)
w = os.open(sys.argv[1], os.O_WRONLY | os.O_NONBLOCK)
try:
    while True:
        os.write(w, b"x" * 4096)
except BlockingIOError:
    pass
open(sys.argv[1] + ".ready", "w").close()
time.sleep(30)' "$fifo" >/dev/null 2>&1 &
  local f=$!; echo "$f" >>"$work/sleepers"; wait_for '[ -e "$fifo.ready" ]'; printf '%s' "$f"
}
tls() {  # tls <сессия> <поля...> — последняя строка журнала с этой сессией
  python3 -I -c 'import json,sys
lines = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.strip()]
found = [d for d in lines if d.get("session") == sys.argv[2]]
d = found[-1] if found else {}
print(" ".join(f"{k}={d.get(k)}" for k in sys.argv[3:]))' "$trace" "$@" 2>&1
}
harness_took() {  # harness_took <pid:started> <сессия> <путь> <код на Python> — took через exec, scope правится до запуска
  local call; call=$(mktemp -d "$work/call.XXXXXX"); took_in "$2" "$3" >"$call/in"
  env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$1" python3 -I -c 'import os,sys
'"$swap_py"'
path = sys.argv[1]
scope = {
    "__name__": "hook",
    "__file__": path,
}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), scope)
exec(sys.argv[2], {
    "scope": scope,
    "os": os,
    "swap": swap,
})
sys.exit(scope["main"](["took"]))' "$HOOK" "$4" <"$call/in" >"$call/out" 2>"$call/err"; echo $? >"$call/rc"
  judged "$call" "took с подменой, строка ${BASH_LINENO[0]}"; rm -rf "$call"
}
nofcntl() {  # nofcntl <ввод> <pid:started> <команда> — хук без модуля fcntl, как на Windows; печатает stdout
  printf '%s' "$1" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$2" python3 -I -c 'import sys; sys.modules["fcntl"] = None; path = sys.argv[1]; sys.argv = [path, sys.argv[2]]; exec(compile(open(path).read(), path, "exec"), {"__name__": "__main__", "__file__": path})' "$HOOK" "$3" 2>&1
}
user_of() { python3 -I -c 'import json,sys
try:
    print(json.loads(sys.stdin.read()).get("systemMessage", ""), end="")
except ValueError as error:
    print("не JSON: %s" % error)'; }
closed_note() { marker "${1:-a}" "$dead_pid" "$dead_started" "$proj" "${2:-$note}" "${3:-закрытая}"; }
ask_took='Another session may be continuing this task: continue it only if the user confirms.'
ask_list='If the user picks it, say so and continue only if the user confirms.'
me="$me_pid:$me_started"

# --- took: первый читатель, другие живые, повторное чтение
reset; closed_note; A=$(live); B=$(live); C=$(live)
out=$(took "$A" sA "$note")
empty "took: первый читатель — модели ничего" "$out"; empty "took: первый читатель — пользователю ничего" "$(heard)"
has "took: первый читатель — журнал" "command=took outcome=took session=sA pid=$(pid_of "$A") live=0 unknown=0 warned=False" "$(tl command outcome session pid live unknown warned)"
has "took: в журнале — настоящий путь записки" "note=$real_note" "$(tl note)"
same "took: первый читатель записан" "$(pid_of "$A")/sA" "$(readers_of "$real_note")"
has "took: папка taken создана с правами 700" "0o700" "$(mode_of "$taken")"
has "took: taken/.lock — права 600" "0o600" "$(mode_of "$taken/.lock")"
same "took: свой список процесса — ключ записки" "$(key_of "$real_note")" "$(keys_of "$A")"
has "took: файл пометки — права 600" "0o600" "$(mode_of "$(mark_of "$real_note")")"
at_a=$(at_of "$real_note" "$A")
case "$at_a" in 20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z) ok ;; *) bad "took: время первого чтения — в формате меток, UTC" "$at_a" ;; esac
out=$(took "$B" sB "$note"); facts="1 other live session(s) reading this note: $(item_of "$A" sA "$at_a")"
same "took: другая живая сессия — пользователю" "Hats handoff: $facts" "$(told)"
same "took: другая живая сессия — модели" "[handoff] $facts. $ask_took" "$out"
has "took: другая живая сессия — журнал" "outcome=took-shared live=1 unknown=0 warned=True" "$(tl outcome live unknown warned)"
same "took: второй читатель записан" "$(pid_of "$A")/sA $(pid_of "$B")/sB" "$(readers_of "$real_note")"
at_b=$(at_of "$real_note" "$B")
out=$(took "$C" sC "$note")
same "took: третий — о двух первых" "Hats handoff: 2 other live session(s) reading this note: $(item_of "$A" sA "$at_a"), $(item_of "$B" sB "$at_b")" "$(told)"
before=$(cat "$(mark_of "$real_note")")
out=$(took "$A" sA2 "$note")
empty "took: повторное чтение тем же процессом — модели ничего" "$out"; empty "took: повторное чтение — пользователю ничего" "$(heard)"
has "took: повторное чтение — again" "outcome=again live=2 unknown=0 warned=False" "$(tl outcome live unknown warned)"
same "took: повторное чтение не меняет файл (время и сессия первого чтения)" "$before" "$(cat "$(mark_of "$real_note")")"
out=$(took "$(live)" 'a/b' "$note")
has "took: номер сессии не из SESSION_ID — предупреждён, в строке «session sA»" "session sA (pid" "$(told)"
lacks "took: негодный номер сессии не печатается" "a/b" "$(told)"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print([r["session"] for r in d["readers"]][-1])' "$(mark_of "$real_note")" >"$work/last-session" 2>&1
same "took: без годного номера сессии — session null" "None" "$(cat "$work/last-session")"
D=$(live); out=$(took "$D" sD "$note")
has "took: читатель без номера сессии — «a session»" ", a session (pid " "$(told)"

# --- took: мёртвые и непроверенные читатели
reset; closed_note; A=$(live)
mark_file "$real_note" "[$(reader_json "900001:$dead_started" sGone),$(reader_json "$me_pid:Thu Jan 1 00:00:00 2026" sOld),$(reader_json "$me" sMe)]"
mkdir -p "$taken"; for r in "900001:$dead_started" "$me_pid:Thu Jan 1 00:00:00 2026" "$me"; do printf '{}' >"$taken/$(reads_of "$r")"; done
out=$(took "$A" sA "$note")
same "took: номер без процесса и тот же номер с другим временем запуска убраны, живой остался" "$me_pid/sMe $(pid_of "$A")/sA" "$(readers_of "$real_note")"
same "took: о мёртвых — ни слова" "Hats handoff: 1 other live session(s) reading this note: $(item_of "$me" sMe)" "$(told)"
if [ ! -e "$taken/$(reads_of "900001:$dead_started")" ] && [ ! -e "$taken/$(reads_of "$me_pid:Thu Jan 1 00:00:00 2026")" ]; then ok; else bad "took: .reads мёртвых читателей удалены" "$(ls "$taken")"; fi
if [ -e "$taken/$(reads_of "$me")" ]; then ok; else bad "took: .reads живого читателя цел" "$(ls "$taken")"; fi
reset; closed_note; A=$(live)
mark_file "$real_note" "[$(reader_json "900001:$dead_started" sGone),$(reader_json "$me_pid:Thu Jan 1 00:00:00 2026" sOld)]"
out=$(took "$A" sA "$note")
empty "took: все прежние читатели мертвы — тишина, как у первого читателя" "$out$(heard)"
has "took: все прежние читатели мертвы — исход took" "outcome=took live=0 unknown=0 warned=False" "$(tl outcome live unknown warned)"
same "took: все прежние читатели мертвы — убраны, новый записан" "$(pid_of "$A")/sA" "$(readers_of "$real_note")"
reset; closed_note; A=$(live); mark_file "$real_note" "[$(reader_json "$me" sMe)]"; mkps 'exit 1'
out=$(took "$A" sA "$note" PATH="$work/psbin:$PATH"); facts="could not check 1 other session(s) that read this note: $(item_of "$me" sMe)"
same "took: живой номер, ps — код 1 без вывода — «could not check», а не «live»" "Hats handoff: $facts" "$(told)"
same "took: непроверенный — модели та же просьба подтверждения" "[handoff] $facts. $ask_took" "$out"
same "took: непроверенный читатель остался в файле" "$me_pid/sMe $(pid_of "$A")/sA" "$(readers_of "$real_note")"
has "took: непроверенный — журнал" "outcome=took-shared live=0 unknown=1 warned=True" "$(tl outcome live unknown warned)"
reset; closed_note; A=$(live); mark_file "$real_note" "[$(reader_json "$me" sMe)]"; mkps 'sleep 10'
ms=$(took_ms "$A" sA "$note" PATH="$work/psbin:$PATH")
same "took: ps молчит — «could not check»" "Hats handoff: $facts" "$(told)"
if [ "$ms" -le 3000 ]; then ok; else bad "took: ps молчит — хук в срок, ps спит 10 с" "${ms} мс"; fi
reset; closed_note; A=$(live); S=$(live)
mark_file "$real_note" "[$(reader_json "$me" sMe),$(reader_json "$S" sS 2026-11-13T09:42:00Z)]"
mkps "case \" \$* \" in *\" $(pid_of "$S") \"*) sleep 10 ;; esac; exec /bin/ps \"\$@\""
out=$(took "$A" sA "$note" PATH="$work/psbin:$PATH")
same "took: живой и непроверенный — одной строкой, непроверенный отдельными словами" \
  "Hats handoff: 1 other live session(s) reading this note: $(item_of "$me" sMe); could not check 1 more: $(item_of "$S" sS 2026-11-13T09:42:00Z)" "$(told)"
has "took: живой и непроверенный — журнал" "outcome=took-shared live=1 unknown=1" "$(tl outcome live unknown)"
reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe 2026-13-45T99:00:00Z)]"
out=$(start startup); lacks "список: читатель с негодным временем — пометки нет" "reading it" "$out$(told)"
A=$(live); out=$(took "$A" sA "$note")
empty "took: читатель с временем 2026-13-45T99:00:00Z отброшен — предупреждения нет" "$out$(heard)"
same "took: плохой читатель выброшен, новый записан" "$(pid_of "$A")/sA" "$(readers_of "$real_note")"

# --- took: гонки — три читателя через блокировку, ps вне блокировки
reset; closed_note; A=$(live); B=$(live); C=$(live); sig="$work/sig"; rm -rf "$sig" "$work/ra" "$work/rb"; mkdir -p "$sig"
run_took "$(took_in sA "$note")" "$A" "$work/ra" HANDOFF_TEST_PAUSE=0.6 HANDOFF_TEST_TAKEN_SIGNAL="$sig" & ra=$!
wait_for '[ -n "$(ls "$sig" | grep "\.locked$")" ]'
run_took "$(took_in sB "$note")" "$B" "$work/rb" HANDOFF_TEST_TAKEN_SIGNAL="$sig" & rb=$!
wait_for '[ "$(ls "$sig" | grep -c "\.waiting$")" -eq 2 ]'; locked=$(ls "$sig" | grep -c '\.locked$'); a_alive=$(kill -0 "$ra" 2>/dev/null && echo yes)
wait "$ra"; wait "$rb"
if [ "$locked" -eq 1 ] && [ "$a_alive" = yes ]; then ok; else bad "гонка: B доказанно ждёт блокировку, пока её держит A" "locked=$locked A жив=${a_alive:-нет}"; fi
out=$(judged "$work/ra" "гонка A"); empty "гонка: A — без предупреждения" "$out$(heard)"
at_a=$(at_of "$real_note" "$A")
out=$(judged "$work/rb" "гонка B"); same "гонка: B — об A, записавшемся после снимка B" "Hats handoff: 1 other live session(s) reading this note: $(item_of "$A" sA "$at_a")" "$(told)"
at_b=$(at_of "$real_note" "$B")
out=$(took "$C" sC "$note")
same "гонка: C после замены A — об A и B" "Hats handoff: 2 other live session(s) reading this note: $(item_of "$A" sA "$at_a"), $(item_of "$B" sB "$at_b")" "$(told)"
same "гонка: три читателя" "$(pid_of "$A")/sA $(pid_of "$B")/sB $(pid_of "$C")/sC" "$(readers_of "$real_note")"
reset; closed_note; D=$(live); X=$(live); Y=$(live); rm -rf "$work/rx" "$work/ry"
mark_file "$real_note" "[$(reader_json "$(pid_of "$D"):Thu Jan 1 00:00:00 2026" sD)]"
mkps "case \" \$* \" in *\" $(pid_of "$D") \"*) sleep 0.6 ;; esac; exec /bin/ps \"\$@\""
run_took "$(took_in sX "$note")" "$X" "$work/rx" PATH="$work/psbin:$PATH" & rx=$!
run_took "$(took_in sY "$note")" "$Y" "$work/ry" PATH="$work/psbin:$PATH" & ry=$!
wait "$rx"; wait "$ry"
judged "$work/rx" "ps 0,6 с, X" >/dev/null; tx=$(told); judged "$work/ry" "ps 0,6 с, Y" >/dev/null; ty=$(told)
r=" $(readers_of "$real_note") "
has "ps 0,6 с для одного номера, два took разом — X записан" " $(pid_of "$X")/sX " "$r"
has "ps 0,6 с для одного номера, два took разом — Y записан" " $(pid_of "$Y")/sY " "$r"
lacks "ps 0,6 с: мёртвый (другое время запуска) убран" "/sD" "$r"
if { [ -z "$tx" ] && [ -n "$ty" ]; } || { [ -n "$tx" ] && [ -z "$ty" ]; }; then ok; else bad "ps 0,6 с: предупреждён ровно один — второй" "X «${tx}» Y «${ty}»"; fi
case "$tx$ty" in "Hats handoff: 1 other live session(s) reading this note: session s"[XY]" (pid "*) ok ;; *) bad "ps 0,6 с: второй — о первом" "«${tx}${ty}»" ;; esac
reset; closed_note; D=$(live); X=$(live); Y=$(live); rm -rf "$work/rx" "$work/ry"
mark_file "$real_note" "[$(reader_json "$D" sD)]"
mkps "case \" \$* \" in *\" $(pid_of "$D") \"*) sleep 0.6 ;; esac; exec /bin/ps \"\$@\""
run_took "$(took_in sX "$note")" "$X" "$work/rx" PATH="$work/psbin:$PATH" & rx=$!
run_took "$(took_in sY "$note")" "$Y" "$work/ry" PATH="$work/psbin:$PATH" & ry=$!
wait "$rx"; wait "$ry"
judged "$work/rx" "ps 0,6 с, живой, X" >/dev/null; tx=$(told); judged "$work/ry" "ps 0,6 с, живой, Y" >/dev/null; ty=$(told)
lacks "ps вне блокировки: живой с медленным ps у обоих проверен — не «could not check»" "could not check" "$tx$ty"
case "$tx|$ty" in
  "Hats handoff: 1 other live session(s) reading this note: session sD "*"|Hats handoff: 2 other live session(s) reading this note: session sD "*", session sX "*) ok ;;
  "Hats handoff: 2 other live session(s) reading this note: session sD "*", session sY "*"|Hats handoff: 1 other live session(s) reading this note: session sD "*) ok ;;
  *) bad "ps вне блокировки: первый — о живом, второй — о живом и о первом" "X «${tx}» Y «${ty}»" ;;
esac
same "ps вне блокировки: все трое в файле" "3" "$(readers_of "$real_note" | wc -w | tr -d ' ')"
reset; closed_note; A=$(live); mark_file "$real_note" "[$(reader_json "$me" sMe)]"; mkps 'sleep 10'
holder=$(hold_lock "$markers/runs.lock" 8)
ms=$(took_ms "$A" sA "$note" PATH="$work/psbin:$PATH"); kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
if [ "$ms" -le 3500 ]; then ok; else bad "took: медленный ps (10 с) и занятая runs.lock (8 с) — не дольше 3,5 с" "${ms} мс"; fi
has "took: медленный ps — предупреждение «could not check» напечатано" "could not check 1 other session(s) that read this note" "$(user_of <"$work/ms.out")"
has "took: занятая runs.lock — строка журнала дописана" "outcome=took-shared unknown=1" "$(tl outcome unknown)"

# --- took: stdout не принимает — печать сдаётся за 0,3 с, took другой записки записан
# Порядок по событиям, не по времени: B стартует первым и до блокировки проверяет своего читателя R; этот ps
# отмечает «B готов» и ждёт, пока A возьмёт блокировку. A стартует только после этой отметки, поэтому B приходит
# к блокировке, пока A держит её и пытается печатать, как бы медленно ни стартовали оба. Порядок доказывают
# времена файлов, а не опрос.
reset; closed_note; printf '## NOW\n\nвторая\n' >"$mem/n2.md"; closed_note b "$mem/n2.md" "вторая"
A=$(live); B=$(live); R=$(live); mark_file "$real_note" "[$(reader_json "$me" sMe)]"; mark_file "$real_mem/n2.md" "[$(reader_json "$R" sR)]"
sig="$work/sig"; rm -rf "$sig" "$work/rb"; mkdir -p "$sig/a" "$sig/b"
mkps "case \" \$* \" in *\" $(pid_of "$R") \"*) : >\"$sig/b.ready\"; for i in \$(seq 1 250); do ls \"$sig/a/\"*.locked >/dev/null 2>&1 && break; sleep 0.02; done ;; esac; exec /bin/ps \"\$@\""
filler=$(fill_fifo "$work/full")
run_took "$(took_in sB "$mem/n2.md")" "$B" "$work/rb" HANDOFF_TEST_TAKEN_SIGNAL="$sig/b" PATH="$work/psbin:$PATH" & fb=$!
wait_for '[ -f "$sig/b.ready" ]' || bad "заполненный stdout: B дошёл до проверки читателя" "нет $sig/b.ready за 5 с"
( took_in sA "$note" | timeout 10 env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$A" HANDOFF_TEST_TAKEN_SIGNAL="$sig/a" python3 -I "$HOOK" took >"$work/full" 2>"$work/full.err"; echo $? >"$work/full.rc" ) & fa=$!
wait "$fa"; wait "$fb"; kill "$filler" 2>/dev/null; wait "$filler" 2>/dev/null
has "заполненный stdout: печать не удалась — not-printed" "command=took outcome=not-printed warned=False" "$(tls sA command outcome warned)"
a_ms=$(tls sA ms); a_ms=${a_ms#ms=}
if [ "$a_ms" -ge 250 ] && [ "$a_ms" -le 1200 ]; then ok; else bad "заполненный stdout: печать сдалась за 0,3 с" "${a_ms} мс"; fi
same "заполненный stdout: читатель не записан" "$me_pid/sMe" "$(readers_of "$real_note")"
if [ "$(cat "$work/full.rc")" = 0 ] && [ ! -s "$work/full.err" ]; then ok; else bad "заполненный stdout: код 0, stderr пуст" "rc=$(cat "$work/full.rc") $(head -c 200 "$work/full.err")"; fi
same "заполненный stdout: временных файлов не осталось" "0" "$(tmp_left)"
order=$(python3 -I -c 'import glob,os,sys
sig, rc = sys.argv[1:3]
def at(pattern):
    found = glob.glob(os.path.join(sig, pattern))
    return os.stat(found[0]).st_mtime_ns if found else None
a_locked, b_waiting, b_locked, a_end = at("a/*.locked"), at("b/*.waiting"), at("b/*.locked"), os.stat(rc).st_mtime_ns
print("ok" if None not in (a_locked, b_waiting, b_locked) and a_locked < b_waiting < a_end and b_locked > a_locked else
      "a_locked=%s b_waiting=%s b_locked=%s a_end=%s" % (a_locked, b_waiting, b_locked, a_end))' "$sig" "$work/full.rc")
same "заполненный stdout: took другой записки ждал блокировку, пока A держал её и пытался печатать" "ok" "$order"
out=$(judged "$work/rb" "заполненный stdout, B")
same "заполненный stdout: took другой записки записан" "$(pid_of "$R")/sR $(pid_of "$B")/sB" "$(readers_of "$real_mem/n2.md")"
has "заполненный stdout: took другой записки — took-shared" "outcome=took-shared live=1" "$(tls sB outcome live)"
rm -f "$work/full" "$work/full.ready"

# --- took: тихие пути — ни строки, ни журнала, ни папки состояния
reset; rm -rf "$work/.claude/state"; A=$(live)
out=$(took "$A" sA "$note" HANDOFF_OFF=1); empty "took: HANDOFF_OFF=1 — тишина" "$out$(heard)"
out=$(EXTRA=',"agent_id":"a1b2"' took "$A" sA "$note"); empty "took: подагент — тишина" "$out$(heard)"
out=$(EXTRA=',"agent_id":""' took "$A" sA "$note"); empty "took: подагент с пустым agent_id — тишина" "$out$(heard)"
out=$(took "$A" sA "$note" CLAUDE_CODE_SESSION_ATTENDED=0); empty "took: без человека — тишина" "$out$(heard)"
out=$(took "$A" sA "$note" CLAUDE_CODE_SESSION_ATTENDED=0 CLAUDE_CODE_ENTRYPOINT=sdk-cli); empty "took: без человека, sdk — тишина" "$out$(heard)"
out=$(took "$A" sA "$note"); empty "took: отметок нет — тишина" "$out$(heard)"
if [ ! -e "$work/.claude/state" ]; then ok; else bad "took: тихие пути — папки состояния нет и не появилась" "$(ls -R "$work/.claude/state" | head -5)"; fi
reset; closed_note; A=$(live); printf 'x\n' >"$mem/note.txt"; printf 'x\n' >"$mem/MEMORY.md"; printf 'x\n' >"$mem/resume-index.md"
printf 'x\n' >"$proj/n.md"; printf 'x\n' >"$mem/other.md"; printf 'x\n' >"$mem/Resume-Index.MD"
holder=$(hold_lock "$markers/runs.lock" 30)
for case_ in "HANDOFF_OFF=1|$note|HANDOFF_OFF=1" "подагент|$note|-" "без человека|$note|CLAUDE_CODE_SESSION_ATTENDED=0" "не .md|$mem/note.txt|-" \
             "MEMORY.md|$mem/MEMORY.md|-" "resume-index.md|$mem/resume-index.md|-" "служебное имя в другом регистре|$mem/Resume-Index.MD|-" \
             "вне памяти и папки записок|$proj/n.md|-" "ни одна отметка не указывает|$mem/other.md|-"; do
  IFS='|' read -r label f extra <<<"$case_"
  set -- ; [ "$extra" = - ] || set -- "$extra"
  if [ "$label" = подагент ]; then ms=$(EXTRA=',"agent_id":"a1"' took_ms "$A" sQ "$f"); else ms=$(took_ms "$A" sQ "$f" "$@"); fi
  if [ "$ms" -le 1000 ] && [ ! -s "$work/ms.out" ] && [ ! -e "$trace" ]; then ok
  else bad "took: $label — тишина, runs.log не тронут, значит занятую runs.lock не ждали" "${ms} мс, $(ls -A "$markers"), $(head -c 200 "$work/ms.out")"; fi
done
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
if [ ! -e "$trace" ] && [ ! -e "$taken" ]; then ok; else bad "took: тихие пути — runs.log и taken/ не появились" "$(ls -A "$markers")"; fi

# --- took: плохой вход — тишина и bad-input
reset; closed_note
for case_ in "не JSON|not json" "не объект|[1]" "пусто|" \
             "hook_event_name не PostToolUse|{\"hook_event_name\":\"Stop\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$note\"},\"session_id\":\"b1\"}" \
             "tool_name не Read|{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$note\"},\"session_id\":\"b1\"}" \
             "file_path не абсолютный|{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"note.md\"},\"session_id\":\"b1\"}" \
             "file_path нет|{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{},\"session_id\":\"b1\"}" \
             "tool_input не объект|{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":\"$note\",\"session_id\":\"b1\"}"; do
  label=${case_%%|*}; out=$(raw_took "${case_#*|}")
  empty "took: плохой вход ($label) — тишина" "$out$(heard)"
  has "took: плохой вход ($label) — bad-input в журнале" "command=took outcome=bad-input" "$(tl command outcome)"
done
if [ ! -e "$taken" ]; then ok; else bad "took: плохой вход — taken/ не создан" "есть"; fi
out=$(raw_took "$(python3 -I -c 'print("[" * 100000 + "]" * 100000)')")
has "took: вход с глубокой вложенностью — bad-input" "outcome=bad-input" "$(tl outcome)"

# --- took: перебор меток — 600 чужих, FIFO и большая метка, срок посреди перебора
reset; closed_note zzz; A=$(live); B=$(live)
python3 -I -c 'import json,os,sys
folder, mem, cwd = sys.argv[1:4]
for i in range(600):
    note = os.path.join(mem, "other%03d.md" % i)
    open(note, "w").write("x\n")
    json.dump({"pid": 99000 + i, "started": "Thu Jan 1 00:00:00 2026", "cwd": cwd, "note": note, "topic": "t", "saved_at": "2026-11-13T09:00:00Z"}, open(os.path.join(folder, "m%03d.json" % i), "w"))' "$markers" "$mem" "$proj"
mkfifo "$markers/0pipe.json"
python3 -I -c 'import json,sys; json.dump({"pid":1,"started":"x","cwd":sys.argv[2],"note":sys.argv[3],"topic":"t" * 70000,"saved_at":"2026-11-13T09:00:00Z"},open(sys.argv[1],"w"))' "$markers/0big.json" "$proj" "$note"
cp "$markers/0big.json" "$work/big.before"
out=$(took "$A" sA "$note")
has "took: 600 меток других записок, FIFO и метка больше 64 КБ, метка записки последней — записан" "outcome=took" "$(tl outcome)"
same "took: перебор меток — читатель записан" "$(pid_of "$A")/sA" "$(readers_of "$real_note")"
if [ -p "$markers/0pipe.json" ] && cmp -s "$markers/0big.json" "$work/big.before"; then ok; else bad "took: FIFO и большая метка не тронуты" "-"; fi
out=$(took "$B" sB "$note" HANDOFF_TEST_BUDGET=0.004)
empty "took: срок кончился посреди меток — тишина" "$out$(heard)"
has "took: срок кончился посреди меток — incomplete" "outcome=incomplete session=sB" "$(tl outcome session)"
same "took: incomplete — не записан" "$(pid_of "$A")/sA" "$(readers_of "$real_note")"
rm -f "$markers/0pipe.json"

# --- took: прочие пути записки — память-ссылка, регистр букв, своя папка, жёсткая ссылка
reset; mkdir -p "$work/vault" "$work/.claude/projects/-linked"; ln -s "$work/vault" "$work/.claude/projects/-linked/memory"
printf '## NOW\n\nпо ссылке\n' >"$work/vault/n.md"; linked="$work/.claude/projects/-linked/memory/n.md"; real_linked=$(realp "$work/vault/n.md")
closed_note a "$linked" "по ссылке"; A=$(live); B=$(live)
out=$(took "$A" sA "$linked")
same "память-ссылка: читатель записан под настоящим путём записки" "$(pid_of "$A")/sA" "$(readers_of "$real_linked")"
upper="$work/.claude/projects/-LINKED/MEMORY/n.md"; [ -e "$upper" ] || upper="$linked"
out=$(took "$B" sB "$upper")
has "память-ссылка, чтение в другом регистре букв — предупреждён об A" "session sA (pid $(pid_of "$A")" "$(told)"
same "память-ссылка и другой регистр — один ключ, один файл пометки" "1" "$(ls "$taken" | grep -c '\.json$')"
same "память-ссылка и другой регистр — оба в одном файле" "$(pid_of "$A")/sA $(pid_of "$B")/sB" "$(readers_of "$real_linked")"
C=$(live); out=$(took "$C" sC "$work/vault/n.md")
empty "граница: записка памяти-ссылки по настоящему пути вне projects не ловится" "$out$(heard)"
reset; own_dir=$(notes_of "$proj"); printf '## NOW\n\nсвоя\n' >"$own_dir/r.md"; closed_note a "$own_dir/r.md" "своя папка"; A=$(live); B=$(live)
out=$(took "$A" sA "$own_dir/r.md")
same "своя папка записок: читатель записан" "$(pid_of "$A")/sA" "$(readers_of "$(realp "$own_dir/r.md")")"
shouty=$(printf '%s' "$own_dir" | sed 's|/Hats/notes/|/HATS/NOTES/|'); [ -e "$shouty/r.md" ] || shouty="$own_dir"
out=$(took "$B" sB "$shouty/r.md")
same "своя папка записок в другом регистре — тот же файл пометки" "$(pid_of "$A")/sA $(pid_of "$B")/sB" "$(readers_of "$(realp "$own_dir/r.md")")"
reset; A=$(live); printf '## NOW\n\nжёсткая\n' >"$mem/a.md"; ln "$mem/a.md" "$mem/b.md"
marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$mem/a.md" "своя"; closed_note m2 "$mem/b.md" "вторая"
out=$(took "$A" sA "$mem/a.md")
same "жёсткая ссылка с двумя метками: читатель в обоих файлах" "$(pid_of "$A")/sA|$(pid_of "$A")/sA" "$(readers_of "$real_mem/a.md")|$(readers_of "$real_mem/b.md")"
same "жёсткая ссылка: два ключа в своём списке" "2" "$(keys_of "$A" | wc -w | tr -d ' ')"
sid=j1; out=$(start clear "$proj" HANDOFF_PROCESS="$A")
has "жёсткая ссылка: /clear отдаёт A его записку" "continues the note \"своя\"" "$out"
same "жёсткая ссылка: после /clear A в обоих файлах" "$(pid_of "$A")/sA|$(pid_of "$A")/sA" "$(readers_of "$real_mem/a.md")|$(readers_of "$real_mem/b.md")"
has "жёсткая ссылка: /clear — читатель уже был, выписки нет" "outcome=gave-note cleared=0 reader=again" "$(tl outcome cleared reader)"
out=$(CMP=0 start startup)
has "жёсткая ссылка: startup через вторую метку показывает A" "\"вторая\" — $real_mem/b.md
   1 live session(s) reading it: $(item_of "$A" sA "$(at_of "$real_mem/a.md" "$A")")" "$(told)"

# --- took: Read → save той же записки → Read другим процессом
reset; closed_note; out=$(took "$me" s1 "$note")
save "$proj" "$note" "та же" >/dev/null
same "save не пишет в taken/: файл пометки цел" "$me_pid/s1" "$(readers_of "$real_note")"
B=$(live); out=$(took "$B" sB "$note")
same "после save той же записки — другой процесс предупреждён" "Hats handoff: 1 other live session(s) reading this note: $(item_of "$me" s1 "$(at_of "$real_note" "$me")")" "$(told)"

# --- took: не записан — блокировка, fcntl, taken, временный файл, os.replace
reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe)]"; A=$(live); cp "$(mark_of "$real_note")" "$work/mark.before"
want_user="Hats handoff: 1 other live session(s) reading this note: $(item_of "$me" sMe)"
holder=$(hold_lock "$taken/.lock" 8)
ms=$(took_ms "$A" sA "$note"); kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
same "блокировка занята — предупреждение по прочитанному" "$want_user" "$(told)"
has "блокировка занята — not-recorded" "outcome=not-recorded reason=lock-busy warned=True" "$(tl outcome reason warned)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before" && [ ! -e "$taken/$(reads_of "$A")" ]; then ok; else bad "блокировка занята — файл не тронут, .reads нет" "$(ls -A "$taken")"; fi
if [ "$ms" -le 3000 ]; then ok; else bad "блокировка занята — ждёт не дольше срока, держатель держит 8 с" "${ms} мс"; fi
out=$(took "$A" sA "$note"); same "блокировка свободна — следующее чтение предупреждает снова" "$want_user" "$(told)"
has "блокировка свободна — записан" "outcome=took-shared" "$(tl outcome)"
reset; closed_note; A=$(live); B=$(live); mark_file "$real_note" "[$(reader_json "$A" sA),$(reader_json "$B" sB)]"
holder=$(hold_lock "$taken/.lock" 4)
out=$(took "$A" sA "$note"); kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
empty "блокировка занята, A уже читатель вместе с живым B — повторное чтение молчит" "$out$(heard)"
has "блокировка занята, A уже читатель — warned=False" "outcome=not-recorded reason=lock-busy warned=False" "$(tl outcome reason warned)"
reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe)]"; A=$(live); cp "$(mark_of "$real_note")" "$work/mark.before"
: >"$work/lock-target"; ln -s "$work/lock-target" "$taken/.lock"
out=$(took "$A" sA "$note")
same "блокировка не открылась (.lock — ссылка) — предупреждение по прочитанному" "$want_user" "$(told)"
has "блокировка не открылась — not-recorded" "outcome=not-recorded reason=lock-not-opened warned=True" "$(tl outcome reason warned)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before" && [ ! -e "$taken/$(reads_of "$A")" ] && [ -L "$taken/.lock" ]; then ok
else bad "блокировка не открылась — файл не тронут, .reads нет, ссылка цела" "$(ls -A "$taken")"; fi
reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe)]"; A=$(live); cp "$(mark_of "$real_note")" "$work/mark.before"
same "нет fcntl: took предупреждает по прочитанному" "$want_user" "$(nofcntl "$(took_in sA "$note")" "$A" took | user_of)"
has "нет fcntl: took не записывает" "command=took outcome=not-recorded reason=no-locking warned=True" "$(tl command outcome reason warned)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before" && [ ! -e "$taken/.lock" ]; then ok; else bad "нет fcntl: файл не тронут, блокировка не создана" "$(ls -A "$taken")"; fi
out=$(nofcntl "{\"session_id\":\"nf\",\"cwd\":\"$proj\",\"source\":\"startup\"}" "$own" start)
has "нет fcntl: список с пометкой" "   1 live session(s) reading it: $(item_of "$me" sMe). $ask_list" "$(printf '%s' "$out" | model_of)"
reset; closed_note; rm -rf "$work/taken-target"; mkdir -p "$work/taken-target"; ln -s "$work/taken-target" "$taken"; A=$(live)
out=$(took "$A" sA "$note")
has "taken — ссылка: не записан" "outcome=not-recorded reason=taken-not-folder" "$(tl outcome reason)"
if [ -L "$taken" ] && [ -z "$(ls -A "$work/taken-target")" ]; then ok; else bad "taken — ссылка: ссылка цела, за ней пусто" "$(ls -A "$work/taken-target")"; fi
rm -rf "$work/taken-target"
reset; closed_note; rm -rf "$work/taken-target" "$work/taken-before"; mkdir -p "$work/taken-target"; ln -s "$work/taken-target" "$taken"
printf '{"note":"%s","readers":[%s]}' "$real_note" "$(reader_json "$me" sMe)" >"$work/taken-target/$(key_of "$real_note").json"
printf '{"pid":%s,"started":"%s","keys":["%s"]}' "$me_pid" "$me_started" "$(key_of "$real_note")" >"$work/taken-target/$(reads_of "$me")"
: >"$work/taken-target/.lock"; cp -R "$work/taken-target" "$work/taken-before"
out=$(CMP=0 start startup)
has "taken — ссылка: список — пользователю «could not check whether»" "1. \"закрытая\" — $real_note
   could not check whether another session is reading it" "$(told)"
has "taken — ссылка: список — модели «could not check whether»" "   could not check whether another session is reading it. $ask_list" "$out"
sid=t1; start clear "$proj" HANDOFF_PROCESS="$me" >/dev/null
has "taken — ссылка: /clear — clear_error=taken-not-folder" "outcome=no-own-marker cleared=0 clear_error=taken-not-folder" "$(tl outcome cleared clear_error)"
if [ -L "$taken" ] && diff -r "$work/taken-before" "$work/taken-target" >/dev/null; then ok; else bad "taken — ссылка: startup и /clear не тронули файлы за ссылкой" "$(ls -A "$work/taken-target")"; fi
rm -rf "$work/taken-target" "$work/taken-before"
reset; closed_note; printf 'x' >"$taken"; A=$(live); out=$(took "$A" sA "$note")
has "taken — не папка: не записан" "outcome=not-recorded reason=taken-not-folder" "$(tl outcome reason)"
same "taken — не папка: файл не тронут" "x" "$(cat "$taken")"
if [ "$(id -u)" -ne 0 ]; then
  reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe)]"; : >"$taken/.lock"; A=$(live); chmod 500 "$taken"
  out=$(took "$A" sA "$note"); chmod 700 "$taken"
  same "временный файл не создать — предупреждение" "$want_user" "$(told)"
  has "временный файл не создать — not-recorded" "outcome=not-recorded reason=temp warned=True" "$(tl outcome reason warned)"
fi
reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe)]"; A=$(live); cp "$(mark_of "$real_note")" "$work/mark.before"
out=$(took "$A" sA "$note" HANDOFF_TEST_FAIL=replace)
same "os.replace упал после печати — предупреждён" "$want_user" "$(told)"
has "os.replace упал — not-recorded" "outcome=not-recorded reason=replace warned=True" "$(tl outcome reason warned)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before" && [ ! -e "$taken/$(reads_of "$A")" ] && [ "$(tmp_left)" -eq 0 ]; then ok
else bad "os.replace упал — файл не тронут, .reads нет, временных нет" "$(ls -A "$taken")"; fi
out=$(took "$A" sA "$note"); same "os.replace упал — следующее чтение предупреждает снова" "$want_user" "$(told)"

# --- took: вместимость — ровно 100 с мёртвыми, 100 живых
reset; closed_note; A=$(live); S=$(live)
list=$(python3 -I -c 'import json,sys
dead = [{"pid": 900001 + i, "started": "Thu Jan 1 00:00:00 2026", "session": "d%d" % i, "at": "2026-11-13T09:00:00Z"} for i in range(98)]
me_pid, me_started, s_pid, s_started = sys.argv[1:5]
live = [{"pid": int(me_pid), "started": me_started, "session": "sMe", "at": "2026-11-13T09:40:00Z"},
        {"pid": int(s_pid), "started": s_started, "session": "sS", "at": "2026-11-13T09:42:00Z"}]
print(json.dumps(dead + live))' "$me_pid" "$me_started" "$(pid_of "$S")" "${S#*:}")
mark_file "$real_note" "$list"; out=$(took "$A" sA "$note")
same "ровно 100 записей, 98 мёртвых — мёртвые убраны, новый записан" "$me_pid/sMe $(pid_of "$S")/sS $(pid_of "$A")/sA" "$(readers_of "$real_note")"
has "ровно 100 записей — took-shared о двух живых" "outcome=took-shared live=2" "$(tl outcome live)"
reset; closed_note
hundred=$(python3 -I -c 'import json,subprocess,sys
procs = [subprocess.Popen(["sleep", "300"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True) for _ in range(100)]
pids = [p.pid for p in procs]
open(sys.argv[1], "a").write("".join("%d\n" % p for p in pids))
out = subprocess.run(["ps", "-o", "pid=,lstart=", "-p", ",".join(map(str, pids))], capture_output=True, text=True, env={"TZ": "UTC", "LC_ALL": "C", "PATH": "/bin:/usr/bin"}).stdout
starts = {int(line.split()[0]): " ".join(line.split()[1:]) for line in out.splitlines() if line.strip()}
print(json.dumps([{"pid": p, "started": starts[p], "session": "h%d" % i, "at": "2026-11-13T09:41:00Z"} for i, p in enumerate(pids)]))' "$work/sleepers")
mark_file "$real_note" "$hundred"; cp "$(mark_of "$real_note")" "$work/mark.before"; Z=$(live)
out=$(took "$Z" sZ "$note")
has "100 живых — предупреждён" "Hats handoff: " "$(told)"
has "100 живых — список обрезан хвостом «and K more»" " more" "$(told)"
has "100 живых — модели та же просьба" "$ask_took" "$out"
has "100 живых — not-recorded, full" "outcome=not-recorded reason=full warned=True" "$(tl outcome reason warned)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before" && [ ! -e "$taken/$(reads_of "$Z")" ]; then ok; else bad "100 живых — файл не тронут, .reads нет" "-"; fi

# --- took: файл пометки или свой .reads нечитаем — тишина, не тронут; список — «could not check whether»
for kind in link fifo big many reads; do
  reset; closed_note; A=$(live); mkdir -p "$taken"; f=$(mark_of "$real_note")
  case $kind in
    link) printf '{"note":"%s","readers":[%s]}' "$real_note" "$(reader_json "$me" sMe)" >"$work/target.json"; ln -s "$work/target.json" "$f" ;;
    fifo) mkfifo "$f" ;;
    big) python3 -I -c 'import json,sys; json.dump({"note":sys.argv[2],"readers":[],"pad":"x" * 70000},open(sys.argv[1],"w"))' "$f" "$real_note" ;;
    many) python3 -I -c 'import json,sys; json.dump({"note":sys.argv[2],"readers":[{"pid":900001 + i,"started":"x","session":"m","at":"2026-11-13T09:00:00Z"} for i in range(101)]},open(sys.argv[1],"w"))' "$f" "$real_note" ;;
    reads) mkfifo "$taken/$(reads_of "$A")" ;;
  esac
  [ -f "$f" ] && ! [ -L "$f" ] && cp "$f" "$work/mark.before"
  out=$(took "$A" sA "$note")
  empty "нечитаемо ($kind): took — тишина" "$out$(heard)"
  has "нечитаемо ($kind): not-recorded" "outcome=not-recorded reason=unreadable" "$(tl outcome reason)"
  case $kind in
    link) if [ -L "$f" ]; then ok; else bad "нечитаемо (link): ссылка цела" "-"; fi ;;
    fifo) if [ -p "$f" ]; then ok; else bad "нечитаемо (fifo): канал цел" "-"; fi ;;
    reads) if [ -p "$taken/$(reads_of "$A")" ] && [ ! -e "$f" ]; then ok; else bad "нечитаемо (reads): свой .reads цел, файла пометки нет" "$(ls -A "$taken")"; fi ;;
    *) if cmp -s "$f" "$work/mark.before"; then ok; else bad "нечитаемо ($kind): файл не тронут" "-"; fi ;;
  esac
  [ "$kind" = reads ] && continue
  out=$(CMP=0 start startup)
  has "нечитаемо ($kind): список — пользователю" "1. \"закрытая\" — $real_note
   could not check whether another session is reading it" "$(told)"
  has "нечитаемо ($kind): список — модели" "   could not check whether another session is reading it. $ask_list" "$out"
done

# --- took: процесс не определён, исключение
reset; closed_note; A=$(live); mkps 'exit 1'
out=$(took "$A" sA "$note" HANDOFF_TEST=0 PATH="$work/psbin:$PATH")
empty "took: процесс не определён — тишина" "$out$(heard)"
has "took: процесс не определён — no-process" "command=took outcome=no-process" "$(tl command outcome)"
if [ ! -e "$taken" ]; then ok; else bad "took: процесс не определён — taken/ не создан" "есть"; fi
reset; closed_note; A=$(live)
out=$(harness_took "$A" sA "$note" 'def broken(*args):
    raise RuntimeError("boom")
swap("find_snapshot", broken)')
empty "took: исключение — тишина" "$out$(heard)"
has "took: исключение — в журнале тип и текст" "command=took outcome=error error=RuntimeError message=boom" "$(tl command outcome error message)"

# --- took: команда из hooks.json как есть через sh -c
reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe)]"; A=$(live); plugin_at "$plugin_root/hooks/hooks.json" yes
took_line=$(python3 -I -c 'import json,os,sys; groups=json.load(open(os.path.join(sys.argv[1],"hooks","hooks.json")))["hooks"]["PostToolUse"]; print([h["command"] for g in groups for h in g["hooks"] if "handoff.py" in h["command"]][0])' "$plugin_root")
call=$(mktemp -d "$work/call.XXXXXX"); took_in sh1 "$note" >"$call/in"
env CLAUDE_PLUGIN_ROOT="$plug" HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$A" sh -c "$took_line" <"$call/in" >"$call/out" 2>"$call/err"; echo $? >"$call/rc"
out=$(judged "$call" "took из hooks.json через sh -c"); rm -rf "$call"
same "hooks.json: команда took как есть через sh -c предупреждает" "$want_user" "$(told)"
has "hooks.json: команда took через sh -c — модели" "[handoff] 1 other live session(s) reading this note" "$out"

# --- пометка в списке новой сессии
reset; closed_note; start startup >/dev/null
if [ ! -e "$taken" ]; then ok; else bad "startup не создаёт taken/" "есть"; fi
mark_file "$real_note" "[$(reader_json "900001:$dead_started" sGone)]"; cp "$(mark_of "$real_note")" "$work/mark.before"
start startup >/dev/null
same "список: все читатели мертвы — как в 8b" "Hats handoff: 1 note from closed sessions in this folder:
1. \"закрытая\" — $real_note" "$(told)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before" && [ ! -e "$taken/.lock" ]; then ok; else bad "startup не пишет в taken/" "$(ls -A "$taken")"; fi
printf 'not json' >"$(mark_of "$real_note")"; start startup >/dev/null
same "список: файл пометки битый — как в 8b" "Hats handoff: 1 note from closed sessions in this folder:
1. \"закрытая\" — $real_note" "$(told)"
has "список без пометок — в журнале 0" "outcome=listed marks=0 marks_dropped=0" "$(tl outcome marks marks_dropped)"
mark_file "$real_note" "[$(reader_json "$me" sMe)]"; cp "$(mark_of "$real_note")" "$work/mark.before"
out=$(CMP=0 start startup)
same "список: живая сессия читает — пользователю строка под записью" "Hats handoff: 1 note from closed sessions in this folder:
1. \"закрытая\" — $real_note
   1 live session(s) reading it: $(item_of "$me" sMe)" "$(told)"
has "список: модели — пометка после строки записки" "1. \"закрытая\" — saved $(markerfield "$markers" saved_at): $real_note
   1 live session(s) reading it: $(item_of "$me" sMe). $ask_list" "$out"
has "список: пометка — в журнале" "outcome=listed marks=1 marks_dropped=0" "$(tl outcome marks marks_dropped)"
old=$(printf '{"session_id":"s","cwd":"%s","source":"startup"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$work/before/run.py" "$OLD_HOOK")
same "список: без строки пометки — прежний текст символ в символ" "$old" "$(printf '%s\n' "$out" | grep -v '^   1 live session(s) reading it: ')"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before"; then ok; else bad "список с пометкой — файл не тронут" "-"; fi
mkps 'exit 1'; out=$(CMP=0 start startup "$proj" PATH="$work/psbin:$PATH")
same "список: непроверенный читатель — отдельными словами" "Hats handoff: 1 note from closed sessions in this folder:
1. \"закрытая\" — $real_note
   could not check 1 session(s) that read it: $(item_of "$me" sMe)" "$(told)"
has "список: непроверенный — модели та же просьба" "   could not check 1 session(s) that read it: $(item_of "$me" sMe). $ask_list" "$out"
S=$(live); mark_file "$real_note" "[$(reader_json "$me" sMe),$(reader_json "$S" sS 2026-11-13T09:42:00Z)]"
mkps "case \" \$* \" in *\" $(pid_of "$S") \"*) sleep 10 ;; esac; exec /bin/ps \"\$@\""
out=$(CMP=0 start startup "$proj" PATH="$work/psbin:$PATH" HANDOFF_TEST_BUDGET=1)
has "список: живой и непроверенный" "   1 live session(s) reading it: $(item_of "$me" sMe); could not check 1 more: $(item_of "$S" sS 2026-11-13T09:42:00Z)" "$(told)"
list=$(python3 -I -c 'import json,sys; print(json.dumps([{"pid": int(sys.argv[1]), "started": "x%d" % i, "session": "reader-with-a-long-name-%02d" % i, "at": "2026-11-13T09:41:00Z"} for i in range(20)]))' "$me_pid")
mark_file "$real_note" "$list"; mkps 'exit 1'; out=$(CMP=0 start startup "$proj" PATH="$work/psbin:$PATH")
fit=$(told | python3 -I -c 'import re,sys
lines = sys.stdin.read().split("\n")
mark = lines[2][3:] if len(lines) > 2 else ""
print("units=%s more=%s" % (len(mark.encode("utf-16-le")) // 2 <= 600, bool(re.search(r", and \d+ more$", mark))))')
same "список: читатели одной записки — до 600 знаков, дальше «and K more»" "units=True more=True" "$fit"
has "список: модели — все читатели" "reader-with-a-long-name-19" "$out"
reset; long=$(printf 'n%.0s' $(seq 1 240)); ttt=$(printf 't%.0s' $(seq 1 130))
for i in 1 2 3 4 5; do
  printf 'x\n' >"$mem/$i$long.md"; marker "m$i" $((99980 + i)) "$dead_started" "$proj" "$mem/$i$long.md" "$ttt" "2026-11-0${i}T10:00:00Z"
  case $i in 1|3|5) mark_file "$real_mem/$i$long.md" "[$(reader_json "$me" sMe)]" ;; esac
done
out=$(CMP=0 start startup)
tail_line=$(told | python3 -I -c 'import re,sys
text = sys.stdin.read()
lines = text.split("\n")
shown = {m.group(1) for m in (re.match(r"\d\. \".*\" — .*/(\d)n+\.md$", line) for line in lines) if m}
dropped = {"1", "2", "3", "4", "5"} - shown
read = dropped & {"1", "3", "5"}
want = "and %d more, %d of them being read by another session" % (len(dropped), len(read))
print("units=%s tail=%s mixed=%s" % (len(text.encode("utf-16-le")) // 2 <= 2000, lines[-1] == want, 0 < len(read) < len(dropped)))')
same "список: записки отброшены по пределу 2000 — хвост считает только помеченные среди отброшенных" "units=True tail=True mixed=True" "$tail_line"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "x"
base=$(printf '{"session_id":"s","cwd":"%s","source":"startup"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$work/before/run.py" "$OLD_HOOK" | python3 -I -c 'import sys; print(len(sys.stdin.read().encode("utf-16-le")) // 2)')
topic=$(python3 -I -c 'import sys; print("x" * (9440 - int(sys.argv[1])))' "$base")
marker a "$dead_pid" "$dead_started" "$proj" "$note" "$topic"; mark_file "$real_note" "[$(reader_json "$me" sMe)]"
out=$(start startup)
lacks "список: пометка не влезает в 9500 — модели её нет, прежний текст цел (сверка с образцом)" "reading it" "$out"
has "список: пометка не влезает — пользователю есть" "   1 live session(s) reading it: $(item_of "$me" sMe)" "$(told)"
has "список: пометка не влезает — marks_dropped" "outcome=listed marks=1 marks_dropped=1" "$(tl outcome marks marks_dropped)"
reset; closed_note; mark_file "$real_note" "[$(reader_json "$me" sMe)]"
out=$(printf '{"session_id":"mx","cwd":"%s","source":"startup"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I -c 'import os,sys
'"$swap_py"'
path = sys.argv[1]
scope = {
    "__name__": "hook",
    "__file__": path,
}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), scope)
def broken(*args):
    raise RuntimeError("marks")
swap("find_marks", broken)
sys.exit(scope["main"](["start"]))' "$HOOK" 2>&1)
has "исключение в пометках — список всё равно отдан" "\"закрытая\"" "$(printf '%s' "$out" | model_of)"
lacks "исключение в пометках — модели пометки нет" "reading it" "$(printf '%s' "$out" | model_of)"
lacks "исключение в пометках — пользователю пометки нет" "reading it" "$(printf '%s' "$out" | user_of)"
has "исключение в пометках — listed и marks_error" "outcome=listed marks=0 marks_error=RuntimeError" "$(tl outcome marks marks_error)"

# --- /clear: выписка на всех трёх путях
reset; A=$(live); printf '## NOW\n\nвторая\n' >"$mem/n2.md"
marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; closed_note b "$mem/n2.md" "вторая"
took "$A" sA "$mem/n2.md" >/dev/null; took "$A" sA "$note" >/dev/null
sid=c1; out=$(start clear "$proj" HANDOFF_PROCESS="$A")
has "/clear: своя записка отдана" "continues the note \"своя\"" "$out"
same "/clear: выписан из чужой записки, её файл без читателей удалён" "нет" "$(readers_of "$real_mem/n2.md")"
same "/clear: читатель записки, отданной этим /clear, остался" "$(pid_of "$A")/sA" "$(readers_of "$real_note")"
same "/clear: свой список — только ключ отданной записки" "$(key_of "$real_note")" "$(keys_of "$A")"
has "/clear: журнал — выписка и исход записи читателя" "outcome=gave-note cleared=1 reader=again receiver=new" "$(tl outcome cleared reader receiver)"
reset; closed_note; B=$(live); took "$B" sB "$note" >/dev/null
sid=c2; start clear "$proj" HANDOFF_PROCESS="$B" >/dev/null
same "/clear без своего якоря: выписан, пустой файл удалён" "нет" "$(readers_of "$real_note")"
if [ ! -e "$taken/$(reads_of "$B")" ]; then ok; else bad "/clear без своего якоря: .reads удалён" "есть"; fi
has "/clear без своего якоря — журнал" "outcome=no-own-marker cleared=1" "$(tl outcome cleared)"
reset; A=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; took "$A" sA "$note" >/dev/null
sid=h1; start clear "$proj" HANDOFF_PROCESS="$A" >/dev/null; sid=h2; start clear "$proj" HANDOFF_PROCESS="$A" >/dev/null
same "/clear, якорь отдан другой сессии: выписан и из своей записки" "нет" "$(readers_of "$real_note")"
has "/clear, отдан другой — журнал" "outcome=handed-elsewhere cleared=1" "$(tl outcome cleared)"
reset; sid=c4; start clear >/dev/null
if [ ! -e "$taken" ]; then ok; else bad "/clear: нет taken/ — выписка ничего не делает" "taken/ есть"; fi
has "/clear: нет taken/ — cleared=0 без ошибки" "outcome=no-own-marker cleared=0 clear_error=None" "$(tl outcome cleared clear_error)"
reset; closed_note; B=$(live); took "$B" sB "$note" >/dev/null; holder=$(hold_lock "$taken/.lock" 8)
sid=c3; start clear "$proj" HANDOFF_PROCESS="$B" >/dev/null; kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
has "/clear: блокировка выписки занята — clear_error" "outcome=no-own-marker cleared=0 clear_error=lock-busy" "$(tl outcome cleared clear_error)"
same "/clear: блокировка занята — читатель остался, следующий /clear попробует снова" "$(pid_of "$B")/sB" "$(readers_of "$real_note")"
ms=$(tl ms); ms=${ms#ms=}
if [ "$ms" -ge 450 ] && [ "$ms" -le 2000 ]; then ok; else bad "/clear: блокировка выписки ждётся до 0,5 с (время хука из runs.log, держатель держит 8 с)" "${ms} мс"; fi
rm -f "$taken/.lock"; sid=c5; start clear "$proj" HANDOFF_PROCESS="$B" >/dev/null
has "/clear: taken/ без .lock — выписка не создаёт блокировку, clear_error" "outcome=no-own-marker cleared=0 clear_error=lock-not-opened" "$(tl outcome cleared clear_error)"
if [ ! -e "$taken/.lock" ] && [ "$(readers_of "$real_note")" = "$(pid_of "$B")/sB" ]; then ok; else bad "/clear: без .lock — блокировка не появилась, читатель цел" "$(ls -A "$taken")"; fi
reset; closed_note; B=$(live); C=$(live); took "$C" sC "$note" >/dev/null; took "$B" sB "$note" >/dev/null; cp "$(mark_of "$real_note")" "$work/mark.before"
sid=c6; start clear "$proj" HANDOFF_PROCESS="$B" HANDOFF_TEST_FAIL=replace >/dev/null
has "/clear: перезапись файла пометки не удалась — cleared=0, clear_error=write" "outcome=no-own-marker cleared=0 clear_error=write" "$(tl outcome cleared clear_error)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before" && [ "$(tmp_left)" -eq 0 ]; then ok; else bad "/clear: перезапись не удалась — файл пометки не тронут, временных нет" "$(readers_of "$real_note"); $(ls -A "$taken")"; fi
same "/clear: перезапись не удалась — ключ остался в .reads" "$(key_of "$real_note")" "$(keys_of "$B")"
sid=c7; start clear "$proj" HANDOFF_PROCESS="$B" >/dev/null
same "/clear: следующий /clear выписывает снова" "$(pid_of "$C")/sC" "$(readers_of "$real_note")"
reset; mine; B=$(live); took "$B" sB "$note" >/dev/null; cp "$(mark_of "$real_note")" "$work/mark.before"
has "/clear без человека: текст 8b (сверка с образцом), без пометки" "continues the note" "$(nobody clear 0 sdk-cli)"
if cmp -s "$(mark_of "$real_note")" "$work/mark.before"; then ok; else bad "/clear без человека: ни записи, ни выписки" "$(readers_of "$real_note")"; fi

# --- /clear отдаёт свою записку: читатель, пометка первой строкой
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; mark_file "$real_note" "[$(reader_json "$B" sB)]"
sid=g1; out=$(CMP=0 start clear "$proj" HANDOFF_PROCESS="$A"); facts="1 live session(s) reading it: $(item_of "$B" sB)"
same "/clear: первая строка модели — пометка" "[handoff] $facts. $ask_took" "$(printf '%s\n' "$out" | sed -n 1p)"
old=$(printf '{"session_id":"g1","cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$A" python3 -I "$work/before/run.py" "$OLD_HOOK")
same "/clear: за пометкой — прежний текст символ в символ" "$old" "$(printf '%s\n' "$out" | sed 1d)"
same "/clear: пользователю — пометка под строкой 8b" "Hats handoff: continuing anchor \"своя\" — $real_note
   $facts" "$(told)"
same "/clear: процесс записан читателем после печати" "$(pid_of "$B")/sB $(pid_of "$A")/g1" "$(readers_of "$real_note")"
has "/clear: журнал — reader=took" "outcome=gave-note reader=took receiver=new" "$(tl outcome reader receiver)"
if [ -f "$markers/own.handed" ]; then ok; else bad "/clear: «отдано» записано после читателя" "own.handed нет"; fi
reset; rm -rf "$markers"; A=$(live)
env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$A" python3 -I "$HOOK" save --cwd "$proj" --note "$note" --topic свежая >/dev/null 2>&1
if [ -f "$markers/$(reads_of "$A" | sed 's/\.reads$/.json/')" ] && [ ! -e "$taken" ]; then ok; else bad "свежее состояние: save пишет отметку и не трогает taken/" "$(ls -A "$markers" 2>&1)"; fi
sid=f1; start clear "$proj" HANDOFF_PROCESS="$A" >/dev/null
has "свежее состояние: /clear без Read создаёт taken/ (700)" "0o700" "$(mode_of "$taken")"
has "свежее состояние: и taken/.lock (600)" "0o600" "$(mode_of "$taken/.lock")"
same "свежее состояние: /clear записал читателя" "$(pid_of "$A")/f1" "$(readers_of "$real_note")"
B=$(live); out=$(took "$B" sB "$note")
same "свежее состояние: Read другим процессом — предупреждён; автор, уже читатель, назван один раз" "Hats handoff: 1 other live session(s) reading this note: $(item_of "$A" f1 "$(at_of "$real_note" "$A")")" "$(told)"
reset; A=$(live); B=$(live); python3 -I -c 'print("## СЕЙЧАС\n"); print("\n".join("😀" * 60 for _ in range(110)))' >"$note"
marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "смайлы"; mark_file "$real_note" "[$(reader_json "$B" sB)]"
sid=e1; out=$(CMP=0 start clear "$proj" HANDOFF_PROCESS="$A")
case "$(printf '%s\n' "$out" | sed -n 1p)" in "[handoff] 1 live session(s) reading it: session sB (pid "*". $ask_took") ok ;; *) bad "полный вывод из эмодзи: пометка первой строкой" "$(printf '%s\n' "$out" | sed -n 1p | head -c 300)" ;; esac
units=$(printf '%s' "$out" | python3 -I -c 'import sys; print(len(sys.stdin.read().encode("utf-16-le")) // 2)')
if [ "$units" -le 9500 ]; then ok; else bad "полный вывод из эмодзи: не длиннее 9500 единиц UTF-16" "$units"; fi
has "полный вывод из эмодзи: режется хвост записки" "😀" "$out"
same "полный вывод из эмодзи: читатель записан" "$(pid_of "$B")/sB $(pid_of "$A")/e1" "$(readers_of "$real_note")"
reset; A=$(live); mkdir -p "$work/gitbin" "$work/repo"
printf '#!/bin/bash\nsleep 30\n' >"$work/gitbin/git"; chmod +x "$work/gitbin/git"
printf '## NOW\n\n- git %s main = abcdef1\n' "$work/repo" >"$note"; marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"
mkdir -p "$taken"; : >"$taken/.lock"; python3 -I -c 'import hashlib,json,os,sys
folder, me_pid, me_started, a_pid, a_started = sys.argv[1:6]
keys = []
for i in range(603):
    note = "/x/other-%03d.md" % i
    readers = [{"pid": int(me_pid), "started": me_started, "session": "sMe", "at": "2026-11-13T09:40:00Z"}]
    if i < 3:
        readers.append({"pid": int(a_pid), "started": a_started, "session": "sA", "at": "2026-11-13T09:41:00Z"})
    key = hashlib.sha256(os.fsencode(note)).hexdigest()
    json.dump({"note": note, "readers": readers}, open(os.path.join(folder, key + ".json"), "w"))
    if i < 3:
        keys.append(key)
open(os.path.join(folder, sys.argv[6]), "w").write(json.dumps({"pid": int(a_pid), "started": a_started, "keys": keys}))' \
  "$taken" "$me_pid" "$me_started" "$(pid_of "$A")" "${A#*:}" "$(reads_of "$A")"
sid=s1; out=$(CMP=0 start clear "$proj" PATH="$work/gitbin:$PATH" HANDOFF_TEST_BUDGET=2 HANDOFF_PROCESS="$A")
has "600 файлов и медленный git: записка отдана, git не успел" "no time to check" "$out"
has "600 файлов и медленный git: свои записи сняты" "cleared=3 clear_error=None" "$(tl cleared clear_error)"
gone=$(python3 -I -c 'import glob,json,os,sys
pid = int(sys.argv[2])
files = [p for p in glob.glob(os.path.join(sys.argv[1], "*.json"))]
print(sum(1 for p in files if any(r["pid"] == pid for r in json.load(open(p))["readers"]) and json.load(open(p))["note"].startswith("/x/")), len(files))' "$taken" "$(pid_of "$A")")
same "600 файлов и медленный git: A нет ни в одном чужом файле, файлы на месте" "0 604" "$gone"
same "600 файлов: свой список — только отданная записка" "$(key_of "$real_note")" "$(keys_of "$A")"
pkill -f "$work/gitbin/git" 2>/dev/null
reset; A=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; filler=$(fill_fifo "$work/full")
( printf '{"session_id":"np","cwd":"%s","source":"clear"}' "$proj" | timeout 10 env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$A" python3 -I "$HOOK" start >"$work/full" 2>"$work/full.err"; echo $? >"$work/full.rc" )
kill "$filler" 2>/dev/null; wait "$filler" 2>/dev/null
has "/clear, stdout не принимает — not-printed" "outcome=not-printed reader=not-printed" "$(tl outcome reader)"
if [ ! -e "$markers/own.handed" ] && [ "$(readers_of "$real_note")" = нет ] && [ "$(tmp_left)" -eq 0 ]; then ok; else bad "/clear не напечатан — ни читателя, ни «отдано», ни временных файлов" "$(ls -A "$markers" "$taken")"; fi
if [ "$(cat "$work/full.rc")" = 0 ] && [ ! -s "$work/full.err" ]; then ok; else bad "/clear не напечатан — код 0, stderr пуст" "rc=$(cat "$work/full.rc")"; fi
rm -f "$work/full" "$work/full.ready"
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; took "$B" sB "$note" >/dev/null; holder=$(hold_lock "$taken/.lock" 4)
sid=k1; out=$(CMP=0 start clear "$proj" HANDOFF_PROCESS="$A" HANDOFF_TEST_BUDGET=1.2); kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
has "/clear, блокировка не взята — печать по снимку" "[handoff] 1 live session(s) reading it: $(item_of "$B" sB "$(at_of "$real_note" "$B")")" "$(printf '%s\n' "$out" | sed -n 1p)"
has "/clear, блокировка не взята — читатель не записан" "outcome=gave-note reader=not-recorded reason=lock-busy" "$(tl outcome reader reason)"
same "/clear, блокировка не взята — в файле только B" "$(pid_of "$B")/sB" "$(readers_of "$real_note")"
if [ -f "$markers/own.handed" ]; then ok; else bad "/clear, блокировка не взята — напечатано, значит «отдано» записано" "own.handed нет"; fi
for kind in big fifo; do
  reset; A=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; mkdir -p "$taken"; f=$(mark_of "$real_note")
  case $kind in
    big) python3 -I -c 'import json,sys; json.dump({"note":sys.argv[2],"readers":[],"pad":"x" * 70000},open(sys.argv[1],"w"))' "$f" "$real_note"; cp "$f" "$work/mark.before" ;;
    fifo) mkfifo "$f" ;;
  esac
  sid=u1; out=$(CMP=0 start clear "$proj" HANDOFF_PROCESS="$A")
  same "/clear, файл пометки своей записки нечитаем ($kind): первая строка модели — «could not check whether»" \
    "[handoff] could not check whether another session is reading it. $ask_took" "$(printf '%s\n' "$out" | sed -n 1p)"
  has "/clear, нечитаем ($kind): читатель не записан" "outcome=gave-note reader=not-recorded reason=unreadable" "$(tl outcome reader reason)"
  if [ -f "$markers/own.handed" ]; then ok; else bad "/clear, нечитаем ($kind): напечатано, значит «отдано» записано" "own.handed нет"; fi
  if { [ "$kind" = fifo ] && [ -p "$f" ]; } || { [ "$kind" = big ] && cmp -s "$f" "$work/mark.before"; }; then ok; else bad "/clear, нечитаем ($kind): файл пометки не тронут" "$(ls -lA "$taken")"; fi
done
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; mark_file "$real_note" "[$(reader_json "$B" sB)]"
out=$(printf '{"session_id":"x1","cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$A" python3 -I -c 'import os,sys
'"$swap_py"'
path = sys.argv[1]
scope = {
    "__name__": "hook",
    "__file__": path,
}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), scope)
def broken(*args):
    raise RuntimeError("snapshot")
swap("find_snapshot", broken)
sys.exit(scope["main"](["start"]))' "$HOOK" 2>&1)
old=$(printf '{"session_id":"x1","cwd":"%s","source":"clear"}' "$proj" | env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$A" python3 -I "$work/before/run.py" "$OLD_HOOK")
same "/clear, исключение в снимке читателей — модели текст 8b символ в символ" "$old" "$(printf '%s' "$out" | model_of)"
same "/clear, исключение в снимке — пользователю строка 8b без пометки" "Hats handoff: continuing anchor \"своя\" — $real_note" "$(printf '%s' "$out" | user_of)"
has "/clear, исключение в снимке — reader=error" "outcome=gave-note reader=error marks_error=RuntimeError" "$(tl outcome reader marks_error)"

# --- took: живой автор записки (запись 63) — отдельная строка; свой процесс, закрытый и непроверенный молчат
since_of() { python3 -I -c 'import sys; from datetime import datetime; print(datetime.strptime(sys.argv[1].partition(":")[2], "%a %b %d %H:%M:%S %Y").strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
author_of() { printf 'pid %s (since %s)' "$(pid_of "$1")" "$(since_of "$1")"; }
still_open='the session that saved this note is still open: '
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"
out=$(took "$B" sB "$note")
same "автор жив, B читает впервые — пользователю строка об авторе" "Hats handoff: $still_open$(author_of "$A")" "$(told)"
same "автор жив — модели строка об авторе и просьба подтверждения" "[handoff] $still_open$(author_of "$A"). $ask_took" "$out"
has "автор жив — журнал" "outcome=took-shared live=0 unknown=0 authors=1 warned=True" "$(tl outcome live unknown authors warned)"
same "автор жив — автор не записан читателем" "$(pid_of "$B")/sB" "$(readers_of "$real_note")"
out=$(took "$B" sB2 "$note")
empty "автор жив, B читает второй раз — тишина" "$out$(heard)"
has "автор жив, второе чтение — again" "outcome=again" "$(tl outcome)"
reset; A=$(live); C=$(live); B=$(live); marker a1 "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; marker a2 "$(pid_of "$C")" "${C#*:}" "$other" "$note" "та же"
out=$(took "$B" sB "$note")
same "два живых автора — оба в строке" "Hats handoff: $still_open$(author_of "$A"), $(author_of "$C")" "$(told)"
has "два живых автора — журнал" "authors=2" "$(tl authors)"
reset; A=$(live); D=$(live); B=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; mark_file "$real_note" "[$(reader_json "$D" sD)]"
out=$(took "$B" sB "$note")
same "живой автор и живой читатель — две строки пользователю" "Hats handoff: $still_open$(author_of "$A")
Hats handoff: 1 other live session(s) reading this note: $(item_of "$D" sD)" "$(told)"
same "живой автор и живой читатель — две строки модели, просьба одна" "[handoff] $still_open$(author_of "$A").
[handoff] 1 other live session(s) reading this note: $(item_of "$D" sD). $ask_took" "$out"
reset; A=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"
out=$(took "$A" sA "$note")
empty "читает сам автор — о себе ни слова" "$out$(heard)"
has "читает сам автор — took, authors=0" "outcome=took live=0 unknown=0 authors=0 warned=False" "$(tl outcome live unknown authors warned)"
reset; A=$(live); D=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; mark_file "$real_note" "[$(reader_json "$D" sD)]"
out=$(took "$A" sA "$note")
same "читает сам автор при живом читателе — только о читателе" "Hats handoff: 1 other live session(s) reading this note: $(item_of "$D" sD)" "$(told)"
reset; closed_note; B=$(live); out=$(took "$B" sB "$note")
empty "автор закрыт — тишина" "$out$(heard)"
has "автор закрыт — authors=0" "outcome=took authors=0" "$(tl outcome authors)"
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; mkps 'exit 1'
out=$(took "$B" sB "$note" PATH="$work/psbin:$PATH")
empty "автор не проверен (ps — код 1) — о нём ни слова" "$out$(heard)"
has "автор не проверен — authors=0" "outcome=took authors=0" "$(tl outcome authors)"
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "Thu Nov 20 10:00:00 2026" "$proj" "$note" "своя"
mkps "case \" \$* \" in *\" $(pid_of "$A") \"*) echo 'Thu Nov 20 10:00:00 2026'; exit 0 ;; esac; exec /bin/ps \"\$@\""
out=$(took "$B" sB "$note" PATH="$work/psbin:$PATH")
same "время запуска автора — в формате меток (записано руками)" "Hats handoff: ${still_open}pid $(pid_of "$A") (since 2026-11-20T10:00:00Z)" "$(told)"
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "not a start time" "$proj" "$note" "своя"
mkps "case \" \$* \" in *\" $(pid_of "$A") \"*) echo 'not a start time'; exit 0 ;; esac; exec /bin/ps \"\$@\""
out=$(took "$B" sB "$note" PATH="$work/psbin:$PATH")
same "время запуска автора не разбирается — как напечатал ps" "Hats handoff: ${still_open}pid $(pid_of "$A") (since not a start time)" "$(told)"
reset; A=$(live); B=$(live); marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "своя"; mkdir -p "$taken"
holder=$(hold_lock "$taken/.lock" 8)
took_ms "$B" sB "$note" >/dev/null; kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
same "блокировка занята — строка об авторе по снимку" "Hats handoff: $still_open$(author_of "$A")" "$(told)"
has "блокировка занята, автор жив — not-recorded, warned" "outcome=not-recorded reason=lock-busy warned=True authors=1" "$(tl outcome reason warned authors)"
out=$(took "$B" sB "$note")
same "блокировка свободна — следующее чтение говорит снова" "Hats handoff: $still_open$(author_of "$A")" "$(told)"

# --- папка записок слушает HATS_STATE_HOME (запись 77)
xs="$work/xstate"
xenv() { env HOME="$work" HATS_STATE_HOME="$xs" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" "$@"; }
reset; mkdir -p "$xs"; base_dir=$(notes_of "$proj")
x_dir=$(xenv python3 -I "$HOOK" where --cwd "$proj" 2>&1)
same "HATS_STATE_HOME: where — <HATS_STATE_HOME>/notes/<проект>" "$xs/notes/${base_dir##*/}" "$x_dir"
x_note=$(xenv python3 -I "$HOOK" new --slug t --cwd "$proj" 2>&1)
same "HATS_STATE_HOME: new — записка в той же папке" "$x_dir/resume-t.md" "$x_note"
printf '# T\n\n## NOW\n\nиз временной папки\n' >"$x_note"
out=$(xenv python3 -I "$HOOK" save --cwd "$proj" --note "$x_note" --topic "временная" 2>&1)
has "HATS_STATE_HOME: save признаёт записку" "marker:" "$out"
has "HATS_STATE_HOME: start после /clear отдаёт записку" "из временной папки" "$(CMP=0 start clear "$proj" HATS_STATE_HOME="$xs")"
empty "HATS_STATE_HOME снят: та же отметка — записки нет" "$(CMP=0 start clear "$proj")"
A=$(live); out=$(took "$A" sA "$x_note" HATS_STATE_HOME="$xs")
has "HATS_STATE_HOME: took признаёт записку" "command=took outcome=took" "$(tl command outcome)"
same "HATS_STATE_HOME: took записал читателя" "$(pid_of "$A")/sA" "$(readers_of "$(realp "$x_note")")"
out=$(env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" save --cwd "$proj" --note "$x_note" --topic x 2>&1)
has "без HATS_STATE_HOME записка временной папки — не записка" "the note must be a file" "$out"
dir=$(env HOME="$work" HATS_STATE_HOME= python3 -I "$HOOK" where --cwd "$proj" 2>&1)
same "HATS_STATE_HOME пустой — прежняя папка" "$base_dir" "$dir"
for value in "relative/state" "~/tilde" "./x"; do
  for command in where new; do
    args=(--cwd "$proj"); [ "$command" = new ] && args+=(--slug t)
    dir=$(cd "$proj" && env HOME="$work/rel-home" HATS_STATE_HOME="$value" python3 -I "$HOOK" "$command" "${args[@]}" 2>&1); rc=$?
    same "HATS_STATE_HOME «${value}»: $command отказывает одной строкой, код 1" \
      "1 handoff: HATS_STATE_HOME='$value' is not an absolute path, so there is no Hats folder" "$rc $dir"
  done
  first=${value#./}; first=${first%%/*}
  if [ ! -e "$work/rel-home" ] && [ ! -e "$proj/$first" ]; then ok
  else bad "HATS_STATE_HOME «${value}»: ни в HOME, ни в папке запуска ничего не создано" \
    "$(ls -a "$proj" "$work/rel-home" 2>&1 | head -5)"; fi
done
printf 'share 73%%\n' >"$base_dir/x.md"; printf 'share 74%%\n' >"$x_dir/y.md"
printf 'x (cite: %s:1 "share 73%%")\n' "$base_dir/x.md" >"$proj/n.md"
has "HATS_STATE_HOME: цитата прежней папки — не источник" "quote of the notes folder is not a source" "$(env HOME="$work" HATS_STATE_HOME="$xs" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1)"
printf 'x (cite: %s:1 "share 74%%")\n' "$x_dir/y.md" >"$proj/n.md"
has "HATS_STATE_HOME: цитата новой папки — не источник" "quote of the notes folder is not a source" "$(env HOME="$work" HATS_STATE_HOME="$xs" python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1)"
steps_general=$(env HOME="$work" HATS_STATE_HOME="$xs" python3 -I -B -c 'import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("handoff", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(os.path.dirname(module.get_notes_root()))' "$HOOK" 2>&1)
same "HATS_STATE_HOME: anchor-steps.json — в нём (папка над корнем записок)" "$xs" "$steps_general"

# --- хук allow (PreToolUse): Read — записка любой папки проекта корня, Write и Edit — только своей; иначе молчит
rm -rf "$work/proc"; mkdir -p "$work/proc/4242"; ln -s "$proj" "$work/proc/4242/cwd"
allow_in() { printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s"},"session_id":"s1","cwd":"%s"}' "$1" "$2" "$proj"; }
allow() {  # allow <инструмент> <путь> [env...] — stdout хука; процесс Claude 4242 в папке $proj; код — в $work/allow.rc, stderr — в $work/allow.err
  local t="$1" f="$2"; shift 2
  allow_in "$t" "$f" | env HOME="$work" HATS_STATE_HOME="$xs" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_PROC="$work/proc" "$@" \
    python3 -I "$HOOK" allow 2>"$work/allow.err"; echo $? >"$work/allow.rc"
}
decision_of() { python3 -I -c 'import json,sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    h = d["hookSpecificOutput"]
    print("%s %s %s" % (sorted(d), h["hookEventName"], h["permissionDecision"]))
except Exception:
    print("не тот вывод: %r" % raw[:200])'; }
quiet_ok() { if [ -z "$2" ] && [ "$(cat "$work/allow.rc")" = 0 ] && [ ! -s "$work/allow.err" ]; then ok; else bad "$1" "«${2:0:200}» rc=$(cat "$work/allow.rc") $(head -c 200 "$work/allow.err")"; fi; }
allowed="['hookSpecificOutput'] PreToolUse allow"
for tool in Write Edit Read; do
  out=$(allow "$tool" "$x_dir/n.md")
  same "allow: $tool записки своей папки проекта — allow" "$allowed" "$(printf '%s' "$out" | decision_of)"
  if [ "$(cat "$work/allow.rc")" = 0 ] && [ ! -s "$work/allow.err" ]; then ok; else bad "allow: $tool — код 0, stderr пуст" "rc=$(cat "$work/allow.rc")"; fi
done
foreign="$xs/notes/0123456789abcdef"; mkdir -p "$foreign"; printf '## NOW\n\nчужая\n' >"$foreign/f.md"
same "allow: Read записки другой папки проекта корня — allow" "$allowed" "$(allow Read "$foreign/f.md" | decision_of)"
quiet_ok "allow: Write в другую папку проекта корня — молчание" "$(allow Write "$foreign/f.md")"
quiet_ok "allow: Edit в другой папке проекта корня — молчание" "$(allow Edit "$foreign/f.md")"
quiet_ok "allow: Write в папку проекта, которой ещё нет — молчание" "$(allow Write "$xs/notes/fedcba9876543210/new.md")"
quiet_ok "allow: Read в папке проекта, которой нет — молчание" "$(allow Read "$xs/notes/fedcba9876543210/new.md")"
if [ ! -e "$xs/notes/fedcba9876543210" ]; then ok; else bad "allow: папка проекта не создана хуком" "есть"; fi
printf 'вне\n' >"$work/hard-target.md"; ln "$work/hard-target.md" "$x_dir/hard.md"
quiet_ok "allow: Edit файла с жёсткой ссылкой наружу — молчание" "$(allow Edit "$x_dir/hard.md")"
quiet_ok "allow: Write поверх файла с жёсткой ссылкой — молчание" "$(allow Write "$x_dir/hard.md")"
same "allow: Read файла с жёсткой ссылкой — allow (Read ничего не меняет)" "$allowed" "$(allow Read "$x_dir/hard.md" | decision_of)"
printf '## NOW\n\nодна ссылка\n' >"$x_dir/single.md"
same "allow: Edit файла с одной ссылкой — allow" "$allowed" "$(allow Edit "$x_dir/single.md" | decision_of)"
quiet_ok "allow: путь вне корня — молчание" "$(allow Write "$proj/n.md")"
quiet_ok "allow: прежняя папка при HATS_STATE_HOME — молчание" "$(allow Read "$base_dir/x.md")"
quiet_ok "allow: не .md — молчание" "$(allow Write "$x_dir/n.txt")"
quiet_ok "allow: прямо в корне — молчание" "$(allow Write "$xs/notes/n.md")"
mkdir -p "$x_dir/sub"; quiet_ok "allow: подпапка проекта — молчание" "$(allow Write "$x_dir/sub/n.md")"
mkdir -p "$xs/notes/project"; quiet_ok "allow: папка не из 16 знаков hex — молчание" "$(allow Read "$xs/notes/project/n.md")"
quiet_ok "allow: .. наружу — молчание" "$(allow Write "$x_dir/../../../n.md")"
printf 'secret\n' >"$work/outside.md"; ln -s "$work/outside.md" "$x_dir/link.md"
quiet_ok "allow: ссылка наружу — молчание" "$(allow Read "$x_dir/link.md")"
mkdir -p "$x_dir/dir.md"; quiet_ok "allow: папка с именем .md — молчание" "$(allow Read "$x_dir/dir.md")"
quiet_ok "allow: HANDOFF_OFF=1 — молчание" "$(allow Write "$x_dir/n.md" HANDOFF_OFF=1)"
quiet_ok "allow: инструмент не из трёх — молчание" "$(allow Bash "$x_dir/n.md")"
quiet_ok "allow: путь не абсолютный — молчание" "$(allow Write "n.md")"
quiet_ok "allow: Write без процесса Claude в папке проекта — молчание" "$(allow Write "$x_dir/n.md" HANDOFF_TEST_PROC="$work/no-proc" HANDOFF_PROCESS="4243:$own_started")"
out=$(printf 'not json' | env HOME="$work" HATS_STATE_HOME="$xs" python3 -I "$HOOK" allow 2>"$work/allow.err"; echo $? >"$work/allow.rc")
quiet_ok "allow: ввод не JSON — молчание" "$out"
out=$(printf '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$x_dir/n.md" | env HOME="$work" HATS_STATE_HOME="$xs" python3 -I "$HOOK" allow 2>"$work/allow.err"; echo $? >"$work/allow.rc")
quiet_ok "allow: другое событие — молчание" "$out"
same "allow: без HATS_STATE_HOME — прежняя папка разрешена" "$allowed" "$(allow_in Read "$base_dir/x.md" | env -u HATS_STATE_HOME HOME="$work" python3 -I "$HOOK" allow | decision_of)"
same "allow: относительный HATS_STATE_HOME — корня нет, молчание" "" "$(allow_in Read "$base_dir/x.md" | env HOME="$work" HATS_STATE_HOME=relative python3 -I "$HOOK" allow 2>&1)"
same "allow: HATS_STATE_HOME с ~ — корня нет, молчание" "" "$(allow_in Read "$base_dir/x.md" | env HOME="$work" HATS_STATE_HOME="~/xstate" python3 -I "$HOOK" allow 2>&1)"
# --- без корня (HATS_STATE_HOME относительный): save, check, took и start не признают прежнюю папку записок
rel_state="relative/state"
renv() { env HOME="$work" HATS_STATE_HOME="$rel_state" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" "$@"; }
reset; base_dir=$(notes_of "$proj"); b_note="$base_dir/resume-b.md"
printf '# B\n\n## NOW\n\nиз прежней папки\n' >"$b_note"
before_markers=$(ls -A "$markers")
out=$(renv python3 -I "$HOOK" save --cwd "$proj" --note "$b_note" --topic b 2>&1); rc=$?
has "без корня: save записки прежней папки — отказ одной строкой, код 1" \
  "1 handoff: HATS_STATE_HOME='$rel_state' is not an absolute path, so there is no Hats folder: the note must be a file "\
"<Claude config>/projects/<folder>/memory/<name>.md, and " \
  "$rc $out"
same "без корня: save записки прежней папки — отметки нет" "$before_markers" "$(ls -A "$markers")"
out=$(renv python3 -I "$HOOK" save --cwd "$proj" --note "$note" --topic m 2>&1); rc=$?
has "без корня: save записки из памяти — отметка записана, код 0" "0 marker: $markers/" "$rc $out"
reset; base_dir=$(notes_of "$proj"); printf '# B\n\n## NOW\n\nиз прежней папки\n' >"$b_note"
printf 'share 75%%\n' >"$base_dir/q.md"; printf 'x (cite: %s:1 "share 75%%")\n' "$base_dir/q.md" >"$proj/n.md"
has "без корня: цитата прежней папки — не источник" "quote of the notes folder is not a source" \
  "$(renv python3 -I "$HOOK" check --cwd "$proj" "$proj/n.md" 2>&1)"
mine a "$proj" "$b_note"
A=$(live); out=$(took "$A" sA "$b_note" HATS_STATE_HOME="$rel_state")
same "без корня: took записки прежней папки — читатель не записан" "нет" "$(readers_of "$(realp "$b_note")")"
B=$(live); out=$(took "$B" sB "$b_note")
same "с корнем по умолчанию: took той же записки — читатель записан" "$(pid_of "$B")/sB" "$(readers_of "$(realp "$b_note")")"
lacks "без корня: start после /clear не отдаёт записку прежней папки" "из прежней папки" \
  "$(CMP=0 start clear "$proj" HATS_STATE_HOME="$rel_state")"
has "с корнем по умолчанию: та же отметка — записка отдаётся" "из прежней папки" "$(CMP=0 start clear "$proj")"
if [ ! -e "$proj/relative" ] && [ ! -e "$work/relative" ]; then ok
else bad "без корня: в папке запуска ничего не создано" "$(ls -a "$proj" "$work" | head -5)"; fi
hooks_allow=$(python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1]))
print([(e.get("matcher"), h["command"], h.get("timeout")) for e in d["hooks"].get("PreToolUse", []) for h in e["hooks"]])' "$plugin_root/hooks/hooks.json" 2>&1)
same "hooks.json: PreToolUse Write|Edit|Read → allow.sh, срок 5" "[('Write|Edit|Read', 'sh \"\${CLAUDE_PLUGIN_ROOT}/scripts/allow.sh\"', 5)]" "$hooks_allow"

# --- allow.sh: без «/notes/» во вводе Python не запускается
real_py=$(command -v python3); mkdir -p "$work/stubbin"
printf '#!/bin/sh\n: >>"%s"\nexec "%s" "$@"\n' "$work/py-called" "$real_py" >"$work/stubbin/python3"; chmod +x "$work/stubbin/python3"
mkdir -p "$work/allowkit/scripts"; cp "$plugin_root/scripts/allow.sh" "$plugin_root/scripts/py.sh" "$work/allowkit/scripts/"; put_hook "$work/allowkit/scripts"
run_allow_sh() { printf '%s' "$1" | env PATH="$work/stubbin:$PATH" HOME="$work" HATS_STATE_HOME="$xs" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" HANDOFF_TEST_PROC="$work/proc" sh "$work/allowkit/scripts/allow.sh" 2>"$work/allow.err"; echo $? >"$work/allow.rc"; }
rm -f "$work/py-called"; out=$(run_allow_sh "$(allow_in Read "$proj/README.md")")
quiet_ok "allow.sh: ввод без /notes/ — молчание, код 0" "$out"
if [ ! -e "$work/py-called" ]; then ok; else bad "allow.sh: ввод без /notes/ — Python не запускался" "заглушка python3 вызвана"; fi
rm -f "$work/py-called"; out=$(run_allow_sh "$(allow_in Read "$x_dir/n.md")")
same "allow.sh: записка папки записок — allow через Python" "$allowed" "$(printf '%s' "$out" | decision_of)"
if [ -e "$work/py-called" ]; then ok; else bad "allow.sh: ввод с /notes/ — Python запущен" "заглушка не вызвана"; fi
rm -f "$work/py-called"; out=$(run_allow_sh "$(allow_in Read "$proj/notes/n.md")")
quiet_ok "allow.sh: /notes/ вне корня — Python запущен и молчит" "$out"
if [ -e "$work/py-called" ]; then ok; else bad "allow.sh: /notes/ вне корня — проверку делает Python" "заглушка не вызвана"; fi

# --- запись 47: блок «Not verified» влезает при широких знаках (ECH2), нечитаемая записка не отдаётся (ECH6),
# внук в своей группе не держит хук (ECH7). Текст модели здесь отличается от образца намеренно — без сверки.
units_of() { python3 -I -c 'import sys; print(len(sys.stdin.read().encode("utf-16-le")) // 2)'; }
wide_note() { python3 -I -c 'print("## СЕЙЧАС\n"); print("\n".join("😀" * 60 for _ in range(110))); print("доля 37% проверки")' >"$note"; }
wide_problem='- line 113: number with no quote and no source'
reset; wide_note; mine
out=$(CMP=0 start clear)
has "широкие знаки, с человеком: блок «Not verified» на месте" "Not verified" "$out"
has "широкие знаки, с человеком: непроверенная строка названа" "$wide_problem" "$out"
has "широкие знаки, с человеком: конец выдержки на месте" "--- end of excerpt ---" "$out"
has "широкие знаки, с человеком: выдержка обрезана" "cut, the rest is in the file" "$out"
last_kept=$(printf '%s\n' "$out" | python3 -I -c 'import sys; lines = sys.stdin.read().split("\n"); i = lines.index("[… cut, the rest is in the file]"); print(len(lines[i - 1]) if lines[i - 1].strip("😀") == "" else "не эмодзи: %r" % lines[i - 1][:40])' 2>&1)
same "широкие знаки, с человеком: перед пометкой обрезки — целая строка записки (60 эмодзи)" "60" "$last_kept"
units=$(printf '%s' "$out" | units_of)
if [ "$units" -le 9500 ]; then ok; else bad "широкие знаки, с человеком: не длиннее 9500 единиц UTF-16" "$units"; fi
out=$(CMP=0 nobody clear 0 - | model_of)
has "широкие знаки, без человека: блок «Not verified» на месте" "Not verified" "$out"
has "широкие знаки, без человека: непроверенная строка названа" "$wide_problem" "$out"
has "широкие знаки, без человека: конец выдержки на месте" "--- end of excerpt ---" "$out"
units=$(printf '%s' "$out" | units_of)
if [ "$units" -le 9500 ]; then ok; else bad "широкие знаки, без человека: не длиннее 9500 единиц UTF-16" "$units"; fi
reset; A=$(live); B=$(live); wide_note
marker own "$(pid_of "$A")" "${A#*:}" "$proj" "$note" "смайлы"; mark_file "$real_note" "[$(reader_json "$B" sB)]"
sid=w1; out=$(CMP=0 start clear "$proj" HANDOFF_PROCESS="$A")
case "$(printf '%s\n' "$out" | sed -n 1p)" in "[handoff] 1 live session(s) reading it: session sB (pid "*". $ask_took") ok ;; *) bad "широкие знаки и читатель: пометка первой строкой" "$(printf '%s\n' "$out" | sed -n 1p | head -c 300)" ;; esac
has "широкие знаки и читатель: блок «Not verified» на месте" "Not verified" "$out"
has "широкие знаки и читатель: непроверенная строка названа" "$wide_problem" "$out"
has "широкие знаки и читатель: конец выдержки на месте" "--- end of excerpt ---" "$out"
units=$(printf '%s' "$out" | units_of)
if [ "$units" -le 9500 ]; then ok; else bad "широкие знаки и читатель: не длиннее 9500 единиц UTF-16" "$units"; fi
reset; mine; chmod 000 "$note"
if cat "$note" >/dev/null 2>&1; then
  skipped=$((skipped+6)); skips="$skips
  пропущено 6: записка читается и после chmod 000 (прогон под root) — нечитаемая записка не проверена"
else
  sid=u1; out=$(CMP=0 start clear)
  empty "нечитаемая своя записка: модели ничего" "$out"
  same "нечитаемая своя записка: пользователю — не прочесть" "Hats handoff: could not read the note of anchor \"задача А\", not given — $real_note" "$(told)"
  if [ ! -e "$markers/a.handed" ]; then ok; else bad "нечитаемая своя записка: «отдано» не записано" "a.handed есть"; fi
  has "нечитаемая своя записка: журнал — note-unreadable" "outcome=note-unreadable session=u1" "$(tl outcome session)"
  chmod 600 "$note"; sid=u2
  has "нечитаемая записка, права вернули: другая сессия получает" "continues the note \"задача А\"" "$(CMP=0 start clear)"
  reset; closed_note; chmod 000 "$note"; out=$(CMP=0 start startup)
  has "нечитаемая записка в списке: строка о том, что не читается" "   could not read the note: no permission, over the size limit or not a regular file" "$out"
  chmod 600 "$note"
fi
reset; : >"$note"; mine; sid=z1
has "пустая своя записка: отдаётся" "continues the note \"задача А\"" "$(CMP=0 start clear)"
has "пустая своя записка: журнал — gave-note" "outcome=gave-note session=z1" "$(tl outcome session)"
reset; : >"$note"; closed_note; out=$(CMP=0 start startup)
has "пустая записка в списке: в списке" "\"закрытая\"" "$out"
lacks "пустая записка в списке: не «could not read the note»" "could not read the note" "$out"
reset; closed_note; mkdir -p "$work/pgrpbin"; rm -f "$work/grandpids"
cat >"$work/pgrpbin/ps" <<EOF
#!/bin/bash
python3 -I -c 'import os,sys,time; os.setpgrp(); open(sys.argv[1], "a").write("%d\n" % os.getpid()); time.sleep(30)' "$work/grandpids" &
sleep 30
EOF
chmod +x "$work/pgrpbin/ps"
CMP=0 start startup "$proj" PATH="$work/pgrpbin:$PATH" HANDOFF_TEST_BUDGET=1 >/dev/null
same "внук ps в своей группе: пользователю «не успел проверить»" "Hats handoff: could not check 1 note in time, none listed" "$(told)"
ms=$(tl ms | sed 's/^ms=//')
case "$ms" in ''|*[!0-9]*) bad "внук ps в своей группе: время хука из runs.log" "ms=$ms" ;; *) if [ "$ms" -le 1700 ]; then ok; else bad "внук ps в своей группе: хук укладывается в срок (время из runs.log)" "${ms} мс при пороге 1700"; fi ;; esac
wait_for '[ -s "$work/grandpids" ]'
cat "$work/grandpids" >>"$work/sleepers" 2>/dev/null

# --- list --cwd (запись 87): тот же вывод, что start на startup, и ничего на диск
tree_of() { python3 -I -c 'import os,sys
for top in sys.argv[1:]:
    for folder, dirs, files in os.walk(top):
        dirs.sort()
        for name in sorted(dirs + files):
            path = os.path.join(folder, name)
            info = os.lstat(path)
            print(path, info.st_size, info.st_mtime_ns, oct(info.st_mode))' "$work/.claude" "$work/Library" "$mem"; }
list_raw() {  # list_raw [cwd] [env...] — stdout и код list
  local cwd="${1:-$proj}"; shift || true
  env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" "$@" python3 -I "$HOOK" list --cwd "$cwd" 2>&1; echo "rc=$?"
}
start_raw() {  # start_raw [cwd] — stdout и код start на startup, мимо помощника и сверки
  printf '{"session_id":"s","cwd":"%s","source":"startup"}' "${1:-$proj}" |
    env HOME="$work" HANDOFF_TEST=1 HANDOFF_PROCESS="$own" python3 -I "$HOOK" start 2>&1; echo "rc=$?"
}
list_matches() {  # list_matches <подпись> — list и start в одном состоянии печатают одно и то же, list ничего не пишет
  local before after listed started
  before=$(tree_of); listed=$(list_raw); after=$(tree_of)
  same "list: $1 — на диске ничего не изменилось" "$before" "$after"
  started=$(start_raw)
  same "list: $1 — тот же вывод, что start на startup" "$started" "$listed"
}
reset; list_matches "якорей нет"
out=$(list_raw); has "list: якорей нет — пользователю «закрытых нет»" "$told_no_closed" "$out"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"; list_matches "один якорь"
has "list: один якорь — модели список" "additionalContext" "$(list_raw)"
reset; for i in 1 2 3 4 5 6 7; do marker "m$i" $((99980 + i)) "$dead_started" "$proj" "$note" "тема $i"; done
list_matches "семь якорей"; has "list: семь якорей — две счётом" "and 2 more" "$(list_raw)"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"; chmod 000 "$note"
list_matches "нечитаемая записка"; has "list: нечитаемая записка — строка о ней" "could not read the note" "$(list_raw)"; chmod 600 "$note"
reset; marker a "$dead_pid" "$dead_started" "$proj" "$note" "закрытая"
before=$(tree_of); attended=$(list_raw "$proj"); unattended_out=$(list_raw "$proj" CLAUDE_CODE_SESSION_ATTENDED=0); after=$(tree_of)
same "list: без человека печатает то же, что с человеком" "$attended" "$unattended_out"
same "list: два запуска — на диске ничего" "$before" "$after"
if [ ! -e "$markers/runs.log" ] && [ ! -e "$markers/taken" ]; then ok; else bad "list: ни runs.log, ни taken/" "$(ls -a "$markers")"; fi
same "list: HANDOFF_OFF=1 — тишина" "rc=0" "$(list_raw "$proj" HANDOFF_OFF=1)"
out=$(env HOME="$work" python3 -I "$HOOK" list 2>&1); rc=$?
if [ $rc -eq 2 ] && [[ "$out" != *Traceback* ]] && [[ "$out" == *--cwd* ]]; then ok; else bad "list без --cwd — отказ argparse, код 2, без трассировки" "rc=$rc ${out:0:300}"; fi
out=$(env HOME="$work" python3 -I "$HOOK" list --cwd proj 2>&1); rc=$?
if [ $rc -eq 2 ] && [[ "$out" != *Traceback* ]] && [[ "$out" == *"absolute"* ]]; then ok; else bad "list с относительной папкой — отказ, код 2, без трассировки" "rc=$rc ${out:0:300}"; fi

# --- run: процесс, который не умирает и после SIGKILL (сон в ядре), не держит хук дольше REAP_TIMEOUT_S
out=$(python3 -I -B -c 'import subprocess, sys, time
sys.path.insert(0, sys.argv[1])
import handoff_consts, handoff_proc, handoff_state
waited = []
class Stuck:
    def __init__(self, *args, **kwargs):
        self.pid = 999999
        self.stdout = open("/dev/null")
    def communicate(self, timeout=None):
        raise subprocess.TimeoutExpired("x", timeout)
    def wait(self, timeout=None):
        waited.append(timeout)
        time.sleep(30 if timeout is None else min(timeout, 30))
        raise subprocess.TimeoutExpired("x", timeout)
handoff_proc.subprocess.Popen = Stuck
handoff_proc.os.killpg = lambda pid, sig: None
handoff_state.deadline = None
print(handoff_proc.run(["x"], 0.1), "no budget:", waited[-1] == handoff_consts.REAP_TIMEOUT_S)
handoff_state.deadline = time.monotonic() + 0.2
handoff_proc.run(["x"], 0.05)
print("part of the budget left:", 0.0 < waited[-1] <= 0.2)
handoff_state.deadline = time.monotonic()
handoff_proc.run(["x"], 0.05)
print("budget spent:", waited[-1] == 0.0)' "$plugin_root/scripts" 2>&1)
same "run: процесс, не умерший после SIGKILL, ждём не дольше REAP_TIMEOUT_S и остатка бюджета хука" "(None, None) no budget: True
part of the budget left: True
budget spent: True" "$out"

# --- README: как поставить плагин, как его выключить и что хук пишет на диск
readme=$(cat "$plugin_root/../README.md" 2>/dev/null)
has "README: как поставить плагин" "claude plugin install hats --marketplace zyuzka/hats" "$readme"
has "README: выключатель хука" "HANDOFF_OFF=1" "$readme"
has "README: что хук пишет на диск" "<config>/state/handoff/runs.log" "$readme"

# --- сверка: форма вывода каждого вызова через помощники и совпадение с образцом
if [ -s "$OLD_HOOK" ]; then ok; else bad "сверка: образец" "нет файла $OLD_HOOK"; fi
begun=0; [ -f "$work/compares.log" ] && begun=$(wc -l <"$work/compares.log" | tr -d ' ')
compared=$(awk -F'\t' '$2 == 1' "$work/checks.log" | wc -l | tr -d ' ')
if [ "$begun" -gt 0 ] && [ "$begun" -eq "$compared" ]; then ok; else bad "сверка: строк сверки столько, сколько вызовов её начало" "начали $begun, строк $compared"; fi
while IFS=$'\t' read -r verdict _ label problem; do
  if [ "$verdict" = ok ]; then ok; else bad "$label" "$problem"; fi
done <"$work/checks.log"

# --- модули: состояние читается только через handoff_state.<имя>; байт-код не пишется
state_imports=$(grep -nE "^[[:space:]]*from[[:space:]]+handoff_state[[:space:]]+import" "$work/loose"/*.py)
if [ -z "$state_imports" ]; then ok; else bad "никто не пишет «from handoff_state import» — копия значения не видит записей" "$state_imports"; fi
mkdir -p "$work/linked"; ln -s "$work/loose/handoff.py" "$work/linked/handoff.py"
linked=$(printf '{"session_id":"linked","cwd":"%s","source":"startup"}' "$work" | env HOME="$work" HANDOFF_TEST=1 python3 -I "$work/linked/handoff.py" start 2>&1); linked_rc=$?
if [ "$linked_rc" -eq 0 ] && [[ "$linked" != *ModuleNotFoundError* ]]; then ok
else bad "хук через символическую ссылку находит свои модули рядом с настоящим файлом" "rc=$linked_rc ${linked:0:300}"; fi
if [ ! -e "$work/loose/__pycache__" ]; then ok; else bad "байт-код не пишется рядом с хуком" "$(ls "$work/loose/__pycache__")"; fi

total=$((pass+fail))
if [ $skipped -gt 0 ]; then echo "handoff: пропущено $skipped$skips"; fi
if [ $fail -eq 0 ]; then echo "handoff: $pass/$total прошли"; exit 0; fi
echo "handoff: $pass/$total прошли, $fail упало$failures"; exit 1
