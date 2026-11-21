
## NOTE — model.json et app store

`app.features` / `app.prefs` (app store) ne sont PAS dans `model.json` : le socle
(`app.version_trigger`/`outbox_trigger`) suppose une colonne `id`, et l'app store est un
package à part, appliqué par ses propres SQL custom (`sql/105–110_app_store_*.sql`, rejoués
par `deploy-local.sh`), avec `resource_iri_pattern` custom (`/features/<slug>`, `/prefs/<user_id>`).
(Note déplacée ici depuis model.json — le JSON n'accepte pas les commentaires `--`.)
