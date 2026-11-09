# 0019. Cook screen aids: oven tasks, alerts, kitchen mode, run sheet

- Status: Accepted
- Date: 2026-11-09

## Context

Nothing on the cook screen made a noise, the tablet went to sleep, the oven's own jobs
("switch it on", "7 then 4") lived in notes, and fourteen dishes made "Up next" a long scroll.

## Decision

### Oven tasks

`Planner.oven_events/2` derives, per oven, from the planned entries:

- **Preheat**: "Switch on *Main oven* to gas 7", the oven's `preheat_minutes` (set on Setup,
  default 15) before the first dish goes in.
- **Adjust**: "Turn *Main oven* to gas 4" when a dish going in wants a different temperature
  from what the oven is set to (the last temperature asked of it).

The temperature is shown in the oven's own scale through `UnitConversion`. Events show as chips
under the plan's kitchen load panel and as tasks in Cook's "Up next" (kinds `:preheat` and
`:adjust`, with the dish they are for). They are ticked like any task; ticks are stored on the
meal (`oven_marks`, `"preheat:<oven id>:<dish id>"`), cleared by Reset progress, and an oven task
also counts as done once its dish has gone in. If the dish is running late the oven task follows
it.

### Ovens at a glance

A strip under the header shows each oven (and any other appliance in use): its setting, what is
in it, "heating up" after the preheat is ticked, or "free".

### Alerts and keep-awake

A colocated hook on the header (`#cook-tools`) owns per-device settings in `localStorage`:

- **Sound** (bell button): when the server says a task has just become due (`tasks_due`,
  pushed when the set of now/overdue tasks gains members, never on first load), play a two-note
  chime from the Web Audio API and, if the tab is hidden and permission was granted, show a
  browser notification. Turning sound on asks for notification permission.
- **Kitchen mode** (magnifier button): adds `kitchen-big` to `<html>`, which bumps the root font
  size so everything scales up for greasy hands and arm's length.
- A screen **wake lock** is requested while the cook screen is open and re-requested when the
  tab becomes visible.

### Up next, folded

The next four tasks show in full; the rest sit under "Later (n) · next at hh:mm".

### Run sheet

`/meals/:id/sheet` lists every planned step of the day in clock order (oven jobs, prep, in, out,
serve per course) under parts of the day, with a tick box, and a Print button. A print
stylesheet hides the chrome. Linked from the cook screen.

## Consequences

- No sound file is shipped; the chime is synthesised.
- Notifications only fire when the page is hidden, so a visible screen just chimes.
- `Cooking.Task` gained an `event` field; dish tasks have it nil.
