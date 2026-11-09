# Cooking Scheduler

Plans a big meal (Christmas dinner, say) backwards from the serving time: which dish goes in
which oven or on which ring, when prep has to start, a shopping list, and a live cook screen
that keeps every device in the kitchen in step. Product decisions are recorded in `docs/adr/`.

## Running it locally

You need Elixir, Erlang and a local PostgreSQL (user and password `postgres`).

```sh
mix setup          # deps, database, seeds (a kitchen and "Christmas 2025")
mix phx.server     # http://localhost:4000
```

Photos are kept on disk under `tmp/storage` in development. To try the site password
locally, start with `SITE_PASSWORD=something mix phx.server`.

Before committing, run `mix precommit` (compile with warnings as errors, format, test).

## Deploying

The app is a standard Phoenix release and expects these environment variables:

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Postgres, e.g. `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | from `mix phx.gen.secret` |
| `PHX_HOST` | the public host name |
| `SITE_PASSWORD` | the one password that opens the site (ADR 0015) |
| `TZ` | the kitchen's time zone, e.g. `Europe/London`; the cook screen runs in local time |
| `BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | optional: a Tigris bucket for photos, as `fly storage create` sets up. Without one, the photo galleries are hidden |

The container image needs time zone data installed for `TZ` names like `Europe/London` to
work (`tzdata` on Debian); a POSIX string such as `GMT0BST,M3.5.0/1,M10.5.0` works without it.
