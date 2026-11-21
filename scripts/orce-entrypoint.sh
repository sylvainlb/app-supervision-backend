#!/bin/sh
# orce-entrypoint.sh — entrypoint ORCE du déploiement energy-supervision :
# copie les flows assemblés (cœur + fap-ldp + app-supervision) sur /data/flows.json
# (flowFile du settings.js bakiné dans l'image), puis délègue à l'entrypoint FAP-light.
set -Eeuo pipefail
cp /flows-app/flows.json /data/flows.json
cp /flows-app/orce-settings.js /data/settings.js   # httpAdminRoot '/editor' (hors middleware LDP)
exec /usr/local/bin/entrypoint-light.sh "$@"
