# 0020. Plan screen reads like the day, and offers fixes

- Status: Accepted
- Date: 2026-11-09

## Context

Plan rows were in the order dishes were added. Placement problems ("No oven with room…") only
showed on the affected row, and the cook had to guess what change would make it fit. Adding a
dish from a past meal meant copying the whole menu, and only onto an empty plan.

## Decision

- **Order**: rows are sorted by when you start them (prep, or in if no prep on the day), under
  dividers for *The day before*, *Morning*, *Afternoon*, *Evening*. Dishes with no cooking time
  go last under *Needs a cooking time*. Rows move when a time edit changes the order; focus
  stays in the box being edited.
- **Problems summary**: a band above the list counts the dishes with issues, names them and
  jumps to the first.
- **Fixes**: `Planner.suggest/4` tries small changes for a dish with issues (a longer rest in
  steps, another oven, both) by re-planning the whole meal, keeping only those that clear the
  dish's issues without making another dish worse. Up to three show as "Try: Rest 30m longer"
  buttons on the row; tapping one applies it with the normal autosave.
- **From a meal**: the Add dish modal has a third tab that lists a chosen past meal's dishes
  with per-dish Add buttons (`Meals.copy_meal_dish/2`, ingredients included, progress cleared).
  Dishes already in the plan (by name) are marked instead.

## Consequences

- Suggestions re-plan a few times per problem dish on every load; fine at kitchen scale.
- The "Copy from {meal}" buttons on an empty plan stay as the quick path.
