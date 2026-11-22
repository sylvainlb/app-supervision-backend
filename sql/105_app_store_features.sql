-- ============================================================================
-- App store v1 — 010_features.sql : app.features catalog — REFERENCE DDL
--
-- ⚠ GENERATED FROM model/app-store.model.json (declarative source of truth,
--   applied at boot by the FAP-LDP node via the app's model.json —
--   fap-ldp-spec §5). Do NOT edit by hand: edit the JSON.
--   (v0.4: role_min column synced by hand until the regenerator lands ;
--    source of truth = model/app-store.model.json, role_min field.)
--   This file is for reading/debugging and drift comparison.
--
-- Spec: app-store-spec.md v0.4 §1.4.1 (model), §1.9 (resolved points).
-- Prerequisite: FAP-LDP core core/sql/00*.sql. psql parameter: -v pod_host=…
-- NO seed: the catalog seed is app-specific (the app's model.json).
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.features (
  id               bigserial PRIMARY KEY,                 -- internal key (the exposed IRI is the slug, decision B2)
  slug             text NOT NULL UNIQUE
                     CHECK (slug ~ '^[a-z][a-z0-9-]{1,62}$'), -- IRI: /features/<slug>
  title_i18n       jsonb NOT NULL DEFAULT '{}'::jsonb,     -- localized from v1: {\"en\": \"…\", \"fr\": \"…\"} (§1.9.2)
  description_i18n jsonb NOT NULL DEFAULT '{}'::jsonb,
  icon             text NOT NULL DEFAULT 'extension',      -- Material Icons name, fallback 'extension' (§1.9.3)
  menu_order       int  NOT NULL DEFAULT 0,                -- menu sort = (menu_order, slug) (§1.9.1)
  component        text,                                    -- custom element tag (packaged in the app in v1)
  route            text,                                    -- associated Orbit route
  role_min         text  NOT NULL DEFAULT 'all'
                     CHECK (role_min IN ('all','technician','manager','admin')), -- menu + guard filtering, not security (§1.4.1)
  config_schema    jsonb NOT NULL DEFAULT '{"fields": []}'::jsonb,  -- meta-schema §1.9.6
  default_enabled  boolean NOT NULL DEFAULT false,          -- also used if the key is missing from prefs (§1.9.4a)
  created_at       timestamptz NOT NULL DEFAULT now(),      -- cross-cutting fields §1.9.5
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz                             -- tombstone (soft delete)
);

-- Generic FAP-LDP core triggers (fap-ldp-spec §5.1/5.2) :
-- updated_at + versioning (app.versions) + tombstone.
CREATE TRIGGER features_set_updated_at BEFORE UPDATE ON app.features
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER features_versioning AFTER UPDATE OR DELETE ON app.features
  FOR EACH ROW EXECUTE FUNCTION app.version_trigger();

-- ----------------------------------------------------------------------------
-- RLS: exposed IRI = /features/<slug> (decision B2) → auth.can applies to the slug.
-- Read: all authenticated users of the pod. Write: admin.
-- ----------------------------------------------------------------------------
ALTER TABLE app.features ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.features FORCE ROW LEVEL SECURITY;   -- even the owner is filtered (fap-ldp-spec §7.2)

CREATE POLICY features_read ON app.features FOR SELECT
  USING (auth.can('https://:pod_host/features/' || slug, 'read'));
CREATE POLICY features_write ON app.features FOR ALL
  USING (auth.can('https://:pod_host/features/' || slug, 'write'))
  WITH CHECK (auth.can('https://:pod_host/features/' || slug, 'write'));

-- ----------------------------------------------------------------------------
-- ACL seed (M2, §1.4.1) :
--  - read foaf:Agent + inherited on the /features/ container: readable by all
--    pod members (framework contract, claim org=<pod>) ; externals are anyway
--    stopped at PDP step 1 (container published=false).
--  - write/control role:admin.
-- ----------------------------------------------------------------------------
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT 'https://:pod_host/features/', 'foaf:Agent', '{read}', true
WHERE NOT EXISTS (
  SELECT 1 FROM auth.acl WHERE resource_uri = 'https://:pod_host/features/' AND subject = 'foaf:Agent');

INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT 'https://:pod_host/features/', 'role:admin', '{write,control}', true
WHERE NOT EXISTS (
  SELECT 1 FROM auth.acl WHERE resource_uri = 'https://:pod_host/features/' AND subject = 'role:admin');

-- ----------------------------------------------------------------------------
-- LDP mapping: INTERNAL container (published=false → never exposed in the data
-- space, invisible to externals, CA-L7). The resource IRI is the slug:
-- resource_iri_pattern '{slug}' — the PEP does the slug→id lookup on
-- GET/PATCH/DELETE (covered by CA-A7, no PEP change).
-- ----------------------------------------------------------------------------
INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name, resource_iri_pattern, published)
SELECT 'https://:pod_host/features/', 'https://:pod_host/features/', 'app', 'features',
       'https://:pod_host/features/{slug}', false
WHERE NOT EXISTS (
  SELECT 1 FROM dsp.asset_mapping WHERE container_uri = 'https://:pod_host/features/');
