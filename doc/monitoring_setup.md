# Monitoring Stack – Setup-Dokumentation

**Host:** `VN-MONITORING` (Debian 12 Bookworm)  
**Stack-Verzeichnis:** `/home/ciphron/docker-compose-icinga/`  
**Docker-Netzwerk:** `icinga-playground` (172.18.0.0/16)

---

## Architektur-Überblick

```
                    ┌──────────────────────────────────────┐
                    │          Docker: icinga-playground    │
                    │                                      │
  :8080 (LAN/WG) ──►  icingaweb2     ◄──► icinga2 :5665  │
                    │      │                   │           │
                    │  icinga-director      icingadb       │
                    │      │                   │           │
                    │  icinga-mysql  ◄──── icinga-redis    │
                    │                           │           │
  :3000 (LAN/WG) ──►  grafana       ◄──── influxdb2 :8086│
                    │      │                               │
                    │     loki :3100 (nur localhost)       │
                    └──────────────────────────────────────┘
                            │
                        cloudflared  (Cloudflare Tunnel, separater Stack)
```

---

## Container-Übersicht

| Container | Image | Version | Ports (Host→Container) | Status |
|---|---|---|---|---|
| `icinga2` | `vincentz/icinga2-custom-test` | 1.0 (custom) | `0.0.0.0:5665→5665` | Up (healthy) |
| `icingaweb2` | `icinga/icingaweb2` | 2.13.0 | `172.30.104.104:8080→8080`, `10.0.0.1:8080→8080` | Up |
| `icinga-director` | `icinga/icingaweb2` | 2.13.0 | – (intern) | Up |
| `icingadb` | `icinga/icingadb` | 1.5.1 | – (intern) | Up |
| `icinga-redis` | `redis` | 7.4.9-alpine | – (intern) | Up (healthy) |
| `icinga-mysql` | `mariadb` | 10.7 | – (intern) | Up (healthy) |
| `grafana` | `grafana/grafana-oss` | 11.6.6 | `172.30.104.104:3000→3000`, `10.0.0.1:3000→3000` | Up |
| `loki` | `grafana/loki` | 3.7.2 | `127.0.0.1:3100→3100` | Up |
| `influxdb2` | `influxdb` | 2.7.12 | `127.0.0.1:8086→8086` | Up |
| `cloudflared` | `cloudflare/cloudflared` | latest | – | Up (separater Stack) |

> Veraltete Test-Container (`*-test`) sind gestoppt (Exited).

---

## Netzwerk & Erreichbarkeit

### Host-Interfaces

| Interface | Adresse | Verwendung |
|---|---|---|
| `eno8303` | `172.30.104.104/24` | LAN (Monitoring-Netz) |
| `eno8403` | `172.30.8.100/24` | zweites LAN-Interface |
| `wg0` | `10.0.0.1/24` | WireGuard VPN |

### Externe Zugänge (nach innen gebunden)

| Dienst | URL | Erreichbar über |
|---|---|---|
| Icinga Web 2 | `http://172.30.104.104:8080` | LAN |
| Icinga Web 2 | `http://10.0.0.1:8080` | WireGuard |
| Grafana | `http://172.30.104.104:3000` | LAN |
| Grafana | `http://10.0.0.1:3000` | WireGuard |
| Icinga 2 API | `https://<host>:5665` | alle Interfaces |
| InfluxDB UI | `http://localhost:8086` | nur localhost |
| Loki | `http://localhost:3100` | nur localhost |

### Externer Zugang via Cloudflare Tunnel

Der Container `cloudflared` stellt einen Cloudflare Tunnel bereit (Stack: `/opt/cloudflared/docker-compose.yml`). Damit sind ausgewählte Dienste ohne öffentliche Portfreigabe erreichbar (z.B. `monitoring.vn.internal`).

---

## Komponenten-Details

### Icinga 2 (Monitoring Engine)

- **Image:** Custom Build auf Basis `icinga/icinga2:2.14.6` (`Dockerfile` im Stack-Verzeichnis)
- **Rolle:** Master (Single-Node)
- **API-Port:** 5665 (öffentlich gebunden)
- **Konfiguration:** `/home/ciphron/docker-compose-icinga/icinga2.conf.d/` → gemountet nach `/etc/icinga2`

**Aktivierte Features:**

| Feature | Beschreibung |
|---|---|
| `api` | Icinga 2 REST API (accept_config/commands deaktiviert) |
| `checker` | Ausführung von Checks |
| `notification` | Benachrichtigungen |
| `icingadb` | IcingaDB-Connector (→ Redis auf `icingadb-redis:6379`) |
| `influxdb2` | Metriken-Export → InfluxDB (Bucket: `icinga`, Org: `monitor`) |

**InfluxDB2-Writer-Konfiguration:**
```
host = influxdb2, port = 8086
organization = monitor, bucket = icinga
flush_interval = 10s, flush_threshold = 1024
enable_send_metadata = true
Tags: hostname, service, command
```

