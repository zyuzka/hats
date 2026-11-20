#!/usr/bin/env bash
# Имя ячейки keychain, которое считает мод (`getCredentialService` в hooks/limit-rules.js), по общей
# таблице plugin/tests/fixtures/credential-services.json — той же, что читает Swift-тест
# CredentialServiceFixtureTests. Набор `claude plugin test` не умеет читать JSON, поэтому таблица
# идёт через node. Проверка сломана руками в конце: копия модуля без хеша обязана упасть.
#   bash plugin/tests/credential-services.test.sh
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d "${TMPDIR:-/tmp}/credential-services-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

if ! command -v node >/dev/null 2>&1; then
  echo "credential-services: node не найден — проверка не запускалась"
  exit 2
fi

check() {  # check <folder with limit-rules.js and thresholds.js>; печатает строки FAIL и итог
  node --input-type=module - "$1" "$root/tests/fixtures/credential-services.json" <<'EOF'
import { readFileSync } from 'node:fs'
const [hooks, table] = process.argv.slice(2)
const { getCredentialService } = await import(`${hooks}/limit-rules.js`)
const cases = JSON.parse(readFileSync(table, 'utf8')).cases
let failed = 0
for (const row of cases) {
  const got = await getCredentialService(row.environment)
  if (got !== row.service) {
    failed += 1
    console.log(`FAIL ${row.name}: ${got} != ${row.service}`)
  }
}
console.log(`cases=${cases.length} failed=${failed}`)
process.exit(failed === 0 && cases.length > 0 ? 0 : 1)
EOF
}

pass=0; fail=0
if out=$(check "$root/hooks"); then pass=$((pass+1)); else fail=$((fail+1)); echo "$out"; fi
echo "$out" | tail -1

cp "$root/hooks/limit-rules.js" "$root/hooks/thresholds.js" "$work/"
python3 -I - "$work/limit-rules.js" <<'EOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
broken = text.replace("if (named === null) return ''", "return ''")
assert broken != text
open(path, "w", encoding="utf-8").write(broken)
EOF
if check "$work" >/dev/null; then fail=$((fail+1)); echo "FAIL the mutant without the hash passed"; else pass=$((pass+1)); fi

echo "credential-services: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
