#!/usr/bin/env bash
# Matrix for the Codex hooks of Hats: window.py (fill of the window, request for the note) and
# note_back.py (the note handed back after a compaction). Session files are made up here in the
# shape Codex writes (event_msg / token_count); the window is 475 000, as for the user's model.
#   bash codex-plugin/tests/window.test.sh
#   PATH="/usr/bin:$PATH" bash codex-plugin/tests/window.test.sh      # under the system Python
set -uo pipefail
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WINDOW="$plugin_root/scripts/window.py"
NOTE_BACK="$plugin_root/scripts/note_back.py"
unset HATS_STATE_HOME
pass=0; fail=0; failures=""
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-window-test.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

root="$work/state"
tmp="$work/tmp"
mkdir -p "$root" "$tmp"
notes="$tmp/hats-codex-notes"
tr="$work/rollout.jsonl"
sid="019a1f04-577c-7210-a55d-85432c05d145"
note="$notes/$sid.md"
own="$root/codex-windows/$sid.json"
journal="$root/codex-hooks.log"

ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); failures="$failures
  $1: $2"; }

COUNT='{"timestamp":"2026-11-18T20:05:43.524Z","type":"event_msg","payload":{"type":"token_count","info":'
COUNT+='{"total_token_usage":{"input_tokens":9,"output_tokens":7,"total_tokens":16},"last_token_usage":'
COUNT+='{"input_tokens":%s,"cached_input_tokens":0,"output_tokens":7,"total_tokens":%s},'
COUNT+='"model_context_window":%s},"rate_limits":null}}\n'
count() { printf "$COUNT" "$1" "$1" "${2:-475000}"; }  # count <input> [window]
percent_of() { count $(( $1 * 4750 )) ; }               # percent_of <percent of 475 000>
message() { printf '{"timestamp":"t","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"%s"}]}}\n' "$1"; }
NO_INFO='{"timestamp":"t","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":null}}}'

input() {  # input <event> [extra fields] [transcript]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"/work/proj","hook_event_name":"%s"%s}' \
    "$sid" "${3-$tr}" "$1" "${2:-}"
}
run_window() { printf '%s' "$1" | env HATS_STATE_HOME="$root" TMPDIR="$tmp" python3 -I "$WINDOW" 2>&1; }
run_back() { printf '%s' "$1" | env HATS_STATE_HOME="$root" TMPDIR="$tmp" python3 -I "$NOTE_BACK" 2>&1; }
context() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); h=d["hookSpecificOutput"]; print(h["hookEventName"]); print(h["additionalContext"])' 2>/dev/null; }
json_field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print(json.dumps(v))' "$1" "$2" 2>/dev/null || echo "<none>"; }
reset() { rm -rf "$notes" "$root/codex-windows" "$journal" "$root/window-thresholds.json"; : > "$tr"; }

silent() {  # silent <name> <output> <rc>
  if [ -z "$2" ] && [ "$3" -eq 0 ]; then ok; else bad "$1: silent, code 0" "rc=$3 out=${2:0:300}"; fi
}
has() {  # has <name> <text> <needle>
  case $2 in *"$3"*) ok ;; *) bad "$1" "no «$3» in: ${2:0:400}" ;; esac
}
lacks() {
  case $2 in *"$3"*) bad "$1" "unexpected «$3» in: ${2:0:400}" ;; *) ok ;; esac
}
equal() { if [ "$2" = "$3" ]; then ok; else bad "$1" "expected «$3», got «$2»"; fi; }

# 1. Below the threshold: 40% → silent; the window goes to the Hats folder.
reset; percent_of 40 > "$tr"
out=$(run_window "$(input UserPromptSubmit)"); silent "40%" "$out" $?
equal "40%: window for Hats" "$(json_field "$own" window)" 475000
equal "40%: percent for Hats" "$(json_field "$own" percent)" 40
equal "40%: cwd for Hats" "$(json_field "$own" cwd)" '"/work/proj"'
equal "40%: file mode 600" "$(stat -f %Lp "$own" 2>/dev/null)" 600
equal "40%: event for Hats" "$(json_field "$own" event)" '"UserPromptSubmit"'

