# Status

Kept true by every session (see `CLAUDE.md` section 4). Last updated 2026-10-17.

## Done

- v1 plan (`docs/superpowers/plans/2026-10-14-piece-counter.md`) Tasks 1–11 on
  branch `feature/v1`: scaffold, core model and maths, reading order, tally,
  session edits, image transform, photo loading, detection with golden-set
  test, view model and start screen, pick-types screen, results screen.
- Final-review fixes (crash, restore, stale edits): `be4d8b8`.
- Session workflow: Trail code map and learnings, Opus-plans/Sonnet-executes,
  status and handoff docs, owner-only guard for agent-context paths.

## Next

- Task 12: on-device acceptance checklist on the S23 Ultra (needs the user;
  plan section "Task 12").
- Merge `feature/v1` into `main` after acceptance passes.

## Open issues

- The plan's step checkboxes were never ticked; this file is the record of
  what is done.
- `guard / trail-owner-only` runs from `main` via `pull_request_target`, so it
  starts checking PRs once this lands on `main`. Mark it a required check then.
