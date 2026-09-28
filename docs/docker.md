# Running with Docker

The repo ships a multi-stage `Dockerfile` (Next.js standalone output,
runs as a non-root user) and **two compose projects**:

- `docker-compose.yml` — the app (`wacrm` project), published on
  http://127.0.0.1:3000.
- `supabase-docker/docker-compose.yml` — a vendored, trimmed
  self-hosted Supabase stack (`supabase` project) providing Postgres 17
  (+pgvector), GoTrue (auth), PostgREST, Realtime, Storage and an Envoy
  API gateway on http://127.0.0.1:8000.

The app still works against a cloud Supabase project if you prefer —
just point the env vars at it — but the default here is fully local.

## Prerequisites

- Docker Engine + Compose v2. On WSL2 with Docker Desktop, enable
  **Settings → Resources → WSL Integration** for your distro.
- ~2 GB of free RAM for the stack plus the app build.

## Quick start

1. Copy the env template and fill it in:

   ```bash
   cp .env.local.example .env.local
   ```

   Set at least `ENCRYPTION_KEY` and `META_APP_SECRET` (see the comments
   inside). Leave the Supabase URL pointing at `http://127.0.0.1:8000`.

2. Generate the stack secrets (creates `supabase-docker/.env` with the
   Postgres password, JWT secret, anon + service-role keys):

   ```bash
   ./scripts/supabase-secrets.sh
   ```

