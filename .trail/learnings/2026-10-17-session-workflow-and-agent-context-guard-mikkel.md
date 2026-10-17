---
title: Session workflow and agent-context guard
author: Mikkel
date: 2026-10-17
branch: chore/session-workflow
cost: { minutes: 1, tokens: 1223 }
touches:
  - ".github/scripts/trail-guard.sh"
  - ".github/CODEOWNERS"
  - CLAUDE.md
  - docs/STATUS.md
  - docs/handoff/README.md
---

## Decided
- Ported the owner-only guard from kjmikkel/Dracula-Night-by-Night (trail-guard.sh, tests, guard.yml on pull_request_target, CODEOWNERS) unchanged, plus two paths specific to this workflow: docs/STATUS.md and docs/handoff/. The next session reads them as instructions, so a non-owner edit there is an injection path just like CLAUDE.md.
- Workflow lives in CLAUDE.md: Opus orchestrates and reviews, implementation goes to Agent subagents with model "sonnet", STATUS.md is kept true, and each planned session ends with a handoff in docs/handoff/.
- .claude/ stays git-ignored, as in Dracula; trail's repo hook entry is per machine (trail init --no-agents --no-global).

## Tried and ruled out
- Committing the workflow on feature/v1: the guard runs from main (pull_request_target), so it shipped on its own branch off main to protect PRs before v1 merges.
- Adding .gitignore on that branch: main has no .gitignore, feature/v1 has one, so it would conflict at merge. The .claude/ and /graft/ ignore lines belong on feature/v1.

## Watch out
- gradlew.bat is at the repo root here (under app/ in Dracula), so the root-executable rule makes it owner-only. That's intended; there's a test for it.
- The guard regex is matched against folded lowercase paths: write new entries in lowercase (docs/status\.md), not as cased on disk.
- Add a test case to trail-guard.test.sh for every regex change, and run: bash .github/scripts/trail-guard.test.sh
