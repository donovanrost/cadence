# Cadence observability runbooks

These runbooks correspond to the provisioned **Cadence / SRE Overview**
dashboard and Grafana alert rules. Start with the dashboard at
`http://localhost:3000/d/cadence-sre-overview`, preserve its time range, and
use the Logs and Traces drilldown links for correlated evidence.

Cadence mission-health alerts are state-aware: telemetry silence is an incident
only while an active, live realized contact declares the
`telemetry_downlink` intent. Silence outside that state is nominal.

## HTTP error ratio

1. Split `http.server.request.duration` by `http.route`, method, status, and
   `error.type`; do not use raw paths because IDs would create unbounded series.
2. Open a representative failed request trace and inspect its child database and
   LiveView spans.
3. Pivot to Loki using the trace ID. Look for a bounded `cadence_event` and
   `error_class`, then verify whether the failure is isolated to one route or
   shared infrastructure.
4. If database latency rose first, inspect database availability and pool
   saturation. If BEAM run queue or process utilization rose first, reduce
   incoming work or add capacity before restarting healthy processes.

## Expected telemetry is stale

1. Confirm `cadence.telemetry.expected == 1` and
   `cadence.contact.expected > 0` for the mission. If not, the alert query or
   contact projection is wrong; telemetry silence itself is nominal.
2. Check `cadence.telemetry.ingress.evidence`, packets, frames, samples, and
   processing duration. A flat evidence rate points upstream; evidence without
   samples points to protocol processing.
3. Inspect ingress and persistence queue depth, backpressure, queue wait, and
   persistence errors. Growing queues indicate downstream saturation rather
   than provider silence.
4. Check provider poll outcomes and the active contact realization. Use the
   mission ID to narrow the time range, then pivot to traces/logs for individual
   contact, provider-binding, path, or evidence IDs.
5. Do not add those IDs as metric labels. They belong in traces and logs.

## Command deadline missed

1. Filter `cadence.commanding.deadline.result{outcome="missed"}` by mission and
   compare it with pending count and oldest eligible age.
2. Check lane dispatch results, scheduled wait reasons, and verifier timeout
   rate.
3. Inspect the command trace/log using its command ID. Determine whether it was
   held by `not_before`, contact availability, a dispatch failure, or a verifier
   timeout.
4. Confirm the contact scheduler has an active command-capable contact before
   retrying. Do not release a command manually without the mission operator's
   authorization.

## Ingress backpressure

1. Identify whether the executor or persistence projector queue is growing.
2. Compare ingress processing duration with persistence duration and queue wait.
3. Check BEAM memory, scheduler run queue, process utilization, database latency,
   and database errors.
4. Reduce provider intake only when the bounded queues are not recovering.
   Restarting Cadence does not fix a slow database or an overloaded downstream
   service and may discard in-memory queue contents.

## Observability export failures

1. Compare exporter queue size with capacity and inspect metric series in flight.
2. Check the collector health and logs:

   ```sh
   docker compose ps otel_collector
   docker compose logs --since=10m otel_collector
   ```

3. Check GreptimeDB, Loki, and Tempo independently. One unhealthy backend should
   not make Cadence unavailable; exporters are bounded and fail open.
4. Restore the backend or collector, then confirm queues drain and successful
   export counters resume. Cadence retains bounded pending metric series and
   retries transient OTLP failures.

## Useful recording queries

The local stack has no Prometheus rule evaluator, so dashboards and Grafana
alerts use these expressions directly. A production Prometheus-compatible
backend should record them at one-minute resolution:

| Suggested record | Expression |
| --- | --- |
| `cadence:http_error_ratio5m` | `sum(rate(http_server_request_duration_seconds_count{error_type!=""}[5m])) / clamp_min(sum(rate(http_server_request_duration_seconds_count[5m])), 1)` |
| `cadence:http_latency_p95_5m` | `histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket[5m])))` |
| `cadence:expected_telemetry_miss_ratio15m` | `sum(rate(cadence_telemetry_availability_interval_total{outcome="missed"}[15m])) / clamp_min(sum(rate(cadence_telemetry_availability_interval_total[15m])), 1)` |
| `cadence:persistence_latency_p95_5m` | `histogram_quantile(0.95, sum by (le) (rate(cadence_telemetry_persistence_duration_seconds_bucket[5m])))` |
| `cadence:otel_export_failure_rate5m` | `sum(rate(otel_sdk_exporter_log_exported_total{error_type!=""}[5m])) + sum(rate(otel_sdk_exporter_metric_data_point_exported_total{error_type!=""}[5m]))` |

## Baseline objectives

Treat these as initial operating thresholds to tune with production traffic:

- HTTP failed-request ratio below 2% over 10 minutes.
- Expected-contact telemetry freshness no older than 30 seconds for 2 minutes.
- No command deadline misses.
- No sustained ingress backpressure for 5 minutes.
- No sustained OTLP export failures for 5 minutes.

Alert on sustained symptoms that require action. Keep nominal contact absence,
single transient retries, and successful high-volume work visible on dashboards
without paging.
