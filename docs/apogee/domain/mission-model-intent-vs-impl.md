# Mission Model: intent (ADR-020) vs what's built, and a mission-wide model

domain, 2026-11-15. A read-only review requested by the director for the user's question:

> "Are there gaps in the implementation? And why not model the WHOLE mission as one mission model
> instead of a model per spacecraft?"

It was written independently of the parallel reviewer and **supersedes the narrower
shared-template proposal** in `config-materialization-model.md`. That doc's measurements stand; its
fix becomes one part of this one.

Paused until this is decided:
- the limits and derived-telemetry ConfigKinds (#77 stages 2–3);
- binding-template step 1.

Notation: `P/` = `packages/cadence_catalog/lib/cadence/catalog/`, `L/` = `apps/cadence/lib/cadence/`.

## The short answer

**ADR-020 already describes the mission-wide model the user is asking for. We built its compiler
but not its composition.**

- **The model is per mission in shape.** Every Mission Model layer and revision is mission-scoped
  (`P/mission_model/layer.ex:11`, `compiler.ex:63-73`); nothing is per spacecraft. The ADR's
  composition is
  `imported layers + governed augmentation layers = one effective revision` (§9, `020-…md:450-456`),
  and the compiler implements it: add, extend, replace and remove, with fingerprints and drift
  diagnostics (`compiler.ex:95-184`).
- **What we built instead:**
  - every catalog import compiles **only its own single imported layer** into an isolated revision
    (`L/catalog/import_execution.ex:24`);
  - `MissionModels.compose/4` has **no caller**;
  - **no augmentation layer is ever written**: `:authored` appears only in a compiler test.
- **So the user's "model per spacecraft" is real in effect, not in the type.**
  - Each spacecraft pins a catalog revision, which pins a whole isolated model revision.
  - The fleet then materializes that choice per spacecraft: binding sets of craft × packet (10,000
    rows per generation on dev), fleet entries, configuration revision documents and application
    bindings.
- **User definitions are not overlays.** Ground limits and derived telemetry live in separate
  tables with their own evaluators and their own point namespace. That is exactly what ADR-020 §5
  and §6 said would be "replaced rather than adapted". The #77 ConfigKinds (stage 1
  `derived_telemetry`, 5504322a8; stage 2 `limit_definition`, c495f6d9f) put change-set governance
  on top of those side tables, which entrenches the family the ADR retires. The pause is right.

## 1. Where each definition family lives today

| Family | In the model? | Also stored or evaluated elsewhere | Gap against ADR-020 |
|---|---|---|---|
| Telemetry containers and parameters | **Yes**: declarations, lowered to the telemetry plan (`P/mission_model/target_lowering.ex:20-35`), decoded per partition (`L/runtime/mission_model_plan_decoder.ex:59-80`) | Copied into `governed_packet_definitions`/`_fields` and into per-(endpoint × packet) capability instances and rules at each binding-set write (`L/governance.ex:52-60`, `L/applications/telemetry_decom.ex:976-1009`) | Shape is right; storage is materialized per craft |
| Commands, arguments, constraints, verifiers | **Yes**: the command plan (`target_lowering.ex:38-60, 376-422`), read by `CommandAuthoringBasis` and `ActiveBasis` | Commanding rows pinned to `mission_model_revision_id` (correct) | None structural |
| Monitoring (limits, alarms) | **Partly**: `monitoring_policy` declarations from XTCE alarms and YAML `limits:` lower to the monitoring plan, evaluated **live in partitions** (`L/semantic_runtime/monitoring_plan.ex`) | **A second system**: `governed_limit_definitions` (+ lifecycle and active tables), four thresholds per point. Authored in the Limits app (direct save) or the #77 `limit_definition` ConfigKind. Evaluated by **batch jobs** over the sample log (`L/limits.ex:219, 381`). Alarms merge both (`L/alarms/sources.ex:1-10`). | §6: "thresholds are syntax sugar for a basic monitoring policy… not a separate architectural family". Two evaluators and two semantics (live vs batch), and conflicts between an imported policy and a ground limit are not diagnosed. |
| Derived telemetry | **Partly**: `algorithm` declarations from XTCE run in `SemanticRuntime`. The YAML importer emits none. | **A second system**: `governed_derived_telemetry_definitions` (expression, source points), its own id namespace ("can't reuse a catalog point's id"), a job evaluator over the sample log (`L/derived_telemetry.ex`), the #77 `derived_telemetry` ConfigKind | §5: "no longer a semantically independent definition family with a parallel point namespace"; should be an algorithm-produced parameter in an augmentation layer |
| Calibrators | Declared (YAML polynomials, XTCE) | **Not executed**: the telemetry target flags them unsupported (`P/mission_model/target.ex:102-110`) | A gap in the plan lowering, independent of layering |
| Enumerations | Yes (parameter types; `EnumerationAlarm` → monitoring) | - | - |
| The point list (limits, derived, dashboards) | **No**: built from the active **binding set** (`L/ops/point_catalog.ex:53-77`, `packet_name.field_name`) | - | Points should come from the effective model's parameters, not from the deployment's materialized rows |

