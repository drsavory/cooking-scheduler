# 0005. Oven space

- Status: Accepted
- Date: 2026-11-07

## Context

Auto-placement only looked at temperature, so it would happily put a turkey and
a nut roast in the same oven at the same time.

## Decision

Every oven dish has an **Oven space**: whole oven, half, third or quarter
(default third). It is set on the new-dish form, the dish detail page and the
Plan screen, is copied between library and meal dishes, and is stored in
twelfths so fractions add up exactly.

The planner only suggests an oven if the dishes already in it at that time,
plus the new one, total no more than one oven. Pinning a dish to an oven that
has no room left shows a "Not enough room" warning instead of blocking it.
Temperature compatibility rules are unchanged.
