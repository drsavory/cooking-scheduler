# 0018. Courses: a dish's own serving time

- Status: Accepted
- Date: 2026-11-09

## Context

Every dish was planned to be ready at the meal's one serving time, so a starter, the main and a
pudding all landed at once and the last twenty minutes were a pile-up. A pudding that should be
in the oven while the main is eaten had to be faked with a long rest.

## Decision

- A dish has a **serving offset** (`serve_offset_minutes`, signed, default 0): minutes after
  the meal's serving time it is ready. Negative is a starter, positive a pudding or cheese.
  Kept within six hours either side.
- It lives on both the library dish and the meal dish, and is copied with the rest of the
  template (ADR 0009).
- The planner counts each dish back from `meal serve + offset`. Everything downstream (kitchen
  load, oven events, the cook timeline, tasks) already works from the entry times, so it
  follows. The cook timeline draws one serve line per course; the kitchen load panel runs to the
  last course.
- "Running behind" is judged per course: a pudding due an hour after the main is not late.
  Likewise a meal's recorded delay (ADR 0002) is the most any dish was ready after *its* course.
- Chosen with a **Serve** chip on the plan row (Starter 45m before · With the main · Pudding
  45m / 1h after · Cheese 1h 30m after; a value set elsewhere shows as "Custom"), and on the
  dish page and new-dish form. The plan row shows a Starter / Pudding badge when set.

## Consequences

- Multi-course meals plan realistically without hacks; the oven is free between courses.
- The header still shows one "Dinner at" time (the main's). Moving dinner moves every course.
