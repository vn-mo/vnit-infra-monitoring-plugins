# Plan: WordPress HTTP-Checks via Icinga Director API

## Ausgangslage

### Was bereits existiert

| Objekt | Typ | Relevanz |
|---|---|---|
| `http` | Check Command | Basis-Plugin (`check_http`), bereits vollständig konfiguriert |
| `HTTP` | Service Template | Importiert `http`, setzt `http_address/$host.name$`, `http_vhost/$host.name$`, `http_useragent: Vincentz Monitoring`, `check_interval: 120s` |
| `Nuclei` | Service Template (passiv) | Zeigt das Muster: `PUT /director/service` mit `object_type: apply` + `assign_filter` |
| Template `Wordpress` | Host Template | Alle WP-Hosts haben dieses Template → Ziel-Scope für die apply rules |

### Relevante `http` Check Command Variablen

| Variable | CLI-Flag | Semantik |
|---|---|---|
| `http_uri` | `-u` | URL-Pfad, z.B. `/wp-config.php` |
| `http_ssl` | `-S` | HTTPS aktivieren |
| `http_sni` | `--sni` | SNI-Extension (nötig für vHosts) |
| `http_onredirect` | `-f` | Redirect-Verhalten: `follow`, `critical`, `warning`, `ok` |
| `http_expect` | `-e` | Erwartete Status-Zeile(n), kommagetrennt. **CRITICAL wenn keine davon matcht.** |
| `http_expect_body_eregi` | `-R` | Case-insensitive Regex im Body. **CRITICAL wenn NICHT gefunden** (Normalfall) |
| `http_invertregex` | `--invert-regex` | Invertiert Regex-Logik: **CRITICAL wenn gefunden** |

---

## Ziel

**Ein einziger aktiver Check** pro WordPress-Host, der alle 5 Pfade in einem Plugin-Lauf prüft.  
Der Check läuft auf dem externen Satelliten `vn-icinga-ex` (78.46.244.95) — direkter Netzwerkzugang zu den WP-Hosts, kein interner Monitoring-Server nötig.  
Sobald ein Host das Template `Wordpress` trägt, erhält er den Check automatisch via apply rule.

### Architektur

```
Icinga Master (monitoring.vn.internal)
  └── Satellite vn-icinga-ex (78.46.244.95, Zone: external)
        └── check_wp_exposure -H <wp-host>
              ├── /wp-config.php          → HTTP 200? → CRITICAL
              ├── /wp-config.php.bak      → HTTP 200? → CRITICAL
              ├── /xmlrpc.php             → HTTP 200? → CRITICAL
              ├── /wp-content/debug.log   → HTTP 200? → CRITICAL
              └── /wp-content/uploads/    → "Index of" im Body? → CRITICAL
```

**Exit-Code-Logik:**
- Mindestens 1 Pfad exponiert → `CRITICAL` (exit 2)
- Kein Pfad exponiert, aber Timeouts → `WARNING` (exit 1)
- Alle Pfade sauber → `OK` (exit 0)

---

## Die 5 Checks im Detail

### Check-Logik: `http_expect`

`check_http -e "HTTP/1. 403,HTTP/1. 404"` → OK wenn der Server mit 403 oder 404 antwortet.  
Antwortet der Server mit **200** (Datei erreichbar) → **CRITICAL**.  
`http_onredirect: follow` → Redirects werden verfolgt, der finale Status-Code entscheidet.

---

### 1. `WP: wp-config.php erreichbar`

| Feld | Wert |
|---|---|
| `object_name` | `WP: wp-config.php erreichbar` |
| `imports` | `["HTTP"]` |
| `assign_filter` | `"Wordpress" in host.templates` |
| `http_uri` | `/wp-config.php` |
| `http_ssl` | `true` |
| `http_sni` | `true` |
| `http_onredirect` | `follow` |
| `http_expect` | `HTTP/1. 403,HTTP/1. 404` |

**Risiko:** DB-Credentials, `AUTH_KEY`, `SECURE_AUTH_KEY` im Klartext abrufbar.

---

### 2. `WP: wp-config.php.bak erreichbar`

Identisch zu Check 1, aber `http_uri: /wp-config.php.bak`.

**Risiko:** Backup-Datei, die Webserver häufig als Plain-Text ausliefert (kein PHP-Parsing).

---

### 3. `WP: xmlrpc.php erreichbar`

| Feld | Wert |
|---|---|
| `http_uri` | `/xmlrpc.php` |
| `http_expect` | `HTTP/1. 403,HTTP/1. 404` |
| restliche vars | wie Check 1 |

**Hintergrund:** Bewusst aus Nuclei-Scope excluded. Dieser Check überwacht, ob xmlrpc.php nach Wartungsarbeiten oder Plugin-Updates wieder auftaucht (z.B. durch WP-Core-Update, der die Datei wiederherstellt).

---

### 4. `WP: debug.log erreichbar`

