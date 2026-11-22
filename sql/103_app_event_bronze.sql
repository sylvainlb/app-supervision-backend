-- ============================================================================
-- 103_app_event_bronze.sql — feeding application events back to the FAP (RG-3)
--
-- The app.outbox_trigger trigger (set by the fap-ldp node) writes every
-- INSERT/UPDATE of app.* into app.outbox ; the ORCE flow 'app-supervision'
-- (flows/app-supervision.json) consumes the outbox and calls
-- public.gate_ingest('app.event', payload, ...) with the gate role.
-- Hence we need: (1) the bronze landing table, (2) the gate_type_map entry.
-- ============================================================================

CREATE TABLE IF NOT EXISTS bronze.app_event (
  id               bigserial PRIMARY KEY,
  raw_payload      jsonb NOT NULL,
  source_topic     text NOT NULL,
  source_system    text NOT NULL,
  ingest_timestamp timestamptz NOT NULL DEFAULT now(),
  message_key      text,
  source_seq       uuid NOT NULL DEFAULT gen_random_uuid()
);

INSERT INTO public.gate_type_map (envelope_type, bronze_table, required_fields, numeric_fields)
VALUES ('app.event', 'app_event', ARRAY['id'], ARRAY[]::text[])
ON CONFLICT (envelope_type) DO NOTHING;

GRANT INSERT ON bronze.app_event TO gate;
GRANT USAGE, SELECT ON SEQUENCE bronze.app_event_id_seq TO gate;
