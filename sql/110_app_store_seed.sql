-- ============================================================================
-- 105_app_store_seed.sql — seed of the app.features catalog (app-store-spec §1.3 :
--   channel = app initdb SQL, NOT model.json — model-injection-spec §1.4).
--
-- Content: spec/app-store-catalogue.md v0.3 §1 (5 base features + store + admin),
-- routes aligned with the app's orbit.json (CI check seed ↔ orbit.json, §1.9.8).
-- Idempotent: ON CONFLICT (slug) DO NOTHING. The on_feature_insert_app_store trigger
-- injects the default key into existing prefs (§1.9.4b).
-- ============================================================================

INSERT INTO app.features (slug, title_i18n, description_i18n, icon, menu_order, role_min,
                           component, route, config_schema, default_enabled, in_menu, tag) VALUES
('dashboard', '{"en": "Dashboard", "fr": "Tableau de bord"}', '{"en": "Site map and energy overview.", "fr": "Carte du site et vue d'ensemble énergétique."}', 'map', 0, 'gestionnaire', 'building-map', '/', '{"fields": []}', true, true, 'building-map'),
('anomalies', '{"en": "Anomalies", "fr": "Anomalies"}', '{"en": "Anomalies detected by the FAP.", "fr": "Anomalies détectées par la FAP."}', 'warning', 1, 'gestionnaire', 'anomaly-list', '/anomalies', '{"fields": []}', true, true, 'anomaly-list'),
('tickets', '{"en": "Tickets", "fr": "Tickets"}', '{"en": "Interventions and their tracking (manager).", "fr": "Interventions et leur suivi (gestionnaire)."}', 'confirmation_number', 2, 'gestionnaire', 'ticket-board', '/tickets', '{"fields": []}', true, true, 'ticket-board'),
('interventions', '{"en": "My interventions", "fr": "Mes interventions"}', '{"en": "Assigned tickets (technician).", "fr": "Tickets assignés (technicien)."}', 'assignment', 3, 'technicien', 'ticket-board', '/interventions', '{"fields": []}', true, true, 'ticket-board'),
('building-detail', '{"en": "Building detail", "fr": "Détail du bâtiment"}', '{"en": "Consumption/PV curves for one building.", "fr": "Courbes de consommation/PV d'un bâtiment."}', 'insights', 4, 'gestionnaire', 'energy-chart', '/buildings/:id', '{"fields": []}', true, true, 'energy-chart'),
('store', '{"en": "App store", "fr": "Boutique d'applications"}', '{"en": "Enable / configure features.", "fr": "Activer / configurer les fonctionnalités."}', 'storefront', 8, 'all', 'app-store', '/store', '{"fields": []}', true, false, 'app-store'),
('admin', '{"en": "Administration", "fr": "Administration"}', '{"en": "Users, roles, catalogue.", "fr": "Utilisateurs, rôles, catalogue."}', 'admin_panel_settings', 9, 'admin', 'user-admin', '/admin', '{"fields": []}', true, true, 'user-admin')
ON CONFLICT (slug) DO NOTHING;
