-- ============================================================================
-- App store v1 — 012_backfill_prefs.sql : migration des users EXISTANTS
-- Spec : app-store-spec.md v0.4 §1.9.4(c).
--
-- À exécuter UNE SEULE FOIS au déploiement, APRÈS 010 + 011, pour les users
-- créés avant l'installation de l'app store : prefs par défaut + ACL owner.
-- (Les users créés ensuite sont couverts par le trigger de 011_prefs.sql.)
-- Idempotent : ne touche pas aux lignes/ACL déjà présentes.
-- Rôle : admin. Paramètre psql : -v pod_host=<host du pod>
-- ============================================================================

-- 1. Ligne de prefs par défaut pour chaque user sans ligne prefs.
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

-- 2. ACL owner-webid (read/write/control) sur /prefs/<pk> pour chaque user.
--    Host dérivé du webid (pas de substitution psql possible ici que dans le
--    SQL direct — on utilise :pod_host comme ailleurs pour la cohérence).
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT 'https://:pod_host/prefs/' || u.id::text, u.webid, '{read,write,control}', false
  FROM app.users u
 WHERE NOT EXISTS (
   SELECT 1 FROM auth.acl a
    WHERE a.resource_uri = 'https://:pod_host/prefs/' || u.id::text
      AND a.subject = u.webid);

-- 3. ACL role:admin sur chaque /prefs/<pk> (M2).
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT 'https://:pod_host/prefs/' || u.id::text, 'role:admin', '{read,write,control}', false
  FROM app.users u
 WHERE NOT EXISTS (
   SELECT 1 FROM auth.acl a
    WHERE a.resource_uri = 'https://:pod_host/prefs/' || u.id::text
      AND a.subject = 'role:admin');

-- 4. Clés par défaut des features ajoutées APRÈS la création des users
--    (si le trigger de 011 n'a pas tourné pour eux — ex. déploiement partiel).
UPDATE app.prefs p
   SET prefs = p.prefs || jsonb_build_object(f.slug, jsonb_build_object('enabled', f.default_enabled))
  FROM app.features f
 WHERE f.deleted_at IS NULL
   AND NOT (p.prefs ? f.slug);
