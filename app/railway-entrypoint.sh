#!/bin/bash
# Start the Swetrix frontend and the same-origin nginx gateway, and exit if
# either one stops.
set -euo pipefail

LISTEN_PORT="${PORT:-8080}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
API_UPSTREAM="${API_UPSTREAM:-swetrix-api:5005}"

# Railway variables are often written as full URLs; nginx wants host:port.
API_UPSTREAM="${API_UPSTREAM#http://}"
API_UPSTREAM="${API_UPSTREAM#https://}"
API_UPSTREAM="${API_UPSTREAM%/}"
case "$API_UPSTREAM" in
  *:*) ;;
  *) API_UPSTREAM="${API_UPSTREAM}:5005" ;;
esac

if [ -z "${BASE_URL:-}" ]; then
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    export BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
  else
    export BASE_URL="http://localhost:${LISTEN_PORT}"
  fi
fi
# The UI derives its API base from BASE_URL, and a trailing slash would produce
# `https://host//backend`.
BASE_URL="${BASE_URL%/}"
export BASE_URL

# The API is reached through this container, not directly by the browser, so the
# frontend's server-side calls go to the same upstream nginx proxies to.
export API_ORIGIN="${API_ORIGIN:-http://${API_UPSTREAM}}"

RESOLVER="$(awk '/^nameserver/ { print $2; exit }' /etc/resolv.conf)"
[ -n "$RESOLVER" ] || RESOLVER="127.0.0.11"
case "$RESOLVER" in
  \[*\]) ;;
  *:*) RESOLVER="[${RESOLVER}]" ;;
esac

sed \
  -e "s|__LISTEN_PORT__|${LISTEN_PORT}|g" \
  -e "s|__FRONTEND_PORT__|${FRONTEND_PORT}|g" \
  -e "s|__API_UPSTREAM__|${API_UPSTREAM}|g" \
  -e "s|__RESOLVER__|${RESOLVER}|g" \
  /etc/nginx/railway.conf.template > /etc/nginx/http.d/swetrix.conf

echo "[swetrix] listen=${LISTEN_PORT} frontend=127.0.0.1:${FRONTEND_PORT} api=${API_UPSTREAM} base_url=${BASE_URL}"
nginx -t

cd /app
PORT="$FRONTEND_PORT" HOST=127.0.0.1 npm run start &
frontend_pid=$!

nginx -g 'daemon off;' &
nginx_pid=$!

terminate() {
  kill "$frontend_pid" "$nginx_pid" 2>/dev/null || true
  wait "$frontend_pid" "$nginx_pid" 2>/dev/null || true
  exit 0
}
trap terminate TERM INT

# Whichever exits first takes the container down with it, so a dead frontend
# does not sit behind a gateway that still answers the healthcheck.
wait -n
echo "[swetrix] a process exited; shutting the container down" >&2
kill "$frontend_pid" "$nginx_pid" 2>/dev/null || true
exit 1
