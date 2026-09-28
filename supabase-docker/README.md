# Self-hosted Supabase stack

Vendored from the `docker/` directory of https://github.com/supabase/supabase
at the commit recorded in `VERSION`, trimmed to the services this app uses
(auth, rest, realtime, storage, imgproxy, api-gw, db). See `docs/docker.md`
for the full runbook.

Configuration lives in `.env` (template: `.env.example`). Generate the
secrets with `../scripts/supabase-secrets.sh`, then fill the SMTP section.
The file is gitignored.

Runtime data (gitignored):

- `volumes/db/data` — the Postgres data directory
- `volumes/storage` — uploaded files (avatars, chat-media, flow-media)

Gateway: http://127.0.0.1:8000 (`/auth/v1`, `/rest/v1`, `/storage/v1`,
`/realtime/v1`).

To re-add Studio, postgres-meta, Supavisor or Edge Runtime, copy the service
blocks from the upstream compose at the pinned commit and restore any env
vars they reference (`DASHBOARD_*`, `POOLER_*`, `FUNCTIONS_VERIFY_JWT` are
already in `.env.example`).
