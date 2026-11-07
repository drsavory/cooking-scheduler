# 0006. Dish tags

- Status: Accepted
- Date: 2026-11-07

## Context

The home page lists every saved dish alphabetically. As the library grows it is hard
to find "a veg to go with the roast" or "a starter".

## Decision

- Saved dishes carry free-form **tags** (`tags` string array, lowercase). A dish can have many.
- A few are suggested as one-tap chips (main, protein, veg, carbs, side, starter, dessert,
  sauce); users can add their own, comma separated.
- Tags live on the library dish only. They are not copied into a meal's dish.
- The home page Dishes section shows each dish's tags and a filter row of every tag in use
  (with counts). Tapping a tag shows only dishes with it; tapping it again clears the filter.
- Tags are edited on the dish page (Edit) and set when creating a dish.

## Consequences

- No separate tags table, so renaming a tag across dishes is not supported yet.
