# app-supervision-backend

Backend de l'application de supervision énergétique — implémentation de
`spec/supervision-energetique-spec-fonctionnelle.md` sur le profil **FAP-light** avec
l'extension **FAP-LDP**.

Ce répertoire est le **dossier de déploiement** (`DEPLOY_DIR` au sens de
`fap-ldp/compose/README.md`) : il ne contient ni le cœur FAP ni l'extension, il les
*assemble* :

```
UI blox (app-supervision/, AUTONOME : servi par vite depuis son propre répertoire,
        appelle le back en absolu cross-origin — CORS)
        │  LDP/JSON-LD (racine /)  +  POST /app/query (proxy signé)  +  /dsp/*  +  /auth/* (Keycloak)
        ▼  (tout sur le domaine du back, ex. http://localhost/ en dev)
┌────────────────────────────────────────────┐
│  ORCE (Node-RED) — 1 runtime               │
│  ├── flows cœur FAP-light (../fap-light-serveur)  : gate, ingestion, catalogue DSP, /dsp/data
│  ├── package node-red-contrib-fap-ldp (../fap-ldp) : conteneur LDP, PDP, PEP app.*
│  └── fragment app-supervision.json (ici)   : POST /app/query (C1.9/D-8), outbox → bronze (RG-3)
└───────────┬────────────────────────────────┘
            │ SQL, rôles PG séparés (gate / app / reader / materializer / admin)
            ▼
┌────────────────────────────────────────────┐
│  PostgreSQL (1 VM, profil light)           │
│  ├── bronze.* / silver.* / gold.*  (cœur FAP-light, inchangé)
│  ├── app.*     (modèle métier supervision, appliqué au boot depuis config/model.json)
│  ├── gold.intervention_anomaly_daily (matview publiée, sql/100 — F7/RG-5)
│  └── auth.acl / dsp.*               (FAP-LDP : ACL, contrats, audit, asset_mapping)
└────────────────────────────────────────────┘
  + caddy (TLS, routes LDP/DSP/app)  +  Keycloak 26.x (realm fap-light, claims webid/role/org, DPoP)
```

- **FAP-light** = `../fap-light-serveur` (cœur : PostgreSQL + ORCE + caddy + IdP, 1 VM, SPOF assumé).
- **FAP-LDP** = `../fap-ldp` (extension : domaine `app.*`, endpoint LDP/JSON-LD, PDP/ACL/RLS — déployée
  dans le même runtime ORCE, `fap-ldp/compose/`).
