-- ============================================================================
-- 103_app_event_bronze.sql — retour vers la FAP des événements applicatifs (RG-3)
--
-- Le trigger app.outbox_trigger (posé par le nœud fap-ldp) écrit chaque
-- INSERT/UPDATE de app.* dans app.outbox ; le flow ORCE 'app-supervision'
-- (flows/app-supervision.json) consomme l'outbox et appelle
-- public.gate_ingest('app.event', payload, ...) avec le rôle gate.
-- Il faut donc : (1) la table bronze d'atterrissage, (2) l'entrée gate_type_map.
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
