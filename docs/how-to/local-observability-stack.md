# Local observability stack (OTel → GreptimeDB/Loki/Tempo → Grafana)

`docker compose up -d greptimedb tempo loki otel_collector grafana` starts the
local observability stack used when instrumenting Cadence with OpenTelemetry.

## Topology

One backend per signal; Grafana's drilldown apps each query their own backend:

```
                                       ┌─OTLP (metrics)──▶ greptimedb ◀─┐
Cadence apps ──OTLP──▶ otel_collector ─┼─OTLP (logs)─────▶ loki ◀───────┼─ grafana
                                       └─OTLP (traces)───▶ tempo ◀──────┘
```

| Service | Image | Host ports |
| --- | --- | --- |
| `otel_collector` | `otel/opentelemetry-collector-contrib` | 4317 (OTLP gRPC), 4318 (OTLP HTTP) |
| `greptimedb` | `greptime/greptimedb` (standalone) | 4000 (HTTP: SQL, PromQL, web UI), 4002 (MySQL), 4003 (Postgres) |
| `loki` | `grafana/loki` (monolithic) | 3100 (query API) |
| `tempo` | `grafana/tempo` (monolithic) | 3200 (query API) |
| `grafana` | `grafana/grafana` | 3000 (UI, anonymous admin — no login) |

The split exists because Grafana's queryless Drilldown apps are wired to
Grafana's own backends: Logs Drilldown requires Loki (LogQL), Traces Drilldown
requires Tempo (TraceQL). Metrics Drilldown accepts any Prometheus-type
datasource, which GreptimeDB's PromQL endpoint satisfies — so metrics stay in
GreptimeDB. Tempo is pinned to 2.x because Tempo 3 moved TraceQL metrics
behind its Kafka-based live-store, which is too heavy for local dev.

GreptimeDB's gRPC port (4001) is intentionally not published: it would collide
with the Phoenix dev server, and only in-network services need it.

## Pointing the apps at it

Export OTLP from the BEAM to the collector:

```
OTEL_SERVICE_NAME=cadence \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=development \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
mix phx.server
```

Cadence uses OTLP/HTTP and appends the standard `/v1/traces` and `/v1/logs`
signal paths to the configured endpoint. When `OTEL_EXPORTER_OTLP_ENDPOINT` is
absent or empty, network exporting is disabled and Cadence runs without an
exporter.

- Bandit spans cover the complete HTTP request lifecycle.
- Phoenix adds route and LiveView spans.
- Ecto adds query spans without recording SQL statements.
- A bounded Logger handler sends batched OTLP protobuf records to the collector.

Operational instrumentation lives under `Cadence.Observability` and
`CadenceWeb.Observability`. `Cadence.Telemetry` remains reserved for spacecraft
telemetry.

### Provider telemetry ingress traces

The provider ingress executor propagates trace context across its asynchronous
queue:

- `cadence.telemetry.ingress.enqueue` is the producer span.
- `cadence.telemetry.ingress.process` is its consumer child.
- `cadence.telemetry.ingress.resolve`, `.runtime`, and `.extract_samples` are
  processing stages. `.record_current_values` appears when that hot path runs.
- `cadence.telemetry.ingress.persist_batch` is a separate consumer trace. A
  persistence batch can combine several processing traces, so it links to every
  contributing processing span instead of choosing an arbitrary parent.

The spans record stable IDs, protocol/direction, bounded counts and sizes, and
queue-wait durations. They intentionally do not record raw packet bytes,
arbitrary provider metadata, or SQL statements.

### Logs and span events

When a log is emitted inside an active span, the OTel runtime adds
`otel_trace_id`, `otel_span_id`, and trace flags to Logger metadata. Cadence's
Logger handler converts the event to an OTLP `LogRecord`, batches it off the
calling process, and sends protobuf over HTTP to the collector. The same fields
also remain visible in console output.

The bridge is bounded and fail-open: clients only send a message to the worker,
the in-memory queue has a fixed ceiling, exports use short retries, and an
unavailable collector does not take down Cadence. Arbitrary Logger metadata is
not exported; only trace context, code location, request ID, `cadence_event`,
bounded domain IDs, and error class cross the network.

`OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` can override the complete logs URL. Otherwise
Cadence uses `OTEL_EXPORTER_OTLP_ENDPOINT` plus `/v1/logs`. Optional tuning:

- `CADENCE_OTEL_LOG_LEVEL` (default `info`)
- `CADENCE_OTEL_LOG_BATCH_SIZE` (default `100`)
- `CADENCE_OTEL_LOG_FLUSH_INTERVAL_MS` (default `1000`)
- `CADENCE_OTEL_LOG_MAX_QUEUE` (default `5000`)
- `OTEL_EXPORTER_OTLP_LOGS_TIMEOUT` (default `5000`)

Provider ingress uses stable event names for meaningful points within a span:

- `cadence.telemetry.ingress.accepted` and `.rejected`
- `cadence.telemetry.ingress.processed` and `.failed`
- `cadence.telemetry.ingress.anomalies_detected`
- `cadence.telemetry.ingress.batch_persisted` and `.persistence_failed`

Failures emit both a span event and a correlated structured log. Error
attributes contain a bounded class, not an inspected provider response or raw
telemetry. Successful high-volume work remains a span event rather than a log
line to avoid turning normal ingress into log noise.

The collector routes each signal to its backend (config at
`dev/otel-collector/config.yaml`): metrics land in GreptimeDB's `public`
database (one table per metric, queryable via PromQL), logs go to Loki's
native OTLP ingest (`service.name` becomes the `service_name` index label),
and traces go to Tempo.

## Grafana

Provisioned datasources (`dev/grafana/provisioning/datasources/greptimedb.yaml`),
one per drilldown app:

- **Prometheus (GreptimeDB)** (default) — GreptimeDB's `/v1/prometheus`
  endpoint. Backs the **Metrics Drilldown** app (Drilldown → Metrics).
- **Loki** — backs the **Logs Drilldown** app (Drilldown → Logs).
- **Tempo** — backs the **Traces Drilldown** app (Drilldown → Traces),
  including its RED metrics (served by Tempo's `local-blocks` processor).

## Direct GreptimeDB access

- Web UI: <http://localhost:4000/dashboard>
- SQL over HTTP: `curl -X POST 'localhost:4000/v1/sql?db=public' -d 'sql=show tables'`
- psql: `psql -h 127.0.0.1 -p 4003 -d public`

Data persists in `./var/greptimedb`, `./var/loki`, `./var/tempo`, and
`./var/grafana`; delete those directories for a clean slate.