- **Front** = `../app-supervision` (Startin'blox, servi par caddy à `/app/`).

## Arborescence de ce répertoire

```
app-supervision-backend/
├── .env.example            ← copier en .env et éditer (API_DOMAIN/APP_DOMAIN, secrets, chemins)
├── compose/
│   └── docker-compose.yml  ← stack autonome energy-supervision (images 100% locales, aucun pull) :
│                             postgres+pg_cron, orce (cœur + package fap-ldp + fragment app-supervision),
│                             keycloak, caddy, mosquitto, sftp
├── config/
│   └── model.json          ← modèle métier app.* (users/buildings/tickets/comments), appliqué au boot
│                             par le nœud fap-ldp : tables, triggers, RLS, asset_mapping, ACL
├── sql/                    ← migrations custom (ordre: cœur → socle fap-ldp → custom, rejouées post-boot)
│   ├── 100_gold_intervention_anomaly_daily.sql  ← matview gold publiée (F7, RG-5, CA-4) + refresh pg_cron
│   ├── 101_seed_demo.sql                        ← parc/bâtiments de démo + users (webid = claims Keycloak)
│   ├── 102_acl_init.sql                         ← ACL initiales (IRI complets, -v base_iri=… requis)
│   ├── 103_app_event_bronze.sql                 ← bronze.app_event + gate_type_map 'app.event' (RG-3)
│   └── 104_gold_ldp_published.sql               ← conteneurs LDP publiés des agrégats gold (spec front §13.3)
├── flows/
│   └── app-supervision.json                   ← fragment ORCE (proxy /app/query C1.9/D-8, outbox RG-3)
├── keycloak/
│   └── realm.json          ← realm fap-light : client front fap-light-ui statique (D-7/I), claims
│                             webid/role/org (H), DPoP, users de démo — rendu par envsubst (${DOMAIN})
├── caddy/
│   └── Caddyfile           ← RÉFÉRENCE prod : deux sites (api.<domaine> back + CORS, app.<domaine> front+proxy)
├── scripts/
│   ├── start.sh            ← démarre le BACKEND (deploy-local.sh) + affiche les URLs (--reset)
│   ├── stop.sh             ← arrête le backend (docker compose down, volumes conservés)
│   ├── deploy-local.sh     ← déploiement idempotent : .env, .build/ (flows/initdb/Caddyfile/realm), compose up,
│   │                           pg_cron, boot fap-ldp, rejoue sql/ custom, vérifs curl
│   └── assemble-flows.sh   ← concatène flows cœur + fap-ldp + app-supervision.json → .build/flows/
# Le front ../app-supervision est AUTONOME : aucune référence à lui dans ce dépôt
# (il se configure/lance depuis son propre répertoire : scripts/configure.sh + npm run dev).
├── tck/
│   └── README.md           ← mapping CA-1..CA-5 (spec fonctionnelle) → TCK cœur (CA-S*) / FAP-LDP (CA-L*)
└── .build/                 ← généré (gitignoré) : flows/, initdb/, keycloak/, Caddyfile, caddy-root.crt rendus
```

## URLs d'accès

**Un seul domaine pour le back** (`API_DOMAIN`, `BASE_IRI` des ressources). **Le front est
autonome** : aucune référence au client dans ce dépôt — il tourne depuis son propre
répertoire `../app-supervision` (vite) et appelle le back en absolu, cross-origin
(CORS géré par le back via `FRONT_ORIGINS`, `/auth` par Keycloak via `webOrigins`).

| Rôle | Dev (défaut, HTTP pur) | Staging/prod (HTTPS) |
|---|---|---|
| **Back LDP** | `http://localhost/` (ex. `/buildings/` avec Bearer) | `https://fap.example.com/` |
| **IdP** | `http://localhost/auth/realms/fap-light` | `https://fap.example.com/auth/realms/fap-light` |
| **DSP** | `POST http://localhost/dsp/catalogue/request` | idem en https |
| **Proxy signé** | `POST http://localhost/app/query` (session OIDC/DPoP) | idem en https |
| **Éditeur** | `http://localhost/editor/` | `https://fap.example.com/editor/` |
| **Front (autonome)** | `http://app.localhost/` (port 80, caddy → vite ; `cd ../app-supervision && npm run dev`) | déployé à part, ex. `https://app.fap.example.com` (mettre son origine dans `FRONT_ORIGINS`) |

Login Keycloak (dev) : **alice / bob / admin**, mot de passe `dev`.

## Démarrer / arrêter

```bash
cd app-supervision-backend
./scripts/start.sh          # démarre le BACKEND (stack docker complète) + affiche les URLs
./scripts/start.sh --reset  # idem en supprimant les volumes (re-seed complet, ex. après
                            # changement de BASE_IRI/domaine)
./scripts/stop.sh           # arrête le backend (docker compose down, volumes conservés)

# Le FRONT est autonome, depuis son propre répertoire :
cd ../app-supervision
./scripts/configure.sh http://localhost   # écrit .env + orbit.json (POD_URL, OIDC_ISSUER…)
npm run dev                               # → http://app.localhost/ (caddy :80 → vite)
```

`start.sh` délègue à `deploy-local.sh` (idempotent : secrets auto, `.build/` rendu — flows,
initdb, Caddyfile, realm Keycloak — compose up, pg_cron, boot fap-ldp, rejoue `sql/` custom,
vérifs curl) et affiche les URLs du back + la commande pour lancer le front.

## Schéma / certificat selon `ENV` (dans `.env`)

| `ENV` | `API_DOMAIN` | Schéma | Certificat |
|---|---|---|---|
| `dev` (défaut) | `localhost` | **`http://localhost/` :80 — HTTP pur** | aucun — aucune erreur navigateur en local |
| `dev` spécial | domaine custom (ex. `api.localhost`) | `https://…` :443 | auto-signé interne (`tls internal`) — le login OIDC exige un contexte sécurisé hors `localhost` |
| `staging` | domaine non public | `https://…` :443 | auto-signé interne (`tls internal`) — importer `.build/caddy-root.crt` dans le navigateur une fois |
| `prod` | vrai domaine (A record → IP), ex. `fap.example.com` | `https://…` :443 | **Let's Encrypt** automatique |

`SCHEME`/`BASE_IRI` sont dérivés de `ENV` + `API_DOMAIN` par `deploy-local.sh` (écrits dans
`.env`, utilisés pour le Caddyfile rendu `.build/Caddyfile`, le realm Keycloak, `FAP_LDP_BASE_IRI`,
`KC_HOSTNAME` et les ACL `base_iri`). Changer `ENV` ou le domaine puis relancer
`./scripts/start.sh --reset` re-rend et re-seed tout proprement.

Le Caddyfile ne sert **que le back** : racine → LDP/ORCE (dont `POST /app/query`, proxy signé —
atteint via la route racine, aucune route dédiée), `/auth/*` → Keycloak, `/dsp/*` et `/editor*`
→ ORCE, plus le CORS pour `FRONT_ORIGINS` (`/auth/*` exclu : Keycloak gère déjà ses headers
CORS via `webOrigins`).

Prérequis : docker + plugin compose (user-local accepté : `~/.docker/cli-plugins/docker-compose`),
python3, openssl, envsubst — et les deux dépôts à côté de celui-ci (`../fap-light-serveur`,
`../fap-ldp`). Toutes les images docker utilisées sont locales (aucun pull).

## Vérifier

```bash
docker compose --project-name energy-supervision --env-file .env -f compose/docker-compose.yml ps
curl -s http://localhost/                           # racine LDP (dev = HTTP pur, pas de -k)
curl -s http://localhost/tickets/                   # conteneur app.* (401 sans session)
curl -s -X POST http://localhost/dsp/catalogue/request   # catalogue DSP (assets gold publiés)
# CORS (front autonome sur http://app.localhost/) :
curl -s -D - -o /dev/null -H "Origin: http://app.localhost" http://localhost/buildings/ | grep -i access-control
curl -s -o /dev/null -w "%{http_code}\n" -X OPTIONS http://localhost/app/query \
  -H "Origin: http://app.localhost" -H "Access-Control-Request-Method: POST"   # preflight → 204
# token de test (password grant) :
TOKEN=$(curl -s http://localhost/auth/realms/fap-light/protocol/openid-connect/token \
  -d grant_type=password -d client_id=fap-light-ui -d username=alice -d password=dev -d scope=openid \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
curl -s -H "Authorization: Bearer $TOKEN" http://localhost/buildings/   # 200 JSON-LD
curl -s -X POST http://localhost/app/query -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"assetId":"dataset:facis:net-grid-hourly","from":"2026-11-19T00:00:00Z","to":"2026-11-20T00:00:00Z"}'  # 200
# tests de conformité : voir tck/README.md
```

## Change requests serveur implémentés (spec `app-store-catalogue.md` §2)

| CR | Contenu | Où | Vérifié |
|---|---|---|---|
| **CR-0** | Toutes les matviews gold publiées en conteneurs LDP (13 assets `/gold/*/`) | `sql/106_cr0_cr1_gold_ldp.sql` | `GET /gold/net_grid_hourly/` etc. → 200 |
| **CR-1** | Matviews `gold.price_hourly` + `gold.city_event_hourly` depuis `silver.energy_price`/`silver.city_event`, publiées LDP | `sql/106` + refresh pg_cron 10 min | 20 lignes chacune, `/gold/price_hourly/` → 200 |
| **CR-2** | `area_m2 double precision` (nullable) sur `app.buildings` (+ lat/lon §13.4 déjà là) | `config/model.json` + `sql/105_cr2_area_m2.sql` | `PATCH app_buildings:area_m2` → 200, servi en lecture |
| **CR-3** | Sous-conteneur LDP `/tickets/<pk>/versions/` (vue `app.ticket_versions` filtrée, RG-5) | `sql/107_cr3_ticket_versions.sql` | `GET /tickets/1/versions/` → 200 + membres |
| **CR-4** | Matview `gold.annual_site_consumption` (kWh/an + kWh/m² par bâtiment), publiée `/gold/annual_site_consumption/` | `sql/108_cr4_annual_site_consumption.sql` | lignes présentes, conteneur → 200 |
| **CR-5** | Endpoint `POST /app/llm` (fonction : session OIDC, rate limit 10/min/user, whitelist assets serveur, lecture **en LDP interne avec le token user** donc ACL/RLS, audit `dsp.audit`, appel LLM si `LLM_ENDPOINT` sinon 503) | `flows/app-supervision.json` + env `LLM_ENDPOINT`/`LLM_API_KEY`/`LLM_ASSETS` | 401/400/403/429/503 testés, audit OK |

Note CR-5 : pas d'async dans les function nodes des flows HTTP (le runtime ORCE ne rend pas
la main) → lecture des assets par split → http request (PEP interne) → join. Le PEP cache les
colonnes au 1er accès : `deploy-local.sh` redémarre ORCE après le rejeu des migrations custom.