**Zusätzliche Pakete im Custom Image:**
- Perl-Bibliotheken: `libwww-perl`, `libdatetime-perl`, `libjson-perl`, `libswitch-perl`, `cpanminus`
- Pakete: `monitoring-plugins-contrib`, `monitoring-plugins-common`, `nagios-snmp-plugins`
- Eigene Plugins aus `./plugins/` → `/usr/lib/nagios/plugins/`

**Icinga 2 Konfigurationsstruktur (`icinga2.conf.d/conf.d/`):**

| Datei | Inhalt |
|---|---|
| `hosts.conf` | Host-Definitionen |
| `services.conf` | Service-Definitionen |
| `commands.conf` | CheckCommand-Definitionen |
| `templates.conf` | Host-/Service-Templates |
| `notifications.conf` | Benachrichtigungs-Objekte |
| `master_notifications.conf` | Notification-Apply-Regeln |
| `master_teams_command.conf` | Microsoft Teams Notification Command |
| `master_teams_config.conf` | Teams-Kanal-Konfiguration |
| `users.conf` | Icinga-User-Objekte |
| `groups.conf` | Host- und Service-Gruppen |
| `timeperiods.conf` | Zeitperioden |
| `downtimes.conf` | Planned Downtimes |
| `api-users.conf` | API-User-Definitionen |

### IcingaDB

- Synchronisiert Icinga-2-Daten zwischen Redis und MariaDB
- Redis-Host: `icingadb-redis:6379`
- Datenbank: `icingadb` auf `icinga-mysql`

### Icinga Director

- Läuft als separater Container (gleiche IcingaWeb2-Image)
- Startet automatisch Migrations und Kickstart beim Hochfahren
- Datenbank: `director` auf `icinga-mysql`
- Verbindet sich zur Icinga-2-API auf `icinga2:5665`

### Icinga Web 2

- Aktivierte Module: `director`, `icingadb`, `incubator`, `grafana`
- Grafana-Modul via `icingaweb2-module-grafana` (gemountet aus `./modules/`)
- Authentifizierung: Datenbank-Backend (`icingaweb`-DB)
- Admin-User: `icingaadmin`

### MariaDB (`icinga-mysql`)

Drei Datenbanken, automatisch initialisiert via `env/mysql/init-mysql.sh`:

| Datenbank | Benutzer | Verwendung |
|---|---|---|
| `icingadb` | `icingadb` | IcingaDB State-Daten |
| `icingaweb` | `icingaweb` | IcingaWeb2 Konfiguration & Auth |
| `director` | `director` | Icinga Director Konfiguration |

### Grafana

- **Image:** `grafana/grafana-oss:11.6.6`
- **Root URL:** `http://monitoring.vn.internal:3000`
- **Anonymer Zugriff:** aktiviert (read-only)
- **Embedding:** aktiviert (`GF_SECURITY_ALLOW_EMBEDDING=1`, für IcingaWeb2-Grafana-Modul)
- **Timezone:** Europe/Berlin
- **Datenquellen:** InfluxDB 2 (Metriken), Loki (Logs)
- **Persistenz:** Docker-Volume `grafana`

### Loki (Log Aggregation)

- **Image:** `grafana/loki:3.7.2`
- **Config:** `/home/ciphron/docker-compose-icinga/loki/loki.yml`
- **Port:** `127.0.0.1:3100` (nur localhost)
- **Storage:** Filesystem (`/loki/chunks`, `/loki/rules`) → Volume `loki-data`
- **Schema:** v13 (TSDB), ab 2024-01-01
- **Retention:** 30 Tage (720h)
- **Ingestion-Limit:** 16 MB/s, Burst 32 MB/s
- **Kompaktierung:** alle 10 Minuten, Lösch-Delay 2h

**Loki-Integration Fluentbit (Firewall-Logs):**  
Syslog-Eingabe (UDP 5140) → Fluentbit-Parser → Loki-Labels.  
Watchguard-Firewall-Logs werden per Regex-Parser in strukturierte Felder extrahiert:  
`msg_id`, `action` (Allow/Deny), `src_ip`, `src_port`, `dst_ip`, `dst_port`, `protocol`

### InfluxDB 2

- **Image:** `influxdb:2.7.12`
- **Port:** `127.0.0.1:8086` (nur localhost)
- **Organisation:** `monitor`
- **Standard-Bucket:** `icinga`
- **Persistenz:** Volumes `influx-data`, `influx-config`
- Daten kommen vom Icinga-2-`Influxdb2Writer`

### Cloudflared (Cloudflare Tunnel)

- **Stack:** `/opt/cloudflared/docker-compose.yml`
- Läuft als User `nobody` (UID 65534), read-only Filesystem
- Hardened: `no-new-privileges`, alle Capabilities gedroppt
- Stellt externen Zugang zu internen Diensten ohne offene Ports bereit

---

## Plugins

### Im Custom-Image enthaltene Plugins (`./plugins/`)

