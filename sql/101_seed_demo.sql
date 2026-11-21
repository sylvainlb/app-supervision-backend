-- ============================================================================
-- 101_seed_demo.sql — parc de démo (bâtiments) et comptes applicatifs de test
--
-- ⚠️ Défensif : app.* est créé au boot par le nœud fap-ldp (config/model.json).
-- Sur un déploiement from-scratch, rejouer APRÈS le 1er boot (voir README de
-- 100_gold_intervention_anomaly_daily.sql pour la commande).
--
-- Le webid des users doit correspondre au claim `webid` émis par Keycloak
-- (keycloak/realm.json : https://${DOMAIN}/users/<pk>). Éditer POD_BASE ci-dessous
-- selon DOMAIN dans .env.
-- ============================================================================

-- La base IRI est passée en variable psql par deploy-local.sh (-v base_iri="$BASE_IRI")
-- (https://api.localhost/ en dev custom, http://localhost/ en dev localhost, …).
-- psql ne substitue PAS :'base_iri' à l'intérieur des blocs dollar-quoted (DO $$…$$) :
-- on la passe par un setting de session, lu via current_setting() dans le bloc.
SELECT set_config('app.pod_base', :'base_iri', false);
DO $$
DECLARE
  pod_base text := current_setting('app.pod_base', true);
BEGIN
  IF to_regclass('app.buildings') IS NULL OR to_regclass('app.users') IS NULL THEN
    RAISE NOTICE 'app.* absent — 101_seed_demo.sql à rejouer après le 1er boot';
    RETURN;
  END IF;

  -- --- Comptes applicatifs (webid = claim Keycloak, spec fap-ldp §7.6 H) ------
  -- upsert sur email : le webid change si on passe de dev (http) à staging/prod (https)
  INSERT INTO app.users (webid, name, email, role) VALUES
    (pod_base || 'users/1', 'Alice Gestionnaire', 'alice@' || regexp_replace(pod_base, '^https?://|/$', ''), 'gestionnaire'),
    (pod_base || 'users/2', 'Bob Technicien',   'bob@'   || regexp_replace(pod_base, '^https?://|/$', ''), 'technicien'),
    (pod_base || 'users/3', 'Admin Parc',       'admin@' || regexp_replace(pod_base, '^https?://|/$', ''), 'admin')
  ON CONFLICT (email) DO UPDATE SET webid = EXCLUDED.webid, name = EXCLUDED.name, role = EXCLUDED.role;

  -- --- Parc de démo : meter_id = clé de jointure avec gold.anomaly_candidates --
  -- facis_asset = IRI de l'asset catalogue DSP du compteur (renseigné au déploiement).
  -- Idempotent : on supprime d'abord comments → tickets → buildings (FK en cascade
  -- manuelle), sinon le DELETE buildings échoue au 2e rejeu.
  DELETE FROM app.comments WHERE ticket_id IN
    (SELECT id FROM app.tickets WHERE building_id IN
      (SELECT id FROM app.buildings WHERE meter_id IN ('meter-site-berlin-001-01','meter-site-berlin-001-02','meter-site-berlin-001-03')));
  DELETE FROM app.tickets WHERE building_id IN
    (SELECT id FROM app.buildings WHERE meter_id IN ('meter-site-berlin-001-01','meter-site-berlin-001-02','meter-site-berlin-001-03'));
  DELETE FROM app.buildings WHERE meter_id IN ('meter-site-berlin-001-01','meter-site-berlin-001-02','meter-site-berlin-001-03');
  INSERT INTO app.buildings (name, address, meter_id, facis_asset, lat, lon) VALUES
    ('Siège — Hall A',  '1 rue des Capteurs, Berlin', 'meter-site-berlin-001-01', NULL, 52.5200, 13.4050),
    ('Siège — Hall B',  '1 rue des Capteurs, Berlin', 'meter-site-berlin-001-02', NULL, 52.5205, 13.4062),
    ('Entrepôt Nord',   '12 quai de l''Énergie, Berlin', 'meter-site-berlin-001-03', NULL, 52.5310, 13.4210);
END $$;

-- ============================================================================
-- Extension fixture démo (idempotente) : tickets à tous les statuts + commentaires.
-- ============================================================================
DO $$
DECLARE
  b1 bigint; b2 bigint; u1 bigint; u2 bigint;
BEGIN
  IF to_regclass('app.tickets') IS NULL THEN RETURN; END IF;
  SELECT id INTO b1 FROM app.buildings WHERE meter_id = 'meter-site-berlin-001-01' LIMIT 1;
  SELECT id INTO b2 FROM app.buildings WHERE meter_id = 'meter-site-berlin-001-03' LIMIT 1;
  SELECT id INTO u1 FROM app.users WHERE role = 'gestionnaire' LIMIT 1;
  SELECT id INTO u2 FROM app.users WHERE role = 'technicien' LIMIT 1;

  INSERT INTO app.tickets (title, description, status, priority, building_id, anomaly_ref, created_by, assigned_to)
  SELECT * FROM (VALUES
    ('Pic de conso Entrepôt Nord', 'Spike sur meter-site-berlin-001-03 détecté par le materializer.', 'IN_PROGRESS', 'HIGH', b2, NULL, u1, u2),
    ('Dérive lente Hall B', 'Dérive z-score > 3 sur meter-site-berlin-001-02.', 'RESOLVED', 'MEDIUM', b1, NULL, u1, u2),
    ('Anomalie faible Hall A', 'Surveillance, anomalie résolue.', 'CLOSED', 'LOW', b1, NULL, u1, NULL)
  ) AS v(title, description, status, priority, building_id, anomaly_ref, created_by, assigned_to)
  WHERE NOT EXISTS (SELECT 1 FROM app.tickets t WHERE t.title = v.title);

  INSERT INTO app.comments (ticket_id, author, text, ts)
  SELECT t.id, u2, 'Intervention lancée, relevés en cours.', now() - interval '30 min'
  FROM app.tickets t CROSS JOIN app.users u
  WHERE t.status = 'IN_PROGRESS' AND u.role = 'technicien'
    AND NOT EXISTS (SELECT 1 FROM app.comments c WHERE c.ticket_id = t.id)
  LIMIT 1;
END $$;