## Patchs appliqués à `../fap-ldp` (composant, monté en lecture seule dans ORCE)

Trois change requests nécessaires au déploiement, dans `core/nodes/nodes/ldp-container.js` :

1. **Exclusion `/app/` du middleware LDP** (C1.9/D-8) : le proxy `POST /app/query` doit atteindre
   ORCE sans être intercepté par le conteneur LDP (le front, lui, est autonome et n'est plus servi
   par ce back).
2. **Décision K (CA-L15)** : `validateTransition()` lit les `business_rules` de `config/model.json`
   et rejette toute transition de statut invalide par `409 dspace:Error invalid_transition`.
3. **`ORDER BY t.<pk>` dynamique** dans la liste des conteneurs : les matviews gold n'ont pas de
   colonne `id` ; la pk est le dernier placeholder du `resource_iri_pattern` de `dsp.asset_mapping`.

## Notes opérationnelles

- **Front (autonome)** : aucune référence ici. Depuis `../app-supervision` :
  `./scripts/configure.sh http://localhost && npm run dev` → **`http://app.localhost/`** (port 80).
  Le client n'a AUCUN proxy vite : tous les appels partent en absolu vers `POD_URL`
  (cross-origin, CORS géré par le back) — un proxy vite casserait le DPoP
  (`DPoP HTTP URL mismatch`). Login Keycloak : **alice** (mdp `dev` en dev).
  En staging/prod : `./scripts/configure.sh https://fap.example.com` et mettre l'origine
  du front dans `FRONT_ORIGINS` (CORS + webOrigins Keycloak).
