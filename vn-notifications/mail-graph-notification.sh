#!/usr/bin/env bash
# Icinga2 HTML Notification via Microsoft Graph API
# Features: HTML-Design, IcingaDB State History (20 Eintraege)
# Credentials: /etc/icinga2/graph-mail.env (chmod 600)

CREDS_FILE="/etc/icinga2/graph-mail.env"
TOKEN_CACHE="/tmp/icinga_graph_token"

usage() {
  cat << EOF
Usage: $0 -t TYPE -s STATE -l HOSTNAME -n HOSTDISPLAYNAME -o OUTPUT -r USEREMAIL -d DATETIME
         [-u SERVICEDISPLAYNAME] [-e SERVICENAME] [-4 ADDRESS]
EOF
}

while getopts "t:s:l:n:o:r:d:u:e:4:h" opt; do
  case "$opt" in
    t) NOTIF_TYPE="$OPTARG" ;;
    s) STATE="$OPTARG" ;;
    l) HOSTNAME="$OPTARG" ;;
    n) HOSTDISPLAYNAME="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    r) USEREMAIL="$OPTARG" ;;
    d) DATETIME="$OPTARG" ;;
    u) SERVICEDISPLAYNAME="$OPTARG" ;;
    e) SERVICENAME="$OPTARG" ;;
    4) ADDRESS="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

for P in NOTIF_TYPE STATE HOSTNAME HOSTDISPLAYNAME OUTPUT USEREMAIL DATETIME; do
  eval "VAL=\$$P"
  [ -z "$VAL" ] && { echo "ERROR: -${P} missing" >&2; exit 1; }
done

[ ! -f "$CREDS_FILE" ] && { echo "ERROR: $CREDS_FILE not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CREDS_FILE"

# --- State color ---
state_color() {
  case "$1" in
    CRITICAL|DOWN) echo "#d9534f" ;;
    WARNING)       echo "#f0ad4e" ;;
    OK|UP)         echo "#5cb85c" ;;
    UNKNOWN)       echo "#9b59b6" ;;
    *)             echo "#777777" ;;
  esac
}

# --- OAuth2 Token (cached 60min) ---
get_token() {
  local NOW; NOW=$(date +%s)
  if [ -f "$TOKEN_CACHE" ]; then
    local EXP TOK
    EXP=$(head -1 "$TOKEN_CACHE"); TOK=$(tail -1 "$TOKEN_CACHE")
    [ "$NOW" -lt "$EXP" ] && [ -n "$TOK" ] && { echo "$TOK"; return; }
  fi
  local RESP; RESP=$(curl -s -X POST \
    "https://login.microsoftonline.com/${GRAPH_TENANT_ID}/oauth2/v2.0/token" \
    -d "client_id=${GRAPH_CLIENT_ID}" \
    -d "client_secret=${GRAPH_CLIENT_SECRET}" \
    -d "scope=https://graph.microsoft.com/.default" \
    -d "grant_type=client_credentials")
  local TOK EXP_IN
  TOK=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
  EXP_IN=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('expires_in',3600))" 2>/dev/null)
  [ -z "$TOK" ] && { echo "ERROR: token failed" >&2; echo "$RESP" >&2; exit 1; }
  echo "$((NOW + EXP_IN - 60))" > "$TOKEN_CACHE"
  echo "$TOK" >> "$TOKEN_CACHE"
  chmod 600 "$TOKEN_CACHE"
  echo "$TOK"
}

