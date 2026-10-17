#!/usr/bin/env bash
# Fail when someone other than the repo owner changes a path that feeds coding
# agents code or instructions: Trail injects .trail/learnings into context at
# session start, and .trail/hook.cjs imports trail from <repo>/node_modules or
# <repo>/dist/claude; Claude Code also loads .claude/, CLAUDE.md, AGENTS.md
# and .mcp.json, node resolves trail's own package name through the root
# package.json, and the next session starts from docs/STATUS.md and the
# continuation prompts in docs/handoff/.
# Usage: <changed file paths, NUL-separated> | trail-guard.sh <pr-author> <repo-owner>
# NUL-separated, because a filename may contain a newline.
set -euo pipefail
author=$1
owner=$2

# (/|$): a symlink or submodule named node_modules, .claude or dist is one path
# with no slash, and node and Claude follow it. A root package.json named like
# trail's package would make hook.cjs resolve trail into this repo.
protected='^\.trail(/|$)|^node_modules(/|$)|^dist$|^dist/claude(/|$)|^package\.json$|(^|/)\.claude(/|$)|(^|/)claude(\.local)?\.md$|(^|/)agents\.md$|(^|/)\.mcp\.json$|^docs/handoff(/|$)|^docs/status\.md$'
short_name='(^|/)[^/]*~[0-9][^/]*(/|$)' # 8.3 alias such as TRAIL~1, which Windows may resolve to .trail
# .trail/hook.cjs runs `npm root -g` through cmd.exe, which tries the current
# directory first with every default PATHEXT extension.
root_exec='^[^/]+\.(com|exe|bat|cmd|vbs|vbe|js|jse|wsf|wsh|msc)$'

# One process splits, folds and matches, so each path is checked against its
# own folded form. A name with a control or line-separator character is
# reported as protected: tools disagree on where such a name ends.
# Folding covers look-alikes a filesystem may treat as the same name:
# compatibility forms (fullwidth letters), case (APFS folds long s to s,
# Windows upper-cases dotless i to I), marks and zero-width characters (HFS+
# ignores the latter), and trailing dots and spaces, which Windows drops from
# every component.
check='
import re, sys, unicodedata as u
pattern = re.compile(sys.argv[1])
for raw in sys.stdin.buffer.read().split(b"\0"):
    if not raw:
        continue
    name = raw.decode("utf-8", "replace")
    shown = name.encode("unicode_escape").decode("ascii")
    if any(u.category(c) in ("Cc", "Zl", "Zp") for c in name):
        print(shown)
        continue
    s = "".join(c for c in u.normalize("NFKD", name) if u.category(c) not in ("Mn", "Cf"))
    s = re.sub(r"[. ]+(/|$)", r"\1", s.casefold().replace("ı", "i"))
    if pattern.search(s):
        print(shown)
'
touched=$(python3 -I -c "$check" "$protected|$short_name|$root_exec")

if [ -n "$touched" ] && [ "$author" != "$owner" ]; then
  echo "::error::Only @$owner may change agent context and code-loading paths. This PR by @$author touches:"
  echo "$touched"
  exit 1
fi
echo "ok: no protected paths changed, or changed by the owner"
