#!/usr/bin/env bash
# start.sh — démarre le BACKEND energy-supervision (stack docker complète).
# Le front (../app-supervision) est AUTONOME : il se lance séparément depuis son
# propre répertoire (voir le résumé affiché en fin de script).
#
# Usage : ./scripts/start.sh [--reset]
#   --reset : docker compose down -v d'abord (volumes supprimés : données perdues,
#             re-seed complet au boot — utile après un changement de BASE_IRI/domaine)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
RESET=0
for a in "$@"; do
  case "$a" in
    --reset) RESET=1 ;;
    *) echo "[start] option inconnue: $a (attendu: --reset)" >&2; exit 2 ;;
  esac
done

dc() { docker compose --project-name energy-supervision --env-file "$HERE/.env" -f "$HERE/compose/docker-compose.yml" "$@"; }

if [ "$RESET" = 1 ]; then
  echo "[start] --reset : arrêt + suppression des volumes (données perdues)…"
  dc down -v || true
fi

echo "[start] déploiement backend (deploy-local.sh)…"
bash "$HERE/scripts/deploy-local.sh"

# .env a été synchronisé par deploy-local.sh : on relit les URLs dérivées
set -a; . "$HERE/.env"; set +a
SCHEME="${SCHEME:-http}"; API_DOMAIN="${API_DOMAIN:-localhost}"
BASE_IRI="${BASE_IRI:-$SCHEME://$API_DOMAIN/}"
BASE="$SCHEME://$API_DOMAIN"

echo
echo "[start] ============================================================"
echo "[start]  Backend energy-supervision démarré. URLs du BACK :"
echo "[start]    LDP (JSON-LD)      : $BASE_IRI   (ex. ${BASE_IRI}buildings/ avec Bearer)"
echo "[start]    IdP (Keycloak)     : ${BASE_IRI}auth/realms/fap-light   (users: alice/bob/admin, mdp: ${DEMO_PASSWORD:-dev})"
echo "[start]    DSP (catalogue)    : POST ${BASE_IRI}dsp/catalogue/request"
echo "[start]    Proxy signé        : POST ${BASE_IRI}app/query  (session OIDC/DPoP requise, CORS ok)"
echo "[start]    Editeur Node-RED   : ${BASE_IRI}editor/"
if [ "$SCHEME" = "https" ] && [ "${ENV:-dev}" != "prod" ]; then
  echo "[start]    Certificat auto-signé : importer UNE FOIS .build/caddy-root.crt dans le navigateur"
fi
echo "[start]  ------------------------------------------------------------"
echo "[start]  FRONT (autonome, depuis son propre répertoire) :"
echo "[start]    cd ../app-supervision && ./scripts/configure.sh $BASE && npm run dev"
echo "[start]    → http://app.localhost/   (port 80 via caddy ; appels cross-origin vers $BASE, CORS géré)"
echo "[start] ============================================================"
