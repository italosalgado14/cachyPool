#!/usr/bin/env bash
# Verify every cross-document reference in this repo still resolves.
#
# Added 2026-11-03 with the documentation restructure, which moved 21 sections across
# 9 files. The failure mode it guards against is silent: a `§N` reference still reads
# fine after its target has moved, and nothing complains. It also catches the subtler
# one that bit during that restructure -- a file moved into runbooks/ goes on naming the
# snapshot doc with no ../ prefix, so the reference now resolves inside runbooks/ and
# points at nothing. (Names are left unquoted in this header on purpose: a backticked
# path here would be read as a reference made by this script.)
#
# Convention this enforces: a reference to a *document* is written relative to the file
# making it (`../ACTUAL-CONFIGURATION.md` from a runbook). Paths to config and source
# files stay in repo-root form (`configs/hypr/monitors.conf`) -- those are paths, not
# links, and are not checked here.
#
#   ./tests/check-doc-refs.sh
#
# Checks:
#   1. `<path>.md` [§N] -> file exists when resolved from the referring file, and has a `## N.` heading
#   2. a `§N` pointer at the dissolved finish-installation-commands.md -> always an error
#   3. bare §N with no document named anywhere near it, in a file that has no §N -> note
#
# A region between `<!-- doc-refs: ignore -->` and `<!-- /doc-refs: ignore -->` is skipped,
# for the one legitimate case: a table that names pre-move paths on purpose.
#
# Notes (as opposed to errors) are informational and do not fail the run: because section
# numbers are preserved across moves, a bare §N stays findable with grep even when no
# document is named beside it.
#
# References to documents outside this repo (upstream project files) are skipped: a
# basename that is not tracked in git is assumed external and only counted.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
exec python3 -I - <<'PYEOF'
import os, re, sys, subprocess

tracked = subprocess.run(['git','ls-files'],capture_output=True,text=True).stdout.split()
md_basenames = {os.path.basename(f) for f in tracked if f.endswith('.md')}
files = [f for f in tracked if f.endswith(('.md','.sh','.py'))
         or f in ('triton-panel/triton-panel','triton-panel/triton-ctl')]

heads = {}
def sections(path):
    if path not in heads:
        try: t = open(path, encoding='utf-8', errors='replace').read()
        except OSError: heads[path] = None; return None
        heads[path] = set(re.findall(r'^##+ (\d+)[.a-z]', t, re.M))
    return heads[path]

errors, notes, checked, external = [], [], 0, set()

for f in files:
    d = os.path.dirname(f)
    try: text = open(f, encoding='utf-8', errors='replace').read()
    except OSError: continue

    # regions a document fences off on purpose (e.g. a table of pre-move paths)
    text = re.sub(r'<!-- doc-refs: ignore.*?<!-- /doc-refs: ignore -->', '', text, flags=re.S)

    for m in re.finditer(r'`([A-Za-z0-9_./-]+\.md)`(\s*§(\d+))?', text):
        rel, sec = m.group(1), m.group(3)
        base = os.path.basename(rel)
        if base not in md_basenames:
            external.add(base)
            if base == 'finish-installation-commands.md' and sec:
                errors.append(f'{f}: `{rel}` §{sec} -> dissolved 2026-11-03, re-point it '
                              f'(mapping table in CHANGELOG.md)')
            continue
        target = os.path.normpath(os.path.join(d, rel))
        checked += 1
        if not os.path.exists(target):
            errors.append(f'{f}: `{rel}` -> missing ({target}); '
                          f'write document paths relative to the referring file')
        elif sec is not None:
            s = sections(target)
            if s is not None and sec not in s:
                errors.append(f'{f}: `{rel}` §{sec} -> no "## {sec}." heading in {target}')

    if f.endswith('.md'):
        own = sections(f) or set()
        for m in re.finditer(r'(?<![`\w.])§(\d+)', text):
            if m.group(1) in own: continue
            if '.md' in text[max(0, m.start()-300):m.start()]: continue   # a doc is named nearby
            notes.append(f'{f}: bare §{m.group(1)}, and this file has no §{m.group(1)}')

print(f'{checked} document references checked across {len(files)} files')
if external: print(f'{len(external)} external/historical doc name(s) skipped: {", ".join(sorted(external))}')
seen=set()
for n in notes:
    if n not in seen: seen.add(n); print(f'  note:  {n}')
for e in errors: print(f'  ERROR: {e}')
print(f'\n{len(errors)} error(s), {len(seen)} note(s)')
sys.exit(1 if errors else 0)
PYEOF
