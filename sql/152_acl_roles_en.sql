-- ============================================================================
-- 152_acl_roles_en.sql — FIX: the historical ACLs use the FR roles
-- (role:manager / role:technician) but the IdP (Keycloak realm fap-light)
-- emits EN roles (manager / technician / admin, claim "role").
-- Without this fix, auth.can('/buildings/','read') = false for a manager → 403
-- on /buildings/ (and any FR ACL resource) → empty feature components.
-- We duplicate the FR ACLs to the EN roles (idempotent, no unique constraint
-- on (resource_uri, subject) → NOT EXISTS).
-- ============================================================================
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT a.resource_uri, 'role:manager', a.modes, a.inherited
FROM auth.acl a
WHERE a.subject = 'role:manager'
  AND NOT EXISTS (SELECT 1 FROM auth.acl b
                  WHERE b.resource_uri = a.resource_uri AND b.subject = 'role:manager');

INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT a.resource_uri, 'role:technician', a.modes, a.inherited
FROM auth.acl a
WHERE a.subject = 'role:technician'
  AND NOT EXISTS (SELECT 1 FROM auth.acl b
                  WHERE b.resource_uri = a.resource_uri AND b.subject = 'role:technician');
