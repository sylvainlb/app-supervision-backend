#!/usr/bin/env bash
# stop.sh — arrête le BACKEND energy-supervision :
#   docker compose down (les volumes sont CONSERVÉS : ./scripts/start.sh relance tel quel,
#   ./scripts/start.sh --reset pour repartir à zéro).
# Le front (../app-supervision) est autonome : l'arrêter séparément (Ctrl-C sur npm run dev).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo "[stop] arrêt de la stack energy-supervision (volumes conservés)…"
docker compose --project-name energy-supervision --env-file "$HERE/.env" \
  -f "$HERE/compose/docker-compose.yml" down

echo "[stop] OK. Relance du back : ./scripts/start.sh   (reset complet : ./scripts/start.sh --reset)"
