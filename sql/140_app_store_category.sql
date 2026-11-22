-- ============================================================================
-- App store — category (shelf) of the catalog features (organization of
-- <app-store> into sections + filters). Copy of app-store/sql/021_features_category.sql.
-- Idempotent (ADD COLUMN IF NOT EXISTS + backfill on NULL), replayed at boot.
-- ============================================================================

ALTER TABLE app.features ADD COLUMN IF NOT EXISTS category text;

UPDATE app.features SET category = 'supervision'
  WHERE category IS NULL AND slug IN
  ('dashboard', 'building-detail', 'anomalies', 'alert-rules', 'sla-dashboard', 'weather-correlation');

UPDATE app.features SET category = 'operations'
  WHERE category IS NULL AND slug IN
  ('tickets', 'interventions', 'city-events');

UPDATE app.features SET category = 'energy'
  WHERE category IS NULL AND slug IN
  ('pv-selfconsumption', 'price-optimizer', 'budget-tracker', 'benchmark');

UPDATE app.features SET category = 'compliance'
  WHERE category IS NULL AND slug IN
  ('report-builder', 'regulatory-export', 'data-sharing');

UPDATE app.features SET category = 'tools'
  WHERE category IS NULL AND slug IN
  ('ai-assistant', 'demo_weather', 'admin', 'store');

CREATE INDEX IF NOT EXISTS features_category_idx ON app.features (category);
