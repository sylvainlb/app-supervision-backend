# TCK — app-supervision-backend

This directory contains no tests of its own: it maps the **acceptance criteria of the
functional spec** (`spec/supervision-energetique-spec-fonctionnelle.md` §9) to the existing TCKs of
the FAP-light core and the FAP-LDP extension, plus the deployment-specific checks.

## Commands

```bash
# FAP-light core TCK (CA-S1..CA-S10: ingestion, DLQ, catalog, data plane HMAC, rate limit,
# watermarks, PG roles, Superset, realm claims, proxy /app/query CA-S10)
bash ../fap-light-serveur/tck/run-tck.sh

# FAP-LDP TCK (W3C LDP subset + PDP/ACL: CA-L1..CA-L15)
bash ../fap-ldp/core/tck/e2e-smoke.sh        # smoke
bash ../fap-ldp/core/tck/ldp-w3c-subset.sh    # W3C LDP conformance (CA-L8)

# Deployment healthcheck (fap-ldp compose)
make -C ../fap-ldp/compose test DEPLOY_DIR=$PWD ENV_FILE=$PWD/.env
```

## Mapping functional spec CA → TCK

| CA (func. spec §9) | Verified by | Comment |
|---|---|---|
| CA-1: anomaly visible on the dashboard < 20 min | CA-S1 (bronze→silver→gold ≤ 10 min) + `gold.city_dashboard_summary` published LDP (asset_mapping, front mapping §13.3) | displayed freshness RG-4 |
| CA-2: ticket created from an anomaly, visible immediately (read-after-write) | CA-L1 (`POST /tickets` → immediate GET) | `anomaly_ref` pre-filled client-side |
| CA-3: cycle OPEN → IN_PROGRESS → RESOLVED + history | CA-L1 (versioning) + **CA-L15** (409 `invalid_transition`, matrix `config/model.json` → `business_rules`, RG-2) | transitions declared on the deployment side |
| CA-4: `intervention_anomaly_daily` in the DSP catalog, queryable with a contract, 401/403 without | CA-S3/S4 (catalog + HMAC) on the matview `sql/100_gold_intervention_anomaly_daily.sql` (published=true) | RG-5: aggregated only |
| CA-5: generic blox list on `/tickets` and a gold resource | CA-L2 (gold asset = LDP container) + CA-L8 (W3C subset) | LDP vs DSP-only asset mapping: front spec §13.3 |

## Deployment-specific checks (to replay after each `deploy`)

Local stack: `docker compose --project-name energy-supervision --env-file .env -f compose/docker-compose.yml`.

```bash
DC="docker compose --project-name energy-supervision --env-file .env -f compose/docker-compose.yml"
API=localhost   # back (LDP, /auth, /dsp, /editor, /app/query) — dev = pure HTTP ; autonomous front on :5173

# 1. Model applied at boot (ORCE logs) + assembled flows loaded (48 nodes)
$DC logs orce | grep "fap-ldp: model applied"          # users, buildings, tickets, comments

# 2. PG roles (C1.4/CA-S7) + pg_cron jobs (materializers 10 min)
$DC exec -T postgres psql -U admin -d fap -c "SELECT rolname FROM pg_roles WHERE rolname IN ('gate','app','reader','materializer')"
$DC exec -T postgres psql -U admin -d fap -c "SELECT jobname FROM cron.job"

# 3. Test token (password grant, scope=openid required for userinfo; demo password = DEMO_PASSWORD=dev)
TOKEN=$(curl -s http://$API/auth/realms/fap-light/protocol/openid-connect/token \
  -d grant_type=password -d client_id=fap-light-ui -d username=alice -d password=dev -d scope=openid \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')

# 4. /app/query proxy (CA-S10): without session → 401 ; with session → 200 + gold rows
#    (the autonomous front calls it cross-origin from :5173 — CORS/preflight handled by caddy)
curl -s -X POST http://$API/app/query -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}'        # → 401
curl -s -X POST http://$API/app/query -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}'        # → 200

# 5. Application LDP (CA-L1/L2): app.* and published gold containers
for p in /tickets/ /buildings/ /gold/anomaly_candidates/ /gold/city_dashboard_summary/ /gold/energy_cost_daily/ /gold/intervention_anomaly_daily/; do
  echo "$p → $(curl -s -o /dev/null -H "Authorization: Bearer $TOKEN" http://$API$p -w '%{http_code}')"
done

# 6. CRUD + workflow (CA-L1, CA-L15): create → read-after-write → 409 invalid transition → valid transition
curl -s -X POST http://$API/tickets/ -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"title":"test","building_id":1,"priority":"HIGH","status":"OPEN"}'                                          # → 201 + Location
curl -s -X PATCH http://$API/tickets/1 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"app_tickets:status":"CLOSED"}'                                                                             # → 409 invalid_transition (from OPEN)
curl -s -X PATCH http://$API/tickets/1 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"app_tickets:status":"IN_PROGRESS"}'                                                                         # → 200

# 7. DSP catalog + published matview (CA-4)
curl -s -X POST http://$API/dsp/catalogue/request | grep -o 'dataset:facis:[a-z-]*'
$DC exec -T postgres psql -U admin -d fap -c "SELECT asset_uri, published FROM dsp.asset_mapping WHERE asset_uri LIKE '/gold/%'"

# 8. Outbox RG-3: every app.* write goes to bronze.app_event via the gate (30 s cycle)
$DC exec -T postgres psql -U admin -d fap -c "SELECT count(*) FROM bronze.app_event; SELECT count(*) FROM app.outbox WHERE processed_at IS NULL"
```
