-- ============================================================================
-- 105_cr2_area_m2.sql — CR-2 (app-store-catalogue spec §2): `area_m2` DDL
--   (number, nullable) on app.buildings, in addition to lat/lon (WGS84, CR
--   front spec §13.4 already delivered). Used by `benchmark` (kwh_m2 / eur_m2).
--
-- The fap-ldp boot (config/model.json) only does CREATE TABLE IF NOT EXISTS:
-- on an existing DB the column is not added → this file migrates it.
-- Idempotent, replayed post-boot by deploy-local.sh.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('app.buildings') IS NULL THEN
    RAISE NOTICE 'app.buildings missing — 105_cr2_area_m2.sql to replay after the 1st boot';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='app' AND table_name='buildings' AND column_name='area_m2') THEN
    ALTER TABLE app.buildings ADD COLUMN area_m2 double precision;
    RAISE NOTICE 'CR-2: column app.buildings.area_m2 added';
  END IF;
END $$;
