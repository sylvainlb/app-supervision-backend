#!/usr/bin/env bash
# deploy-local.sh — deploys the "energy supervision" server (FAP-light + FAP-LDP
# + app supervision), autonomously and idempotently.
#
# ENVIRONMENT (in .env):
#   API_DOMAIN: domain of the BACK (LDP, /auth, /dsp, /editor, /app/query) — localhost in dev,
#     real domain in staging/prod. The front (../app-supervision) is AUTONOMOUS (vite,
#     cross-origin via FRONT_ORIGINS): no client reference here.
#   ENV=dev      → pure HTTP :80 (API_DOMAIN=localhost, no certificate) ;
#                  if custom domain in dev → self-signed HTTPS (OIDC requires https outside localhost)
#   ENV=staging  → internal self-signed HTTPS (tls internal)
#   ENV=prod     → automatic Let's Encrypt HTTPS (real public domain, A record → IP)
# SCHEME / BASE_IRI are derived from ENV + API_DOMAIN (and written to .env).
#
# Steps: .env (auto-generated secrets) → .build/ (rendered flows, initdb, Caddyfile, realm)
# → docker compose up → pg_cron → fap-ldp node boot → replay sql/ custom → checks.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="${CORE_DIR:-$HERE/../fap-light-serveur}"
LDP_DIR="${LDP_DIR:-$HERE/../fap-ldp}"
BUILD="$HERE/.build"
ENV_FILE="$HERE/.env"

