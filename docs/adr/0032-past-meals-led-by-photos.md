# 0032. Past meals are led by their photos

- Status: Accepted
- Date: 2026-11-21
- Amends: 0013, 0031

## Context

The photos are the best record of a meal, but on home a past meal was a line of text and its
pictures were two clicks away on the Summary, one gallery per dish.

## Decision

- **Past meals are photo cards**, full width below *Coming up*: 1 column on a phone, 2 on a
  tablet, 3 on a wide screen; the latest six, then *Show all N past meals*.
- Each card leads with a **mosaic**: the first photo large with the next two beside it, and
  "+N" on the last when there are more; a meal with one or two photos shows the first alone.
  The meal's own photos come first, then each dish's in dish order (`Photos.by_meal/1`).
  Below: name, date, on time/late, dishes and photos, *How it went* and the ⋯ menu. A meal
  with no photos shows a dashed *Add photos* box linking to its Summary.
- **Clicking a photo opens a full-screen viewer** on that photo, for that meal's photos:
  previous/next buttons, ← → and Esc, swiping on touch screens, and a strip of thumbnails to
  jump about. It wraps round at either end, shows "2 / 12", captions each photo with its dish
  ("The table" for the meal's own), links to *How it went*, and preloads the neighbours so
  stepping feels instant.
- The viewer is server state on the home LiveView (`viewer: %{meal_id, index}`); only
  swiping needs JavaScript (a colocated `.PhotoSwipe` hook that sends the same step event).

## Consequences

- Home loads every past meal's photo records (not the images) up front; images load lazily
  at full size, so the thumbnail-resizing note in ADR 0013 matters more as photos pile up.
- Adding and deleting photos still happens only on the Summary.
