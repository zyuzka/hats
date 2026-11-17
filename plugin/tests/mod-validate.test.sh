#!/usr/bin/env bash
# Мод плагина глазами `claude plugin validate`: плагин и маркетплейс проходят проверку, а в том, что
# модуль слушает и зовёт, нет запрещённого планами задач 9 и 9b — `$.process`, `$.http`, `$.model`,
# `$.store`, `$.env.set`, таймера `$.clock.every` (будит сессию), хуков `classic.*` и
# `session.compact`, записи переменных окружения. `$.prompt.submit` и `$.clock.after` с задачи 9b
# разрешены: продолжение после своей /clear и ожидание снимка и передачи записки внутри цепочки
# очистки. Проверяется запрещённое, а не точный список вызовов. Сама проверка сломана руками в
# конце: копия плагина с каждым запрещённым вызовом или хуком обязана упасть.
#   bash plugin/tests/mod-validate.test.sh
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$root/.." && pwd)"
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/mod-validate-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }

if ! command -v claude >/dev/null 2>&1; then
  echo "mod-validate: claude не найден — проверка не запускалась"
  exit 2
fi

validate() {  # validate <folder> <output file>; код выхода — код claude plugin validate
  claude plugin validate "$1" >"$2" 2>&1
}

forbidden() {  # forbidden <output file>: печатает запрещённое, найденное в строках модуля
  python3 -I - "$1" <<'EOF'
import re
import sys

TIMERS = ("$.clock.every",)
text = open(sys.argv[1], encoding="utf-8").read()
calls = re.findall(r"register\.js calls: (.*)", text)
hooks = re.findall(r"register\.js hooks: (.*)", text)
writes = re.findall(r"register\.js env writes: (.*)", text)
found = []
if not calls or not hooks:
    found.append("no calls or hooks line")
for line in calls:
    for name in re.findall(r"\$\.[A-Za-z]+(?:\.[A-Za-z]+)?", line):
        if name.split(".")[1] in ("process", "http", "model", "store") or name in TIMERS + ("$.env.set",):
            found.append(name)
for line in hooks:
    for name in (part.strip() for part in line.split(",")):
        if name.startswith("classic.") or name == "session.compact":
            found.append(name)
for line in writes:
    if line.strip() != "nothing":
        found.append(f"env writes: {line.strip()}")
print("\n".join(found))
EOF
}

out="$work/plugin.txt"
if validate "$root" "$out" && grep -q "Validation passed" "$out"; then ok; else bad "плагин проходит validate" "$(tail -5 "$out")"; fi
if ! found=$(forbidden "$out"); then bad "фильтр запрещённого отработал" "${found:-пустой вывод}"
elif [ -z "$found" ]; then ok
else bad "в модуле нет запрещённого" "$found"; fi
if grep -q "register.js calls: .*\$.command.run" "$out"; then ok
else bad "строка calls: видна и называет \$.command.run" "$(grep 'calls:' "$out")"; fi
if grep -q "register.js calls: .*\$.prompt.read.*\$.prompt.submit" "$out" && grep -q 'register.js hooks: .*command.run' "$out"; then ok
else bad "строки calls: и hooks: называют \$.prompt.read, \$.prompt.submit и хук command.run" "$(grep 'calls:\|hooks:' "$out")"; fi

out="$work/market.txt"
if validate "$repo" "$out" && grep -q "Validation passed" "$out"; then ok; else bad "маркетплейс проходит validate" "$(tail -5 "$out")"; fi

broken() {  # broken <ожидаемая находка> <строка, вставленная первой в тело register>
  local copy="$work/broken-${1//[^A-Za-z]/-}"
  rm -rf "$copy"
  cp -R "$root" "$copy"
  python3 -I - "$copy/hooks/register.js" "$2" <<'EOF'
import sys

path, line = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
head = "export const register = on => {\n"
assert text.count(head) == 1, "register head not found"
open(path, "w", encoding="utf-8").write(text.replace(head, head + "  " + line + "\n"))
EOF
  local result="$copy.txt"
  validate "$copy" "$result"
  if forbidden "$result" | grep -qxF -- "$1"; then ok; else bad "проверка ловит: $1" "$(grep 'register.js\|✘' "$result" | head -3)"; fi
}

broken '$.store.get' "on('session.measure', async (\$, e, next) => { await \$.store.get('k'); return next(e) })"
broken '$.process.spawn' "on('session.measure', async (\$, e, next) => { await \$.process.spawn({ argv: ['true'] }); return next(e) })"
broken '$.http.fetch' "on('session.measure', async (\$, e, next) => { await \$.http.fetch({ url: 'https://a.b' }); return next(e) })"
broken '$.model.complete' "on('session.measure', async (\$, e, next) => { await \$.model.complete({ messages: [] }); return next(e) })"
broken '$.env.set' "on('session.measure', async (\$, e, next) => { await \$.env.set('X', '1'); return next(e) })"
broken '$.clock.every' "on('session.measure', async (\$, e, next) => { \$.clock.every(1000, () => {}); return next(e) })"
broken 'classic.Stop' "on('classic.Stop', (\$, e, next) => next(e))"
broken 'session.compact' "on('session.compact', (\$, e, next) => next(e))"
total=$((pass+fail))
if [ $fail -eq 0 ]; then echo "mod-validate: $pass/$total прошли"; exit 0; fi
echo "mod-validate: $pass/$total прошли, $fail упало$failures"; exit 1
