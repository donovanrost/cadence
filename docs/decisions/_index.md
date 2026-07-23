---
title: Architecture Decision Records
tags: [decisions, adr, index]
created: 2026-03-28
updated: 2026-07-21
status: active
---

# Architecture Decision Records

This directory holds ADRs for the redesigned Cadence system in `apps/cadence`
and `apps/cadence_web`.

For the current implementation shape and developer workflow, start with the
[Developer Architecture Guide](../developer-architecture-guide.md).

Legacy ADRs remain under
[`legacy/cadence_legacy/docs/decisions`](../../legacy/cadence_legacy/docs/decisions/_index.md).

## Accepted Decisions

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](001-mission-scoped-runtime-and-selector-model.md) | Mission-Scoped Runtime and Selector Model | Accepted |
| [ADR-002](002-organization-mission-scope-and-identity-model.md) | Organization, Mission, and Identity Scope Model | Accepted |
| [ADR-003](003-authorization-context-and-policy-evaluation-model.md) | Authorization Context and Policy Evaluation Model | Accepted |
| [ADR-004](004-activation-authorization-and-approval-policy.md) | Activation Authorization and Approval Policy | Accepted |
| [ADR-005](005-runtime-partitioning-and-workload-isolation.md) | Runtime Partitioning and Workload Isolation | Accepted |
| [ADR-006](006-contact-link-and-transport-runtime-model.md) | Contact, Link, and Transport Runtime Model | Accepted |
| [ADR-007](007-first-party-capability-abi.md) | First-Party Capability ABI | Accepted |
| [ADR-008](008-multi-format-catalog-import-architecture.md) | Multi-Format Catalog Import Architecture | Accepted |
| [ADR-009](009-canonical-telemetry-catalog-model.md) | Canonical Telemetry Catalog Model | Accepted |
| [ADR-010](010-canonical-command-catalog-model.md) | Canonical Command Catalog Model | Accepted |
| [ADR-011](011-command-staging-queueing-and-release-lifecycle.md) | Command Staging, Queueing, and Release Lifecycle | Accepted |
| [ADR-012](012-provider-adapter-and-ground-station-simulator-model.md) | Provider Adapter and Ground Station Simulator Model | Accepted |
| [ADR-014](014-shared-ccsds-library-boundary.md) | Shared CCSDS Library Boundary | Accepted |
| [ADR-015](015-management-control-data-plane-architecture.md) | Management Plane, Control Plane, and Data Plane Architecture | Accepted |

## Superseded Decisions

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-013](013-control-plane-data-plane-and-reconciliation-patterns.md) | Control Plane, Data Plane, and Reconciliation Patterns | Superseded by ADR-015 |

## Planned Decisions

- Future mission-supplied plugin ABI
