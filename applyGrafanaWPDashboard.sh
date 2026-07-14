#!/usr/bin/env bash
set -uo pipefail

GRAFANA_URL="http://monitoring.vn.internal:3000"
GRAFANA_TOKEN_FILE=".creds_grafana"
DASHBOARD_UID="a6b5988c-22f1-475f-856e-ab3e803df8e6"
TMP_IN="/tmp/gf_dashboard_in.json"
TMP_OUT="/tmp/gf_dashboard_out.json"

if [[ ! -f "${GRAFANA_TOKEN_FILE}" ]]; then
  echo "FEHLER: ${GRAFANA_TOKEN_FILE} fehlt"
  exit 1
fi

GRAFANA_TOKEN="$(tr -d '\r\n' < "${GRAFANA_TOKEN_FILE}")"
if [[ -z "${GRAFANA_TOKEN}" ]]; then
  echo "FEHLER: ${GRAFANA_TOKEN_FILE} ist leer"
  exit 1
fi

echo "--- Lade aktuelles Dashboard-JSON ..."
curl -sf \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  "${GRAFANA_URL}/api/dashboards/uid/${DASHBOARD_UID}" \
  -o "${TMP_IN}"

python3 -c "import json; d=json.load(open('${TMP_IN}')); print('    Aktuelle Version:', d['dashboard']['version'])"

echo "--- Patche Dashboard (Queries C+D, WARNING-Mapping, noValue) ..."
python3 /usr/local/lib/vnit/gf_patch_wp_dashboard.py "${TMP_IN}" "${TMP_OUT}"

python3 -c "import json; d=json.load(open('${TMP_OUT}')); print('    Neue Version:', d['dashboard']['version'])"

echo "--- Schreibe Dashboard zurück ..."
RESULT=$(curl -sf \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "${GRAFANA_URL}/api/dashboards/db" \
  -d @"${TMP_OUT}")

STATUS=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','?'))")
SAVED_VERSION=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version','?'))")

if [[ "$STATUS" == "success" ]]; then
  echo "OK — Dashboard aktualisiert (Version ${SAVED_VERSION})"
  echo "    ${GRAFANA_URL}/d/${DASHBOARD_UID}/online"
else
  echo "FEHLER: ${RESULT}"
  exit 1
fi
