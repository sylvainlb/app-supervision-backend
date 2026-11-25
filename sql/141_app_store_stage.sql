-- ============================================================================
-- App store — v0.5 two-stage discriminant (chantier 3, ratified J8).
-- Copie de app-store/sql/022_features_stage.sql (source : app-store/spec).
-- Idempotent (ADD COLUMN IF NOT EXISTS), rejoué au boot.
-- Additif uniquement : les lignes existantes gardent stage='code' (CA-A8).
-- ============================================================================

ALTER TABLE app.features ADD COLUMN IF NOT EXISTS stage text NOT NULL DEFAULT 'code'
  CHECK (stage IN ('code', 'declarative'));

ALTER TABLE app.features ADD COLUMN IF NOT EXISTS document_iri text NULL;

CREATE INDEX IF NOT EXISTS features_stage_idx ON app.features (stage);

COMMENT ON COLUMN app.features.stage IS 'two-stage store discriminant: code (SRI bundle) | declarative (JSON-LD document)';
COMMENT ON COLUMN app.features.document_iri IS 'declarative stage: versioned component document IRI; NULL on code stage';