# 2. Warning threshold: start of a turn at 61% with 60/70 → write the note, tell the user in one line.
reset; percent_of 61 > "$tr"
out=$(run_window "$(input UserPromptSubmit)"); rc=$?
equal "61%: code 0" "$rc" 0
ctx=$(printf '%s' "$out" | context)
has "61%: event name" "$ctx" "UserPromptSubmit"
has "61%: names the note path" "$ctx" "$note"
has "61%: asks to write" "$ctx" "write a resume note"
has "61%: tell the user in one line" "$ctx" "tell the user in one line"
has "61%: names the fill" "$ctx" "61% full"
has "61%: names the save threshold" "$ctx" "do that at 70%"
equal "61%: notes folder mode 700" "$(stat -f %Lp "$notes" 2>/dev/null)" 700
has "61%: journal" "$(cat "$journal" 2>/dev/null)" '"asked-to-write"'
has "61%: first attempt journalled" "$(cat "$journal" 2>/dev/null)" '"attempt": 1'

# 3. Update: next turn at 64%, no compaction, the note is there → update it, do not tell the user.
printf 'code word BLUE\n' > "$note"
percent_of 61 > "$tr"; percent_of 64 >> "$tr"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "64%: asks to update" "$ctx" "update the resume note"
has "64%: do not tell" "$ctx" "Do not tell the user"
lacks "64%: no second announcement" "$ctx" "tell the user in one line"
has "64%: journal" "$(cat "$journal")" '"asked-to-update"'

# 3b. The note was never written (a turn cut short, the sandbox refused): the loud request comes back
# while the file is missing, three loud requests in all, then only the update wording.
rm -f "$note"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "64% without the note: loud again" "$ctx" "tell the user in one line"
has "64% without the note: second attempt journalled" "$(cat "$journal")" '"attempt": 2'
equal "64% without the note: count" "$(json_field "$notes/$sid.state.json" loud)" 2
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "64% without the note: loud a third time" "$ctx" "tell the user in one line"
equal "64% without the note: count at the limit" "$(json_field "$notes/$sid.state.json" loud)" 3
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "64% past the limit: update wording" "$ctx" "update the resume note"
lacks "64% past the limit: no fourth announcement" "$ctx" "tell the user in one line"
has "64% past the limit: journal" "$(cat "$journal")" '"note-missing"'

# 3b-empty. An empty note or a folder in its place is no note: loud until the limit, then note-missing.
for kind in empty folder; do
  rm -rf "$note"; printf '{"announced": false, "loud": 0}' > "$notes/$sid.state.json"
  run_window "$(input UserPromptSubmit)" >/dev/null
  if [ "$kind" = empty ]; then : > "$note"; else mkdir "$note"; fi
  ctx=$(run_window "$(input UserPromptSubmit)" | context)
  has "$kind note: loud again" "$ctx" "tell the user in one line"
  run_window "$(input UserPromptSubmit)" >/dev/null
  missing_before=$(grep -c '"note-missing"' "$journal")
  ctx=$(run_window "$(input UserPromptSubmit)" | context)
  has "$kind note past the limit: update wording" "$ctx" "update the resume note"
  equal "$kind note past the limit: note-missing journalled" "$(grep -c '"note-missing"' "$journal")" "$((missing_before + 1))"
done
rm -rf "$note"

# 3b-old. A state from an earlier version, announced without a count, and no note: one more loud request.
printf '{"announced": true, "percent": 64}' > "$notes/$sid.state.json"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "old state without the note: loud" "$ctx" "tell the user in one line"
equal "old state: counted as the second" "$(json_field "$notes/$sid.state.json" loud)" 2
printf 'code word BLUE\n' > "$note"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "old state with the note: update wording" "$ctx" "update the resume note"
lacks "old state with the note: quiet" "$ctx" "tell the user in one line"
equal "old state with the note: count unchanged" "$(json_field "$notes/$sid.state.json" loud)" 2

# 3b-stale. A state from an earlier version beside a note left from before: the note as it is now does not
# count, so the request stays loud; left unchanged to the limit, the silent turn journals note-missing.
printf '{"announced": true, "percent": 64}' > "$notes/$sid.state.json"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "old state, stale note: loud" "$ctx" "tell the user in one line"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "old state, stale note unchanged: loud at the limit" "$ctx" "tell the user in one line"
missing_before=$(grep -c '"note-missing"' "$journal")
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "stale note past the limit: update wording" "$ctx" "update the resume note"
equal "stale note past the limit: note-missing journalled" "$(grep -c '"note-missing"' "$journal")" "$((missing_before + 1))"

