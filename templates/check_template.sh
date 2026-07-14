#!/usr/bin/env bash
set -uo pipefail

VERSION="1.0.0"
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

VERBOSE=0
TIMEOUT=10
WARNING=""
CRITICAL=""

usage() {
  cat <<'EOF'
Usage: check_template.sh [OPTIONS]

Options:
  -h, --help                Show help
  -V, --version             Show version
  -v, --verbose             Increase verbosity (repeatable)
  -t, --timeout SEC         Timeout in seconds (default: 10)
  -w, --warning THRESH      Warning threshold (single number)
  -c, --critical THRESH     Critical threshold (single number)

Output format:
  STATUS: message | 'metric'=value;warn;crit;min;max
EOF
}

print_version() {
  echo "check_template.sh v${VERSION}"
}

fail_unknown() {
  local msg="$1"
  echo "UNKNOWN: ${msg}"
  exit ${STATE_UNKNOWN}
}

on_timeout() {
  echo "UNKNOWN: Plugin timed out after ${TIMEOUT}s"
  exit ${STATE_UNKNOWN}
}

is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

cmp_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (a > b) print 1; else print 0 }'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit ${STATE_UNKNOWN}
        ;;
      -V|--version)
        print_version
        exit ${STATE_UNKNOWN}
        ;;
      -v|--verbose)
        VERBOSE=$((VERBOSE + 1))
        shift
        ;;
      -t|--timeout)
        [[ $# -lt 2 ]] && fail_unknown "Missing value for $1"
        TIMEOUT="$2"
        shift 2
        ;;
      -w|--warning)
        [[ $# -lt 2 ]] && fail_unknown "Missing value for $1"
        WARNING="$2"
        shift 2
        ;;
      -c|--critical)
        [[ $# -lt 2 ]] && fail_unknown "Missing value for $1"
        CRITICAL="$2"
        shift 2
        ;;
      *)
        fail_unknown "Unknown argument: $1"
        ;;
    esac
  done

  is_number "$TIMEOUT" || fail_unknown "Invalid timeout: ${TIMEOUT}"
  [[ -n "$WARNING" ]] && ! is_number "$WARNING" && fail_unknown "Invalid warning threshold: ${WARNING}"
  [[ -n "$CRITICAL" ]] && ! is_number "$CRITICAL" && fail_unknown "Invalid critical threshold: ${CRITICAL}"
}

main() {
  parse_args "$@"

  trap on_timeout ALRM
  alarm_seconds=$(printf '%.0f' "$TIMEOUT")
  (( alarm_seconds > 0 )) || fail_unknown "Timeout must be > 0"
  ( sleep "$alarm_seconds"; kill -s ALRM $$ >/dev/null 2>&1 ) &
  timer_pid=$!

  # TODO: Hier eigentliche Messung einbauen.
  # Beispiel-Messwert:
  metric_value=7
  metric_label="example_metric"
  metric_uom=""
  min="0"
  max=""

  if [[ $VERBOSE -ge 1 ]]; then
    echo "DEBUG: value=${metric_value} warning=${WARNING:-n/a} critical=${CRITICAL:-n/a}"
  fi

  status="OK"
  code=$STATE_OK

  if [[ -n "$CRITICAL" ]] && [[ $(cmp_gt "$metric_value" "$CRITICAL") -eq 1 ]]; then
    status="CRITICAL"
    code=$STATE_CRITICAL
  elif [[ -n "$WARNING" ]] && [[ $(cmp_gt "$metric_value" "$WARNING") -eq 1 ]]; then
    status="WARNING"
    code=$STATE_WARNING
  fi

  perf="'${metric_label}'=${metric_value}${metric_uom};${WARNING};${CRITICAL};${min};${max}"
  echo "${status}: ${metric_label}=${metric_value}${metric_uom} | ${perf}"

  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" 2>/dev/null || true
  exit "$code"
}

main "$@"
