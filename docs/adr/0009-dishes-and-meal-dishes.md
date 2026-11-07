# 0009. Dishes and meal dishes

- Status: Accepted
- Date: 2026-11-07

## Context

We had `dishes` (a dish inside one meal) and `saved_dishes` (the reusable library). The
names made the library sound secondary, when it is the list people choose from.

## Decision

- **Dish** (`dishes`, `Meals.Dish`) is a dish you can choose from, e.g. "Roast turkey". It
  carries the default times, temperature, notes, ingredients and tags.
- **Meal dish** (`meal_dishes`, `Meals.MealDish`) is one dish's instance in a meal. It starts
  as a copy of a dish and keeps `dish_id` pointing back to it. It also holds the day's
  state: prepped, ingredients in, cooking progress, appliance choice.
- `dish_ingredients` belongs to either a meal dish (`meal_dish_id`) or a dish (`dish_id`).
- Context functions follow the names: `list_dishes/0`, `create_dish/1`, `add_dish_to_meal/2`
  for the library; `list_meal_dishes/1`, `create_meal_dish/2`, `add_meal_dish/3` for a meal.
- Behaviour is unchanged: no screens, routes or flows moved.

## Consequences

- Supersedes the "saved dish" wording in earlier ADRs; read it as "dish".
- Forms for a meal dish post under `meal_dish[...]`; the library form stays `dish[...]`.
- Local variables in LiveViews are still often called `dish` where they hold a meal dish.
