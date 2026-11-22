-- ============================================================================
-- 102_acl_init.sql — initial ACLs of the supervision deployment (func. spec §2, RG-2, RG-6)
--
-- ⚠️ auth.can() compares FULL IRIs: the PEP calls the PDP with
--    resourceUri = baseIri + path (e.g. 'https://app.localhost/tickets/').
--    → the resource_uri below are therefore full IRIs, built on the
--      psql variable :base_iri passed by deploy-local.sh (-v base_iri="https://$DOMAIN/").
--    Manual application:
--      psql -v base_iri="https://app.localhost/" -f sql/102_acl_init.sql
--
-- Subjects: webid, 'role:<role>', 'foaf:Agent' (public). Inheritance (inherited)
-- only on containers (resource_uri ending with '/').
-- GDPR: NO global read on the root (it would inherit onto /users/*) — /users/ = admin only.
-- The PEP also sets a 'control' ACE (subject = owner's webid) on each created
-- resource (owner field of model.json).
-- ============================================================================

-- cleanup of ACLs from another base IRI (dev http ↔ staging/prod https switch, or old relative path)
DELETE FROM auth.acl WHERE resource_uri NOT LIKE :'base_iri' || '%';

-- root container: readable by internal members (inherited=false: do NOT cover /users/)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri', 'role:manager', '{read}', false WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri' AND subject='role:manager');
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri', 'role:technician', '{read}', false WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri' AND subject='role:technician');
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri', 'role:admin', '{read}', false WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri' AND subject='role:admin');

-- buildings: read all internal, write admin (published → also data space via DSP contract)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'buildings/', s, '{read}', true FROM (VALUES ('role:manager'),('role:technician'),('role:admin')) v(s)
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'buildings/' AND subject=s AND 'read'=ANY(modes));
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'buildings/', 'role:admin', '{read,write,append,control}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'buildings/' AND subject='role:admin' AND 'control'=ANY(modes));

-- tickets: read manager + technician (RLS filters assigned_to for the technician, RG-2);
-- write manager (append on the container, write on the resource via owner ACE + RLS)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'tickets/', s, '{read}', true FROM (VALUES ('role:manager'),('role:technician'),('role:admin')) v(s)
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'tickets/' AND subject=s AND 'read'=ANY(modes));
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'tickets/', 'role:manager', '{read,write,append}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'tickets/' AND subject='role:manager' AND 'write'=ANY(modes));

-- users: admin only (GDPR — never published in the data space, RG-5)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'users/', 'role:admin', '{read,write,append,control}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'users/' AND subject='role:admin');

-- published gold: read via DSP contract (PDP step 1) — public ACL, the contract filters
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'gold/', 'foaf:Agent', '{read}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'gold/' AND subject='foaf:Agent');

-- every INSERT/DELETE triggers pg_notify('fap_revoked') → the PDP purges its cache (CA-L9)
