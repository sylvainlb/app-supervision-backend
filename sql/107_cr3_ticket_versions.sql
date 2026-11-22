-- ============================================================================
-- 107_cr3_ticket_versions.sql — CR-3 (app-store-catalogue spec §2) :
--   LDP exposure of versions: sub-container `/tickets/<pk>/versions/`.
--
-- app.versions (fap-ldp core: table_name, row_id, version, data, changed_by,
-- changed_at) version-tracks all app.* tables. For the tickets LDP container
-- we expose a FILTERED VIEW table_name='tickets' (the other tables
-- remain unpublished — RG-5), mapped as `/tickets/*/versions/` (same
-- mechanism as `/tickets/*/comments/`).
--
-- ⚠️ Defensive (to_regclass): replayed post-boot by deploy-local.sh.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('app.versions') IS NULL OR to_regclass('app.tickets') IS NULL THEN
    RAISE NOTICE 'app.versions/app.tickets missing — 107 to replay after the 1st boot';
    RETURN;
  END IF;

  -- Filtered view: ticket versions only (RG-5: no raw app.* tables published)
  EXECUTE $DDL$
    CREATE OR REPLACE VIEW app.ticket_versions AS
    SELECT id, row_id AS ticket_id, version, data, changed_by, changed_at
    FROM app.versions
    WHERE table_name = 'tickets'
  $DDL$;
  EXECUTE 'GRANT SELECT ON app.ticket_versions TO reader, app';

  -- LDP mapping of the /tickets/<pk>/versions/ sub-container (last placeholder = pk)
  INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                                 resource_iri_pattern, time_column, published)
  VALUES ('/tickets/*/versions/', '/tickets/*/versions/', 'app', 'ticket_versions',
          '/tickets/<ticket_id>/versions/<id>', 'changed_at', true)
  ON CONFLICT (asset_uri) DO UPDATE SET published = true, container_uri = EXCLUDED.container_uri,
    table_schema = EXCLUDED.table_schema, table_name = EXCLUDED.table_name,
    resource_iri_pattern = EXCLUDED.resource_iri_pattern, time_column = EXCLUDED.time_column;
END $$;
