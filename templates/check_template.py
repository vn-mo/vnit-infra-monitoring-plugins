#!/usr/bin/env python3
"""Icinga/Nagios plugin template with range thresholds and perfdata."""

from __future__ import annotations

import argparse
import math
import signal
import sys
from dataclasses import dataclass

VERSION = "1.0.0"
STATE_OK = 0
STATE_WARNING = 1
STATE_CRITICAL = 2
STATE_UNKNOWN = 3


class CheckError(Exception):
    pass


@dataclass
class RangeSpec:
    invert: bool
    start: float
    end: float


def parse_threshold(raw: str) -> RangeSpec:
    if raw is None or raw == "":
        raise CheckError("Empty threshold")

    invert = raw.startswith("@")
    body = raw[1:] if invert else raw

    if ":" in body:
        left, right = body.split(":", 1)
        start = 0.0 if left == "" else (-math.inf if left == "~" else float(left))
        end = math.inf if right == "" else float(right)
    else:
        start = 0.0
        end = float(body)

    if start > end:
        raise CheckError(f"Invalid threshold range (start > end): {raw}")

    return RangeSpec(invert=invert, start=start, end=end)


def threshold_match(value: float, spec: RangeSpec) -> bool:
    inside = spec.start <= value <= spec.end
    return inside if spec.invert else (not inside)


def timeout_handler(_signum, _frame):
    print("UNKNOWN: Plugin timed out", flush=True)
    raise SystemExit(STATE_UNKNOWN)


def collect_metric(_args: argparse.Namespace) -> float:
    # TODO: Eigentliche Messlogik hier implementieren.
    return 7.0


def main() -> int:
    parser = argparse.ArgumentParser(description="Icinga/Nagios plugin template")
    parser.add_argument("-V", "--version", action="store_true", help="Show version")
    parser.add_argument("-v", "--verbose", action="count", default=0, help="Increase verbosity")
    parser.add_argument("-t", "--timeout", type=int, default=10, help="Timeout in seconds")
    parser.add_argument("-w", "--warning", help="Warning threshold, e.g. 10 or 10:20 or @10:20")
    parser.add_argument("-c", "--critical", help="Critical threshold, e.g. 20 or 20: or ~:5")
    args = parser.parse_args()

    if args.version:
        print(f"check_template.py v{VERSION}")
        return STATE_UNKNOWN

    if args.timeout <= 0:
        print("UNKNOWN: Timeout must be > 0")
        return STATE_UNKNOWN

    signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(args.timeout)

    try:
        warning_spec = parse_threshold(args.warning) if args.warning else None
        critical_spec = parse_threshold(args.critical) if args.critical else None

        value = collect_metric(args)
        if not isinstance(value, (int, float)):
            raise CheckError("Metric value is not numeric")

        label = "example_metric"
        uom = ""
        min_value = "0"
        max_value = ""

        status = "OK"
        code = STATE_OK

        if critical_spec and threshold_match(value, critical_spec):
            status = "CRITICAL"
            code = STATE_CRITICAL
        elif warning_spec and threshold_match(value, warning_spec):
            status = "WARNING"
            code = STATE_WARNING

        warn_text = args.warning or ""
        crit_text = args.critical or ""
        perf = f"'{label}'={value}{uom};{warn_text};{crit_text};{min_value};{max_value}"

        print(f"{status}: {label}={value}{uom} | {perf}")
        if args.verbose and args.verbose >= 2:
            print(f"debug: warning={warn_text} critical={crit_text} value={value}")

        return code

    except ValueError as exc:
        print(f"UNKNOWN: Invalid numeric value: {exc}")
        return STATE_UNKNOWN
    except CheckError as exc:
        print(f"UNKNOWN: {exc}")
        return STATE_UNKNOWN
    except Exception as exc:  # pragma: no cover
        print(f"UNKNOWN: Unexpected error: {exc}")
        return STATE_UNKNOWN


if __name__ == "__main__":
    sys.exit(main())
