-- ============================================================================
-- 142_components_ai_models_acl.sql — initial ACLs of the two app-store/IA
-- containers provisioned by config/model.json (tables app.components,
-- app.ai_models — applied at orce boot; this file is replayed post-boot).
--
--   /components/  (chantier 3, app-store-spec v0.6 §1.4.3): published component
--                 documents (envelope { slug, sri, document }).
--   /ai_models/   (chantier 5, spec ch.4/5 annexe B): local model registry.
--
-- Both: read = every authenticated pod user (foaf:Agent, inherited), write =
-- admin only (publication / registry administration). published=false in the
-- model → LDP-served to pod members, NOT exposed in the external data space
-- (same regime as /features/). psql variable: -v base_iri=… (like 102_acl_init.sql).
-- Idempotent. Role: admin.
-- ============================================================================

-- /components/ : read foaf:Agent (inherited), write/control role:admin
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'components/', 'foaf:Agent', '{read}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri = :'base_iri' || 'components/' AND subject = 'foaf:Agent');

INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'components/', 'role:admin', '{write,control}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri = :'base_iri' || 'components/' AND subject = 'role:admin');

-- /ai_models/ : read foaf:Agent (inherited — profiles browse and pick a model),
-- write/control role:admin. NO credential here (F1.4): endpoint/model_id only.
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'ai_models/', 'foaf:Agent', '{read}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri = :'base_iri' || 'ai_models/' AND subject = 'foaf:Agent');

INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'ai_models/', 'role:admin', '{write,control}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri = :'base_iri' || 'ai_models/' AND subject = 'role:admin');

-- ----------------------------------------------------------------------------
-- Seed: one local model entry so the registry is not empty at first boot.
-- The endpoint is overridable at deploy time: SET app.ai_models_endpoint before
-- replaying (default = ollama's default port on the host).
-- The entry is the value of cmp:model in AI components (equality on `name`).
-- No credential (F1.4) — remote-model secrets live in the ORCE service env
-- (AI_MODEL_SECRET_<NAME>).
-- Defensive (like 101_seed_demo.sql): app.ai_models is created at orce boot →
-- skip gracefully when replayed at initdb time, before the 1st boot.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('app.ai_models') IS NULL THEN
    RAISE NOTICE 'app.ai_models missing — 142 seed replayed after the 1st orce boot';
    RETURN;
  END IF;
  INSERT INTO app.ai_models (name, protocol, endpoint, model_id, location, context_window, native_structured_output, jurisdiction)
  SELECT 'ollama://mistral-small', 'openai_chat',
         COALESCE(NULLIF(current_setting('app.ai_models_endpoint', true), ''), 'http://localhost:11434'),
         'mistral-small', 'local', 128000, true, 'local (pod host)'
  WHERE NOT EXISTS (SELECT 1 FROM app.ai_models WHERE name = 'ollama://mistral-small');
END $$;
