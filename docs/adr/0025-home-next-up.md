# 0025. Home: next up, and a proper new-meal form

- Status: Accepted
- Date: 2026-11-09

## Context

Home listed every meal equally, so the one you were about to cook had no more prominence than
last year's. A new meal was always "New meal", dated today, for 13:30.

## Decision

- A **Next up** hero at the top: the soonest unfinished meal dated today or later, or failing
  that the most recent unfinished one. It shows the date in words, dinner time, dish count, the
  meal's next-time note, and the action for its stage (keep planning / start prepping, open prep
  / cook, back to cooking).
- The **new meal form** asks for name, date and dinner time up front (defaults kept), plus the
  start-from meal and, when there is a cooked meal, the actual-times checkbox (ADR 0024).
- Spotlight (ADR 0012) also matches dishes by ingredient and says "uses sumac" in the result.

## Consequences

- The meal grid below is unchanged and remains the history.
