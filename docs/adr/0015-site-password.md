# 0015. One shared password for the site

- Status: Accepted
- Date: 2026-11-07

## Context

ADR 0001 has "log in" as the first step of every flow, but nothing was built: every page,
every delete button and every photo was open to anyone with the address. The app is used by
one household, and the data has no owner column, so user accounts would add a lot for no
benefit yet.

## Decision

- The whole site sits behind **one shared password**, set by `SITE_PASSWORD`. Production
  refuses to start without it; in development it is optional and in tests it is off unless a
  test sets it.
- `/login` asks for the password; once given it is remembered in the session. A log-out button
  in the header forgets it. Everything else, including `/photos/:id`, redirects to `/login`.
- Passwords are compared in constant time. There are no accounts, no email and no reset: the
  password is changed by changing the environment variable.

## Consequences

- `CookingSchedulerWeb.Auth` holds the rule as both a plug (for controllers) and an
  `on_mount` hook (for the `live_session`). New routes go in the protected scope.
- Deploying needs `SITE_PASSWORD` next to `DATABASE_URL` and `SECRET_KEY_BASE` (see README).
- If the app ever needs to be shared beyond one household, replace this with real accounts
  (`mix phx.gen.auth`) and give meals, dishes and the kitchen an owner.
