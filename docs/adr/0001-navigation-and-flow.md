# 0001. Navigation and product flow

- Status: Accepted
- Date: 2026-11-07

## Context

The UI grew screen by screen (Meals, Library, Dishes, Cook, plus a redirect
controller) and the flow became unclear. We need one product direction to
build against before writing more code.

## Decision

There are two user flows.

### 1. Initial setup (first login only)

1. Log in.
2. Set up the kitchen (appliances, etc.).
3. Land on the **home page**.

### 2. Usage after setup (every later login)

Log in and land directly on the **home page**. There is no other entry point.

### Home page

- Focused on meals and dishes. The kitchen is rarely changed, so it only gets a small
  "Kitchen settings" link (plus the nav link), not a banner or summary.
- Primary actions: **Create dish** and **Create meal**.
- Lists **historical meals** and **dishes** in a clear, readable way.
  - Each meal shows: number of dishes, prep time, and how delayed it was
    (recorded on the meal).
  - Dishes are reusable ideas for future meals.

### Core views

| View | Purpose | Style |
|------|---------|-------|
| Create dish | Capture a new dish idea for use in future meals | Form |
| Plan meal | Build a meal and its schedule | Table-like: all info visible in one place |
| Cook meal | Run a meal live | Dynamic, real-time |

### Rules

- **Creating a meal** either starts from scratch or **from any previous meal**
  (the user picks which; never an implicit "last one" such as last Christmas's).
- **Cooking** is started on a **user-chosen meal**, not necessarily the latest.
- **Every meal is its own unique instance**, even if it has the same dishes as
  an earlier one. Starting from a previous meal copies it into a new, independent
  meal. Nothing is shared or aggregated between them.
- Cooking timings (start, actuals, delays) belong to that one meal. To cook the
  same dishes again, create a new meal from the old one.
- Planning and cooking are separate views of the same meal: plan first, then
  cook.

## Consequences

- Home is the single hub. Separate top-level Library/Dishes/Meals screens are
  folded into it or become secondary.
- No separate cook session entity is needed: cooking progress and delays live
  on the meal itself. Meal stats (dish count, prep time, delay) are read
  directly from it.
- "Start from previous meal" means copying a meal's dishes/plan into a new
  meal; it does not link or mutate the original.
- Routing: after login, redirect to setup if the kitchen is not configured,
  otherwise to home.

## Implementation status

- Done: home hub (create dish/meal, meal and dish lists with stats, small kitchen settings link), create/edit
  dish form, per-meal plan and cook routes (`/meals/:id/plan`, `/meals/:id/cook`), removal
  of the implicit "current meal", the Library page and the redirect controller.
- Meal status and delay are derived from the meal's dishes (`Meals.summarize/2`); no
  separate cook session entity.
- The library auto-updates from edits to a meal's dishes only until that meal has been
  started; after that the meal is a historical record.
- Not done: the plan view is still per-dish cards, not the table-like layout above.
- Login is one shared password for the whole site (ADR 0015); there are no user accounts.

## Open questions

- Assumed: a meal is cooked once. Revisit if re-cooking the same meal is needed.
- The "Start from last year's menu" starter on an empty plan is a leftover from before
  this ADR. Keep, or replace with "start from a previous meal" only.
