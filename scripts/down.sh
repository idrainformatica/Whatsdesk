#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

docker compose --env-file .env.local down --remove-orphans 2>/dev/null || true
(cd supabase-docker && docker compose down --remove-orphans)

echo "Everything is stopped."