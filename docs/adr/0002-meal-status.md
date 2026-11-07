# 0002. Meal status

- Status: Accepted
- Date: 2026-11-07

## Context

A meal's status was derived from dish progress (planned, cooking, cooked). That
had no place for the stage between "the plan is done" and "I'm cooking": buying
and gathering ingredients, and doing early prep.

## Decision

Every meal has one stored status, in this order:

| Status | Meaning |
|--------|---------|
| `planning` | Dishes and timings are still being worked out (the default) |
| `prepping` | The plan is settled; ingredients are being got in and early prep is under way |
| `cooking` | At least one dish has been started |
| `complete` | Every timed dish is done, or the cook finished the meal early |

### Rules

- **Planning and prepping are the cook's choice.** The home page card offers
  "Start prepping" and "Back to planning". Nothing is inferred for these two.
- **Cooking and complete follow progress.** Starting the first dish moves the
  meal to `cooking`. Finishing the last timed dish, or "Finish cooking", moves
  it to `complete`.
- **Undoing progress** until no dish is started drops a `cooking` or `complete`
  meal back to `prepping`. **Reset progress** does the same, because the plan
  still exists.
- A meal's delay is only recorded once it is `complete`.
- Status is shown and changed on the home page. Plan and cook screens don't
  expose it.

## Consequences

- Existing meals were backfilled from their progress (`complete`, `cooking`, or
  `planning`).
- Status is stored, so cooking progress changes must go through `Meals`
  (`start_cooking`, `finish_cooking`, `undo_*`, `finish_meal`, `reset_cooking`)
  to keep it in sync.
