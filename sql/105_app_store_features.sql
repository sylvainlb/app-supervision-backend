-- ============================================================================
-- App store v1 — 010_features.sql : catalogue app.features — DDL DE RÉFÉRENCE
--
-- ⚠ GÉNÉRÉ DEPUIS model/app-store.model.json (source de vérité déclarative,
--   appliquée au boot par le nœud FAP-LDP via le model.json de l'app —
--   fap-ldp-spec §5). Ne PAS éditer à la main : éditer le JSON.
--   (v0.4 : colonne role_min synchronisée à la main en attendant le regénérateur ;
--    source de vérité = model/app-store.model.json, champ role_min.)
--   Ce fichier sert à la lecture/debug et à la comparaison de drift.
--
-- Spec : app-store-spec.md v0.4 §1.4.1 (modèle), §1.9 (précisions tranchées).
-- Prérequis : core/sql/00*.sql du socle FAP-LDP. Paramètre psql : -v pod_host=…
-- SANS seed : le seed du catalogue est app-specific (model.json de l'app).
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.features (
  id               bigserial PRIMARY KEY,                 -- clé interne (l'IRI exposée est le slug, décision B2)
  slug             text NOT NULL UNIQUE
                     CHECK (slug ~ '^[a-z][a-z0-9-]{1,62}$'), -- IRI : /features/<slug>
  title_i18n       jsonb NOT NULL DEFAULT '{}'::jsonb,     -- localisé dès la v1 : {"fr": "…"} (§1.9.2)
  description_i18n jsonb NOT NULL DEFAULT '{}'::jsonb,
  icon             text NOT NULL DEFAULT 'extension',      -- nom Material Icons, fallback 'extension' (§1.9.3)
  menu_order       int  NOT NULL DEFAULT 0,                -- tri du menu = (menu_order, slug) (§1.9.1)
  component        text,                                    -- tag du custom element (packagé dans l'app en v1)
  route            text,                                    -- route Orbit associée
  role_min         text  NOT NULL DEFAULT 'all'
                     CHECK (role_min IN ('all','technicien','gestionnaire','admin')), -- filtrage menu + guard, pas sécurité (§1.4.1)
  config_schema    jsonb NOT NULL DEFAULT '{"fields": []}'::jsonb,  -- méta-schéma §1.9.6
  default_enabled  boolean NOT NULL DEFAULT false,          -- aussi utilisé si la clé manque dans les prefs (§1.9.4a)
  created_at       timestamptz NOT NULL DEFAULT now(),      -- champs transverses §1.9.5
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz                             -- tombstone (soft delete)
);

-- Triggers génériques du socle FAP-LDP (fap-ldp-spec §5.1/5.2) :
-- updated_at + versioning (app.versions) + tombstone.
CREATE TRIGGER features_set_updated_at BEFORE UPDATE ON app.features
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
CREATE TRIGGER features_versioning AFTER UPDATE OR DELETE ON app.features
  FOR EACH ROW EXECUTE FUNCTION app.version_trigger();

-- ----------------------------------------------------------------------------
-- RLS : IRI exposée = /features/<slug> (décision B2) → auth.can porte sur le slug.
-- Lecture : tous les users authentifiés du pod. Écriture : admin.
-- ----------------------------------------------------------------------------
ALTER TABLE app.features ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.features FORCE ROW LEVEL SECURITY;   -- même le owner est filtré (fap-ldp-spec §7.2)

CREATE POLICY features_read ON app.features FOR SELECT
  USING (auth.can('https://:pod_host/features/' || slug, 'read'));
CREATE POLICY features_write ON app.features FOR ALL
  USING (auth.can('https://:pod_host/features/' || slug, 'write'))
  WITH CHECK (auth.can('https://:pod_host/features/' || slug, 'write'));

-- ----------------------------------------------------------------------------
-- ACL seed (M2, §1.4.1) :
--  - read foaf:Agent + inherited sur le conteneur /features/ : lisible par tous
--    les membres du pod (contrat-cadre, claim org=<pod>) ; les externes sont de
--    toute façon arrêtés à l'étape 1 du PDP (conteneur published=false).
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
-- Mapping LDP : conteneur INTERNE (published=false → jamais exposé en data
-- space, invisible des externes, CA-L7). L'IRI des ressources est le slug :
-- resource_iri_pattern '{slug}' — le PEP fait le lookup slug→id sur
-- GET/PATCH/DELETE (couvert par CA-A7, aucun changement du PEP).
-- ----------------------------------------------------------------------------
INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name, resource_iri_pattern, published)
SELECT 'https://:pod_host/features/', 'https://:pod_host/features/', 'app', 'features',
       'https://:pod_host/features/{slug}', false
WHERE NOT EXISTS (
  SELECT 1 FROM dsp.asset_mapping WHERE container_uri = 'https://:pod_host/features/');