# 3c. Stop past the warning threshold asks nothing.
out=$(run_window "$(input Stop)"); silent "Stop at 64%" "$out" $?
equal "Stop at 64%: event for Hats" "$(json_field "$own" event)" '"Stop"'
equal "Stop at 64%: percent for Hats" "$(json_field "$own" percent)" 64

# 4. After the compaction: SessionStart compact with the note → the note goes back.
printf 'Code word: BLUE-HERON-7\nNext step: the essay\n' > "$note"
out=$(run_back "$(input SessionStart ',"source":"compact"')"); rc=$?
equal "compact: code 0" "$rc" 0
ctx=$(printf '%s' "$out" | context)
has "compact: event name" "$ctx" "SessionStart"
has "compact: the note itself" "$ctx" "BLUE-HERON-7"
has "compact: the next step" "$ctx" "Next step: the essay"
has "compact: go on" "$ctx" "Go on with the task"
has "compact: journal" "$(cat "$journal")" '"handed-back"'
equal "compact: warning armed again" "$(json_field "$notes/$sid.state.json" announced)" false
equal "compact: count starts over" "$(json_field "$notes/$sid.state.json" loud)" 0
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "compact, still at 64%: first request again" "$ctx" "tell the user in one line"

# 5. No note: SessionStart compact without the file → says there is none, journal line.
rm -f "$note"
ctx=$(run_back "$(input SessionStart ',"source":"compact"')" | context)
has "compact without a note" "$ctx" "no resume note was found"
has "compact without a note: path" "$ctx" "$note"
has "compact without a note: journal" "$(cat "$journal")" '"no-note"'

# 5b. Another source of SessionStart is not this hook's.
out=$(run_back "$(input SessionStart ',"source":"startup"')"); silent "startup" "$out" $?

# 5c. A note longer than the limit is cut and says so.
python3 -c 'print("x" * 30000)' > "$note"
ctx=$(run_back "$(input SessionStart ',"source":"compact"')" | context)
has "long note cut" "$ctx" "[cut at 24000 characters]"

# 6. New round: after the compaction 25% re-arms, then 61% warns again.
reset; mkdir -m 700 "$notes"; printf 'old\n' > "$note"
percent_of 64 > "$tr"; run_window "$(input UserPromptSubmit)" >/dev/null
equal "round: noted before" "$(json_field "$notes/$sid.state.json" announced)" true
percent_of 25 >> "$tr"
out=$(run_window "$(input Stop)"); silent "round: 25% on Stop" "$out" $?
equal "round: re-armed below the threshold" "$(json_field "$notes/$sid.state.json" announced)" false
percent_of 61 >> "$tr"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "round: warns again at 61%" "$ctx" "tell the user in one line"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "round: the note of the last arming is not this one's, loud again" "$ctx" "tell the user in one line"
touch -t 203001010000 "$note"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "round: the note rewritten in this arming, update wording" "$ctx" "update the resume note"
lacks "round: the note rewritten in this arming, quiet" "$ctx" "tell the user in one line"

# 6b. A spent count starts over below the threshold.
printf '{"announced": true, "percent": 64, "loud": 3, "before": null}' > "$notes/$sid.state.json"
percent_of 25 >> "$tr"
out=$(run_window "$(input Stop)"); silent "spent: 25% on Stop" "$out" $?
equal "spent: count starts over" "$(json_field "$notes/$sid.state.json" loud)" 0

# 7. Thresholds off: save_percent null → no request at 80%; warn_percent null too.
reset; percent_of 80 > "$tr"
printf '{"warn_percent": 60, "save_percent": null}' > "$root/window-thresholds.json"
out=$(run_window "$(input UserPromptSubmit)"); silent "save off" "$out" $?
printf '{"warn_percent": null, "save_percent": 70}' > "$root/window-thresholds.json"
out=$(run_window "$(input UserPromptSubmit)"); silent "warn off" "$out" $?
lacks "thresholds off: no failure in the journal" "$(cat "$journal" 2>/dev/null)" '"failed"'

# 8. Thresholds of Hats: 50/55 → 52% asks and names 55%.
reset; percent_of 52 > "$tr"
printf '{"warn_percent": 50, "save_percent": 55, "after_save": "tell"}' > "$root/window-thresholds.json"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "50/55 at 52%" "$ctx" "do that at 55%"

