# Icinga Mail-Benachrichtigungen – Einrichtungsplan

## Ziel

Icinga soll bei **WARNING** und **CRITICAL** E-Mails versenden.

### Erster Wurf: Helpdesk-Tickets per Mail

| Parameter | Wert |
|-----------|------|
| Empfänger | `helpdesk-it@vincentz.net` |
| Auslöser | WARNING, CRITICAL (+ Recovery) |
| Scope | Templates `Linux Agents`, `Windows Agents`, `Ping Host`, `Pingless Host`, `SaaS` sowie Hostgruppen `Access Points`, `Switches`, `printers` |
| Ausgeschlossen | Templates `Website`, `Wordpress`, `Domain` |

---

## Implementierungsstand (2026-07-15)

| Schritt | Status | Notiz |
|---------|--------|-------|
| SMTP Port 25 (Exchange Direct Send) | ❌ blockiert | WatchGuard blockt ausgehend Port 25 → Graph API als Primär-Weg |
| msmtp konfiguriert | ✅ Fallback bereit | `/home/ciphron/docker-compose-icinga/config/msmtprc` |
| Microsoft Graph API Auth | ✅ | App Registration, Client Credentials Flow |
| Notification-Skript `mail-graph-notification.sh` | ✅ deployed | `/opt/icinga-plugins/` → `/usr/lib/nagios/icinga-plugins/` |
| Credentials `/etc/icinga2/graph-mail.env` | ✅ | chmod 600, Owner icinga |
| `mail-graph-notification` Command in Director | ✅ | Timeout 60s |
| User `helpdesk-mail` | ✅ | `helpdesk-it@vincentz.net` |
| UserGroup `mail-helpdesk` | ✅ | User zugeordnet |
| Notification-Templates | ✅ deployed | `mail-host-helpdesk-tmpl`, `mail-service-helpdesk-tmpl` |
| Host-Notification-Command (Down/Up) | ✅ deployed | `mail-graph-host-notification` aktiv auf `mail-host-helpdesk-tmpl` |
| Apply-Regel | ✅ | 360 Notifications instanziiert, Container healthy |
| HTML Mail-Body | ✅ | Design, Detailtabelle, Button, State History |
| State History (IcingaDB) | ✅ | Korrekte Spalten: `event_time`, `host_id`, `service_id` |
| Grafana-Graph in Mail | ❌ deaktiviert | Renderer zurückgebaut, Mails werden bewusst ohne Graph versendet |
| pymysql in icinga2-Container | ✅ | installiert via pip --break-system-packages |
| Director Deploy | ✅ | Config `a02bcdd7...` deployed |
| End-to-End Test | ✅ | Mail kommt in osTicket an, HTML korrekt dargestellt |

---

## Transportweg: Microsoft Graph API (HTTPS)

```
Icinga2 → mail-graph-notification.sh
  → curl POST login.microsoftonline.com  (OAuth2 Token, 60min gecacht)
  → curl POST graph.microsoft.com/v1.0/users/it@vincentz.net/sendMail
```

### App Registration

| Feld | Wert |
|------|------|
| Tenant ID | `8cbe03bd-1604-4312-a56b-9c4fad756b23` |
| Client ID | `d9308e3a-43c9-4acb-ae0d-1f05835e7e7c` |
| Permission | `Mail.Send` (Application) |
| Absender | `it@vincentz.net` |
| Credentials-Datei | `/etc/icinga2/graph-mail.env` (im Container, chmod 600) |

---

## Skript: `mail-graph-notification.sh`

**Quelle:** `vnit-infra-monitoring-plugins/vn-notifications/mail-graph-notification.sh`  
**Deployed:** `/opt/icinga-plugins/mail-graph-notification.sh`

Features:
- HTML-Mail: farbiger Header (rot/gelb/grün je State), Detailtabelle, „In Icinga öffnen"-Button
- State History: letzte 20 Zustandswechsel aus IcingaDB (MySQL-Abfrage via pymysql)
- OAuth2-Token-Cache: `/tmp/icinga_graph_token` (60min gültig, kein re-Auth bei jeder Mail)

