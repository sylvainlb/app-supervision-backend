-- ============================================================================
-- 105_app_store_seed.sql — seed du catalogue app.features (app-store-spec §1.3 :
--   canal = SQL initdb de l'app, PAS model.json — model-injection-spec §1.4).
--
-- Contenu : spec/app-store-catalogue.md v0.3 §1 (5 features de base + store + admin),
-- routes alignées sur orbit.json de l'app (check CI seed ↔ orbit.json, §1.9.8).
-- Idempotent : ON CONFLICT (slug) DO NOTHING. Le trigger on_feature_insert_app_store
-- injecte la clé par défaut dans les prefs existantes (§1.9.4b).
-- ============================================================================

INSERT INTO app.features (slug, title_i18n, description_i18n, icon, menu_order, role_min,
                           component, route, config_schema, default_enabled, in_menu, tag) VALUES
('dashboard', '{"en": "Dashboard"}', '{"en": "Site map and energy overview."}', 'map', 0, 'gestionnaire', 'building-map', '/', '{"fields": []}', true, true, 'building-map'),
('anomalies', '{"en": "Anomalies"}', '{"en": "Anomalies detected by the FAP."}', 'warning', 1, 'gestionnaire', 'anomaly-list', '/anomalies', '{"fields": []}', true, true, 'anomaly-list'),
('tickets', '{"en": "Tickets"}', '{"en": "Interventions and their tracking (manager)."}', 'confirmation_number', 2, 'gestionnaire', 'ticket-board', '/tickets', '{"fields": []}', true, true, 'ticket-board'),
('interventions', '{"en": "My interventions"}', '{"en": "Assigned tickets (technician)."}', 'assignment', 3, 'technicien', 'ticket-board', '/interventions', '{"fields": []}', true, true, 'ticket-board'),
('building-detail', '{"en": "Building detail"}', '{"en": "Consumption/PV curves for one building."}', 'insights', 4, 'gestionnaire', 'energy-chart', '/buildings/:id', '{"fields": []}', true, true, 'energy-chart'),
('store', '{"en": "App store"}', '{"en": "Enable / configure features."}', 'storefront', 8, 'all', 'app-store', '/store', '{"fields": []}', true, false, 'app-store'),
('admin', '{"en": "Administration"}', '{"en": "Users, roles, catalogue."}', 'admin_panel_settings', 9, 'admin', 'user-admin', '/admin', '{"fields": []}', true, true, 'user-admin')
ON CONFLICT (slug) DO NOTHING;
