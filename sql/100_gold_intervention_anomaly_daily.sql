-- ============================================================================
-- 100_gold_intervention_anomaly_daily.sql — published aggregate view (func. spec F7, RG-5, CA-4)
--
-- Gold matview `intervention_anomaly_daily` = join `gold.anomaly_candidates`
-- × `app.tickets` : number of anomalies, tickets, average resolution delay,
-- per building and per day. Only aggregated gold views are published in the
-- data space (RG-5): never the raw app.* tables.
--
-- ⚠️ This file is defensive (to_regclass): the app.* tables are created AT BOOT
-- by the fap-ldp node from config/model.json, hence potentially AFTER the
-- initdb migrations. On a from-scratch deployment, replay it after the 1st
-- boot:
--   docker compose -f ../fap-ldp/compose/docker-compose.yml --env-file .env \
--     exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/<NN>_custom_100_gold_intervention_anomaly_daily.sql
-- (or directly: psql "postgres://postgres@localhost/fap" -f sql/100_gold_intervention_anomaly_daily.sql)
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('app.tickets') IS NULL OR to_regclass('app.buildings') IS NULL
     OR to_regclass('gold.anomaly_candidates') IS NULL THEN
    RAISE NOTICE 'app.* or gold.anomaly_candidates missing — 100_gold_intervention_anomaly_daily.sql to replay after the 1st boot';
    RETURN;
  END IF;

  -- --- Aggregate matview (F7) ------------------------------------------------
  -- Anomaly ↔ building link via app.buildings.meter_id = anomaly_candidates.meter_id.
  EXECUTE $DDL$
    CREATE MATERIALIZED VIEW IF NOT EXISTS gold.intervention_anomaly_daily AS
    WITH anom AS (
      SELECT b.id AS building_id, a.event_timestamp::date AS day, count(*) AS anomalies
      FROM gold.anomaly_candidates a
      JOIN app.buildings b ON b.meter_id = a.meter_id
      GROUP BY b.id, a.event_timestamp::date
    ),
    tick AS (
      SELECT building_id, created_at::date AS day,
             count(*) AS tickets,
             avg(EXTRACT(EPOCH FROM (updated_at - created_at)) / 3600)
               FILTER (WHERE status IN ('RESOLVED', 'CLOSED')) AS avg_resolution_hours
      FROM app.tickets
      WHERE deleted_at IS NULL
      GROUP BY building_id, created_at::date
    )
    SELECT a.building_id,
           b.name AS building_name,
           a.day,
           a.anomalies,
           coalesce(t.tickets, 0) AS tickets,
           t.avg_resolution_hours
    FROM anom a
    JOIN app.buildings b ON b.id = a.building_id
    LEFT JOIN tick t ON t.building_id = a.building_id AND t.day = a.day
  $DDL$;

  -- --- Publication: DSP asset + LDP container (CA-4, CA-L2) ------------------
  -- The core DSP catalog self-derives from information_schema (publishable gold schema);
  -- here we register the LDP mapping and mark it published (contract + policySummary + HMAC
  -- served by the core control plane, like any gold asset).
  INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                                 resource_iri_pattern, time_column, published)
  VALUES ('/gold/intervention_anomaly_daily/', '/gold/intervention_anomaly_daily/',
          'gold', 'intervention_anomaly_daily',
          '/gold/intervention_anomaly_daily/<building_id>/<day>', 'day', true)
  ON CONFLICT (asset_uri) DO UPDATE SET published = true;

  -- --- Reader rights (data plane + LDP node) ---------------------------------
  EXECUTE 'GRANT SELECT ON gold.intervention_anomaly_daily TO reader';
  EXECUTE 'GRANT SELECT ON gold.intervention_anomaly_daily TO app';

  -- --- pg_cron refresh: right after the core gold_refresh() (10 min) ---------
  IF to_regclass('cron.job') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fap-app-gold-refresh-interventions') THEN
      PERFORM cron.schedule('fap-app-gold-refresh-interventions', '*/10 * * * *',
        'SELECT public.gold_refresh(); REFRESH MATERIALIZED VIEW gold.intervention_anomaly_daily;');
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron missing — refresh of gold.intervention_anomaly_daily to schedule after the 1st boot';
  END IF;
END $$;
