-- ============================================================================
-- App store v2 — 131_base_features_v2.sql : les features de BASE passent en
-- DISTANTES (CDN + SRI) — plus aucun composant métier packagé dans l'app.
-- Généré par app-supervision/scripts/build-features.mjs (sri = sha384 réelle du
-- bundle public/features-dist/<slug>.js). Le composant store (app-store/app-menu)
-- reste packagé : c'est le mécanisme d'installation (bootstrap).
-- Idempotent — rejoué au boot par deploy-local.sh.
-- ============================================================================

UPDATE app.features SET npm_package = '@facis/app-supervision', version = '0.1.0', cdn_url = '/features-dist/dashboard.js', sri = 'sha384-Bv/d+wKDHtxoPhRpem37vVllGWWDHaumjoc59tXGlQ3IC3mCgi/5MyPMDFrxXSGs', tag = 'building-map' WHERE slug = 'dashboard' AND deleted_at IS NULL;
UPDATE app.features SET npm_package = '@facis/app-supervision', version = '0.1.0', cdn_url = '/features-dist/building-detail.js', sri = 'sha384-4PCraNt2sRU0IceILiEPORd4SLsC1PftFWBYlPnCfgN73nhyMdEWSWZoe9n+P7jj', tag = 'building-header' WHERE slug = 'building-detail' AND deleted_at IS NULL;
UPDATE app.features SET npm_package = '@facis/app-supervision', version = '0.1.0', cdn_url = '/features-dist/anomalies.js', sri = 'sha384-o0ZPWaWq9E2PaB3KxYq5fUUoHaLewLjVYPmHp8QiAdNPltCr7hKqJVsdFvJfGGSQ', tag = 'anomaly-list' WHERE slug = 'anomalies' AND deleted_at IS NULL;
UPDATE app.features SET npm_package = '@facis/app-supervision', version = '0.1.0', cdn_url = '/features-dist/tickets.js', sri = 'sha384-l8GCY1IlG9ytncHAIEjwoYuCJk53oA0I5o4OVw2s67HNE15oxV6sYT4p0/NGPHBw', tag = 'ticket-board' WHERE slug = 'tickets' AND deleted_at IS NULL;
UPDATE app.features SET npm_package = '@facis/app-supervision', version = '0.1.0', cdn_url = '/features-dist/interventions.js', sri = 'sha384-oUEA9EyZWvluqrMebBRfiLjgd8lW8V0M0X6D61+XukdaQ7kMn6jot3fkmQGFIhJ4', tag = 'ticket-board' WHERE slug = 'interventions' AND deleted_at IS NULL;
UPDATE app.features SET npm_package = '@facis/app-supervision', version = '0.1.0', cdn_url = '/features-dist/admin.js', sri = 'sha384-I1vxjsbMF23Ecgx4/tlcJMosqpFbd5om7iSBdO+tcCaRsKoPf0IulmGWUHssA1HF', tag = 'user-admin' WHERE slug = 'admin' AND deleted_at IS NULL;
