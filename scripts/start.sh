#!/usr/bin/env bash
# start.sh — starts the energy-supervision BACKEND (full docker stack).
# The front (../app-supervision) is AUTONOMOUS: it is launched separately from its
# own directory (see the summary printed at the end of the script).
#
# Usage: ./scripts/start.sh [--reset]
#   --reset: docker compose down -v first (volumes deleted: data lost,
#             full re-seed at boot — useful after a BASE_IRI/domain change)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
RESET=0
for a in "$@"; do
  case "$a" in
    --reset) RESET=1 ;;
    *) echo "[start] unknown option: $a (expected: --reset)" >&2; exit 2 ;;
  esac
done

dc() { docker compose --project-name energy-supervision --env-file "$HERE/.env" -f "$HERE/compose/docker-compose.yml" "$@"; }

if [ "$RESET" = 1 ]; then
  echo "[start] --reset: shutdown + volume deletion (data lost)…"
  dc down -v || true
fi

echo "[start] backend deployment (deploy-local.sh)…"
bash "$HERE/scripts/deploy-local.sh"

# .env was synchronized by deploy-local.sh: re-read the derived URLs
set -a; . "$HERE/.env"; set +a
SCHEME="${SCHEME:-http}"; API_DOMAIN="${API_DOMAIN:-localhost}"
BASE_IRI="${BASE_IRI:-$SCHEME://$API_DOMAIN/}"
BASE="$SCHEME://$API_DOMAIN"

echo
echo "[start] ============================================================"
echo "[start]  energy-supervision Backend started. BACK URLs:"
echo "[start]    LDP (JSON-LD)      : $BASE_IRI   (e.g. ${BASE_IRI}buildings/ with Bearer)"
echo "[start]    IdP (Keycloak)     : ${BASE_IRI}auth/realms/fap-light   (users: alice/bob/admin, password: ${DEMO_PASSWORD:-dev})"
echo "[start]    DSP (catalog)      : POST ${BASE_IRI}dsp/catalogue/request"
echo "[start]    Signed proxy       : POST ${BASE_IRI}app/query  (OIDC/DPoP session required, CORS ok)"
echo "[start]    Node-RED editor    : ${BASE_IRI}editor/"
if [ "$SCHEME" = "https" ] && [ "${ENV:-dev}" != "prod" ]; then
  echo "[start]    Self-signed certificate: import .build/caddy-root.crt ONCE into the browser"
fi
echo "[start]  ------------------------------------------------------------"
echo "[start]  FRONT (autonomous, from its own directory):"
echo "[start]    cd ../app-supervision && ./scripts/configure.sh $BASE && npm run dev"
echo "[start]    → http://app.localhost/   (port 80 via caddy ; cross-origin calls to $BASE, CORS handled)"
echo "[start] ============================================================"
