-- ============================================================================
-- 104_gold_ldp_published.sql — published LDP containers for gold aggregates
-- Final mapping front spec §13.3 : anomaly_candidates, city_dashboard_summary,
-- energy_cost_daily are served as direct LDP (published) ; net_grid_hourly and
-- pv_performance_hourly remain DSP-only (hourly volume) via the /app/query proxy.
--
-- ⚠️ gold matviews do not appear in information_schema.tables
--    (relkind='m') : the core seed 007 does not map them → we declare them here.
-- ============================================================================

INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                               resource_iri_pattern, time_column, published)
VALUES
  ('/gold/anomaly_candidates/',     '/gold/anomaly_candidates/',     'gold', 'anomaly_candidates',     '/gold/anomaly_candidates/<event_timestamp>/<meter_id>', 'event_timestamp', true),
  ('/gold/city_dashboard_summary/', '/gold/city_dashboard_summary/', 'gold', 'city_dashboard_summary', '/gold/city_dashboard_summary/<site_id>',               'updated_at',      true),
  ('/gold/energy_cost_daily/',      '/gold/energy_cost_daily/',      'gold', 'energy_cost_daily',      '/gold/energy_cost_daily/<day>/<site_id>',              'day',             true)
ON CONFLICT (asset_uri) DO UPDATE SET published = true;

-- the /gold/ container is already in ACL read foaf:Agent (102_acl_init.sql) ;
-- data space publication (DSP catalog) remains managed core-side (datasets.json).
