# Plugin-Standard fuer Icinga/Nagios (verbindlich)

Diese Richtlinie ist fuer dieses Repository verpflichtend.

Alle neu entwickelten oder geaenderten Icinga/Nagios-Plugins MUESSEN den offiziellen Plugin-Standards folgen.

## 1) Pflicht: Exit Codes

Plugin-Exit-Codes sind strikt einzuhalten:

- `0` = `OK`
- `1` = `WARNING`
- `2` = `CRITICAL`
- `3` = `UNKNOWN`

`UNKNOWN` nur bei ungueltigen Parametern oder Low-Level-Fehlern (z.B. interne I/O-Fehler, nicht ausfuehrbarer Check).

## 2) Pflicht: Plugin-Output (STDOUT)

- Ausgabe MUSS auf `STDOUT` erfolgen (nicht auf `STDERR`).
- Erste Zeile MUSS eine kurze, klare Zusammenfassung enthalten.
- Empfohlenes Format:

```text
<STATUS>: <Kurzbeschreibung> | 'label'=value[UOM];[warn];[crit];[min];[max]
```

- Mehrzeilige Ausgabe ist erlaubt, aber die erste Zeile bleibt die entscheidende Uebersicht fuer Listen/Alerts.

## 3) Pflicht: Performance Data

Wenn messbare Werte vorhanden sind, MUSS Perfdata mit ausgegeben werden.

- Format:

```text
'label'=value[UOM];[warn];[crit];[min];[max]
```

- Mehrere Metriken sind durch Leerzeichen getrennt.
- Labels duerfen kein `=` und kein `'` enthalten.
- Zahlenformat immer C/POSIX-kompatibel (Dezimalpunkt `.`).

## 4) Pflicht: Thresholds

- Plugins MUESSEN `-w/--warning` und `-c/--critical` unterstuetzen, wenn Schwellen sinnvoll sind.
- Reihenfolge der Bewertung: zuerst `critical`, dann `warning`, sonst `ok`.
- Bereichs-Syntax gemaess Standard unterstuetzen:

```text
[@]start:end
```

Beispiele:

- `10` -> Alert ausserhalb `0..10`
- `10:` -> Alert unter `10`
- `~:10` -> Alert ueber `10`
- `@10:20` -> Alert innerhalb `10..20`

## 5) Pflicht: Standard-Optionen

Jedes Plugin SOLL folgende Optionen bereitstellen:

- `-h/--help`
- `-V/--version`
- `-v/--verbose` (mehrfach moeglich)
- `-t/--timeout`
- `-w/--warning` (wenn Schwellen relevant)
- `-c/--critical` (wenn Schwellen relevant)

`--help` und `--version` sollen sauber ausgeben und mit `UNKNOWN (3)` beenden, wenn keine eigentliche Check-Ausfuehrung stattfindet.

## 6) Pflicht: Timeout-Verhalten

- Jeder Check MUSS intern ein Timeout haben (zusaeztlich zu Icinga-Timeouts).
- Bei Timeout: klare Meldung und `UNKNOWN (3)`.

## 7) Pflicht: Sichere Implementierung

- Alle Eingaben validieren.
- Externe Kommandos nur mit vollem Pfad aufrufen.
- Keine unnoetigen Temp-Dateien; falls unvermeidbar, robustes Fehlerhandling und Cleanup.

## 8) Pflicht: Icinga-Integration

- Plugin vor Integration immer direkt auf CLI testen (mit demselben User/Umfeld wie der spaetere Check).
- CheckCommand-Parameter konsistent benennen (Praefixschema `<command>_<parameter>` in Icinga-Konfiguration/Director).

## 9) Mindest-Qualitaet vor Merge

Ein Plugin-Change gilt nur als fertig, wenn:

- Exit-Codes korrekt sind.
- Erste Output-Zeile klar und alert-tauglich ist.
- Perfdata korrekt formatiert ist (falls Messwert vorhanden).
- Thresholds und Timeout testbar funktionieren.
- `--help` und `--version` vorhanden sind.
- Mindestens ein positiver und ein negativer Testfall dokumentiert ist.

## Offizielle Referenzen

- Monitoring Plugins Development Guidelines:
  https://www.monitoring-plugins.org/doc/guidelines.html
- Icinga 2 Service Monitoring / Plugin API:
  https://icinga.com/docs/icinga-2/latest/doc/05-service-monitoring/
- Nagios Plugins Development Guidelines:
  https://nagios-plugins.org/doc/guidelines.html
