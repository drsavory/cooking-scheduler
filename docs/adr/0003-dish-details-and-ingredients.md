# 0003. Dish detail view and ingredients

- Status: Accepted
- Date: 2026-11-07

## Context

Dish details could only be seen by editing the dish: inline on the Plan screen,
or on the dish form. There was no way to just look at a dish and its cooking
details, and nowhere to record what goes into it.

## Decision

### Dish detail view

Every dish has a detail page showing its cooking details (method, heat,
prep / cook / buffer / rest times, notes, recipe link) and its ingredients.

| Dish | Route | Reached from |
|------|-------|--------------|
| Dish in a meal | `/meals/:meal_id/dishes/:id` | Eye icon on the Plan screen; "Details" on a Cook task (returns to Cook) |
| Library dish | `/dishes/:id` | Clicking its name in the home page Dishes list |

It is viewable and editable in every meal status.

### Editing

Editing happens on the detail page itself, in the same layout, so there is no
separate edit screen to get lost in. The boxes are **locked until Edit is
pressed**. While editing, nothing is saved until **Save**; **Cancel** discards
the changes. Invalid values show an error and can't be saved. (The Plan screen's
cards still autosave, as before.) Ingredients are added and removed directly,
with their own Add button. The "New dish" form is only for creating a dish, and
leads to its detail page afterwards.

### Ingredients

- Ingredients are one **shared list**. An ingredient (e.g. butter) exists once,
  matched case-insensitively, and any number of dishes use it.
- A dish has ingredients **with an optional amount**, stored as a number plus a
  unit chosen from a dropdown: `g`, `kg`, `ml`, `l`, `tsp`, `tbsp`, `cup`,
  `pinch`. No unit means whole items, shown as "2 items" and chosen as "items" in the dropdown. Amounts accept decimals and
  fractions ("1.5", "1/2", "1 1/2"). A unit without an amount is dropped.
  Adding an ingredient the dish already has updates the amount.
- Removing an ingredient from a dish never deletes it from the shared list.
- Ingredients are optional; they are added and removed from the detail view.

### Copying

Ingredients follow the same independence rules as the rest of a dish
(see ADR 0001):

- Copying a meal, or adding a library dish to a meal, **copies** the
  ingredients. Meals stay independent.
- Changing ingredients on a meal dish updates its library dish, under the same
  rule as other details: not for placeholder names, and not once the meal has
  been started.
- Changing ingredients on a **library dish** also replaces the ingredients of
  that dish in every meal that is still `planning` or `prepping`, so ingredients
  added from the Dishes list show up in meals already planned. Meals that are
  `cooking` or `complete` are historical and are left alone. This applies to
  ingredients only; other library dish details still don't reach existing meals.
  Because it replaces the list, ingredients added on a meal's own copy are lost
  when the library dish's ingredients change. Edits on a meal dish never spread
  to other meals, only to the library.

## Consequences

- Two owners (meal dish, library dish) share one `dish_ingredients` table, with a
  database check that exactly one owner is set.
- No shopping list or unit conversion yet. Amounts are structured, so a shopping
  list can total them later, but only within the same unit (g with g, not g
  with kg) until conversion exists.
