# 0029. Sized dishes, past versions, and inside temperature

- Status: Accepted
- Date: 2026-11-21
- Amends: 0017, 0024

## Context

A turkey is one dish in the library, but each one is a different weight, and the weight
decides the cook time. When choosing a dish we want to see every turkey we've cooked, not
just the recipe. Some dishes are also done when the inside reaches a temperature, not when a
timer runs out.

Variants like gravy are a different case: onion gravy and red-wine gravy are different
recipes, not different sizes of one.

## Decision

- **Sized dishes.** A library dish can carry a cook-time rule: `minutes_per_size` per
  `size_unit` (kg or lb) plus `base_minutes`. A dish with a rule is *sized*
  (`MealDish.sized?/1`). The rule is optional and is set on the New dish form ("Cook time
  depends on the weight?") or on the dish page.
- **Meal dishes copy the rule and keep their own `size`.** Cook time is
  `base + per × size` (`MealDish.cook_for_size/2`). Changing the weight (or the rule) resets
  the cook time; typing a cook time in the same change wins, so it stays editable.
- **Adding a sized dish asks for its weight.** In *Your dishes*, a sized dish shows its rule
  and "cooked N times, last 5.2 kg", and picking it opens a weight step instead of adding it
  straight away. The weight is prefilled from the last one cooked (`Meals.suggested_size/2`,
  converted through `UnitConversion` if it was weighed in the other unit), the cook time
  previews as you type, and you choose to start from the saved recipe or from a past version
  (its meal, weight, planned vs took, lateness and next-time note, from `dish_history/1`).
- **Starting from a past version** copies that version's times, temperature, notes and
  ingredients. The cook-time rule always comes from the library dish, so the weight is in its
  unit and improving the rule improves every future one.
- A sized dish made on the modal's *New dish* tab goes to the weight step rather than into the
  meal with a guessed time.
- **Inside temperature.** Any dish can have `done_temp` in °C or °F (°C unless said), copied
  into meals. It is shown in both scales, converted through `UnitConversion`, on the plan row,
  on the cook screen's "out" task and in-progress card, and on the dish page.
- **Variants stay separate dishes.** Gravies and stuffings are separate library dishes grouped
  with tags (`sauce`, or your own like `gravy`). There's no parent/child dish tree.

## Consequences

- The plan card shows *Weight* in Timing for sized dishes and *Done when* for every dish; the
  dish page shows weight per meal and the rule on the library dish. Past versions show their
  weight in *How it went*.
- Weight and the rule are copied with meals (`copy_meal_dishes/2`), so "plan it again"
  keeps last year's weight until you change it.
- Not done yet: suggesting a better rule from the history (e.g. "your last three averaged
  44m per kg"), and a `family` field to fold variants into one row if tags get crowded.