# 8b. An unusable thresholds file falls back to 60/70.
reset; percent_of 65 > "$tr"
printf '{"warn_percent": 70, "save_percent": 60}' > "$root/window-thresholds.json"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "warn >= save: 60/70 at 65%" "$ctx" "do that at 70%"
printf 'not json' > "$root/window-thresholds.json"
percent_of 61 > "$tr"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "broken thresholds: 60/70 at 61%" "$ctx" "do that at 70%"
has "broken thresholds: journal names it" "$(cat "$journal")" '"thresholds-unreadable"'
has "broken thresholds: journal says why" "$(cat "$journal")" 'not a JSON object'
has "warn >= save: journal names both" "$(cat "$journal")" 'warn_percent=70 not below save_percent=60'
printf '{"warn_percent": 9, "save_percent": 70}' > "$root/window-thresholds.json"
run_window "$(input UserPromptSubmit)" >/dev/null
has "warn out of range: journal names the value" "$(cat "$journal")" 'warn_percent=9'
reset; percent_of 61 > "$tr"
printf '{"warn_percent": 60, "save_percent": 70}' > "$root/window-thresholds.json"
run_window "$(input UserPromptSubmit)" >/dev/null
lacks "usable thresholds: no unreadable line" "$(cat "$journal")" '"thresholds-unreadable"'

# 8c. A FIFO in place of a file the hooks read never hangs them: 60/70 and a journal line, at once.
reset; percent_of 61 > "$tr"
mkfifo "$root/window-thresholds.json"
started=$(date +%s)
ctx=$(printf '%s' "$(input UserPromptSubmit)" | env HATS_STATE_HOME="$root" TMPDIR="$tmp" \
  perl -e 'alarm 5; exec @ARGV' python3 -I "$WINDOW" 2>&1 | context)
took=$(( $(date +%s) - started ))
has "FIFO thresholds: 60/70 at 61%" "$ctx" "do that at 70%"
if [ "$took" -lt 4 ]; then ok; else bad "FIFO thresholds: no hang" "took ${took}s"; fi
has "FIFO thresholds: journal" "$(cat "$journal" 2>/dev/null)" '"thresholds-unreadable"'
rm -f "$root/window-thresholds.json"
reset; percent_of 61 > "$tr"; run_window "$(input UserPromptSubmit)" >/dev/null
rm -f "$note"; mkfifo "$note"
started=$(date +%s)
printf '%s' "$(input SessionStart ',"source":"compact"')" | env HATS_STATE_HOME="$root" TMPDIR="$tmp" \
  perl -e 'alarm 5; exec @ARGV' python3 -I "$NOTE_BACK" >/dev/null 2>&1
took=$(( $(date +%s) - started ))
if [ "$took" -lt 4 ]; then ok; else bad "FIFO note: no hang" "took ${took}s"; fi
rm -f "$note"

# 9. Broken session file: no token_count, info null, garbage, no file, empty input.
reset; message hello > "$tr"; printf '%s\n' "$NO_INFO" >> "$tr"; printf '{not json "token_count"\n' >> "$tr"
out=$(run_window "$(input UserPromptSubmit)"); silent "no usable token_count" "$out" $?
[ -e "$own" ] && bad "no token_count" "window file written" || ok
out=$(run_window "$(input UserPromptSubmit '' "$work/missing.jsonl")"); silent "missing session file" "$out" $?
out=$(printf 'garbage' | env HATS_STATE_HOME="$root" TMPDIR="$tmp" python3 -I "$WINDOW" 2>&1); silent "garbage input" "$out" $?
out=$(printf '' | env HATS_STATE_HOME="$root" TMPDIR="$tmp" python3 -I "$NOTE_BACK" 2>&1); silent "empty input (note_back)" "$out" $?

# 9b. The last usable count wins, also behind info null and other lines; a count far back is found.
reset; percent_of 61 > "$tr"; percent_of 30 >> "$tr"; printf '%s\n' "$NO_INFO" >> "$tr"; message bye >> "$tr"
out=$(run_window "$(input UserPromptSubmit)"); silent "last count 30% wins" "$out" $?
equal "last count 30%: percent" "$(json_field "$own" percent)" 30
reset; percent_of 62 > "$tr"
python3 -c 'import sys; line = "{\"type\":\"response_item\",\"payload\":{\"text\":\"" + "y" * 1000 + "\"}}\n"; sys.stdout.write(line * 3000)' >> "$tr"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "count 3 MB back" "$ctx" "62% full"
reset; percent_of 63 > "$tr"
python3 -c 'import sys; sys.stdout.write("z" * (1048576 - 101) + "\n")' >> "$tr"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
has "count across a block edge" "$ctx" "63% full"

