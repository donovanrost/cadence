---
title: Dashboard BYO QuestDB Smoke
status: working runbook
tags: [dashboards, questdb, byo-tsdb, verification]
---

# Dashboard BYO QuestDB Smoke

The BYO QuestDB smoke proves the dashboard source contract against a
customer-owned QuestDB endpoint instead of the managed local QuestDB service.
It exercises the product path for:

- registering a customer-owned dashboard data source
- registering a non-secret credential reference
- resolving the endpoint through the env-material resolver
- applying QuestDB telemetry schema migrations to the external endpoint
- writing one observation
- probing source health
- resolving dashboard telemetry history through the source registry

## Local Run

Start the customer-owned QuestDB service:

```sh
docker compose up -d questdb_customer
```

Run the smoke against the customer QuestDB HTTP endpoint:

```sh
MIX_ENV=test mix cadence.data_sources.byo_questdb_smoke \
  --http-endpoint http://127.0.0.1:9100
```

The task defaults to unique smoke record ids and deletes the Cadence-side
source, binding, credential, health, and generated mission records after the
run. This keeps the test database usable for repeated local or CI runs.
Because the external QuestDB write can become query-visible slightly after the
HTTP write returns, the task retries the final dashboard history read-back five
times with a 100 ms delay by default. Use `--history-read-attempts` and
`--history-retry-sleep-ms` only when a slower CI runner needs different timing.

Use `--keep-records` when inspecting the generated Cadence registry state:

```sh
MIX_ENV=test mix cadence.data_sources.byo_questdb_smoke \
  --http-endpoint http://127.0.0.1:9100 \
  --keep-records
```

The cleanup only removes Cadence registry and health records for the smoke run.
It does not delete telemetry observations written to the external QuestDB
endpoint.

## CI Guidance

The smoke is suitable as an optional live gate when CI can provide Docker and
the `questdb_customer` service.

Recommended CI shape:

- Start `questdb_customer` with `docker compose up -d questdb_customer`.
- Run the task under `MIX_ENV=test` against `http://127.0.0.1:9100`.
- Let the task use its default cleanup behavior.
- Treat failures as BYO source-contract failures, not as ordinary unit-test
  failures, because the gate depends on an external service.

The default development environment can run the same task, but the dev database
must already have the current Cadence migrations applied because the smoke
persists source, credential, health, and operational-event records.

## Follow-Ups

This smoke uses the current env-profile material resolver. It is not a
substitute for the future secret-management backend, authz policy, or long-term
tenant/mission database isolation model.
