#!/usr/bin/env bash
# applyWPHttpChecks.sh
# Legt CheckCommand "wp-exposure" und den Service Apply Rule "WP Security Exposure"
# im Icinga Director an und deployt die Konfiguration.
#
# Das Plugin /usr/lib/nagios/plugins/custom/check_wp_exposure muss auf VN-ICINGA-EX
# bereits vorhanden und ausführbar sein.
#
# Idempotent: POST schlägt fehl wenn Objekt existiert (200-Response prüfen),
# PUT/PATCH für Updates verwenden falls nötig.

set -uo pipefail

DIRECTOR="http://monitoring.vn.internal:8080/director"
AUTH="icingaadmin:vnit"
SATELLITE="vn-icinga-ex"
PLUGIN="/usr/lib/nagios/plugins/custom/check_wp_exposure"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

director_post() {
  local endpoint="$1"
  local payload="$2"
  local name="$3"

  local HTTP_CODE
  local BODY
  BODY=$(curl -k -s \
    -u "$AUTH" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -w "\n%{http_code}" \
    -X POST "${DIRECTOR}/${endpoint}" \
    -d "$payload" 2>/dev/null)

  HTTP_CODE=$(printf '%s' "$BODY" | awk 'END{print}')
  RESP=$(printf '%s' "$BODY" | awk 'NR>1{print prev} {prev=$0}')

  case "$HTTP_CODE" in
    200|201)
      printf "${GREEN}[OK]${NC}  %-35s angelegt (HTTP %s)\n" "$name" "$HTTP_CODE"
      ;;
    422)
      # Director gibt 422 wenn Objekt bereits existiert
      printf "${YELLOW}[--]${NC}  %-35s bereits vorhanden — übersprungen\n" "$name"
      ;;
    *)
      printf "${RED}[ERR]${NC} %-35s HTTP %s: %s\n" "$name" "$HTTP_CODE" "$RESP"
      return 1
      ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "1/3  CheckCommand registrieren..."
# ──────────────────────────────────────────────────────────────────────────────
director_post "command" '{
  "object_name": "wp-exposure",
  "object_type": "object",
  "command": "'"$PLUGIN"'",
  "arguments": {
    "-H": {
      "value": "$wp_exposure_host$",
      "description": "Target hostname to check",
      "required": true
    },
    "-p": {
      "value": "$wp_exposure_port$",
      "description": "HTTPS port (default: 443)",
      "required": false,
      "set_if": "$wp_exposure_port$"
    },
    "-t": {
      "value": "$wp_exposure_timeout$",
      "description": "Timeout in seconds (default: 10)",
      "required": false,
      "set_if": "$wp_exposure_timeout$"
    }
  },
  "vars": {
    "wp_exposure_host": "$host.name$"
  }
}' "command/wp-exposure"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "2/3  Service anlegen (verknüpft mit Host-Template 'Wordpress')..."
# ──────────────────────────────────────────────────────────────────────────────
# WICHTIG: object_type=object + host=<Template-Name> ist das korrekte Director-
# Muster für template-basierte Apply Rules.
# object_type=apply mit assign_filter generiert ungültiges Icinga2-DSL (null in 1).
director_post "service" '{
  "object_name": "WP Security Exposure",
  "object_type": "object",
  "host": "Wordpress",
  "check_command": "wp-exposure",
  "command_endpoint": "'"$SATELLITE"'",
  "check_interval": 300,
  "retry_interval": 60,
  "max_check_attempts": 3,
  "vars": {
    "wp_exposure_host": "$host.name$"
  }
}' "service/WP Security Exposure"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "3/3  Deploy..."
# ──────────────────────────────────────────────────────────────────────────────
DEPLOY=$(curl -k -s \
  -u "$AUTH" \
  -H "Accept: application/json" \
  -X POST "${DIRECTOR}/config/deploy" 2>/dev/null)

CHECKSUM=$(printf '%s' "$DEPLOY" | grep -o '"checksum":"[^"]*"' | cut -d'"' -f4)
if [[ -n "$CHECKSUM" ]]; then
  printf "${GREEN}[OK]${NC}  Deploy ausgelöst — checksum: %s\n" "$CHECKSUM"
else
  printf "${RED}[ERR]${NC} Deploy fehlgeschlagen: %s\n" "$DEPLOY"
  exit 1
fi

echo ""
echo "Fertig. Service 'WP Security Exposure' läuft auf Satellit '${SATELLITE}'."
echo "Check-Interval: 300s. Warten auf ersten Check-Lauf in Icinga Web 2."
