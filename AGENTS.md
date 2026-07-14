# vnit-infra-monitoring — Agent Instructions

Bash-Skripte zur Konfiguration und zum Monitoring der VNIT-Infrastruktur via Icinga2, Icinga Director, Grafana, Loki und Fluent Bit.

---

## Infrastruktur-Übersicht

| Dienst | Adresse | Protokoll |
|---|---|---|
| Icinga Director (HTTP API) | `http://monitoring.vn.internal:8080` | HTTP |
| Icinga2 REST API | `https://monitoring.vn.internal:5665` | HTTPS |
| Grafana | `http://monitoring.vn.internal:3000` | HTTP |
| Loki | `http://monitoring.vn.internal:3100` | HTTP |
| Fluent Bit | lokal auf den Ziel-Hosts | — |
| **Icinga Satellite** | `78.46.244.95` | SSH (via Jump) |

---

## SSH-Zugang

### Icinga Satellite — `VN-ICINGA-EX`

```
ssh VN-ICINGA-EX
```

SSH-Config (`~/.ssh/config`) ist bereits konfiguriert:

| Parameter | Wert |
|---|---|
| Host | `VN-ICINGA-EX` |
| HostName | `78.46.244.95` |
| User | `root` |
| ProxyJump | `vnadm-mo@VN-ITADM01` (172.30.101.233) |

**Jump-Host:** `VN-ITADM01` → `VN-ICINGA-EX`. Direkter SSH auf `78.46.244.95` funktioniert **nicht** ohne Jump.  
`ForwardAgent yes` ist gesetzt — keine manuelle Key-Weitergabe nötig.

---

## Credentials — KRITISCH: zwei verschiedene Auth-Systeme

| API | Credentials | Hinweis |
|---|---|---|
| Icinga Director (`:8080`) | `icingaadmin:vnit` | Icinga Web 2 User |
| Icinga2 REST API (`:5665`) | `root:d04e0e3607dd5c8c` | Icinga2 API User |
| Grafana (`:3000`) | `Bearer <see .creds_grafana>` | Service Account Token (Admin, `vnit-infra-monitoring`) |
| IcingaDB MySQL (`icinga-mysql:3306`) | `icingadb:Ao334sPhTVEkTVVDvP67Y6bxAZzGBU` | DB: `icingadb`; Grafana DS UID: `deri94sayzuo0d` |

**Niemals verwechseln.** `root:d04e0e3607dd5c8c` gibt HTTP 401 gegen den Director. `icingaadmin:vnit` gibt HTTP 401 gegen die Icinga2 API.

---

## Grafana API

Basis: `http://monitoring.vn.internal:3000`  
Auth: `-H "Authorization: Bearer <token from .creds_grafana>"`  
Service Account: `vnit-infra-monitoring` (Role: Admin, SA-ID: 2, Token-ID: 1)

Grafana-Version: **12.0.1**

### Wichtige Endpunkte

| Endpunkt | Methode | Zweck |
|---|---|---|
| `/api/health` | `GET` | Liveness-Check (kein Auth nötig) |
| `/api/org` | `GET` | Aktuelle Organisation |
| `/api/datasources` | `GET` | Alle Datasources auflisten |
| `/api/datasources` | `POST` | Datasource anlegen |
| `/api/datasources/name/<name>` | `GET` | Datasource per Name lesen |
| `/api/folders` | `GET` | Alle Ordner auflisten |
| `/api/folders` | `POST` | Ordner anlegen |
| `/api/dashboards/db` | `POST` | Dashboard anlegen / aktualisieren |
| `/api/dashboards/uid/<uid>` | `GET` | Dashboard per UID lesen |
| `/api/dashboards/uid/<uid>` | `DELETE` | Dashboard löschen |
| `/api/search?type=dash-db` | `GET` | Dashboards suchen |
| `/api/serviceaccounts` | `GET/POST` | Service Accounts verwalten |

### Beispiel-Aufruf

```bash
curl -s \
  -H "Authorization: Bearer $(cat .creds_grafana)" \
  -H "Content-Type: application/json" \
  http://monitoring.vn.internal:3000/api/datasources
```

---

## Icinga Director API

Basis: `http://monitoring.vn.internal:8080/director/`  
Auth: `-u "icingaadmin:vnit"`

### Wichtige Endpunkte

| Endpunkt | Methode | Zweck |
|---|---|---|
| `/director/service?name=<name>` | `GET` | Service-Definition lesen |
| `/director/service?name=<name>` | `PUT` | Service anlegen / überschreiben (idempotent) |
| `/director/services` | `GET` | Alle Services listen (gibt `{"objects": [...]}`) |
| `/director/command?name=<name>` | `GET` | Check Command mit Argumenten lesen |
| `/director/config/deploy` | `POST` | Konfiguration deployen |

