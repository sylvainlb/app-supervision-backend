#!/usr/bin/env bash
# stop.sh — stops the energy-supervision BACKEND:
#   docker compose down (volumes are KEPT: ./scripts/start.sh restarts as-is,
#   ./scripts/start.sh --reset to start from scratch).
# The front (../app-supervision) is autonomous: stop it separately (Ctrl-C on npm run dev).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo "[stop] stopping the energy-supervision stack (volumes kept)…"
docker compose --project-name energy-supervision --env-file "$HERE/.env" \
  -f "$HERE/compose/docker-compose.yml" down

echo "[stop] OK. Restart the back: ./scripts/start.sh   (full reset: ./scripts/start.sh --reset)"
