#!/usr/bin/env bash
# checkWordpressExposure.sh
# WordPress-spezifische Konfigurationsprüfungen — nur Report
#
# Geprüfte Pfade pro Host:
#   /wp-config.php          — DB-Credentials, Auth-Keys
#   /wp-config.php.bak      — Backup mit Klartext-Credentials
#   /xmlrpc.php             — Brute-Force-Vektor (bewusst von Nuclei excluded)
#   /wp-content/debug.log   — Fehlermeldungen / Stack Traces / Pfade
#   /wp-content/uploads/    — Directory Listing aktiv?
#
# Voraussetzungen: curl, jq, bash >=4

set -uo pipefail

ICINGA_API="https://monitoring.vn.internal:5665"
ICINGA_USER="root"
ICINGA_PASS="d04e0e3607dd5c8c"
CURL_TIMEOUT=10

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

FINDINGS=0
TOTAL=0

# Format: "Label:Pfad:Modus"
# Modus: http_status | dir_listing
CHECK_PATHS=(
  "wp-config.php:/wp-config.php:http_status"
  "wp-config.php.bak:/wp-config.php.bak:http_status"
  "xmlrpc.php:/xmlrpc.php:http_status"
  "debug.log:/wp-content/debug.log:http_status"
  "uploads-listing:/wp-content/uploads/:dir_listing"
)

# ──────────────────────────────────────────────────────────────────────────────
# Hosts aus Icinga2-API holen
# ──────────────────────────────────────────────────────────────────────────────
HOSTS_JSON=$(curl -k -s \
  -u "${ICINGA_USER}:${ICINGA_PASS}" \
  -H "Accept: application/json" \
  -H "X-HTTP-Method-Override: GET" \
  -X POST "${ICINGA_API}/v1/objects/hosts" \
  -d '{
    "filter": "\"Wordpress\" in host.templates",
    "attrs": ["name", "address"],
    "pretty": true
  }')

mapfile -t HOST_NAMES < <(echo "$HOSTS_JSON" | jq -r '.results[].name')
mapfile -t HOST_ADDRS < <(echo "$HOSTS_JSON" | jq -r '.results[].attrs.address')

if [[ "${#HOST_NAMES[@]}" -eq 0 ]]; then
  echo "Keine Hosts mit Template 'Wordpress' gefunden. Abbruch."
  exit 1
fi

printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD} WordPress Exposure Check — $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
printf "${BOLD} Hosts: %d${NC}\n" "${#HOST_NAMES[@]}"
printf "${BOLD}══════════════════════════════════════════════════════════════${NC}\n\n"

# ──────────────────────────────────────────────────────────────────────────────
# Pro Host: alle Pfade prüfen
# ──────────────────────────────────────────────────────────────────────────────
for i in "${!HOST_NAMES[@]}"; do
  HOST_NAME="${HOST_NAMES[$i]}"
  HOST_ADDR="${HOST_ADDRS[$i]}"

  printf "${BOLD}Host:${NC} %s  ${BOLD}Adresse:${NC} %s\n" "${HOST_NAME}" "${HOST_ADDR}"
  printf "──────────────────────────────────────────────────────────────\n"

  for CHECK in "${CHECK_PATHS[@]}"; do
    CHECK_LABEL="${CHECK%%:*}"
    CHECK_REST="${CHECK#*:}"
    PATH_URI="${CHECK_REST%%:*}"
    CHECK_MODE="${CHECK_REST##*:}"
    URL="https://${HOST_ADDR}${PATH_URI}"
    TOTAL=$((TOTAL + 1))

    if [[ "${CHECK_MODE}" == "dir_listing" ]]; then
      # Body + HTTP-Code in einem Aufruf: letzte Zeile = Code, Rest = Body
      RESPONSE=$(curl -k -s \
        --max-time "${CURL_TIMEOUT}" \
        --connect-timeout "${CURL_TIMEOUT}" \
        -w "\n%{http_code}" \
        "${URL}" 2>/dev/null) || RESPONSE=$'\n000'
      HTTP_CODE=$(printf '%s' "$RESPONSE" | tail -1)
      BODY=$(printf '%s' "$RESPONSE" | head -n -1)

      if [[ "${HTTP_CODE}" == "200" ]] && echo "${BODY}" | grep -qi "index of"; then
        printf "  ${RED}[EXPOSED]${NC}   %-28s %s  (Directory Listing aktiv)\n" \
          "${CHECK_LABEL}" "${URL}"
        FINDINGS=$((FINDINGS + 1))
      else
        printf "  ${GREEN}[OK]${NC}        %-28s %s  (HTTP %s)\n" \
          "${CHECK_LABEL}" "${URL}" "${HTTP_CODE}"
      fi

    else
      HTTP_CODE=$(curl -k -s \
        --max-time "${CURL_TIMEOUT}" \
        --connect-timeout "${CURL_TIMEOUT}" \
        -o /dev/null -w "%{http_code}" \
        "${URL}" 2>/dev/null) || HTTP_CODE="000"

      case "${HTTP_CODE}" in
        200)
          printf "  ${RED}[EXPOSED]${NC}   %-28s %s\n" "${CHECK_LABEL}" "${URL}"
          FINDINGS=$((FINDINGS + 1))
          ;;
        301|302|303|307|308)
          # Redirect kann auf Login-Seite zeigen — kein direkter Zugriff, aber prüfenswert
          printf "  ${YELLOW}[REDIRECT]${NC}  %-28s %s  (HTTP %s)\n" \
            "${CHECK_LABEL}" "${URL}" "${HTTP_CODE}"
          ;;
        401|403)
          printf "  ${GREEN}[OK]${NC}        %-28s %s  (HTTP %s — Zugriff verweigert)\n" \
            "${CHECK_LABEL}" "${URL}" "${HTTP_CODE}"
          ;;
        404|410)
          printf "  ${GREEN}[OK]${NC}        %-28s %s  (HTTP %s — nicht vorhanden)\n" \
            "${CHECK_LABEL}" "${URL}" "${HTTP_CODE}"
          ;;
        000)
          printf "  ${YELLOW}[TIMEOUT]${NC}   %-28s %s  (nicht erreichbar / Timeout)\n" \
            "${CHECK_LABEL}" "${URL}"
          ;;
        *)
          printf "  ${YELLOW}[WARN]${NC}      %-28s %s  (HTTP %s)\n" \
            "${CHECK_LABEL}" "${URL}" "${HTTP_CODE}"
          ;;
      esac
    fi
  done

  printf "\n"
done

# ──────────────────────────────────────────────────────────────────────────────
# Zusammenfassung
# ──────────────────────────────────────────────────────────────────────────────
printf "══════════════════════════════════════════════════════════════\n"
if [[ "${FINDINGS}" -gt 0 ]]; then
  printf "${RED}${BOLD} %-28s %d von %d Checks exponiert!${NC}\n" "Ergebnis:" "${FINDINGS}" "${TOTAL}"
else
  printf "${GREEN}${BOLD} %-28s Keine Expositionen (%d Checks OK)${NC}\n" "Ergebnis:" "${TOTAL}"
fi
printf "══════════════════════════════════════════════════════════════\n"
