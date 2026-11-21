#!/usr/bin/env bash
# deploy-local.sh — déploie le serveur "energy supervision" (FAP-light + FAP-LDP
# + app supervision), de façon autonome et idempotente.
#
# ENVIRONNEMENT (dans .env) :
#   API_DOMAIN : domaine du BACK (LDP, /auth, /dsp, /editor, /app/query) — localhost en dev,
#     vrai domaine en staging/prod. Le front (../app-supervision) est AUTONOME (vite,
#     cross-origin via FRONT_ORIGINS) : aucune référence au client ici.
#   ENV=dev      → HTTP pur :80 (API_DOMAIN=localhost, pas de certificat) ;
#                  si domaine custom en dev → HTTPS auto-signé (OIDC exige https hors localhost)
#   ENV=staging  → HTTPS auto-signé interne (tls internal)
#   ENV=prod     → HTTPS Let's Encrypt automatique (vrai domaine public, A record → IP)
# SCHEME / BASE_IRI sont dérivés de ENV + API_DOMAIN (et écrits dans .env).
#
# Étapes : .env (secrets auto-générés) → .build/ (flows, initdb, Caddyfile, realm rendus)
# → docker compose up → pg_cron → boot nœud fap-ldp → rejoue sql/ custom → vérifs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="${CORE_DIR:-$HERE/../fap-light-serveur}"
LDP_DIR="${LDP_DIR:-$HERE/../fap-ldp}"
BUILD="$HERE/.build"
ENV_FILE="$HERE/.env"

log() { echo "[deploy] $*"; }
die() { echo "[deploy] ERREUR: $*" >&2; exit 1; }

command -v docker >/dev/null || die "docker requis"
docker compose version >/dev/null 2>&1 || die "docker compose requis (plugin, ex. ~/.docker/cli-plugins/docker-compose)"
[ -d "$CORE_DIR" ] || die "cœur FAP absent: $CORE_DIR"
[ -d "$LDP_DIR" ] || die "extension FAP-LDP absente: $LDP_DIR"

# --- 0. .env + secrets auto-générés -------------------------------------------
if [ ! -f "$ENV_FILE" ]; then cp "$HERE/.env.example" "$ENV_FILE"; log ".env créé depuis .env.example"; fi
set_secret() {
  local var="$1"
  if grep -q "^$var=" "$ENV_FILE"; then
    if grep -q "^$var=CHANGE_ME" "$ENV_FILE" || grep -q "^$var=$" "$ENV_FILE"; then
      sed -i "s|^$var=.*|$var=$(openssl rand -hex 24)|" "$ENV_FILE"
    fi
  else
    echo "$var=$(openssl rand -hex 24)" >> "$ENV_FILE"
  fi
}
for s in PG_ADMIN_PASSWORD PG_GATE_PASSWORD PG_READER_PASSWORD PG_APP_PASSWORD \
         PG_MATERIALIZER_PASSWORD KEYCLOAK_ADMIN_PASSWORD DSP_HMAC_SECRET \
         SFTP_PASSWORD; do
  set_secret "$s"
done
# mot de passe des 3 users de démo (alice/bob/admin) : lisible en dev, aléatoire en staging/prod
if [ "${ENV:-dev}" = "dev" ]; then
  if grep -q "^DEMO_PASSWORD=" "$ENV_FILE"; then sed -i "s|^DEMO_PASSWORD=.*|DEMO_PASSWORD=dev|" "$ENV_FILE"; else echo "DEMO_PASSWORD=dev" >> "$ENV_FILE"; fi
else
  set_secret DEMO_PASSWORD
fi
set -a; . "$ENV_FILE"; set +a

