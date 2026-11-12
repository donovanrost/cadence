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

The binding set's governed packet definitions don't persist each field's `parameter_id` /
`qualified_name` (they read back nil). That's by design: at runtime they are lookup keys only.
`PartitionOwner` resolves each packet against the mission-model telemetry plan
(`MissionModelPlanDecoder.resolve_telemetry_configuration/2`), whose fields carry the ids, so
samples keep their semantic identity. Don't "fix" the nils. Do hash the binding set as it reads
back, never the in-memory build (2026-11-12 outage, below).

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

## 2026-11-12 outage: gen 8 unadmittable after restart, and its repair

- **What.** After qa's 22:14:32Z :4011 restart, the mission control reconciler couldn't re-admit
  generation 8 (the #65 canary, r9, applied 21:58Z live). First it crashed 128 times on
  `String.to_existing_atom("criteria")` in `MissionModel.Reference.new/1` (rev 4 is the first
  model with a `criteria` reference role; in a fresh dev VM the atom didn't exist yet), then,
  once the atom existed, on `{:mission_runtime_spec_mismatch, :binding_set_content_sha256}`.
  With no admitted spec, every ingest failed `no_active_binding_set` (005 from 23:57Z, 001's
  armed pass 00:03:52-00:11:52Z). The ingress journal is off on :4011, so that TM is lost.
- **Why the hash.** The catalog-path apply (`ConfigurationGeneration.next_binding_set` then
  `activate`) hashed the in-memory binding set. Read back, its packet fields lack
  `parameter_id`/`qualified_name` (by design, above), so the stored hash
  (`fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c`) never matched the
  persisted set (`4edf93da0468094db3c6f67f78641688b92cb5062157ade2dc5ed3fda01bd093`).
  `Control.Activations` re-fetches before hashing, which is why other generations were fine.
- **Repair (dev DB only, director-approved).** 2026-11-12 00:30:16Z, run by domain:
  `docs/apogee/domain/repairs/2026-11-12-gen8-binding-set-hash.sql` set the hash to
  `4edf93da…` on gen 8's activation, the active binding set and the approved activation
  request (`activation_request_ccxol52jpu_17QMA`, which `ApprovalAdmission` compares). The
  precheck required exactly one row in each; before-dump alongside. No runtime state was keyed
  by a gen-8 runtime basis (no semantic commits, heads or checkpoints under one). The
  reconciler admitted gen 8 at 00:30:52Z.
- **Fixes.** The catalog path hashes the persisted read; `Reference` decodes kinds and roles
  through an explicit list; a Readiness blocker shows an active generation the runtime hasn't
  applied.
