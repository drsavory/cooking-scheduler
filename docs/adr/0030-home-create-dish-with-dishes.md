# 0030. Home: "New dish" lives with the dishes

- Status: Accepted
- Date: 2026-11-21
- Amends: 0001, 0024

## Context

The home page's new-meal form ended with **Create meal** and **Create dish** side by side, so
making a dish looked like part of starting a meal. The *Use the times that actually happened*
box also showed whenever any meal had been cooked, even when starting from scratch or from a
meal that hadn't been cooked, where it does nothing.

## Decision

- The new-meal form is only about the meal: name, date, time, what to start from, and
  **Create meal**.
- **New dish** is a small button in the *Dishes* section heading, next to the count. It still
  goes to `/dishes/new` (`#create-dish`).
- *Use the times that actually happened* appears only once the meal chosen in *Start from* is
  complete (it has real times to use).

## Consequences

- ADR 0001's two primary actions are still on the home page, each next to what it makes.
- The form sends change events so it knows the chosen meal; what's typed is kept in the form's
  state.
