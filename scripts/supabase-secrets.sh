#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/supabase-docker/.env"

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required but not found." >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT_DIR/supabase-docker/.env.example" "$ENV_FILE"
  echo "Created $ENV_FILE from template."
fi

gen_hex() { openssl rand -hex "$1"; }
gen_base64() { openssl rand -base64 "$1"; }

base64_url_encode() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }

jwt_secret="$(gen_base64 30)"
header='{"alg":"HS256","typ":"JWT"}'
iat=$(date +%s)
exp=$((iat + 5 * 3600 * 24 * 365))

gen_token() {
  payload="$1"
  payload_base64=$(printf %s "$payload" | base64_url_encode)
  header_base64=$(printf %s "$header" | base64_url_encode)
  signed_content="${header_base64}.${payload_base64}"
  signature=$(printf %s "$signed_content" | openssl dgst -binary -sha256 -hmac "$jwt_secret" | base64_url_encode)
  printf '%s' "${signed_content}.${signature}"
}

anon_key="$(gen_token "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")"
service_role_key="$(gen_token "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")"

postgres_password="$(gen_hex 16)"
dashboard_username="admin-$(gen_hex 4)"
dashboard_password="$(gen_hex 16)"
secret_key_base="$(gen_base64 48)"
realtime_db_enc_key="$(gen_hex 8)"
vault_enc_key="$(gen_hex 16)"
pg_meta_crypto_key="$(gen_base64 24)"
s3_protocol_access_key_id="$(gen_hex 16)"
s3_protocol_access_key_secret="$(gen_hex 32)"

sed -i \
  -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${postgres_password}|" \
  -e "s|^JWT_SECRET=.*|JWT_SECRET=${jwt_secret}|" \
  -e "s|^ANON_KEY=.*|ANON_KEY=${anon_key}|" \
  -e "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=${service_role_key}|" \
  -e "s|^DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=${dashboard_username}|" \
  -e "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${dashboard_password}|" \
  -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=${secret_key_base}|" \
  -e "s|^REALTIME_DB_ENC_KEY=.*|REALTIME_DB_ENC_KEY=${realtime_db_enc_key}|" \
  -e "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=${vault_enc_key}|" \
  -e "s|^PG_META_CRYPTO_KEY=.*|PG_META_CRYPTO_KEY=${pg_meta_crypto_key}|" \
  -e "s|^S3_PROTOCOL_ACCESS_KEY_ID=.*|S3_PROTOCOL_ACCESS_KEY_ID=${s3_protocol_access_key_id}|" \
  -e "s|^S3_PROTOCOL_ACCESS_KEY_SECRET=.*|S3_PROTOCOL_ACCESS_KEY_SECRET=${s3_protocol_access_key_secret}|" \
  "$ENV_FILE"

echo "Secrets written to $ENV_FILE."
echo "Copy ANON_KEY and SERVICE_ROLE_KEY from there into .env.local if not done yet."