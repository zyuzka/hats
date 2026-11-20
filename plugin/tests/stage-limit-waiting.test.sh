#!/usr/bin/env bash
# Событие `waiting` лимита по общему со Swift образцу plugin/tests/fixtures/stage-limit-waiting.json
# (его же читает Swift-тест SessionStageLimitWaitingTests): мод читает образец своим чтением файла
# стадии (`findStageFile` в hooks/files.js) и не теряет ни одного `waiting`, а событие, которое пишет
# `setLimitWaiting` (hooks/limit-drain.js), после `getLimitsRecord` несёт те же ключи, что и образец,
# и `origin` из набора образца. Набор `claude plugin test` не умеет читать JSON, поэтому — через node.
# Проверка сломана руками в конце: копия модуля, теряющая `waiting` при чтении, обязана упасть.
#   bash plugin/tests/stage-limit-waiting.test.sh
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d "${TMPDIR:-/tmp}/stage-limit-waiting-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

if ! command -v node >/dev/null 2>&1; then
  echo "stage-limit-waiting: node не найден — проверка не запускалась"
  exit 2
fi

check() {  # check <folder with the hooks>; печатает строки FAIL и итог
  node --input-type=module - "$1" "$root/tests/fixtures/stage-limit-waiting.json" "$work/state" <<'EOF'
import { mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
const [hooks, sample, state] = process.argv.slice(2)
const { findStageFile } = await import(`${hooks}/files.js`)
const { getLimitsRecord, setEpisode, createLimits } = await import(`${hooks}/limit-rules.js`)
const { setLimitWaiting } = await import(`${hooks}/limit-drain.js`)
const text = readFileSync(sample, 'utf8')
const data = JSON.parse(text)
mkdirSync(`${state}/session-thresholds`, { recursive: true })
writeFileSync(`${state}/session-thresholds/${data.session}.json`, text)
const $ = {
  env: { get: async name => (name === 'HATS_STATE_HOME' ? state : undefined) },
  fs: {
    stat: async path => {
      const stat = statSync(path)
      return { kind: stat.isFile() ? 'file' : 'dir', size: stat.size, isLink: false }
    },
    read: async path => readFileSync(path, 'utf8'),
  },
}
const failures = []
const saved = await findStageFile($, data.session)
const kinds = ['five_hour', 'seven_day']
for (const kind of kinds) {
  const want = data.limits[kind].waiting
  const got = saved?.limits?.[kind]?.waiting ?? null
  if (got === null) failures.push(`${kind}: the waiting event was lost`)
  if (got !== null && JSON.stringify(getLimitsRecord(saved.limits)[kind].waiting) !== JSON.stringify(want)) failures.push(`${kind}: the waiting event changed`)
}
const limits = createLimits()
const episode = setEpisode(limits, { kind: 'five_hour', reading: { percent: 81, resetsMs: Date.parse('2026-11-14T15:00:00Z') }, thresholds: { warn: 70, save: 80, lead: 682 } })
setLimitWaiting({ item: { kind: 'five_hour', episode, worn: 'work', why: 'no_hat' }, untilMs: Date.parse('2026-11-14T14:15:00Z'), origin: 'warned' }, { now: Date.parse('2026-11-14T14:11:00Z'), minutes: 10 })
const written = getLimitsRecord(limits).five_hour.waiting
const sampleKeys = Object.keys(data.limits.five_hour.waiting).sort().join(',')
if (Object.keys(written).sort().join(',') !== sampleKeys) failures.push(`the written keys ${Object.keys(written).sort().join(',')} != ${sampleKeys}`)
const origins = new Set(kinds.map(kind => data.limits[kind].waiting.origin).concat('warned'))
if (!origins.has(written.origin)) failures.push(`origin ${written.origin} is not in the sample`)
for (const line of failures) console.log(`FAIL ${line}`)
console.log(`checks=${kinds.length * 2 + 2} failed=${failures.length}`)
process.exit(failures.length === 0 ? 0 : 1)
EOF
}

pass=0; fail=0
if out=$(check "$root/hooks"); then pass=$((pass+1)); else fail=$((fail+1)); echo "$out"; fi
echo "$out" | tail -1

mkdir -p "$work/broken"
cp "$root/hooks/"*.js "$work/broken/"
python3 -I - "$work/broken/limit-rules.js" <<'EOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
broken = text.replace("    waiting: findWaiting(value.waiting),", "    waiting: null,")
assert broken != text
open(path, "w", encoding="utf-8").write(broken)
EOF
if check "$work/broken" >/dev/null; then fail=$((fail+1)); echo "FAIL the mutant that loses waiting passed"; else pass=$((pass+1)); fi

echo "stage-limit-waiting: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
