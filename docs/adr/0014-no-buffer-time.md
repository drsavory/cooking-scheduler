# 0014. No separate buffer time

- Status: Accepted
- Date: 2026-11-07

## Context

Each dish had four times: prep, cook, buffer and rest. Buffer was the spreadsheet's
"adjustment" on top of the suggested cooking time. In practice it was only ever added to
the cook time, so it was one more box to fill in with no decision behind it.

## Decision

- Dishes have **prep, cook and rest** times only. Cook time is the whole time on the heat;
  any margin goes into it.
- Existing buffers are folded into cook time by migration, so planned schedules don't move.
- The starter menu's cook times are the sheet's suggested time plus its adjustment.

## Consequences

- Dish forms (library, plan and dish detail) show three time boxes.
- Any dish with a cook time counts as a timed dish for cook progress and meal status.