Parameter (identisch zu Standard-Icinga-Skripten):
```
-t TYPE   -s STATE   -l HOSTNAME   -n HOSTDISPLAYNAME
-o OUTPUT   -r USEREMAIL   -d DATETIME
-u SERVICEDISPLAYNAME   -e SERVICENAME   -4 ADDRESS
```

---

## Icinga Director Konfiguration

### NotificationCommand `mail-graph-notification`
- Script: `/usr/lib/nagios/icinga-plugins/mail-graph-notification.sh`
- Timeout: 60s
- Arguments: `-r`, `-t`, `-s`, `-l`, `-n`, `-o`, `-u`, `-e`, `-d`, `-4`

### Notification-Templates
- `mail-service-helpdesk-tmpl`: Command `mail-graph-notification`, States Warning/Critical/OK, Types Problem/Recovery
- `mail-host-helpdesk-tmpl`: Command `mail-graph-host-notification`, States Down/Up, Types Problem/Recovery

### Apply-Regel (`/etc/icinga2/conf.d/notify-helpdesk.conf`)

```icinga2
apply Notification "helpdesk-mail-service" to Service {
  import "mail-service-helpdesk-tmpl"
  assign where "Linux Agents" in host.templates || "Windows Agents" in host.templates
      || "Ping Host" in host.templates || "Pingless Host" in host.templates
      || "SaaS" in host.templates || "Access Points" in host.groups
      || "Switches" in host.groups || "printers" in host.groups
  ignore where "Website" in host.templates || "Wordpress" in host.templates || "Domain" in host.templates
}
```

Datei ist persistent im gemounteten Volume:  
`/home/ciphron/docker-compose-icinga/icinga2.conf.d/conf.d/notify-helpdesk.conf`

---

## Offene Punkte

| Punkt | Verantwortlich | Status |
|-------|---------------|--------|
| WatchGuard: TCP 25 von `172.30.104.104` freischalten (SMTP-Fallback) | Netzwerk-Admin | optional |
| Client Secret Ablaufdatum überwachen (max. 2 Jahre) | vnit | offen |

---

## Findings / Bekannte Probleme

| Problem | Ursache | Lösung |
|---------|---------|--------|
| SMTP Port 25 blockiert | WatchGuard blockt ausgehend | Graph API als Primär-Weg |
| Mail-Body leer (1. Bug) | `<<< "$HTML_BODY"` nach `<<PYEOF` ungültig (stdin-Konflikt) | HTML in Temp-Datei, Python liest per `open()` |
| Mail-Body leer (2. Bug) | `sys.stdin.read()` liest leer wenn stdin = Python-Heredoc | History ebenfalls in Temp-Datei |
| History: `change_time` unbekannt | IcingaDB-Spalte heißt `event_time` | Korrigiert |
| History: JOIN schlägt fehl | `state_history` hat direkte `host_id`/`service_id` Spalten, kein `object_id` | Korrigiert |
| Grafana-Graph aus Mails entfernt | Renderer-Setup war instabil und nicht erforderlich für Ticketing | Renderer zurückgebaut, Skript versendet ohne Graph |
| Icinga2 DSL: `\|\|` mit Zeilenumbruch bricht Apply-Rules | Parser erwartet `||` am Zeilenende bei Multi-line, oder alles einzeilig | `assign where` einzeilig schreiben |
| Apply-Rules nicht per `icingacli` anlegbar | Director-CLI unterstützt keine Apply-Rules | `.conf`-Datei direkt in `conf.d/` |
| Director muss vor Icinga2-Reload deployed sein | Sonst "Import references unknown template" | Reihenfolge: Director deploy → icinga2 reload |

---

## Referenzen

- [Graph API sendMail](https://learn.microsoft.com/en-us/graph/api/user-sendmail)
- [OAuth2 Client Credentials Flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow)
- [Icinga2 Notifications Doku](https://icinga.com/docs/icinga-2/latest/doc/03-monitoring-basics/#notifications)