**User-added definitions as overlays:** not implemented. The layer type has `:imported | :authored`
(`P/mission_model/layer.ex:6`), and the compiler composes layers correctly, but:
- no product path writes an `:authored` layer;
- no path composes more than one layer;
- a new import doesn't carry anything forward, since there is nothing to carry.

The ADR's implementation status (2026-08-12) claims layers, revisions, the XTCE frontend and the four
plan consumers. It does not claim augmentation layers. Sequence steps 5–6 (parameter, algorithm and
monitoring augmentations, `020-…md:689-692`) were never started.

## 2. What truly varies per spacecraft

On dev, 500 spacecraft have **2 distinct effective configurations** (499 identical; 001 differs only
by its catalog override, the canary). What is genuinely per spacecraft is identity and deployment,
not definitions:

- **Identity:** spacecraft id, SCID, display name, its source endpoints (`source_ref`).
- **Deployment state:** commanding and telemetry switches, uplink routes and transport profiles
  (SCID/VCID, provider binding), routing-rule exclusions.
- **Which model it runs:** today a catalog revision, set by the profile or a per-craft override.
  This is the rollout lever.
- **Deltas:**
  - today, the profile's overridable paths (catalog, handled APIDs, routing);
  - later, possibly a per-craft monitoring threshold (a craft with a degraded sensor). That is a
    definition delta and needs a home in the model (section 3).
- **History:** which model and configuration it ran, when, and under which change.

No per-spacecraft store holds definitions today. They hold identity or references. The **copies**
come from materializing references into per-craft rows. Five places record "which catalog or model
is this craft on":
1. the profile or override (the source of truth);
2. the configuration revision document and column;
3. `spacecraft_application_bindings` (drifted; fixed in f146ba03d);
4. the fleet entry's `mission_model` manifest;
5. the binding set's per-endpoint instance ids.

`application_packet_bindings` carries it too.

## 3. A mission-wide model, SpaceSystem style

The model below is ADR-020 as written, finished. It needs no new concepts, only the missing
composition and a deployment binding that doesn't materialize.

**One model lineage per mission.**
- The **effective revision N** = the current imported layer(s) + the current augmentation layers,
  compiled by the existing compiler. A new import makes a new imported layer.
- The next effective revision re-composes it with the same augmentations.
- An augmentation that no longer fits (its `expected_fingerprint` drifted) is a **diagnostic before
  activation**, not a silent loss. That is the compiler's existing behaviour (`compiler.ex:133-184`).

**SpaceSystem tree** (ADR-020 §3: one bus or payload model reused by several spacecraft; the IR
does not own inventory):
- the mission root holds mission-wide parameters, for example a cross-craft derived parameter
  (open question 1);
- child SpaceSystems per **spacecraft type or profile** (bus, payload) hold the shared definitions.

**Overlays as augmentation layers.** Limits, derived parameters, alarm policies and calibration
corrections the operators author are **governed augmentation layers**:
- staged and approved through change sets (the #77 governance flow is the right flow; its *target*
  becomes "stage declarations into the next augmentation layer");
- immutable once composed, and attributable;
- a conflict with an imported definition is a typed, diagnosed `replace` or `extend`, never last-write-wins (§9).

**A spacecraft is a deployment binding, outside the IR** (§3), one small row per craft:
- spacecraft id, SCID, endpoints;
- SpaceSystem (type) ref;
- **effective revision ref (N or N+1)**;
- delta ref.

Deltas come in two kinds:
- **Definition deltas** (a per-craft threshold): context-scoped declarations in an augmentation layer,
  i.e. XTCE's context-matched alarms keyed on spacecraft identity. That keeps one revision for the
  fleet instead of one per craft.
- **Deployment deltas** (routing exclusions, switches): stay on the binding.

**Staged rollouts (N vs N+1).**
- Revisions are immutable, so N and N+1 coexist. The runtime already supports different craft on
  different model revisions in one generation (`L/control/spacecraft_model_bindings.ex:47-55,
  92-115` groups fleet entries by manifest).
- A canary moves 1 binding to N+1. A rollout moves cohorts. Rollback moves them back.
- Each move is a binding-row update plus an assignment-history row. The runtime groups by
  (revision, framing) and expands per partition in memory: `BindingSetIndex.select/2` already slices
  per endpoint.

