-- ============================================================================
-- App store — v2 (Partie 2) : colonnes v2 sur app.features (chargement à chaud)
-- Copie de app-store/sql/020_features_v2.sql (source : app-store/spec).
-- Idempotent (ADD COLUMN IF NOT EXISTS, DROP/ADD CONSTRAINT), rejoué au boot.
-- NE S'APPLIQUE QU'EN V2 : la Partie 1 (v1) reste inchangée (L3, CA-B6).
-- ============================================================================

  ADD COLUMN IF NOT EXISTS cdn_url     text,     -- jsDelivr
  ADD COLUMN IF NOT EXISTS sri         text,     -- SHA-384 du binaire
  ADD COLUMN IF NOT EXISTS tag         text,     -- tag du custom element distant
  ADD COLUMN IF NOT EXISTS model_injected boolean NOT NULL DEFAULT false;  -- modèle injecté via E11 (L3)

-- v2 : chaque entrée de prefs peut porter la version réellement chargée
-- (stockée dans le jsonb prefs, pas de colonne dédiée — §2.1 :
-- installed_version / installed_sri dans prefs.<slug>).

-- v2 : les packages installés via E11 (POST /admin/apps) ont un slug en
-- ^[a-z][a-z0-9_]{1,30}$ (underscore, spec model-injection §4.2) et sont upsertés
-- dans app.features → la grammaire des slugs du catalogue accepte désormais aussi
-- '_' (les slugs v1 en '-' restent valides ; l'intersection reste non vide).
ALTER TABLE app.features DROP CONSTRAINT IF EXISTS features_slug_check;
ALTER TABLE app.features ADD CONSTRAINT features_slug_check CHECK (slug ~ '^[a-z][a-z0-9_-]{1,62}$');