| Feld | Wert |
|---|---|
| `http_uri` | `/wp-content/debug.log` |
| `http_expect` | `HTTP/1. 403,HTTP/1. 404` |
| restliche vars | wie Check 1 |

**Risiko:** Stack Traces, absolute Pfade, DB-Queries, Plugin-Fehler — alles was `WP_DEBUG_LOG` aufzeichnet.

---

### 5. `WP: Uploads Directory Listing`

| Feld | Wert |
|---|---|
| `http_uri` | `/wp-content/uploads/` |
| `http_ssl` | `true` |
| `http_sni` | `true` |
| `http_onredirect` | `follow` |
| `http_expect_body_eregi` | `Index of` |
| `http_invertregex` | `true` |

**Logik:** `check_http -R "Index of" --invert-regex` → **CRITICAL wenn** Body den String `Index of` enthält.  
Antwortet der Server mit 403 (Directory Listing deaktiviert) → kein Match → **OK**.  
Antwortet der Server mit 200 + `Index of` im Body → Match → invertiert → **CRITICAL**.

**Hinweis:** `http_expect` wird hier **nicht** gesetzt (bleibt leer), weil `check_http` bei leerem `-e` jeden HTTP-Status akzeptiert und die Entscheidung ausschließlich über den Body-Regex fällt.

---

## Implementierung (deployed)

### Plugin auf Satellit

**Pfad:** `/usr/lib/nagios/plugins/custom/check_wp_exposure` auf `vn-icinga-ex`  
**SSH-Zugang:** `ssh VN-ICINGA-EX` (Jump via VN-ITADM01, siehe `~/.ssh/config`)

### Director-Objekte (angelegt + deployed)

| Objekt | Typ | Details |
|---|---|---|
| `wp-exposure` | CheckCommand | Ruft `/usr/lib/nagios/plugins/custom/check_wp_exposure` auf |
| `WP Security Exposure` | Service (apply) | `command_endpoint: vn-icinga-ex`, `check_interval: 300s`, `assign_filter: "Wordpress" in host.templates` |

### CheckCommand-Variablen

| Variable | Standardwert | Bedeutung |
|---|---|---|
| `wp_exposure_host` | `$host.name$` | Zu prüfender Hostname |
| `wp_exposure_port` | *(leer → 443)* | HTTPS-Port |
| `wp_exposure_timeout` | *(leer → 10s)* | Curl-Timeout |

### Director API — Muster für Wiederausführung

CheckCommand (POST zum Erstellen, PUT zum Überschreiben):

```bash
curl -k -s -u "icingaadmin:vnit" \
  -H "Accept: application/json" -H "Content-Type: application/json" \
  -X POST "http://monitoring.vn.internal:8080/director/command" \
  -d '{ "object_name": "wp-exposure", "object_type": "object", ... }'
```

Service Apply Rule:

```bash
curl -k -s -u "icingaadmin:vnit" \
  -H "Accept: application/json" -H "Content-Type: application/json" \
  -X POST "http://monitoring.vn.internal:8080/director/service" \
  -d '{
    "object_name": "WP Security Exposure",
    "object_type": "apply",
    "check_command": "wp-exposure",
    "command_endpoint": "vn-icinga-ex",
    "assign_filter": "\"Wordpress\" in host.templates"
  }'
```

**Hinweis:** Director nimmt für neue Objekte `POST`, nicht `PUT` (PUT gibt "No such object available" wenn noch nicht vorhanden).

Vollständiges idempotentes Skript: [`applyWPHttpChecks.sh`](../applyWPHttpChecks.sh)

---

## Limitierungen & Edge Cases

| Punkt | Details |
|---|---|
| **Self-signed Certs** | `check_http` prüft SSL-Zertifikate. Falls WP-Hosts selbst-signierte Certs haben: `http_ssl_force_tlsv1_2_or_higher: false` oder `-k`-Äquivalent nötig. Das `http`-Command hat keinen `--insecure`-Flag — ggf. über `http_certificate`-Var mit `-1` für "skip verify" lösen. |
| **Redirects auf Login** | `wp-config.php`/`xmlrpc.php` können auf `/wp-login.php` umleiten (302 → 200 Login-Seite). Mit `http_onredirect: follow` → Check wertet dann den Login-Status (200) aus → CRITICAL. Das ist gewollt — Redirect sollte zu 403/404 gehen, nicht zu einer Login-Seite. |
| **Uploads ohne Index of** | Manche WP-Setups liefern bei aktiviertem Directory Listing eine custom `index.html` statt Apache/nginx-Standard. Dann fehlt `Index of` im Body → Check zeigt fälschlich OK. Alternative: `http_expect: "HTTP/1. 403"` statt Body-Regex (konservativer). |
| **Port-Varianz** | HTTP-Template nutzt Standardport (80/443). Hosts auf non-standard Ports brauchen `http_port` als zusätzliche var. |
| **check_interval** | Geerbt vom HTTP-Template: 120s. Für Security-Checks ggf. sinnvoll reduzieren (z.B. 300s — häufiger als normal nicht nötig, da sich Dateistruktur selten ändert). |
