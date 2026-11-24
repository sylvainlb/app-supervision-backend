-- ============================================================================
-- 152_acl_roles_en.sql — FIX: les ACL historiques utilisent les rôles FR
-- (role:gestionnaire / role:technicien) mais l'IdP (Keycloak realm fap-light)
-- émet des rôles EN (manager / technician / admin, claim "role").
-- Sans ce fix, auth.can('/buildings/','read') = false pour un manager → 403
-- sur /buildings/ (et toute ressource ACL en FR) → composants features vides.
-- On duplique les ACL FR vers les rôles EN (idempotent, pas de contrainte
-- unique sur (resource_uri, subject) → NOT EXISTS).
-- ============================================================================
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT a.resource_uri, 'role:manager', a.modes, a.inherited
FROM auth.acl a
WHERE a.subject = 'role:gestionnaire'
  AND NOT EXISTS (SELECT 1 FROM auth.acl b
                  WHERE b.resource_uri = a.resource_uri AND b.subject = 'role:manager');

INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT a.resource_uri, 'role:technician', a.modes, a.inherited
FROM auth.acl a
WHERE a.subject = 'role:technicien'
  AND NOT EXISTS (SELECT 1 FROM auth.acl b
                  WHERE b.resource_uri = a.resource_uri AND b.subject = 'role:technician');
