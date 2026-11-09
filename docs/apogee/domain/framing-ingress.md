# Profile framing feeds ingress; change sets produce generations (DECISIONS #15 follow-up, P2)

Owner: **domain**. Status: **draft for review** (2026-11-09). Reviewer: director (touches the live
ingest path and activation admission). `L` = `apps/cadence/lib/cadence`.

## Today

- The TM codec takes its options from each frame's evidence metadata
  (`L/protocol/tm_frame_ingress.ex:131`: `frame_size`, `secondary_header_length`,
  `ocf_length`, `fecf`). The TCP adapter stamps that metadata with the **transport's**
  `ingress_metadata` (`L/provider_adapters/tcp_socket.ex:126,511,652`).
- The profile's framing reaches only each spacecraft's configuration document
  (`document["protocol"]`, `ConfigurationInput.from_profile`). That document is part of the
  admitted fleet entry, but nothing in the partition reads it.
- A change set that edits profile framing writes profile v+1 and moves pins, but it **doesn't
  produce an activation**. So decode can't change, even if it read the profile.

## Proposal

### 1. Ingress reads admitted framing (data plane)

- Control already builds the runtime spec from the fleet (`SpacecraftModelBindings.runtime_basis`
  → `source_runtime_bases`, keyed by source endpoint). Each source basis gets one more field:
  `framing`, the source spacecraft's admitted `document["protocol"]` (frame size, secondary
  header, insert zone, OCF, truncated header, fecf).
- In the partition (`L/runtime/partition_owner.ex:1058`), before `TMFrameIngress.process`,
  merge the basis framing **over** the evidence metadata. Admitted framing wins, and the
  transport's `ingress_metadata` stays the fallback for sources without an admitted entry.
- `frame_codec_opts` is unchanged. The overlay adds no per-frame cost beyond one map merge,
  and the partition holds its source's basis already.
- Change in behaviour: a source whose admitted framing differs from its transport's ingress
  metadata decodes with the admitted framing from the next generation on. ADR-004 §2 holds:
  stored frames are never reinterpreted.

### 2. Change sets produce generations (control)

- Kinds declare `runtime_impact: :generation` for:
  - `spacecraft_profile` edits to framing or catalog paths;
  - `spacecraft_override` on those paths;
  - later `application_installation`.
- In the apply transaction, after the ops and finalize, for the affected spacecraft:
  1. Build their new fleet entries from **effective** config (profile version + overrides):
     `document["protocol"]` from framing, and `catalog_revision_id`. Keep everything else
     from the active entry. Merge with the unchanged active entries, then `FleetSnapshot.store`.
  2. Compose the binding set as `Review.replace_contributions` does, and
     `Governance.persist_binding_set`.
  3. Create the activation request **pre-approved with the change set's own review evidence**,
     and persist the activation, all in the same transaction. That adds
     `Management.Activations.request_reviewed/…`: it records the change-set review instead of a
     second decision row, and keeps `ApprovalAdmission` re-validation. The revision gets
     `activation_id` and `generation`.
  4. After commit, run the existing tail (ensure_started → `apply_generation` →
     `TelemetryDecom.activation_applied` with hydrated entries → execution completion). The
     apply result reports `runtime: :converging`, then `:applied` / `:degraded` on the runtime
     topic when the reconciler settles.
- **Spacecraft governed by a per-spacecraft configuration review** (legacy flow) aren't touched.
  They keep their pin and entry, as rollout already does.
- **Synthetic profiles:** activation stops forking them for change-set spacecraft; the effective
  config carries the difference. Converting existing ones into overrides is a separate,
  reviewable lift (profile-routing.md §6C).

## Risks and tests

- **Wrong framing breaks decode.** The preview gets a compatibility check: frame size
  compatible with the catalog, and a HOLD when admitted framing differs from the transport's
  ingress metadata, naming both values.
- **Tests (targeted, given the load rule):**
  - a partition decodes with admitted framing over transport metadata;
  - a profile frame-size change set produces generation N+1 with the new framing for moved
    spacecraft only;
  - the governed spacecraft keeps its entry;
  - the fleet tests stay green.

## Ask

OK to build in this order: (1) ingress overlay, (2) generation-producing applies? Or should (2)
wait behind a flag until fe-setup's review page shows the HOLD?

## Decisions and build notes (DECISIONS #33)

- **(1) built** (`8087801f`, `bc234414`). The overlay applies only to fleet entries with
  `"framing_authority" => "profile"` and an explicit `"framing"` map. Only change-set generations
  write those. Legacy entries carry neither, so their decode is unchanged. Source runtime bases
  now allow 8,000 sources; the old cap was 1,000 and would have broken fleets past it.
- **(2) built** (`8f798dde`): `Cadence.Comms.FramingDrift.audit/2`,
  `mix cadence.config.framing_drift`, and readiness finding `framing_drift` (caution, fix
  `{profile, id}`).
- **(3) build plan, behind the per-mission flag `cadence.configuration` →
  `profile_framing_generations` (default off):**
  - **Kinds:** `spacecraft_profile` edits that touch framing or catalog, and
    `spacecraft_override` on those paths, report `:generation`. With the flag off they behave as
    in P1 (no activation), and the preview says so.
  - **Inside the apply transaction:** an injected composition builder
    (`Cadence.Control.ConfigurationGeneration`) builds the affected spacecraft's entries from
    effective config, marked `framing_authority: profile`. It stores the fleet, composes and
    persists the binding set, and creates the activation request **pre-approved by the change
    set**. That only happens when the set satisfied the activation policy: direct, or reviewed by
    a non-author. Metadata v2 carries `"change_set" => %{id, revision, content_sha256}` instead of
    per-spacecraft draft review evidence. Admission gets a matching branch: the change set must
    be applied at that revision, the head must not have moved, and the fleet hash must match.
  - **After commit:** the existing execution tail runs (admission + generation +
    `apply_generation`). Execution therefore runs after the revision commits, as legacy reviews
    do. If it fails, the revision stays applied and the runtime reports `:degraded`, with
    retries.
  - **Preview:** a compatibility HOLD for `framing_mismatch` in fe-setup's agreed item shape,
    whenever a profile-authoritative change would differ from the transport's ingress metadata.

## Default on (DECISIONS #45, 2026-11-09)

After qa's #33 and #36 gates passed, `profile_framing_generations` defaults to **on**
(`Cadence.Platform.ConfigurationSettings`). A mission can still turn it off: an explicit
mission-level setting overrides the default.

The framing compatibility HOLD now checks only spacecraft whose runtime framing the apply would
change. Those are the spacecraft with an active fleet entry that differs from their effective
profile framing, as computed by the same builder that makes the activation
(`ConfigurationGeneration.changed_spacecraft/3`). With the default on, a routing-only profile
edit therefore doesn't hold.

Missions that had the flag set explicitly keep that value. On :4011, Earendil was set off
explicitly after the #36 gate, so it stays off until someone changes it.
