-- ============================================================================
-- App store v1 — 012_backfill_prefs.sql : migration of EXISTING users
-- Spec: app-store-spec.md v0.4 §1.9.4(c).
--
-- To run ONCE at deployment, AFTER 010 + 011, for users
-- created before the app store was installed: default prefs + owner ACL.
-- (Users created afterwards are covered by the 011_prefs.sql trigger.)
-- Idempotent: does not touch existing rows/ACLs.
-- Role: admin. psql parameter: -v pod_host=<pod host>
-- ============================================================================

-- 1. Default prefs row for each user without a prefs row.
INSERT INTO app.prefs (user_id, prefs)
SELECT u.id,
       COALESCE((
         SELECT jsonb_object_agg(f.slug, jsonb_build_object('enabled', f.default_enabled))
           FROM app.features f
          WHERE f.deleted_at IS NULL
       ), '{}'::jsonb)
  FROM app.users u
  LEFT JOIN app.prefs p ON p.user_id = u.id
 WHERE p.user_id IS NULL;

-- 2. owner-webid ACL (read/write/control) on /prefs/<pk> for each user.
--    Host derived from the webid (no psql substitution possible here except in
--    direct SQL — we use :pod_host as elsewhere for consistency).
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT 'https://:pod_host/prefs/' || u.id::text, u.webid, '{read,write,control}', false
  FROM app.users u
 WHERE NOT EXISTS (
   SELECT 1 FROM auth.acl a
    WHERE a.resource_uri = 'https://:pod_host/prefs/' || u.id::text
      AND a.subject = u.webid);

-- 3. role:admin ACL on each /prefs/<pk> (M2).
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT 'https://:pod_host/prefs/' || u.id::text, 'role:admin', '{read,write,control}', false
  FROM app.users u
 WHERE NOT EXISTS (
   SELECT 1 FROM auth.acl a
    WHERE a.resource_uri = 'https://:pod_host/prefs/' || u.id::text
      AND a.subject = 'role:admin');

-- 4. Default keys for features added AFTER the users were created
--    (if the 011 trigger did not run for them — e.g. partial deployment).
UPDATE app.prefs p
   SET prefs = p.prefs || jsonb_build_object(f.slug, jsonb_build_object('enabled', f.default_enabled))
  FROM app.features f
 WHERE f.deleted_at IS NULL
   AND NOT (p.prefs ? f.slug);
