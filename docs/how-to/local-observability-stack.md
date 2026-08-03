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
CADENCE_TELEMETRY_CURRENT_VALUE_STORE=postgres \
mix phx.server
```

Cadence uses OTLP/HTTP and appends the standard `/v1/traces`, `/v1/metrics`, and `/v1/logs`
signal paths to the configured endpoint. When `OTEL_EXPORTER_OTLP_ENDPOINT` is
absent or empty, network exporting is disabled and Cadence runs without an
exporter.

## Exercise the full contact and telemetry path

After starting the observability stack and applying migrations, run the SRE
demo from the umbrella root:

```
mix ecto.migrate

OTEL_SERVICE_NAME=cadence-sre-demo \
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=development \
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
CADENCE_OTEL_METRICS_EXPORT_INTERVAL_MS=1000 \
CADENCE_OTEL_METRICS_SAMPLE_INTERVAL_MS=1000 \
CADENCE_OTEL_MISSION_HEALTH_INTERVAL_MS=1000 \
mix run --no-start dev/dashboard_ops_demo.exs
```

The script persists a uniquely named organization, mission, spacecraft, source
endpoint, packet binding, two published native dashboards, dashboard-management
assets, operational context, and a scheduled telemetry contact. The normal
contact scheduler realizes the contact, opens a real TCP downlink adapter on an
ephemeral port, and connects the Cadence simulator at 2 Hz. The resulting TM
frames travel through CCSDS extraction, ingress archives, current-value
projection, and telemetry persistence. See
[Run the Dashboard and Ops Demo](run-dashboard-ops-demo.md) for the presenter
walkthrough.

The standalone demo uses the Postgres compatibility ingress archive, protocol
record archive, and current-value backend. This keeps the shared live
projection's packet/evidence provenance intact while allowing the simulator
process and Phoenix process to see the same point values. Start Phoenix with
`CADENCE_TELEMETRY_CURRENT_VALUE_STORE=postgres` as shown above; the default ETS
backend is node-local and is appropriate only when ingestion and dashboard
reads happen in the same BEAM node.

Leave the command running while using the
[Cadence / SRE Overview](http://localhost:3000/d/cadence-sre-overview/cadence-sre-overview)
dashboard. Select `cadence-sre-demo` as the service and the mission ID printed by
the script. The script also prints the authenticated Cadence dashboard URL,
which contains live five-minute trends and current-value tiles for the APID 42
uptime and battery-voltage points. Press Ctrl-C twice to stop it.

Optional controls:

- `CADENCE_SRE_DEMO_RATE_HZ` (default `2.0`)
- `CADENCE_SRE_DEMO_CONTACT_SECONDS` (default `3600`)
- `CADENCE_SRE_DEMO_LOG_LEVEL` (default `info`)
- `CADENCE_SRE_DEMO_RUN_ID` (defaults to a unique integer; set it only when
  deliberately reusing the same persisted demo objects)

- Bandit spans cover the complete HTTP request lifecycle.
- Phoenix adds route and LiveView spans.
- Ecto adds query spans without recording SQL statements.
- A bounded Logger handler sends batched OTLP protobuf records to the collector.
- A bounded metrics reporter aggregates `:telemetry` events and periodic runtime
  samples, then sends OTLP protobuf metrics to the collector.

Operational instrumentation lives under `Cadence.Observability` and
`CadenceWeb.Observability`. `Cadence.Telemetry` remains reserved for spacecraft
telemetry.

### Metrics

The central metric contract is `Cadence.Observability.Metrics.Catalog`. It
includes HTTP and database golden signals, BEAM saturation, telemetry ingress
and persistence, commanding, contact scheduling, provider polling, background
jobs, and the observability exporters themselves.

Domain object IDs are intentionally excluded from metric dimensions. Mission ID
is permitted only on the bounded mission-health series. Command, contact,
provider binding, path, source endpoint, evidence, request, and trace IDs remain
available in logs and traces.

Mission health is state-aware. `cadence.telemetry.expected` becomes `1` only
while an active live realized contact includes `telemetry_downlink`. Availability
misses are recorded only in that state; silence outside an expected contact is
nominal.

Optional metrics tuning:

- `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` (complete metrics URL)
- `CADENCE_OTEL_METRICS_EXPORT_INTERVAL_MS` (default `10000`)
- `CADENCE_OTEL_METRICS_SAMPLE_INTERVAL_MS` (default `10000`)
- `CADENCE_OTEL_MISSION_HEALTH_INTERVAL_MS` (default `15000`)
- `CADENCE_TELEMETRY_FRESHNESS_GRACE_SECONDS` (default `30`)
- `CADENCE_OTEL_METRICS_MAX_QUEUE` (default `10000`)
- `CADENCE_OTEL_METRICS_MAX_SERIES` (default `5000`)
- `OTEL_EXPORTER_OTLP_METRICS_TIMEOUT` (default `5000`)

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

Grafana also provisions:

- **Cadence / SRE Overview** at
  <http://localhost:3000/d/cadence-sre-overview/cadence-sre-overview>.
- **Cadence / Ingress Load Test** at
  <http://localhost:3000/d/cadence-ingress-load-test/cadence-ingress-load-test>.
  It refreshes every five seconds and exposes bounded service, direction, and
  protocol filters plus an editable target-rate line. Its capture-journal row
  shows retained bytes versus capacity, independent processing/archive lag,
  the highest active journal utilization, admitted bitrate, and p50/p99 append
  latency split by the bounded durability profile.
- Alert rules for HTTP errors, expected-contact telemetry misses, command
  deadline misses, ingress backpressure, and OTLP export failures.
- Operator response guidance in
  [`cadence-observability-runbooks.md`](cadence-observability-runbooks.md).

## Direct GreptimeDB access

- Web UI: <http://localhost:4000/dashboard>
- SQL over HTTP: `curl -X POST 'localhost:4000/v1/sql?db=public' -d 'sql=show tables'`
- psql: `psql -h 127.0.0.1 -p 4003 -d public`

Data persists in `./var/greptimedb`, `./var/loki`, `./var/tempo`, and
`./var/grafana`; delete those directories for a clean slate.

When the laptop ingress overlay is included, those mutable data paths are
replaced with size-capped tmpfs mounts. The observability history is then
intentionally lost when the containers stop, and the host `./var` directories
are not used.

For a durable server, Compose, or Kubernetes deployment, enable the candidate
only with an explicitly provisioned filesystem:

- `CADENCE_INGRESS_JOURNAL_ENABLED=true`
- `CADENCE_INGRESS_JOURNAL_PATH=/mounted/cadence/ingress-journal`
- `CADENCE_INGRESS_JOURNAL_MAX_BYTES` (default 8 GiB)
- `CADENCE_INGRESS_JOURNAL_SEGMENT_BYTES` (default 256 MiB)
- `CADENCE_INGRESS_JOURNAL_DURABILITY=sync` for a durability boundary, or
  `page_cache` only for an explicitly volatile test profile

The bounded load-test Compose profile overrides the path to
`/benchmark/journal` on tmpfs so it cannot consume laptop disk space.
