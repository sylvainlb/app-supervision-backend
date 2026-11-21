# TCK — app-supervision-backend

Ce dossier ne contient pas de tests propres : il mappe les **critères d'acceptation de la spec
fonctionnelle** (`spec/supervision-energetique-spec-fonctionnelle.md` §9) vers les TCK existants du
cœur FAP-light et de l'extension FAP-LDP, plus les vérifications spécifiques au déploiement.

## Commandes

```bash
# TCK cœur FAP-light (CA-S1..CA-S10 : ingestion, DLQ, catalogue, data plane HMAC, rate limit,
# watermarks, rôles PG, Superset, realm claims, proxy /app/query CA-S10)
bash ../fap-light-serveur/tck/run-tck.sh

# TCK FAP-LDP (sous-ensemble W3C LDP + PDP/ACL : CA-L1..CA-L15)
bash ../fap-ldp/core/tck/e2e-smoke.sh        # smoke
bash ../fap-ldp/core/tck/ldp-w3c-subset.sh    # conformité W3C LDP (CA-L8)

# Healthcheck du déploiement (compose fap-ldp)
make -C ../fap-ldp/compose test DEPLOY_DIR=$PWD ENV_FILE=$PWD/.env
```

## Mapping CA spec fonctionnelle → TCK

| CA (spec fonc. §9) | Vérifié par | Commentaire |
|---|---|---|
| CA-1 : anomalie visible sur le dashboard < 20 min | CA-S1 (bronze→silver→gold ≤ 10 min) + `gold.city_dashboard_summary` publié LDP (asset_mapping, mapping front §13.3) | fraîcheur affichée RG-4 |
| CA-2 : ticket créé depuis une anomalie, visible immédiatement (read-after-write) | CA-L1 (`POST /tickets` → GET immédiat) | `anomaly_ref` pré-rempli côté front |
| CA-3 : cycle OPEN → IN_PROGRESS → RESOLVED + historique | CA-L1 (versioning) + **CA-L15** (409 `invalid_transition`, matrice `config/model.json` → `business_rules`, RG-2) | transitions déclarées côté déploiement |
| CA-4 : `intervention_anomaly_daily` dans le catalogue DSP, requêtable avec contrat, 401/403 sans | CA-S3/S4 (catalogue + HMAC) sur la matview `sql/100_gold_intervention_anomaly_daily.sql` (published=true) | RG-5 : agrégée uniquement |
| CA-5 : blox liste générique sur `/tickets` et une ressource gold | CA-L2 (asset gold = conteneur LDP) + CA-L8 (W3C subset) | mapping assets LDP vs DSP-only : spec front §13.3 |

## Vérifications spécifiques au déploiement (à rejouer après chaque `deploy`)

Stack locale : `docker compose --project-name energy-supervision --env-file .env -f compose/docker-compose.yml`.

```bash
DC="docker compose --project-name energy-supervision --env-file .env -f compose/docker-compose.yml"
API=localhost   # back (LDP, /auth, /dsp, /editor, /app/query) — dev = HTTP pur ; front autonome sur :5173

# 1. Modèle appliqué au boot (logs ORCE) + flows assemblés chargés (48 nœuds)
$DC logs orce | grep "fap-ldp: model applied"          # users, buildings, tickets, comments

# 2. Rôles PG (C1.4/CA-S7) + jobs pg_cron (materializers 10 min)
$DC exec -T postgres psql -U admin -d fap -c "SELECT rolname FROM pg_roles WHERE rolname IN ('gate','app','reader','materializer')"
$DC exec -T postgres psql -U admin -d fap -c "SELECT jobname FROM cron.job"

# 3. Token de test (password grant, scope=openid requis pour l'userinfo ; mdp de démo = DEMO_PASSWORD=dev)
TOKEN=$(curl -s http://$API/auth/realms/fap-light/protocol/openid-connect/token \
  -d grant_type=password -d client_id=fap-light-ui -d username=alice -d password=dev -d scope=openid \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')

# 4. Proxy /app/query (CA-S10) : sans session → 401 ; avec session → 200 + lignes gold
#    (le front autonome l'appelle en cross-origin depuis :5173 — CORS/preflight gérés par caddy)
curl -s -X POST http://$API/app/query -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}'        # → 401
curl -s -X POST http://$API/app/query -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}'        # → 200

# 5. LDP applicatif (CA-L1/L2) : conteneurs app.* et gold publiés
for p in /tickets/ /buildings/ /gold/anomaly_candidates/ /gold/city_dashboard_summary/ /gold/energy_cost_daily/ /gold/intervention_anomaly_daily/; do
  echo "$p → $(curl -s -o /dev/null -H "Authorization: Bearer $TOKEN" http://$API$p -w '%{http_code}')"
done

# 6. CRUD + workflow (CA-L1, CA-L15) : création → read-after-write → 409 transition invalide → transition valide
curl -s -X POST http://$API/tickets/ -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"title":"test","building_id":1,"priority":"HIGH","status":"OPEN"}'                                          # → 201 + Location
curl -s -X PATCH http://$API/tickets/1 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"app_tickets:status":"CLOSED"}'                                                                             # → 409 invalid_transition (depuis OPEN)
curl -s -X PATCH http://$API/tickets/1 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"app_tickets:status":"IN_PROGRESS"}'                                                                         # → 200

# 7. Catalogue DSP + matview publiée (CA-4)
curl -s -X POST http://$API/dsp/catalogue/request | grep -o 'dataset:facis:[a-z-]*'
$DC exec -T postgres psql -U admin -d fap -c "SELECT asset_uri, published FROM dsp.asset_mapping WHERE asset_uri LIKE '/gold/%'"

# 8. Outbox RG-3 : chaque écriture app.* part en bronze.app_event via la gate (cycle 30 s)
$DC exec -T postgres psql -U admin -d fap -c "SELECT count(*) FROM bronze.app_event; SELECT count(*) FROM app.outbox WHERE processed_at IS NULL"
```
