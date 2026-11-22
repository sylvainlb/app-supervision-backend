
## NOTE — model.json and app store

`app.features` / `app.prefs` (app store) are NOT in `model.json`: the base layer
(`app.version_trigger`/`outbox_trigger`) assumes an `id` column, and the app store is a separate
package, applied by its own custom SQL (`sql/105–110_app_store_*.sql`, replayed
by `deploy-local.sh`), with a custom `resource_iri_pattern` (`/features/<slug>`, `/prefs/<user_id>`).
(Note moved here from model.json — JSON does not accept `--` comments.)
