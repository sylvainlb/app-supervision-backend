-- ============================================================================
-- App store v1 — 011_prefs.sql : app.prefs preferences — REFERENCE DDL
--
-- ⚠ GENERATED FROM model/app-store.model.json (source of truth, applied at
--   boot by the node via the app's model.json). Do NOT edit by hand.
--
-- Spec: app-store-spec.md v0.4 §1.4.2, §1.9.4, §1.9.10.
-- ONE LDP resource per user: /prefs/<user_id> (decisions B1/B3).
-- PATCH body (form R1, §1.5) : {"prefs": {"<slug>": {"enabled": false}}}
-- Prerequisite: core/sql/00*.sql + app.features core. psql parameter: -v pod_host=…
-- ============================================================================
-- The BODIES of the 2 trigger functions are NOT here: they live in
-- sql/triggers/app_store_on_user_insert.sql and app_store_on_feature_insert.sql
-- (referenced by the JSON). Only the CREATE TRIGGER statements are reproduced below.

CREATE TABLE IF NOT EXISTS app.prefs (
  user_id    bigint PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,  -- GDPR (§1.9.5)
  prefs      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {"<slug>": {"enabled": bool, "config": {...}}}
  created_at timestamptz NOT NULL DEFAULT now(),   -- cross-cutting fields §1.9.5
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz                           -- tombstone
);

CREATE TRIGGER prefs_set_updated_at BEFORE UPDATE ON app.prefs
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER prefs_versioning AFTER UPDATE OR DELETE ON app.prefs
  FOR EACH ROW EXECUTE FUNCTION app.version_trigger();

-- ----------------------------------------------------------------------------
-- RLS owner-only: a user only sees/modifies THEIR prefs; for another user
-- the row is filtered out → the PEP returns 404 (decision §1.9.10: do not leak
-- existence — CA-A2).
-- ----------------------------------------------------------------------------
ALTER TABLE app.prefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.prefs FORCE ROW LEVEL SECURITY;

CREATE POLICY prefs_read ON app.prefs FOR SELECT
  USING (auth.can('https://:pod_host/prefs/' || user_id::text, 'read'));
CREATE POLICY prefs_insert ON app.prefs FOR INSERT
  WITH CHECK (auth.can('https://:pod_host/prefs/' || user_id::text, 'write'));
CREATE POLICY prefs_update ON app.prefs FOR UPDATE
  USING (auth.can('https://:pod_host/prefs/' || user_id::text, 'write'))
  WITH CHECK (auth.can('https://:pod_host/prefs/' || user_id::text, 'write'));
CREATE POLICY prefs_delete ON app.prefs FOR DELETE
  USING (auth.can('https://:pod_host/prefs/' || user_id::text, 'write'));

-- ----------------------------------------------------------------------------
-- LDP mapping: internal container /prefs/, resource /prefs/<user_id>, bigint PK
-- (compliant with the PEP <container>/<pk> pattern, fap-ldp-spec §6.3).
-- ----------------------------------------------------------------------------
INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name, resource_iri_pattern, published)
SELECT 'https://:pod_host/prefs/', 'https://:pod_host/prefs/', 'app', 'prefs',
       'https://:pod_host/prefs/{user_id}', false
WHERE NOT EXISTS (
  SELECT 1 FROM dsp.asset_mapping WHERE container_uri = 'https://:pod_host/prefs/');

-- ----------------------------------------------------------------------------
-- Triggers (bodies in sql/triggers/, referenced by model/app-store.model.json):
--  1. on_user_insert_app_store    AFTER INSERT ON app.users    → sql/triggers/app_store_on_user_insert.sql
--     (default prefs + owner-webid ACL on /prefs/<pk> + role:admin, §1.4.2/M2)
--  2. on_feature_insert_app_store AFTER INSERT ON app.features → sql/triggers/app_store_on_feature_insert.sql
--     (default key injected into all prefs, §1.9.4b)
-- SECURITY DEFINER (FORCE RLS filters even the owner) ; host derived from the webid.
-- ----------------------------------------------------------------------------
CREATE TRIGGER on_user_insert_app_store AFTER INSERT ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.app_store_on_user_insert();

CREATE TRIGGER on_feature_insert_app_store AFTER INSERT ON app.features
  FOR EACH ROW EXECUTE FUNCTION app.app_store_on_feature_insert();
