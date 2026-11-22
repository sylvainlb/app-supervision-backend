-- ============================================================================
-- App store — v2 (Part 2): v2 columns on app.features (hot reload)
-- Copy of app-store/sql/020_features_v2.sql (source: app-store/spec).
-- Idempotent (ADD COLUMN IF NOT EXISTS, DROP/ADD CONSTRAINT), replayed at boot.
-- APPLIES TO V2 ONLY: Part 1 (v1) remains unchanged (L3, CA-B6).
-- ============================================================================

  ADD COLUMN IF NOT EXISTS cdn_url     text,     -- jsDelivr
  ADD COLUMN IF NOT EXISTS sri         text,     -- SHA-384 du binaire
  ADD COLUMN IF NOT EXISTS tag         text,     -- tag du custom element distant
  ADD COLUMN IF NOT EXISTS model_injected boolean NOT NULL DEFAULT false;  -- model injected via E11 (L3)

-- v2: each prefs entry can carry the actually loaded version
-- (stored in the prefs jsonb, no dedicated column — §2.1 :
-- installed_version / installed_sri in prefs.<slug>).

-- v2: packages installed via E11 (POST /admin/apps) have a slug matching
-- ^[a-z][a-z0-9_]{1,30}$ (underscore, model-injection spec §4.2) and are upserted
-- into app.features → the catalog slug grammar now also accepts
-- '_' (v1 '-' slugs remain valid; the intersection stays non-empty).
ALTER TABLE app.features DROP CONSTRAINT IF EXISTS features_slug_check;
ALTER TABLE app.features ADD CONSTRAINT features_slug_check CHECK (slug ~ '^[a-z][a-z0-9_-]{1,62}$');
