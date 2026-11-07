# 0007. Kitchen load on the Plan screen

- Status: Accepted
- Date: 2026-11-07

## Context

With oven space tracked (ADR 0005) the planner can say "not enough room", but
not how close each appliance is to its limit. Rest times are the main lever for
freeing an oven, and there was nothing to show where they would help.

## Decision

The Plan screen shows a **Kitchen load** panel above the dish list: one strip
per appliance that has something in it, on a shared time axis running from the
earliest start to serving.

- Ovens: bar height is the share of the oven in use (stacked from dish space),
  coloured green, amber at 75%+, solid amber when full and red if over.
  The label gives the peak.
- Hob rings and other appliances hold one thing at a time, so they are shown as
  simply in use or free.
- Only time on the heat counts; rest happens off the appliance, so lengthening a
  rest visibly frees the oven earlier. The panel updates as dishes are edited.

`Planner.load/2` computes this from planned entries (pure, no database).