**What a fleet move costs:**
- compile N+1 once;
- update N bindings (one statement);
- append assignment history (one `insert_all`);
- write one generation record.

Measured today, it is 17,524 statements and about 14 MB at 500 craft.

## 4. What it replaces

| Today | Becomes |
|---|---|
| Isolated single-layer revision per import; `compose/4` unused | The mission lineage: imported + augmentation layers composed per effective revision |
| `governed_limit_definitions` (+ lifecycle and active tables), `Limits` batch evaluator, `limit_definition` ConfigKind | Monitoring declarations in an augmentation layer, compiled to the monitoring plan, evaluated live (one evaluator); Limits app = authoring UI over those declarations (§6) |
| `governed_derived_telemetry_definitions`, job evaluator, `derived_telemetry` ConfigKind, the parallel point namespace | Algorithm-produced parameters in an augmentation layer, executed by `SemanticRuntime` (§5) |
| Point catalog built from the binding set | Points = the effective revision's parameters (one namespace) |
| Binding set = craft × packet rows per generation | Grouped by (revision, framing) plus membership; expanded per partition at runtime |
| Per-craft configuration revision documents, `spacecraft_application_bindings`, per-craft fleet manifests | Deployment binding row + assignment history; `spacecraft_application_bindings` becomes a projection or is deleted |
| Catalog revision as the per-craft lever | Catalog revision stays as **import provenance** (already the stated intent, `L/mission_models/telemetry_projection.ex:5-6`); the lever is the effective revision |
| `governed_packet_definitions` copy | Read from the revision's telemetry plan (already content-addressed) |
| #77 stage 3 (`telemetry_decom` per spacecraft) | Unnecessary: the APID selection and switches live on the binding |

**What is kept unchanged:**
- the Mission Model IR package, compiler, targets and plans;
- the XTCE and YAML importers;
- the runtime plan decoders and `SemanticRuntime`;
- activations and generations;
- change sets as the governance flow;
- FleetSnapshot v2's content-addressed entries (they already dedupe identical entries).

**Migration**, no dual-write (ADR "Impact", `020-…md:575-578`):
1. Translate the existing limit and derived rows **once** into the first augmentation layer. On dev
   they are few; check counts in a slot.
2. Compose it with the current imported layer into effective revision N.
3. Bind every craft to N (001 to its N+1 equivalent).
4. Retire the side tables and evaluators.

Old generations stay readable as they are, since revisions and binding-set versions are immutable.

## 5. Recommendation

**Finish ADR-020 rather than add to the side systems.** It is the mission-wide, overlay-based model
the user describes. The gaps are composition and deployment binding, not the IR.

Proposed order, each step shippable:

1. **Augmentation layers and the lineage.**
   - Wire `compose/4` into revision building: each effective revision = latest imported layer(s) +
     current augmentation layers.
   - Change-set kinds stage *declarations* into the next augmentation layer. This re-targets #77's
     governance; it doesn't discard it.
   - Diagnostics block activation.
2. **Limits and derived telemetry into the model.** Monitoring and algorithm augmentations, one live
   evaluator each, points from the model, a one-time translation of existing rows, then retire
   `governed_limit_definitions` and `governed_derived_telemetry_definitions` with their evaluators.
   Calibrator execution belongs in the same step (a plan-lowering gap).
3. **Deployment binding instead of materialization.** A per-craft binding row (revision ref, type
   ref, deltas) with assignment history. Binding sets grouped by (revision, framing). Remove the
   per-craft document and application-binding copies. This absorbs `config-materialization-model.md`
   steps 1–2.
4. **Rollouts as binding moves.** Canary, cohort and rollback as reference flips. The runtime's
   per-manifest grouping already carries mixed fleets.

**Open questions for the user:**
1. **Cross-spacecraft derived parameters.** Today a derived definition is mission-scoped
   (`"__mission__"`). Should a parameter computed from several craft live on the mission root
   SpaceSystem, with inputs addressed by instance?
2. **Per-craft definition deltas.** Context-scoped declarations in the shared lineage (my
   recommendation: one revision for the fleet), or a per-craft augmentation layer (simpler to
   author, but a revision per variant)?
3. **Imports.** Does a new import replace the imported layer wholesale in the lineage (my default),
   or can several imported layers coexist (bus model and payload model from separate files, as §3
   allows)?
4. **Live vs batch monitoring.** Ground limits are evaluated over history by jobs today, which can
   backfill. The model's monitoring plan is live. Is history backfill for a new limit a requirement?

**Until decided:**
- #77 stages 2–3 and binding-template step 1 stay paused.
- The built stage 1–2 kinds keep working as they are; no further investment in them.
- The drift and parity fixes and step 4 continue, because they correct today's behaviour whatever
  the model becomes.
