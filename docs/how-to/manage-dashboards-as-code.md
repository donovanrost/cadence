---
title: Manage Dashboards as Code
tags: [how-to, dashboards, ci, operations]
status: active
created: 2026-08-01
updated: 2026-08-01
---

# Manage Dashboards as Code

Cadence dashboards can move between missions as governed JSON artifacts without
moving credentials or runtime samples. An export contains the Dashboard Document,
an integrity digest over its binding semantics, export provenance, and an explicit
identity-replacement policy. Import always assigns a new dashboard identity and the
target organization and mission.

## Export and validate

Dashboard authors download an artifact from **Dashboard Settings → Export JSON**.
Validate one or more artifacts from the repository root:

```sh
mix cadence.dashboards.validate dashboards/flight-power.cadence-dashboard.json
```

The task accepts governed export bundles and legacy raw Dashboard Documents. It
fails when JSON cannot be decoded, an export's binding digest does not match, the
schema version is unsupported, required identity is absent, or a widget, layout,
binding, runtime default, section, repeat, or override violates the compiled
Dashboard Document contract.

The machine-readable authoring contract is
[`apps/cadence/priv/dashboard_document.schema.json`](../../apps/cadence/priv/dashboard_document.schema.json).
The compiled validator remains authoritative because it also checks registered
widget types and domain-specific runtime semantics.

## CI example

```yaml
- name: Validate Cadence dashboards
  run: mix cadence.dashboards.validate dashboards/*.json
```

Pin reusable Library widgets to an exact `library_widget_id` and
`library_version`. Publishing a newer Library version reports an update posture;
it does not rewrite consuming dashboard artifacts. Review the generated diff and
save a new dashboard version when intentionally upgrading.

## Import policy

Use **Dashboard Directory → Import**. Cadence verifies the export digest before
copying the definition, drops source version identity, records import provenance,
and assigns the current authenticated organization and mission. Resolve any
environment-specific source bindings in Editor and review publish readiness before
publishing.
