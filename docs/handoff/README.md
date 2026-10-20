# Handoffs

One continuation prompt per planned session, named `YYYY-MM-DD-<topic>.md`.
The next session pastes or reads the newest one and starts from it. Owner-only
path: the guard rejects changes here from anyone else.

## Template

```markdown
# Continue: <topic>

## Context
<one paragraph: the goal, and the spec/plan files it comes from>

## Done this session
- <task> (<commit>) — <what it does, in a line>

## Remaining, in order
1. <task> — files: <paths> — done when: <observable result>

## Decisions made (do not reopen)
- <decision> — because <reason>

## Ruled out
- <approach> — because <what went wrong>

## Watch out for
- <trap, flaky test, device quirk>

## Verify before starting
- <command> → expected <result>

## First step
<the exact next action, written as the prompt for the next session>
```
