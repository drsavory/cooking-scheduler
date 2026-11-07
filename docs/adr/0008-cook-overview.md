# 0008. Whole-meal overview on the Cook screen

- Status: Accepted
- Date: 2026-11-07

## Context

The Cook screen only showed the next tasks and in-progress dishes, so there was
no sense of the whole meal: what is still ahead, what overlaps, how it ends.
The big clock/dinner banner took a lot of room for little information.

## Decision

- The header is a single compact bar: clock, dinner time (with ±5m), status.
- Below it, an **overview timeline** ("The whole meal"): one row per dish on a
  shared time axis from the earliest prep (or now) to the projected serve time.
  Each row shows prep, time on the heat, then rest. A "now" line and a serve
  line cross all rows; hour gridlines give scale.
- Rows are **grouped by appliance** (ovens, then rings, then others, then "No appliance"),
  each group under a small header, so you can see what each one is doing and when.
- Hovering (or focusing) a row shows a tooltip like the plan's kitchen load: the dish, its
  appliance and state, prep / cooking / resting clock times, and the temperature.
- "Up next" and the side column (in progress, resting, done) stay as they were.

The timeline is derived from `Cooking.lives/2` (actual start/finish/extra time),
so it moves as things run late.