# --- IcingaDB: last 20 state changes as HTML table ---
get_history_html() {
python3 << PYEOF
import pymysql, html as hl, sys

STATE_MAP = {
    0: ('OK',       '#5cb85c'),
    1: ('WARNING',  '#f0ad4e'),
    2: ('CRITICAL', '#d9534f'),
    3: ('UNKNOWN',  '#9b59b6'),
}

def badge(state_int):
    label, color = STATE_MAP.get(state_int, ('?', '#777'))
    return (f'<span style="background:{color};color:#fff;padding:2px 7px;'
            f'border-radius:3px;font-size:11px;font-weight:bold;">{label}</span>')

try:
    conn = pymysql.connect(
        host='${ICINGADB_HOST}', port=${ICINGADB_PORT},
        user='${ICINGADB_USER}', password='${ICINGADB_PASS}',
        database='${ICINGADB_NAME}', connect_timeout=3
    )
    cur = conn.cursor()
    SERVICE = '${SERVICENAME}'
    HOST    = '${HOSTNAME}'

    if SERVICE:
        cur.execute("""
            SELECT sh.previous_soft_state, sh.soft_state,
                   FROM_UNIXTIME(sh.event_time/1000), LEFT(sh.output, 200)
            FROM state_history sh
            JOIN service s ON s.id = sh.service_id
            JOIN host h    ON h.id = sh.host_id
            WHERE h.name = %s AND s.name = %s
            ORDER BY sh.event_time DESC LIMIT 20
        """, (HOST, SERVICE))
    else:
        cur.execute("""
            SELECT sh.previous_soft_state, sh.soft_state,
                   FROM_UNIXTIME(sh.event_time/1000), LEFT(sh.output, 200)
            FROM state_history sh
            JOIN host h ON h.id = sh.host_id
            WHERE h.name = %s AND sh.service_id IS NULL
            ORDER BY sh.event_time DESC LIMIT 20
        """, (HOST,))

    rows = cur.fetchall()
    conn.close()

    if not rows:
        print('<p style="color:#888;font-style:italic;font-size:13px;">Noch keine History-Einträge vorhanden.</p>')
        sys.exit(0)

    out = ['<table style="width:100%;border-collapse:collapse;font-size:12px;margin-top:8px;">',
           '<tr style="background:#2d3748;color:#fff;">',
           '<th style="padding:7px 10px;text-align:left;font-weight:600;">Zeitpunkt</th>',
           '<th style="padding:7px 10px;text-align:center;font-weight:600;">Von</th>',
           '<th style="padding:7px 10px;text-align:center;font-weight:600;">Nach</th>',
           '<th style="padding:7px 10px;text-align:left;font-weight:600;">Output</th>',
           '</tr>']
    for i, (prev, curr, ts, output) in enumerate(rows):
        bg = '#f8f9fa' if i % 2 == 0 else '#ffffff'
        out.append(
            f'<tr style="background:{bg};border-bottom:1px solid #e9ecef;">'
            f'<td style="padding:5px 10px;white-space:nowrap;color:#4a5568;">{ts}</td>'
            f'<td style="padding:5px 10px;text-align:center;">{badge(prev)}</td>'
            f'<td style="padding:5px 10px;text-align:center;">{badge(curr)}</td>'
            f'<td style="padding:5px 10px;font-family:monospace;font-size:11px;color:#2d3748;">'
            f'{hl.escape(output or "")}</td></tr>'
        )
    out.append('</table>')
    print(''.join(out))
except Exception as e:
    print(f'<p style="color:#888;font-style:italic;font-size:13px;">History nicht verfügbar: {hl.escape(str(e))}</p>')
PYEOF
}

# ============================================================
TOKEN=$(get_token)
STATE_COLOR=$(state_color "$STATE")

IS_SERVICE=false
[ -n "$SERVICEDISPLAYNAME" ] && IS_SERVICE=true

if $IS_SERVICE; then
  SUBJECT="[${NOTIF_TYPE}] ${SERVICEDISPLAYNAME} on ${HOSTDISPLAYNAME} is ${STATE}!"
  TITLE_LINE="${SERVICEDISPLAYNAME} on ${HOSTDISPLAYNAME}"
else
  SUBJECT="[${NOTIF_TYPE}] Host ${HOSTDISPLAYNAME} is ${STATE}!"
  TITLE_LINE="Host ${HOSTDISPLAYNAME}"
fi

HISTORY_HTML=$(get_history_html)

ICINGAWEB_URL="http://172.30.104.104:8080/icingaweb2"
if $IS_SERVICE; then
  DETAIL_URL="${ICINGAWEB_URL}/icingadb/service?name=${SERVICENAME}&host.name=${HOSTNAME}"
else
  DETAIL_URL="${ICINGAWEB_URL}/icingadb/host?name=${HOSTNAME}"
fi

# Write HISTORY_HTML to temp file to avoid stdin/heredoc conflict
TMP_HISTORY=$(mktemp /tmp/icinga_hist_XXXXXX.html)
printf '%s' "$HISTORY_HTML" > "$TMP_HISTORY"

