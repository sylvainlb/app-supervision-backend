-- ============================================================================
-- 102_acl_init.sql — ACL initiales du déploiement supervision (spec fonc. §2, RG-2, RG-6)
--
-- ⚠️ auth.can() compare des IRI COMPLETS : le PEP appelle le PDP avec
--    resourceUri = baseIri + path (ex. 'https://app.localhost/tickets/').
--    → les resource_uri ci-dessous sont donc des IRI complets, bâtis sur la
--      variable psql :base_iri passée par deploy-local.sh (-v base_iri="https://$DOMAIN/").
--    Application manuelle :
--      psql -v base_iri="https://app.localhost/" -f sql/102_acl_init.sql
--
-- Sujets : webid, 'role:<role>', 'foaf:Agent' (public). Héritage (inherited)
-- uniquement sur les conteneurs (resource_uri finissant par '/').
-- RGPD : PAS de read globale sur la racine (hériterait sur /users/*) — /users/ = admin seul.
-- Le PEP pose en plus une ACE 'control' (subject = webid du propriétaire) sur chaque
-- ressource créée (champ owner du model.json).
-- ============================================================================

-- nettoyage des ACL d'une autre base IRI (changement dev http ↔ staging/prod https, ou ancien chemin relatif)
DELETE FROM auth.acl WHERE resource_uri NOT LIKE :'base_iri' || '%';

-- conteneur racine : lisible par les membres internes (inherited=false : ne PAS couvrir /users/)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri', 'role:gestionnaire', '{read}', false WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri' AND subject='role:gestionnaire');
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri', 'role:technicien', '{read}', false WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri' AND subject='role:technicien');
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri', 'role:admin', '{read}', false WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri' AND subject='role:admin');

-- bâtiments : lecture tous internes, écriture admin (published → aussi data space via contrat DSP)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'buildings/', s, '{read}', true FROM (VALUES ('role:gestionnaire'),('role:technicien'),('role:admin')) v(s)
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'buildings/' AND subject=s AND 'read'=ANY(modes));
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'buildings/', 'role:admin', '{read,write,append,control}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'buildings/' AND subject='role:admin' AND 'control'=ANY(modes));

-- tickets : lecture gestionnaire + technicien (RLS filtre assigned_to pour le technicien, RG-2) ;
-- écriture gestionnaire (append sur le conteneur, write sur la ressource via ACE owner + RLS)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'tickets/', s, '{read}', true FROM (VALUES ('role:gestionnaire'),('role:technicien'),('role:admin')) v(s)
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'tickets/' AND subject=s AND 'read'=ANY(modes));
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'tickets/', 'role:gestionnaire', '{read,write,append}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'tickets/' AND subject='role:gestionnaire' AND 'write'=ANY(modes));

-- users : admin seul (RGPD — jamais publié en data space, RG-5)
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'users/', 'role:admin', '{read,write,append,control}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'users/' AND subject='role:admin');

-- gold publié : lecture via contrat DSP (étape 1 du PDP) — ACL publique, le contrat filtre
INSERT INTO auth.acl (resource_uri, subject, modes, inherited)
SELECT :'base_iri' || 'gold/', 'foaf:Agent', '{read}', true
WHERE NOT EXISTS (SELECT 1 FROM auth.acl WHERE resource_uri=:'base_iri'||'gold/' AND subject='foaf:Agent');

-- chaque INSERT/DELETE déclenche pg_notify('fap_revoked') → le PDP purge son cache (CA-L9)