# --- 0b. ENV + domaine → SCHEME / BASE_IRI + origines front (CORS) ----------------
# Un seul domaine : API_DOMAIN = le BACK (LDP racine, /auth, /dsp, /editor, /app/query)
# → BASE_IRI des ressources = $SCHEME://$API_DOMAIN/.
# Le front (../app-supervision) est AUTONOME : servi par vite depuis son propre répertoire,
# il appelle le back en absolu cross-origin — ses origines sont dans FRONT_ORIGINS
# (CORS Caddy + webOrigins/redirectUris Keycloak).
# SCHEME : dev → http si API_DOMAIN=localhost (défaut), https auto-signé sinon (le login
#          OIDC exige un contexte sécurisé hors "localhost") ; staging/prod → https.
ENV="${ENV:-dev}"
API_DOMAIN="${API_DOMAIN:-localhost}"
FRONT_ORIGINS="${FRONT_ORIGINS:-http://app.localhost:5173 http://localhost:5173 http://localhost:5174 http://localhost:3000}"
case "$ENV" in
  dev)     if [ "$API_DOMAIN" = "localhost" ]; then SCHEME="http"; else SCHEME="https"; fi ;;
  staging) SCHEME="https" ;;
  prod)    SCHEME="https" ;;
  *) die "ENV inconnu: $ENV (dev|staging|prod)" ;;
esac
[ "$ENV" = "dev" ] && [ "$API_DOMAIN" != "localhost" ] \
  && log "WARN: dev avec API_DOMAIN=$API_DOMAIN → HTTPS auto-signé (OIDC exige https hors localhost)"
DOMAIN="$API_DOMAIN"   # alias (emails, KC_HOSTNAME) — le back vit sur API_DOMAIN
BASE_IRI="$SCHEME://$API_DOMAIN/"
BASE_IRI_NO_SLASH="$SCHEME://$API_DOMAIN"
# Domaine du FRONT : en dev/staging, caddy rend un site $FRONT_DOMAIN qui proxifie le serveur
# vite du client tournant sur l'hôte (aucun fichier du client monté dans le back).
# En prod, le front est déployé à part (son propre serveur) — pas de site front rendu.
FRONT_DOMAIN="${FRONT_DOMAIN:-app.$API_DOMAIN}"
[ "$ENV" = "dev" ] && [ "$API_DOMAIN" = "localhost" ] && FRONT_DOMAIN="${FRONT_DOMAIN:-app.localhost}"
FRONT_DEV_PORT="${FRONT_DEV_PORT:-5173}"
# synchro dans .env pour docker compose (KC_HOSTNAME, FAP_LDP_BASE_IRI) et les scripts
for kv in "ENV=$ENV" "SCHEME=$SCHEME" "BASE_IRI=$BASE_IRI" "DOMAIN=$DOMAIN" "API_DOMAIN=$API_DOMAIN" "FRONT_DOMAIN=$FRONT_DOMAIN" "FRONT_DEV_PORT=$FRONT_DEV_PORT" "FRONT_ORIGINS=$FRONT_ORIGINS"; do
  k="${kv%%=*}"; v="${kv#*=}"
  line="$k=$v"
  [ "$k" = "FRONT_ORIGINS" ] && line="FRONT_ORIGINS=\"$v\""   # liste d'origines : quotée pour le source .env
  if grep -q "^$k=" "$ENV_FILE"; then sed -i "s|^$k=.*|$line|" "$ENV_FILE"; else echo "$line" >> "$ENV_FILE"; fi
