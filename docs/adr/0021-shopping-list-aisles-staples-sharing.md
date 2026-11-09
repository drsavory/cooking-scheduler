# 0021. Shopping list: aisles, cupboard staples, totals, sharing

- Status: Accepted
- Date: 2026-11-09

## Context

The shopping list was one A to Z list. Salt and oil appeared on it every time, 500 g and 1 kg
of the same thing showed as two amounts, and the list could only be used by someone holding
the app.

## Decision

- An **ingredient** (the shared record, ADR 0003) has an optional aisle `category` (fruit & veg,
  meat & fish, dairy & eggs, bakery, cupboard, frozen, drinks) and a `staple` flag.
- Both are set from a small tag button on a shopping row or a dish's ingredient row (shared
  `ingredient_filing` components). Filing once applies everywhere the ingredient is used.
- The list groups to-buy items by aisle in shop order, with unfiled items first so they get
  filed. **Staples** sit in a collapsed *Check the cupboard* group, don't count towards "N of M
  bought", and count as "in" for a dish's *all ingredients in* tick.
- Amounts are **totalled across metric units** through `UnitConversion` (500 g + 1 kg → 1.5 kg;
  1.5 l + 200 ml → 1.7 l; the big unit from 1 kg / 1 l up). Spoons, cups and counts stay
  separate, as "1 tbsp + 2 tsp" is more useful than "25 ml".
- **Share list** produces plain text (grouped by aisle, then the cupboard checks) via the Web
  Share API on phones or the clipboard elsewhere.

## Consequences

- `shopping_checks` are unchanged; a staple can still be ticked, it just lives elsewhere.
- Changing an ingredient's staple flag re-derives "all ingredients in" for every meal using it.
