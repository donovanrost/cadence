#!/usr/bin/env python3
"""Pump synthetic OTLP telemetry into the local observability stack.

Sends correlated traces (multi-span, with span events and occasional errors),
logs (trace-correlated, mixed severities), and metrics (gauge + counter +
histogram) for a handful of fake Cadence services to the OTel collector at
localhost:4318. Backfills the recent past so Grafana range queries and the
drilldown apps have data immediately.

Usage: python3 scripts/synthetic_telemetry.py [--minutes 30] [--traces 150]
"""

import argparse
import json
import os
import random
import time
import urllib.request

OTLP = "http://localhost:4318"

SERVICES = {
    "cadence-web": [
        ("GET /ops/contacts", ["Cadence.Contacts.list_contacts", "SELECT contacts"]),
        ("GET /ops/schedule", ["Cadence.Scheduling.upcoming_passes", "SELECT passes"]),
        ("POST /api/commands", ["Cadence.Commands.enqueue", "INSERT command_queue"]),
    ],
    "cadence-core": [
        ("provider.reserve_contact", ["ProviderClient.request", "Reconciler.apply"]),
        ("telemetry.ingest_frame", ["FrameDecoder.decode", "QuestDB.write_batch"]),
        ("pass.execute", ["Uplink.transmit", "Downlink.capture", "QuestDB.write_batch"]),
    ],
    "cadence-simulator": [
        ("provider.simulate_pass", ["GroundStation.acquire", "GroundStation.release"]),
        ("provider.admin_sync", ["Registry.refresh"]),
    ],
}

LOG_LINES = [
    (9, "INFO", "contact reservation confirmed by provider"),
    (9, "INFO", "pass window opened, beginning acquisition"),
    (9, "INFO", "telemetry frame batch persisted"),
    (5, "DEBUG", "provider heartbeat ok"),
    (13, "WARN", "provider response latency above threshold"),
    (13, "WARN", "retrying reservation reconciliation"),
    (17, "ERROR", "provider rejected reservation: window overlap"),
    (17, "ERROR", "frame decode failed: bad sync marker"),
]