log() { echo "[deploy] $*"; }
die() { echo "[deploy] ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null || die "docker required"
docker compose version >/dev/null 2>&1 || die "docker compose required (plugin, e.g. ~/.docker/cli-plugins/docker-compose)"
[ -d "$CORE_DIR" ] || die "FAP core missing: $CORE_DIR"
[ -d "$LDP_DIR" ] || die "FAP-LDP extension missing: $LDP_DIR"

# --- 0. .env + auto-generated secrets ------------------------------------------
if [ ! -f "$ENV_FILE" ]; then cp "$HERE/.env.example" "$ENV_FILE"; log ".env created from .env.example"; fi
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
# password of the 3 demo users (alice/bob/admin): readable in dev, random in staging/prod
if [ "${ENV:-dev}" = "dev" ]; then
  if grep -q "^DEMO_PASSWORD=" "$ENV_FILE"; then sed -i "s|^DEMO_PASSWORD=.*|DEMO_PASSWORD=dev|" "$ENV_FILE"; else echo "DEMO_PASSWORD=dev" >> "$ENV_FILE"; fi
else
  set_secret DEMO_PASSWORD
fi
set -a; . "$ENV_FILE"; set +a

# --- 0b. ENV + domain → SCHEME / BASE_IRI + front origins (CORS) ------------------
# A single domain: API_DOMAIN = the BACK (root LDP, /auth, /dsp, /editor, /app/query)
# → resources' BASE_IRI = $SCHEME://$API_DOMAIN/.
# The front (../app-supervision) is AUTONOMOUS: served by vite from its own directory,
# it calls the back in absolute cross-origin — its origins are in FRONT_ORIGINS
# (Caddy CORS + Keycloak webOrigins/redirectUris).
# SCHEME: dev → http if API_DOMAIN=localhost (default), self-signed https otherwise (the
#          OIDC login requires a secure context outside "localhost") ; staging/prod → https.
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
  && log "WARN: dev with API_DOMAIN=$API_DOMAIN → self-signed HTTPS (OIDC requires https outside localhost)"
DOMAIN="$API_DOMAIN"   # alias (emails, KC_HOSTNAME) — the back lives on API_DOMAIN
BASE_IRI="$SCHEME://$API_DOMAIN/"
BASE_IRI_NO_SLASH="$SCHEME://$API_DOMAIN"
# FRONT domain: in dev/staging, caddy renders a $FRONT_DOMAIN site that proxies the vite
# server of the client running on the host (no client file mounted in the back).
# In prod, the front is deployed separately (its own server) — no front site rendered.
FRONT_DOMAIN="${FRONT_DOMAIN:-app.$API_DOMAIN}"
[ "$ENV" = "dev" ] && [ "$API_DOMAIN" = "localhost" ] && FRONT_DOMAIN="${FRONT_DOMAIN:-app.localhost}"
FRONT_DEV_PORT="${FRONT_DEV_PORT:-5173}"
# sync into .env for docker compose (KC_HOSTNAME, FAP_LDP_BASE_IRI) and the scripts
for kv in "ENV=$ENV" "SCHEME=$SCHEME" "BASE_IRI=$BASE_IRI" "DOMAIN=$DOMAIN" "API_DOMAIN=$API_DOMAIN" "FRONT_DOMAIN=$FRONT_DOMAIN" "FRONT_DEV_PORT=$FRONT_DEV_PORT" "FRONT_ORIGINS=$FRONT_ORIGINS"; do
  k="${kv%%=*}"; v="${kv#*=}"
  line="$k=$v"
  [ "$k" = "FRONT_ORIGINS" ] && line="FRONT_ORIGINS=\"$v\""   # origins list: quoted for sourcing .env
  if grep -q "^$k=" "$ENV_FILE"; then sed -i "s|^$k=.*|$line|" "$ENV_FILE"; else echo "$line" >> "$ENV_FILE"; fi
done
export ENV SCHEME BASE_IRI BASE_IRI_NO_SLASH DOMAIN API_DOMAIN FRONT_DOMAIN FRONT_DEV_PORT FRONT_ORIGINS FAP_ORG="${FAP_ORG:-fap-pod}"
set -a; . "$ENV_FILE"; set +a   # reload (DEMO_PASSWORD may have just been written)
# JSON arrays rendered for the Keycloak realm (envsubst): webOrigins + redirectUris of the front
export FRONT_WEB_ORIGINS FRONT_REDIRECT_URIS
FRONT_WEB_ORIGINS="$(python3 -c 'import json,os;print(json.dumps(os.environ["FRONT_ORIGINS"].split()))')"
FRONT_REDIRECT_URIS="$(python3 -c 'import json,os; o=os.environ["FRONT_ORIGINS"].split(); b=os.environ["BASE_IRI"]; print(json.dumps([b+"app/*", b.rstrip("/")+"/*"]+[x+"/*" for x in o]))')"
log "ENV=$ENV → back: $BASE_IRI (API_DOMAIN=$API_DOMAIN, SCHEME=$SCHEME) · autonomous front, CORS origins: $FRONT_ORIGINS"

dc() { docker compose --project-name energy-supervision --env-file "$ENV_FILE" -f "$HERE/compose/docker-compose.yml" "$@"; }

# --- 1. .build/flows — core + fap-ldp + app-supervision flows --------------------
CORE_DIR="$CORE_DIR" LDP_DIR="$LDP_DIR" bash "$HERE/scripts/assemble-flows.sh" "$BUILD/flows.json"
cp "$HERE/scripts/orce-settings.js" "$BUILD/orce-settings.js"

# --- 2. .build/initdb — ordered migrations: core → fap-ldp → custom --------------
# Do NOT rm -rf the directory itself: it is mounted in the postgres container
# (bind mount on the inode) — only empty its contents.
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
  -v dsp_agreement_id="${DSP_AGREEMENT_ID:-agreement:internal:framework-contract}"
  -d "${POSTGRES_DB:-fap}")
DIR="$(dirname "$0")"
for f in "$DIR"/sql/*.sql; do
  echo "[init] $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
EOF
chmod +x "$BUILD/initdb/init.sh"
chmod -R a+rX "$BUILD/initdb"   # fap-ldp sources may be 600 — the container runs as 'postgres'
log "initdb: $(ls "$BUILD/initdb/sql" | wc -l) migrations (core → fap-ldp → custom)"

# --- 3. .build/Caddyfile — rendered according to ENV + domain -------------------------
# ONE site only: the back on $API_DOMAIN. The front is autonomous (vite, cross-origin):
# it is NOT served here. CORS for FRONT_ORIGINS. The POST /app/query proxy no longer has a
# dedicated route: it falls through to the root → ORCE (the fap-ldp node excludes /app/ from
# the LDP middleware, patch C1.9), and its preflight is handled by @preflight (path *).
# SCHEME=http (dev, API_DOMAIN=localhost): pure HTTP :80, no certificate.
# SCHEME=https: dev/staging → tls internal (self-signed) ; prod → automatic Let's Encrypt.
mkdir -p "$BUILD"
BACK_ROUTES='  handle /auth/* {
    # NO strip_prefix: Keycloak serves under /auth (--http-relative-path /auth),
    # it must see the /auth path for DPoP validation (htu) and redirects.
    # Explicit X-Forwarded-*: Keycloak (KC_PROXY_HEADERS=xforwarded) rebuilds
    # the request scheme/host/port from these headers.
    reverse_proxy keycloak:8080 {
      header_up X-Forwarded-Host {http.request.host}
      header_up X-Forwarded-Proto {http.request.scheme}
      header_up X-Forwarded-Port {http.request.port}
    }
  }
  handle /dsp/* {
    reverse_proxy orce:1880 {
      # orce returns "Access-Control-Allow-Origin: *" → duplicate forbidden with
      # the one set by caddy (@corsOrigin): we strip it upstream.
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
# CEL expression "Origin ∈ FRONT_ORIGINS" (the multi-value header matcher is not
# accepted in a named matcher block → explicit CEL, generated from FRONT_ORIGINS)
CORS_CEL="$(python3 -c 'import os; o=os.environ["FRONT_ORIGINS"].split(); print("`" + " || ".join("{http.request.header.Origin} == '"'"'%s'"'"'" % x for x in o) + "`")')"
CORS_ROUTES="  # CORS: the autonomous front (FRONT_ORIGINS, e.g. vite http://localhost:5173) calls
  # the back cross-origin. /auth/* excluded: Keycloak ALREADY adds its CORS headers
  # (webOrigins) — a duplicate Access-Control-Allow-Origin would fail the request.
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
# FRONT site: in dev/staging, proxy to the client's vite server on the host
# (the client stays autonomous: none of its files is mounted in the back).
# In prod, the front is deployed separately → no front site rendered here.
FRONT_SITE=""
if [ "$ENV" != "prod" ]; then
  if [ "$SCHEME" = "http" ]; then
    FRONT_SITE="http://$FRONT_DOMAIN {
  # front (autonomous client): proxy to the host's vite server — HMR/websocket OK
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
  { echo "# Caddyfile generated by deploy-local.sh — ENV=$ENV, pure HTTP :80 (back: $API_DOMAIN, no certificate)."
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
  { echo "# Caddyfile generated by deploy-local.sh — ENV=$ENV SCHEME=https back=$API_DOMAIN"
    [ "$ENV" = "prod" ] && echo "# prod: automatic Let's Encrypt (real public domain, A record → IP). Front deployed separately." \
                       || echo "# $ENV: internal self-signed HTTPS (tls internal) — local CA: .build/caddy-root.crt (to import into the browser)."
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
log "Caddyfile rendered: $BUILD/Caddyfile (ENV=$ENV SCHEME=$SCHEME back=$API_DOMAIN front=${FRONT_DOMAIN:-separate})"

# --- 4. .build/keycloak — rendered realm (BASE_IRI, front origins, FAP_ORG, password) --
mkdir -p "$BUILD/keycloak"
envsubst '${DOMAIN} ${BASE_IRI} ${BASE_IRI_NO_SLASH} ${FRONT_WEB_ORIGINS} ${FRONT_REDIRECT_URIS} ${FAP_ORG} ${DEMO_PASSWORD}' \
  < "$HERE/keycloak/realm.json" > "$BUILD/keycloak/realm.json"
log "realm rendered: $BUILD/keycloak/realm.json (BASE_IRI=$BASE_IRI)"
log "Keycloak demo users: alice / bob / admin — password: ${DEMO_PASSWORD:-dev} (dev)"

# --- 5. up ----------------------------------------------------------------------
cd "$HERE"
dc up -d
# mounted files (Caddyfile, realm) do not trigger a recreate: restart to reload
dc restart caddy >/dev/null && log "caddy reloaded (rendered Caddyfile)"
dc up -d --force-recreate keycloak >/dev/null 2>&1 || true   # realm imported at boot: recreate to pick up the rendered version (internal H2 db)
until dc exec -T postgres pg_isready -U admin -d fap >/dev/null 2>&1; do sleep 1; done
log "postgres healthy"

# pg_cron after the 1st boot (05_pg_cron.sql outside the initdb scan)
dc exec -T postgres psql -U admin -d fap -v ON_ERROR_STOP=1 \
  -f /docker-entrypoint-initdb.d/post/05_pg_cron.sql >/dev/null && log "pg_cron installed (materializers 10 min)"

# --- 6. wait for the fap-ldp node boot (applies config/model.json) ---------------
log "waiting for fap-ldp boot (model applied)…"
applied=0
for i in $(seq 1 60); do
  if dc logs orce 2>/dev/null | grep -q "model applied"; then applied=1; break; fi
  sleep 2
done
[ "$applied" = 1 ] || log "WARN: 'model applied' not seen in orce logs (check: docker compose logs orce)"
# safeguard: the loaded flows must be the assembled flows (core + fap-ldp + custom)
# → hash comparison (the node count is not enough after a func edit)
n="$(dc exec -T orce md5sum /data/flows.json 2>/dev/null | cut -d' ' -f1)"
attendu="$(md5sum "$BUILD/flows.json" | cut -d' ' -f1)"
if [ "$n" != "$attendu" ]; then
  log "flows not up to date in orce (md5 $n != $attendu) — copying + restart"
  dc exec -T orce cp /flows-app/flows.json /data/flows.json
  dc restart orce >/dev/null
  for i in $(seq 1 30); do
    dc logs orce 2>/dev/null | grep -q "model applied" && break
    sleep 2
  done
fi

# --- 7. replay custom migrations post-boot (app.* exists now) --------------------
# 101_seed_demo.sql and 102_acl_init.sql take the base IRI as a psql variable (-v base_iri=...)
for f in "$BUILD"/initdb/sql/*custom*.sql; do
  [ -e "$f" ] || continue
  dc exec -T postgres psql -U admin -d fap -v ON_ERROR_STOP=1 -v base_iri="$BASE_IRI" \
    -f "/docker-entrypoint-initdb.d/sql/$(basename "$f")" >/dev/null \
    && log "post-boot replay: $(basename "$f")"
done
# the fap-ldp PEP caches columns per table (node.columns) on first access: after a
# custom migration (e.g. CR-2 area_m2), restart orce to clear this cache
dc restart orce >/dev/null && log "orce restarted (column cache cleared after custom migrations)"
for i in $(seq 1 30); do
  dc logs orce 2>/dev/null | grep -q "model applied" && break
  sleep 2
done

# --- 8. checks ----------------------------------------------------------------------
[ "$SCHEME" = "https" ] && CURL="curl -sk" || CURL="curl -s"   # -k: internal self-signed cert
BASE="$SCHEME://$API_DOMAIN"
log "checks (back=$BASE):"
$CURL -s -o /dev/null -w "  GET  $BASE/                  → %{http_code} (LDP root)\n" "$BASE/"
$CURL -s -o /dev/null -w "  GET  $BASE/tickets/          → %{http_code} (401/403 expected without a session)\n" "$BASE/tickets/"
$CURL -s -X POST "$BASE/dsp/catalogue/request" | head -c 120; echo "  ← catalogue DSP"
$CURL -s -X POST "$BASE/app/query" -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}' \
  -o /dev/null -w "  POST $BASE/app/query          → %{http_code} (401 expected without a session, CA-S10)\n"
$CURL -s -o /dev/null -w "  OPTIONS $BASE/buildings/ (CORS preflight, Origin front) → %{http_code}\n" \
  -X OPTIONS "$BASE/buildings/" -H "Origin: ${FRONT_ORIGINS%% *}" -H "Access-Control-Request-Method: GET"
$CURL -s "$BASE/auth/realms/fap-light/.well-known/openid-configuration" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("  issuer:", d["issuer"])' 2>/dev/null || true
# in self-signed HTTPS: extract the local CA for import into the browser (Firefox/Chrome)
if [ "$SCHEME" = "https" ] && [ "$ENV" != "prod" ]; then
  dc exec -T caddy cat /data/caddy/pki/authorities/local/root.crt > "$BUILD/caddy-root.crt" 2>/dev/null \
    && log "local Caddy CA exported: $BUILD/caddy-root.crt (to import in Firefox: Settings → Certificates)"
fi
log "OK — back: $BASE/ (LDP) · $BASE/auth/realms/fap-light (IdP) · $BASE/dsp/ · $BASE/editor/ · POST $BASE/app/query (signed proxy)"
log "     AUTONOMOUS front: cd ../app-supervision && ./scripts/configure.sh $BASE && npm run dev → http://app.localhost/ (caddy :80 → vite)"