# 9c. A session id that is not one.
reset; percent_of 80 > "$tr"
out=$(printf '{"session_id":"../x","transcript_path":"%s","hook_event_name":"UserPromptSubmit"}' "$tr" \
  | env HATS_STATE_HOME="$root" TMPDIR="$tmp" python3 -I "$WINDOW" 2>&1); silent "bad session id" "$out" $?

# 10. Without a Hats folder: 60/70, no window file, the journal goes to the notes folder.
reset; percent_of 61 > "$tr"
out=$(printf '%s' "$(input UserPromptSubmit)" | env HATS_STATE_HOME="$work/no-hats" TMPDIR="$tmp" python3 -I "$WINDOW")
has "no Hats folder: still asks" "$(printf '%s' "$out" | context)" "do that at 70%"
[ -e "$work/no-hats" ] && bad "no Hats folder" "the hook created it" || ok
has "no Hats folder: journal in notes" "$(cat "$notes/hooks.log" 2>/dev/null)" '"asked-to-write"'

# 10b. A relative HATS_STATE_HOME is no Hats folder: 60/70 (a thresholds file under the relative path is not
# read), no window file there or in the default folder, the journal goes to the notes folder.
reset; percent_of 61 > "$tr"; rm -rf "$work/run" "$work/home"
mkdir -p "$work/run/rel" "$work/home/Library/Application Support/Hats"
printf '{"warn_percent": 20, "save_percent": 30}' > "$work/run/rel/window-thresholds.json"
out=$(printf '%s' "$(input UserPromptSubmit)" |
  (cd "$work/run" && env HATS_STATE_HOME=rel HOME="$work/home" TMPDIR="$tmp" python3 -I "$WINDOW"))
equal "relative root: code 0" "$?" 0
has "relative root: still asks at 60/70" "$(printf '%s' "$out" | context)" "do that at 70%"
has "relative root: journal in notes" "$(cat "$notes/hooks.log" 2>/dev/null)" '"asked-to-write"'
equal "relative root: nothing written under the relative path" "$(ls -A "$work/run/rel")" "window-thresholds.json"
equal "relative root: nothing written in the default folder" "$(ls -A "$work/home/Library/Application Support/Hats")" ""

# 11. Stop sweeps window files older than 30 days and leaves fresh ones.
reset; percent_of 20 > "$tr"
mkdir -p "$root/codex-windows"
printf '{}' > "$root/codex-windows/old-1.json"; touch -t 202601010000 "$root/codex-windows/old-1.json"
printf '{}' > "$root/codex-windows/fresh-1.json"
run_window "$(input Stop)" >/dev/null
[ -e "$root/codex-windows/old-1.json" ] && bad "sweep" "old file kept" || ok
[ -e "$root/codex-windows/fresh-1.json" ] && ok || bad "sweep" "fresh file removed"

# 11b. Temporary window files: an old one is swept, a fresh one kept.
reset; percent_of 20 > "$tr"
mkdir -p "$root/codex-windows"
printf '{}' > "$root/codex-windows/.tmp-old.json"; touch -t 202601010000 "$root/codex-windows/.tmp-old.json"
printf '{}' > "$root/codex-windows/.tmp-new.json"
run_window "$(input Stop)" >/dev/null
[ -e "$root/codex-windows/.tmp-old.json" ] && bad "sweep tmp" "old temporary kept" || ok
[ -e "$root/codex-windows/.tmp-new.json" ] && ok || bad "sweep tmp" "fresh temporary removed"

# 11c. Stop sweeps the notes folder: notes, state and temporary files older than 30 days; the rest stays.
reset; percent_of 20 > "$tr"; mkdir -m 700 "$notes"
for f in old-1.md old-1.state.json .tmp-old.json; do printf 'x' > "$notes/$f"; touch -t 202601010000 "$notes/$f"; done
printf 'x' > "$notes/fresh-1.md"; printf 'x' > "$notes/hooks.log"; touch -t 202601010000 "$notes/hooks.log"
run_window "$(input Stop)" >/dev/null
for f in old-1.md old-1.state.json .tmp-old.json; do [ -e "$notes/$f" ] && bad "notes sweep" "$f kept" || ok; done
for f in fresh-1.md hooks.log; do [ -e "$notes/$f" ] && ok || bad "notes sweep" "$f removed"; done

