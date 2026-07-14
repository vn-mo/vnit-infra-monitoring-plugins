# Plugin Templates (Icinga/Nagios)

Diese Vorlagen sind fuer neue Checks in diesem Repo gedacht und orientieren sich an den verbindlichen Regeln aus:

- ../doc/plugin_standard_icinga_nagios.md

## Dateien

- check_template.sh: Bash-Vorlage fuer einfache Checks
- check_template.py: Python-Vorlage mit vollstaendiger Threshold-Range-Logik

## Schnellstart

1. Datei kopieren und umbenennen, z.B. nach `check_vpn_clients.sh` oder `check_vpn_clients.py`.
2. Messwert-Ermittlung in `collect_metric()` bzw. im markierten Bash-Abschnitt einbauen.
3. Standard-Optionen beibehalten: `-h -V -v -t -w -c`.
4. Perfdata ausgeben: `'label'=value[UOM];warn;crit;min;max`.
5. Exit-Codes strikt einhalten: 0/1/2/3.

## Ausfuehrbar machen

```bash
chmod +x templates/check_template.sh templates/check_template.py
```
