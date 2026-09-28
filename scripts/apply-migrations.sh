#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_CONTAINER="supabase-db"

if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  echo "Error: container $DB_CONTAINER is not running." >&2
  exit 1
fi

shopt -s nullglob
files=("$ROOT_DIR"/supabase/migrations/*.sql)
if [ "${#files[@]}" -eq 0 ]; then
  echo "Error: no migration files found in supabase/migrations." >&2
  exit 1
fi

for sql in "${files[@]}"; do
  name="$(basename "$sql")"
  echo "==> Applying $name"
  docker exec -i "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d postgres < "$sql"
done

echo "All ${#files[@]} migrations applied."