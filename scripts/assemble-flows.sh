#!/usr/bin/env bash
# assemble-flows.sh — concatenates the ORCE flows of the supervision deployment:
#   FAP-light core + fap-ldp fragment + model-injection ext fragment (E11, v2 app store)
#   + app-supervision fragment (here)
# → .build/flows/flows.json (mounted into ORCE, see compose/docker-compose.yml).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="${CORE_DIR:-$HERE/../fap-light-serveur}"
LDP_DIR="${LDP_DIR:-$HERE/../fap-ldp}"
OUT="${1:-$HERE/.build/flows.json}"

CORE_FLOWS="$CORE_DIR/deploy/orce/data/flows.json"
[ -f "$CORE_FLOWS" ] || CORE_FLOWS="$CORE_DIR/core/flows/flows.json"   # official FACIS core
[ -f "$CORE_FLOWS" ] || { echo "ERROR: core flows not found (CORE_DIR=$CORE_DIR)" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
MI_FLOWS="$LDP_DIR/ext/model-injection/compose/flows/model-injection.json"
[ -f "$MI_FLOWS" ] || { echo "ERROR: model-injection fragment not found ($MI_FLOWS)" >&2; exit 1; }
python3 - "$CORE_FLOWS" "$LDP_DIR/compose/flows/fap-ldp.json" "$MI_FLOWS" "$HERE/flows/app-supervision.json" "$OUT" <<'PYEOF'
import json, sys
flows = []
for path in sys.argv[1:5]:
    with open(path) as f:
        flows.extend(json.load(f))
with open(sys.argv[5], 'w') as f:
    json.dump(flows, f, indent=1, ensure_ascii=False)
print(f"flows.json assembled: {sys.argv[5]} ({len(flows)} nodes = core + fap-ldp + model-injection + app-supervision)")
PYEOF
