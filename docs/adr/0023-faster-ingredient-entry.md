# 0023. Faster ingredient entry: paste a list, import a recipe

- Status: Accepted
- Date: 2026-11-09

## Context

Ingredients went in one at a time through three boxes. Most dishes come from a web recipe that
already lists them.

## Decision

- **Paste a list** on the dish page: one ingredient per line, read by
  `DishIngredient.parse_line/1` ("200 g butter", "2 onions, finely chopped", "1 1/2 cups flour",
  "½ tsp cumin", "a pinch of nutmeg", "2 x 400g tins tomatoes", "salt"). Bullets and list
  numbers are stripped, text after a comma or bracket is dropped from the name, ounces, pounds,
  fluid ounces and pints become grams or millilitres through `UnitConversion`. Unreadable lines
  are reported, not guessed.
- **Import from the recipe link**: `RecipeImport.fetch/1` gets the page with `Req` and reads
  the schema.org `Recipe` from its JSON-LD (handles `@graph` and lists; no HTML parser). It
  returns the name, prep and cook times (ISO 8601 durations; total minus prep when there is no
  cook time) and the ingredient lines.
  - On the **dish page** the button adds the ingredients and fills prep/cook only where the dish
    has none. Runs with `start_async` so the page stays live.
  - On the **new-dish form** it fills blank boxes (name, times, link) and keeps the ingredient
    lines to add on save.
- Tests stub the request with `:recipe_import_req` (Req's `plug:` option). No new dependency.

## Consequences

- Sites without JSON-LD say "doesn't have a recipe we can read"; nothing is scraped from HTML.
- A 10 s timeout and no retries keep a slow site from hanging the page.
