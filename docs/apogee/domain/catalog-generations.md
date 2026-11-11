# Catalog-path generations (DECISIONS #36, #65)

A spacecraft's catalog revision decides how its telemetry is decoded and how its commands are
built. Changing it now goes through a change set, like framing (#45), and produces a runtime
generation.

## One writer

While a spacecraft's profile (with its overrides) names a catalog revision, that is the
spacecraft's catalog (`CatalogAuthority.effective/2`):

- A change set that changes the profile's or an override's `catalog_revision_id` moves the
  spacecraft (see Apply).
- The spacecraft's own configuration follows it. Saving or activating a configuration with a
  different catalog is refused with `:spacecraft_catalog_set_by_profile`, which points to a
  change set.
- Spacecraft without a profile catalog keep setting their catalog in their own configuration
  and activating it there.

**Existing mismatches aren't re-pointed silently.** A spacecraft whose configuration still uses
another catalog than its profile sets keeps running on it. Readiness lists it under the
`catalog.catalog_not_converged` caution, with `affected` =
`[%{spacecraft_id, effective_catalog_revision_id, configured_catalog_revision_id}]` and fix
kind `change_set`. A change set that touches the spacecraft (a pin or an override) converges it.

## Apply

For each spacecraft the set touches (pins moved, directly or by a profile rollout, and
overrides) that has an active fleet entry, and whose effective catalog differs from that entry,
the apply does the following inside its transaction:

1. Derives a configuration revision from the running one with only the catalog changed
   (`Drafts.derive_catalog/5`, created by the applier).
2. Compiles it with the per-spacecraft review's builder (`Review.compile/3`): telemetry
   capability instances and rules for the new catalog, and the fleet entry with the new mission
   model.
3. Rebuilds the binding set with those contributions (`Review.binding_set/3`).
4. Cancels commands on the spacecraft that haven't started to release, with reason
   `catalog_changed: <change set id>` (recorded on the request and its group).
5. Admits and records the generation. Admission checks that each moved entry is the
   spacecraft's latest configuration with that catalog.

Rollback takes the same path back.

One apply is one generation. The #65 canary (r9, 2026-11-11) went 7 to 8; its "6 to 8" read
the previous change set's generation and missed 7, the Nov 9 activation of all 500 spacecraft
configurations, which was made through per-spacecraft review rather than a change set.

## Preview: `compatibility` check (`CatalogCompatibility`)

| Reason | Blocking | Meaning |
| --- | --- | --- |
| `catalog_change` | no | `spacecraft_ids` move `from` → `to`. |
| `catalog_cancels_commands` | no | `requests` waiting to release on them are canceled by the apply. |
| `catalog_command_in_flight` | **yes** | `requests` releasing or radiating now; apply when they finish. |
| `catalog_configuration_pending` | **yes** | `spacecraft_ids` have a newer configuration that isn't active yet; activate or discard it first. |

A blocking item can't be acknowledged away. The check carries `blocking: true` and submission
answers `{:holds_blocking, preview}` until it clears. The apply re-checks in-flight commands
itself (`{:catalog_command_in_flight, ids}`) for the race.
