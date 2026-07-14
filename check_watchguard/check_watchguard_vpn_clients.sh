#!/usr/bin/env bash
set -uo pipefail

VERSION="1.0.0"
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

HOST=""
COMMUNITY="public"
SNMP_VERSION="2c"
LOCAL_IP=""
LOCAL_PORT="443"
WARNING=""
CRITICAL=""
TIMEOUT=10
VERBOSE=0

usage() {
  cat <<'EOF'
Usage: check_watchguard_vpn_clients.sh [OPTIONS]

Required:
  -H, --hostname HOST        Firewall address for SNMP
  -L, --local-ip IP          Local/listener IP to count on (e.g. 213.61.145.66)

Optional:
  -C, --community STRING     SNMP community (default: public)
  -S, --snmp-version VER     SNMP version (default: 2c)
  -p, --port PORT            Local listener port (default: 443)
  -w, --warning THRESH       Warning threshold (number)
  -c, --critical THRESH      Critical threshold (number)
  -t, --timeout SEC          Timeout in seconds (default: 10)
  -v, --verbose              Increase verbosity (repeatable)
  -V, --version              Show version
  -h, --help                 Show help

Output:
  STATUS: vpn_clients on <ip>:<port> = <count> | 'vpn_clients'=<count>;<warn>;<crit>;0;

Notes:
  Uses TCP-MIB tcpConnState table:
  1.3.6.1.2.1.6.13.1.1
  Counts entries in ESTABLISHED state (5) where local endpoint matches IP:PORT.
EOF
}

print_version() {
  echo "check_watchguard_vpn_clients.sh v${VERSION}"
}

unknown() {
  echo "UNKNOWN: $1"
  exit ${STATE_UNKNOWN}
}

is_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (a > b) print 1; else print 0 }'
}

on_timeout() {
  echo "UNKNOWN: Plugin timed out after ${TIMEOUT}s"
  exit ${STATE_UNKNOWN}
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -H|--hostname)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        HOST="$2"
        shift 2
        ;;
      -L|--local-ip)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        LOCAL_IP="$2"
        shift 2
        ;;
      -C|--community)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        COMMUNITY="$2"
        shift 2
        ;;
      -S|--snmp-version)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        SNMP_VERSION="$2"
        shift 2
        ;;
      -p|--port)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        LOCAL_PORT="$2"
        shift 2
        ;;
      -w|--warning)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        WARNING="$2"
        shift 2
        ;;
      -c|--critical)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        CRITICAL="$2"
        shift 2
        ;;
      -t|--timeout)
        [[ $# -lt 2 ]] && unknown "Missing value for $1"
        TIMEOUT="$2"
        shift 2
        ;;
      -v|--verbose)
        VERBOSE=$((VERBOSE + 1))
        shift
        ;;
      -V|--version)
        print_version
        exit ${STATE_UNKNOWN}
        ;;
      -h|--help)
        usage
        exit ${STATE_UNKNOWN}
        ;;
      *)
        unknown "Unknown argument: $1"
        ;;
    esac
  done

  [[ -n "$HOST" ]] || unknown "Missing required option -H/--hostname"
  [[ -n "$LOCAL_IP" ]] || unknown "Missing required option -L/--local-ip"
  is_number "$LOCAL_PORT" || unknown "Invalid port: ${LOCAL_PORT}"
  is_number "$TIMEOUT" || unknown "Invalid timeout: ${TIMEOUT}"
  [[ -n "$WARNING" ]] && ! is_number "$WARNING" && unknown "Invalid warning: ${WARNING}"
  [[ -n "$CRITICAL" ]] && ! is_number "$CRITICAL" && unknown "Invalid critical: ${CRITICAL}"
}

main() {
  parse_args "$@"

  trap on_timeout ALRM
  ( sleep "$TIMEOUT"; kill -s ALRM $$ >/dev/null 2>&1 ) &
  timer_pid=$!

  oid=".1.3.6.1.2.1.6.13.1.1"
  local_pattern="\\.${LOCAL_IP//./\\.}\\.${LOCAL_PORT}\\."

  cmd_output="$(snmpwalk -v"$SNMP_VERSION" -c "$COMMUNITY" -On "$HOST" "$oid" 2>&1)"
  rc=$?

  if [[ $rc -ne 0 ]]; then
    kill "$timer_pid" >/dev/null 2>&1 || true
    wait "$timer_pid" 2>/dev/null || true
    unknown "SNMP query failed: ${cmd_output}"
  fi

  count="$(printf '%s\n' "$cmd_output" | awk -v pat="$local_pattern" '
    $0 ~ pat && $NF == "5" { c++ }
    END { print c+0 }
  ')"

  if [[ $VERBOSE -ge 1 ]]; then
    matched_total="$(printf '%s\n' "$cmd_output" | awk -v pat="$local_pattern" '$0 ~ pat { c++ } END { print c+0 }')"
    echo "DEBUG: host=${HOST} local=${LOCAL_IP}:${LOCAL_PORT} matched=${matched_total} established=${count}"
  fi

  status="OK"
  code=$STATE_OK

  if [[ -n "$CRITICAL" ]] && [[ $(gt "$count" "$CRITICAL") -eq 1 ]]; then
    status="CRITICAL"
    code=$STATE_CRITICAL
  elif [[ -n "$WARNING" ]] && [[ $(gt "$count" "$WARNING") -eq 1 ]]; then
    status="WARNING"
    code=$STATE_WARNING
  fi

  perf="'vpn_clients'=${count};${WARNING};${CRITICAL};0;"
  echo "${status}: vpn_clients on ${LOCAL_IP}:${LOCAL_PORT} = ${count} | ${perf}"

  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" 2>/dev/null || true
  exit "$code"
}

main "$@"
