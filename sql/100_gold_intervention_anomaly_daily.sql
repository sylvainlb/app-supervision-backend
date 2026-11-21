-- ============================================================================
-- 100_gold_intervention_anomaly_daily.sql — vue agrégée publiée (spec fonc. F7, RG-5, CA-4)
--
-- Matview gold `intervention_anomaly_daily` = jointure `gold.anomaly_candidates`
-- × `app.tickets` : nombre d'anomalies, de tickets, délai moyen de résolution,
-- par bâtiment et par jour. Seules les vues agrégées gold sont publiées dans le
-- data space (RG-5) : jamais les tables brutes de app.*.
--
-- ⚠️ Ce fichier est défensif (to_regclass) : les tables app.* sont créées AU BOOT
-- par le nœud fap-ldp depuis config/model.json, donc potentiellement APRÈS les
-- migrations initdb. Sur un déploiement from-scratch, le rejouer après le 1er
-- boot :
--   docker compose -f ../fap-ldp/compose/docker-compose.yml --env-file .env \
--     exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/<NN>_custom_100_gold_intervention_anomaly_daily.sql
-- (ou directement : psql "postgres://postgres@localhost/fap" -f sql/100_gold_intervention_anomaly_daily.sql)
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('app.tickets') IS NULL OR to_regclass('app.buildings') IS NULL
     OR to_regclass('gold.anomaly_candidates') IS NULL THEN
    RAISE NOTICE 'app.* ou gold.anomaly_candidates absent — 100_gold_intervention_anomaly_daily.sql à rejouer après le 1er boot';
    RETURN;
  END IF;

  -- --- Matview agrégée (F7) -------------------------------------------------
  -- Lien anomalie ↔ bâtiment via app.buildings.meter_id = anomaly_candidates.meter_id.
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

  -- --- Publication : asset DSP + conteneur LDP (CA-4, CA-L2) -----------------
  -- Le catalogue DSP cœur s'auto-dérive d'information_schema (schéma gold publiable) ;
  -- ici on enregistre le mapping LDP et on marque publié (contrat + policySummary + HMAC
  -- servis par le plan de contrôle cœur, comme tout asset gold).
  INSERT INTO dsp.asset_mapping (asset_uri, container_uri, table_schema, table_name,
                                 resource_iri_pattern, time_column, published)
  VALUES ('/gold/intervention_anomaly_daily/', '/gold/intervention_anomaly_daily/',
          'gold', 'intervention_anomaly_daily',
          '/gold/intervention_anomaly_daily/<building_id>/<day>', 'day', true)
  ON CONFLICT (asset_uri) DO UPDATE SET published = true;

  -- --- Droits reader (data plane + nœud LDP) ---------------------------------
  EXECUTE 'GRANT SELECT ON gold.intervention_anomaly_daily TO reader';
  EXECUTE 'GRANT SELECT ON gold.intervention_anomaly_daily TO app';

  -- --- Refresh pg_cron : juste après le gold_refresh() du cœur (10 min) ------
  IF to_regclass('cron.job') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fap-app-gold-refresh-interventions') THEN
      PERFORM cron.schedule('fap-app-gold-refresh-interventions', '*/10 * * * *',
        'SELECT public.gold_refresh(); REFRESH MATERIALIZED VIEW gold.intervention_anomaly_daily;');
    END IF;
  ELSE
    RAISE NOTICE 'pg_cron absent — refresh de gold.intervention_anomaly_daily à planifier après le 1er boot';
  END IF;
END $$;