# 13. Exactly at the warning threshold asks; one percent below stays silent.
reset; percent_of 60 > "$tr"
has "exactly 60%" "$(run_window "$(input UserPromptSubmit)" | context)" "write a resume note"
reset; percent_of 59 > "$tr"
out=$(run_window "$(input UserPromptSubmit)"); silent "59%" "$out" $?

# 14. A failed window record does not stop the request.
reset; percent_of 61 > "$tr"; mkdir -m 500 "$root/codex-windows"
ctx=$(run_window "$(input UserPromptSubmit)" | context)
chmod 700 "$root/codex-windows"
has "window not recorded: still asks" "$ctx" "write a resume note"
has "window not recorded: journal" "$(cat "$journal")" '"window-not-recorded"'

# 15. A notes folder others may enter is refused: no request, no note handed back, a journal line.
reset; percent_of 61 > "$tr"; mkdir -m 700 "$notes"; printf 'planted
' > "$note"; chmod 777 "$notes"
out=$(run_window "$(input UserPromptSubmit)"); silent "0777 notes folder: no request" "$out" $?
ctx=$(run_back "$(input SessionStart ',"source":"compact"')" | context)
lacks "0777 notes folder: note not handed back" "$ctx" "planted"
has "0777 notes folder: says no note" "$ctx" "no resume note was found"
has "0777 notes folder: journal" "$(cat "$journal")" '"notes-folder-refused"'
chmod 700 "$notes"

# 15b. A note that is a link is not followed.
reset; mkdir -m 700 "$notes"; printf 'secret
' > "$work/elsewhere.md"; ln -s "$work/elsewhere.md" "$note"
ctx=$(run_back "$(input SessionStart ',"source":"compact"')" | context)
lacks "linked note: not followed" "$ctx" "secret"

# 16. Only the last 16 MiB of the session file are read.
reset; percent_of 61 > "$tr"
python3 -c 'import sys; sys.stdout.write(("q" * 1023 + "\n") * (17 * 1024))' >> "$tr"
out=$(run_window "$(input UserPromptSubmit)"); silent "count 17 MiB back: not read" "$out" $?

# 17. The fill after the last answer: input 57 000 (12%) and a 7 000-token answer → end_percent 13;
#     a count without a usable total → end_percent null, percent as before.
reset; printf "$COUNT" 57000 64000 475000 > "$tr"
out=$(run_window "$(input Stop)"); silent "Stop with a long answer" "$out" $?
equal "long answer: percent is the input" "$(json_field "$own" percent)" 12
equal "long answer: end_percent counts the answer" "$(json_field "$own" end_percent)" 13
reset; printf "$COUNT" 57000 '"x"' 475000 > "$tr"
out=$(run_window "$(input Stop)"); silent "Stop without a total" "$out" $?
equal "no total: percent" "$(json_field "$own" percent)" 12
equal "no total: end_percent null" "$(json_field "$own" end_percent)" null
reset; printf "$COUNT" 57000 56000 475000 > "$tr"
run_window "$(input Stop)" >/dev/null
equal "total below input: end_percent null" "$(json_field "$own" end_percent)" null

# 12. The output is one JSON line, nothing else on stdout or stderr.
reset; percent_of 61 > "$tr"
out=$(run_window "$(input UserPromptSubmit)")
equal "one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1

# --- every journal line names its session; bad input leaves it out
journal_line() {  # the only line of the journal: script outcome session-or-<no session>; <none> when there is not exactly one
  python3 -I -c 'import json,sys
lines = open(sys.argv[1]).read().splitlines()
if len(lines) != 1:
    print("<none>"); raise SystemExit
d = json.loads(lines[0])
print(d.get("script"), d.get("outcome"), d["session"] if "session" in d else "<no session>")' "$journal" 2>/dev/null || echo "<none>"; }
reset; percent_of 61 > "$tr"; run_window "$(input UserPromptSubmit)" >/dev/null
equal "journal: asked-to-write names the session" "$(journal_line)" "window asked-to-write $sid"
rm -f "$journal"; run_back "$(input SessionStart ',"source":"compact"')" >/dev/null
equal "journal: note_back names the session" "$(journal_line)" "note_back no-note $sid"
reset; percent_of 61 > "$tr"
run_back '{"session_id":"a/b","hook_event_name":"SessionStart","source":"compact"}' >/dev/null
equal "journal: a bad session id is left out, not written as null" "$(journal_line)" "note_back bad-session <no session>"

echo "codex hooks: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '%s\n' "$failures"
  exit 1
fi
