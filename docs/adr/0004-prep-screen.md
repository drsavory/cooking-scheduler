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

- A **shopping list** link at the top, showing "N of M bought". The list has its own
  screen (`/meals/:id/shopping`, see below).
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
- Shopping ticks are stored (see below), so they survive reloads and are per meal.

## Shopping list

`/meals/:id/shopping`, reached from Prep. Every ingredient in the meal appears
once, A to Z, with the dishes that use it. Amounts are totalled per unit
(500 g + 1 kg, 3 items; never converted); an ingredient with no amounts just
lists its dishes. Tapping an item ticks it off and moves it to a "Bought"
group; "Untick all" resets.

- The list is derived from the meal's dishes, so it always matches them.
- Only the ticks are stored, in `shopping_checks` (meal + ingredient; a row means
  bought). Ticks belong to one meal, so the same ingredient in another meal is
  separate. If an ingredient is removed from every dish its tick simply stops
  showing.
- Dishes follow the list: a dish's "all ingredients in" (Prep step 1) is ticked
  automatically once every one of its ingredients is bought, and unticked when one
  is put back or "Untick all" is used. A dish with no ingredients is never touched, so
  it can still be ticked by hand. Ticking a dish by hand does not tick its ingredients.
