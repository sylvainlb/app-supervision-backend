-- ============================================================================
-- App store v1 — 011_prefs.sql : préférences app.prefs — DDL DE RÉFÉRENCE
--
-- ⚠ GÉNÉRÉ DEPUIS model/app-store.model.json (source de vérité, appliquée au
--   boot par le nœud via le model.json de l'app). Ne PAS éditer à la main.
--
-- Spec : app-store-spec.md v0.4 §1.4.2, §1.9.4, §1.9.10.
-- Ressource LDP UNIQUE par utilisateur : /prefs/<user_id> (décisions B1/B3).
-- Body PATCH (forme R1, §1.5) : {"prefs": {"<slug>": {"enabled": false}}}
-- Prérequis : core/sql/00*.sql + socle app.features. Paramètre psql : -v pod_host=…
-- ============================================================================
-- Les CORPS des 2 fonctions trigger ne sont PAS ici : ils vivent dans
-- sql/triggers/app_store_on_user_insert.sql et app_store_on_feature_insert.sql
-- (référencés par le JSON). Seuls les CREATE TRIGGER sont reproduits ci-dessous.

CREATE TABLE IF NOT EXISTS app.prefs (
  user_id    bigint PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,  -- RGPD (§1.9.5)
  prefs      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {"<slug>": {"enabled": bool, "config": {...}}}
  created_at timestamptz NOT NULL DEFAULT now(),   -- champs transverses §1.9.5
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz                           -- tombstone
);

CREATE TRIGGER prefs_set_updated_at BEFORE UPDATE ON app.prefs
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER prefs_versioning AFTER UPDATE OR DELETE ON app.prefs
  FOR EACH ROW EXECUTE FUNCTION app.version_trigger();

-- ----------------------------------------------------------------------------
-- RLS owner-only : un user ne voit/modifie QUE ses prefs ; pour un autre user
-- la ligne est filtrée → le PEP rend 404 (décision §1.9.10 : ne divulgue pas
-- l'existence — CA-A2).
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
-- Mapping LDP : conteneur interne /prefs/, ressource /prefs/<user_id>, PK bigint
-- (conforme au pattern <container>/<pk> du PEP, fap-ldp-spec §6.3).
-- ----------------------------------------------------------------------------
INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name, resource_iri_pattern, published)
SELECT 'https://:pod_host/prefs/', 'https://:pod_host/prefs/', 'app', 'prefs',
       'https://:pod_host/prefs/{user_id}', false
WHERE NOT EXISTS (
  SELECT 1 FROM dsp.asset_mapping WHERE container_uri = 'https://:pod_host/prefs/');

-- ----------------------------------------------------------------------------
-- Triggers (corps dans sql/triggers/, référencés par model/app-store.model.json) :
--  1. on_user_insert_app_store    AFTER INSERT ON app.users    → sql/triggers/app_store_on_user_insert.sql
--     (prefs par défaut + ACL owner-webid sur /prefs/<pk> + role:admin, §1.4.2/M2)
--  2. on_feature_insert_app_store AFTER INSERT ON app.features → sql/triggers/app_store_on_feature_insert.sql
--     (clé par défaut injectée dans toutes les prefs, §1.9.4b)
-- SECURITY DEFINER (FORCE RLS filtre même le owner) ; host dérivé du webid.
-- ----------------------------------------------------------------------------
CREATE TRIGGER on_user_insert_app_store AFTER INSERT ON app.users
  FOR EACH ROW EXECUTE FUNCTION app.app_store_on_user_insert();

CREATE TRIGGER on_feature_insert_app_store AFTER INSERT ON app.features
  FOR EACH ROW EXECUTE FUNCTION app.app_store_on_feature_insert();
