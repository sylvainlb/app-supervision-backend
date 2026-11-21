#!/usr/bin/env bash
# assemble-flows.sh — concatène les flows ORCE du déploiement supervision :
#   cœur FAP-light + fragment fap-ldp + fragment ext model-injection (E11, v2 app store)
#   + fragment app-supervision (ici)
# → .build/flows/flows.json (monté dans ORCE, voir compose/docker-compose.yml).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIR="${CORE_DIR:-$HERE/../fap-light-serveur}"
LDP_DIR="${LDP_DIR:-$HERE/../fap-ldp}"
OUT="${1:-$HERE/.build/flows.json}"

CORE_FLOWS="$CORE_DIR/deploy/orce/data/flows.json"
[ -f "$CORE_FLOWS" ] || CORE_FLOWS="$CORE_DIR/core/flows/flows.json"   # cœur FACIS officiel
[ -f "$CORE_FLOWS" ] || { echo "ERREUR: flows cœur introuvables (CORE_DIR=$CORE_DIR)" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
MI_FLOWS="$LDP_DIR/ext/model-injection/compose/flows/model-injection.json"
[ -f "$MI_FLOWS" ] || { echo "ERREUR: fragment model-injection introuvable ($MI_FLOWS)" >&2; exit 1; }
python3 - "$CORE_FLOWS" "$LDP_DIR/compose/flows/fap-ldp.json" "$MI_FLOWS" "$HERE/flows/app-supervision.json" "$OUT" <<'PYEOF'
import json, sys
flows = []
for path in sys.argv[1:5]:
    with open(path) as f:
        flows.extend(json.load(f))
with open(sys.argv[5], 'w') as f:
    json.dump(flows, f, indent=1, ensure_ascii=False)
print(f"flows.json assemblé: {sys.argv[5]} ({len(flows)} nœuds = cœur + fap-ldp + model-injection + app-supervision)")
PYEOF
