# 0013. Photos on a finished meal

- Status: Accepted
- Date: 2026-11-07

## Context

We want to keep pictures of how a meal and its dishes turned out, to look back on next year.
A dish only has something to photograph once it is cooked, so photos don't belong on the
planning or dish screens.

## Decision

- A new **Summary** screen, `/meals/:id/summary`, exists for a **complete** meal. Any other
  meal is sent to its cook screen. It shows the date and whether dinner was on time, a gallery
  for the meal, and a gallery for each dish that was finished (dishes skipped by "Finish
  cooking" are left out).
- It is reached from the home page: a complete meal's card shows **Photos** in place of
  **Cook** (Reset progress still allows cooking again). "Finish cooking" on the cook screen
  also lands here.
- A **photo** belongs to a meal (`meal_id`) or to one dish in a meal (`meal_dish_id`), never
  both (database check). Library dishes have none: a photo records what actually got cooked.
- Choosing files uploads them straight away (up to 6 at a time, 10 MB each). Delete uses the
  in-app confirm dialog. Each gallery is a `PhotoGallery` live component, since a page holds
  several and each needs its own upload.
- Photos are **viewed** on the dish screen, read-only. A library dish (`/dishes/:id`) shows the
  photos from every meal it has been cooked in, newest meal first, each captioned with its meal
  and linking to that meal's summary, so a dish's pictures build up over the years. A dish
  inside a meal shows its own. Adding and deleting happens only on the summary.
- Files live behind `CookingScheduler.Storage`: `Storage.Local` (`tmp/storage`) in dev and
  tests, `Storage.Tigris` in production when `BUCKET_NAME` is set (as `fly storage create`
  does, with `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`). With no adapter the galleries
  are hidden.
- The bucket is private. Images are served by `GET /photos/:id`, which reads from storage.
- Type is decided by the file's first bytes (JPEG, PNG, WebP, GIF), not the browser's claim.
- Deleting a meal, a meal dish or a photo also deletes the stored files.

## Consequences

- Images are served as uploaded, with no resizing or thumbnails. Add resizing if large phone
  photos make the grid slow.
- HEIC isn't accepted; phones normally convert to JPEG when picking from a browser.
- The Summary screen is the place to grow into a record of the meal (notes, what to change
  next time).
