# 0017 – Plan screen: adding a dish goes through the library

**Status:** accepted (amends 0001 and 0003)

The Plan screen had three "Oven / Hob / Slow cooker dish" buttons that dropped a placeholder
dish into the meal to be filled in on its card, plus a separate strip for saved dishes. That
made the plan card a recipe editor, and placeholders ("New oven dish") leaked into the library.

Now there is one **Add dish** button. It opens an in-app modal with two tabs:

- **Your dishes** – the library dishes not already in this meal, with a search box. Picking
  one adds a copy to the meal (as before) and closes the modal.
- **New dish** – the `/dishes/new` form itself, rendered inside the modal as a nested
  LiveView. Saving creates the library dish *and* adds it to the meal, then closes the modal.
  Cancel just closes it.

The modal opens on **New dish** when the library has nothing left to offer, otherwise on
**Your dishes**. Escape, the backdrop and the close button all dismiss it.

Consequences:

- Every meal dish starts life as a library dish. There are no more placeholder dishes, so the
  starter menu and "copy from a meal" are the only other ways dishes enter a meal.
- `DishFormLive` renders without the app layout when nested and reports back to its parent
  with messages rather than navigating.
- `Meals.add_meal_dish/3` (the placeholder maker) is no longer used by any screen but is kept.
