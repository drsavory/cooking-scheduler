# 0033. Summary: led by photos, one card per dish

- Status: Accepted
- Date: 2026-11-21
- Amends: 0013, 0024, 0032

## Context

The Summary listed every dish three times, in a wide timing table, a column of notes and a
gallery per dish, each its own full-width section. It was spread out, and the photos came last.

## Decision

- **Header**: name, date, an on time / late pill, "7 of 9 dishes on time", the photo count,
  and *Plan it again with the real times*.
- **Mosaic** under it: every photo of the meal (its own first, then each dish's), the first
  large with four beside it and "+N" on the last. Any of them opens the viewer.
- **The table** beside **Next time**: the meal's own gallery, and its next-time note, side by
  side on wide screens.
- **The dishes**: one card per timed dish, 1 to 3 across, holding its name and result, a
  compact *In / Out / Took* row (what happened, with the plan underneath when it differs), a
  compact gallery when it was cooked, and its next-time note. The timing table and the
  separate notes and gallery sections are gone.
- **The viewer is shared** with home (`CookingSchedulerWeb.PhotoViewer`: `viewer/1`,
  `mosaic/1`, and `handle/3` for its events). Tapping a photo in any gallery opens it there
  instead of a new tab; a gallery tells the page `:photos_changed` after an upload or delete,
  so the mosaic keeps up.

## Consequences

- `PhotoGallery` takes `compact` for the dish cards.
- Adding and deleting photos still happens only here.
