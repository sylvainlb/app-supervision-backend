-- ============================================================================
-- 106_cr0_cr1_gold_ldp.sql — CR-0 + CR-1 (app-store-catalogue spec §2)
--
-- CR-0: publish ALL gold matviews as LDP containers (LDP-only
--   decision v0.3, revised front spec §13.3): net_grid_hourly, pv_performance_hourly,
--   weather_hourly, energy_balance_hourly, event_impact_daily,
--   streetlight_zone_hourly + the 3 already published + CR-1/CR-4 below.
-- CR-1: gold matviews `price_hourly` and `city_event_hourly` from the real
--   silver views silver.energy_price / silver.city_event, published as
--   LDP containers /gold/price_hourly/ and /gold/city_event_hourly/.
--
-- ⚠️ Defensive (to_regclass): replayed post-boot by deploy-local.sh.
--    Matviews do not appear in information_schema.tables (relkind='m').
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('silver.energy_price') IS NULL OR to_regclass('silver.city_event') IS NULL THEN
    RAISE NOTICE 'silver views missing — 106 to replay after the 1st core boot';
    RETURN;
  END IF;

  -- --- CR-1: gold matviews from the real silver views -----------------------
  EXECUTE $DDL$
    CREATE MATERIALIZED VIEW IF NOT EXISTS gold.price_hourly AS
    SELECT date_trunc('hour', event_timestamp) AS hour,
           site_id,
           avg(price_eur_kwh) AS price_eur_kwh
    FROM silver.energy_price
    GROUP BY 1, 2
  $DDL$;
  EXECUTE $DDL$
    CREATE MATERIALIZED VIEW IF NOT EXISTS gold.city_event_hourly AS
    SELECT date_trunc('hour', event_timestamp) AS hour,
           zone_id,
           count(*) AS event_count,
           max(severity) AS max_severity
    FROM silver.city_event
    GROUP BY 1, 2
  $DDL$;

  -- --- CR-0: LDP publication of ALL gold matviews ----------------------------
  -- resource_iri_pattern: the LAST placeholder = pk used by the
  -- dynamic PEP ORDER BY (fap-ldp patch #3, matviews without an id column).
  INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                                 resource_iri_pattern, time_column, published)
  VALUES
    ('/gold/anomaly_candidates/',     '/gold/anomaly_candidates/',     'gold', 'anomaly_candidates',     '/gold/anomaly_candidates/<event_timestamp>/<meter_id>', 'event_timestamp', true),
    ('/gold/city_dashboard_summary/', '/gold/city_dashboard_summary/', 'gold', 'city_dashboard_summary', '/gold/city_dashboard_summary/<site_id>',               'updated_at',      true),
    ('/gold/energy_balance_hourly/',  '/gold/energy_balance_hourly/',  'gold', 'energy_balance_hourly',  '/gold/energy_balance_hourly/<site_id>/<hour>',          'hour',            true),
    ('/gold/energy_cost_daily/',      '/gold/energy_cost_daily/',      'gold', 'energy_cost_daily',      '/gold/energy_cost_daily/<day>/<site_id>',              'day',             true),
    ('/gold/event_impact_daily/',     '/gold/event_impact_daily/',     'gold', 'event_impact_daily',     '/gold/event_impact_daily/<zone_id>/<event_date>',      'event_date',      true),
    ('/gold/intervention_anomaly_daily/', '/gold/intervention_anomaly_daily/', 'gold', 'intervention_anomaly_daily', '/gold/intervention_anomaly_daily/<building_id>/<day>', 'day',        true),
    ('/gold/net_grid_hourly/',        '/gold/net_grid_hourly/',        'gold', 'net_grid_hourly',        '/gold/net_grid_hourly/<site_id>/<hour>',               'hour',            true),
    ('/gold/pv_performance_hourly/',  '/gold/pv_performance_hourly/',  'gold', 'pv_performance_hourly',  '/gold/pv_performance_hourly/<site_id>/<hour>',         'hour',            true),
    ('/gold/streetlight_zone_hourly/', '/gold/streetlight_zone_hourly/','gold', 'streetlight_zone_hourly','/gold/streetlight_zone_hourly/<zone_id>/<hour>',       'hour',            true),
    ('/gold/weather_hourly/',         '/gold/weather_hourly/',         'gold', 'weather_hourly',         '/gold/weather_hourly/<site_id>/<hour>',                'hour',            true),
    ('/gold/price_hourly/',           '/gold/price_hourly/',           'gold', 'price_hourly',           '/gold/price_hourly/<site_id>/<hour>',                  'hour',            true),
    ('/gold/city_event_hourly/',      '/gold/city_event_hourly/',      'gold', 'city_event_hourly',      '/gold/city_event_hourly/<zone_id>/<hour>',             'hour',            true)
  ON CONFLICT (asset_uri) DO UPDATE SET published = true, container_uri = EXCLUDED.container_uri,
    table_schema = EXCLUDED.table_schema, table_name = EXCLUDED.table_name,
    resource_iri_pattern = EXCLUDED.resource_iri_pattern, time_column = EXCLUDED.time_column;

  -- --- reader/app rights on all gold matviews (LDP PEP + data plane) --------
  EXECUTE 'GRANT SELECT ON gold.anomaly_candidates, gold.city_dashboard_summary, gold.energy_balance_hourly, gold.energy_cost_daily, gold.event_impact_daily, gold.intervention_anomaly_daily, gold.net_grid_hourly, gold.pv_performance_hourly, gold.streetlight_zone_hourly, gold.weather_hourly, gold.price_hourly, gold.city_event_hourly TO reader, app';

  -- --- pg_cron refresh of the new matviews (with the core gold_refresh()) ---
  IF to_regclass('cron.job') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fap-app-gold-refresh-cr0cr1') THEN
      PERFORM cron.schedule('fap-app-gold-refresh-cr0cr1', '*/10 * * * *',
        'SELECT public.gold_refresh(); REFRESH MATERIALIZED VIEW gold.price_hourly; REFRESH MATERIALIZED VIEW gold.city_event_hourly;');
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron missing — refresh price_hourly/city_event_hourly to schedule after the 1st boot';
  END IF;
END $$;
