-- ============================================================================
-- 101_seed_demo.sql — demo fleet (buildings) and test application accounts
--
-- ⚠️ Defensive: app.* is created at boot by the fap-ldp node (config/model.json).
-- On a from-scratch deployment, replay AFTER the 1st boot (see README of
-- 100_gold_intervention_anomaly_daily.sql for the command).
--
-- The users' webid must match the `webid` claim issued by Keycloak
-- (keycloak/realm.json : https://${DOMAIN}/users/<pk>). Edit POD_BASE below
-- according to DOMAIN in .env.
-- ============================================================================

-- The base IRI is passed as a psql variable by deploy-local.sh (-v base_iri="$BASE_IRI")
-- (https://api.localhost/ in custom dev, http://localhost/ in localhost dev, …).
-- psql does NOT substitute :'base_iri' inside dollar-quoted blocks (DO $$…$$):
-- it is passed via a session setting, read via current_setting() in the block.
SELECT set_config('app.pod_base', :'base_iri', false);
DO $$
DECLARE
  pod_base text := current_setting('app.pod_base', true);
BEGIN
  IF to_regclass('app.buildings') IS NULL OR to_regclass('app.users') IS NULL THEN
    RAISE NOTICE 'app.* missing — 101_seed_demo.sql to replay after the 1st boot';
    RETURN;
  END IF;

  -- --- Application accounts (webid = Keycloak claim, fap-ldp spec §7.6 H) ----
  -- upsert on email: the webid changes when moving from dev (http) to staging/prod (https)
  INSERT INTO app.users (webid, name, email, role) VALUES
    (pod_base || 'users/1', 'Alice Manager', 'alice@' || regexp_replace(pod_base, '^https?://|/$', ''), 'manager'),
    (pod_base || 'users/2', 'Bob Technician',   'bob@'   || regexp_replace(pod_base, '^https?://|/$', ''), 'technician'),
    (pod_base || 'users/3', 'Fleet Admin',       'admin@' || regexp_replace(pod_base, '^https?://|/$', ''), 'admin')
  ON CONFLICT (email) DO UPDATE SET webid = EXCLUDED.webid, name = EXCLUDED.name, role = EXCLUDED.role;

  -- --- Demo fleet: meter_id = join key with gold.anomaly_candidates ----------
  -- facis_asset = IRI of the meter's DSP catalog asset (filled in at deployment).
  -- Idempotent: delete comments → tickets → buildings first (manual cascade
  -- FK), otherwise the buildings DELETE fails on the 2nd run.
  DELETE FROM app.comments WHERE ticket_id IN
    (SELECT id FROM app.tickets WHERE building_id IN
      (SELECT id FROM app.buildings WHERE meter_id IN ('meter-site-berlin-001-01','meter-site-berlin-001-02','meter-site-berlin-001-03')));
  DELETE FROM app.tickets WHERE building_id IN
    (SELECT id FROM app.buildings WHERE meter_id IN ('meter-site-berlin-001-01','meter-site-berlin-001-02','meter-site-berlin-001-03'));
  DELETE FROM app.buildings WHERE meter_id IN ('meter-site-berlin-001-01','meter-site-berlin-001-02','meter-site-berlin-001-03');
  INSERT INTO app.buildings (name, address, meter_id, facis_asset, lat, lon) VALUES
    ('HQ — Hall A',  '1 Sensor Street, Berlin', 'meter-site-berlin-001-01', NULL, 52.5200, 13.4050),
    ('HQ — Hall B',  '1 Sensor Street, Berlin', 'meter-site-berlin-001-02', NULL, 52.5205, 13.4062),
    ('North Warehouse',   '12 Energy Quay, Berlin', 'meter-site-berlin-001-03', NULL, 52.5310, 13.4210);
END $$;

-- ============================================================================
-- Demo fixture extension (idempotent): tickets at all statuses + comments.
-- ============================================================================
DO $$
DECLARE
  b1 bigint; b2 bigint; u1 bigint; u2 bigint;
BEGIN
  IF to_regclass('app.tickets') IS NULL THEN RETURN; END IF;
  SELECT id INTO b1 FROM app.buildings WHERE meter_id = 'meter-site-berlin-001-01' LIMIT 1;
  SELECT id INTO b2 FROM app.buildings WHERE meter_id = 'meter-site-berlin-001-03' LIMIT 1;
  SELECT id INTO u1 FROM app.users WHERE role = 'manager' LIMIT 1;
  SELECT id INTO u2 FROM app.users WHERE role = 'technician' LIMIT 1;

  INSERT INTO app.tickets (title, description, status, priority, building_id, anomaly_ref, created_by, assigned_to)
  SELECT * FROM (VALUES
    ('Consumption spike North Warehouse', 'Spike on meter-site-berlin-001-03 detected by the materializer.', 'IN_PROGRESS', 'HIGH', b2, NULL, u1, u2),
    ('Slow drift Hall B', 'z-score drift > 3 on meter-site-berlin-001-02.', 'RESOLVED', 'MEDIUM', b1, NULL, u1, u2),
    ('Minor anomaly Hall A', 'Monitoring, anomaly resolved.', 'CLOSED', 'LOW', b1, NULL, u1, NULL)
  ) AS v(title, description, status, priority, building_id, anomaly_ref, created_by, assigned_to)
  WHERE NOT EXISTS (SELECT 1 FROM app.tickets t WHERE t.title = v.title);

  INSERT INTO app.comments (ticket_id, author, text, ts)
  SELECT t.id, u2, 'Intervention started, readings in progress.', now() - interval '30 min'
  FROM app.tickets t CROSS JOIN app.users u
  WHERE t.status = 'IN_PROGRESS' AND u.role = 'technician'
    AND NOT EXISTS (SELECT 1 FROM app.comments c WHERE c.ticket_id = t.id)
  LIMIT 1;
END $$;
