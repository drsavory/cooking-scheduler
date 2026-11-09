# 0022. When prep happens

- Status: Accepted
- Date: 2026-11-09

## Context

A dish's prep time was always scheduled immediately before it went on, yet "Prep on the 24th"
was the real intent for several dishes and lived in a note. The Prep screen listed prep-ahead
dishes with no sense of when.

## Decision

- A dish has `prep_day`: *just before cooking* (default, as before), *morning of*, or *day
  before*. On the library dish and the meal dish; copied with the template.
- Set with a **Prep** chip on the plan row (shown once the dish has prep time), on the dish page
  and on the new-dish form.
- **Prep screen** step 2 is split into *The day before*, *The morning of*, *Just before cooking*.
  All can be ticked; ticking a just-before dish means you got ahead. The header shows how far
  off the meal is ("in 3 days").
- **Cook screen**: a prep task appears for just-before dishes, and for ahead dishes only if
  they were never ticked. The timeline draws a prep segment under the same rule.

## Consequences

- The planner's `prep_at` is unchanged (still `in − prep`); only who shows it differs.
