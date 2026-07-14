# Plan: Grafana-Dashboard „Online" — Nuclei & WP Security Exposure ergänzen

## Ist-Zustand

**Dashboard:** `Online` (UID `a6b5988c-22f1-475f-856e-ab3e803df8e6`, Version 56)

### Struktur

| Element | Details |
|---|---|
| Row | `Websites Health` |
| Panel id=2 | `stat`-Panel, `repeat: getHostNames` (horizontal) |
| Query A | InfluxDB: measurement `http`, service `HTTPS` → Alias `$getHostNames` |
| Query B | InfluxDB: measurement `http`, service `HTTPS WP Admin reachable` → Alias `Backend` |

Jede Host-Kachel zeigt zwei Text-Blöcke übereinander: den Hostnamen mit HTTPS-Status und darunter „Backend OK/ERROR".

### Datasource

| Name | UID | Typ |
|---|---|---|
| `influxdb` | `fen9bl394jvuoc` | InfluxDB v1 (InfluxQL), DB: `icinga` |

### Bestätigte Measurements & Service-Tags (bereits Daten vorhanden)

| Check | Measurement | `service::tag` | Mögliche States |
|---|---|---|---|
| Nuclei (passiv) | `dummy` | `Nuclei` | 0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN |
| WP Security Exposure | `wp-exposure` | `WP Security Exposure` | 0=OK, 1=WARNING, 2=CRITICAL |

---

## Ziel

Pro Host-Kachel zwei weitere Text-Blöcke ergänzen:

```
┌────────────────────────────┐
│ www.example.de             │
│           OK               │  ← HTTPS (Query A, bereits vorhanden)
├────────────────────────────┤
│ Backend                    │
│           OK               │  ← HTTPS WP Admin (Query B, bereits vorhanden)
├────────────────────────────┤
│ Nuclei                     │
│           OK               │  ← NEU: Query C
├────────────────────────────┤
│ Exposure                   │
│           OK               │  ← NEU: Query D
└────────────────────────────┘
```

---

## Umsetzung

### 1. Zwei neue Queries an Panel id=2 anhängen

**Query C — Nuclei:**

```json
{
  "datasource": { "type": "influxdb", "uid": "fen9bl394jvuoc" },
  "refId": "C",
  "measurement": "dummy",
  "resultFormat": "table",
  "orderByTime": "ASC",
  "policy": "default",
  "groupBy": [
    { "type": "time", "params": ["$__interval"] },
    { "type": "fill", "params": ["null"] }
  ],
  "select": [[
    { "type": "field", "params": ["state"] },
    { "type": "last",  "params": [] },
    { "type": "alias", "params": ["Nuclei"] }
  ]],
  "tags": [
    { "key": "hostname::tag", "operator": "=~", "value": "/^$getHostNames$/" },
    { "condition": "AND", "key": "service::tag", "operator": "=", "value": "Nuclei" }
  ]
}
```

**Query D — WP Security Exposure:**

```json
{
  "datasource": { "type": "influxdb", "uid": "fen9bl394jvuoc" },
  "refId": "D",
  "measurement": "wp-exposure",
  "resultFormat": "table",
  "orderByTime": "ASC",
  "policy": "default",
  "groupBy": [
    { "type": "time", "params": ["$__interval"] },
    { "type": "fill", "params": ["null"] }
  ],
  "select": [[
    { "type": "field", "params": ["state"] },
    { "type": "last",  "params": [] },
    { "type": "alias", "params": ["Exposure"] }
  ]],
  "tags": [
    { "key": "hostname::tag", "operator": "=~", "value": "/^$getHostNames$/" },
    { "condition": "AND", "key": "service::tag", "operator": "=", "value": "WP Security Exposure" }
  ]
}
```

### 2. Value Mapping um WARNING ergänzen

Die bestehenden Mappings kennen 0=OK, 2=ERROR, 3=ERROR. State 1 (WARNING) fehlt und muss ergänzt werden:

```json
{
  "1": { "color": "orange", "index": 3, "text": "WARNING" }
}
```

Vollständiges `mappings`-Array nach der Änderung:

```json
"mappings": [
  {
    "type": "value",
    "options": {
      "0": { "color": "green",    "index": 1, "text": "OK"      },
      "1": { "color": "orange",   "index": 3, "text": "WARNING" },
      "2": { "color": "red",      "index": 0, "text": "ERROR"   },
      "3": { "color": "dark-red", "index": 2, "text": "ERROR"   }
    }
  }
]
```

### 3. `noValue`-Handling

Hosts, auf die das Template `Wordpress` nicht zutrifft, haben keinen Nuclei- oder Exposure-Datenpunkt. Damit die Kachel nicht leer/grau erscheint, im Panel-Feld `fieldConfig.defaults`:

```json
"noValue": "–"
```

Alternativ: `mappings` um `special` type für `null`-Werte erweitern:
```json
{ "type": "special", "options": { "match": "null", "result": { "text": "–", "color": "gray" } } }
```

---

## Grafana API — Dashboard-Update

Das gesamte Dashboard-JSON wird mit `POST /api/dashboards/db` überschrieben. Pflichtfelder:

```bash
curl -s \
  -H "Authorization: Bearer $(cat .creds_grafana)" \
  -H "Content-Type: application/json" \
  -X POST http://monitoring.vn.internal:3000/api/dashboards/db \
  -d '{
    "dashboard": { ...vollständiges Dashboard-JSON mit version+1... },
    "overwrite": false,
    "message": "Add Nuclei and WP Security Exposure panels"
  }'
```

- `version` muss auf **57** gesetzt werden (aktuell 56), sonst gibt die API `412 Precondition Failed`.
- `"overwrite": false` schützt vor Race Conditions.

---

## Alternativvariante: Separate Row „Security"

Statt die Queries in Panel id=2 einzubauen, können zwei eigenständige Repeat-Panels in einer neuen Row angelegt werden:

| Panel | Titel | Query | gridPos |
|---|---|---|---|
| Row | `Security` | — | y=5, h=1, w=24 |
| Stat-Panel | `Nuclei` | Query C (wie oben) | y=6, h=4, w=24, repeat=getHostNames |
| Stat-Panel | `WP Security Exposure` | Query D (wie oben) | y=10, h=4, w=24, repeat=getHostNames |

**Vorteil:** Sauber trennbar, eigene Überschriften, können unabhängig ein-/ausgeklappt werden.  
**Nachteil:** Drei separate Scroll-Bereiche statt einem kompakten Block pro Host.

**Empfehlung:** Zunächst Variante 1 (Queries C+D in Panel id=2) — gleiche Kompaktheit wie das bestehende Layout. Wenn der Block unübersichtlich wird, separate Row nachrüsten.

---

## Implementierungsreihenfolge

1. Aktuelles Dashboard-JSON laden: `GET /api/dashboards/uid/a6b5988c-22f1-475f-856e-ab3e803df8e6`
2. `panels[1].targets` um Query C und D erweitern
3. `panels[1].fieldConfig.defaults.mappings` um WARNING ergänzen
4. `panels[1].fieldConfig.defaults.noValue` auf `"–"` setzen
5. `dashboard.version` auf 57 setzen
6. Dashboard via `POST /api/dashboards/db` zurückschreiben

Das Skript dafür soll als `applyGrafanaWPDashboard.sh` angelegt werden.
