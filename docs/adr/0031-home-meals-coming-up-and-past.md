# 0031. Home meals: coming up, and past meals

- Status: Accepted
- Date: 2026-11-21
- Amends: 0002, 0025

## Context

Every meal was a big card with the same weight and much the same buttons: last year's finished
Christmas took as much room as next week's dinner, finished meals still offered *Plan*, and
the grid repeated the meal already in the *Next up* hero. It would only get noisier as meals
pile up.

## Decision

- **Next up** (ADR 0025) stays the one big card, and gains a ⋯ menu.
- **Coming up**: every other unfinished meal, soonest first, as a compact row in one panel:
  small date tile, name, status, "in 3 weeks · dinner 13:30 · 6 dishes · 20m prep", and
  **one button for its stage**: Plan (planning), Prep (prepping), Cook (cooking). The name
  links to the same place.
- **Past meals**: complete meals, newest first, as a quieter list: date with year, name, the
  result (on time / late), dishes, photos and the meal's next-time note, with **How it went**
  (the Summary). The latest five show; *Show all N past meals* reveals the rest. Finished meals
  no longer offer *Plan*.
- **⋯ menu** for everything else, by stage:
  - planning: Start prepping, Start cooking
  - prepping: Edit the plan, Start cooking, Back to planning
  - cooking: Edit the plan, Finish cooking, Reset progress
  - complete: Plan it again, Plan it again with the real times (ADR 0024), Reset progress
  - always: Delete meal

  Destructive items still go through `<.confirm_button>`.

## Consequences

- Status is still changed from home (ADR 0002), now from the menu.
- `Photos.count_by_meal/0` counts a meal's own and its dishes' photos for the past list.
- The empty state ("No meals yet") shows only when there are no meals at all.

## Layout

- On wide screens *Next up* sits beside *Plan a new meal*; the form goes full width when
  there's no next meal, and everything stacks on a phone.
- *Past meals* became photo cards below *Coming up*, at full width (ADR 0032), replacing the
  compact past list described above.