| Plugin | Beschreibung |
|---|---|
| `check_netstat.pl` | Netzwerkverbindungen prüfen (Perl) |
| `check_snmp_synology` | Synology NAS via SNMP überwachen |

### Externe Plugins auf dem Host (`/opt/icinga-plugins/`)

Gemountet in `icinga2` nach `/usr/lib/nagios/icinga-plugins`:

| Plugin | Beschreibung |
|---|---|
| `check_hp_msm.sh` | HP MSM WLAN-Controller Checks |
| `check_snmp_temperature.pl` | SNMP-Temperaturüberwachung |
| `check_watchguard_vpn_clients.sh` | WatchGuard VPN-Client-Zählung via SNMP |

Weitere Plugins aus `vnit-infra-monitoring-plugins/` werden bei Bedarf manuell nach `/opt/icinga-plugins/` deployt.

---

## Volumes

| Volume | Pfad im Container | Inhalt |
|---|---|---|
| `icinga2` | `/data` (icinga2) | Icinga 2 Laufzeitdaten |
| `icingaweb` | `/data` (icingaweb2, director) | IcingaWeb2 Konfiguration |
| `mysql` | `/var/lib/mysql` | MariaDB Datenbankdateien |
| `grafana` | `/var/lib/grafana` | Grafana Dashboards & Einstellungen |
| `influx-data` | `/var/lib/influxdb2` | InfluxDB Zeitreihendaten |
| `influx-config` | `/etc/influxdb2` | InfluxDB Konfiguration |
| `loki-data` | `/loki` | Loki Log-Daten |

Host-Bind-Mounts:

| Host-Pfad | Container-Pfad | Container |
|---|---|---|
| `/opt/icinga-plugins` | `/usr/lib/nagios/icinga-plugins` | icinga2 |
| `./icinga2.conf.d` | `/etc/icinga2` | icinga2 |

---

## Logging (Container)

Alle Container: `json-file`-Driver mit Rotation.

| Container-Gruppe | max-size | max-file |
|---|---|---|
| Icinga-Stack | 1 MB | 10 |
| Loki | 10 MB | 3 |

---

## Konfigurationsdateien (Stack-Verzeichnis)

```
/home/ciphron/docker-compose-icinga/
├── docker-compose.yml              # Stack-Definition
├── Dockerfile                      # Custom Icinga 2 Image
├── .env                            # Secrets (nicht ins Repo!)
├── db.env                          # Grafana DB-Zugangsdaten
├── icinga2.conf.d/                 # Icinga 2 Konfiguration (→ /etc/icinga2)
│   ├── conf.d/                     # Hosts, Services, Commands, etc.
│   ├── features-available/         # Verfügbare Features
│   └── features-enabled/           # Aktivierte Features (Symlinks)
├── icinga2-feature.d/              # Backup-/Alternative Feature-Configs
├── icingadb.conf                   # IcingaDB-Feature-Konfiguration
├── icingaweb-api-user.conf         # API-User für IcingaWeb
├── init-icinga2.sh                 # Init-Skript
├── env/mysql/init-mysql.sh         # DB-Initialisierung beim ersten Start
├── loki/loki.yml                   # Loki Konfiguration
├── modules/
│   └── icingaweb2-module-grafana/  # Grafana-Modul für IcingaWeb2
└── plugins/                        # Im Custom-Image enthaltene Plugins
```

```
/opt/cloudflared/
└── docker-compose.yml              # Cloudflared Tunnel Stack
```

---

## Stack-Verwaltung

```bash
cd /home/ciphron/docker-compose-icinga

# Stack starten
sudo docker compose up -d

# Stack starten + Image neu bauen
sudo docker compose up -d --build

# Status prüfen
sudo docker compose ps

# Logs eines Containers anzeigen
sudo docker logs -f icinga2

# Stack stoppen
sudo docker compose down

# Stack komplett zurücksetzen (ALLE DATEN WERDEN GELÖSCHT)
sudo docker compose down --volumes && sudo docker compose up -d --build
```

---

## Umgebungsvariablen (`.env`)

```dotenv
ICINGA_ADMIN_PASSWORD=
ICINGADB_MYSQL_PASSWORD=
ICINGAWEB_ICINGA2_API_USER_PASSWORD=
ICINGAWEB_MYSQL_PASSWORD=
ICINGA_DIRECTOR_MYSQL_PASSWORD=
MYSQL_ROOT_PASSWORD=

INFLUXDB_INIT_USERNAME=
INFLUXDB_INIT_PASSWORD=
INFLUXDB_INIT_ADMIN_TOKEN=
```

---

## Weiterführende Dokumentation

- [grafana_wp.md](grafana_wp.md) – Grafana WordPress-Dashboard
- [wp_http_check.md](wp_http_check.md) – WordPress HTTP-Checks
- [plugin_standard_icinga_nagios.md](plugin_standard_icinga_nagios.md) – Plugin-Standards
- `/home/ciphron/docker-compose-icinga/README.md` – Stack-README
- `/home/ciphron/docker-compose-icinga/Logging.md` – Fluentbit/Loki Log-Setup
