-- ============================================================================
-- 104_gold_ldp_published.sql — conteneurs LDP publiés pour les agrégats gold
-- Mapping définitif spec front §13.3 : anomaly_candidates, city_dashboard_summary,
-- energy_cost_daily sont servis en LDP direct (publiés) ; net_grid_hourly et
-- pv_performance_hourly restent DSP-only (volume horaire) via le proxy /app/query.
--
-- ⚠️ les matviews gold n'apparaissent pas dans information_schema.tables
--    (relkind='m') : le seed 007 du cœur ne les mappe pas → on les déclare ici.
-- ============================================================================

INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                               resource_iri_pattern, time_column, published)
VALUES
  ('/gold/anomaly_candidates/',     '/gold/anomaly_candidates/',     'gold', 'anomaly_candidates',     '/gold/anomaly_candidates/<event_timestamp>/<meter_id>', 'event_timestamp', true),
  ('/gold/city_dashboard_summary/', '/gold/city_dashboard_summary/', 'gold', 'city_dashboard_summary', '/gold/city_dashboard_summary/<site_id>',               'updated_at',      true),
  ('/gold/energy_cost_daily/',      '/gold/energy_cost_daily/',      'gold', 'energy_cost_daily',      '/gold/energy_cost_daily/<day>/<site_id>',              'day',             true)
ON CONFLICT (asset_uri) DO UPDATE SET published = true;

-- le conteneur /gold/ est déjà en ACL read foaf:Agent (102_acl_init.sql) ;
-- la publication data space (catalogue DSP) reste gérée côté cœur (datasets.json).
