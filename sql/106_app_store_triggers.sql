-- App-store core trigger function — referenced by model/app-store.model.json
-- (triggers[0]). plpgsql body: trigger logic cannot be purely
-- declarative ; the JSON declares the table/event/file, the SQL carries the body.
--
-- Trigger on user creation (app-store-spec §1.4.2): default prefs from
-- app.features.default_enabled AND owner-webid ACL (read/write/control) on
-- /prefs/<pk> + role:admin (M2).
-- SECURITY DEFINER: FORCE ROW LEVEL SECURITY filters even the owner (fap-ldp-spec
-- §7.2) — the function is created by the admin role (BYPASSRLS).
-- The pod host is derived from the webid (https://<host>/users/<pk>): no
-- placeholder substitution possible inside a function body.
CREATE OR REPLACE FUNCTION app.app_store_on_user_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_host  text := split_part(NEW.webid, '/', 3);
  v_prefs jsonb;
BEGIN
  SELECT COALESCE(jsonb_object_agg(slug, jsonb_build_object('enabled', default_enabled)), '{}'::jsonb)
    INTO v_prefs
    FROM app.features
   WHERE deleted_at IS NULL;

  INSERT INTO app.prefs (user_id, prefs) VALUES (NEW.id, v_prefs);

  INSERT INTO auth.acl (resource_uri, subject, modes, inherited) VALUES
    ('https://' || v_host || '/prefs/' || NEW.id::text, NEW.webid, '{read,write,control}', false),
    ('https://' || v_host || '/prefs/' || NEW.id::text, 'role:admin', '{read,write,control}', false);
  RETURN NEW;
END $$;
-- App-store core trigger function — referenced by model/app-store.model.json
-- (triggers[1]). When the admin adds a feature, injects the default key
-- into all existing prefs (app-store-spec §1.9.4b).
-- SECURITY DEFINER: same (write into app.prefs despite FORCE RLS).
CREATE OR REPLACE FUNCTION app.app_store_on_feature_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE app.prefs p
     SET prefs = p.prefs || jsonb_build_object(NEW.slug, jsonb_build_object('enabled', NEW.default_enabled))
   WHERE p.deleted_at IS NULL
     AND NOT (p.prefs ? NEW.slug);
  RETURN NEW;
END $$;
