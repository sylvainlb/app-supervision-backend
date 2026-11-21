-- ============================================================================
-- 106_cr0_cr1_gold_ldp.sql — CR-0 + CR-1 (spec app-store-catalogue §2)
--
-- CR-0 : publier TOUTES les matviews gold en conteneurs LDP (décision LDP-only
--   v0.3, spec front §13.3 révisée) : net_grid_hourly, pv_performance_hourly,
--   weather_hourly, energy_balance_hourly, event_impact_daily,
--   streetlight_zone_hourly + les 3 déjà publiées + CR-1/CR-4 ci-dessous.
-- CR-1 : matviews gold `price_hourly` et `city_event_hourly` à partir des vues
--   silver réelles silver.energy_price / silver.city_event, publiées en
--   conteneurs LDP /gold/price_hourly/ et /gold/city_event_hourly/.
--
-- ⚠️ Défensif (to_regclass) : rejoué post-boot par deploy-local.sh.
--    Les matviews n'apparaissent pas dans information_schema.tables (relkind='m').
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('silver.energy_price') IS NULL OR to_regclass('silver.city_event') IS NULL THEN
    RAISE NOTICE 'vues silver absentes — 106 à rejouer après le 1er boot du cœur';
    RETURN;
  END IF;

  -- --- CR-1 : matviews gold depuis les vues silver réelles --------------------
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

  -- --- CR-0 : publication LDP de TOUTES les matviews gold --------------------
  -- resource_iri_pattern : le DERNIER placeholder = pk utilisée par le ORDER BY
  -- dynamique du PEP (patch fap-ldp #3, matviews sans colonne id).
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

  -- --- Droits reader/app sur toutes les matviews gold (PEP LDP + data plane) --
  EXECUTE 'GRANT SELECT ON gold.anomaly_candidates, gold.city_dashboard_summary, gold.energy_balance_hourly, gold.energy_cost_daily, gold.event_impact_daily, gold.intervention_anomaly_daily, gold.net_grid_hourly, gold.pv_performance_hourly, gold.streetlight_zone_hourly, gold.weather_hourly, gold.price_hourly, gold.city_event_hourly TO reader, app';

  -- --- Refresh pg_cron des nouvelles matviews (avec le gold_refresh() cœur) ---
  IF to_regclass('cron.job') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fap-app-gold-refresh-cr0cr1') THEN
      PERFORM cron.schedule('fap-app-gold-refresh-cr0cr1', '*/10 * * * *',
        'SELECT public.gold_refresh(); REFRESH MATERIALIZED VIEW gold.price_hourly; REFRESH MATERIALIZED VIEW gold.city_event_hourly;');
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron absent — refresh price_hourly/city_event_hourly à planifier après le 1er boot';
  END IF;
END $$;