# Build HTML – reads history from temp file, no stdin conflict
HTML_BODY=$(python3 - "$STATE" "$STATE_COLOR" "$NOTIF_TYPE" \
  "$TITLE_LINE" "$OUTPUT" "$HOSTNAME" "$HOSTDISPLAYNAME" \
  "$SERVICENAME" "$SERVICEDISPLAYNAME" "$DATETIME" "$ADDRESS" \
  "$DETAIL_URL" "$TMP_HISTORY" <<PYEOF
import sys, html as hl

(_, STATE, STATE_COLOR, NOTIF_TYPE, TITLE_LINE,
 OUTPUT, HOSTNAME, HOSTDISPLAYNAME, SERVICENAME, SERVICEDISPLAYNAME,
 DATETIME, ADDRESS, DETAIL_URL, TMP_HISTORY) = sys.argv

def e(s): return hl.escape(s)

history_html = open(TMP_HISTORY).read()

if SERVICENAME:
    svc_row = f'''<tr style="border-bottom:1px solid #e2e8f0;">
        <td style="padding:8px 0;color:#718096;">Service</td>
        <td style="padding:8px 0;">{e(SERVICEDISPLAYNAME)}</td></tr>'''
else:
    svc_row = ""

if ADDRESS:
    addr_row = f'''<tr style="border-bottom:1px solid #e2e8f0;">
        <td style="padding:8px 0;color:#718096;">IP-Adresse</td>
        <td style="padding:8px 0;"><code>{e(ADDRESS)}</code></td></tr>'''
else:
    addr_row = ""

print(f"""<!DOCTYPE html>
<html><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:24px 0;">
<tr><td align="center">
<table width="640" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">

  <tr><td style="background:{e(STATE_COLOR)};padding:20px 28px;">
    <table width="100%"><tr>
      <td style="color:#fff;font-size:11px;opacity:0.85;text-transform:uppercase;letter-spacing:1px;">Icinga Monitoring</td>
      <td align="right" style="color:#fff;font-size:11px;opacity:0.85;">{e(NOTIF_TYPE)}</td>
    </tr></table>
    <div style="color:#fff;font-size:22px;font-weight:bold;margin-top:8px;">{e(TITLE_LINE)}</div>
    <div style="margin-top:8px;">
      <span style="background:rgba(0,0,0,0.2);color:#fff;padding:4px 12px;border-radius:4px;font-size:14px;font-weight:bold;">{e(STATE)}</span>
    </div>
  </td></tr>

  <tr><td style="padding:24px 28px;">
    <table style="width:100%;border-collapse:collapse;font-size:14px;">
      <tr style="border-bottom:1px solid #e2e8f0;">
        <td style="padding:8px 0;color:#718096;width:130px;">Zeitpunkt</td>
        <td style="padding:8px 0;">{e(DATETIME)}</td></tr>
      <tr style="border-bottom:1px solid #e2e8f0;">
        <td style="padding:8px 0;color:#718096;">Host</td>
        <td style="padding:8px 0;">{e(HOSTDISPLAYNAME)} <span style="color:#a0aec0;font-size:12px;">({e(HOSTNAME)})</span></td></tr>
      {svc_row}
      {addr_row}
      <tr>
        <td style="padding:8px 0;color:#718096;vertical-align:top;">Check Output</td>
        <td style="padding:8px 0;"><code style="background:#f7fafc;border:1px solid #e2e8f0;padding:6px 10px;border-radius:4px;display:block;font-size:13px;color:#2d3748;word-break:break-all;">{e(OUTPUT)}</code></td></tr>
    </table>

    <div style="margin-top:20px;">
      <a href="{e(DETAIL_URL)}" style="background:{e(STATE_COLOR)};color:#fff;padding:10px 20px;border-radius:5px;text-decoration:none;font-size:13px;font-weight:bold;">In Icinga öffnen &#8594;</a>
    </div>

    <h3 style="color:#4a5568;border-bottom:2px solid #e2e8f0;padding-bottom:6px;margin-top:28px;">&#128336; State History (letzte 20 Eintr&#228;ge)</h3>
    {history_html}

  </td></tr>

  <tr><td style="background:#f7fafc;padding:14px 28px;border-top:1px solid #e2e8f0;font-size:11px;color:#a0aec0;">
    Icinga2 Monitoring &middot; <a href="http://172.30.104.104:8080/icingaweb2" style="color:#a0aec0;">IcingaWeb2</a>
  </td></tr>

</table></td></tr></table>
</body></html>""")
PYEOF
)

rm -f "$TMP_HISTORY"

# Write HTML to temp file to avoid stdin/heredoc conflict
TMP_HTML=$(mktemp /tmp/icinga_html_XXXXXX.html)
printf '%s' "$HTML_BODY" > "$TMP_HTML"

# Assemble JSON payload – all data via files, no stdin conflict
PAYLOAD=$(python3 - "$SUBJECT" "$USEREMAIL" "$TMP_HTML" <<PYEOF
import json, sys
subject   = sys.argv[1]
recipient = sys.argv[2]
body      = open(sys.argv[3]).read()

msg = {
    "subject": subject,
    "body": {"contentType": "HTML", "content": body},
    "toRecipients": [{"emailAddress": {"address": recipient}}]
}
print(json.dumps({"message": msg, "saveToSentItems": False}))
PYEOF
)

rm -f "$TMP_HTML"

HTTP_RESP=$(curl -s -w "\n%{http_code}" -X POST \
  "https://graph.microsoft.com/v1.0/users/${GRAPH_FROM}/sendMail" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD")

HTTP_CODE=$(echo "$HTTP_RESP" | tail -1)
HTTP_BODY=$(echo "$HTTP_RESP" | head -n -1)

if [ "$HTTP_CODE" = "202" ]; then
  exit 0
else
  echo "ERROR: Graph API HTTP ${HTTP_CODE}" >&2
  echo "$HTTP_BODY" >&2
  exit 1
fi
