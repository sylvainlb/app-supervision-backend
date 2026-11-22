# app-supervision-backend

Backend of the energy supervision application — implementation of
`spec/supervision-energetique-spec-fonctionnelle.md` on the **FAP-light** profile with
the **FAP-LDP** extension.

This directory is the **deployment directory** (`DEPLOY_DIR` in the sense of
`fap-ldp/compose/README.md`): it contains neither the FAP core nor the extension, it
*assembles* them:

```
UI blox (app-supervision/, AUTONOMOUS: served by vite from its own directory,
        calls the back in absolute cross-origin — CORS)
        │  LDP/JSON-LD (root /)  +  POST /app/query (signed proxy)  +  /dsp/*  +  /auth/* (Keycloak)
        ▼  (all on the back domain, e.g. http://localhost/ in dev)
┌────────────────────────────────────────────┐
│  ORCE (Node-RED) — 1 runtime               │
│  ├── FAP-light core flows (../fap-light-serveur)  : gate, ingestion, DSP catalog, /dsp/data
│  ├── package node-red-contrib-fap-ldp (../fap-ldp) : LDP container, PDP, PEP app.*
│  └── app-supervision.json fragment (here)   : POST /app/query (C1.9/D-8), outbox → bronze (RG-3)
└───────────┬────────────────────────────────┘
            │ SQL, separate PG roles (gate / app / reader / materializer / admin)
            ▼
┌────────────────────────────────────────────┐
│  PostgreSQL (1 VM, light profile)          │
│  ├── bronze.* / silver.* / gold.*  (FAP-light core, unchanged)
│  ├── app.*     (supervision business model, applied at boot from config/model.json)
│  ├── gold.intervention_anomaly_daily (published matview, sql/100 — F7/RG-5)
│  └── auth.acl / dsp.*               (FAP-LDP: ACL, contracts, audit, asset_mapping)
└────────────────────────────────────────────┘
  + caddy (TLS, LDP/DSP/app routes)  +  Keycloak 26.x (realm fap-light, claims webid/role/org, DPoP)
```

- **FAP-light** = `../fap-light-serveur` (core: PostgreSQL + ORCE + caddy + IdP, 1 VM, accepted SPOF).
- **FAP-LDP** = `../fap-ldp` (extension: `app.*` domain, LDP/JSON-LD endpoint, PDP/ACL/RLS — deployed
  in the same ORCE runtime, `fap-ldp/compose/`).
