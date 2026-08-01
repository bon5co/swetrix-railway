#!/bin/sh
# Wait for ClickHouse to answer, then start the API.
set -eu

CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-http://localhost}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-8123}"
PING_URL="${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/ping"
ATTEMPTS="${CLICKHOUSE_WAIT_ATTEMPTS:-90}"
INTERVAL="${CLICKHOUSE_WAIT_INTERVAL:-5}"

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
  if wget --no-verbose --tries=1 --timeout=5 -O /dev/null "$PING_URL" 2>/dev/null; then
    echo "[swetrix-api] ClickHouse ready at ${PING_URL} (attempt ${attempt})"
    exec npm run start:prod
  fi
  echo "[swetrix-api] waiting for ClickHouse at ${PING_URL} (${attempt}/${ATTEMPTS})"
  attempt=$((attempt + 1))
  sleep "$INTERVAL"
done

echo "[swetrix-api] ClickHouse unreachable at ${PING_URL} after ${ATTEMPTS} attempts" >&2
exit 1
