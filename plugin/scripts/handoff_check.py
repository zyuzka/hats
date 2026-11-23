"""The note check: citations, number claims, git facts and the state lines.

Part of handoff.py, which holds the contract of the whole hook."""
import os

import handoff_state
from handoff_clock import out_of_time, time_left
from handoff_consts import (
    ALL_VERIFIED,
    CITE,
    CITE_START,
    CLAUSE_BREAK,
    FENCE,
    GIT_FACT,
    INLINE_CODE,
    LINE_LENGTH_LIMIT,
    NOTHING_CHECKED,
    NUMBER_CLAIM,
    PROBLEM_LIMIT,
    RATIO_PERCENT,
    SOURCE_SIZE_LIMIT,
    STATE_FACT_LIMIT,
    SYSTEM_SOURCE,
)
from handoff_files import is_same_file, read_regular, usable
from handoff_paths import cite_in_memory, is_in_notes_folder
from handoff_proc import run
from handoff_text import body_start, bounded_in


def verify_cite(match, base_dir, note_real, cache):
    raw = match.group("path").strip().strip("`")
    if not usable(raw):
        return "quote: bad path"
    path = os.path.expanduser(raw)
    if not os.path.isabs(path):
        path = os.path.join(base_dir, path)
    real = os.path.realpath(path)
    if note_real and (real == note_real or is_same_file(real, note_real)):
        return "quote of the note itself is not a source"
    if cite_in_memory(real):
        return f"quote of Claude's memory is not a source: {raw}"
    if is_in_notes_folder(real):
        return f"quote of the notes folder is not a source: {raw}"
    if real not in cache:
        text = read_regular(real, SOURCE_SIZE_LIMIT)
        cache[real] = None if text is None else text.split("\n")
    lines = cache[real]
    if lines is None:
        return f"quote: no regular file up to 2 MB: {raw}"
    number = int(match.group("line"))
    if number < 1 or number > len(lines):
        return f"quote: {raw} has no line {number}"
    key = (real, number)
    if key not in cache:
        cache[key] = " ".join(lines[number - 1].split())
    quoted = next(t for t in (match.group("t1"), match.group("t2"), match.group("t3")) if t is not None)
    want = " ".join(quoted.split())
    if not want:
        return "quote is empty — nothing to compare"
    if not bounded_in(want, cache[key]):
        return f"quote: text not found at {raw}:{number}: \"{want[:60]}\""
    return None


def check_text(text, base_dir, note_real):
    problems = []
    claims = 0
    cache = {}
    lines = text.split("\n")
    fence = None
    fence_line = 0
    for i in range(body_start(lines), len(lines)):
        number = i + 1
        if out_of_time():
            problems.append((number, "check ran out of time before the end of the note"))
            fence = None
            break
        line = lines[i]
        found = FENCE.match(line)
        if fence is None and found:
            fence, fence_line = found.group("fence"), number
            continue
        if fence is not None:
            if found and found.group("fence")[0] == fence[0] and len(found.group("fence")) >= len(fence) \
                    and not found.group("info").strip():
                fence = None
            continue
        if len(line) > LINE_LENGTH_LIMIT:
            problems.append((number, "line longer than 5,000 characters — not checked"))
            continue
        stopped = False
        for match in CITE.finditer(line):
            if out_of_time():
                stopped = True
                break
            claims += 1
            reason = verify_cite(match, base_dir, note_real, cache)
            if reason:
                problems.append((number, reason))
        if stopped:
            problems.append((number, "check ran out of time before the end of the note"))
            break
        rest = CITE.sub(" ", line)
        if CITE_START.search(INLINE_CODE.sub(" ", rest)):
            problems.append((number, "quote not parsed — write (cite: <path>:<line> \"<exact text>\")"))
        for match in RATIO_PERCENT.finditer(rest):
            claims += 1
            n, m = int(match.group("n")), int(match.group("m"))
            p = float(match.group("p").replace(",", "."))
            if m == 0 or abs(n * 100 / m - p) > 1:
                share = "—" if m == 0 else f"{n * 100 / m:.1f}%"
                problems.append((number, f"arithmetic: {n} of {m} is {share}, written {match.group('p')}%"))
        for clause in CLAUSE_BREAK.split(SYSTEM_SOURCE.sub("(cmd: -)", RATIO_PERCENT.sub(" ", rest))):
            if not NUMBER_CLAIM.search(clause):
                continue
            claims += 1
            if not SYSTEM_SOURCE.search(clause):
                problems.append((number, "number with no quote and no source"))
                break
    if fence is not None:
        problems.insert(0, (fence_line, "code block not closed — the lines after it were not checked"))
    return problems, claims


def checked_counted(text, base_dir, note_real):
    try:
        return check_text(text, base_dir, note_real)
    except Exception as error:
        handoff_state.check_errors.append(type(error).__name__)
        return [(None, f"note check failed ({type(error).__name__}) — check the note yourself")], 0


def get_verdict_line(claims):
    return NOTHING_CHECKED if claims == 0 else ALL_VERIFIED


def problem_lines(problems):
    out = [f"- line {number}: {reason}" if number else f"- {reason}" for number, reason in problems[:PROBLEM_LIMIT]]
    if len(problems) > PROBLEM_LIMIT:
        out.append(f"- and {len(problems) - PROBLEM_LIMIT} more")
    return out


def remote_mark(repo, ref):
    mark = " (local ref, no fetch)"
    if ref.startswith("origin/"):
        return mark
    code, name = run(["git", "-c", "core.fsmonitor=false", "-C", repo, "rev-parse", "--verify", "--quiet",
                      "--symbolic-full-name", "--end-of-options", ref], time_left(1.0))
    if code is None:
        return mark
    return mark if code == 0 and (name or "").startswith("refs/remotes/") else ""


def state_lines(text):
    out = []
    for line in text.split("\n"):
        match = GIT_FACT.match(line.replace("`", ""))
        if not match:
            continue
        if len(out) >= STATE_FACT_LIMIT:
            out.append("- further state facts not checked: more than four")
            break
        raw, ref, noted = match.group("repo"), match.group("ref"), match.group("sha")
        if not usable(raw):
            out.append(f"- git: bad path, {ref} not checked")
            continue
        repo = os.path.realpath(os.path.expanduser(raw))
        if out_of_time():
            out.append(f"- git {repo} {ref}: no time to check")
            continue
        if not os.path.isdir(repo):
            out.append(f"- git {repo} {ref}: no such folder")
            continue
        code, current = run(["git", "-c", "core.fsmonitor=false", "-C", repo, "rev-parse", "--verify",
                             "--quiet", "--end-of-options", ref + "^{commit}"], time_left(1.0))
        current = (current or "").strip()
        if code is None:
            out.append(f"- git {repo} {ref}: no time to check")
        elif code != 0 or not current:
            out.append(f"- git {repo} {ref}: not found")
        elif current.startswith(noted):
            local = remote_mark(repo, ref)
            out.append(f"- git {repo} {ref} = {noted}: matches{local}")
        else:
            local = remote_mark(repo, ref)
            out.append(f"- git {repo} {ref}: was {noted}, now {current[:len(noted)]}{local}")
    return out
