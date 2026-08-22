---
title: Run the Dashboard and Ops Demo
tags: [how-to, dashboards, operations, demo]
status: active
created: 2026-08-01
updated: 2026-08-01
---

# Run the Dashboard and Ops Demo

This demo tells one operator story across Cadence's dashboard and Ops
information architecture. It uses a real scheduled contact, TCP provider,
Cadence Simulator, CCSDS ingress, QuestDB history, and Postgres-backed current
values. The alarm, command, source-health, data-operation, and dashboard
management records are persisted through the same stores read by the product.

The setup creates a unique Flight Day 42 mission on each run. It does not add a
demo-only route or bypass the authenticated Ops shell.

## What the demo creates

- A live spacecraft contact with two APID 42 telemetry points at 2 Hz.
- **Flight Day 42 — Pass Overview**, with progressive dashboard sections.
- **Flight Day 42 — Battery Investigation**, a focused follow-up surface.
- A critical battery alarm and a nominal uptime condition.
- A queued battery-recovery command visible in the persistent context rail.
- A degraded telemetry-source status and a grouped backfill request.
- Published dashboard versions, an authenticated share, a frozen-time
  snapshot, a reusable library widget, an as-code deployment record, and a
  wallboard playlist.

## Prerequisites

Start Postgres, QuestDB, and the local observability stack, then apply all
migrations:

```sh
docker compose up -d postgres questdb greptimedb tempo loki otel_collector grafana
cd apps/cadence_web
mix ecto.migrate
```

The dashboard management migrations in the current checkout must be applied
before running the fixture.

## Start Cadence

In the first terminal, start Phoenix with the shared Postgres current-value
projection. The standalone demo process and Phoenix must use the same store.

```sh
cd apps/cadence_web
CADENCE_TELEMETRY_CURRENT_VALUE_STORE=postgres mix phx.server
```

Sign in once and note the email address you use. The demo grants that existing
user organization-admin access to its generated organization. This is required
for the Editor, Settings, Sources administration, and Data Operations
administration stops in the walkthrough.

## Start the live fixture

In a second terminal, run:

```sh
cd apps/cadence_web
CADENCE_DASHBOARD_DEMO_BROWSER_EMAIL=operator@example.com \
CADENCE_DASHBOARD_DEMO_GRAFANA_URL=http://localhost:3300 \
mix run --no-start ../../dev/dashboard_ops_demo.exs
```

Replace `operator@example.com` with the signed-in account. The script waits for
the contact to become active and for QuestDB history to contain telemetry, then
prints direct links for every demo stop. Leave it running so the charts remain
live. Press Ctrl-C twice after the walkthrough.

If Grafana uses the repository's default `:3000` mapping, either omit the
Grafana comparison or set `CADENCE_DASHBOARD_DEMO_GRAFANA_URL` accordingly.

## Presenter flow

### 1. Establish the information architecture

Open the printed **Start here** URL. Search for `ops-demo` in the Dashboard
Directory and point out the two purpose-built dashboards, their tags, published
state, and the separation between Viewer, Editor, Activity, Diagnostics, and
Settings.

The left navigation answers “where can I do this work?” The right context rail
answers “what needs my attention while I do it?” Keep the rail open throughout
the demo.

### 2. Operate from the pass overview

Open **Pass overview**. Show that the primary page remains telemetry-first:
live charts and current values dominate the canvas. Expand **Engineering
detail** to demonstrate progressive disclosure without turning the core view
into a configuration page.

Use the time and scope controls to explain that the viewer changes runtime
context without mutating the published dashboard definition.

### 3. Carry context across pages

In the right rail, call out the critical battery alarm and queued recovery
command. Open **Alarm workspace**, inspect the evidence and limit-definition
links, then open **Command workspace** and follow the recovery command.

Navigate to Timeline or Planning. The focused command and mission-level alarm
summary remain in the shell rail, preserving awareness while the central task
changes.

### 4. Investigate without overloading the dashboard

Open **Battery Investigation** or hand off to **Explore** from a telemetry
widget. The second dashboard contains the focused correlation view; Explore
owns ad-hoc query work. This is the key hierarchy distinction: dashboards
monitor known operational questions, while dedicated pages own deeper work.

Open **Data sources** to show the degraded managed QuestDB source, then **Data
operations** to show the requested completeness backfill. The demo intentionally
stops at a request state; administrative approval and execution remain explicit
operations.

### 5. Show governance and reuse

Return to the overview and visit **Activity** for its create/publish history and
**Diagnostics** for source posture. If the account has author access, open
**Editor** to show staged edits and **Settings** for sharing, snapshots, export,
and lifecycle controls.

Open the Dashboard Library to show **Battery Voltage — Flight Standard**. Open
Playlists and present **Flight Day 42 Ops Rotation** to demonstrate wallboard
rotation across the overview and investigation views.

### 6. Compare with Grafana

Open the printed Grafana SRE overview URL. Use it as the prior-art comparison:
Grafana remains strong at broad observability exploration; Cadence applies the
same interaction quality to mission-scoped telemetry, commands, alarms,
contacts, source provenance, and governed historical-data operations.

## Optional controls

- `CADENCE_DASHBOARD_DEMO_RUN_ID` uses a deliberate stable suffix. Omit it for a
  unique, isolated demo mission.
- `CADENCE_DASHBOARD_DEMO_RATE_HZ` changes the simulator rate (default `2.0`).
- `CADENCE_DASHBOARD_DEMO_CONTACT_SECONDS` changes contact duration (default
  `3600`).
- `CADENCE_DASHBOARD_DEMO_LOG_LEVEL` changes console verbosity.
- `CADENCE_DASHBOARD_DEMO_CADENCE_URL` changes printed Cadence links.
- `CADENCE_DASHBOARD_DEMO_GRAFANA_URL` changes the Grafana comparison link.

The older `CADENCE_SRE_DEMO_*` variables remain supported for compatibility.
