# vnit-infra-monitoring-plugins - Agent Instructions

Diese Datei beschreibt, wie AI Coding Agents in diesem Repository sicher und effizient arbeiten.

## Projektzweck

- Bash- und Plugin-Skripte fuer Icinga2, Icinga Director und Grafana in der VNIT-Monitoring-Umgebung.
- Schwerpunkt: reproduzierbare API-Automation, robuste Nagios/Icinga-Plugins und dokumentierte Deploy-Ablaufe.

## Erst lesen (Link statt Duplikat)

- Stack-Architektur, Container, Netz, Ports: [doc/monitoring_setup.md](doc/monitoring_setup.md)
- Verbindlicher Plugin-Standard: [doc/plugin_standard_icinga_nagios.md](doc/plugin_standard_icinga_nagios.md)
- WP-HTTP-Check-Hintergrund: [doc/wp_http_check.md](doc/wp_http_check.md)
- Grafana-WP-Dashboard-Kontext: [doc/grafana_wp.md](doc/grafana_wp.md)
- Plugin-Templates: [templates/README.md](templates/README.md)

## Repo-Landkarte

- Director/Grafana Apply-Skripte: [applyWPHttpChecks.sh](applyWPHttpChecks.sh), [applyGrafanaWPDashboard.sh](applyGrafanaWPDashboard.sh), [applyNucleiWordpress.sh](applyNucleiWordpress.sh)
- Reporting-Scan (kein Nagios-Plugin): [checkWordpressExposure.sh](checkWordpressExposure.sh)
- API-Probe-Skripte: [getHosts.sh](getHosts.sh), [getHosts2.sh](getHosts2.sh), [getHosts3.sh](getHosts3.sh)
- Produktionsplugin WatchGuard: [check_watchguard/check_watchguard_vpn_clients.sh](check_watchguard/check_watchguard_vpn_clients.sh)
- MSM-Plugin-Artefakte: [check_msm/doc/check_hp_msm.sh](check_msm/doc/check_hp_msm.sh)

## Kritische Stolperfallen

- Auth strikt trennen:
  - Director API auf :8080 mit icingaadmin:vnit
  - Icinga2 API auf :5665 mit root:d04e0e3607dd5c8c
- Director-Endpunkte:
  - CheckCommand lesen via /director/command?name=...
  - Nicht /director/checkcommands verwenden
- Director Objekt-Lifecycle:
  - Neue Objekte mit POST
  - Updates mit PUT auf name-basierte URL
- Nach Director-Aenderungen immer deployen:
  - POST /director/config/deploy
- Historische Beispiele sind teils veraltet:
  - assign_filter/object_type=apply in dieser Umgebung vermeiden
  - bevorzugtes Muster siehe [applyWPHttpChecks.sh](applyWPHttpChecks.sh)

## Arbeitskonventionen fuer Agents

- Nur gezielte, kleine Aenderungen; keine grossflaechigen Refactors ohne Auftrag.
- Bei Plugin-Aenderungen immer den Standard aus [doc/plugin_standard_icinga_nagios.md](doc/plugin_standard_icinga_nagios.md) einhalten.
- Bei Aenderungen an Plugins unter check_*/ immer sofort live deployen: Skript nach /opt/icinga-plugins/ kopieren, chmod 755 setzen und innerhalb des Containers icinga2 unter /usr/lib/nagios/icinga-plugins/ verifizieren.
- Skriptstil beibehalten:
  - #!/usr/bin/env bash
  - set -uo pipefail
- Bei API-Automation idempotentes Verhalten anstreben und Fehler klar ausgeben.

## Schnellkommandos

- WP-Director-Objekte anwenden:
  - bash applyWPHttpChecks.sh
- WP-Exposure-Report ausfuehren:
  - bash checkWordpressExposure.sh
- Grafana-WP-Dashboard anwenden:
  - bash applyGrafanaWPDashboard.sh
- WatchGuard-Plugin-Hilfe:
  - bash check_watchguard/check_watchguard_vpn_clients.sh --help
- Template-Checks pruefen:
  - bash templates/check_template.sh --help
  - python3 templates/check_template.py --help

## Review-Checkliste vor Abschluss

- Sind verwendete API-Credentials und Endpunkte korrekt getrennt?
- Wurde nach Director-Aenderungen deployt?
- Erfuellt Plugin-Output Exit-Codes, Kurzstatus und Perfdata?
- Wurden bestehende Docs verlinkt statt neu zu duplizieren?

## Optionaler Ausbau

- Fuer wiederkehrende Director-Workflows lohnt sich eine eigene Skill-Datei unter .github/skills/director-apply/.
- Fuer Plugin-Qualitaetsgate lohnt sich ein Hook (PreToolUse/PostToolUse), der bei Plugin-Dateien auf Pflichtoptionen und Exit-Code-Muster prueft.
