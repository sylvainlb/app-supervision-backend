-- ============================================================================
-- 105_cr2_area_m2.sql — CR-2 (spec app-store-catalogue §2) : DDL `area_m2`
--   (number, nullable) sur app.buildings, en complément de lat/lon (WGS84, CR
--   spec front §13.4 déjà livré). Utilisé par `benchmark` (kwh_m2 / eur_m2).
--
-- Le boot fap-ldp (config/model.json) ne fait que CREATE TABLE IF NOT EXISTS :
-- sur une DB existante la colonne n'est pas ajoutée → ce fichier la migre.
-- Idempotent, rejoué post-boot par deploy-local.sh.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('app.buildings') IS NULL THEN
    RAISE NOTICE 'app.buildings absent — 105_cr2_area_m2.sql à rejouer après le 1er boot';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='app' AND table_name='buildings' AND column_name='area_m2') THEN
    ALTER TABLE app.buildings ADD COLUMN area_m2 double precision;
    RAISE NOTICE 'CR-2: colonne app.buildings.area_m2 ajoutée';
  END IF;
END $$;
