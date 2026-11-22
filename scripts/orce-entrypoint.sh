#!/bin/sh
# orce-entrypoint.sh — ORCE entrypoint of the energy-supervision deployment:
# copies the assembled flows (core + fap-ldp + app-supervision) to /data/flows.json
# (flowFile of the settings.js baked into the image), then delegates to the FAP-light entrypoint.
set -Eeuo pipefail
cp /flows-app/flows.json /data/flows.json
cp /flows-app/orce-settings.js /data/settings.js   # httpAdminRoot '/editor' (outside the LDP middleware)
exec /usr/local/bin/entrypoint-light.sh "$@"