**Kein** `/director/checkcommands`-Endpunkt — gibt 404. Singular `/director/command?name=…` verwenden.

### Services an Host-Template verknüpfen (= Apply Rule)

**KRITISCH:** `object_type: apply` + `assign_filter` erzeugt **ungültiges Icinga2-DSL** (`assign where null in 1`) — Config-Reload schlägt still fehl, Icinga2 rollt zur alten Config zurück.

Korrektes Muster: `object_type: object` + `host: <Template-Name>`:

```bash
curl -k -s \
  -u "icingaadmin:vnit" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X POST "http://monitoring.vn.internal:8080/director/service" \
  -d '{
    "object_name": "<NAME>",
    "object_type": "object",
    "host": "Wordpress",
    "check_command": "<cmd>",
    "vars": { ... }
  }'
```

Director generiert daraus intern `assign where "Wordpress" in host.templates`.

**Neue Objekte:** `POST` (nicht `PUT`). `PUT` gibt "No such object" wenn noch nicht vorhanden.

**Update:** `PUT /director/service?name=<Name>`

### Nach jeder Änderung: Deploy

```bash
curl -k -s -u "icingaadmin:vnit" -H "Accept: application/json" \
  -X POST "http://monitoring.vn.internal:8080/director/config/deploy"
```

### Vorhandene Service-Templates

| Template | check_command | Zweck |
|---|---|---|
| `HTTP` | `http` | Basis-HTTP-Check; setzt `http_address/$host.name$`, `check_interval:120s` |
| `Nuclei` | `dummy` (passiv) | Passiver Check für Nuclei-Ergebnisse |

### Nuclei-Konfiguration

Nuclei-Config liegt auf dem Icinga Satellite (`VN-ICINGA-EX`) unter `/opt/nuclei`.

---

## Icinga2 REST API

Basis: `https://monitoring.vn.internal:5665/v1/`  
Auth: `-u "root:d04e0e3607dd5c8c"`  
Immer `-k` (self-signed Cert) und `-H "X-HTTP-Method-Override: GET" -X POST` für Leseanfragen.

### Hosts eines Templates auflisten

```bash
curl -k -s \
  -u "root:d04e0e3607dd5c8c" \
  -H "Accept: application/json" \
  -H "X-HTTP-Method-Override: GET" \
  -X POST "https://monitoring.vn.internal:5665/v1/objects/hosts" \
  -d '{"filter": "\"Wordpress\" in host.templates", "attrs": ["name","address"]}'
```

---

## Host-Templates (bekannte)

| Template | Bedeutung |
|---|---|
| `Wordpress` | Alle WP-gehosteten Instanzen — Ziel für WP-spezifische apply rules |
| `Windows Agents` | Windows-Hosts mit Icinga-Agent |

---

## check_http — relevante Variablen

| Variable | CLI-Flag | Verwendung |
|---|---|---|
| `http_uri` | `-u` | URL-Pfad |
| `http_ssl` | `-S` | HTTPS |
| `http_sni` | `--sni` | SNI für vHosts |
| `http_onredirect` | `-f` | `follow` / `critical` / `warning` / `ok` |
| `http_expect` | `-e` | Erwartete Status-Zeilen (kommagetrennt); CRITICAL wenn keine matcht |
| `http_expect_body_eregi` | `-R` | Body-Regex case-insensitive; CRITICAL wenn NICHT gefunden |
| `http_invertregex` | `--invert-regex` | Invertiert Regex: CRITICAL wenn gefunden |

---

## Projekt-Konventionen

- Alle Skripte: `#!/usr/bin/env bash`, `set -uo pipefail`
- Curl-Aufrufe immer mit `-k` (self-signed Certs in allen internen Diensten)
- Alle Director-Skripte deployen am Ende automatisch: `POST /director/config/deploy`
- Skript-Dokumentation als Markdown unter `doc/`
- **Verbindlich fuer alle Icinga/Nagios-Plugins:** `doc/plugin_standard_icinga_nagios.md`

---

## Vorhandene Skripte

| Datei | Zweck |
|---|---|
| [`applyNucleiWordpress.sh`](applyNucleiWordpress.sh) | Nuclei-Passivcheck als apply rule im Director anlegen |
| [`checkWordpressExposure.sh`](checkWordpressExposure.sh) | WP-Pfade per curl prüfen (nur Report, kein Director) |
| [`getHosts.sh`](getHosts.sh) | Einzelnen Host aus Director lesen |
| [`getHosts2.sh`](getHosts2.sh) | Hosts nach Template aus Icinga2 API lesen |
| [`getHosts3.sh`](getHosts3.sh) | Hosts nach Template aus Icinga2 API lesen (verbose) |
| [`doc/wp_http_check.md`](doc/wp_http_check.md) | Plan: WP-HTTP-Checks als aktive Checks im Director |
