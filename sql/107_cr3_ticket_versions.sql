-- ============================================================================
-- 107_cr3_ticket_versions.sql — CR-3 (spec app-store-catalogue §2) :
--   exposition LDP des versions : sous-conteneur `/tickets/<pk>/versions/`.
--
-- app.versions (socle fap-ldp : table_name, row_id, version, data, changed_by,
-- changed_at) historise toutes les tables app.*. Pour le conteneur LDP des
-- tickets on expose une VUE filtrée table_name='tickets' (les autres tables
-- restent non publiées — RG-5), mappée comme `/tickets/*/versions/` (même
-- mécanisme que `/tickets/*/comments/`).
--
-- ⚠️ Défensif (to_regclass) : rejoué post-boot par deploy-local.sh.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('app.versions') IS NULL OR to_regclass('app.tickets') IS NULL THEN
    RAISE NOTICE 'app.versions/app.tickets absent — 107 à rejouer après le 1er boot';
    RETURN;
  END IF;

  -- Vue filtrée : versions des tickets uniquement (RG-5 : pas de tables brutes app.* publiées)
  EXECUTE $DDL$
    CREATE OR REPLACE VIEW app.ticket_versions AS
    SELECT id, row_id AS ticket_id, version, data, changed_by, changed_at
    FROM app.versions
    WHERE table_name = 'tickets'
  $DDL$;
  EXECUTE 'GRANT SELECT ON app.ticket_versions TO reader, app';

  -- Mapping LDP du sous-conteneur /tickets/<pk>/versions/ (dernier placeholder = pk)
  INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                                 resource_iri_pattern, time_column, published)
  VALUES ('/tickets/*/versions/', '/tickets/*/versions/', 'app', 'ticket_versions',
          '/tickets/<ticket_id>/versions/<id>', 'changed_at', true)
  ON CONFLICT (asset_uri) DO UPDATE SET published = true, container_uri = EXCLUDED.container_uri,
    table_schema = EXCLUDED.table_schema, table_name = EXCLUDED.table_name,
    resource_iri_pattern = EXCLUDED.resource_iri_pattern, time_column = EXCLUDED.time_column;
END $$;