done
export ENV SCHEME BASE_IRI BASE_IRI_NO_SLASH DOMAIN API_DOMAIN FRONT_DOMAIN FRONT_DEV_PORT FRONT_ORIGINS FAP_ORG="${FAP_ORG:-fap-pod}"
set -a; . "$ENV_FILE"; set +a   # recharger (DEMO_PASSWORD peut venir d'être écrit)
# JSON arrays rendus pour le realm Keycloak (envsubst) : webOrigins + redirectUris du front
export FRONT_WEB_ORIGINS FRONT_REDIRECT_URIS
FRONT_WEB_ORIGINS="$(python3 -c 'import json,os;print(json.dumps(os.environ["FRONT_ORIGINS"].split()))')"
FRONT_REDIRECT_URIS="$(python3 -c 'import json,os; o=os.environ["FRONT_ORIGINS"].split(); b=os.environ["BASE_IRI"]; print(json.dumps([b+"app/*", b.rstrip("/")+"/*"]+[x+"/*" for x in o]))')"
log "ENV=$ENV → back: $BASE_IRI (API_DOMAIN=$API_DOMAIN, SCHEME=$SCHEME) · front autonome, origines CORS: $FRONT_ORIGINS"

dc() { docker compose --project-name energy-supervision --env-file "$ENV_FILE" -f "$HERE/compose/docker-compose.yml" "$@"; }

# --- 1. .build/flows — flows cœur + fap-ldp + app-supervision -------------------
CORE_DIR="$CORE_DIR" LDP_DIR="$LDP_DIR" bash "$HERE/scripts/assemble-flows.sh" "$BUILD/flows.json"
cp "$HERE/scripts/orce-settings.js" "$BUILD/orce-settings.js"

# --- 2. .build/initdb — migrations ordonnées : cœur → fap-ldp → custom ---------
# Ne PAS rm -rf le dossier lui-même : il est monté dans le conteneur postgres
# (bind mount sur l'inode) — vider seulement son contenu.
mkdir -p "$BUILD/initdb"
find "$BUILD/initdb" -mindepth 1 -delete
mkdir -p "$BUILD/initdb/sql" "$BUILD/initdb/post"
i=0
for f in "$CORE_DIR"/deploy/postgres/init/sql/0[1-4]*.sql; do
  [ -e "$f" ] && cp "$f" "$BUILD/initdb/sql/$(printf '%02d' $i)_$(basename "$f")" && i=$((i+1))
done
[ -e "$CORE_DIR/deploy/postgres/init/sql/05_pg_cron.sql" ] && cp "$CORE_DIR/deploy/postgres/init/sql/05_pg_cron.sql" "$BUILD/initdb/post/05_pg_cron.sql"
for f in "$LDP_DIR"/core/sql/0*.sql; do
  [ -e "$f" ] && cp "$f" "$BUILD/initdb/sql/$(printf '%02d' $i)_$(basename "$f")" && i=$((i+1))
done
for f in "$HERE"/sql/*.sql; do
  [ -e "$f" ] && cp "$f" "$BUILD/initdb/sql/$(printf '%02d' $i)_custom_$(basename "$f")" && i=$((i+1))
done
cat > "$BUILD/initdb/init.sh" <<'EOF'
#!/bin/bash
set -Eeuo pipefail
PSQL=(psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-admin}"
  -v admin_pw="${POSTGRES_PASSWORD:?}"
  -v gate_pw="${PG_GATE_PASSWORD:?}"
  -v reader_pw="${PG_READER_PASSWORD:?}"
  -v app_pw="${PG_APP_PASSWORD:?}"
  -v materializer_pw="${PG_MATERIALIZER_PASSWORD:-}"
  -v dsp_agreement_id="${DSP_AGREEMENT_ID:-agreement:interne:contrat-cadre}"
  -d "${POSTGRES_DB:-fap}")
DIR="$(dirname "$0")"
for f in "$DIR"/sql/*.sql; do
  echo "[init] $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
EOF
chmod +x "$BUILD/initdb/init.sh"
chmod -R a+rX "$BUILD/initdb"   # les sources fap-ldp peuvent être en 600 — le conteneur tourne en 'postgres'
log "initdb: $(ls "$BUILD/initdb/sql" | wc -l) migrations (cœur → fap-ldp → custom)"

# --- 3. .build/Caddyfile — rendu selon ENV + domaine --------------------------------
# UN SEUL site : le back sur $API_DOMAIN. Le front est autonome (vite, cross-origin) :
# il n'est PAS servi ici. CORS pour FRONT_ORIGINS. Le proxy POST /app/query n'a plus de
# route dédiée : il tombe dans la racine → ORCE (le nœud fap-ldp exclut /app/ du
# middleware LDP, patch C1.9), et son preflight est géré par @preflight (path *).
# SCHEME=http (dev, API_DOMAIN=localhost) : HTTP pur :80, pas de certificat.
# SCHEME=https : dev/staging → tls internal (auto-signé) ; prod → Let's Encrypt auto.
mkdir -p "$BUILD"
BACK_ROUTES='  handle /auth/* {
    # PAS de strip_prefix : Keycloak sert sous /auth (--http-relative-path /auth),
    # il doit voir le chemin /auth pour la validation DPoP (htu) et les redirections.
    # X-Forwarded-* explicites : Keycloak (KC_PROXY_HEADERS=xforwarded) reconstruit
    # scheme/host/port de la requête depuis ces headers.
    reverse_proxy keycloak:8080 {
      header_up X-Forwarded-Host {http.request.host}
      header_up X-Forwarded-Proto {http.request.scheme}
      header_up X-Forwarded-Port {http.request.port}
    }
  }
  handle /dsp/* {
    reverse_proxy orce:1880 {
      # orce renvoie « Access-Control-Allow-Origin: * » → doublon interdit avec
      # celui posé par caddy (@corsOrigin) : on le strippe côté upstream.
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Credentials
    }
  }
  handle /editor* {
    reverse_proxy orce:1880 {
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Credentials
    }
  }
  handle {
    reverse_proxy orce:1880 {
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Credentials
    }
  }'
# Expression CEL « Origin ∈ FRONT_ORIGINS » (le matcher header multi-valeurs n'est pas
# accepté en bloc named matcher → CEL explicite, généré depuis FRONT_ORIGINS)
CORS_CEL="$(python3 -c 'import os; o=os.environ["FRONT_ORIGINS"].split(); print("`" + " || ".join("{http.request.header.Origin} == '"'"'%s'"'"'" % x for x in o) + "`")')"
CORS_ROUTES="  # CORS : le front autonome (FRONT_ORIGINS, ex. vite http://localhost:5173) appelle
  # le back en cross-origin. /auth/* exclu : Keycloak ajoute DÉJÀ ses headers CORS
  # (webOrigins) — un doublon Access-Control-Allow-Origin ferait échouer la requête.
  @corsOrigin {
    not path /auth/*
    expression $CORS_CEL
  }
  @preflight {
    method OPTIONS
    not path /auth/*
    expression $CORS_CEL
  }
  handle @preflight {
    respond 204
  }
  header @corsOrigin Access-Control-Allow-Origin \"{http.request.header.Origin}\"
  header @corsOrigin Access-Control-Allow-Credentials \"true\"
  header @corsOrigin Access-Control-Allow-Methods \"GET, POST, PUT, PATCH, DELETE, OPTIONS\"
  # cache-control/pragma : sibStore / solid-client-authn les envoient en lecture.
  header @corsOrigin Access-Control-Allow-Headers \"Authorization, DPoP, Content-Type, Accept, Origin, Cache-Control, Pragma, If-Match, If-None-Match, Slug, Link\"
  header @corsOrigin Access-Control-Expose-Headers \"Location, ETag, Link, Allow, WAC-Allow, Preference-Applied, Content-Location\"
  header @corsOrigin Vary \"Origin\""
# Site FRONT : en dev/staging, proxy vers le serveur vite du client sur l'hôte
# (le client reste autonome : aucun de ses fichiers n'est monté dans le back).
# En prod, le front est déployé à part → pas de site front rendu ici.
FRONT_SITE=""
if [ "$ENV" != "prod" ]; then
  if [ "$SCHEME" = "http" ]; then
    FRONT_SITE="http://$FRONT_DOMAIN {
  # front (client autonome) : proxy vers le serveur vite de l'hôte — HMR/websocket OK
  reverse_proxy host.docker.internal:$FRONT_DEV_PORT
}"
  else
    FRONT_SITE="https://$FRONT_DOMAIN {
  tls internal
  reverse_proxy host.docker.internal:$FRONT_DEV_PORT
}"
  fi
fi
if [ "$SCHEME" = "http" ]; then
  { echo "# Caddyfile généré par deploy-local.sh — ENV=$ENV, HTTP pur :80 (back: $API_DOMAIN, pas de certificat)."
    [ -n "$FRONT_SITE" ] && { echo; echo "$FRONT_SITE"; }
    echo
    echo ":80 {"
    echo "$CORS_ROUTES"
    echo "$BACK_ROUTES"
    echo "}"
  } > "$BUILD/Caddyfile"
else
  TLS_LINE=""
  [ "$ENV" != "prod" ] && TLS_LINE="  tls internal"
  { echo "# Caddyfile généré par deploy-local.sh — ENV=$ENV SCHEME=https back=$API_DOMAIN"
    [ "$ENV" = "prod" ] && echo "# prod : Let's Encrypt automatique (vrai domaine public, A record → IP). Front déployé à part." \
                       || echo "# $ENV : HTTPS auto-signé interne (tls internal) — CA locale : .build/caddy-root.crt (à importer dans le navigateur)."
    echo
    echo ":80 {"
    echo "  redir https://{host}{uri} permanent"
    echo "}"
    echo
    [ -n "$FRONT_SITE" ] && { echo "$FRONT_SITE"; echo; }
    echo "https://$API_DOMAIN {"
    [ -n "$TLS_LINE" ] && echo "$TLS_LINE"
    echo "$CORS_ROUTES"
    echo "$BACK_ROUTES"
    echo "}"
  } > "$BUILD/Caddyfile"
fi
log "Caddyfile rendu: $BUILD/Caddyfile (ENV=$ENV SCHEME=$SCHEME back=$API_DOMAIN front=${FRONT_DOMAIN:-à part})"

# --- 4. .build/keycloak — realm rendu (BASE_IRI, origines front, FAP_ORG, mdp) ------
mkdir -p "$BUILD/keycloak"
envsubst '${DOMAIN} ${BASE_IRI} ${BASE_IRI_NO_SLASH} ${FRONT_WEB_ORIGINS} ${FRONT_REDIRECT_URIS} ${FAP_ORG} ${DEMO_PASSWORD}' \
  < "$HERE/keycloak/realm.json" > "$BUILD/keycloak/realm.json"
log "realm rendu: $BUILD/keycloak/realm.json (BASE_IRI=$BASE_IRI)"
log "users de démo Keycloak : alice / bob / admin — mot de passe: ${DEMO_PASSWORD:-dev} (dev)"

# --- 5. up ----------------------------------------------------------------------
cd "$HERE"
dc up -d
# les fichiers montés (Caddyfile, realm) ne déclenchent pas de recreate : restart pour recharger
dc restart caddy >/dev/null && log "caddy rechargé (Caddyfile rendu)"
dc up -d --force-recreate keycloak >/dev/null 2>&1 || true   # realm importé au boot : recréer pour prendre le rendu (base H2 interne)
until dc exec -T postgres pg_isready -U admin -d fap >/dev/null 2>&1; do sleep 1; done
log "postgres healthy"

# pg_cron après le 1er boot (05_pg_cron.sql hors du scan initdb)
dc exec -T postgres psql -U admin -d fap -v ON_ERROR_STOP=1 \
  -f /docker-entrypoint-initdb.d/post/05_pg_cron.sql >/dev/null && log "pg_cron installé (materializers 10 min)"

# --- 6. attendre le boot du nœud fap-ldp (applique config/model.json) ------------
log "attente du boot fap-ldp (model applied)…"
applied=0
for i in $(seq 1 60); do
  if dc logs orce 2>/dev/null | grep -q "model applied"; then applied=1; break; fi
  sleep 2
done
[ "$applied" = 1 ] || log "WARN: 'model applied' non vu dans les logs orce (vérifier: docker compose logs orce)"
# garde-fou : les flows chargés doivent être les flows assemblés (cœur + fap-ldp + custom)
# → comparaison par hash (le nombre de nœuds ne suffit pas après une édition de func)
n="$(dc exec -T orce md5sum /data/flows.json 2>/dev/null | cut -d' ' -f1)"
attendu="$(md5sum "$BUILD/flows.json" | cut -d' ' -f1)"
if [ "$n" != "$attendu" ]; then
  log "flows non à jour dans orce (md5 $n != $attendu) — copie + restart"
  dc exec -T orce cp /flows-app/flows.json /data/flows.json
  dc restart orce >/dev/null
  for i in $(seq 1 30); do
    dc logs orce 2>/dev/null | grep -q "model applied" && break
    sleep 2
  done
fi

# --- 7. rejoue des migrations custom post-boot (app.* existe maintenant) ---------
# 101_seed_demo.sql et 102_acl_init.sql prennent la base IRI en variable psql (-v base_iri=...)
for f in "$BUILD"/initdb/sql/*custom*.sql; do
  [ -e "$f" ] || continue
  dc exec -T postgres psql -U admin -d fap -v ON_ERROR_STOP=1 -v base_iri="$BASE_IRI" \
    -f "/docker-entrypoint-initdb.d/sql/$(basename "$f")" >/dev/null \
    && log "rejeu post-boot: $(basename "$f")"
done
# le PEP fap-ldp cache les colonnes par table (node.columns) au 1er accès : après une
# migration custom (ex. CR-2 area_m2), restart orce pour vider ce cache
dc restart orce >/dev/null && log "orce redémarré (cache colonnes vidé après migrations custom)"
for i in $(seq 1 30); do
  dc logs orce 2>/dev/null | grep -q "model applied" && break
  sleep 2
done

# --- 8. vérifications -------------------------------------------------------------
[ "$SCHEME" = "https" ] && CURL="curl -sk" || CURL="curl -s"   # -k : cert auto-signé interne
BASE="$SCHEME://$API_DOMAIN"
log "vérifs (back=$BASE):"
$CURL -s -o /dev/null -w "  GET  $BASE/                  → %{http_code} (racine LDP)\n" "$BASE/"
$CURL -s -o /dev/null -w "  GET  $BASE/tickets/          → %{http_code} (401/403 attendu sans session)\n" "$BASE/tickets/"
$CURL -s -X POST "$BASE/dsp/catalogue/request" | head -c 120; echo "  ← catalogue DSP"
$CURL -s -X POST "$BASE/app/query" -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}' \
  -o /dev/null -w "  POST $BASE/app/query          → %{http_code} (401 attendu sans session, CA-S10)\n"
$CURL -s -o /dev/null -w "  OPTIONS $BASE/buildings/ (CORS preflight, Origin front) → %{http_code}\n" \
  -X OPTIONS "$BASE/buildings/" -H "Origin: ${FRONT_ORIGINS%% *}" -H "Access-Control-Request-Method: GET"
$CURL -s "$BASE/auth/realms/fap-light/.well-known/openid-configuration" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("  issuer:", d["issuer"])' 2>/dev/null || true
# en HTTPS auto-signé : extraire le CA local pour l'import dans le navigateur (Firefox/Chrome)
if [ "$SCHEME" = "https" ] && [ "$ENV" != "prod" ]; then
  dc exec -T caddy cat /data/caddy/pki/authorities/local/root.crt > "$BUILD/caddy-root.crt" 2>/dev/null \
    && log "CA local Caddy exportée: $BUILD/caddy-root.crt (à importer dans Firefox : Paramètres → Certificats)"
fi
log "OK — back: $BASE/ (LDP) · $BASE/auth/realms/fap-light (IdP) · $BASE/dsp/ · $BASE/editor/ · POST $BASE/app/query (proxy signé)"
log "     front AUTONOME : cd ../app-supervision && ./scripts/configure.sh $BASE && npm run dev → http://app.localhost/ (caddy :80 → vite)"