3. Fill the SMTP section of `supabase-docker/.env` — GoTrue needs a
   working SMTP server to deliver signup confirmations and password
   resets (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`,
   `SMTP_ADMIN_EMAIL`, `SMTP_SENDER_NAME`).

4. Copy `ANON_KEY` and `SERVICE_ROLE_KEY` from `supabase-docker/.env`
   into `.env.local` (`NEXT_PUBLIC_SUPABASE_ANON_KEY` and
   `SUPABASE_SERVICE_ROLE_KEY`).

5. Start everything (stack → wait for health → apply the database
   migrations → build and start the app):

   ```bash
   ./scripts/up.sh
   ```

The app is served on http://127.0.0.1:3000, the Supabase API on
http://127.0.0.1:8000. Port 3000 must be free — stop `npm run dev`
first (`up.sh` refuses to start otherwise).

> Use `HOST_PORT` in `.env.local` to publish the app elsewhere. `PORT`
> is what the server listens on _inside_ the container and is pinned by
> compose.

## Scripts

| Script | What it does |
| --- | --- |
| `scripts/up.sh` | Starts the Supabase stack, waits for health, applies migrations, builds and starts the app |
| `scripts/down.sh` | Stops both compose projects (data is kept) |
| `scripts/apply-migrations.sh` | Replays `supabase/migrations/*.sql` in order against the running `supabase-db` container (idempotent) |
| `scripts/supabase-secrets.sh` | Regenerates all secrets in `supabase-docker/.env` (run only on a fresh install — the DB password and JWT secret are baked into the running stack) |

## Build-time vs runtime variables

- `NEXT_PUBLIC_*` variables are **inlined into the client bundle at
  build time**. They are passed as Docker build args by
  `docker-compose.yml`. If you change any of them, rebuild:
  `docker compose --env-file .env.local up --build -d`. This includes
  `NEXT_PUBLIC_APP_LOCALE` (`en | it | ko | pt | es`), so the UI
  language is fixed per image.
- Everything else (`SUPABASE_SERVICE_ROLE_KEY`, `ENCRYPTION_KEY`,
  `META_APP_SECRET`, …) is read at **runtime** from `.env.local` via
  `env_file` and is never baked into the image — safe to change with
  just a container restart.
- `SUPABASE_URL` is set by `docker-compose.yml` to
  `http://host.docker.internal:8000` at runtime: containers cannot
  reach the host's `127.0.0.1`, so server-side code (middleware,
  service-role clients) talks to the gateway through the host. The
  browser keeps using `NEXT_PUBLIC_SUPABASE_URL`. `npm run dev` does
  not set it and talks to `http://127.0.0.1:8000` directly.
  The session cookie name is pinned to `sb-wacrm-auth-token` in the
  three client factories (`src/lib/supabase/client.ts`,
  `src/lib/supabase/server.ts`, `src/middleware.ts`): supabase-js
  derives the default cookie name from the URL hostname, and with
  different browser/server URLs the two sides would look for
  different cookies — the middleware would never see the session and
  would bounce every request back to `/login`.

## The Supabase stack

Vendored from the upstream `supabase/supabase` `docker/` directory
(commit in `supabase-docker/VERSION`) and trimmed to what this app
uses:

| Service | Image | Purpose |
| --- | --- | --- |
| `db` | `supabase/postgres:17.6.1.136` | Postgres 17 + pgvector, roles (`anon`/`authenticated`/`service_role`), realtime publication |
| `auth` | `supabase/gotrue:v2.196.0` | Email/password auth, sessions, SMTP |
| `rest` | `postgrest/postgrest:v14.17` | The REST API behind `supabase.from()` |
| `realtime` | `supabase/realtime:v2.134.10` | `postgres_changes` subscriptions |
| `storage` + `imgproxy` | `supabase/storage-api:v1.74.0` | Buckets `avatars`, `chat-media`, `flow-media` |
| `api-gw` | `envoyproxy/envoy:v1.39.1` | Single entry point on :8000 (`/auth/v1`, `/rest/v1`, `/storage/v1`, `/realtime/v1`) |

Not included (the app doesn't use them): Studio, postgres-meta,
Supavisor, Edge Runtime. To re-add one, copy the service block from the
upstream compose at the pinned commit and add back any env vars it
references.

The migrations in `supabase/migrations/` run **after** the stack is
healthy, because they reference `auth.users` (created by GoTrue at
startup) and `storage.buckets` (created by the Storage API). They are
idempotent, so `scripts/apply-migrations.sh` can be re-run safely.
Postgres is not published on the host; use
`docker exec -it supabase-db psql -U postgres -d postgres` for ad-hoc
SQL.

## Backups

- Database: `docker exec supabase-db pg_dump -U postgres postgres > backup.sql`
- Files: the `supabase-docker/volumes/storage/` folder
- Restore: `docker exec -i supabase-db psql -U postgres postgres < backup.sql`

## Plain Docker (no Compose)

The app image itself is Supabase-agnostic — you can build and run it
against any Supabase (self-hosted or cloud):

```bash
docker build \
  --build-arg NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:8000 \
  --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key \
  -t wacrm .

docker run -d --env-file .env.local -e PORT=3000 -p 3000:3000 wacrm
```

## Notes

- Received attachments are copied into the `chat-media` Storage bucket,
  because Meta deletes media roughly 30 days after it arrives and the
  copy is the only thing that outlives that. With the self-hosted stack
  the bucket lives in `supabase-docker/volumes/storage/` — watch disk
  usage. Turn it off per account under Settings → WhatsApp → Attachment
  Storage; attachments received while it's off become unviewable once
  Meta drops them. Files over 16 MB (the bucket's limit) are never
  copied.
- Nothing inside the container is scheduled. If you use automation Wait
  steps or flows, point an external scheduler at
  `GET /api/automations/cron` and `GET /api/flows/cron` on this
  deployment, sending the shared secret in the `x-cron-secret` header
  (`AUTOMATION_CRON_SECRET`, see `.env.local.example`). Both return 503
  until that variable is set.
- SMTP via Gmail: Google may rewrite the `From:` header to the
  authenticated account unless the sending address is configured as a
  "Send mail as" alias in that Google account.
- Reset-password links target `/auth/callback?next=/reset-password`, a
  route that does not exist yet in the app (upstream gap, unchanged by
  the self-hosted setup).
