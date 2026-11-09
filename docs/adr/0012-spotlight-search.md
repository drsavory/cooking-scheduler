# 0012. Spotlight search

- Status: Accepted
- Date: 2026-11-07

## Context

Meals and dishes pile up. When you already know the name, scrolling the home page or
filtering by tag is slow, and you may be on another screen entirely.

## Decision

- Pressing `/` on **any** screen (when not typing in a field) opens a spotlight-style
  search dialog. A search button in the header does the same for touch/mouse.
- It searches pages (currently just Home), meals (by name) and dishes (by name and tags),
  grouped under Pages, Meals and Dishes. Pages open their route, meals open their plan and
  dishes open their detail page. Pages carry their own `href`, so the server decides where
  they go.
- Arrow keys move the selection, Enter opens it, Escape or a backdrop click closes it.
- The dialog lives in `Layouts.app`. A colocated hook sends the query to the current
  LiveView, which an `on_mount` hook (`SearchHook`) answers, so pages don't load search
  data themselves and results are always fresh.