def post(path, payload):
    req = urllib.request.Request(
        OTLP + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        assert resp.status == 200, f"{path} -> {resp.status}"


def rid():
    return os.urandom(8).hex()


def resource(service):
    return {
        "attributes": [
            {"key": "service.name", "value": {"stringValue": service}},
            {"key": "deployment.environment", "value": {"stringValue": "dev"}},
        ]
    }


def make_trace(service, root_name, child_names, start_ns):
    """Build one trace; returns (spans, log_records, is_error, duration_ms)."""
    trace_id = os.urandom(16).hex()
    root_span_id = rid()
    is_error = random.random() < 0.08
    slow = random.random() < 0.15
    base = random.uniform(30, 120) * (8 if slow else 1)

    spans, logs, cursor = [], [], start_ns
    child_budget = 0
    children = []
    for name in child_names:
        dur = int(base * random.uniform(0.2, 0.5) * 1e6)
        children.append((name, cursor, dur))
        cursor += dur + int(random.uniform(1, 5) * 1e6)
        child_budget += dur

    root_end = start_ns + child_budget + int(base * 0.3 * 1e6)
    duration_ms = (root_end - start_ns) / 1e6

    for i, (name, s, dur) in enumerate(children):
        span_id = rid()
        failed = is_error and i == len(children) - 1
        span = {
            "traceId": trace_id,
            "spanId": span_id,
            "parentSpanId": root_span_id,
            "name": name,
            "kind": 3,
            "startTimeUnixNano": str(s),
            "endTimeUnixNano": str(s + dur),
            "attributes": [
                {"key": "cadence.tenant", "value": {"stringValue": random.choice(["acme-sat", "orbital-x", "polar-obs"])}},
            ],
            "status": {"code": 2 if failed else 1},
        }
        if failed:
            span["events"] = [{
                "timeUnixNano": str(s + dur - 1000),
                "name": "exception",
                "attributes": [
                    {"key": "exception.type", "value": {"stringValue": "Cadence.ProviderError"}},
                    {"key": "exception.message", "value": {"stringValue": "provider rejected reservation: window overlap"}},
                ],
            }]
        else:
            span["events"] = [{
                "timeUnixNano": str(s + dur // 2),
                "name": "processing",
                "attributes": [{"key": "batch.size", "value": {"intValue": str(random.randint(4, 96))}}],
            }]
        spans.append(span)

    spans.append({
        "traceId": trace_id,
        "spanId": root_span_id,
        "name": root_name,
        "kind": 2,
        "startTimeUnixNano": str(start_ns),
        "endTimeUnixNano": str(root_end),
        "attributes": [
            {"key": "cadence.tenant", "value": {"stringValue": "acme-sat"}},
        ],
        "status": {"code": 2 if is_error else 1},
    })

    weight, sev, body = random.choice(LOG_LINES)
    if is_error:
        weight, sev, body = 17, "ERROR", "provider rejected reservation: window overlap"
    logs.append({
        "timeUnixNano": str(start_ns + 1000),
        "severityNumber": weight,
        "severityText": sev,
        "body": {"stringValue": f"{body} (op={root_name})"},
        "traceId": trace_id,
        "spanId": root_span_id,
        "attributes": [
            {"key": "operation", "value": {"stringValue": root_name}},
        ],
    })
    return spans, logs, is_error, duration_ms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=int, default=30, help="history window to backfill")
    ap.add_argument("--traces", type=int, default=150, help="number of traces")
    args = ap.parse_args()

    now_ns = int(time.time() * 1e9)
    window_ns = args.minutes * 60 * int(1e9)

    # --- traces + correlated logs ---
    total_spans = total_logs = errors = 0
    for service, ops in SERVICES.items():
        span_batch, log_batch = [], []
        n = args.traces // len(SERVICES)
        for _ in range(n):
            root_name, children = random.choice(ops)
            start = now_ns - random.randint(0, window_ns)
            spans, logs, is_error, _ = make_trace(service, root_name, children, start)
            span_batch.extend(spans)
            log_batch.extend(logs)
            errors += is_error
        # extra uncorrelated log chatter
        for _ in range(n * 2):
            weight, sev, body = random.choice(LOG_LINES)
            log_batch.append({
                "timeUnixNano": str(now_ns - random.randint(0, window_ns)),
                "severityNumber": weight,
                "severityText": sev,
                "body": {"stringValue": body},
            })
        post("/v1/traces", {"resourceSpans": [{"resource": resource(service), "scopeSpans": [{"spans": span_batch}]}]})
        post("/v1/logs", {"resourceLogs": [{"resource": resource(service), "scopeLogs": [{"logRecords": log_batch}]}]})
        total_spans += len(span_batch)
        total_logs += len(log_batch)

    # --- metrics: gauge, counter, histogram per service ---
    step_ns = 15 * int(1e9)
    total_points = 0
    for service in SERVICES:
        gauge_pts, sum_pts, hist_pts = [], [], []
        monotonic = 0
        t = now_ns - window_ns
        while t <= now_ns:
            gauge_pts.append({
                "asDouble": random.uniform(2, 40),
                "timeUnixNano": str(t),
                "attributes": [{"key": "queue", "value": {"stringValue": "contacts"}}],
            })
            monotonic += random.randint(1, 30)
            sum_pts.append({
                "asInt": str(monotonic),
                "startTimeUnixNano": str(now_ns - window_ns),
                "timeUnixNano": str(t),
            })
            lat = [random.uniform(5, 400) for _ in range(20)]
            bounds = [10, 25, 50, 100, 250, 500]
            counts = [0] * (len(bounds) + 1)
            for v in lat:
                for i, b in enumerate(bounds):
                    if v <= b:
                        counts[i] += 1
                        break
                else:
                    counts[-1] += 1
            hist_pts.append({
                "startTimeUnixNano": str(now_ns - window_ns),
                "timeUnixNano": str(t),
                "count": str(len(lat)),
                "sum": sum(lat),
                "bucketCounts": [str(c) for c in counts],
                "explicitBounds": bounds,
            })
            t += step_ns
        metrics = [
            {"name": "cadence_contact_queue_depth", "gauge": {"dataPoints": gauge_pts}},
            {"name": "cadence_frames_ingested_total",
             "sum": {"dataPoints": sum_pts, "aggregationTemporality": 2, "isMonotonic": True}},
            {"name": "cadence_provider_request_duration_ms",
             "histogram": {"dataPoints": hist_pts, "aggregationTemporality": 2}},
        ]
        post("/v1/metrics", {"resourceMetrics": [{"resource": resource(service), "scopeMetrics": [{"metrics": metrics}]}]})
        total_points += len(gauge_pts) + len(sum_pts) + len(hist_pts)

    print(f"sent {total_spans} spans across ~{args.traces} traces ({errors} error traces), "
          f"{total_logs} log records, {total_points} metric points "
          f"over the last {args.minutes} minutes for services: {', '.join(SERVICES)}")


if __name__ == "__main__":
    main()