- **Front** = `../app-supervision` (Startin'blox, served by caddy at `/app/`).

## Layout of this directory

```
app-supervision-backend/
├── .env.example            ← copy to .env and edit (API_DOMAIN/APP_DOMAIN, secrets, paths)
├── compose/
│   └── docker-compose.yml  ← standalone energy-supervision stack (100% local images, no pull):
│                             postgres+pg_cron, orce (core + fap-ldp package + app-supervision fragment),
│                             keycloak, caddy, mosquitto, sftp
├── config/
│   └── model.json          ← app.* business model (users/buildings/tickets/comments), applied at boot
│                             by the fap-ldp node: tables, triggers, RLS, asset_mapping, ACL
├── sql/                    ← custom migrations (order: core → fap-ldp base → custom, replayed post-boot)
│   ├── 100_gold_intervention_anomaly_daily.sql  ← published gold matview (F7, RG-5, CA-4) + pg_cron refresh
│   ├── 101_seed_demo.sql                        ← demo fleet/buildings + users (webid = Keycloak claims)
│   ├── 102_acl_init.sql                         ← initial ACLs (full IRIs, -v base_iri=… required)
│   ├── 103_app_event_bronze.sql                 ← bronze.app_event + gate_type_map 'app.event' (RG-3)
│   └── 104_gold_ldp_published.sql               ← published LDP containers of gold aggregates (front spec §13.3)
├── flows/
│   └── app-supervision.json                   ← ORCE fragment (proxy /app/query C1.9/D-8, outbox RG-3)
├── keycloak/
│   └── realm.json          ← fap-light realm: static front client fap-light-ui (D-7/I), claims
│                             webid/role/org (H), DPoP, demo users — rendered by envsubst (${DOMAIN})
├── caddy/
│   └── Caddyfile           ← prod REFERENCE: two sites (api.<domain> back + CORS, app.<domain> front+proxy)
├── scripts/
│   ├── start.sh            ← starts the BACKEND (deploy-local.sh) + prints the URLs (--reset)
│   ├── stop.sh             ← stops the backend (docker compose down, volumes kept)
│   ├── deploy-local.sh     ← idempotent deployment: .env, .build/ (flows/initdb/Caddyfile/realm), compose up,
│   │                           pg_cron, fap-ldp boot, replays sql/ custom, curl checks
│   └── assemble-flows.sh   ← concatenates core flows + fap-ldp + app-supervision.json → .build/flows/
# The front ../app-supervision is AUTONOMOUS: no reference to it in this repo
# (it configures/launches from its own directory: scripts/configure.sh + npm run dev).
├── tck/
│   └── README.md           ← mapping CA-1..CA-5 (functional spec) → core TCK (CA-S*) / FAP-LDP (CA-L*)
└── .build/                 ← generated (gitignored): rendered flows/, initdb/, keycloak/, Caddyfile, caddy-root.crt
```

## Access URLs

**A single domain for the back** (`API_DOMAIN`, the resources' `BASE_IRI`). **The front is
autonomous**: no client reference in this repo — it runs from its own
`../app-supervision` directory (vite) and calls the back in absolute, cross-origin
(CORS handled by the back via `FRONT_ORIGINS`, `/auth` by Keycloak via `webOrigins`).

| Role | Dev (default, pure HTTP) | Staging/prod (HTTPS) |
|---|---|---|
| **Back LDP** | `http://localhost/` (e.g. `/buildings/` with Bearer) | `https://fap.example.com/` |
| **IdP** | `http://localhost/auth/realms/fap-light` | `https://fap.example.com/auth/realms/fap-light` |
| **DSP** | `POST http://localhost/dsp/catalogue/request` | same over https |
| **Signed proxy** | `POST http://localhost/app/query` (OIDC/DPoP session) | same over https |
| **Editor** | `http://localhost/editor/` | `https://fap.example.com/editor/` |
| **Front (autonomous)** | `http://app.localhost/` (port 80, caddy → vite ; `cd ../app-supervision && npm run dev`) | deployed separately, e.g. `https://app.fap.example.com` (put its origin in `FRONT_ORIGINS`) |

Keycloak login (dev): **alice / bob / admin**, password `dev`.

## Start / stop

```bash
cd app-supervision-backend
./scripts/start.sh          # starts the BACKEND (full docker stack) + prints the URLs
./scripts/start.sh --reset  # same, deleting the volumes (full re-seed, e.g. after
                            # changing BASE_IRI/domain)
./scripts/stop.sh           # stops the backend (docker compose down, volumes kept)

# The FRONT is autonomous, from its own directory:
cd ../app-supervision
./scripts/configure.sh http://localhost   # writes .env + orbit.json (POD_URL, OIDC_ISSUER…)
npm run dev                               # → http://app.localhost/ (caddy :80 → vite)
```

`start.sh` delegates to `deploy-local.sh` (idempotent: auto secrets, rendered `.build/` — flows,
initdb, Caddyfile, Keycloak realm — compose up, pg_cron, fap-ldp boot, replays `sql/` custom,
curl checks) and prints the back URLs + the command to launch the front.

## Scheme / certificate according to `ENV` (in `.env`)

| `ENV` | `API_DOMAIN` | Scheme | Certificate |
|---|---|---|---|
| `dev` (default) | `localhost` | **`http://localhost/` :80 — pure HTTP** | none — no browser error locally |
| special `dev` | custom domain (e.g. `api.localhost`) | `https://…` :443 | internal self-signed (`tls internal`) — OIDC login requires a secure context outside `localhost` |
| `staging` | non-public domain | `https://…` :443 | internal self-signed (`tls internal`) — import `.build/caddy-root.crt` into the browser once |
| `prod` | real domain (A record → IP), e.g. `fap.example.com` | `https://…` :443 | **Let's Encrypt** automatic |

`SCHEME`/`BASE_IRI` are derived from `ENV` + `API_DOMAIN` by `deploy-local.sh` (written to
`.env`, used for the rendered `.build/Caddyfile`, the Keycloak realm, `FAP_LDP_BASE_IRI`,
`KC_HOSTNAME` and the `base_iri` ACLs). Changing `ENV` or the domain then rerunning
`./scripts/start.sh --reset` re-renders and re-seeds everything cleanly.

The Caddyfile serves **only the back**: root → LDP/ORCE (including `POST /app/query`, signed proxy —
reached via the root route, no dedicated route), `/auth/*` → Keycloak, `/dsp/*` and `/editor*`
→ ORCE, plus CORS for `FRONT_ORIGINS` (`/auth/*` excluded: Keycloak already manages its own
CORS headers via `webOrigins`).

Prerequisites: docker + compose plugin (user-local accepted: `~/.docker/cli-plugins/docker-compose`),
python3, openssl, envsubst — and the two sibling repos (`../fap-light-serveur`,
`../fap-ldp`). All docker images used are local (no pull).

## Verify

```bash
docker compose --project-name energy-supervision --env-file .env -f compose/docker-compose.yml ps
curl -s http://localhost/                           # LDP root (dev = pure HTTP, no -k)
curl -s http://localhost/tickets/                   # app.* container (401 without a session)
curl -s -X POST http://localhost/dsp/catalogue/request   # DSP catalog (published gold assets)
# CORS (autonomous front on http://app.localhost/) :
curl -s -D - -o /dev/null -H "Origin: http://app.localhost" http://localhost/buildings/ | grep -i access-control
curl -s -o /dev/null -w "%{http_code}\n" -X OPTIONS http://localhost/app/query \
  -H "Origin: http://app.localhost" -H "Access-Control-Request-Method: POST"   # preflight → 204
# test token (password grant) :
TOKEN=$(curl -s http://localhost/auth/realms/fap-light/protocol/openid-connect/token \
  -d grant_type=password -d client_id=fap-light-ui -d username=alice -d password=dev -d scope=openid \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
curl -s -H "Authorization: Bearer $TOKEN" http://localhost/buildings/   # 200 JSON-LD
curl -s -X POST http://localhost/app/query -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}'  # 200
# conformance tests: see tck/README.md
```

## Server change requests implemented (spec `app-store-catalogue.md` §2)

| CR | Content | Where | Verified |
|---|---|---|---|
| **CR-0** | All gold matviews published as LDP containers (13 `/gold/*/` assets) | `sql/106_cr0_cr1_gold_ldp.sql` | `GET /gold/net_grid_hourly/` etc. → 200 |
| **CR-1** | Matviews `gold.price_hourly` + `gold.city_event_hourly` from `silver.energy_price`/`silver.city_event`, published LDP | `sql/106` + pg_cron refresh 10 min | 20 rows each, `/gold/price_hourly/` → 200 |
| **CR-2** | `area_m2 double precision` (nullable) on `app.buildings` (+ lat/lon §13.4 already there) | `config/model.json` + `sql/105_cr2_area_m2.sql` | `PATCH app_buildings:area_m2` → 200, served on read |
| **CR-3** | LDP sub-container `/tickets/<pk>/versions/` (`app.ticket_versions` filtered view, RG-5) | `sql/107_cr3_ticket_versions.sql` | `GET /tickets/1/versions/` → 200 + members |
| **CR-4** | Matview `gold.annual_site_consumption` (kWh/year + kWh/m² per building), published `/gold/annual_site_consumption/` | `sql/108_cr4_annual_site_consumption.sql` | rows present, container → 200 |
| **CR-5** | Endpoint `POST /app/llm` (function: OIDC session, rate limit 10/min/user, server-side asset allowlist, read **via internal LDP with the user token** so ACL/RLS apply, audit `dsp.audit`, LLM call if `LLM_ENDPOINT` else 503) | `flows/app-supervision.json` + env `LLM_ENDPOINT`/`LLM_API_KEY`/`LLM_ASSETS` | 401/400/403/429/503 tested, audit OK |

Note CR-5: no async in the HTTP flow function nodes (the ORCE runtime does not return the
main) → asset read via split → http request (internal PEP) → join. The PEP caches the
columns on first access: `deploy-local.sh` restarts ORCE after replaying the custom migrations.

## Patches applied to `../fap-ldp` (component, mounted read-only in ORCE)

Three change requests needed for the deployment, in `core/nodes/nodes/ldp-container.js`:

1. **Exclusion of `/app/` from the LDP middleware** (C1.9/D-8): the `POST /app/query` proxy must reach
   ORCE without being intercepted by the LDP container (the front, for its part, is autonomous and is no longer
   served by this back).
2. **Decision K (CA-L15)**: `validateTransition()` reads the `business_rules` of `config/model.json`
   and rejects any invalid status transition with `409 dspace:Error invalid_transition`.
3. **Dynamic `ORDER BY t.<pk>`** in the container listing: gold matviews have no `id`
   column; the pk is the last placeholder of the `resource_iri_pattern` in `dsp.asset_mapping`.

## Operational notes

- **Front (autonomous)**: no reference here. From `../app-supervision`:
  `./scripts/configure.sh http://localhost && npm run dev` → **`http://app.localhost/`** (port 80).
  The client has NO vite proxy: all calls go absolute to `POD_URL`
  (cross-origin, CORS handled by the back) — a vite proxy would break DPoP
  (`DPoP HTTP URL mismatch`). Keycloak login: **alice** (password `dev` in dev).
  In staging/prod: `./scripts/configure.sh https://fap.example.com` and put the
  front origin in `FRONT_ORIGINS` (CORS + Keycloak webOrigins).
- **Certificate**: in pure HTTP dev, none. In staging (self-signed HTTPS): import once
  `.build/caddy-root.crt` into the browser (Settings → Certificates → Authorities → Import).
- **Node-RED editor**: `http://localhost/editor/` in dev (httpAdminRoot `/editor`, outside
  the LDP middleware — copied at boot by `scripts/orce-entrypoint.sh` from `scripts/orce-settings.js`).
  The LDP nodes are in the **FAP-LDP** palette (`fap-ldp-container` PEP, `fap-ldp-pdp`,
  `fap-ldp-model` boot); our proxy/outbox in the **app-supervision** palette.
- **PATCH**: send `Content-Type: application/json` (the Node-RED body-parser does not read
  `application/merge-patch+json` in stream mode; merge-patch semantics still apply,
  the key must be prefixed as served, e.g. `{"app_tickets:status":"IN_PROGRESS"}`).
- OIDC token (password grant, tests): `scope=openid` required for userinfo
  (see "Verify" above; demo password = `DEMO_PASSWORD` in `.env`, `dev` in dev).
- The `sql/10x` migrations are automatically replayed after boot by `deploy-local.sh`
  (they need `app.*`, created at boot by the `fap-ldp` node).

## References

- `spec/supervision-energetique-spec-fonctionnelle.md` — scope F1–F7, model §4.1, RG-1..RG-6, CA-1..CA-5
- `spec/fap-light-spec-serveur.md` — FAP-light core (C1.1–C1.9, D-1..D-8, CA-S1..CA-S10)
- `spec/fap-ldp-spec.md` — FAP-LDP extension (E1–E3, decisions A–K, CA-L1..CA-L15)
- `spec/fap-domaine-app-et-profils.md` — retained light profile, security rules (PG roles)
- `spec/supervision-energetique-front-technique.md` — consumed client contract (§9 proxy /app/query, §13.3 asset mapping, §13.5 workflow)
