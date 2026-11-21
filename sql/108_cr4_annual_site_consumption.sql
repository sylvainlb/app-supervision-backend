-- ============================================================================
-- 108_cr4_annual_site_consumption.sql — CR-4 (spec app-store-catalogue §2) :
--   matview gold `annual_site_consumption` (kWh/an par bâtiment), publiée en
--   conteneur LDP /gold/annual_site_consumption/ (export réglementaire,
--   benchmark kwh_m2 via area_m2 = CR-2).
--
-- Source : silver.energy_meter (par meter_id, pas horaire agrégé par site comme
-- net_grid_hourly) JOIN app.buildings ON meter_id. Pas horaire = kWh sur 1 h.
--
-- ⚠️ Défensif (to_regclass) : rejoué post-boot par deploy-local.sh.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('silver.energy_meter') IS NULL OR to_regclass('app.buildings') IS NULL
     OR to_regclass('gold.net_grid_hourly') IS NULL THEN
    RAISE NOTICE 'silver.energy_meter / app.buildings / gold absent — 108 à rejouer après le 1er boot';
    RETURN;
  END IF;

  EXECUTE $DDL$
    CREATE MATERIALIZED VIEW IF NOT EXISTS gold.annual_site_consumption AS
    SELECT b.id AS building_id,
           b.name AS building_name,
           date_part('year', m.event_timestamp)::int AS year,
           sum(m.active_power_kw) AS consumption_kwh,
           sum(m.active_power_kw) / nullif(b.area_m2, 0) AS kwh_m2,
           b.area_m2
    FROM silver.energy_meter m
    JOIN app.buildings b ON b.meter_id = m.meter_id
    GROUP BY b.id, b.name, 3, b.area_m2
  $DDL$;

  -- Publication LDP + data space (dernier placeholder = pk pour le ORDER BY du PEP)
  INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                                 resource_iri_pattern, time_column, published)
  VALUES ('/gold/annual_site_consumption/', '/gold/annual_site_consumption/',
          'gold', 'annual_site_consumption',
          '/gold/annual_site_consumption/<building_id>/<year>', 'year', true)
  ON CONFLICT (asset_uri) DO UPDATE SET published = true, container_uri = EXCLUDED.container_uri,
    table_schema = EXCLUDED.table_schema, table_name = EXCLUDED.table_name,
    resource_iri_pattern = EXCLUDED.resource_iri_pattern, time_column = EXCLUDED.time_column;

  EXECUTE 'GRANT SELECT ON gold.annual_site_consumption TO reader, app';

  -- Refresh pg_cron (après gold_refresh() cœur, 10 min)
  IF to_regclass('cron.job') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fap-app-gold-refresh-annual') THEN
      PERFORM cron.schedule('fap-app-gold-refresh-annual', '*/10 * * * *',
        'SELECT public.gold_refresh(); REFRESH MATERIALIZED VIEW gold.annual_site_consumption;');
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron absent — refresh annual_site_consumption à planifier après le 1er boot';
  END IF;
END $$;
