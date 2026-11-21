# 0028. Kitchen load bars jump to their dish

- Status: Accepted
- Date: 2026-11-21
- Amends: 0027

## Context

The Kitchen load panel shows which dish is in which oven slot, but to change one you had to
find its row in the plan yourself.

## Decision

- Clicking (or pressing Enter on) a dish's bar in the Kitchen load scrolls to that dish's row
  on the Plan screen and opens its settings (ADR 0026). The row flashes a ring briefly so
  your eye lands on it.
- The bar is a link to `#dish-card-<id>`, so the jump works even before the server replies.
  The row has a scroll margin so it isn't hidden under the sticky header.
- Hover and focus still show the tooltip.
