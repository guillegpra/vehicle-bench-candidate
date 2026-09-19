import json
import re


def _find_timestamp(log: str, pattern: str) -> float:
    regex = re.compile(
        rf"^\S+\s+([0-9]+\.[0-9]+)\s+.*{pattern}.*$",
        re.MULTILINE,
    )

    match = regex.search(log)

    if not match:
        raise AssertionError(f"Log record not found: {pattern}")

    return float(match.group(1))


def assert_command_forwarded_within(
    log: str,
    request_id: str,
    grpc_method: str,
    max_ms: int,
):
    queued = _find_timestamp(
        log,
        rf"CMD\s+INFO.*remote command received.*req={re.escape(request_id)}",
    )

    forwarded = _find_timestamp(
        log,
        rf"GRPC\s+INFO.*{re.escape(grpc_method)} ->.*req={re.escape(request_id)}",
    )

    elapsed_ms = (forwarded - queued) * 1000.0

    if elapsed_ms > int(max_ms):
        raise AssertionError(
            f"{grpc_method} for {request_id} was forwarded after "
            f"{elapsed_ms:.1f} ms; requirement is <= {max_ms} ms"
        )

    return elapsed_ms


def get_json_value_as_integer(document: str, key: str):
    value = json.loads(document)[key]
    if type(value) is not int:
        raise AssertionError(f"{key} must be an integer, got {value!r}")
    return value


def assert_heartbeat_sequence_timing(log: str, expected_period_s: float = 2.0,
                                     tolerance_s: float = 0.25):
    """Compare consecutive nominal responses; exclude gaps and process restarts.

    Subtract response latency to estimate request start times. The tolerance
    allows the bench scheduler's response-then-sleep loop and normal jitter.
    """
    samples = re.findall(
        r"^\S+\s+(\d+\.\d+)\s+\S+\s+TCU\s+HB\s+(?:DEBUG|WARN)\s+"
        r".*heartbeat (?:ok|latency above threshold)\s+seq=(\d+)\s+latency_ms=(\d+)",
        log, re.MULTILINE,
    )
    checked = 0
    for previous, current in zip(samples, samples[1:]):
        t0, seq0, latency0 = map(float, previous)
        t1, seq1, latency1 = map(float, current)
        if seq1 != seq0 + 1 or t1 <= t0:
            continue
        interval = (t1 - latency1 / 1000) - (t0 - latency0 / 1000)
        if abs(interval - float(expected_period_s)) > float(tolerance_s):
            raise AssertionError(
                f"Heartbeat {int(seq0)} -> {int(seq1)} period {interval:.3f}s; "
                f"expected {expected_period_s}s +/- {tolerance_s}s"
            )
        checked += 1
    if not checked:
        raise AssertionError("No consecutive heartbeat responses found for timing validation")
    return checked
