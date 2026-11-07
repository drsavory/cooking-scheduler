# 0004. Prep screen

- Status: Accepted
- Date: 2026-11-07

## Context

Getting a meal ready to cook meant opening the Plan screen, opening each dish's
"more" menu and ticking "All ingredients in" and "Prepped" one dish at a time.
That is the work done in the days before cooking, and it was buried.

## Decision

Add a **Prep** view for a meal at `/meals/:id/prep`, between Plan and Cook:
plan, then prep, then cook.

- A **shopping list** at the top: every ingredient in the meal once, A to Z, with
  the dishes that use it. Amounts are totalled per unit (500 g + 1 kg, never
  converted); an ingredient with no amounts just lists the dishes. It is derived,
  not stored, so it has no ticks.
- Step 1, **Check the ingredients are in**: one large tick per dish ("all ingredients
  in"), each listing the dish's ingredients and amounts. "Everything's in" ticks
  them all.
- Step 2, **Prep ahead**: one tick per dish that has prep time, showing the prep
  time and notes.
- A progress bar counts ticks done out of ticks needed. "Ready to cook" leads on
  to Cook.
- The ticks are the existing per-dish `ingredients_in` and `prepped` flags, so
  Cook's prep tasks stay in step. They are removed from the Plan screen's "more"
  menu only if they stop being useful there; for now both places edit the same flags.

### Reaching it

- Home: "Start prepping" on a planning meal sets it to `prepping` (ADR 0002) and
  opens Prep. A prepping meal shows "Open prep".
- Plan: a "Start prepping" / "Open prep" button, same behaviour.
- Opening Prep for a meal still in `planning` shows a banner with "Start
  prepping"; the status is never changed silently (ADR 0002: the cook's choice).
- Ticking is allowed in any status.

## Consequences

- Prep is one more view of the same meal; no new data.
- Per-ingredient ticks on the shopping list are not done. They need a place to
  store per-ingredient state for a meal.
