#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: docker compose is not available." >&2
  echo "Start Docker Desktop and enable Settings > Resources > WSL Integration for this distro." >&2
  exit 1
fi

if [ ! -f supabase-docker/.env ]; then
  ./scripts/supabase-secrets.sh
fi

if grep -q 'replace-with-smtp-host' supabase-docker/.env; then
  echo "Warning: SMTP_HOST in supabase-docker/.env is still a placeholder." >&2
  echo "Signup confirmation and password reset emails will not be delivered." >&2
fi

if ss -tln 2>/dev/null | grep -qE ':(3000)\s'; then
  echo "Error: port 3000 is already in use." >&2
  echo "Stop the running dev server (npm run dev) or set HOST_PORT in .env.local." >&2
  exit 1
fi

echo "==> Starting the Supabase stack"
(cd supabase-docker && docker compose up -d)

GW_PORT="$(grep -E '^API_GW_HTTP_PORT=' supabase-docker/.env | cut -d= -f2 || true)"
GW_PORT="${GW_PORT:-8000}"
ANON_KEY="$(grep -E '^ANON_KEY=' supabase-docker/.env | cut -d= -f2-)"

echo "==> Waiting for the stack to become healthy"
ready=0
for _ in $(seq 1 90); do
  db_h="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' supabase-db 2>/dev/null || echo missing)"
  auth_h="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' supabase-auth 2>/dev/null || echo missing)"
  storage_h="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' supabase-storage 2>/dev/null || echo missing)"
  gw_h="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' supabase-envoy 2>/dev/null || echo missing)"
  if [ "$db_h" = healthy ] && [ "$auth_h" = healthy ] && [ "$storage_h" = healthy ] && [ "$gw_h" = healthy ]; then
    ready=1
    break
  fi
  sleep 2
done

if [ "$ready" != 1 ]; then
  echo "Error: the Supabase stack did not become healthy in time." >&2
  docker compose -f supabase-docker/docker-compose.yml ps
  exit 1
fi

if curl -fsS -H "apikey: ${ANON_KEY}" -H "Authorization: Bearer ${ANON_KEY}" "http://127.0.0.1:${GW_PORT}/auth/v1/health" >/dev/null 2>&1; then
  echo "Gateway is answering on http://127.0.0.1:${GW_PORT}"
else
  echo "Error: gateway health check failed on http://127.0.0.1:${GW_PORT}" >&2
  docker logs supabase-envoy --tail 20 || true
  exit 1
fi

echo "==> Applying database migrations"
./scripts/apply-migrations.sh

echo "==> Building and starting the app"
docker compose --env-file .env.local up -d --build

echo ""
echo "Done. App: http://127.0.0.1:3000  Supabase API: http://127.0.0.1:${GW_PORT}"