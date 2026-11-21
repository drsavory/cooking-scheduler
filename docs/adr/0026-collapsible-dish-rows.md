# 0026. Plan screen: dish rows open to edit

- Status: Accepted (supersedes the inputs row of 0016)
- Date: 2026-11-21

## Context

With prep timing, serving course, temperature, scale, space and oven all on show, every dish
on the Plan screen wrapped to two rows of nine labelled boxes. The plan read as a wall of
form fields; most of the time the cook only wants to see what happens when.

## Decision

- **Closed by default**: each dish is one line: method icon, name, a muted summary of its
  settings ("20m prep · 1h 20m cook · 15m rest · gas 7 · half oven"), the time chips, the
  oven badge, and edit / view / remove.
- **Open to edit**: tapping the name or the chevron opens the settings under the row, grouped
  as *Dish* (name), *Timing* (prep, cook, rest, when to prep, serve with), the heat source
  (temp, scale, space, oven; ring; appliance) and *Notes* (notes, recipe link, checklist).
  The separate "more" button is gone.
- Several rows can be open at once; which ones is kept on the server so a row stays open when
  an edit moves it to another part of the day.
- A row opens on its own when it has no cooking time or an invalid entry.
- Issues and "Try:" fixes stay visible on the closed row.
- The settings are always rendered (hidden when closed) so autosave sees the whole form.