- **Certificat** : en dev HTTP pur, aucun. En staging (HTTPS auto-signé) : importer une fois
  `.build/caddy-root.crt` dans le navigateur (Paramètres → Certificats → Autorités → Importer).
- **Éditeur Node-RED** : `http://localhost/editor/` en dev (httpAdminRoot `/editor`, hors
  middleware LDP — copié au boot par `scripts/orce-entrypoint.sh` depuis `scripts/orce-settings.js`).
  Les nœuds LDP sont dans l'onglet **FAP-LDP** (`fap-ldp-container` PEP, `fap-ldp-pdp`,
  `fap-ldp-model` boot) ; notre proxy/outbox dans l'onglet **app-supervision**.
- **PATCH** : envoyer `Content-Type: application/json` (le body-parser Node-RED ne lit pas
  `application/merge-patch+json` en stream ; la sémantique merge-patch s'applique quand même,
  la clé doit être préfixée comme servie, ex. `{"app_tickets:status":"IN_PROGRESS"}`).
- Le token OIDC (password grant, tests) : `scope=openid` requis pour l'userinfo
  (voir « Vérifier » ci-dessus ; mdp de démo = `DEMO_PASSWORD` dans `.env`, `dev` en dev).
- Les migrations `sql/10x` sont rejouées automatiquement après le boot par `deploy-local.sh`
  (elles ont besoin de `app.*`, créé au boot par le nœud `fap-ldp`).

## Références

- `spec/supervision-energetique-spec-fonctionnelle.md` — périmètre F1–F7, modèle §4.1, RG-1..RG-6, CA-1..CA-5
- `spec/fap-light-spec-serveur.md` — cœur FAP-light (C1.1–C1.9, D-1..D-8, CA-S1..CA-S10)
- `spec/fap-ldp-spec.md` — extension FAP-LDP (E1–E3, décisions A–K, CA-L1..CA-L15)
- `spec/fap-domaine-app-et-profils.md` — profil light retenu, règles de sécurité (rôles PG)
- `spec/supervision-energetique-front-technique.md` — contrat client consommé (§9 proxy /app/query, §13.3 mapping assets, §13.5 workflow)
