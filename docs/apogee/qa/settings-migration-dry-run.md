# Per-field settings migration: dry run on :4011 (cadence_apogee_dev)

- 2026-11-13 16:15Z, api 14455857d, in-node `Cadence.Management.SettingsOverrideMigration.dry_run().report` (reads only).
- Director, 16:3xZ: skip `run(plan)` here: 0 rewrites means no revision and no audit entry. This report is the record.
- The 0-rewrite run path (this shape: one differing governance field) is covered by api's test 1cf5d814d:
  `written: []`, `stale: []`, governance history unchanged, no system audit entry.

```
Per-field settings overrides: dry run, 1 mission(s) with an override, 0 to rewrite.

Earendil (mission-earendil-demo, org org-reflect-orbital-demo)
  Governance v1: unchanged
    kept (differs): approval_requirement = "direct" (organization: "independent")
  No change: nothing is written and no audit entry is made.

```
