# 0024. What happened last time: actuals, notes, and planning again

- Status: Accepted
- Date: 2026-11-09

## Context

The cook screen recorded when every dish went in and came out and how much time was added, but
nothing ever showed it back, and a new meal copied the *planned* times. ADR 0013 left the
Summary as the place to grow a record of the meal.

## Decision

- **Summary** shows a *How it went* table for every timed dish: planned in/out, actual in/out,
  how long it took against the plan, and the result against its course (on time, late, early,
  not cooked).
- **Next time** notes: a free-text note on the meal and on each meal dish, saved as you type on
  the Summary. A meal dish's note shows on its dish page; a library dish shows a *How it went*
  history of every complete meal it was in (took vs planned, result, note); the home page dish
  card shows the last one in a line, and the next-up hero shows the meal note.
- **Plan it again with the real times** on the Summary, and *Use the times that actually
  happened* when starting a meal from a cooked one on Home: each dish's cook time becomes
  `Meals.actual_cook/1` (out − in when both are known, else planned + extra).
  `Meals.create_meal_from/3` takes `actual_times: true`.

## Consequences

- Still nothing is shared between meals; the copy just starts from better numbers.
- `lateness/2` (per course, ADR 0018) is the one definition of early/late used everywhere.
