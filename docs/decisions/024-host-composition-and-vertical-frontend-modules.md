---
title: "ADR-024: Host Composition and Vertical Frontend Modules"
tags: [adr, frontend, vue, modules, composition]
status: accepted
created: 2026-09-06
---

# ADR-024: Host Composition and Vertical Frontend Modules

## Decision

The host owns placement and composition. Domain modules own the contributed
feature. Frontend delivery, optional capability installation, and Managed
Application runtime execution are separate decisions. Independent frontend
releases are not currently required; coordinated releases remain supported.

Catalog is core platform functionality consumed by telemetry decomposition and
future payload capabilities. Ops is a workspace into which modules contribute,
not the owner of everything displayed under an Ops URL.

This refines ADR-016 and ADR-023 without changing Phoenix ownership of routes,
authentication, authorization, durable state, or governed effects. Module loading
does not grant permissions. A host-owned page is allowed to compose module-owned
content; it must remain navigable when a contribution fails.

## Target ownership

```text
frontend/
├── apps/host/src/
│   ├── auth-and-navigation/
│   ├── mission-and-spacecraft/
│   ├── catalog/
│   ├── administration/
│   ├── capability-management/
│   └── ops-workspace/
├── modules/
│   ├── communications/
│   ├── planning-and-contacts/
│   ├── dashboards-and-exploration/
│   ├── commanding/
│   ├── data-operations/
│   ├── telemetry-decom/
│   ├── derived-telemetry/
│   ├── limits-and-alarming/
│   └── payload-specific/                 # Future
└── packages/
    ├── ui/                              # Domain-neutral presentation
    └── plugin-sdk/                      # Published host/module contracts
```

The existing `apps/*` remote packages are migration sources, not the target
domain taxonomy. No rename of durable application, release, or surface identifiers
is implied by moving frontend source. Compatibility adapters may delegate to a
new owner's public entry point; they must not retain a second implementation.

| Existing page family | Target owner |
| --- | --- |
| Mission list/new/overview; spacecraft identity, profiles, readiness | Host mission and spacecraft |
| Catalog databases, revisions, artifacts, imports | Host catalog |
| Sign-in, invitations, notifications, account navigation | Host auth and navigation |
| Organization/platform administration | Host administration |
| Installation inventories and activation approvals | Host capability management |
| Ops rails, shared context, contribution placement | Host Ops workspace |
| Transport, station, provider and routing pages, spacecraft routing | Communications |
| Requirements, plans, contacts, fleet planning | Planning and contacts |
| Dashboard directory/editor/viewer/library/playlists/shares/snapshots, exploration | Dashboards and exploration |
| Mission and spacecraft commanding | Commanding |
| Sources, backend settings, historical workflows | Data operations |
| Decomposition configuration, packet bindings | Telemetry decom |
| Derived definitions/latest values | Derived telemetry |
| Limit configuration, posture, limit-backed alarms | Limits and alarming |

Placement is independent of ownership. In particular, dashboard diagnostics remain
dashboard-owned inside administration; spacecraft readiness aggregates
capability-owned status; and the host approves capability-owned activation requests.
Provider account UI belongs to Communications despite organization scope.
The cross-module timeline belongs to workspace composition. If the alarm inbox
expands beyond limits, its composition belongs to the workspace rather than Limits.

## Vertical feature slices

```text
modules/<module>/src/
├── index.ts                          # Deliberate public entry
├── contributions.ts                  # Assembles feature registrations
├── features/<feature>/
│   ├── FeaturePanel.vue
│   ├── SupportingComponent.vue
│   ├── useFeatureState.ts
│   ├── contracts.ts
│   ├── contribution.ts
│   └── FeaturePanel.test.ts
└── shared/                           # Only demonstrated cross-feature reuse
```

Host areas follow the same feature-local organization. Start features flat.
Tests, contracts, state, and contribution implementations live with their feature,
not in module-wide component/composable/contribution silos. Public registrations
do not contain displaced feature logic. Cross-module consumers import public
entries, never another feature's private files. Do not promote domain components
to frontend-wide shared UI merely to make imports convenient.

## Contribution contracts

Add named, versioned slots for demonstrated consumers rather than arbitrary hooks
into host internals. Distinguish data contributions (readiness/status) from UI
contributions (diagnostic panels/pages). A slot defines context, admitted identity,
ordering, interactions, and unavailable/error behavior. Each feature validates its
own versioned DTO before rendering. The host must not interpret domain DTO fields.

Only compiled, host-admitted registrations can supply components. Server payloads
cannot select arbitrary component names or JavaScript imports. Every read and action
is authorized in Phoenix, including refreshes and client-side navigation. Unknown
identities, unsupported versions, malformed data and renderer failures must not
break other contributions or remove host navigation.

## Adoption and verification

First implement `/admin/runtime` as a host-owned administration diagnostics page
with a dashboard-owned runtime diagnostics contribution. Preserve decision filters,
selection links, evidence redaction, existing URLs and platform-admin admission.
Keep the historical organization-admin surface as a compatibility adapter while
other pages migrate. This is the first slice, not completion of the ownership map.

Required evidence for each slice: real component tests, producer/consumer DTO
coverage, permission and failure isolation checks, browser navigation where
available, production compilation, and `mix precommit`. Loading a remote alone
does not prove workflow completeness. Migrate subsequent ownership cohorts using
the same rules; refine slot contracts only when another real consumer needs them.

### Current migration status

The ownership and authorized workflow audit is reconciled across all six host
areas and eight domain modules: 35 host features and 40 module features. The
[verification record](../architecture/frontend-ownership-verification.md) maps
requirements to feature-local tests, native authority/persistence checks and 43
authenticated browser cohorts, with explicit external-provider/runtime limits.
The final documentation verification gate passed: 42 plane tests and 3,955
workspace tests, with zero frozen-source drift. The ADR-024 migration target is
implemented and verified within the limits in that record.

Existing remote packages remain compatibility delivery adapters; coordinated
releases are supported. Durable identities, URLs, Phoenix authority and the
production design system remain in place. Payload-specific ownership is future
work outside this demonstrated target.

### Historical migration checkpoints

The entries below retain their original chronological scope and evidence limits.
Earlier in-progress statements are superseded by the current status and linked
verification record; they are not a current list of missing workflows.

- Planning and contacts has an in-progress domain package at
  `modules/planning-and-contacts/`, with vertical slices for contact requirements,
  contact plans, contact scheduling and fleet planning. Twelve existing Vue
  implementations and their presentation types now live with those features.
  Historical Ops Console entries re-export focused public module entries, and
  the delivery CSS scans the new owner. Initial extraction was checked against
  compiled-script and template fingerprints for all twelve views. As workflows
  gain semantic contracts, their historical preservation oracles are replaced
  with intentional producer, consumer and action tests described below. The
  unchanged views retain their extraction checks. Mounted tests cover requirement
  links, fleet creation payloads and policy gating, plan decision reasons,
  provider-change review, contact records and contact scheduling.
  Fleet Policy, New Contact Requirement and Requirement Templates now use
  feature-specific server producers with current mission-scoped domain reads,
  plain form DTOs and Policy-derived administrative forms. Their former generic
  placeholder producers have been removed. Persisted producer/consumer coverage
  exercises declaration, template versions and lifecycle, draft versus approved
  policy evidence, active mission service identities, grant revocation, scope
  rejection and unavailable policy versions. Failed version reads are not
  represented as an unconfigured policy; second-based evidence is not floored
  to whole hours or minutes.
  Policy approvals and grant issuance now carry a version-1 evidence reference:
  organization, mission, policy identity, immutable version and content hash.
  Vue rejects malformed or mismatched references, clears an approval reason when
  its reviewed identity changes, and shows which approved version a grant uses
  even when a newer draft is displayed. The host no longer substitutes the latest
  policy for a reviewed approval. Grant issuance rechecks its expected reference
  inside a transaction holding a shared policy-row lock through insertion;
  activation and retirement use the conflicting update lock. Persisted tests
  cover stale drafts, changed active policies, wrong hashes, scope substitution,
  retired policies and permission denial. Real producer props pass through
  client-compiled Vue form events into the host action and domain persistence.
  Headless Chrome fixture checks cover the visible approved-version label,
  reason reset, disabled decisions and unavailable warning; these are not
  authenticated live-mission browser evidence.
  Historical clients without this evidence are intentionally rejected; rollout
  is coordinated without renaming durable surface or action identities.
  Policy saves now carry an explicit version-1 edit reference, distinguishing
  initial creation from edits of a scoped immutable version and content hash.
  The server rejects stale or malformed references and overlays only exposed
  fields on the reviewed document; hidden scoring, resource capacities, provider
  budgets and critical-cost reserves are preserved. The domain's existing row
  lock and expected-version check still guard persistence. Validation uses the
  same merged domain documents without writing a version. Durations use explicit
  integer day/hour/minute/second units instead of decimal hours, and optional
  overall ceilings stay optional. Vue retains unsaved inputs across refreshes,
  disables stale saves and requires an explicit reload to discard those inputs.
  Persisted producer-to-client-to-action tests cover lossless edits, initial
  creation, stale drafts, scope/hash rejection, permissions and domain bounds.
  Production-built Chrome fixtures verify native duration input values and form
  validity, stale-save containment, explicit reload, and narrow-screen wrapping.
  These checks do not establish authenticated live-mission integration.
  Legacy policy-edit payloads are intentionally rejected during coordinated
  rollout, as with the decision references above.
  Grant horizons now use the same bounded whole-second duration syntax and
  native text control as policy editing, with explicit day/hour/minute/second
  units rather than decimal or whole hours. The producer preserves the approved
  horizon exactly, and issuance passes parsed seconds to the existing domain
  policy-bound checks. Policies still require at least 60 seconds; grants may be
  shorter, including one second, but cannot exceed the approved policy horizon.
  Persisted producer-to-client-to-action tests cover 60, 3601 and 5400 seconds,
  shorter grants, excessive bounds and malformed or legacy hour-only payloads.
  Production-built Chrome fixtures verify the native input's accessible name,
  exact value, form validity, emitted duration and narrow-screen wrapping.
  These fixture checks do not establish authenticated live-mission integration;
  non-mutating grant-form validation checks syntax, not full policy eligibility.
  The requirements list now reads current immutable requirement versions and
  actual lifecycle states instead of returning a constant empty array. Its
  identity-ordered live ledger uses 25-row pages plus one lookahead row, with
  lifecycle filters retained in canonical host links and both route catalogs.
  Missing current versions on the requested page fail the read rather than
  silently disappearing. This is live offset pagination, not a frozen snapshot
  across concurrent lifecycle changes or inserts. The feature admits a bounded
  version-1 DTO and mission-relative links before rendering; unsupported data
  produces an unavailable state. The former fixed progress bar is removed, and
  lifecycle is explicitly distinguished from reservation status. Producer-to-Vue
  tests cover current content, missing versions, filters and bounded pages;
  native host-route tests cover query forwarding. Chrome fixtures cover populated,
  empty and unavailable states and narrow-screen layout. Full integration and
  authenticated mission navigation remain to be verified for this increment.
  Requirement-detail reads and Vue controls now use a version-1 semantic DTO.
  The host requires a version-1 reviewed
  requirement reference (organization, mission, identity, version and hash),
  and plan creation additionally requires an explicit planning-run identity.
  It rejects stale or inactive requirements, mismatched run versions and
  cross-run selections; a newer search cannot silently replace the reviewed
  run. Historical payloads without these references are intentionally rejected.
  Persisted action tests exercise these decisions through the actual host
  boundary with deterministic provider-search fixtures. These are sequential
  admission and persistence checks, not proof against concurrent requirement
  changes during a search or proposal transaction. The subject admission now
  accepts the requirement context's actual three-element success tuple. The
  producer projects current or explicitly historical content and an explicitly
  selected run; it does not select the latest run on the operator's behalf.
  Historical, inactive and non-executable reviews disable decisions. Native
  Vue controls emit exact requirement/run references, and successful searches
  navigate to the run actually created.
  Bounded detail-read APIs now support requirement versions, planning runs,
  route searches and opportunity snapshots. Each query retrieves at most 26
  rows and returns 25 with an explicit continuation flag. Version history is
  anchored at the reviewed version; run history is a live offset-paged ledger,
  not a frozen snapshot across concurrent searches. Ordering includes identity
  tie-breakers, and ineligible opportunities remain part of the evidence.
  These APIs retain organization/mission/subject filters but do not replace
  host authorization. They bound returned rows, not total database scan work
  or serialized provider-document size. The detail DTO exposes bounded label
  previews, statuses, timestamps, identities and hashes, not raw provider
  errors or credential-bearing documents. Version/run/page parameters are
  captured by the existing mission-scoped host route. Feature-owned tab-local
  selection survives same-review page changes and remounts, is partitioned by
  actor and immutable review identity, and is capped at the host JSON boundary's
  100-item request limit. Storage failures prevent silent loss through page
  navigation; only a matching completed action result clears a submitted
  selection. This advisory state is never action authority.
  Producer-to-Vue tests, native control tests and isolated Chrome fixtures cover
  review identity, pagination, selection and contained invalid data. A persisted
  integration test feeds actual producer props through client-compiled Vue checkbox
  and button events into the host action, verifying that a newer search does not
  replace the selected run in the resulting proposal. Authenticated
  browser navigation through the complete workflow remains unverified. Successful
  proposal creation targets its exact plan; the destination now projects an
  immutable plan review rather than its previous placeholder.
  Plan submission, approval, rejection and execution now require a version-1
  reviewed plan reference (organization, mission, plan identity, version and hash).
  The host no longer substitutes the latest version or hash. Execution checks the
  reference against the approved immutable fact before accepting execution work;
  existing internal callers may still omit these optional control-layer checks.
  Persisted host-action tests cover stale and malformed references, scope and
  permission denial, exact approval/rejection records and pre-execution rejection
  without inserted work. Approval results use the approved fact's actual identity,
  not a nonexistent nested plan field. These are sequential checks, not proof of
  all concurrent decision/execution interleavings. The module-owned Vue plan
  detail now supplies this evidence; coordinated migration rejects old payloads.
  Plan review now has bounded Management and Control read APIs: version history
  and a live decision ledger exclude versions newer than the reviewed version;
  execution pages select exactly that version. Opportunity pages follow the
  immutable manifest's selected, locked and rejected order, preserving those
  dispositions and fetching only the requested page's snapshots within the plan's
  organization, mission and declared runs. Missing evidence fails the page instead
  of disappearing through a join. Persisted tests cover pagination, newer-version
  isolation, exact execution selection, scope isolation and missing evidence.
  Review version bounds match PostgreSQL's stored integer range; oversized values
  return validation errors before query encoding.
  The semantic plan-detail producer and module-owned Vue consumer now use those
  reads. The contract includes exact version/hash, manifest dispositions, pinned
  opportunity references, requirement coverage and findings, decision history,
  exact-version execution and independent bounded page cursors. Current lifecycle
  state is distinguished from the reviewed immutable version. Historical reviews
  cannot decide. The host captures the mission/surface action and query authority
  in a narrow plan port; the feature owns validation, reasons, pending state and
  reconciliation. Generic Ops browser events do not dispatch plan decisions.
  Confirmed decisions refresh in place. An uncertain action keeps its reason and
  disables further decisions; a read retry does not repeat the mutation. Earlier
  completed operations cannot unlock a later uncertain operation. New review
  identities clear obsolete reasons, and departed pages ignore late responses.
  Persisted producer-to-native-Vue-to-host-action tests cover submission, approval
  and stale evidence; component and delivery tests cover permissions, historical
  state, exact evidence and contained recovery. Authenticated browser navigation,
  actual provider execution and concurrent interleavings remain separate gates.
  Host routing tests verify every independent evidence-page parameter and the
  reviewed version. Plan identity remains path-owned even when a query parameter
  tries to replace it. Plan pages retain the existing authenticated browser scope
  and application live session. These reads do not create a new authorization
  boundary.
  This is not workflow completion. Other generic planning producers still use
  placeholder empty collections and fixed policy/readiness states; rendering
  those placeholders does not prove real mission data is represented.
  Semantic versioned contracts, the remaining
  authoritative reads, and complete host workflow integration remain required.
  Routes, permissions, durable identities and existing effect bindings are
  unchanged by this ownership and read-producer repair.
- Commanding now has a domain-owned package at `modules/commanding/` with
  `features/mission-commands/` and `features/spacecraft-commanding/`. Each feature
  owns its Vue implementation, contracts and component tests; consumers use
  focused public entries. Mission command monitoring is now the compiled
  `commanding.monitor` Ops page contribution. Its semantic version-1 read model
  admits exact organization/mission context, finite states and bounded evidence;
  it exposes no command creation, approval or release port. Phoenix reauthorizes
  reads and refreshes under the existing Ops policy. Canonical filters, pagination
  and request focus use host-owned URL navigation; focus can resolve outside the
  selected filters or page. Unknown selectors and failed reads are contained
  without removing host navigation or presenting stale data as current.
  The historical Ops Commands surface is a scoped link-only adapter, not a
  second monitor or read producer. Durable application/surface identities remain
  unchanged. The spacecraft entry now delegates to the owner
  destination; the host composes its semantic spacecraft contribution described below.
  Browser DTOs contain 25 rows per page, at most 200 target suggestions and
  20 verifier records per request, with explicit totals and truncation notices.
  The canonical source still reads mission-wide records: these browser limits
  are not database IO bounds, and full evidence-history pagination remains work.
  Persisted producer/consumer tests cover scope rejection, canonical evidence
  identities and timestamp precision, filtered focus, empty results and paging.
  Mounted tests cover navigation/history, refresh containment and native details
  retention; Storybook covers fixture-backed rendering, interaction and
  accessibility. These do not establish authenticated live-mission browser
  integration or complete commanding workflows. Ownership tests reject imports
  of delivery-package or sibling-feature internals.
- The dashboard domain has a server-owned staging transaction for the Editor.
  It binds the original document/version to an actor, mission and dashboard;
  staged commands and discard do not create durable versions. Every operation
  reauthorizes and checks the original save precondition, while a separate
  staging revision rejects delayed commands within a retained transaction.
  Explicit save writes all accumulated changes as one attributed version under
  the existing optimistic lock, without publishing. Discard restores the starting
  document; an externally changed saved draft requires an explicit reopen rather
  than silent rebasing. The read layer can resolve the actual unsaved document
  through the production engine and project its staging revision separately from
  the durable version. Immediate commands and staging share the same field,
  binding, layout and error implementations. The host page now retains this
  transaction across same-page refreshes and exposes a version-2 editor state;
  old page sessions rotate their token instead of retaining immediate-write
  semantics. Vue distinguishes unapplied inspector fields from staged changes.
  Applying a field group or layout updates the candidate, not the saved version;
  switching inspector panels preserves already-staged work. Save includes any
  unapplied fields and creates one version; Discard restores the starting draft
  without writes. Navigation and unload guards cover both kinds of unsaved work,
  and guard registration survives host transitions while commands remain disabled.
  Review saves first, then opens Activity at the acknowledged version; the editor
  cannot publish directly. Observable choices use staged defaults and bind both
  document version and staging revision. Candidate preview uses the production
  resolver without a live refresh loop, and unavailable preview does not save or
  erase the candidate. Tests cover ten layout stages without writes, one explicit
  save, discard, stale revisions, permission loss, producer/consumer contracts,
  compiled host refresh/navigation/history, and preview accessibility. This does
  not yet establish full W4/W7 parity: Explore-to-editor candidate handoff and
  authenticated live-browser workflow verification remain separate work.
- The Ops execution-diagnostics slice now has a mission-authorized read boundary
  and colocated semantic TypeScript contracts/validation. Published definitions
  are inspected through the existing resolver; plan, request, frame, cache and
  source-execution metadata are explicitly read-time inspection evidence, not a
  reconstruction of an earlier viewer session. Recorded refresh/invalidation
  decisions remain a separate scoped collection, with durable versus process-local
  provenance and explicit unavailable states. Inspection failure does not erase
  recorded decisions. Collections contain at most 50 distinct rows, with a limit
  indicator, exact diagnostic identities and allowlisted bounded scalar details;
  source values, raw provenance and raw cache-key parts are not serialized.
  The coordinated diagnostics DTO is now version 2, with an explicit row kind.
  Plan warnings are selectable rows with their actual code, severity, scope and
  affected placement/frame/field/request/source identities. Warning identities
  are derived from those allowlisted fields and dashboard scope, not historical
  event IDs; reordering preserves them and duplicate projections collapse.
  The plan summary retains the total warning count, while its 50-row collection
  bound includes the summary and signals omitted distinct warning rows. Free-form
  warning messages, arbitrary details, links and evidence are not serialized.
  Exact warning identities are rejected if malformed rather than truncated.
  Retained sessions with an older DTO version renew their evidence and token;
  their old action tokens are not admitted by the current page adapter.
  The feature-local Vue view renders all seven collections with controlled
  master/detail selection and filtering of the loaded rows. Selection changes
  do not rerun inspection; missing selections are not replaced, and filtered-out
  selected evidence remains visible. Identity copying preserves literal text
  and reports clipboard failures without claiming success. The real persisted
  producer contract check also renders every collection through Vue, including
  unavailable, limited, durable and process-local evidence.
  Storybook imports the focused public `execution-diagnostics` entry and exercises
  filtering, selection, partial availability and missing evidence in Chromium;
  these are isolated presentation scenarios, not authenticated Ops route proof.
  The host-side diagnostics page-session adapter now separates view selection
  from admitted runtime context. Every preparation and action reauthorizes the
  published resource; view-only navigation retains the inspection and token,
  while runtime-context changes rotate the token. Explicit inspection refresh
  uses an exact next sequence, and publication changes flag retained evidence
  instead of silently replacing it. Permission loss clears retained evidence,
  including on malformed action requests. Runtime queries preserve admitted
  scalar values exactly and reject unsupported selectors rather than dropping
  them. HostPageLive now connects this adapter to the compiled
  `dashboards.execution-diagnostics` contribution on the existing authenticated
  Ops route, retaining its mission-operation policy. The feature-local page
  wrapper uses URL-backed selection and explicit single-flight inspection;
  failed or mismatched replies hide old evidence and require a fresh host reload.
  Viewer links preserve supported effective runtime context, while unsupported
  replay-run context has no diagnostics link. The historical remote surface now
  links to the canonical host page instead of rendering its incomplete producer.
  Persisted LiveView-to-Vue checks cover the actual page DTO and refresh replies;
  mounted BrowserHost tests cover selection and in-memory history restoration
  without replacing the rails. These are not live-browser workflow evidence.
  W5.3 remains incomplete: context-preserving typed drilldowns to Explore,
  Sources, Catalog and AdminRuntime, and authenticated browser workflow
  verification are still required.
- Explore now has a domain-owned vertical slice under `features/exploration/`,
  composed through the compiled `dashboards.exploration` Ops contribution. Its
  existing authenticated mission route and operation policy are unchanged; no
  frontend installation or release lookup is needed. The legacy remote entry
  links to the canonical host page with the original query instead of retaining
  the placeholder investigation implementation. Its finite query admission retains
  source-dashboard identity and legacy alias conflicts, rejects unknown or
  malformed selectors, and is covered by a real producer-to-Vue redirect check.
  The read has a finite URL admission module, an unsaved resolver
  request compiler, and a mission-authorized server read. Telemetry history passes
  its row bound and ordering into the source query; both participate in plan and
  source identity. Relative windows use the server clock, explicit timestamps
  retain microseconds, and navigation-only sample selection does not change the
  execution identity. Contact reads resolve a nonempty, mission-owned endpoint
  set once while retaining the original contact URL. Missing or foreign scope
  resources do not become mission-wide queries. Regression coverage also exposed
  and corrected primary/overlay data-context routing in the engine: primary
  source selectors are retained, while overlays remove primary selectors and
  retain their own per-source selections. Missing explicit primary sources or
  bindings no longer execute the default source.
  A version-two browser projection emits only bounded observations, exact
  timestamps, actual sample/source/binding identities and sanitized warning codes.
  It excludes resolver internals and arbitrary adapter metadata. Duplicate row
  identities and malformed frames are rejected before serialization. Empty,
  unavailable and unsupported queries remain distinct; unsupported selectors
  never silently become broader reads. Result status considers all admitted
  warnings, including errors omitted from the bounded display collection.
  Every host refresh reauthorizes the read.
  Query controls and sample selection use host navigation, retaining binding and
  origin context. Following an observation freezes the executed time window and
  preserves timestamp microseconds and pins inspection to the returned source and
  binding when supplied by the row. Selection now inspects the physical sample through the
  authorized read. Failed refreshes hide old observations and sample details.
  The Ops slot now supports explicitly declared read-only navigation without an
  action token or execution capability; replaced snapshots invalidate old ports.
  Navigation guards are rebound with the admitted port and disposed on unmount.
  Persisted producer-to-Vue checks cover the actual browser model. Mounted host
  tests cover query changes, selected-sample URLs, history restoration, failed
  refreshes, permission-loss snapshots and retry without replacing the Ops rails.
  Storybook imports the public exploration entry and exercises populated, empty,
  unsupported-scope and failed-refresh states in Chromium. A screenshot confirms
  the retained production styling. These are fixture-backed presentation and
  component/transport checks, not authenticated live-browser evidence; the in-app
  browser connection was unavailable at this verification attempt.
  Explore is not workflow-complete: authenticated selected-sample browser
  verification, saved-question and authoring actions, original-view restoration and typed diagnostics drilldowns remain
  outstanding. Operational-observable ordering/bounds and telemetry transport,
  station and link scope semantics also remain required; the new read currently
  returns explicit unsupported errors for these instead of ignoring selectors.
  The version-three Explore DTO includes an authorized source-dashboard reference.
  It reads only the published document's identity and name, without executing its
  widgets or falling back to a draft. Foreign, missing, archived and unpublished
  origins have the same unavailable state and do not erase investigation results.
  The feature builds the same-mission URL from this exact reference; arbitrary
  hrefs cannot enter the contract. Opening the source dashboard uses its published
  defaults, explicitly not the Explore filters or a reconstruction of the original
  view. Failed refreshes hide the stale reference. Explore currently retains only
  the source dashboard ID, so restoring the original dashboard runtime context
  needs a separate admitted navigation contract. The editor authoring handoff also
  remains outstanding: its widget form cannot yet represent all Explore time and
  source-query controls. These must not be silently discarded during migration.
  The authorized read now exposes server-only query preparation separately from
  source execution. Preparation retains the admitted navigation query and exact
  effective time, scope, data, limits and sampling request, including contact
  endpoint resolution; it does not acquire the telemetry runtime, inspect samples
  or create durable documents. Preparation still reads authorization and scope
  resources. Its result is neither a browser DTO nor an availability receipt or
  reusable authorization grant: execution always prepares afresh, and future
  authoring must independently reauthorize. Tests cover query equivalence,
  inspection-only source selectors, replay bounds, unsupported inputs, revoked
  permissions and absence of telemetry reads or dashboard writes. This is a
  handoff prerequisite, not an implemented Add-to-dashboard flow. Retaining an
  Explore widget's own time window and query limit/order would require a document
  contract extension; adopting dashboard defaults instead requires explicit
  review. Neither behavior is silently selected by this preparation boundary.
- Physical sample inspection has a storage read contract composed into the
  authorized Explore read. `PhysicalSampleQuery` requires tenant, mission, point,
  sample, realm and resolved source/binding identities. Optional spacecraft,
  endpoint and clock constraints are validated and retained; empty endpoint
  scopes and history/selection controls are rejected. The read facade dispatches
  through a captured history policy, with no fallback to another backend,
  latest values or effective canonical selection. Postgres uses its exact
  tenant-scoped record lookup; ETS checks stored tenant evidence while scanning
  exact-ID candidates in bounded chunks. QuestDB applies every query constraint
  before a two-row ambiguity bound and validates returned tenant/source identity,
  clocks, quality and value encoding. Missing, ambiguous, unsupported, malformed
  and unavailable reads remain distinct server-side outcomes. Tests use persisted
  Postgres records, real ETS tables and an injected QuestDB HTTP executor; they
  are not live QuestDB or authenticated Explore workflow evidence.
  The source registry now exposes optional adapter inspection against an already
  resolved binding, without re-resolving a mutable default. It validates binding
  ownership and explicit source selectors, compiles physical selection from the
  planned point/scope/window, resolves execution-only credentials, and uses the
  captured history policy. Unsupported scope selectors and unresolved clocks
  fail closed; endpoint constraints and historical segment bounds intersect.
  Adapter results carry stored tenant identity separately from the legacy sample
  struct, and the registry checks it along with sample/source/scope identity.
  Inspection observes the source circuit breaker and execution timeout; its
  request-owned worker contains adapter crashes and is stopped with its caller.
  Tests cover adapter overrides, credential material, failed reads and worker
  lifecycle. Registry-owned execution receipts now retain resolved bindings in
  server-only source and dashboard results, including cache hits and historical
  segments. Adapter-provided receipts cannot replace them, and old results
  without receipts do not trigger a fresh default lookup. The authorized Explore
  read inspects only those captured bindings under the planned scope and clocks.
  Multi-segment inspection has one overall budget, rejects ambiguous records and
  does not treat a failed candidate read as proof of a unique match.
  Persisted tests change a binding during row execution and prove inspection
  still uses the original source; selection can also inspect records outside the
  visible history page.
  The version-two DTO adds finite inspection states and allowlisted stored
  identity, quality, exact generation/receipt clocks and record references.
  Raw and engineering values are bounded literal JSON or binary hex; deep,
  oversized and unsupported runtime values have explicit display states.
  Credentials, retained bindings and arbitrary provenance are not serialized.
  The Vue detail view lives in the exploration vertical slice, with source
  identity visible and secondary provenance collapsible. Recorded revision state
  is explicitly not a current canonical-status assertion. Inspection failures
  preserve query rows; failed refreshes hide both rows and details.
  Authorized producer-to-Vue rendering, mounted host selection/history tests and
  seven Chromium stories cover this composition. Desktop/mobile preview
  screenshots retain the production styling and show no page-level horizontal
  overflow. These are not authenticated live-browser workflow evidence: the
  in-app browser connection remains unavailable. Live QuestDB and authenticated
  end-to-end navigation verification are still required.
- Historical telemetry frame merging preserves positional sample IDs, including
  duplicates and unknown IDs, rather than treating them as a set. Per-segment
  field alignment is checked before concatenation, so opposite length errors
  cannot cancel out into a plausible merged frame. Registry-owned source
  identity replaces adapter claims, and compact row-count spans preserve each
  merged observation's source, binding, dataset and realm without inferring
  provenance from timestamps. Existing merged results without valid spans fail
  projection instead of guessing. Exploration validates bounded segment batches,
  globally orders observations and then applies the displayed row limit.
  Selected source and binding IDs are separate navigation-only query fields:
  they filter already captured bindings for physical inspection and do not
  replace the historical query's source context. This avoids requiring one
  historical source to cover the entire original window. Selection pins must
  appear as a pair with a sample identity; unknown pins do not trigger a fallback
  source lookup. Clearing selection removes the pins without losing query or
  origin context, and highlighting distinguishes duplicate IDs across sources.
  Regression coverage includes repeated/nil IDs, overlapping clocks, malformed
  alignment/spans, nested merges, global limits and batches larger than the
  workspace presentation bound. A persisted two-source Explore test follows the
  newest row into physical inspection, preserves the table and renders both real
  DTOs through Vue; a forged selection causes no physical read.
- GridStack and uPlot are installed dependencies owned by the dashboard module,
  pinned to the existing vendored versions (10.3.1 and 1.6.32). The copied runtime
  and CSS assets, legacy Ops vendor shims, and raw-library module exports are
  removed. The complete comparison against integrity-verified published packages
  found only formatting and small syntax cleanups, not Cadence-specific behavior;
  Cadence's chart/grid styling overrides remain separate and unchanged.
  Components import the package runtimes directly. Public `workspace.css` and
  `charts.css` entries compose library CSS before the Cadence dashboard patterns,
  keeping library paths internal and host CSS independent of Ops Console.
  These are ordinary build dependencies, not federation singletons or a library
  version upgrade. Node producer-render checks ask Vite to process GridStack 10's
  extensionless ESM imports; the old UMD-only global `self` workaround is removed.
- Storybook consumes the host's public mission entry and the dashboard module's
  focused `charts` entry instead of historical remote Vue wrappers. The chart
  entry exposes the existing feature implementation and runtime port without
  importing workspace-only GridStack code. Storybook's CSS sources include the
  relocated host areas and dashboard module, preserving production navigation
  icons and feature styling. Share/snapshot contributions leave the main landmark
  to the Ops host rather than nesting a second main landmark inside it.
- Mission shares and definition snapshots now live in the dashboard module's
  `features/sharing/` slice, with compiled `dashboards.share` and
  `dashboards.snapshot` contributions. Their existing authenticated Ops routes
  bind resource identity from the path and accept no browser context overrides.
  Every read reauthorizes mission operation; expired/revoked shares are unavailable.
  Shares follow the current published definition and never fall back to a draft.
  A share without an available publication has an explicit no-publication state.
  Snapshots use their stored definition/version after subsequent edits or archive;
  pinned library versions are resolved without substituting the latest version.
  Definition-only views do not compose or execute runtime sources. Data-enabled
  views reuse the validated read-only canvas without acquiring author authority.
  Captured runtime context is finite and bounded; empty context preserves document
  defaults, and fixed time windows retain exact boundaries (up to 31 days).
  Fixed windows are not frozen telemetry copies. The complete definition is
  displayed as escaped JSON, bounded to 512 KiB, with scope/version and
  section/placement identity checked against the canvas. The historical remote
  entries contain canonical-host links only; their mismatched placeholder
  producers and duplicate viewers are removed. Persisted producer-to-Vue tests
  cover both visibility policies, publication state, immutable snapshots and
  scope rejection. An isolated production-browser fixture covers settings links,
  refresh, revoked-share containment, retained rails, direct reload and desktop/
  600px layout. Authenticated live-mission browser verification and live delivery
  remain outstanding for the broader migration.
- Dashboard settings now uses the compiled `dashboards.settings` contribution in
  `ops.page`, with its semantic contracts, Vue form state, renderer and tests
  colocated in `features/settings/`. The existing URL retains its authenticated
  application session and dashboard-author policy. Path identity, page token,
  user/organization identity, observed version/revision and an ordered command
  sequence gate writes; every action rechecks authorization. Confirmed writes
  require an explicit reload before another change. This is page-instance
  duplicate protection, not durable cross-session exactly-once execution.
  Read-only collection pagination does not consume the write sequence. Failed
  reads retain the last admitted model; pagination and refresh retain unsaved
  form values and native input identity. A concurrently changed revision requires
  explicit review/rebase or discard before saving local metadata. Created shares
  and snapshots expose scoped links, and export uses the existing authenticated
  attachment endpoint for the latest saved draft. The old remote entry is now a
  canonical-host link only; its placeholder form/collection producer is removed.
  Producer-to-renderer tests cover persisted DTOs; host tests cover token retirement,
  revoked access, conflicts, failed refresh and export authorization/audit records.
  An isolated production-browser fixture exercises editing, pagination, concurrent
  revision review, save/share/snapshot/revoke/archive, retained Ops rails and direct
  reload without remote assets. Desktop and 600px layouts were inspected. This is
  synthetic transport evidence, not an authenticated live-mission browser run.
- The settings domain boundary now provides persisted, author-authorized semantic
  reads and observed-version/revision commands for metadata/defaults, share
  creation/revocation, snapshot creation and archive. Sharing effects hold a
  dashboard lock through persistence; revocation additionally binds the share to
  that dashboard. Save/archive enforce revisions in document persistence so
  publication-only changes conflict without moving runtime invalidation before
  commit. Legacy documents use the existing schema migration path before the
  observed-version check; migration cannot silently advance an action's
  precondition. Share expiration is explicitly nullable or 1–8760 hours. Metadata pages
  are capped at 25 records and omit raw snapshot documents and stored runtime
  context. Snapshot creation captures the observed draft with an empty explicit
  runtime selection; it does not publish or claim to freeze telemetry values.
  A feature-local semantic consumer validates scope, versions, bounds and finite
  values against persisted producer fixtures. Editor and settings now share the
  demonstrated runtime-defaults JSON decoder. The settings route now consumes
  this boundary through the host admission and compiled contribution described
  above. Share and snapshot destinations now use the sharing slice described
  above; dashboard diagnostics still requires its own migration.
- Playlist authoring and presentation now live together in `features/playlists/`,
  with separate `dashboards.playlists` and `dashboards.playlist-present`
  contributions through `ops.page`. Both existing URLs retain their authenticated
  application session and author/operator policies; presentation identity comes
  from the path, not a query override. No installation or release lookup is needed.
  The author builds an ordered queue of up to 100 entries, including intentional
  repetitions, with keyboard-accessible reorder/remove controls. Read-only,
  paginated dashboard search preserves the unsaved queue and ignores stale replies.
  Playlist and choice pages contain at most 25 rows. Creation independently checks
  authority and locks active mission-scoped references before persistence.
  Page tokens and sequences prevent duplicate submissions in the active instance;
  successful or uncertain creation stays consumed through ordinary refresh until
  explicit reload. This is not durable cross-session exactly-once delivery.
  Presentation reuses the module's read-only published snapshot renderer, binds
  position and play/pause to bounded URL state, and supports manual or timed
  rotation. Unpublished, archived or unavailable entries retain their positions;
  no draft is substituted. Published names come from the same saved snapshot.
  Automatic advancement stops on hidden tabs, unmount and unresolved navigation;
  refresh permits recovery. The freshness label explicitly distinguishes these
  snapshots from live streaming. Persisted producer/renderer, host transport and
  mounted interaction tests cover the boundaries. An isolated production-browser
  fixture covers queue search/order/repeats, dirty navigation, creation receipts,
  published/unavailable positions, automatic rotation, retained Ops rails and
  direct reload. No live mission writes were made; authenticated integration,
  live delivery and the remaining dashboard workflows remain separate work.
- The reusable dashboard widget library now composes `dashboards.library` through
  `ops.page`, without an application installation or release lookup. Browsing,
  definition authoring, immutable version history, current-draft consumers,
  draft placement, contracts, validation and tests live in `features/library/`.
  Phoenix retains the existing authenticated application session and
  `:ops_dashboard_author` policy. Its semantic read model bounds library,
  version-history, consumer-dashboard and target-dashboard pages to 25 rows;
  consumer metadata does not expose dashboard documents or placement overrides.
  New library versions check the observed latest version under the item lock.
  Adding a library widget pins the exact selected version into a new dashboard
  draft against its observed document version; it never publishes or upgrades
  existing pins. Host commands are bound to user, organization, mission, path,
  token, sequence and the displayed selection. Uncertain effects require explicit
  reload, while ordinary refresh preserves the review lock. These are page-instance
  guards, not durable cross-session idempotency guarantees.
  Feature-local JSON admission enforces a 32 KiB envelope and bounded structures;
  malformed explicit fields are rejected locally and independently in Phoenix.
  Tests exercise real producer DTOs in Vue, scope and stale-write rejection,
  immutable pins, bounded consumers, retired tokens and duplicate submission.
  An isolated production-browser fixture checks creation, version append, exact
  draft placement, dirty navigation and target selection, conflict/reload,
  retained native controls and Ops rails, and receipt navigation to the editor.
  Browser effects use fixture data, not a live mission. Authenticated browser
  integration and the remaining dashboard workflows are still required.
- The dashboard editor route now composes `dashboards.editor` through `ops.page`,
  with `dashboard_id` bound as the resource identity and no installation/release
  lookup. Its Vue inspector, state, DTO, validation, contribution and tests live
  together in `features/editor/`; the host owns placement and navigation only.
  The editor supports metadata, sections, embedded widget definitions, numeric
  layout editing, current-draft publication and a saved-draft snapshot preview.
  Library and unsupported definitions cannot be converted into embedded widgets.
  Phoenix's existing authenticated application session and
  `:ops_dashboard_author` policy are unchanged. `OpsEditorPage` binds commands
  to user, organization, mission, dashboard, path, token, sequence and the
  displayed document version. Uncertain/conflicting effects require explicit
  saved-draft reload; ordinary refresh does not unlock them. These are
  page-instance guards, not durable cross-session exactly-once guarantees.
  The optional `OpsPagePort.guardNavigation` registers an instance-owned leave
  guard with the host router; the editor also handles native before-unload.
  Component and isolated production-browser checks cover declined navigation
  and Back, draft/native identity, explicit reload and retained Ops rails.
  Browser saves use a fixture, not an authenticated live mission.
  The feature-local observable picker reuses the canonical mission catalog
  provider for active and derived telemetry, and the domain registry for backed
  operational observables. Searches are bounded and authorized against the
  displayed draft, filter operational choices by widget and scope, and do not
  consume save sequences. Stale search responses cannot replace current choices;
  selected IDs survive unavailable or changed catalogs. Selection remains a local
  draft edit. Direct ID entry is retained as an explicit advanced control.
  Editor DTO v3 includes document grid geometry and the domain's layout bounds,
  plus runtime defaults distinct from the widget-form defaults.
  Its feature-local layout canvas uses the same GridStack engine as the viewer;
  the unchanged vendored runtime now lives under module-local `shared/gridstack`.
  Existing public runtime exports remain compatible. Authored placements are
  arranged within their sections with saved-widget previews where available,
  pointer drag/resize and keyboard equivalents. Entry does not autosave or compact
  the document. Gesture completion captures displaced neighbors into a local
  draft; explicit save uses the existing observed-version layout command.
  Navigation is guarded during gestures and unsaved layout edits. Discard and
  uncertain-write review retain the same editor lifecycle. Repeated placements
  show a representative saved instance while editing their authored layout.
  Runtime defaults now have feature-local quick controls for time mode/axis,
  data realm/source selection/view and limit semantics, alongside a complete
  JSON editor for scopes, source contexts, overlays and other authored settings.
  Quick controls preserve unedited settings. JSON has a 32 KiB envelope and
  bounded nesting, collections, strings and numbers; domain context validation
  runs before persistence. Invalid JSON remains local; known domain rejection
  retains the editable draft. Explicit save uses the same permission, sequence,
  observed-version and immutable-snapshot boundary as other authoring commands.
  Publication remains separate. These controls configure document defaults,
  not the viewer's current session or resource authorization. Domain context
  validation is not proof that a referenced source/replay resource is available.
  Authenticated browser authoring remains work;
  numeric position inputs remain available alongside the layout canvas.

- Dashboard version history now contributes `dashboards.activity` through
  `ops.page`. Its component, state, validation, registration and tests are
  colocated in `features/activity/`. The existing authenticated Ops route is
  retained without an installation/release lookup. Phoenix supplies bounded
  metadata pages (25 versions and 25 lifecycle events), scoped independent
  cursors, and only the selected document's summary, never raw documents or
  audit payloads. Restore appends an attributed draft snapshot; publication
  changes the published pointer without replacing the latest draft. Both require
  the displayed draft version and observed document revision, including when
  another publication changes only the pointer. The host binds the selected
  version and page-instance token/sequence. Conflicting or uncertain writes
  require explicit history reload; ordinary refresh cannot unlock them.
  Publication issue deep links are acknowledged, but detailed issue inspection
  is not implemented in this metadata view. Authenticated live browser writes
  remain a separate verification gate.

- Dashboard authoring now has a frontend-delivery-independent domain command
  boundary (`Cadence.Dashboards.Authoring`). Rename, section, widget, layout and
  current-draft publication commands require the document version the operator
  observed; a fresh server read cannot silently replace that precondition.
  Commands recheck scoped author permission, retain persistence's optimistic
  transaction and publication-readiness checks, and attribute draft snapshots
  to the authenticated user. Inputs have exact bounded shapes; missing section
  or placement identities cannot become additions. Widget edits preserve
  unedited binding, override, repeat and layout settings, support all eight chart
  observables, and validate operational observables against the widget's selected
  scope. Library definitions remain outside embedded-widget editing.
  The editor composition above now consumes this boundary. Authenticated browser
  editing and the remaining workflow coverage are still required.
  The workspace snapshot contract also now uses the domain/chart enums `hidden`
  and `bold`, with producer-to-consumer and real Vue markup regression coverage;
  the unsupported aliases `never` and `thick` are rejected.

- The published dashboard viewer route now composes the compiled
  `dashboards.workspace` contribution through `ops.page`, with the dashboard
  path parameter bound as `resourceId`. `OpsWorkspacePage` admits URL context
  before the authorized domain read; neither a frontend application installation
  nor a remote release is needed. It retains Phoenix's existing authenticated
  `:application` live session and `:ops` policy. Page tokens bind user,
  organization, mission, dashboard and path, survive same-path refresh, and are
  replaced on context changes. The feature admits only published snapshots,
  presents all seven widget kinds, and owns its context controls and navigation
  links. The host owns route transitions, refresh admission and failure isolation.
  Latest snapshots are explicitly labeled as snapshots, not live delivery.
  URL controls currently admit finite time-axis, realm, data-view and limit-mode
  enums plus range/archive intervals of at most 31 days, normalized to UTC.
  Unsupported source/replay and drilldown parameters fail closed rather than
  silently changing the requested context. Source-specific resource admission,
  replay controls, evidence/drilldown and scoped live delivery remain required
  work. Editor and activity links now target compiled module contributions.

- `WorkspaceSnapshotCanvas` now adapts admitted semantic snapshots inside the
  dashboard workspace feature and renders the existing module-owned canvas,
  grid and seven widget kinds. Widget-specific adapters preserve null values,
  numeric chart envelopes, event endpoints and explicit unknown health; malformed
  or unavailable widget data retains its placement. Grid geometry comes from
  the document. Instance-scoped DOM and chart correlation identities avoid
  cross-canvas collisions; ordinary data refreshes preserve native/disclosure
  state, while resource/context/geometry changes reset it. The existing chart
  now keeps explicit null samples as gaps instead of coercing them to zero.
  This remains a **read-only snapshot renderer** within the migrated viewer: it
  intentionally cannot inherit an ancestor's action/subscription bridge and
  does not advance a live clock without live delivery. Primary frames, chart
  comparisons and annotation geometry render; additional overlay roles are
  explicitly disclosed but not yet adapted to source-specific limit/quality
  presentations. Evidence/drilldown actions, richer frame labels, editor
  interactions, extended source/replay URL admission and scoped live updates
  remain integration work. Real Elixir producer tests
  now traverse the presentation adapter as well as the DTO validator. Isolated
  production-browser coverage exercises all seven kinds in the actual host Ops
  frame, refresh identity, disclosure, context reset and teardown/remount; it
  does not establish authenticated viewer or editor workflow coverage.

- The dashboard workspace rendering chain now lives together in
  `dashboards-and-exploration/features/workspace/`: canvas, grid, widgets,
  comparisons, editor guard and telemetry chart, including the existing GridStack
  and uPlot assets. Legacy Ops paths delegate to the module's public `workspace`
  entry; the domain-neutral clipboard control lives in shared UI. Vendor styles
  follow their owning renderers and the Ops stylesheet scans module source.
  Charts consume an explicit instance-provided version-1 runtime port with finite
  actions and append/selection subscriptions, without a module-side browser-event
  fallback. The compatibility adapter admits declared actions and delegates to
  its own Ops bridge; its inbound telemetry broadcasts remain legacy global
  transport debt. The port is not an authorization boundary or a semantic DTO
  validator. This initial extraction established renderer ownership; the
  published viewer composition described above now uses semantic snapshots.
  The legacy dashboard read producer still returns an empty canvas. Remaining
  editor workflows and scoped runtime delivery remain required work. The renderer
  extraction itself changed no routes or Phoenix authority.
  An isolated production-built browser fixture covers actual grid/chart rendering,
  native identity, disclosure persistence and chart subscription remounting in the
  host Ops frame. It does not prove authenticated editor/viewer workflows. Direct
  unbundled fixture loading still rejects the existing GridStack UMD default
  import; production bundling succeeds, but dev-server interop remains unverified.

- The workspace now has a version-1 semantic snapshot boundary:
  `Cadence.Reads.Dashboards.Workspace` independently checks mission/operator
  scope and author policy for draft reads. Published viewing never falls back
  to a draft. `Resolution.resolve_with_document/2` returns the exact hydrated
  document used by the engine, so snapshot construction does not independently
  re-fetch library definitions. Expanded placements, all seven registered widget
  kinds, primary/overlay frames and annotation geometry retain domain ownership.
  Unsupported definitions and malformed frame buckets remain explicit unavailable
  placements rather than disappearing. Raw adapter metadata, evidence and action
  payloads are excluded from this read DTO. The module's colocated validator binds
  organization, mission and dashboard identity and checks the versioned shape.
  Persisted-document and actual engine tests feed real Elixir output through that
  TypeScript validator. This is a read/contract foundation, not an active host
  viewer: URL-context admission, semantic-to-renderer adaptation, evidence/action
  ports and live delivery still require integration before replacing the route.

- Dashboard blank, clone and import creation now live together in
  `dashboards-and-exploration/features/creation/`, beside their presentation,
  contracts, validation, contribution and tests. The existing creation URL uses
  `ops.page` and admits `mode` and `source_dashboard_id` as URL state.
  `Cadence.Reads.Dashboards.Creation` supplies authorized semantic context;
  `Cadence.Dashboards.Creation` independently authorizes and persists a new
  target-scoped document. Clone copies the fetched document only if its version
  matches the displayed source; import uses the existing document/export codec.
  Phoenix binds submission to its page token, route, source version and sequence.
  Known pre-persistence validation failures permit correction; successful or
  uncertain submissions stay consumed through refresh. These are page-instance
  guards, not durable cross-session idempotency or atomic source lifecycle locks.
  The legacy Ops creation component delegates to the public module entry; its
  historical federation producer/action contract remains migration debt.
  Library, playlists, settings and other dashboard routes still
  need migration. Real producer/renderer tests cover all three modes. Isolated
  actual-host browser coverage verifies directory-to-creation navigation,
  cancellation, native draft/rail identity and submission locking through
  refresh and contribution recovery, with remote requests blocked and no live
  effects. Authenticated browser creation remains unverified.

- The existing Ops frame now lives in the host's
  `ops-workspace/features/frame/` slice: header, rails, navigation construction,
  context presentation and rail behavior remain host composition. The generic
  application shell delegates to that frame without changing native controls.
  Dashboard directory UI, contracts, URL construction, state and tests live in
  `dashboards-and-exploration/features/directory/`. Its route uses the named
  `ops.page` version 1 slot and no longer requires an Ops remote release.
  `Cadence.Reads.Dashboards.Directory` authorizes a semantic, versioned DTO with
  personal stars, active/archived filtering, description/tag search, actual
  widget-count/update-time sorting, and 50-row pagination. Filters are URL state.
  Scoped commands live in `Cadence.Dashboards.DirectoryActions`; Phoenix binds
  effects to the authenticated page token, displayed row/version and sequence.
  Uncertain outcomes remain locked through read refresh. These are page-instance
  admission guards, not cross-session exactly-once or atomic lifecycle guarantees.
  The historical Ops directory component delegates to the module's presentation;
  its historical federation producer/action contracts remain migration debt.
  Other Ops routes still use the remote. Rail domain summaries also still need
  domain-owned contribution contracts; this frame extraction does not claim they
  are already generalized slots. Isolated actual-host browser coverage verifies
  filtering/Back, rail and native-input identity, star refresh, and uncertain
  restore containment with release requests blocked. Authenticated browser
  coverage and live dashboard effects remain unverified.

- Communications overview, setup validation, transport/routing/station directories
  and details now compose through `mission.page` version 1. Each of the five
  vertical features declares its own registrations; the module entry only
  assembles them. The host admits identity, version, organization, mission and
  optional path-owned resource identity; feature validators admit the DTO and
  bind detail data to that resource. `Cadence.Reads.Comms.Pages` owns the shared
  bounded producer and independently authorizes mission reads; the historical
  federation provider is a query-identity adapter to that same implementation.
  These eight routes no longer require frontend installation or release admission.
  Existing native GET search forms and host-routed pagination/detail links remain.
  Collection sort/direction now reach the stores before pagination rather than
  merely appearing in response metadata; existing store defaults stay intact.
  Transport creation, routing creation, and station creation/edit now use four
  additional feature-local registrations with explicit validate/save ports.
  Phoenix binds each form to user, organization, mission, path and page token,
  remembers the exact validated draft, and consumes submission before effects.
  Same-instance refresh preserves draft and submission state; uncertain saves
  remain locked with a records-review link. These are page-instance guards, not
  cross-session exactly-once guarantees. Commands live in
  `Cadence.Management.CommunicationsSetup`, a management-plane coordinator;
  the legacy action provider delegates without changing durable action identities.
  Provider directory, creation and detail now also use feature-local mission
  registrations, bringing Communications to fifteen mission-page contributions.
  Provider reads live in `Cadence.Reads.Comms.MissionProviders`; registration
  lives in `Cadence.GroundNetworks.MissionProviderRegistration`. Existing
  control-plane validation/synchronization and management archival remain their
  authoritative commands. The host binds observed provider versions and ordered
  page-local effect sequences; uncertain effects stay locked across read refresh.
  Creation pins the displayed account/grant versions. Bounded-policy timing
  fields now survive registration instead of being dropped by the old adapter.
  These admission checks do not provide atomic external-effect or cross-session
  exactly-once guarantees. Legacy provider adapters delegate to the same owners.
  Overview and the provider directory still consume
  their historical presentation DTOs; this move does not claim that DTO cleanup is
  finished. An isolated actual-BrowserHost check covers all eight pages, native
  GET search/empty results, pagination, Back and reload with release assets
  blocked. A separate isolated BrowserHost check covers all four setup forms,
  native input/draft identity across refresh, and locked uncertain outcomes with
  release assets blocked and no live effects. Provider browser checks also cover
  directory-to-creation navigation, preserved native drafts on refresh, confirmed
  fixture creation navigation, and uncertain-effect locks through feature and
  host refresh. Authenticated browser coverage for
  this cohort remains unverified.

- Provider-account directory, registration and detail Vue implementations now
  live in Communications' `features/provider-accounts/` slice with feature-local
  contracts, draft handling, event mappings and tests. Historical organization-admin
  entries delegate to a public package export; application/surface/action identities
  and Phoenix authorization, credential and grant effects remain unchanged.
  Real producer DTO rendering and mounted interaction tests cover this extraction.
  Registration now admits its bounded, known-field DTO in Communications and uses
  a feature-owned workflow. Validation replies update the mounted form, preserve
  stable hidden references and coalesce newer drafts. Numeric inputs serialize as
  strings, including zero quotas. Pending submissions are frozen; stale replies
  cannot navigate a new page, and uncertain outcomes prevent duplicate attempts.
  Detail now also owns bounded DTO admission, grant drafts and its action workflow.
  Actions carry observed account/credential versions and, for revocation, the grant
  version. Phoenix checks stale snapshots and account/grant ownership before effects;
  these admission checks are not an atomic external-effect or exactly-once guarantee.
  Confirmed receipts update the mounted detail; uncertain results lock mutations
  while permitting read-only refresh. Sandbox producer/consumer and interaction
  tests cover these paths. The directory now admits a bounded, organization-bound
  data model from `Cadence.Reads.Comms.ProviderAccountDirectory`; classes and layout
  belong to Vue instead of the old server attribute tree. The host composes it
  through `organization.page` version 1, without frontend installation/release
  admission. Historical directory entries delegate to the same producer and
  component. Registration now also uses a compiled organization-page contribution
  and explicit validate/save port, bound in Phoenix to user, organization, path
  and page token. Generated identities survive refresh and validation; navigation
  invalidates the old instance, and submission consumes it before effects, including
  partial/uncertain completion. Its historical backend provider delegates to the
  GroundNetworks domain workflow. This is a page-instance replay guard, not a
  transactional credential/account creation or global exactly-once guarantee.
  Detail now composes through `comms.provider-account-detail`, bound to the account
  URL, user, organization and page token. Scoped reads and credential/grant commands
  live in `Cadence.Reads.Comms.ProviderAccountDetail` and
  `Cadence.GroundNetworks.ProviderAccountOperations`; legacy adapters delegate.
  A monotonic page-local effect sequence rejects replay. Uncertain effects lock
  further mutation while permitting read-only refresh, without clearing grant drafts.
  These are page-instance guards, not cross-session or atomic-effect guarantees.
  Authenticated browser registration
  submission and credential/grant effects remain unverified.

- Administration diagnostics is host composition with a dashboard-owned runtime
  diagnostics contribution. The historical organization-admin surface delegates
  to that feature.
- Catalog's six page routes now render core host features under
  `apps/host/src/catalog/features/{databases,revisions,artifacts,imports}`.
  Reads live under `Cadence.Reads.Catalog`; re-import authority lives under
  `Cadence.Catalog.Reimport`. These routes do not require an application
  installation, release lookup, or remote renderer. Historical Mission & Catalog
  remote entries delegate to the public `@cadence/plugin-host/catalog` entry.
- Catalog uploads use a feature-local Vue bridge to a Phoenix-owned native upload
  form. Path-bound sessions are reauthorized before validation, cancellation, and
  submission; database creation, artifact storage, and import-job creation are
  transactional. Component and LiveView tests cover real uploads, second revisions,
  rollback, cancellation, stale navigation, and session revocation. The browser
  upload-and-import workflow still needs end-to-end verification.
- Mission directory, creation, and overview now render host-owned vertical slices
  under `mission-and-spacecraft/features/`. Reads live in `Cadence.Reads.Missions`;
  the legacy remote delegates to the public `@cadence/plugin-host/missions` entry.
  Creation is scoped in `Cadence.Missions.Creation` and bound to a page-instance
  token that is invalidated on successful save, navigation, or organization change.
  Overview retains its existing readiness aggregation; capability contribution
  contracts for that aggregation remain part of the subsequent spacecraft work.
  Read-only browser coverage verifies directory, creation form, cancellation,
  overview and direct reload with remote release assets blocked. Mission creation
  is covered by component and LiveView tests; browser submission is not yet verified.
- Browser host routing is instance-owned rather than installed as an app-wide
  Vue plugin during component setup. Teardown removes only that host's history
  subscriptions and rejects pending replies. Component tests cover same-app
  remounts; a live browser check verifies a Vite hot update without document
  reload, followed by working back navigation and direct reload.
- Mission and spacecraft application installation management now live together
  under `capability-management/features/application-installations/`, including
  their components, contracts, runtime validation and interaction tests. The host
  admits a versioned, scope-bound inventory snapshot and contains malformed data
  or failed actions. Historical remote entries use the host's public API; legacy
  host component names are retained in the component registry.
  Reads now use `Cadence.Reads.Applications.Installations` directly rather than
  federated surface registration. Exact pinned-profile eligibility, scoped
  lifecycle authority and retained installations remain intact. Component and
  LiveView tests cover both scopes and lifecycle transitions; read-only browser
  verification covers mission inventory navigation and reload with remote assets
  blocked. Browser lifecycle submission and spacecraft inventory verification
  remain unverified. Activation approvals are tracked separately below.
- Spacecraft directory and profile browsing now render host-owned features under
  `mission-and-spacecraft/features/{spacecraft-directory,spacecraft-profiles}`.
  Their reads use `Cadence.Reads.Spacecraft.Pages` without a frontend installation
  or release lookup; the five historical Vue entries delegate to the public
  `@cadence/plugin-host/spacecraft` entry. Feature-local contracts and tests cover
  producer DTOs, query controls, empty states, and immutable profile version history.
  Directory filters now reach the scoped store query, query state remains visible,
  and profile drift counts spacecraft rather than version groups. Profile detail
  navigation, labels, the empty state, and the creation link consume their actual
  producer shape. Read-only browser checks cover both empty directories, filter
  selection, direct reloads and back navigation with remote assets blocked.
  Populated spacecraft/profile browser workflows remain unverified because the
  development mission had no records at the last browser check.
- Spacecraft creation and both identity-editing routes now render the host-owned
  `mission-and-spacecraft/features/spacecraft-identity/` slice. The single form,
  draft state, action handling, contracts, validation and tests live together;
  historical new/edit entries delegate to its public API. Core reads live in
  `Cadence.Reads.Spacecraft.IdentityForm`, and scoped mutation authority lives in
  `Cadence.Spacecraft.Identity`, independently of frontend installation or release.
  Forms bind to page-instance tokens and reauthorize each validation/save. Tokens
  are consumed on successful save and rotate on navigation; stale replies cannot
  navigate a newer page. Identity edits preserve the displayed profile pin unless
  a different version or None is explicitly chosen. Legacy callers omitting a
  version retain their existing pin when the profile is unchanged.
  Component and LiveView tests cover real creation/editing, explicit profile
  versions, invalid inputs, uniqueness, forged scope, duplicate saves and revoked
  sessions. Browser checks cover the empty creation form, direct reload and
  cancellation with remote assets blocked. Browser creation submission and
  populated identity editing remain unverified; no development records were added.
- Profile creation now lives in `mission-and-spacecraft/features/profile-creation/`
  with its form, draft state, contracts, validation and tests. The historical
  `SpacecraftTypeNew` entry delegates to the host public API. Reads use
  `Cadence.Reads.Spacecraft.ProfileForm`; `Cadence.Spacecraft.ProfileCreation`
  owns scoped validation and persistence. Both host and legacy actions use that
  same boundary, including protocol choices, bounded numeric fields, available
  optional application declarations, and server-derived identity/version/scope.
  Creating a profile declares application defaults; it does not install, activate
  or load any application. The form uses the existing page-token lifecycle and
  preserves drafts across validation replies. Component and LiveView checks cover
  real creation, invalid inputs, protocol fields, duplicate saves, stale actions,
  revoked sessions and producer/consumer contracts. Browser checks cover adaptive
  protocol controls, direct reload and cancellation with remote assets blocked.
  Browser creation submission remains unverified; no development records were added.
- Spacecraft overview and readiness now live in the host-owned
  `mission-and-spacecraft/features/{spacecraft-overview,spacecraft-readiness}/`
  slices with colocated contracts, validation, fixtures and mounted component tests.
  Historical remote entries delegate through the host public API. Exact profile
  pins are retained; missing pins are explicitly unavailable, and profile binding
  alone does not claim operational readiness.
  The versioned `spacecraft.readiness` data slot composes Communications-owned
  routing setup and capability-owned status through the existing admitted status
  providers. The host renders standard status facts without domain-specific
  components. Invalid, duplicate, wrong-scope and unavailable contributions remain
  isolated from core panels and valid siblings. Provider failures are sanitized.
  Phoenix-to-Vue contract tests cover populated snapshots, SCID zero, exact version
  pins, missing profiles, navigation and authorization. Populated browser
  overview/readiness workflows remain unverified.
- Activation approvals now live in the host's
  `capability-management/features/activation-approvals/` slice. The Ops URL and
  administrator policy remain unchanged; the historical Ops renderer delegates
  through the host public API. The inbox now reads real pending requests instead
  of a constant empty list. Reads use `Cadence.Reads.ActivationApprovals`;
  decisions enter the public Management/Control activation boundaries, preserving
  exact binding-set content, human separation of duties and runtime authority.
  Tokens bind decisions to a page instance, organization and mission and rotate
  after successful decisions. Approval success is distinguished from runtime
  application needing review. Feature-local component/contract tests and
  LiveView tests cover populated requests, rejection, real runtime application,
  invalid scope, self-review, stale navigation and revoked sessions. Read-only
  browser checks cover the empty inbox, refresh and reload with remote assets
  blocked. Populated browser review and browser decision submission remain
  unverified; no development decisions were submitted.
- Communications now has a domain-owned package at `modules/communications/`
  with six vertical slices: overview, setup validation, transports, routing,
  ground stations and providers. Nineteen existing feature views have one
  implementation there; historical remote Vue entries delegate through its
  public API. Form contracts, overview DTO validation, fixtures and mounted
  behavior tests are feature-local. Status badges and finding identity helpers
  remain module-local shared presentation because several features use them.
  Ownership tests reject dependencies from domain source back into delivery
  packages and imports into sibling feature internals.
  This is a source-ownership migration, not a new release or an installation
  policy change. Federation manifests and query/action transport still live in
  the legacy remote package. Its former generic collection/detail renderer now
  delegates to the module's public read-surface entry.
  Spacecraft routing, organization provider accounts, feature-specific admission
  for provider DTOs and host slot composition remain subsequent Communications
  work. No live approved release has been republished by this migration.
  Module and remote component tests, strict type checks and production builds
  cover the relocated source. All nineteen moved Vue templates match their
  pre-migration bytes. An isolated browser DOM harness verifies overview, four
  creation forms, local navigation and reload using fixtures; it does not prove
  authenticated live-release integration or persistence workflows. Screenshot
  capture did not yield a usable visual check.
- Communications' eight canonical read surfaces now have feature-owned
  registrations and DTO admission: overview, setup validation, transport/routing/
  station directories and their details. The module boundary admits only known
  version-one registrations, contains malformed data and renderer failures, and
  rejects cross-mission and unsafe navigation. Overview presentation attributes
  and collections are bounded. Details render explicitly selected facts rather
  than arbitrary DTO keys; transport ownership is consistent with origin, and
  routing displays its pinned transport version.
  Directories render numeric counts, search, creation links and query-preserving
  pagination. Existing authenticated routes forward only their supported listing
  query keys. The scoped producer now refetches the normalized page rather than
  returning out-of-range rows with clamped metadata. Real persisted test records
  validate all eight producer payloads against their actual TypeScript consumers.
  Remote transport tests cover retry and stale query/action replies after
  navigation or unmount. A fixture-backed browser check covers all eight read
  surfaces, numeric counts, pagination/back/edit links and reload; a station
  detail screenshot confirms the retained Cadence styling. Authenticated
  live-release integration and persistence workflows remain unverified.
  No approved release has been republished.
- Communications setup-form admission now lives beside the transport, routing
  and ground-station features. The delivery wrapper uses the module's public
  form entry for transport/routing creation and station creation/editing, rather
  than passing unchecked response properties into components. Readers select
  known fields, bound collections, validate mission navigation and cancellation,
  retain exact routing selections, and check transport configuration identity
  and visibility references. Station editing binds its immutable identity to the
  edit and cancellation paths. Unknown versions and malformed DTOs fail before
  form mount; renderer exceptions have sanitized containment and retry.
  Existing form templates, actions and Phoenix authorization remain unchanged.
  Real persisted producer/consumer tests cover all four forms and caught a
  station-edit producer bug: the success tuple was passed to JSON admission
  instead of being unwrapped. That producer now admits the form data itself.
  Mounted tests cover admitted controls and event payloads; an isolated browser
  harness verifies all four forms, immutable edit identity, local navigation,
  direct reload and recovery from a malformed reply. The screenshot retains the
  Cadence form layout. Browser submissions and authenticated live-release
  integration remain unverified; no development records or approved releases
  were changed.
- Communications transport/routing creation and station creation/editing now
  own their draft-validation and save workflows inside their respective features.
  Shared workflow mechanics coalesce edits, admit only the latest validation,
  preserve drafts and show inline rejection/recheck feedback. Save requires the
  exact accepted draft; native controls are disabled while it is pending. Stale
  replies cannot navigate a replacement page. Unknown save outcomes and unusable
  successful-save destinations prevent blind duplicate submission.
  Transport validation uses the same scoped configuration builder as persistence
  and returns a bounded, origin-bound endpoint review without saving a record.
  Its review describes draft validation, not runtime readiness. Feature tests
  cover concurrent edits, context replacement, rejection, duplicate submission
  and conditional configuration fields; backend tests cover validation without
  persistence and the subsequent saved configuration.
  An isolated browser check covers editing all four forms, inline validation
  failure, explicit recheck, enabled Save and direct reload; its screenshot
  confirms the retained form styling. This uses fixture replies, not production
  provider choices. Browser persistence and authenticated live-release
  integration remain unverified; no development records or releases were changed.
- Provider-managed transport setup now uses a feature-owned, versioned selection
  receipt. Initial provider options include exact provider versions. Partial
  validation returns active downlink service choices and compatible ready
  delivery choices before a draft is complete. Selecting a delivery yields an
  explicitly selected read-only configuration preview; provider diagnostics and
  credentials are not forwarded. The transport feature retains draft values and
  relevant choices while validation is pending, clears dependent selections on
  upstream changes, and rejects stale or mismatched receipts. Incomplete drafts
  can display choices and previews but cannot authorize Save.
  Preview and persistence use the same scoped selection resolver. Saving cannot
  silently repin a changed provider, and submitted direct configuration cannot
  override provider-derived setup. Persisted producer/consumer tests cover the
  initial form, partial choices, preview, actual save, incompatible/cross-mission
  selections and version drift. A fixture-backed browser check covers sequential
  provider/service/delivery selection, read-only derived configuration, incomplete
  name gating and dependent-selection reset; its screenshot confirms the retained
  Cadence layout. It performs no form submission.
  Authenticated live-release integration and browser
  submission remain unverified; no development records or releases were changed.
- Communications provider directory, creation and detail now admit their DTOs
  inside `features/providers/`, beside their components, contracts, draft state,
  operation handling and tests. The federation wrapper delegates to the public
  `@cadence/communications/providers` entry and supplies a captured host port.
  Creation updates the selected account summary locally, preserves the draft,
  sends exact account/grant version pins and navigates only after an admitted
  success receipt. Phoenix rejects changed, foreign or revoked bindings.
  Detail operations keep the page available on failure, prevent duplicate pending
  operations and offer read-only recovery for uncertain outcomes. Refresh cannot
  regress behind the last confirmed operation version; confirmed archival returns
  to the directory because the active-detail API excludes archived providers.
  Unmounted or replaced features ignore stale replies. Diagnostic JSON is redacted
  before delivery, and private query errors are not displayed.
  Persisted producer/consumer tests cover all three page shapes, empty states,
  real creation and archival, scope and pin rejection, and diagnostic redaction.
  Mounted tests cover grant selection, policy gating, rejected/unknown outcomes,
  refresh recovery, archival confirmation and navigation races. An isolated
  browser check covers grant summaries, conditional policy fields, save gating,
  detail controls/history, directory navigation targets and direct reload;
  its screenshot confirms retained Cadence styling. No browser operation was
  submitted. Authenticated live-release integration remains unverified.
  Organization provider accounts and additional host slot composition remain
  subsequent Communications work.
- Spacecraft routing is a Communications-owned vertical feature composed by the
  host through `spacecraft.page`, version 1. The existing spacecraft routing URL
  selects a compiled `comms.spacecraft-routing` contribution without an application
  installation or release lookup. The host admits slot identity, version and exact
  organization/mission/spacecraft context, while the feature admits its own DTO.
  Missing data, unsupported registrations and renderer failures leave host
  navigation intact and support a reauthorized read-only retry.
  `Cadence.Reads.Comms.SpacecraftRouting` owns the scoped producer; the historical
  spacecraft surface and Vue entry delegate to the same owner. Routing cards show
  the transport name and version actually pinned by each rule, not the latest
  transport version. Creation/detail links retain their mission and spacecraft
  scope. Tests cover empty/populated producer contracts, immutable pins, path vs.
  query identity, foreign scopes, revoked sessions, legacy delegation, malformed
  snapshots and renderer recovery. The actual host was verified in an isolated
  browser fixture with remote assets blocked: directory navigation/back, direct
  reload and retry all pass. No browser writes or release publication occurred;
  authenticated browser integration remains unverified.
- Remaining administration pages, Ops composition,
  and the remaining domain modules still need their ownership migrations.

- The workspace static gate now checks all frontend ownership areas through Vue's
  compiler, including the dashboard module and colocated tests that lacked a
  module configuration. `pnpm check` retains formatting and type-aware lint and
  then runs `vue-tsc` across 16 projects. The root tools have an explicit project;
  CSS-only tokens need none. The driver rejects packages with unconfigured typed
  sources and incomplete or duplicate root references. Its tests compile an
  invalid Vue template, observe rejection and verify the corrected template.
  This replaces inaccurate plain-TypeScript diagnostics for SFC imports without
  introducing a permissive Vue shim. Real dashboard test typing errors were
  corrected, and the editor grid now declares its existing feature-owned props.
  This validation coverage does not close the remaining ownership or workflow gaps.

- Reservation detail now owns a semantic review under the Planning and Contacts
  contact-scheduling feature. Phoenix supplies reservation values, the separately
  selected immutable provider change, descending change history and a scoped audit
  ledger. Both histories use bounded seek pages; links preserve the selected
  change and the other history cursor. Booked plan/requirement links retain their
  original versions. The existing authenticated reservation URL is unchanged.
  Native approval, rejection and acknowledgment capture organization, mission,
  reservation, change ID, provider revision and proposal hash. Phoenix rejects
  substituted or superseded evidence and retains existing governed authorization,
  policy, grant and transaction checks. Approval receipts now read the updated
  change from the transaction result, avoiding a failure after persistence.
  The feature owns admission, reasons, pending guards and uncertain-outcome read
  recovery; delivery provides a captured host port through its public entry.
  Explicit operational extension fields are reviewable; arbitrary provider data
  is withheld and incomplete reviews cannot enable approval or rejection here.
  Persisted tests exercise native producer-to-Vue-to-action approval, all three
  receipt forms, stale inputs, paging and restricted data. Isolated Chrome checks
  exercise native approval, exact evidence, uncertain read recovery and mobile
  historical review with production styles. Authenticated live-release browser
  integration remains unverified. Contact scheduling and execution record
  placeholders remain subsequent work, alongside the other unfinished cohorts.

- Contact-record detail now owns a validated semantic record in the Planning and
  Contacts contact-scheduling feature. The scoped producer distinguishes scheduled
  and realized identities, rejects ambiguous or broken links, reads immutable
  schedule revisions, and validates the provider-change origin before linking to
  its reservation. History seeks strictly behind a revision and remains bounded
  by the reviewed revision. Paths, source endpoints and intents have independent
  bounded pages. Historical schedule windows and source references remain separate
  from current scheduled paths and realized execution evidence; old revision
  snapshots do not claim to contain missing path bindings. Standalone realized
  contacts render without inventing a schedule.
  Read refresh uses a captured public module port, retains the previous record on
  failure, rejects foreign or replaced identities and ignores departed responses.
  No raw runtime configuration or metadata is delivered. Producer/public-consumer
  tests cover real scheduled/realized records, provider-change lineage, historical
  windows, empty standalone records, scope revocation and bounded paging. Existing
  authenticated record URLs preserve path-owned identity and forward explicit
  revision/page queries. Isolated browser fixtures exercise current-revision and
  realized-contact navigation, back/reload, failed refresh retention and mobile
  layout. Authenticated live-release browser integration remains unverified.
  Contact scheduling and the remaining ADR ownership cohorts are still open.


- Contact scheduling now owns spacecraft selection, ready-route review, UTC
  opportunity search, reservation and cancellation in the Planning and Contacts
  vertical slice. Its semantic producer reads separate bounded scheduled,
  realized and provider-reservation ledgers, paged spacecraft and route readiness,
  and Policy-derived operation permissions. Existing authenticated mission URLs
  capture spacecraft and independent page queries in the host. The module uses
  native navigation to change that captured context and a narrow public port for
  the declared actions and read refresh.
  Search compares every reviewed route pin before provider traffic. Expiring
  signed capabilities retain exact scope, route, provider opportunity and booking
  identity without exposing raw provider metadata. Public expiry uses the earlier
  provider or capability deadline. Host input admission and durable idempotency
  hashing allow the opaque token only for the declared scheduling reserve action;
  other inputs retain the standard JSON limits. Search responses fit the host
  JSON boundary and explicitly mark truncation, directing operators to narrow the
  window. Cancellation requires native review and compares reservation revision,
  lifecycle and provider reference while atomically claiming the row before its
  provider call. Duplicate reservation identity compares timestamp instants at
  microsecond precision, avoiding false conflicts caused by database precision
  normalization. Confirmed effects retain their receipt if a read fails; unknown
  outcomes lock further mutations, and read refresh never repeats an effect.
  Departed replies are ignored. Provider failures retain durable reconciliation
  evidence. This increment does not close the remaining ADR ownership cohorts or
  authenticated live-release browser integration.

  Persisted producer-to-native-Vue-to-action tests exercise search, opaque
  reservation capabilities, stable retries and exact reviewed cancellation through
  the real provider HTTP client with a local test adapter. Host transport tests
  cover token admission, idempotency hashing and revoked access. Module tests
  cover malformed/scoped responses, policy permissions, pending and departed
  operations, uncertain outcomes, and failed read retention. The frontend checks,
  publication checks and full `mix precommit` gate passed. Isolated Chrome checks
  cover native spacecraft selection, search/reserve/cancel, page navigation and
  reload/back, uncertainty recovery and mobile layout. These isolated fixtures
  do not establish authenticated live-release browser integration.


- The fleet run directory now uses a feature-local semantic contract and scoped
  Phoenix reads instead of placeholder rows and a permanently stopped policy.
  Its approved policy reference remains pinned to the active version even when a
  newer draft exists. Runs show their persisted lifecycle, phase, horizon,
  requirement count, policy input and candidate Plan version. The directory has
  bounded 25-row pages with lifecycle filters and deterministic timestamp/ID
  ordering. Existing authenticated mission URLs retain their scope and now admit
  explicit page/state queries; native navigation preserves those filters.
  A captured public read port owns refresh recovery. It never resumes a planner,
  rejects mismatched context or pages, ignores departed responses and retains
  prior evidence when refresh fails. Failed policy-version reads are not shown
  as an absent policy. Module tests, persisted producer/public-Vue render checks
  and isolated Chrome navigation cover these behaviors. The creation and run
  detail workflows remain subsequent fleet work, including exact reviewed start,
  resume and repair evidence. Authenticated live-release browser integration and
  other ADR ownership cohorts remain open.

  Frontend tests, Vue-aware checks and the publication build passed. The final
  `mix precommit` run passed all 3,481 workspace tests and 42 plane tests.
  Authenticated LiveView transport tests also verify the directory's page/state
  context. This is a verified directory increment, not completion of fleet
  creation, run decisions or the broader ownership migration.

- Manual fleet creation now has a feature-local semantic policy model, native UTC
  horizon form, bounded requirement/template review pages, and an explicit queued
  run action. The preview is read-only. Its fingerprint binds the mission, exact
  approved policy, selected requirement versions, active template versions, due
  occurrences and existing generation evidence. Missing current requirement or
  template versions fail review rather than silently removing demand. Creation
  rechecks that fingerprint
  under database locks before materializing recurring demand and persisting the run
  in the same transaction. Failed creation rolls back generated demand. Previously
  generated closed requirements are neither counted as new demand nor reopened.
  Revised generated requirements outside the horizon stay excluded, and occurrence
  materialization must match the reviewed generation evidence.
  The module validates the server review and confirmed receipt, pins requirement
  and run links to durable identities, and pauses further creation after an
  unconfirmed outcome. Policy refresh is read-only and preserves confirmed evidence
  on failure. The host supplies only the captured declared read/action port and
  excludes this page from the legacy global action event handler.

  Persisted tests exercise review drift, paging, exact input references, atomic
  rollback and public producer-to-native-Vue-to-public-action behavior, including
  revoked access. Isolated Chrome checks exercise UTC form submission, review
  paging, confirmed creation, unknown outcomes, read recovery, policy absence and
  mobile layout. Fleet run detail, explicitly reviewed continuation and repair,
  authenticated live-release browser integration and remaining ADR ownership
  cohorts remain open.

  Final fleet-creation validation passed: 990 frontend component tests, 329 Node
  tests, Vue-aware checking across 16 projects, the production publication build,
  and the complete `mix precommit` gate with 3,491 workspace tests and 42 plane
  tests. The checked source revision had no drift outside its 27-file ownership
  ledger. This verifies the manual-creation increment; it does not close the
  outstanding fleet run workflows or the broader ADR target.


- Fleet run detail now owns a version-1 semantic review inside the fleet-planning
  feature. Scoped Phoenix reads expose pinned policy and requirement versions,
  coverage, optimizer decisions, resource pressure, automation history, candidate
  Plan identity and repair commitments. Independent ten-row pages retain their
  selectors in native URLs. Historical inputs are not replaced by newer versions;
  missing pinned evidence makes the review unavailable. Provider documents remain
  private. The existing `/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id`
  route stays in the browser/authenticated-scope pipeline and application LiveView
  session, preserving mission authorization and durable surface identity.

  Refresh is now a captured read-only query. Explicit continuation carries the
  observed run fingerprint, checks current planning inputs before phase advancement,
  and uses a run-scoped PostgreSQL advisory lock shared by UI and internal planner
  callers. A dedicated linked session holds that lock across worker transactions;
  each active orchestration requires one additional database connection. Contention
  rejects a second orchestration, and owner exit releases its session. This does
  not turn remote provider effects into a database transaction.

  Repair creation rechecks the exact source run, candidate Plan version, active
  policy and execution/locked-commitment fingerprint under database row locks.
  The native UTC window is bounded at microsecond precision. Creation atomically
  queues a successor with the reviewed commitments; it does not search or book
  contacts. The source Plan is preserved. Durable continuation and repair action
  IDs remain unchanged, while historical unreviewed payloads are rejected during
  coordinated rollout. The feature validates replies, retains confirmed receipts
  across failed reads and prevents another mutation after an unknown outcome.

  Persisted tests cover native producer-to-public-Vue-to-public-action behavior,
  stale inputs and execution evidence, policy changes, exact horizon bounds,
  deterministic paging, authorization, lock contention and owner-exit recovery.
  Isolated Chrome fixtures cover continuation, repair, read recovery, native
  navigation/reload/back and mobile layout. These checks do not establish
  authenticated live-release browser integration. Remaining host contribution
  composition and other ADR ownership cohorts remain open.

  Final fleet-run validation passed: 1,006 frontend component tests, 329 Node
  tests, Vue-aware checks across 16 projects, and the production publication
  build. The full `mix precommit` gate passed 3,503 workspace tests and
  42 plane tests, with no new architecture dependency violations. Isolated
  Chrome checks passed all ten scenarios with no page errors or mobile overflow.
  Source hashes remained unchanged throughout the gates, and the increment
  stayed within its 34-file ownership ledger. This completes the fleet-run
  workflow increment; host contribution composition, the remaining domain
  migrations and authenticated live-release browser integration remain open.


- The fleet directory is now a compiled `planning.fleet-directory` contribution
  to the host's version-1 `ops.page` slot. Its existing URL, page/state selectors,
  production component and historical Ops Console entry are preserved. The host
  owns placement and navigation without an installation or frontend release
  lookup. Planning and Contacts owns the contribution, DTO admission and existing
  directory workflow; its public contribution assembly starts with this feature.

  The slot now supports a captured read-only port. Phoenix binds each read to the
  current page path, actor, organization, mission and page-instance token, then
  reauthorizes it and uses the captured query. The host admits only the response
  envelope; the feature interprets the directory data. Reads return evidence
  without replacing the host bootstrap or invoking an action. Failed/malformed
  reads retain the visible directory, departed responses are rejected, and
  unchanged host envelope rerenders cannot rewind newer feature evidence.
  Initial unavailable data and renderer failures retain the host retry control
  and navigation. Existing authenticated browser scope and application LiveView
  placement remain authoritative.

  Persisted tests exercise the actual producer through the public contribution,
  captured paging, fresh reads without planning effects, wrong identities/tokens,
  injected queries, navigation departure and revoked sessions. Mounted host tests
  cover feature reuse, envelope/DTO rejection, read recovery, renderer containment
  and same-context rerenders. Other Planning pages still use their historical
  delivery adapters; their reviewed workflows need subsequent host contribution
  composition. Remaining domain modules and administration also remain open.

  Final validation passed: 1,015 frontend component tests, 329 Node tests,
  Vue-aware checking across 16 projects and the production publication build.
  `mix precommit` passed all 3,508 workspace tests and 42 plane tests,
  including the authenticated host contribution transport. The production-built
  Chrome fixture passed eight scenarios with remote application requests blocked,
  no page errors and no document overflow at 390px. The lifecycle filter now fits
  its narrower host container. The shared Ops top bar remains cramped at that
  width and is recorded as a subsequent host-frame correction. Authenticated
  live-release browser integration remains unverified. All source hashes stayed
  fixed during the gates, with no drift outside the 24-file ownership ledger.

- Fleet creation and run detail now join the directory as compiled Planning
  contributions (`planning.fleet-start` and `planning.fleet-run`) in `ops.page`.
  Their existing URLs, run resource identity, five evidence-page selectors,
  native controls and historical surface/action identities remain intact. The
  host selects the public contributions directly; feature-local adapters bind
  the existing validated workflows to captured read and declared action ports.
  Unchanged host bootstrap copies cannot cancel an in-flight preview or rewind
  newer feature evidence. Failed reads retain the reviewed view, and uncertain
  creation or repair receipts keep further effects paused.

  Phoenix captures the actor, organization, mission, path, resource and token,
  reauthorizes each request, and rejects injected read parameters or undeclared
  actions. Creation requires the exact successful preview from that page. Run
  actions require the displayed resource and evidence from the latest admitted
  read. Effect submissions are consumed before calling the existing governed
  Fleet Planning action owner, including uncertain outcomes; read recovery does
  not reset this page-instance protection. The domain still checks authoritative
  policy/input/plan/commitment evidence and controls the actual effects. Preview
  remains the existing explicit `validate-fleet-run` operation; evidence refresh
  cannot start planning. This protection is scoped to a mounted server page,
  not a claim of durable deduplication across new browser sessions.

  Authenticated producer-to-public-contribution-to-action tests cover native
  creation, continuation and repair payloads and receipts, stale inputs, replay,
  read-only recovery, captured paging, foreign resources, departed tokens and
  revoked sessions. The production-built host fixture exercises native controls
  and navigation without remote application loading. Mobile date inputs are
  bounded inside their cards for both creation and repair. Fleet policy still
  needs its own validated host contribution and recovery contract; the other
  Planning and domain ownership cohorts remain open. Shared mobile header
  crowding and authenticated live-release browser integration remain tracked
  limitations of the broader migration.

  Final fleet workflow composition validation passed: 1,024 frontend component
  tests and 329 Node tests, Vue-aware checking across 16 projects, and the
  production publication build. Full `mix precommit` passed 3,515 workspace
  tests and 42 plane tests, including all authenticated host workflow tests.
  Ten production-built Chrome host scenarios passed with no page errors or
  remote application requests; 390px creation and repair date controls fit their
  cards. All 5,242 source hashes remained fixed through the gates, with no drift
  outside the 18-file ownership ledger. This verifies the creation/run host
  composition cohort; fleet policy, other ADR ownership cohorts and authenticated
  live-release browser integration remain open.

- Contact-plan review now uses `planning.plan-review` at the existing
  `/missions/:mission_id/ops/plans/:contact_plan_id` URL. The host binds the
  path-owned plan identity and the existing version and six page selectors.
  Phoenix retains the `:browser` and `:require_authenticated_scope` pipeline,
  `:application` LiveView session and per-operation mission authorization.
  Captured reads pin the initially reviewed version even when a newer version
  becomes current; they retain independently paged history, manifest-ordered
  opportunities and execution evidence for exactly the reviewed version.

  Planning owns the contribution, semantic admission, native decision forms and
  captured operation state. Submit, approve, reject and execute use the existing
  governed domain paths. Actual results bind the actor, organization, mission,
  plan, action, version and content hash. Known precondition rejections preserve
  reasons and require an admitted refresh. Unclassified failures can follow
  committed approval or execution work and remain unconfirmed rather than
  promising that no effect occurred.

  Captured receipts recover a lost transport response without repeating the
  action. A refresh without the matching sequence, action and complete input
  cannot unlock an uncertain operation. Failed, foreign or version-substituted
  reads retain the previous evidence, reason drafts and confirmed receipt.
  Confirmation clears only the matching action's submitted reason; other
  decision reasons remain separate. Unchanged bootstrap copies do not cancel
  pending operations, and pending decisions participate in host navigation
  guards. These receipts protect the mounted page, not cross-session retries.

  Confirmed execution remains locked while a refresh still shows the
  pre-execution approved state. An admitted execution state settles that read
  without replaying the command. Plan-review verification passed: 1,076 frontend
  component tests, 329 Node tests, Vue-aware checking across 16 projects with
  219 unchanged warnings and no errors, and the production publication build.
  Full `mix precommit` passed 3,550 workspace tests and 42 plane tests, including
  all 815 web tests. Authenticated tests passed actual producer data through the
  public contribution and native forms into governed decisions and admitted
  their actual receipts. Execution used a fixture with no real provider route.

  Ten production-built Chrome host fixture scenarios passed with no page errors
  or remote application requests; screenshot review confirmed the page at
  desktop and 390px widths. A stalled Chrome startup was diagnosed and the final
  fixture run passed after cleanup. The in-app browser remained unavailable
  before navigation, and authenticated live-release browser integration remains
  unverified. Backend source stayed fixed throughout precommit. Frontend gates
  were repeated after a lint correction and the execution-refresh regression
  fix, both made before backend native producer tests. The final 5,310-file
  snapshot had no drift or changes outside the 23-file ledger. Only this
  verification prose was added afterward. Nineteen host routes still use legacy
  application placement. The next cohort completes the contact-scheduling
  feature across scheduling, contact records and reservation review; remaining
  modules, host ownership and shared mobile header work continue afterward.

- Fleet policy now has a compiled Planning contribution (`planning.fleet-policy`)
  at the existing policy URL. A semantic read model exposes the current draft,
  separately approved policy, editable values, permissions, bounded service
  identity choices and paged grant ledger. Frontend field layout and production
  presentation belong to the colocated feature. The host supplies captured read
  and declared action ports; it does not interpret policy fields or load a remote
  application for this route. Whole-second duration values survive presentation.

  Phoenix reauthorizes the existing authenticated host placement for every read
  and action. Page tokens bind the actor, organization, mission and exact query.
  Serialized operations retain their real receipt in the mounted server page,
  allowing a lost response to be recovered by a read without repeating an effect.
  Reviewed draft, approval, grant policy and revocation references must match the
  displayed evidence before the existing governed domain owners are called.
  Revocation passes the reviewed grant hash unchanged. Known domain rejections
  permit correction; unconfirmed outcomes pause further changes. This receipt
  protection remains scoped to a mounted page, not durable cross-session dedupe.

  Feature state keeps dirty policy, grant and revocation inputs across reads,
  queues a save behind pending validation, and requires explicit reload when a
  changed approved policy makes an edited grant draft stale. Confirmed receipts
  reset only the matching saved draft. Grant and identity pagination use captured
  URL selectors with 25-row reads and independent lookahead; identity choices
  expose only IDs and names. Existing authenticated router scopes remain intact.

  Policy verification passed: 1,034 frontend component tests and 329 Node tests,
  Vue-aware checking across 16 projects with no new lint warnings, and the
  production publication build. Full `mix precommit` passed 3,525 workspace
  tests and 42 plane tests, including first-policy creation and actual native
  save, approval, grant issuance and revocation receipts. Nine production-built
  Chrome host fixture scenarios passed with no page errors or remote application
  requests; policy controls fit at 390px. The in-app browser connection remained
  unavailable, so authenticated live-release browser integration is unverified.
  A presenter type-annotation correction during initial gate setup produced
  byte-identical JavaScript; the corrected 5,256-file snapshot stayed fixed
  through the remaining gates. No changes occurred outside the 26-file ledger.
  Other Planning surfaces, missing domain modules, remaining host ownership
  work and shared mobile header crowding remain open under this ADR.

- Contact requirement directory and review now contribute compiled Planning
  pages (`planning.requirement-directory` and `planning.requirement-review`).
  The directory exposes a bounded semantic ledger; field labels, journey steps,
  lifecycle links and row presentation belong to the frontend feature. Existing
  native components, IDs, URLs and historical surface/action identities remain.
  Requirement review retains its scoped immutable evidence, version/run history,
  four page selectors and 100-item tab-persisted opportunity selection.

  Phoenix captures the authenticated actor, mission, resource, path and token,
  reauthorizes reads and actions, and pins the initially displayed requirement
  version for subsequent reads on that page. Updated current-version evidence
  invalidates stale actions without silently selecting a newer requirement or
  search. Planning and proposal creation use the existing governed domain owners
  and exact displayed references. Sequential page operations retain actual
  receipts for recovery without resubmission; unconfirmed outcomes pause further
  effects. This is mounted-page protection, not cross-session deduplication.

  Compiled review state now owns pending actions and validated receipts. A
  matching confirmed proposal receipt clears its selected opportunities, and an
  explicitly followed result link uses the admitted resource and navigation URL.
  The historical global result-event fallback remains only for callers without
  the contributed workflow. Unchanged bootstrap copies cannot unlock a pending
  operation. Failed reads preserve evidence and selection; the feature leave
  guard also participates in host navigation, including failed tab storage.

  Requirement composition validation passed: 1,044 frontend component tests,
  329 Node tests, Vue-aware checking across 16 projects with no new lint
  warnings, and the production publication build. Full `mix precommit` passed
  3,532 workspace tests and 42 plane tests, including all 797 web tests.
  Eight production-built Chrome host fixture scenarios passed with no page
  errors or remote application requests and no document overflow at 390px.
  Browser checks caught and verified the explicit path-owned resource binding
  for requirement review. Two historical route-test expectations were updated
  during initial backend checks; production source did not change with that
  correction. The corrected 5,271-file snapshot stayed fixed through rerun
  frontend and remaining backend gates, with no changes outside the 25-file
  ownership ledger. Requirement creation and templates, plan detail and contact
  scheduling/record/reservation composition, the remaining domain modules and
  host ownership work, shared mobile header crowding and authenticated
  live-release browser integration remain open.

- Contact need declaration now uses `planning.requirement-declaration` at the
  existing `/missions/:mission_id/ops/requirements/new` URL. The Planning feature
  owns field presentation, draft state, validation feedback, bounded spacecraft
  choices and receipt navigation. Phoenix retains authenticated page placement,
  captured UTC defaults, mission authority and the creation transaction.

  Declaration validation and persistence share the domain preparation function;
  validation normalizes and checks the complete proposed requirement without
  inserting rows. The contribution serializes validation, choice reads and Save,
  coalesces intermediate validation drafts and saves the latest submitted values.
  Choice pages contain at most 25 spacecraft; changing them retains the draft
  and one selected spacecraft from a previous page. Captured reads preserve the
  original horizon. Native UTC controls accept second-resolution defaults.

  Actual creation receipts bind actor, organization, mission, requirement ID,
  initial version and content hash. Completed creation prevents another Save on
  the mounted page and remains recoverable by a captured read. Unknown outcomes
  pause actions, while known validation rejection permits correction. Pending
  Save participates in the host navigation guard. These guarantees are local to
  the mounted page; no durable cross-session deduplication is claimed.

  The historical extraction oracle retains its original hashes. Its test removes
  only the explicitly counted date-resolution and mobile grid sizing changes
  when reconstructing the predecessor; browser and interaction tests check the
  changed controls directly. All other legacy form executable behavior remains
  under that oracle. Remaining Planning composition and full ADR ownership work
  continue after this cohort; authenticated live-release browser integration
  and the shared mobile header crowding remain open.

  Declaration verification passed: 1,054 frontend component tests and 329 Node
  tests, Vue-aware checking across 16 projects with 219 unchanged lint warnings
  and no errors, and the production publication build. Full `mix precommit`
  passed 3,537 workspace tests and 42 plane tests, including all 802 web tests.
  Nine production-built Chrome host fixture scenarios passed with no page
  errors or remote application requests. Screenshot review and field-boundary
  assertions verified the native date controls at 390px after correcting their
  mobile grid and label sizing. The in-app browser failed before opening a page;
  fixture verification does not establish authenticated live-release behavior.
  All 5,285 source files stayed fixed through the gates, with no changes outside
  the 27-file ledger. Only this verification prose was added afterward. The next
  cohort is recurring requirement templates at `/ops/requirement-templates`;
  21 host routes still carry legacy application placement and four target domain
  modules remain absent, in addition to nested feature ownership gaps.

- Recurring requirement templates now use the compiled Planning contribution
  `planning.requirement-templates` at the existing
  `/missions/:mission_id/ops/requirement-templates` URL. The feature owns ledger
  and editor presentation, dirty draft state, validation feedback, page controls
  and receipt handling. Phoenix captures the authorized actor, mission, path,
  token and UTC defaults; each operation is reauthorized before dispatch.

  Template and spacecraft reads are bounded to 25 visible entries, with template
  lookahead indicating another page. Captured page reads retain edited recurrence
  values and a spacecraft selected on a previous choice page. Operators receive
  the ledger without administrator controls. Creation validates the complete
  native form and uses the same domain preparation as persistence. Both template
  and declaration adapters now reject whitespace-only required form fields
  before validation or creation, without changing recurring materialization rules.

  Lifecycle commands carry the exact displayed template identity, version,
  content hash, lifecycle state, lifecycle timestamp and lifecycle actor. The
  domain checks this evidence while holding the template row lock; a version
  change or intervening same-version lifecycle change rejects the old decision.
  Successful pause, activation and closure retain actual receipts and require
  an admitted ledger refresh before another change. Failed refreshes preserve
  evidence and drafts; unknown outcomes pause actions until receipt recovery.

  A matching confirmed creation clears only the saved draft. Validation is
  serialized with creation and lifecycle actions, and pending changes participate
  in the host navigation guard. Receipt recovery is mounted-page protection,
  not durable cross-session deduplication. The native component retains its
  extraction hashes after removing only the added anchor step binding and
  native text-length limits when reconstructing the predecessor. The contributed layout supplies responsive
  field sizing; date and daily-time inputs retain UTC second precision.

  Oversized draft fields are caught before dispatch and remain editable with
  feedback, including Unicode values whose byte length exceeds the input limit.
  They cannot turn a known local input problem into an unrecoverable unknown
  operation. Native template text controls also expose the domain character
  limits. The declaration contribution uses the same local recovery behavior.

  Template verification passed: 1,066 frontend component tests and 329 Node
  tests, Vue-aware checking across 16 projects with 219 unchanged lint warnings
  and no errors, and the production publication build. Full `mix precommit`
  passed 3,545 workspace tests and 42 plane tests, including all 810 web tests.
  The initial full run found one historical fleet-navigation expectation for
  legacy template placement; only that test changed before the successful full
  rerun. Production and frontend source remained unchanged by that correction.
  The corrected 5,299-file snapshot stayed fixed through the rerun, with no
  changes outside the 33-file ledger. Only this verification prose was added
  afterward.

  Ten production-built Chrome host fixture scenarios passed with no page errors
  or remote application requests. Screenshot review and field assertions
  verified the template ledger and native date controls at 390px. The in-app
  browser failed before opening a page; fixture verification does not establish
  authenticated live-release behavior. Contact-plan review is the next
  composition cohort. Twenty host routes still carry legacy application
  placement; remaining Planning composition, four absent target domain modules,
  host ownership work, shared mobile header crowding and authenticated
  live-release browser integration remain open.

- Contact scheduling, contact-record history and reservation review now compose
  through `planning.contact-schedule`, `planning.contact-record` and
  `planning.reservation-review` at their existing URLs. All three contributions,
  semantic contracts, native UI, state owners and tests live in the
  `contact-scheduling` feature. Historical remote entries retain compatibility
  delegates. Phoenix captures the actor, organization, mission, path and page
  token and rechecks authentication and authorization on every read and action.
  Contact records pin the initial reviewed revision; reservation reviews pin the
  selected provider change. Independent ledger and history selectors remain
  path-qualified, and query parameters cannot replace the path resource.

  Search preserves UTC seconds and exact route evidence, returns bounded signed
  opportunities, and creates no reservations. Reserve consumes a displayed
  capability through the governed booking adapter and its stable idempotency
  key. Cancellation requires the reviewed reservation revision, lifecycle and
  provider reference plus administrative authority. Provider-change decisions
  use the exact selected change and proposal hash. Serialized operations retain
  actual results and recover lost responses without repeating provider effects.
  Unknown booking or cancellation outcomes pause further mutations; a later
  observation can settle the same durable reservation. Such results explicitly
  carry `observed` provenance instead of claiming a returned provider response.
  A provider error after entering cancellation retains its durable identity.
  Captured recovery belongs to the mounted host session, not a cross-session
  receipt service.

  Native state retains drafts, independent decision reasons, search evidence and
  prior results across unavailable or foreign reads. Pending effects guard host
  navigation. Completed mutations require refreshed admitted evidence before
  more work. Reconciliation reads the returned reservation directly, independently
  of the current ledger page; reads that predate an attempted operation cannot
  unlock it. The
  generic application JSON boundary remains unchanged. Explicit native planning
  forms admit their declared text bounds and signed capability sizes, and typed
  workflow output has a separate bounded normalizer. Long UTF8 reasons and
  rationale therefore no longer fail the generic 240-byte string gate.

  These three routes reduce legacy host application placements from nineteen
  to sixteen. Four target domain modules, remaining host ownership and workflow
  gaps, shared mobile header crowding and authenticated live-release browser
  integration still remain. Completion of this feature is not completion of
  ADR-024.

  Verification passed: 1,087 frontend component tests, 329 Node tests, Vue-aware
  checking for sixteen projects, and production publication. Frontend checking
  retained 219 existing warnings with zero errors. The full `mix precommit`
  passed compilation with warnings as errors, strict Credo, workspace,
  extension and architecture checks, 42 plane tests and 3,564 workspace tests,
  including 827 web tests. Persisted producer-to-native-consumer tests exercise
  provider effects, permissions, exact evidence, unknown-outcome recovery,
  booking reconciliation outside the visible ledger page, and long UTF8 input.

  Ten production-built Chrome host fixture scenarios passed with no page errors
  or remote application requests. All three pages fit a 390px viewport; shared
  header crowding remains open. This fixture transport does not establish
  authenticated live-release browser behavior. The final 5,327-file source
  snapshot includes 46 changes within a 47-file owned ledger and no unrelated
  changes. A frontend-only UTC parser correction preceded the final gate's
  native producer tests; all frontend gates and browser fixtures were rerun
  afterward. Only this verification prose was added after the passing gates.
  Data Operations historical workflows are the next ownership cohort.

- Data Operations now has a `modules/data-operations` owner. Its
  `historical-workflows` feature contains the existing UI, colocated contracts
  and mounted action tests; both historical Ops entries delegate to its public
  export. The existing template is unchanged, and the delivery stylesheet scans
  the new owner. This is the beginning of its workflow cohort: the reader and
  management routes still use legacy placement, and their empty presentation
  producer, native state and host contributions remain to be replaced.

  Backend prerequisites now read exact organization-and-mission request groups.
  The directory pages whole groups, while action evidence includes every event
  in the selected group. Group transitions, retries and the compatibility action
  adapter no longer filter the first 1,000 mission events. Wrapped and historical
  unwrapped group payloads share the same identity semantics. Correction policy
  also checks exact scoped completion evidence, so a completed correction beyond
  that former window cannot admit an obsolete correction request. Request validation
  checks workflow, UTC range, source scope, active telemetry binding and input
  bounds; submission uses the same checks before writing. Validation no longer
  reports empty fields as valid. Persisted tests cover large and late groups,
  scope isolation, actual transitions and retries, and confirmed request writes.

  Sixteen legacy placements and three absent target modules remain. Data
  Operations still needs real semantic producers and captured workflows,
  including complete result identities, reviewed-state evidence, draft and
  response recovery, and native host/browser integration. The separate data
  sources feature and the broader ADR-024 target remain open.

  Prerequisite verification passed: 44 focused backend tests, 1,089 frontend
  component tests, 329 Node tests, Vue-aware checking for seventeen projects,
  and production publication. Frontend checking retained 219 existing warnings
  with zero errors. The final full `mix precommit` passed compilation with
  warnings as errors, strict Credo, workspace, extension and architecture checks,
  42 plane tests and 3,574 workspace tests, including 827 web tests. An earlier
  gate attempt was intentionally stopped to repair the discovered correction
  supersession window; it is not passing evidence.

  Five production-built Chrome feature fixture scenarios passed, covering view
  navigation, native request values, recovery confirmation, selected-event
  identity and 390px layout. These use fixture props and do not establish native
  host or authenticated backend integration. All 5,338 source files remained
  fixed through the final gate, with 27 changed files inside the 27-file owned
  ledger and no unrelated changes. Only this verification prose was added
  afterward. Semantic producer and captured workflow implementation are next;
  this checkpoint does not complete the Data Operations cohort.

- The historical-workflow semantic producer now reads the actual scoped group
  directory, independently paged audit, jobs and origin identities, and active
  telemetry bindings. Complete selected-group events and current job evidence
  remain internal; their digest changes when a job or correction completion
  changes the reviewed state. Reader and administrator permissions remain
  distinct. Large groups do not truncate action evidence to fit display pages.

  Group transition review now applies the per-item policy used by execution,
  including existing jobs and correction lineage. Correction availability uses
  the authoritative correction review. Individual and group retries reject
  mismatched job identities and foreign mission jobs before mutation. Request,
  transition, retry and correction audit events retain the current host
  operation identity when supplied; later decisions do not inherit a previous
  operation identity. This correlation supports response investigation but is
  not by itself durable idempotency or confirmation of a partial operation.

  The new producer is not yet wired into native host placement. Captured native
  actions, concurrent reviewed-state enforcement, bounded result receipts,
  draft recovery and producer-to-mounted-consumer integration remain the next
  work in this cohort. Existing frontend prerequisites retain their earlier
  verification scope; this backend change does not establish a completed native
  workflow or authenticated browser integration.

  Backend verification passed: 39 focused tests and the full `mix precommit`,
  including warnings-as-errors compilation, strict Credo, dependency/extension/
  architecture checks, 42 plane tests and 3,591 workspace tests (2,295 domain,
  827 web and 136 simulator tests). The eight changed files stayed inside the
  eight-file owned ledger. The gate's initial formatting step updated one owned
  producer test before validation; the other source hashes were unchanged.
  The final snapshot contains 5,342 files. Only this verification prose was
  added after the passing gate. Native composition and the broader migration
  remain open.

- Data Operations historical workflows now use native `ops.page` contributions
  at both existing reader and management URLs. The host captures the authenticated
  actor, organization, mission, path, token and action sequence, and reauthorizes
  every read and action. Feature-local DTO admission, state, controls and tests
  consume the real producer. Directory, audit, job, origin and binding pages are
  independent; request drafts and decision reasons survive refreshes and binding
  paging. Changed bindings require explicit acceptance of the current version.
  Native UTC controls preserve seconds. Long audit reasons remain reachable in
  expandable details, and the lifecycle reason column now stores text to support
  the declared 4,096-byte native reason boundary.

  Confirmed requests, group transitions, retries and corrections return actual
  event/group/job identities with explicit bounded display counts. The native
  adapter rejects existing request runs and stale captured binding/group evidence.
  A dedicated PostgreSQL session serializes native decisions for the same group;
  it does not claim to lock every worker or legacy caller. Ambiguous effects stay
  unconfirmed. The host retains operation responses for same-session refresh
  recovery, and the client guards pending navigation and prevents repeat submission
  of an unchanged completed request. This is not yet durable operation recovery
  across host process loss or proof of atomic multi-item effects.

  Both legacy presentation entries now provide a scoped canonical workspace link;
  their empty producer and duplicate request state are removed. Durable legacy
  surface/action identities remain. Fourteen legacy placements, the separate data
  sources feature, remaining module owners and broader workflow gaps remain open.

  Verification passed: 46 focused domain tests, six focused web tests, 1,095
  frontend component tests and 333 Node test executions, Vue-aware checking for
  seventeen projects, and production publication. Frontend checking retained
  219 existing warnings with zero errors. Actual producer data passes through
  mounted native Vue controls into authenticated LiveView request, approval and
  start actions; resulting audit and job identities are checked in persistence.
  Separate production-built Chrome fixtures cover six native feature scenarios,
  response recovery and 390px layout. They replay those real producer/action
  fixtures and do not establish authenticated live-browser integration.

  Publication exposed a release-checker lexer bug with nested JavaScript
  templates containing escaped backticks. The checker now scans nested template
  expressions without losing string boundaries. Regression tests retain missing
  import and unresolved dynamic-import rejection, and the complete generated
  publication passes inspection. The initial repository gate was intentionally
  interrupted for this repair; only the subsequent full gate is passing evidence.

  The final `mix precommit` passed warnings-as-errors compilation, strict Credo,
  workspace, extension and architecture checks, 42 plane tests and 3,600 workspace
  tests (2,302 domain, 829 web and 136 simulator tests). All 5,354 source files
  remained fixed through that gate. The 28 changed files stayed inside the
  28-file owned ledger; only this verification prose was added afterward. This
  verifies native historical composition within the limits above, and leaves the
  full ADR-024 migration active.

- Data Sources now has a colocated feature under
  `modules/data-operations/src/features/data-sources/`. Its presentation contract,
  Vue implementation and mounted tests live together. Reader, registration and
  settings delivery entries delegate to the same public module entry. Compiled
  script and template fingerprints match the prior implementation; the extraction
  does not change its markup or styling.

  The new semantic source producer reads actual scoped source and binding pages,
  immutable source/binding history, observed health, watermarks and deployment
  jobs. Each displayed collection has independent 25-row pages and explicit
  continuation evidence. Deployment identity and payload scope are filtered
  before paging, for both current wrapped and historical unwrapped job payloads.
  Observation timestamps preserve microseconds. Raw diagnostic payloads are not
  emitted. Shared definitions remain visible and are distinguished from records
  editable by the mission's administrator.

  A native action adapter now checks reviewed source, binding, destination and job
  identities before delegating to the existing governed action adapter. Source
  evidence includes credential-reference changes, so a stale review cannot rotate
  credentials again. Registration validates configuration and rejects existing
  source identities before writing. Confirmed results retain actual source,
  binding, credential-event and deployment-job identities. These are sequential
  reviewed-state checks, not proof of concurrent mutation exclusion or durable
  operation recovery.

  The semantic producer and reviewed actions are backend prerequisites; native
  host placement, feature DTO admission, complete draft/response recovery and
  producer-to-mounted-consumer-to-host integration remain to be connected. The
  historical Data Sources producer still serves its migration presentation until
  that replacement. Fourteen legacy route placements and the broader target
  remain open; this extraction does not complete the Data Sources workflows.

  Prerequisite verification recorded 27 focused backend tests, 1,101 frontend
  component tests, 333 Node test executions, Vue-aware checking for seventeen
  projects and production publication. Checking retained 219 existing warnings
  with no errors. Four production-built Chrome presentation fixtures passed,
  including a 390px viewport; they do not establish native host integration.
  The full precommit log records every stage succeeding, including 42 plane and
  3,612 workspace tests. Its terminal response was lost during context recovery,
  so the exact process exit is not independently retained. All 5,363 source
  files match the frozen gate snapshot, with 21 changes inside the 21-file ledger.
  Only this verification prose was added after that audit.

- The four Data Sources URLs now compose compiled native `ops.page`
  contributions from the `data-sources` feature. Versioned semantic admission,
  state, registration and settings controls, evidence views and tests are
  colocated with their owner. The host captures actor, organization, mission,
  path, token and sequence; detail/settings paging cannot replace the source
  named in the URL. Existing authenticated browser scope and application
  LiveView session retain Ops reader and Ops administrator policies.

  Independent pages expose actual sources, bindings, source and binding history,
  observed health, health history, watermarks and deployment jobs. Observation
  identities retain binding, realm, dataset and replay context, with microsecond
  timestamps. Only declared evidence fields render. Registration, source controls,
  binding moves, credential rotation and deployment actions use the governed
  adapter and exact reviewed records. Shared definitions remain read-only.
  Lifecycle controls require a dedicated BYO backend. Retry requires a failed
  job; requeue requires a running job, and both recheck the displayed job state
  before entering the governed adapter.
  Source and destination changes require explicit acceptance; off-page binding
  selections retain their values and cannot be submitted until reviewed records
  are visible again. A successful binding move clears the old selected history
  subject while preserving the returned binding identity.

  Same-session response recovery retains actual operation results and unsaved
  registration values, prevents duplicate submission of a completed source
  identity, and guards navigation during pending or unconfirmed operations.
  Read and validation failures do not claim an ambiguous write. Mutation failures
  remain unconfirmed when the effect cannot be established. This does not yet
  provide recovery across host process loss or exclude concurrent legacy/worker
  mutations. Full live backend provisioning/probe behavior remains distinct from
  the persisted registration, disable and binding integration evidence.

  Legacy delivery entries now link to the canonical workspace. Their fixed health
  counts, empty histories, guessed detail links and duplicate forms are removed.
  Ten legacy host application placements and three absent target module owners
  remain, alongside broader workflow and authenticated browser integration gaps.
  The full ADR-024 goal remains active.

  Verification passed: 29 focused domain tests, 22 focused web tests, 1,109
  frontend component tests and 333 Node test executions. Vue-aware checking
  passed across seventeen projects, retaining 219 existing warnings and no
  errors; production publication passed. Real producer data passes through
  mounted native controls and authenticated LiveView into persisted registration,
  disable, binding-move and running-job requeue results. Eight production-built
  Chrome fixture scenarios passed, including response recovery and 390px layouts.
  They replay actual producer/action evidence and do not establish authenticated
  live-browser integration.

  The final `mix precommit` exited successfully, passing warnings-as-errors
  compilation, strict Credo, workspace, extension and architecture checks,
  42 plane tests and 3,621 workspace tests (2,316 domain, 836 web and 136 simulator
  tests). All 5,373 source files matched the frozen gate snapshot. The 27 changed
  files stayed inside the 27-file owned ledger. Only this verification prose was
  added afterward. Two earlier runs were intentionally interrupted for legacy
  route-test expectations and backend eligibility repairs; neither is counted as
  a passing full gate.

  Explicitly clearing a retained binding or destination selection remains a
  draft-control follow-up before Data Sources workflow completion. The broader
  ownership migration and runtime integration limits above remain open.

- Data Sources binding and destination selections now clear their captured review
  when the native empty option is chosen. Mounted coverage verifies that refresh
  retains the empty value and submission remains disabled.

- Telemetry Decom configuration now lives in
  `modules/telemetry-decom/src/features/configuration/`, including its component,
  DTO admission and compiled registration. Both former delivery implementations
  delegate to the public feature. The canonical query is registered to Telemetry
  Decom; an explicit legacy Spacecraft identity adapter preserves the prior
  surface and query names without a duplicate provider registration.

  The version-1 configuration DTO carries scoped spacecraft identity, saved
  configuration, actual compiler counts and diagnostics, activation preflight,
  pending mission request identity and status relative to the active binding set.
  The producer no longer substitutes the first catalog revision for a missing
  saved revision. The first configuration form is visible before a configuration
  exists. Revision selection is local until explicit submission; refresh retains
  drafts and changed saved revisions require explicit review. Restoring a disabled
  saved configuration preserves its endpoint and APIDs. Workspace disable retains
  its existing installation and configuration effects; restoring workspace access
  remains a host capability-management operation.

  The canonical bridge now transports declared lifecycle actions using their
  host-owned permission, effect, confirmation and execution metadata. The existing
  dispatcher still performs authorization, installation admission and activation
  preflight; durable bridge idempotency remains in place. Activation request
  results expose a bounded receipt with the actual request identity instead of
  returning domain structs. No route or authentication pipeline changed.

  This is configuration ownership progress, not Telemetry Decom completion.
  Packet bindings remain in the delivery package. Revision options still need
  bounded paging, configuration edits and mission-wide activation need reviewed
  version evidence enforced through concurrent writes, and draft/response recovery
  needs broader navigation and failure coverage. Derived Telemetry and Limits and
  Alarming remain absent owners. The ten legacy host placements and the full
  ADR-024 goal remain open.

  Verification passed for this configuration cohort: 35 focused domain tests,
  13 registry contract tests, the full 837-test web suite, 1,113 frontend component
  tests and 333 Node test executions. Final wrapper/component checks also passed.
  Vue-aware checking passed across eighteen projects with 219 existing warnings
  and no errors; production publication passed for the host and all six remotes.
  The authenticated HTTP bridge test carries a real configuration read through
  mounted Vue submission into persisted configuration, then verifies action-version
  rejection and workspace disable. Nine production-built Chrome fixture scenarios
  passed, including initial configuration, confirmation, preserved re-enable
  inputs, pending-request gating and 390px button bounds. These fixtures do not
  establish authenticated live-browser transport.

  The final `mix precommit` exited successfully with 42 plane tests and 3,627
  workspace tests, including 2,321 domain, 837 web and 136 simulator tests. All
  5,387 source files matched the frozen gate snapshot; the 40 changed files stayed
  inside the recorded ownership ledger. Only this verification prose was added
  afterward. The full migration goal and the workflow limits above remain open.


- Telemetry Decom configuration submissions now carry a scoped review reference
  over the saved application binding and packet inputs, including the absence of
  a first configuration. Mission submission uses a reference over all Telemetry
  Decom bindings and inputs in the mission. The producer and authority compare
  these references inside a mission-scoped PostgreSQL transaction lock. The
  application binding store, configuration updates, packet replacement/disable,
  applied-state stamping and mission request composition participate in that lock.
  Failed operations roll back their nested writes. This closes the earlier gap
  between reading a configuration and locking its final row update.

  The configuration feature displays mission configuration and input versions,
  enabled states, catalog and endpoint identities, saved APIDs and packet counts.
  A separate acknowledgement is required for mission submission. Refreshed
  configuration evidence retains the revision draft and requires review; changed
  mission evidence clears the acknowledgement. At most 200 combined configuration
  and input rows are displayed. Larger missions explicitly disable submission
  until a complete review workflow is available. The governed activation request
  records the reviewed configuration basis. This reference covers saved desired
  configurations; it does not freeze permission revocation, installation changes,
  endpoint lifecycle or runtime state.

  The legacy Spacecraft telemetry surface now delegates its three actions to the
  canonical Telemetry Decom dispatcher, preserving durable identities and URLs.
  Workspace disable therefore reaches the same installation and packet effects
  as the canonical surface. Both paths serialize the canonical bounded result.
  The HTTP bridge exposes the existing domain-owned ActionFailure message so
  stale reviews provide a refresh instruction instead of generic invalid input.
  No routes or authentication pipelines changed.

  This cohort is not full migration completion. Packet-binding feature ownership,
  bounded revision selection, larger-mission review, navigation/receipt recovery,
  authenticated browser integration and the remaining ADR-024 owners and host
  placements still require work. The earlier configuration cohort's verification
  above applies to its own frozen snapshot; successor verification follows below.

  Successor verification passed: 31 focused domain and 14 focused web tests;
  1,115 frontend component tests and 333 Node test executions; Vue-aware checking
  across eighteen projects with 219 existing warnings and no errors; production
  publication for the host and all six remotes. Twelve production-built Chrome
  fixture scenarios passed, including mission acknowledgement, invalidation after
  another spacecraft changes, scoped review submission and 390px layout. These
  used actual producer fixtures and do not establish authenticated live-browser
  transport. The authenticated HTTP test verifies producer-to-Vue-to-action
  persistence, stale-review rejection, idempotent failure replay and disable.

  The final root `mix precommit` exited successfully with 42 plane tests and
  3,633 workspace tests, including 2,327 domain, 837 web and 136 simulator tests.
  The root formatter made one whitespace-only call-wrapping change before
  compilation; both versions were recorded. All 5,390 source files then matched
  the formatted gate snapshot at completion, with 18 changed files inside the
  ownership ledger and zero unowned changes. Only this verification prose was
  added afterward. The full ADR-024 migration remains active; packet-binding
  feature ownership is the next cohort.


- Telemetry Decom packet bindings now belong to
  `modules/telemetry-decom/src/features/packet-bindings/`: a validated semantic
  document, component, draft and pending-save state, explicit action port and
  compiled contribution. The delivery application delegates to this public
  feature. The durable surface, query, action and URL identities are unchanged.
  Phoenix retains scoped authorization and the governed activation boundary.

  The producer pages packets, endpoints and packet fields in groups of 25, with
  complete counts and explicit unavailable selections. Endpoint reads include
  mission-wide endpoints and the current spacecraft only. Route query parameters
  are captured by the existing authenticated spacecraft LiveView session and
  limited to the feature's six declared paging/search keys. No routes or
  authentication pipelines changed. Catalogs larger than 512 packets are
  navigable; a legacy selection exceeding the 512-binding limit requires an
  explicit draft reset before replacement.

  Packet submission checks both the exact reviewed configuration and packet
  version under the mission configuration lock, including the catalog selected
  in Manage. Drafts survive paging in a scope-, actor- and installation-qualified
  tab journal. Each save records an immutable input and idempotency key before
  sending. An unknown response blocks another save and can be recovered with the
  same key, including after remount. A retry authorization failure does not prove
  the earlier save failed. Confirmed receipts and refreshed server evidence are
  kept separate from later drafts. Clearing the endpoint is an explicit local
  choice and disables submission. Saving packet inputs does not activate them.

  Verification passed: 19 focused domain/registry tests and 15 focused web
  tests, including actual producer-to-public-component-to-HTTP persistence,
  stale review rejection, identical idempotent replay and signed-release
  admission. The full frontend suite passed 1,123 component tests and 333 Node
  test executions. All eighteen projects passed Vue-aware checking, with 219
  existing lint warnings and no errors. Production publication passed for the
  host and all six remotes. Fourteen Chrome scenarios using production-built
  public components and actual producer fixtures covered explicit endpoint
  clearing, pending-save recovery after reload with the same key/input, paging
  with retained drafts, complete counts and legacy replacement, plus 390px
  layout. These fixtures do not establish authenticated live-browser transport.

  The final root `mix precommit` exited successfully with 42 plane tests and
  3,638 workspace tests, including 2,331 domain, 838 web and 136 simulator tests.
  All 5,401 source files matched the frozen gate snapshot at completion. The 29
  changed files stayed inside the 30-file ownership ledger, with zero unrelated
  changes. Only this verification prose was added afterward.

  The full ADR-024 migration remains active. Broader ownership gaps, bounded
  revision selection, review for larger missions and authenticated live-browser
  integration remain open. Derived Telemetry is the next missing domain owner;
  its existing declarative definitions form and latest-value count require a
  complete module-owned workflow.

- Derived Telemetry now owns `modules/derived-telemetry/src/features/definitions/`:
  its semantic contract, definition directory, editor, immutable history, source
  references, latest values, scoped draft journal and explicit action port. The
  existing Ops remote exposes this owner through `./DerivedTelemetry`, supporting
  coordinated releases while preserving the `derived_telemetry/manage` surface,
  query/action identities and mission URL. Phoenix retains mission authorization
  and installation admission. The existing authenticated mission application host
  captures the feature's eleven declared query keys; no routes or pipelines changed.

  Definitions, history, source references, latest values and spacecraft choices
  have counts and pages of 25. Operators can inspect the exact producing version
  of a value even after a newer definition is saved, edit the reviewed current
  version, or explicitly reuse a historical expression in a new version. Missing
  selected versions are unavailable; saving does not imply evaluation has run.
  Latest values retain spacecraft scope, timestamps, quality and trigger identity.

  Saves require the reviewed definition identity and version. An advisory lock
  serializes writes to the same mission point, including first creation. Conflicting
  immutable writes return a conflict instead of an unwritten proposed value. Two
  independent database transactions prove that only one concurrent first save wins.
  Actor-, installation- and scope-qualified tab journals retain drafts across
  navigation and preserve the exact input/key before sending. Unknown outcomes
  block another save and recover with that same input/key after reload. A failed
  recovery authorization does not establish that the original save failed.

  Expression storage is widened to text with an explicit 8 KB action bound. The
  exact save contract and its canonical idempotency request admit that field;
  other inputs keep their generic bounds. Derived receipts allow 64 KB including
  JSON escaping in both application and database admission, while other application
  receipts retain 16 KB. Authenticated tests cover a full-length expression, its
  immutable stored version, identical receipt replay and stale-review rejection.

  Verification passed: 30 focused domain tests and 41 focused web tests, including
  ordinary bounded idempotency documents, exact long-expression admission,
  immutable stored values, full-length receipt replay and catalog/release identity.
  The full frontend suite passed 1,130 component tests and 333 Node test executions.
  All nineteen projects passed Vue-aware type checking, with 219 existing lint
  warnings and no errors. Production publication passed for the host and six
  remotes. Fifteen Chrome scenarios using production-built public components and
  actual producer fixtures covered history, paged scopes, pending-save recovery
  and 390px layouts. A separate Chrome check loaded the built `./DerivedTelemetry`
  artifact through the production host federation loader, validated its manifest,
  and exercised its query/action port. These fixture bridges do not establish
  authenticated live-browser transport.

  The final root `mix precommit` exited successfully with 42 plane tests and
  3,649 workspace tests, including 2,338 domain, 842 web and 136 simulator tests.
  All 5,423 source files matched the frozen gate snapshot at completion. The 46
  changed files stayed inside the 46-file ledger, with zero unrelated changes.
  Only this verification prose was added afterward.

  The full ADR-024 migration remains active. Limits and Alarming remains the last
  absent target domain owner, and ten host placements still delegate to legacy
  application implementations. Broader workflow and authenticated browser
  coverage remain open. The Derived editor also needs feature-owned explanatory
  messages for known rejection codes because the production bridge deliberately
  replaces server messages with generic text; its rejection and recovery state
  behavior is verified, while that message improvement is a follow-up.

- Limits and Alarming ownership is in progress. Its new domain persistence
  boundary commits an immutable definition, lifecycle event, operational event
  and active pointer together. Conflicting version contents return a conflict;
  identical retries return the stored definition. Activation validation errors
  roll back the whole write. Definition and lifecycle writers share a lock for
  the organization, mission, point and limit set.

  The reviewed append operation checks both the latest definition identity/version
  and the active lifecycle event. Reactivating an older definition invalidates a
  prior review even when the newest stored version is unchanged. Scoped definition
  and history reads expose full counts and pages of 25. This boundary is ready for
  the new feature producer; the existing application form still uses its existing
  action contract until the module-owned workflow supplies review evidence.

  The Derived Telemetry editor now owns explanatory messages for known rejection
  codes, including the production bridge's generic error text. It retains the
  draft and requires refreshed evidence after a definitive rejection; unknown
  outcomes retain their immutable input and idempotency key for recovery.

  Verification passed: 16 focused Limits tests, including immutable conflicts,
  lifecycle rollback, changed activation review, scoped paging and an independent
  concurrent first-save winner. The Derived feature's nine component tests and
  type check passed, as did production publication for the host and six remotes.
  The final root `mix precommit` passed 42 plane tests and 3,656 workspace tests,
  including 2,345 domain, 842 web and 136 simulator tests. Warning-free compilation,
  strict Credo, architecture and extension checks also passed. All 5,426 source
  files matched the frozen snapshot at completion; the eight changed files stayed
  within the ten-file ledger, with zero unrelated changes. Only this verification
  prose was added afterward.

  The full ADR-024 goal remains active, including the Limits and Alarming frontend
  owner, remaining legacy placements, broader workflow gaps and authenticated
  browser integration. The next continuation connects the reviewed append boundary
  to the complete Limits producer, editor and delivery contract.


- Limits and Alarming now has a frontend owner at
  `modules/limits-and-alarming/`, with colocated definitions and current-posture
  features. Their public contributions declare semantic queries, validated
  documents and explicit operation ports. The coordinated Ops release exposes
  both existing `limits/manage` and `limits/activity` surfaces through `./Limits`
  in the existing `cadence.mission-assurance` package. Phoenix retains mission
  authorization, installation admission and governed effects. The authenticated
  mission application host accepts declared feature query keys and preserves
  legacy definition/version/point aliases; no routes or pipelines were added.

  The definition workflow includes counted pages of definitions and canonical
  telemetry/derived points, reviewed editing, immutable version history and
  lifecycle history. Historical thresholds can be reused only as a new version
  based on the current definition and activation review. The action delegates to
  the atomic reviewed append boundary and returns the actual stored definition.
  Pending operations preserve their exact input and idempotency key before sending,
  survive tab reload, and prevent competing saves. Actor-, installation- and
  mission-qualified journals retain threshold drafts and unfinished point/set
  selections across paging. Confirmed receipts remain separate from later drafts
  and current activation evidence. Known rejections have feature-owned messages;
  an uncertain recovery authorization failure leaves the original operation pending.

  Current posture shows counted and paged evaluated states with spacecraft and
  severity filters, actual generation/receipt times and producing definition
  versions. Counts cover the complete selected search and spacecraft scope before
  severity filtering. Existing sample evidence URLs and exact historical definition
  links are preserved. Saving does not imply that evaluation ran or that a displayed
  state is fresh. Shared read-only definition evidence serves both features.
  The existing latest-state projection remains per mission, spacecraft and point;
  each row identifies the limit set actually evaluated.

  Fully populated valid definition/history documents exceed the generic 64 KB
  host output allowance. Only Limits trusted query responses use the existing
  bounded workflow output policy; action requests and receipts retain their
  existing bounds. Focused authenticated tests cover the full document, exact
  receipt replay, stale reviews and older-version reactivation.

  This increment also moves the existing Ops alarm route into host composition
  with the `limits.alarm-conditions` contribution. The feature owns its semantic
  contract, counted condition and spacecraft pages, existing severity/state/search
  filters, explicit navigation and captured refresh. The host admits the page ID,
  token, scope and response envelope while the owner validates condition data.
  Refresh failures retain the last loaded evidence, and same-context bootstrap
  rerenders cannot rewind a successful read. The old Ops remote alarm component
  delegates through the owner's canonical destination adapter; its duplicated
  presentation producer has been removed. Existing Ops authentication and URLs
  remain; eight host placements still use legacy application implementations.

  Posture and alarm conditions share the canonical state-evidence projection,
  validated state contract and evaluated-state list. State filtering occurs before
  counting and paging; severity totals describe the complete selected search,
  condition-state and spacecraft scope. Semantic alarm acknowledgement is a
  separate transition model and is not exposed for these limit-event identities.

  The first full root gate reached 2,348 of 2,349 domain tests and stopped at the
  existing capability signer test's 100 ms receive timeout. All 5,455 frozen sources
  matched at terminal, with zero unrelated changes. That test now installs its
  monitor atomically and allows a bounded scheduler wait while still requiring
  normal signer exit before token verification. The second root gate passed
  42 plane tests and 3,671 workspace tests, including 2,352 domain, 850 web and
  136 simulator tests. All 5,471 sources matched the frozen snapshot at terminal.

  An authenticated browser check then exercised real sign-in, counted condition
  paging, severity/state/search navigation, and captured refresh through the actual
  Phoenix endpoint and LiveView websocket. It exposed a production build collision:
  Vite component CSS overwrote Tailwind's app.css. Vite now emits components.css,
  loaded alongside the preserved Tailwind stylesheet in the production layout.
  The browser check passed after this repair, including a loaded-style assertion.
  Sample source records were not seeded; exact sample links were checked, without
  claiming that their downstream contents were verified.

- Spacecraft commanding is now a host-composed `commanding.spacecraft`
  contribution under the existing spacecraft URL and authorization policy. Its
  feature-local version-1 contract presents the exact pinned profile version,
  SCID, uplink and packet protocols, with distinct unbound, unavailable and deleted
  profile evidence. It never substitutes the latest profile or equates configured
  protocols with runtime encoding, transport readiness or release authorization.
  Existing identity, routing and readiness links reach their owning workflows.

  The page reads counted 25-row pages of source endpoints assigned to the exact
  spacecraft, with search and canonical paging. Monitor links use source endpoint
  identities, rather than inferring a command target from a spacecraft identity.
  Mission-only and other-spacecraft endpoints do not enter this projection.
  The old remote entry is a destination adapter; its placeholder presentation
  producer and duplicated implementation are removed. Command creation, approval
  and release workflows remain broader goal work.

  Focused persisted producer/public-component checks, host permission and isolation
  tests, and module component tests pass. Two authenticated browser tests exercise
  the current production assets and actual Phoenix/LiveView transport: alarm reads
  and captured refresh, plus exact spacecraft pinning, endpoint paging, search and
  navigation into the mission command monitor. Narrow alarm controls stay within
  the Ops form. The spacecraft breadcrumb uses a resolved title. The shared Ops
  header now uses two rows on narrow screens, preserving mission context, full
  critical counts, UTC and native account actions. The actual authenticated alarm
  check verifies non-overlapping header bounds from 320px through desktop widths
  and the live connection indicator. Existing shell behavior tests also pass.

  The full frontend suite passed 1,164 component tests and 333 Node executions.
  Type checking passed for 20 projects; the host and six remote publications and
  Phoenix browser assets built successfully. The third combined root gate passed
  2,355 domain tests and 853 of 854 web tests, finding one stale test that still
  expected the legacy commanding placement. All 5,478 frozen sources matched at
  terminal. That assertion now checks the commanding spacecraft contribution;
  all seven focused route tests pass. The final combined root gate, including the
  header repair, passed 42 plane tests and 3,678 workspace tests: 333 foundation,
  2,355 domain, 854 web and 136 simulator tests. All 5,478 frozen sources matched
  at terminal, with zero unrelated changes. The full ADR-024 goal remains active,
  with eight legacy placements and broader workflow and runtime coverage required.

- Organization home now belongs to the host's
  `administration/features/organization-home` slice. Its version-1 semantic read
  contains the selected organization, counted mission/spacecraft/active-membership
  totals, and at most three recently created missions. The owning contexts perform
  bounded database queries; recent rows use creation time with a stable identity
  tiebreaker, replacing the old slug-sorted list and per-mission spacecraft loads.
  Active memberships retain the member directory's semantics, including an active
  membership whose user is disabled. These counts are not a count of active users.
  Counts and recent rows are separate database observations, not an atomic snapshot.

  The feature owns its rendering, canonical links, empty state and data validation.
  The core boundary rejects unknown pages, mismatched organization identities and
  malformed or unavailable data while retaining the host and its retry action.
  The existing authenticated `/` route and organization policy remain authoritative
  for initial loads, refreshes and navigation. Admin-mode redirects remain intact.
  The former organization-admin home entry delegates to the owner's destination;
  its presentation producer and two unused legacy components are removed. Durable
  surface and query identities remain unchanged under coordinated releases.

  Persisted producer-to-component tests cover complete totals, chronological order
  and ties, tenant exclusion and denied reads. Focused web tests cover captured
  organization scope, refreshes, navigation and revoked sessions. An authenticated
  production-asset browser check verifies sign-in, counted home data, three recent
  missions, persistent-shell navigation to the mission directory and creation form,
  ignored foreign-organization URL parameters, narrow layout and session removal.
  It navigates to creation without saving a mission. The full frontend suite passed
  1,170 component tests; type checking, host/remote publications and native browser
  assets also passed. The authenticated federation browser gate passes against the
  current publications, including persistent core navigation, immutable release
  promotion and rollback, failure containment and explicit packet-save recovery.
  Recovery retains the reviewed payload and idempotency key after a stopped CSRF
  request; no mutation is replayed automatically. Browser harness expectations now
  distinguish core destinations from legacy publication entry points and exercise
  the semantic packet-bindings feature. The final root gate passed 42 plane tests
  and 3,684 workspace tests: 333 foundation, 2,358 domain, 857 web and 136 simulator
  tests. All 5,486 frozen sources matched at completion, with zero unrelated
  changes. Seven legacy host placements and broader workflow/runtime work remain;
  the full ADR-024 goal is active.


- The cross-module timeline now belongs to the host's
  `ops-workspace/features/timeline` slice. The existing authenticated
  `/missions/:mission_id/ops/timeline` URL uses the core host placement, retaining
  the browser/authenticated-scope pipeline, application live session and Ops
  mission policy. Phoenix authorizes initial reads, navigation and refreshes.
  The former Ops Console entry delegates to the owner's public destination;
  compatibility query/action identities remain, with semantic destination props
  instead of a second presentation producer.

  The version-1 contract carries scoped mission facts, editable filters, up to
  100 events, a continuation cursor and independently selected evidence. The
  owner validates context, shape and version before rendering. It preserves
  canonical event links, half-open UTC ranges, unavailable selection recovery,
  scoped dashboard return links, and shell navigation. Selected evidence exposes
  curated source, subject and reference identities without arbitrary metadata.
  Invalid filters remain visible and editable rather than silently broadening
  the read. The feature owns its contracts, rendering, tests and public entry.

  History merges bounded portions from persisted projections and operational
  events on effective event time and binary identity order. Canonical projection
  rows win even when a stale operational copy would match different filters.
  A shared covered frontier prevents incomplete merged pages; empty bounded
  portions can offer continuation to older matching events. Endpoint-derived
  spacecraft identities use scoped, referenced-ID queries for both list and
  selected reads. Pages are separate observations, not an atomic history snapshot
  or an exhaustive event count. Other operational consumers retain their default
  occurred-time ordering.

  Focused producer, paging, compatibility-action and web checks pass, including
  persisted producer-to-Vue validation, tenant exclusion, revoked sessions,
  canonical overrides, equal-time ordering and continuation beyond 1,000
  nonmatching candidates. Full frontend tests, Vue-aware type checking across
  20 projects, strict Credo and coordinated publications pass. The full frontend
  suite includes 1,179 passing component tests. An authenticated production-asset
  browser check passes sign-in, 100-row and older-history navigation, half-open
  UTC filters, selected-event deep links, persistent shell/rail identity, 390px
  evidence layout, foreign query/event exclusion, editable invalid filters,
  observed refresh and session removal. The final root gate passed 42 plane
  tests and 3,695 workspace tests: 333 foundation, 2,366 domain,
  860 web and 136 simulator tests. All 5,499 frozen sources matched at
  completion, with zero unrelated changes. The legacy contract test now verifies
  the semantic destination props. Six legacy
  host placements and broader workflow/runtime work remain; the full ADR-024
  goal remains active.


- Notifications now belong to the host's
  `auth-and-navigation/features/notifications` slice. `/notifications` retains
  its browser/authenticated-scope pipeline, application live session and user
  policy, so an authenticated account needs no organization membership to read
  notices or accept an invitation. The version-1 recipient contract contains
  curated notification facts, independent read and invitation status, an unread
  filter and at most 50 rows with stable exclusive history cursors. Recipient
  identity comes from the authenticated session, not URL parameters. Invitation
  status lookups are bounded to the returned notification references and current
  recipient email or durable accepting user identity; arbitrary metadata, action
  URLs and invitation credentials are absent from the DTO.

  Reading an invitation does not imply acceptance. Pending, accepted, expired,
  revoked and unavailable invitations use authoritative status and expiry facts;
  an accepted invitation remains associated with its accepting user after an
  email change. Actions recheck the active persisted recipient and notification
  ownership. Acceptance remains in Accounts' locked invitation transaction;
  repeated acceptance cannot create another membership. The host pins actions to
  the current recipient, path and visit token, reauthenticates before dispatch,
  and ignores stale responses after navigation or recipient changes. Failed
  transport leaves an uncertain outcome visible and prevents another action
  until an explicit refresh returns a fresh observation. No action is replayed
  automatically. Notification PubSub updates refresh the scoped inbox and bell.

  The legacy inbox entry delegates to the owner's public destination and its
  second panel implementation is removed. Existing surface/action identities
  remain; the legacy bell keeps its count and recent-notification response shape.
  Current focused checks pass 18 domain and 25 web tests, including persisted
  producer-to-Vue validation, real acceptance/membership effects, no-membership
  access, foreign recipients, stale visit tokens and revoked sessions. The full
  frontend suite passes 1,188 component tests and Vue-aware type checking across
  20 projects. Strict Credo, coordinated publications and native assets pass.
  The authenticated production-asset browser check passes no-membership sign-in,
  foreign-user query exclusion, 50-row and older/unread history, read-state and
  bell-count updates, observed refresh, acceptance of an already-read invitation,
  retained host navigation, accepted status after reload and session removal.
  The enclosing test verifies the created membership, accepted invitation and
  exact unread count; desktop and 390px layouts were inspected. The final root
  gate passed 42 plane tests and 3,705 workspace tests: 333 foundation,
  2,370 domain, 866 web and 136 simulator tests. All 5,511 frozen sources
  matched at completion, with zero unrelated changes. Five legacy administration
  placements and broader workflow/runtime work remain; the full ADR-024 goal is
  active.

- Platform overview, organization directory and organization creation now belong
  to separate host administration features: `platform-overview`,
  `organization-directory` and `organization-create`. Their existing `/admin`,
  `/admin/organizations` and `/admin/organizations/new` URLs retain the
  browser/authenticated-scope pipeline, application live session and admin policy.
  Initial loads, navigation, refreshes and creation reauthenticate the browser
  session and its admin-mode expiry. The domain boundary also reloads the active
  persisted user and requires current platform-admin eligibility.

  Version-1 semantic contracts contain administrator identity and observation
  time. Overview counts organizations and active user accounts without advertising
  an unimplemented user-management action. The directory fetches at most 51 rows,
  exposes 50, and uses exclusive binary slug/identity cursors. Counts and pages
  are separate observations. The features own labels, canonical links, paging,
  empty states, validation and failure recovery. Unknown pages, malformed data,
  unsupported versions and mismatched administrators remain contained by the
  administration boundary while host navigation remains available.

  Creation admits only the reviewed display name and slug, with bounded text and
  curated field errors. The authoritative insert does not suppress an identity
  conflict; the existing general persistence helper keeps its separate semantics.
  Duplicate slugs retain the original organization and the user's draft. A
  successful visit is consumed and exposes a created-organization receipt and
  canonical destination. Actions pin path, administrator and visit token; late
  completions after navigation, account changes or a replaced visit token cannot
  overwrite current context. An uncertain transport outcome retains the draft,
  blocks automatic or repeated submission and offers directory/status recovery.
  Refresh alone does not infer that an uncertain operation failed.

  The three legacy remote entries now delegate to public owner destinations, and
  their presentation producers plus the unused list renderer are removed. Durable
  application, surface and action identities remain under coordinated releases;
  the legacy creation action delegates to the same freshly authorized effect.
  Organization detail, native organization switching and invitations remain a
  separate administration increment.

  Four focused domain tests pass, including persisted producer-to-real-Vue-to-
  creation evidence, binary paging, global counts, duplicate and injected input
  rejection, and fresh privilege revocation. Four new web tests plus the existing
  administration/provider checks pass after their legacy expectations were
  updated. They cover consumed and stale visits, session revocation, mode expiry,
  navigation and invalid-cursor recovery. The full frontend suite passes 1,199
  component tests plus Node suites; Vue-aware type checking passes all 20 projects,
  and strict Credo reports no issues. Coordinated publications and native Phoenix
  assets compile successfully. Actual Chrome 152 browser coverage passes sign-in,
  admin-mode reauthentication, 50-row paging and deep reload, invalid-query recovery,
  persistent host navigation, duplicate-slug correction, organization creation,
  updated directory/counts and session removal. The enclosing test verifies the
  new organization and preserves the duplicate's original name. Desktop and 390px
  layouts were inspected. The first root gate passed all 42 plane tests and
  2,373 of 2,374 domain tests, finding that the new administration namespace lacked
  explicit architecture ownership. All 5,532 frozen sources matched at terminal.
  Administration identity effects are now declared in the management plane and
  identity context, retaining the existing dependency limits; all 13 focused
  architecture and administration tests pass. The final combined
  root gate passed 42 plane tests and
  3,714 workspace tests: 333 foundation, 2,375 domain, 870 web and
  136 simulator tests. All 5,532 frozen sources matched at completion,
  with zero unrelated changes. Two legacy
  administration placements and broader workflow/runtime work remain; the full
  ADR-024 goal remains active.


- Platform organization detail and invitations now belong to distinct host
  administration features, `organization-detail` and `organization-invite`.
  `/admin/organizations/:org_id` and its `/invite` child retain the existing
  browser/authenticated-scope pipeline, application live session and admin policy.
  Route parameters determine the organization; query fields cannot redirect an
  action to another tenant. Reads and effects require a fresh active persisted
  platform administrator and current admin-mode session.

  The detail contract exposes curated organization, membership, pending invitation
  and service identity facts. Each directory independently fetches at most 26 rows,
  exposes 25 and pages by exclusive binary identity. This is stable identity order,
  not a claim about chronology. Disabled members remain visible with their actual
  account state. Credential digests and arbitrary metadata are excluded. Native
  organization switching retains its POST form, method override and CSRF field.

  Service identity issuance accepts only a reviewed name and optional identity,
  fixes authority to the current organization and returns its plaintext token
  solely in the action reply. Duplicate identities preserve the original credential
  and produce a curated field error. The UI displays the token for the issuing
  visit and clears it on dismissal; refreshed snapshots contain only a safe identity
  receipt. Invitations admit a reviewed email, optional name, membership role and
  explicit platform eligibility grant. They persist before mail submission and
  distinguish submitted mail from an unavailable transport without claiming delivery
  or replaying the invitation. Deliberate replacement revokes the prior pending
  invitation. Accepting an existing recipient's invitation now applies the approved
  platform grant inside the locked acceptance transaction, without enabling admin
  mode automatically.

  Both actions bind path, administrator, organization and visit token. Successful
  visits are consumed. Unknown transport outcomes retain the draft and prevent
  automatic retry; refresh alone cannot establish that an operation failed. Late
  replies cannot replace a newer page, user or visit token. Legacy remote entries
  now delegate to public owner destinations and their effects use the same scoped
  operations. The core route table has no remaining legacy application/surface
  placements; the separate federated application adapter remains available for
  explicitly mounted applications and forwards caller-owned presentation attributes.

  Focused domain, real producer-to-Vue-to-effect, web and host checks pass. They
  cover bounded tenant reads, duplicate credential preservation, reviewed grants,
  recipient acceptance, mail submission failure, consumed visits, revoked sessions
  and stale completions. The full frontend suite passes 1,214 component tests plus
  Node suites; type checking passes all 20 Vue projects with no errors, and strict
  Credo reports no issues. Coordinated publications and native Phoenix assets
  compile successfully. Actual Chrome 152 coverage passes independent paging and
  deep reload, native CSRF organization switching, duplicate identity correction,
  issuance and credential authentication restricted to the correct organization,
  token dismissal and absence after reload, persistent host navigation, reviewed
  invitation fields, mail submission receipt, pending invitation reads, recipient
  acceptance and session removal. The enclosing test verifies persisted identity
  authority, membership and platform eligibility without automatically enabled
  admin mode. Desktop and 390px layouts were inspected. The first browser attempt
  found a test selector looking inside the panel for the title rendered in the
  shared page header; correcting that selector allowed the complete run to pass.
  The combined root gate passed 42 plane tests and 3,728 workspace
  tests: 333 foundation, 2,385 domain, 874 web and 136 simulator.
  All 5,549 frozen sources matched at completion, with zero unrelated changes.
  The full ADR-024 goal remains active: auth/navigation ownership and broader
  authorized workflow gaps require further work.


- Auth and navigation now has feature-local owners for sign-in, admin-mode
  reauthentication, invitation acceptance, organization access, account menus and
  primary navigation. The notification bell belongs to the existing notifications
  feature and is composed beside account actions. Historical LiveVue component
  identities resolve through explicit public exports; the former shell implementations
  and their displaced tests are removed. ApplicationShell and BrowserHost retain
  host composition and transport. Shared native navigation helpers have typed public
  exports for the demonstrated shell and Ops consumers.

  Native session pages and the shell context have version-1 producer contracts.
  Each feature validates its own data and contains malformed or unsupported input.
  Invalid native form data hides its effects and offers a safe recovery destination.
  A malformed notification summary can disable the bell without removing account
  actions, and failed primary navigation retains a home link. Bell destinations
  remain compiled inbox links; notification payloads cannot supply their own action
  URLs. The real host continues to derive navigation selection from its compiled
  route metadata rather than trusting server-selected frontend components.

  Sign-in retains the browser and redirect-if-authenticated-scope pipeline and auth
  live session. Invitation links retain the browser pipeline; admin-mode, organization
  switching and sign-out retain the authenticated browser pipeline. Native forms keep
  their original endpoints, method overrides, CSRF fields, credential names and
  password autocomplete semantics. They do not gain client-side effect ports. Valid
  CSRF updates preserve typed credentials; validation responses retain only the
  non-password values supplied by Phoenix. Invitation copy distinguishes platform
  eligibility from an enabled admin-mode session.

  The no-organization page now counts usable invitations for the active persisted
  recipient with a database aggregate over pending, unexpired rows. Reading a
  notification does not hide a pending invitation, and expired, revoked or synthetic
  notification entries do not imply available access. The count is independent of
  notification paging and refreshes recipient email and account state from persistence.

  Two domain tests cover recipient isolation, 125-row counting, expiry/status rules,
  current email and disabled accounts. Nineteen focused web tests pass, including
  actual producer data mounted through BrowserHost and the public feature components,
  with captured native forms driving sign-in, organization selection, admin-mode,
  invitation acceptance and sign-out through Phoenix. Full frontend verification
  passes 1,223 component tests, including all 65 Storybook Chromium tests, plus Node
  suites. Type checking passes all 20 Vue projects and strict Credo reports no issues.
  Storybook initially found missing icons because its CSS scan still referenced the
  old owner; its explicit sources now include auth and navigation. Production CSS
  already includes the complete host source tree. Coordinated publications and
  native assets compile successfully. Actual Chrome 152 coverage passes password
  rejection and sign-in, admin-mode entry and exit, native organization selection
  and sign-out, an already-read pending invitation, existing-recipient acceptance,
  new-recipient native acceptance, password mismatch with non-password value
  retention, platform eligibility without enabled admin mode and session removal.
  The enclosing test verifies the resulting memberships, accepted invitation and
  platform capability. Desktop and 390px layouts were inspected. The auth/navigation
  combined root gate passed 42 plane tests and 3,731 workspace
  tests: 333 foundation, 2,387 domain, 875 web and 136 simulator.
  All 5,569 frozen sources matched at completion, with zero unrelated changes.
  The first full run timed out waiting for verifier-scheduler telemetry. All four
  scheduler tests passed in isolation. The next run exposed an older shell-test
  assertion for the former sign-in prop; it now checks the versioned page contract.
  Focused shell tests and this complete final retry passed.
  Broader authorized commanding and evidence-history workflows remain open; the
  full ADR-024 goal remains active.

- Commanding now has a feature-local command request review owner, public entry and
  compiled `commanding.review` Ops contribution at
  `/missions/:mission_id/ops/commands/requests/:command_request_id`. The route uses
  the authenticated browser scope and application live session with Ops placement;
  privileged reads and decisions additionally require fresh mission-management
  authorization from persisted user and membership state. The monitor supplies a
  freshly checked `can_review` field and retains its filter/focus URLs and evidence
  for older identities that cannot form a review route.

  The review contains exact target, pinned model reference, command, submitted and
  resolved arguments, criticality, timing and requester identities. Arbitrary
  metadata and actor fields remain excluded. Decision history uses an exact scoped
  request and a 26-row database query for 25 displayed records and a durable cursor.
  A shared request lock keeps request semantics and history coherent during reads;
  the output has a 128 KiB bound. Approval/rejection now locks the request before
  checking pending state, human actor, self-review and the optional exact-content
  precondition, then inserts the decision and updates lifecycle in one transaction.

  The finite UI action constructs its actor on the server and returns the persisted
  decision identity. Host bindings include organization, mission, request, user,
  path and page token. A submission consumes its page operation; lost responses can
  recover the saved receipt by reading, without automatic repetition. Changed
  reviewed content clears the client's earlier decision and confirmation. Pending
  navigation is guarded, and stale or foreign responses cannot replace the review.
  Approval does not itself enqueue or release a command. The approval reason column
  is widened to text so the 2,000-byte UI boundary can be persisted without truncation.

  Eight focused domain tests cover scoped reads, fresh authorization, exact review
  preconditions, concurrent decisions on independent database connections and the
  full 2,000-byte Unicode reason round trip. Nine focused web tests pass, including
  actual producer data consumed by Vue and its captured decision sent through Phoenix
  to a persisted receipt. Full frontend verification passes 1,239 component tests,
  including all 65 Storybook Chromium tests, plus Node suites. All 20 Vue projects
  type-check, strict Credo passes and architecture checks report no new or unclassified
  boundary violations. Coordinated publications and native assets build successfully.
  Actual Chrome 152 passes 13 scenarios covering requester isolation, managed review
  navigation, exact command semantics, mobile layout, approval with the full reason,
  receipt refresh, reload without replay, rejection, 25-plus-2 history paging, member
  denial and session removal. The enclosing database test confirms the real reviewer,
  exactly one decision per request and no queue or release entries. Desktop and 390px
  captures were inspected. The reason regression first demonstrated the old database
  limit, then passed after the text-column migration.
  Command review combined root gate passed 42 plane tests and 3,743
  workspace tests: 333 foundation, 2,395 domain, 879 web and
  136 simulator. All 5,587 frozen sources matched at completion,
  with zero unrelated changes.
  The architecture task currently examines an empty workspace-root dependency graph.
  A separate official domain xref audit covers 1,324 sources and 5,453
  edges and finds no boundary findings originating in this cohort; it does expose
  existing findings elsewhere. The root task result therefore does not establish
  whole-domain architecture compliance. Correct graph generation remains follow-up
  work alongside the open UI workflows.
  Command authoring/stages, queue/release workflows, the monitor's mission-wide
  canonical IO and broader release/verifier evidence history remain open. The full
  ADR-024 goal remains active.

- **Direct command authoring** now belongs to the Commanding module's
  `features/command-authoring` slice, with the public
  `@cadence/commanding/command-authoring` entry and compiled `commanding.authoring`
  Ops contribution. `/missions/:mission_id/ops/commands/new` uses the authenticated
  browser scope (`:browser`, `:require_authenticated_scope`) and application
  LiveView session with `:require_user_scope`; every read, preview and create also
  requires fresh human `manage_mission` authorization. The monitor exposes the
  creation link only to the corresponding authorized audience. Existing command
  review and monitor URLs retain their identities.
  Target and command discovery uses 25-entry pages with durable identity cursors,
  search and explicit selection. Argument controls preserve omitted defaults,
  fixed values and explicit false, reject unsafe integers, and support UTC timing
  without losing precision. The server resolves a preview against the exact active
  model, target and invocation; it supplies the actor and reserved request ID.
  The user reviews submitted and resolved arguments, target, model, safety fields,
  priority and timing before confirming creation. Previewing does not persist a
  request. Creation consumes one host-held attempt; uncertain outcomes recover an
  exact persisted receipt by read without replaying the mutation. A subsequent
  review still enforces its own human approval policy, including self-review denial.
  Model activation, revision/plan identities and target rows remain locked through
  revalidation and insertion. Creation rechecks current human access immediately
  before insertion after any lock wait. Changed basis, target, preview or scope
  rejects the attempt. Duplicate request IDs produce errors rather than reporting
  an uninserted value as success. Three independent-connection tests prove that a
  real activation waits for insertion, a waiting create rejects a changed generation,
  and access revoked during that wait prevents insertion.
  Catalog admission reads revision metadata, four exact ready plan identities and
  only the command plan document. SQL limits that returned document to 8 MiB;
  active/target metadata is capped at 64 KiB, discovery/preview documents at 128 KiB,
  and editable argument sets at 64 fields. Oversized and inconsistent models remain
  unavailable. These limits bound returned data and application materialization;
  the JSON size predicate does not establish a physical database IO or CPU bound.
  Focused domain and existing commanding/review regressions passed 35 tests.
  Host component coverage exercises captured preview/create/read ports and late
  responses after replacement. The actual server document also passes through the
  compiled Vue producer into Phoenix preview and create handlers with a persisted
  receipt. Eight final web tests passed with incremental props enabled; departure
  assertions consume the fresh host-context reply rather than stale bootstrap HTML.
  Full frontend testing passed 1,250 component/Storybook tests, including
  65 Chromium Storybook tests, plus transport and tool checks. All 20 Vue projects
  type-check; lint reports zero errors with 229 existing warnings. Production
  publication and native asset builds passed.
  An authenticated Chrome 152 run passed 15 discovery, paging, selection, preview,
  confirmation, receipt, review-navigation, mobile and permission scenarios with
  zero browser errors. Its database assertions prove one request with the signed-in
  author and resolved default, and zero queue/release rows. Desktop discovery,
  resolved preview, persisted receipt and 390px screenshots were inspected.
  A separate official domain xref audit covers 1,329 sources and 5,473 edges:
  the same 307 pre-existing findings remain, with no new or removed findings. The
  empty-graph root architecture task limitation documented above still applies.
  Command authoring combined root gate passed 42 plane tests and 3,762
  workspace tests: 333 foundation, 2,410 domain, 883 web and
  136 simulator. All 5,605 frozen sources matched at completion,
  with zero unrelated changes.
  Command stages, queue/release workflows, mission-wide monitor IO, full release
  and verifier history and the broader final ownership audit remain open. The full
  ADR-024 goal remains active.


- **Command stages** now use three Commanding-owned vertical slices:
  `features/command-stages`, `features/stage-create` and
  `features/stage-workbench`, each with a public package entry, validated contract,
  contribution and local tests. The workbench owns its repeated-edit state.
  Shared argument controls and semantic validation now serve both direct authoring
  and staged authoring from `shared/command-draft`; features do not import another
  feature's private implementation. Host composition registers `commanding.stages`,
  `commanding.stage-create` and `commanding.stage-workbench`.
  The directory, creation and workbench URLs live below
  `/missions/:mission_id/ops/commands/stages`. They use the existing authenticated
  browser scope (`:browser`, `:require_authenticated_scope`) and application
  LiveView session (`:require_user_scope`) because every stage operation requires
  a current human mission manager. Private stages remain visible only to their
  owner, including when another user is an organization administrator. Shared
  stages allow mission-manager item collaboration; container settings remain
  owner-controlled. SQL applies visibility before directory paging.
  Directory, command and target discovery use 25-entry pages. Workbench item pages
  use paired order-and-ID cursors; an independently selected item can remain
  inspectable outside the visible page. Bounded SQL materialization and finite DTOs
  reject oversized argument documents without hiding the item's cancellation path.
  Notes, ordering and cancellation work without an available current command model.
  Description and notes columns now support the admitted 4,000-byte UTF-8 values.
  All stage writers and batch submission share the scoped stage lock, preserving
  immutable owner, item parent and submitted-request pointers. Selected batches
  contain at most 25 distinct current item fingerprints. Phoenix holds the exact
  resolved command semantics, model and target identities, real actor and reserved
  request IDs. Submission revalidates this evidence and current authorization under
  locks before inserting the entire batch and its item pointers atomically.
  A stage becomes submitted only when no draft items remain under the same lock.
  Native independent-connection tests cover competing submissions, edits, additions,
  cancellation and permission changes after stage or target lock waits.
  Captured route/actor sessions and separately consumed write nonces protect repeated
  edits. Known outcomes can be read from the retained host receipt before a fresh
  nonce is issued. Unknown formal submissions recover exact persisted request
  evidence without replay. Unknown draft writes permit an explicit fresh-state
  restart without claiming a historical receipt. A batch preview shows resolved
  arguments, target, model, timing, priority, notes and actor; explicit confirmation
  precedes formal request creation. Approval, queueing and release remain separate.
  A native test exposed out-of-range uint8 values resolving successfully and encoding
  999 as 231. Shared integer-width validation now rejects out-of-range provided,
  default, fixed and opcode values at resolution/encoding boundaries. Four focused
  regressions and all 27 catalog tests pass. This does not close the separate
  string/binary, boolean, layout-width or floating-point encoder conformance audit.
  Focused stage, authoring, review, integer and concurrency checks passed 84 domain
  tests. Eleven Phoenix producer regressions include actual compiled Vue controls
  producing creation, repeated draft edits, batch previews and persisted submission.
  Full frontend testing passed 1,263 component/Storybook tests, including 65 Chromium
  Storybook cases, plus transport/tool checks. All 20 Vue projects type-check; lint
  reports zero errors and 230 warnings. Strict Credo examined 2,540 sources with no
  findings. Publication and native asset builds passed; publication and Credo's
  final logs were recovered after their original tool exit handles were lost.
  An authenticated Chrome 152 run passed 24 scenarios with zero browser errors:
  native sign-in, private/shared access, all four paging paths, search, two draft
  saves, notes/order, explicit cancellation, exact batch confirmation, receipt/read
  recovery, reload, review navigation and session removal. Database assertions prove
  exactly one formal request with the signed-in actor, resolved default and source
  item provenance, and zero queue/release records. Desktop directory, reviewed batch,
  persisted receipt and 390px draft screenshots were inspected.
  The official domain xref audit covers 1,335 sources and 5,514 edges, retaining
  the same 307 pre-existing findings with zero new or removed findings. The root
  architecture task's empty graph limitation remains open.
  Command stages combined root gate passed 42 plane tests and 3,814
  workspace tests: 333 foundation, 2,459 domain, 886 web and
  136 simulator. All 5,651 frozen sources matched at completion,
  with zero unrelated changes.
  Queue/release workflows and encoder conformance, mission-wide monitor IO,
  complete release/verifier/evidence history, architecture task repair and the
  broader final ownership audit remain open. The full ADR-024 goal remains active.


- **Command wire validation** now protects the direct-authoring and staged-authoring
  workflows at request validation and runtime encoding. The shared catalog
  `WireEncoding` and `WireValue` helpers admit the fixed layouts and values the
  encoder can faithfully represent. The authoring catalog derives its supported
  flag from this admission as well as the argument-count limit. Both authoring
  features explain when the current command definition cannot be prepared;
  ordinary stage inspection remains available.
  Overlong strings and binary values fail before encoding instead of being cut.
  String widths use encoded bytes, preserving UTF-8 boundaries. Fixed and null-
  terminated UTF-8/ASCII strings validate padding, terminators and character sets.
  Boolean arguments require actual booleans and honor their declared byte order.
  Signed enumerated values preserve signed bounds through resolution and encoding.
  Float32 overflow cannot emit an infinity bit pattern. Argument-specification
  defaults and fixed values pass the same wire checks as supplied values.
  Unknown format names retain an unsupported marker through normalization.
  Unimplemented integer/float formats, length prefixes and dynamic encodings are
  unavailable rather than silently using a different format. Duplicate argument
  identities, missing references, overlapping/out-of-layout steps, alternate bit
  origins and mismatched argument/step widths fail definition admission.
  Validation runs before buffer allocation. The complete padded output, including
  its opcode, is limited to 1 MiB, with at most 4,096 specifications and steps.
  A declared model maximum can further restrict its layout. Valid little-endian,
  bit-packed, signed, boolean and multibyte string cases retain exact expected
  bytes. Unknown resolved argument names and fixed-value overrides are rejected.
  Nineteen encoding cases and four workflows using actual imported, compiled and
  activated models passed. Those workflows prove direct and staged rejection before
  persistence, valid UTF-8 request creation, float-width/overflow rejection and no
  partial submission when a previously stored batch contains an invalid wire value.
  An actual unsupported-model producer also passes through the compiled Vue
  consumer, which offers no preview action. All 27 catalog tests passed.
  Full frontend testing passed 1,264 component/Storybook cases, including
  65 Chromium stories, plus transport and typecheck-tool checks. An initial
  Storybook session-start timeout was followed by a successful full rerun.
  All 20 Vue projects type-check; lint reports zero errors and 230 warnings.
  Strict Credo examined 2,544 sources with no findings. Production publication
  and native assets built successfully.
  Authenticated Chrome 152 regressions passed all 15 direct-authoring and 24 stage
  scenarios with zero browser errors, alongside 11 Phoenix producer tests.
  Each browser workflow verifies its exact persisted request and zero queue/release
  rows. Eight current desktop/mobile screenshots were inspected. The official
  domain graph remains 1,335 sources and 5,514 edges with the same 307 pre-existing
  findings and zero new or removed findings; the root empty-graph limitation remains.
  Command wire validation combined root gate passed 42 plane tests and 3,837
  workspace tests: 333 foundation, 2,482 domain, 886 web and
  136 simulator. All 5,655 frozen sources matched at completion,
  with zero unrelated changes.
  Queue/release workflows, mission-wide monitor IO, full release/verifier/evidence
  history, architecture task repair and the broader final ownership audit remain
  open. Command-level default/fixed maps and layout-level opcode byte-order
  interpretation still need a contract audit before any new semantics are added.
  The full ADR-024 goal remains active.

- Command queue admission now locks the exact organization/mission/request before
  checking lifecycle and expiry. Control's immutable approved-content handoff is
  checked against that locked request before persistence. An internal precondition
  can reject admission after the request and lane locks are acquired. Expiry is
  checked again after a lane wait. Queue insertion and the request transition commit
  together, and automatic dispatch is scheduled after that commit.
  Native tests first reproduced three predecessor failures: cancellation was
  overwritten with a persisted queue row, changed approved content was queued, and
  a VM-generated sequence overtook an earlier persisted equal-priority entry.
  Lane ordering now uses the persisted lane maximum under a transaction-scoped
  advisory lock, with an index for the scoped sequence lookup. The existing bigint
  storage and durable request/queue identities remain in use. Sequence exhaustion
  rejects admission without partial effects. Existing database uniqueness
  constraints are mapped to their actual names so conflicts return changesets.
  Eleven independent-connection database cases pass, covering those three failures,
  duplicate concurrent admission, commit ordering within a lane, independent endpoint
  lanes, rejected preconditions, sequence exhaustion, expiry while waiting,
  uniqueness rejection and dispatch observing committed queue data. The persisted
  predecessor fixture models restart ordering; it does not run an actual VM restart.
  The broader Commanding regression passed 122 tests. Strict Credo examined 2,546
  source files with no issues after test alias cleanup. Official domain xref reports
  1,336 sources and 5,516 edges with the same 307 existing findings and zero new or
  removed findings; the root empty-graph limitation remains open.
  Command queue admission combined root gate passed 42 plane tests and 3,848
  workspace tests: 333 foundation, 2,493 domain, 886 web and
  136 simulator. All 5,658 frozen sources matched at completion,
  with zero unrelated changes.
  The human queue/release interface, mission-wide monitor IO, complete evidence
  histories, architecture task repair and the final ownership audit remain open.
  This admission prerequisite does not complete the full ADR-024 migration goal.
- Commanding now owns a queue-submission vertical with its local semantic contract,
  confirmation state, component tests and public contribution. Request review links
  to `/missions/:mission_id/ops/commands/requests/:command_request_id/queue` under
  the existing authenticated browser/application session and Ops host policy.
  Phoenix authorizes every load, action and recovery read. The server retains the
  approved request, actor and operation identity; the browser submits only the
  exact preview token after an explicit transmission warning and confirmation.
  Authorization and reviewed content are checked again after database lock waits.
  Lost replies consume the attempt and use reads to recover only the matching
  persisted operation, actor, target, timing and approved-content hash. Another
  operation's queue is displayed as observed state without claiming its receipt.
  A reload shows the existing queue entry and cannot submit it again. The receipt
  establishes queue admission; release and verification remain separate evidence.
  Argument and opcode previews preserve server-produced JSON text so 64-bit values
  are not rounded by JavaScript display. Queue sequence is a bounded decimal string.
  This view labels priority ranks 0 through 4 as Urgent, High, Elevated, Normal and
  Low; other persisted ranks display Custom with their numeric rank. Authoring and
  staging still expose numeric priority inputs, so ADR-011's named-class input
  requirement remains open.
  Release claims now share the queue admission lane lock and transactionally
  recheck the prepared request, queue state, expiry, lane occupancy and current
  ordering. The predecessor's independent-connection oracle persisted two
  `release_pending` entries in one lane; it did not execute two transmissions.
  Seven release admission cases cover that interleaving, higher-priority arrival,
  changed prepared content/routing, duplicate same-entry claims, independent lanes
  and cancellation during a request-lock wait. The runtime passes its exact
  prepared request into admission and transmits only after a successful claim.
  Existing restart requeue and late-completion behavior are not established as
  multi-node delivery safety by these claim tests.
  Five native imported-model queue service tests and an independent-connection
  authorization-after-lock-wait case pass. Five authenticated host tests include
  the actual Phoenix producer through compiled Vue confirmation into durable queue
  admission and receipt reads, exact recovery and access/token/path rejection.
  The frontend suite passed 1,275 tests including 65 Chrome Storybook cases; full
  workspace formatting, lint/type checks, publication and native asset builds pass.
  Authenticated Chrome passed 13 scenarios from a second person's hazardous-command
  approval through queue confirmation, receipt refresh, reload, review return,
  membership denial and sign-out. Native assertions verify one approval and one
  queue with the actual reviewer, imported model, target and resolved defaults.
  No release attempt is expected with this fixture's absent contact. Four desktop
  and 390px screenshots were inspected; no JavaScript errors were reported.
  The initial browser harness expected a shorter priority label and was corrected
  to the actual named rank label before the successful run.
  The broader native regression passed 71 Commanding/control tests. Strict Credo
  checked 2,553 source files with no issues after test alias cleanup. Official
  domain xref reports 1,338 sources and 5,526 edges with the same 307 existing
  findings and zero new or removed findings. The root empty-graph limitation remains.
  Command queue confirmation and release claim combined root gate passed 42 plane tests and 3,866
  workspace tests: 333 foundation, 2,506 domain, 891 web and
  136 simulator. All 5,675 frozen sources matched at completion,
  with zero unrelated changes.
  Broader release controls, monitor database materialization, full evidence history,
  architecture task repair and the final ownership audit remain open. This cohort
  does not complete the full ADR-024 migration goal.

- Command review now receives server-produced JSON text for submitted arguments,
  resolved arguments and opcode, retaining every decimal digit through the Vue
  contract and rendered review. An imported unsigned 64-bit default first proved
  the predecessor defect: the native value `18446744073709551615` remained exact
  in persistence while the existing browser consumer and display formatter showed
  `18446744073709552000` and still admitted approval. That predecessor evidence
  combines a native producer/action test with its actual JavaScript consumer and
  formatter; it is not a predecessor browser screenshot.
  The new contract checks JSON syntax and object shape without replacing the source
  text with parsed JavaScript numbers. The old numeric DTO is rejected, requiring
  a coordinated producer/consumer release. Existing held decision identities,
  authorization and approval effects remain authoritative in Phoenix.
  Authoring and stage editing now offer ADR-011's named priority classes, preserving
  an existing custom stage rank when switching choices. Previews and review use the
  same named rank labels. Unsafe JavaScript integers in authoring and staged draft
  contracts still fail closed; full unsigned 64-bit browser authoring is a separate
  support limitation. The exact review fixture was created through the native
  authoring API with an imported model default.
  Thirty focused Vue cases, six native review cases and ten authenticated host
  cases pass, including the actual imported-model producer through compiled Vue
  into a human approval with the exact persisted default. The full frontend suite
  passed 1,278 cases including 65 Chrome Storybook cases; full formatting, lint,
  type checks, production publication and native assets pass. Strict Credo checked
  2,554 sources with no findings. Authenticated Chrome passed 28 listed scenarios
  across two native workflows: exact review and queue confirmation, plus named
  authoring priority selection persisted as rank 1. Additional assertions verify
  the full unsigned 64-bit decimal on desktop and 390px review screens. Ten current
  screenshots were inspected and no JavaScript errors were reported. Native checks
  establish the exact approval/queue and authoring receipts, without a release
  attempt in these absent-contact fixtures.
  Official domain xref remains 1,338 sources and 5,526 edges with the same 307
  existing findings and zero new or removed findings. The root empty-graph
  limitation remains open.
  Exact command review and named priority combined root gate passed 42 plane tests and 3,867
  workspace tests: 333 foundation, 2,506 domain, 892 web and
  136 simulator. All 5,676 frozen sources matched at completion,
  with zero unrelated changes.
  Bounded monitor database materialization, complete release/verifier/evidence
  history, broader release controls, architecture task repair and the final
  ownership audit remain open. The full ADR-024 migration goal remains active.

- Mission command monitoring now uses a scoped database read with one statement
  snapshot for the page, independent focus, mission-wide summary, counts and target
  choices. PostgreSQL returns at most 25 page rows, one focused row, 20 verifier
  previews per displayed request and 201 target values including lookahead. Each
  selected evidence row is limited to 64 KiB before database return; malformed or
  oversized selected evidence fails unavailable rather than becoming a truncated
  identity. This bounds result materialization, not mission-wide database scan or
  aggregate work. Arguments, encoded payloads, verifier criteria and arbitrary
  metadata are not selected. Only the displayed requester label is extracted from
  the actor document inside PostgreSQL.
  Native predecessor telemetry established that a 25-row page materialized all
  28 requests, 28 queues, 28 releases and 588 verifiers, including encoded payload
  columns. The new native query-result assertions verify one bounded result and
  absence of large persisted private fields. A separate oversized actor-label case
  proves its contents do not cross the database boundary. The first attempt used
  a display-name fixture exceeding its varchar column; the fixture was corrected
  to exercise a JSON-stored actor label without changing production behavior.
  The existing canonical projection remains the comparison oracle. Tests preserve
  lifecycle/status precedence, legacy state normalization, latest-release ordering,
  all-verifier status/counts, future-deadline ordering, literal wildcard search,
  Unicode conversion, 203 target choices, page clamping and filter-independent
  focus. A failure attached to an older release beyond the 20 displayed verifiers
  still makes the command failed. Search derives bound translation parameters from
  the same Elixir Unicode conversion rather than relying on database locale rules.
  No route, browser DTO version, contribution identity or command effect changes.
  Fourteen native monitor/review cases and six authenticated host cases pass,
  including actual producers through compiled Vue. The Commanding module suite
  passed 65 cases, with five conditional producer cases skipped in that standalone
  invocation; the host checks supply actual producer data. Strict Credo checked
  2,559 sources without findings, and production native assets built successfully.
  Authenticated Chrome 152 passed 15 scenarios covering pagination, independent
  focus, partial verifier evidence, exact Unicode/literal search, refresh/reload,
  organization denial and sign-out. Twelve measured monitor reads each returned
  one database result with at most 25 page rows, one focus and 20 verifier previews;
  the largest fixture result was 16,178 bytes. These measurements are fixture
  evidence, not a database scan-cost benchmark. Complete persisted request, queue,
  release and verifier records were unchanged after the browser workflow. Four
  current desktop/mobile screenshots were inspected with zero JavaScript errors.
  An initial harness sign-out selector was corrected for the existing dedicated
  no-organization-access form before the successful browser run.
  Official domain xref reports 1,342 sources and 5,538 edges, retaining the same
  307 existing findings with zero new or removed findings. The root empty-graph
  limitation remains open.
  Command monitor bounded database read combined root gate passed 42 plane tests and 3,873
  workspace tests: 333 foundation, 2,512 domain, 892 web and
  136 simulator. All 5,681 frozen sources matched at completion,
  with zero unrelated changes.
  Complete release/verifier/evidence history, broader release controls, large
  integer browser authoring support, architecture task repair and the final
  ownership audit remain open. The full ADR-024 migration goal remains active.


- Commanding now owns a separate `command-history` vertical with its own semantic
  contract, query admission, components, tests and compiled `commanding.history`
  contribution. The host places its request-addressed history route inside the
  existing authenticated browser/application LiveView session with Ops policy.
  Monitor evidence links open this history; the return link focuses the exact
  request. Phoenix retains mission authorization and the read grants no command
  action port or action token.
  A single scoped statement snapshot supplies independently paged release and
  verifier ledgers: 25 displayed records and one lookahead each, with explicit
  selections independent of their current pages. Cursor identities resolve only
  within the exact organization, mission, request and selected release. Missing
  or foreign selections fail unavailable rather than substituting a newer release.
  Live ledger pages do not claim a frozen snapshot across separate refreshes.
  Matched references come from the selected persisted verifier. Telemetry is scoped
  to its mission; transport actions and capability records must additionally match
  the exact request and release, preserving native document-wrapper and fallback
  precedence. Missing, oversized or malformed backing evidence is local to the
  evidence panel. Telemetry values remain bounded server-produced JSON text, keeping
  unsigned64 digits exact. Private provenance, request documents, wire payloads,
  verifier criteria and arbitrary metadata are omitted. Native result size is bounded
  before database return; this does not establish constant database scan cost.
  Eight history tests and six monitor regressions pass, including multi-page ledgers,
  independent selections after newer releases, scoped rejection, exact wide values,
  all three backing-record kinds, correlation precedence and malformed evidence.
  Three authenticated history host tests and five monitor host regressions pass,
  with actual native DTOs validated and rendered through the real Vue contribution.
  Twenty-four new mounted/contract tests pass. The full frontend suite passed 1,302
  cases including 65 Chrome Storybook cases, plus its node tooling/transport gates.
  Full frontend checks, production publication and native assets passed. Strict
  Credo checked 2,568 sources after alias ordering cleanup. Fixture schema dependencies
  found by official xref were repaired through existing public persistence APIs;
  xref reports 1,348 sources and 5,553 edges with the same 307 existing findings,
  zero new and zero removed. The root empty-graph limitation remains open.
  Authenticated Chrome 152 passed 17 scenarios covering monitor-to-history navigation,
  25-plus-3 release pages, 25-plus-5 verifier pages, older failure selection, all
  three matched-record kinds, refresh/reload, browser back, missing evidence,
  organization denial and sign-out. Four desktop/mobile screenshots were inspected
  with zero JavaScript errors. All persisted request, queue, release, verifier,
  telemetry sample and transport records remained unchanged. 17 measured reads
  each returned one database result with at most 26 release and 26 verifier rows;
  the largest fixture result was 17,635 bytes. These are read
  fixtures, not proof of command transmission or spacecraft execution. The initial
  browser harness was corrected to open the monitor's existing collapsed evidence
  disclosure before following its history link.
  Command history combined root gate passed 42 plane tests and 3,884
  workspace tests: 333 foundation, 2,520 domain, 895 web and
  136 simulator. All 5,700 frozen sources matched at completion,
  with zero unrelated changes.
  Broader release controls, large integer browser authoring support, architecture
  task repair and the final ownership audit remain open. The full ADR-024 migration
  goal remains active.

- Command authoring and stage workbench now carry exact argument JSON text across
  the browser boundary. Authoring catalogs and stage workbench documents use
  version 2; the stage directory remains version 1. Defaults, fixed values and
  hazard displays retain their original JSON text. Submitted and resolved preview
  arguments and selected draft arguments no longer travel as JavaScript numeric
  maps. Integer controls preserve decimal/scientific input using digit arithmetic;
  numeric-looking enum strings remain distinct from numeric enum input. Float
  controls retain finite JavaScript number semantics, not arbitrary decimal
  precision. Old or mixed argument DTOs and duplicate JSON keys are rejected.
  Phoenix still derives the actor and model basis, holds previews and governs
  request creation and atomic stage submission. Existing authenticated Ops routes
  and durable identities are unchanged.
  The native predecessor fixture retained the exact imported uint64 default
  `18446744073709551615`, while the actual authoring consumer rejected its decoded
  catalog after JavaScript rounded the default. The old explicit wide-integer
  input was rejected as well. No request, queue or release was created by that
  predecessor proof; it did not demonstrate an approved rounded request.
  The coordinated contract removes that authoring support limitation. Native
  request tests verify unsigned defaults, explicit uint64 and signed64 values,
  numeric/text enum intent, exact encoded bytes and stored requests. Stage tests
  verify save, selected-item read, edit and formal batch submission. Existing wire
  limits still reject out-of-range integers. Argument documents keep their 64-key
  and 32 KiB input bounds, with 128 KiB resolved read bounds; a native command with
  more resolved defaults than the UI contract supports now returns unavailable
  without crashing or creating requests. Mounted tests cover exact controls,
  defaults/fixed/hazard text, typed enums, omission, false, zero, empty strings and
  float overflow. Fifteen focused web tests pass, including actual producers through
  mounted Vue into Phoenix request creation and stage submission. The full
  frontend suite passed 1,318 Vue cases including 65 Chrome cases, together with
  its tooling and transport tests. All 20 frontend projects typecheck; publication
  and native production assets build. Strict native analysis is clean across
  2,573 sources. The official domain graph contains 1,350 sources and 5,561 edges,
  with the same 307 existing boundary findings and zero new findings.
  Authenticated Chrome exercised 19 scenarios across default and explicit unsigned
  inputs, signed input, numeric and text enum inputs, previews and confirmation,
  receipt refresh, review navigation/reload, native range rejection, 390px layout,
  saved draft reload/edit and batch submission. Native assertions verify six
  requests and one submitted draft with exact values, zero queues and zero release
  attempts. This proves authoring and submission, not transmission or execution.
  Four desktop/mobile screenshots were inspected with exact digits visible.
  Exact authoring combined root gate passed 42 plane tests and 3,895
  workspace tests: 333 foundation, 2,529 domain, 897 web and
  136 simulator. All 5,708 frozen sources matched at completion,
  with zero unrelated changes.
  Broader release controls, restart/late-completion semantics, architecture task
  repair and final ownership verification remain open. The full ADR-024 migration
  goal remains active.


### Legacy dashboard entry and query handoff closure

- The durable Ops remote library, playlist directory, playlist presentation and
  activity entries now delegate to their dashboard feature owner. Compatibility
  pages retain exact mission, dashboard, playlist, version and issue identities
  in links to the existing authenticated Ops workspace workflows. They do not
  maintain duplicate forms or synthesize empty library, playlist or activity data.
  Native action IDs and their existing governed semantics remain available.
- Playlist presentation now declares its playlist subject and position query in
  native and frontend route metadata. The generic authenticated federation shell
  now supplies its URL selectors in `data-query-params`; previously the actual
  browser bridge sent an empty map and subject-based native reads failed.
  Shell transport admits a bounded flat string map and rejects duplicate decoded
  keys, nested values, forbidden object keys, control characters and excessive
  size using the existing unavailable-application response. Native readers remain
  responsible for scoped subject authorization and query semantics.
- Verification: 14 native producer/action/definition cases, 23 controller cases,
  24 existing authenticated dashboard workflow cases, and the full frontend suite
  passed. The browser rerun traversed all four actual authenticated federation
  shells and published remote entries to their canonical pages, preserved activity
  version/issue and playlist position after reload, reported no JavaScript errors,
  and left persisted dashboard and playlist records unchanged. Three desktop/mobile
  screenshots were inspected. An earlier frontend run hit a Storybook browser
  connection timeout; its subsequent full rerun passed without competing builds.
- Publication, frontend checks and official domain xref passed. The domain graph
  has 1,350 sources and 5,563 edges, with the same 307 pre-existing boundary
  findings and no new findings. The empty-root architecture-task defect remains
  open; passing the combined gate does not establish whole-domain compliance.
  Legacy dashboard combined root gate passed 42 plane tests and 3,900
  workspace tests: 333 foundation, 2,532 domain, 899 web and
  136 simulator. All 5,717 frozen sources matched at completion,
  with zero unrelated changes.
- This closes these four compatibility roots, not the full ADR-024 goal. Residual
  legacy widget reachability, broader ownership verification, release recovery
  semantics and architecture gate repair remain open.


### Explicit Ops registry and dashboard viewer/editor delegation

- The legacy dashboard viewer and editor now hand exact scoped identities to the
  existing authenticated Ops workspace viewer and editor. The predecessor native
  producer returned an empty canvas for a persisted, published one-widget
  dashboard; the actual old remote rendered zero widgets. The destination adapter
  preserves declared viewer selectors verbatim, including selections that the
  canonical page rejects as unavailable. Editor links admit only the dashboard
  identity. Neither compatibility entry maintains a second canvas or edit form.
- The Ops registry now explicitly imports its 34 native entry components and
  rejects inherited object members as renderer names. All durable surface/action
  identities, standalone entry and three federation exposes remain available.
  Reachability analysis including those roots identified 85 obsolete component
  and helper copies, which were removed. The active dashboard, chart and editor
  implementations remain with their domain owners, and shell components remain
  host-owned. Obsolete native empty-canvas and activity DTO builders were removed;
  active data-source and data-operations identity adapters remain.
- Verification: 21 native producer/definition/action cases and 36 native web
  workflow/navigation/clipboard cases passed. Thirteen focused dashboard Vue
  cases and 51 Ops tests passed; the full frontend run passed 1,331 Vue cases,
  including 65 Chrome cases, plus tooling and transport suites. All 20 frontend
  projects typecheck. Publication and native assets build successfully.
  Authenticated Chrome traversed all six actual published remote entries to their
  canonical routes and reloaded them, rendered the persisted placement in viewer
  and editor, preserved exact time, activity and playlist selections, rejected a
  missing dashboard, and retained an unavailable result for unsupported drilldown.
  Fourteen browser scenarios completed without JavaScript errors; native assertions
  confirmed unchanged dashboard and playlist records. Five desktop/mobile
  screenshots were inspected. The fixture contains no telemetry samples, so this
  establishes widget placement and navigation rather than telemetry delivery.
- The official domain dependency graph has 1,350 sources and 5,560 edges, with
  the same 307 existing findings and no new findings. The architecture task's
  empty-root graph defect remains open; these counts come from the actual domain
  graph rather than the combined gate's architecture summary.
  Dashboard registry combined root gate passed 42 plane tests and 3,900
  workspace tests: 333 foundation, 2,532 domain, 899 web and
  136 simulator. All 5,633 frozen sources matched at completion,
  with zero unrelated changes.
- The full ADR-024 goal remains active. Broader ownership/workflow verification,
  command release recovery and late completion, and architecture gate repair
  remain open.

### Remote renderer admission and host-owned notification bell

- The organization-admin notification bell now delegates through the host auth
  and navigation public entry to the canonical bell. Its native producer supplies
  a versioned recipient summary with five persisted notices, the authoritative
  unread count and actual read timestamps. The adapter validates that recipient
  against the separately supplied host user identity. Notice links lead to the
  canonical inbox; marking read and accepting invitations remain explicit inbox
  actions. Durable surface, query and action identities remain available.
- Mission catalog, spacecraft, telemetry decom and both Communications renderers
  now require an own registry entry before issuing a query. Mounted cases cover
  unknown names and inherited object member names. Eight unreachable presentation
  and helper copies were removed after checking federation exposes and standalone
  roots. Active compatibility entries still delegate to their owners.
- Native workspace discovery now excludes the frontend dependency tree. The
  official before/after project exports were identical, including all metadata
  for the six native projects. The measured discovery invocation decreased from
  106.25 seconds to 0.82 seconds. Frontend validation still covers its separate
  20-project workspace.
- Verification: five native inbox/producer cases and 31 native web cases passed,
  including the actual persisted bell DTO through the exposed remote component.
  The full frontend suite passed 1,355 Vue cases, including 65 Chrome cases, plus
  tooling and transport suites. Test mock type annotations and native aliases
  were corrected after initial typecheck/Credo findings; current checks and
  affected focused reruns pass. A focused Vue invocation from the workspace root
  lacked package configuration and ran no tests; package-local reruns passed.
  Publication and native asset builds passed.
- Authenticated Chrome traversed the actual published bell for an account without
  organization membership. Eleven scenarios checked the five-row summary, foreign
  recipient exclusion, canonical inbox navigation, unchanged unread state after
  navigation and reload, and the new count after an explicit inbox mark-read.
  Native assertions confirmed only that selected notice changed; the existing
  read timestamp and foreign notice remained unchanged. No JavaScript errors
  occurred. Desktop and 390-pixel screenshots were inspected.
- The production frontend import audit found 712 cross-package imports across
  20 packages, with no relative cross-package, unknown or unexported imports.
  The official domain graph remains at 1,350 sources, 5,560 edges and 307 existing
  findings, with no new findings. The separate empty-root architecture-task
  defect remains open.
  Remote residual combined root gate passed 42 plane tests and 3,901
  workspace tests: 333 foundation, 2,533 domain, 899 web and
  136 simulator. All 5,628 frozen sources matched at completion,
  with zero unrelated changes.
- The full ADR-024 goal remains active: remaining contribution admission and
  workflow verification, command release recovery and late completion, and
  architecture gate repair still require work.

### Derived Telemetry and Limits contribution lifecycle

- Both published adapters now admit the compiled application, surface and query
  identities and versions, mission scope and declared save action before reading.
  A shared delivery helper selects only their compiled registrations; feature DTO
  admission remains with the domain-owned surface. Limits posture has no save
  effect. The existing public contribution entries and durable identities remain.
- Each load captures its context and bound bridge methods. Changing host props
  synchronously retires old ports and starts a new load and feature instance.
  Retired reads, saves and navigation cannot issue another bridge operation;
  late responses cannot replace the current document or confirm another context's
  save. Current save/recovery calls preserve the exact input and idempotency key.
  The domain features retain their existing scoped draft and pending-save journals.
- Mounted predecessor evidence showed Derived Telemetry querying unsupported
  surface names, both adapters retaining old ports that used a later mission,
  and Limits retaining its definitions renderer after selection changed to
  activity. This used a recording local bridge and does not establish unauthorized
  Phoenix access. Eighteen current mounted cases cover admission, context and
  bridge changes, stale ports, delayed reads/saves, retry, unmount, posture
  selection and immutable action keys.
- Verification: 17 native producer/action cases and four authenticated Limits API
  cases passed. All 20 frontend projects typecheck; the full frontend retry passed
  1,372 Vue cases, including 65 Chrome cases, plus tooling and transport suites.
  The initial full run hit a Storybook connection timeout before its Chrome tests
  started. A deliberately malformed test context needed an explicit type cast;
  current typecheck and affected component tests pass. Publication, native assets
  and strict Credo passed.
- Authenticated Chrome exercised all three actual published remote surfaces,
  explicit Derived Telemetry and reviewed Limits saves, receipt and draft reload,
  two-mission isolation, and posture refresh/navigation. Twelve scenarios passed
  without JavaScript errors. Native assertions confirmed exactly one derived
  version and one active limit version in the reviewed mission, and none in the
  other mission. Three desktop/mobile screenshots were inspected. The posture
  fixture has no evaluated telemetry and verifies its empty-state flow. The first
  browser attempt used an incorrect receipt selector after a successful native
  save; the corrected complete rerun passed.
- The production import audit covers 713 cross-package imports in 20 packages
  without boundary findings. The official native graph remains 1,350 sources,
  5,560 edges and 307 existing findings, with no new findings; the separate
  empty-root architecture-task defect remains open.
  Contribution lifecycle combined root gate passed 42 plane tests and 3,901
  workspace tests: 333 foundation, 2,533 domain, 899 web and
  136 simulator. All 5,630 frozen sources matched at completion,
  with zero unrelated changes.
- The full ADR-024 goal remains active. Remaining workflow/ownership verification,
  command release recovery and late completion, and architecture gate repair
  still require work.

### Command release claim recovery and uncertain outcomes

- A new queue claim now binds its persisted release attempt in the same database
  transaction. Attempt insertion is strict: a duplicate identity cannot substitute
  different encoded bytes or leave a claimed queue without its new attempt.
  The queue's active-attempt reference is store-owned. The migration adds a nullable
  unique reference without inferring ownership for historical incomplete claims.
- Dispatcher startup preserves incomplete claims. Neither a missing completion nor
  a transport error proves that bytes were not delivered. An ambiguous returned
  error or process exit records `release_uncertain` and keeps the queue lane held;
  a failed uncertainty write still leaves the committed pending claim held.
  Legacy unbound claims also stay held and cannot authorize a completion. This
  does not introduce automatic replay or an operator override without durable
  evidence and governed authority.
- Completion locks the request, lane and queue and validates the current attempt,
  scope, prepared request and queue basis, immutable attempt and lifecycle. An
  older or mismatched result cannot write into a successor claim. An already
  completed attempt returns its recorded state without resetting verification,
  inserting duplicate verifiers or scheduling another dispatch.
- The canonical native monitor, bounded SQL projection, history projection, API
  filter and domain-owned Vue contracts all preserve `release_uncertain`. The
  monitor counts and filters it as indeterminate, and its evidence view explains
  that the lane is held and the command may already have been transmitted. History
  preserves the exact attempt selection and distinguishes uncertainty from a
  successful completion. Existing scoped routes and authorization are unchanged;
  the enum expansion ships with the coordinated frontend publication.
- Verification so far: 46 focused native cases and 38 affected Vue cases pass.
  Native coverage includes an actual TCP receiver obtaining a command before an
  injected transport-record persistence failure, followed by a held uncertain
  claim; this uses the shared rollback-only runtime sandbox. A separate test uses
  independent committed database connections, observes a waiting PostgreSQL lock,
  and proves a late failure cannot rewrite a successful completion. The initial
  TCP test expected an idle socket after the injected runtime failure; it was
  corrected to accept a closed socket as well as a timeout, with no further bytes.
- All 20 frontend projects typecheck, with the existing 237 warnings and no errors.
  The full frontend suite passes 1,375 Vue cases including 65 Chrome cases, plus
  tooling and transport suites. The publication build passes. Strict Credo's first
  review requested smaller claim-validation functions and test aliases; the
  revised native recovery suite passes. Eleven native web cases pass, including
  producer-to-compiled-Vue admission of uncertainty and the API state filter.
- Authenticated Chrome passed eleven scenarios against the actual publication:
  native bound uncertain claim, monitor status and filter, held-lane explanation,
  history navigation, exact release selection, absent completion and verifiers,
  reload, 390-pixel layout and return to the focused command. No JavaScript errors
  occurred. Native records were unchanged by browsing. Three desktop/mobile
  screenshots were inspected. Final strict Credo passed.
  Command release recovery combined root gate passed 42 plane tests and 3,915
  workspace tests: 333 foundation, 2,546 domain, 900 web and
  136 simulator. Of 5,633 frozen sources, 5,632 matched exactly. The root
  formatter wrapped one new web-test call before compilation and testing; its
  exact frozen predecessor, formatter output and location-free AST parity were
  verified. There were zero unrelated or unexplained changes.
- The production import audit covers 713 cross-package imports in 20 packages
  without boundary findings. The official native graph has 1,350 sources, 5,564
  edges and the same 307 findings, with no new findings. The separate empty-root
  architecture-task defect remains open. The full ADR-024 goal remains active.


### Architecture coverage recovery (verified)

The architecture task now derives one production graph from the current Cadence
and CadenceWeb compiler manifests, including cross-project references, instead of
accepting an empty workspace-root xref graph. Source inventories, compiler hashes,
reference labels and prepared JSON are checked before boundary findings are
admitted. Isolated two-project compilation tests exercise cross-project coverage,
stale source rejection and uncompiled source rejection.

The recovery also removes dashboard settings row exposure through an
owner-held snapshot transaction and moves Data Sources event and credential reads
behind owning APIs. Scoped native event tests preserve exact event identity,
domain values, organization isolation and mission-bound organization-neutral
history. Reviewed host adapters, declaration values, configuration owners and
supervision/address contracts now have explicit ownership with negative boundary
tests. All findings have been resolved against the complete graph and the combined
root gate passed. The full UI ownership goal remains active.


Telemetry Decom query-provider declarations now live with its existing frontend
catalog/release contribution module, preserving the public contributor function.
Mission Model activation-manifest construction now belongs to the Management
owner; the Control helper delegates to that owner and preserves its existing API.
The deterministic semantic evaluator and its plan/value types have a shared
Catalog classification, while durable execution storage remains Runtime/Data.
The first recovered root architecture command verified 1,451 production sources
and 6,160 dependencies and rejected 16 outstanding findings; subsequent owner
extractions remain subject to the next combined check.


The recovered production check now passes with 1,454 domain/web sources and
6,169 dependencies, with zero findings and the unchanged empty baseline. Exact
prepared graph JSON passes the CLI; empty prepared JSON is rejected. The frontend
import audit still covers 713 cross-package imports in 20 packages with no issues.

The source repairs include typed job availability facts consumed by
nondefault dispatchers, public Contact settlement during mission lifecycle
assembly, precise fleet continuation/repair ownership, and Data-owned source
observation journals. Limits checks explicit persistence scope without loading a
mission object. Active generation reads now pass through a bounded read adapter;
Management authoring/qualification retain their authority. Seventy-two focused
native cases cover that extraction, including exact digest bytes, scoped callbacks,
concurrent generation/target locks, stage operations and comparison. Forty-four
architecture cases cover actual compiler coverage and positive/negative ownership
contracts.

The combined root `mix precommit` passed on 2026-09-11 (UTC): strict compilation,
Credo, workspace boundaries, extension integrity, the recovered architecture check,
42 plane tests and 3,939 workspace tests (333 foundation, 2,569 domain, 901 web,
136 simulator). All 5,638 frozen files matched exactly, with 41 owned changes and
zero unrelated changes. This closure paragraph is the only post-gate source change.
No frontend files changed in this recovery; earlier browser/publication evidence
is not a new browser run for this cohort.

The full ADR-024 goal remains active. The registered legacy Ops workspace landing
still presents integration-demo text and a hard-coded component count. Its
host-owned navigation replacement and verification are next. Registered dock
composition also needs a current completeness review.


### Ops workspace landing recovery (verified)

The advertised `/missions/:mission_id/ops` entry now resolves to HostPageLive in
the existing authenticated `:application` session, using `:ops` authorization and
operational context. Host shell selection explicitly recognizes this entry.
The host-owned landing feature replaces integration-demo text and the literal
component count with mission-scoped Observe, Act, Plan and System navigation.
The Ops rail and landing share one typed destination definition. Phoenix derives
administrative admission; the frontend accepts only a versioned model whose
organization and mission match the independent current host context.

The historical `ops_console` / `workspace` surface and `cadence.ops.workspace`
query identities are unchanged. Its producer delegates to the same authorized
read owner, and its delivery component delegates to the host's public Ops entry.
Response-supplied host identities cannot override the authenticated context.
Malformed models, unsupported versions and stale mission identities render an
unavailable state without destination links. Existing URLs and native navigation
remain intact; a coordinated publication supplies the new DTO and consumer.

Verification so far: eight focused native producer/registration cases, including
actual producer-to-mounted-Vue coverage for member and administrator models;
16 initial web cases plus three final landing cases covering entry, query-scope
substitution, foreign-mission rejection, navigation away and back, anonymous
access and revoked-session refresh; 17 legacy adapter cases; 1,387 full frontend
cases including 65 Chrome cases, followed by 86 focused host/navigation cases
after the final shell-selection correction. Final Vue-aware checking passed all
20 frontend projects. Both the final production publication and Phoenix asset
build passed. The static import audit covers 714 cross-package imports in 20
packages with zero issues or unknown imports.

A native authenticated Chrome 152 run passed 13 scenarios: canonical and published
entry, permission-filtered links, persistent host navigation, browser history,
reload, published-to-canonical navigation and 390px layouts. Four screenshots
were visually inspected. The in-app browser could not connect because its tool
metadata lacked `sandboxPolicy`; the existing ephemeral Phoenix/native Chrome
harness supplied this browser evidence. The combined root `mix precommit` gate
passed. The full ADR-024 goal remains active, including the registered
Ops dock composition review and remaining requirement-by-requirement audit.

The first combined attempt stopped on one alias style correction. The next passed
architecture and all plane/foundation checks, then failed one existing 200ms
source-deadline expectation during the async domain phase. All ten cache-execution
cases passed in isolation with the same seed. That test module now runs in ExUnit's
synchronous group; concurrent provider execution, deadlines and every test body
remain unchanged. The fresh combined gate passed after this scheduling fix.

Ops landing combined verification passed 42 plane tests and 3,944 workspace tests
(333 foundation, 2,571 domain, 904 web and 136 simulator). The recovered architecture
check covers 1,456 production sources and 6,176 dependencies with zero findings.
All 5,647 frozen files matched exactly; 26 changes belong to this cohort and no
unrelated changes occurred. Only this ADR status and closure prose changed after
the gate. The full migration remains active pending the remaining ownership and
workflow completeness review.

### Published dashboard creation recovery (verified)

The authenticated published `ops_console/dashboard_new` entry returned an approved
query successfully but rendered no usable form: its generic `form.fields` and
nested page header did not match the creation presentation contract. Chrome
confirmed the contained undefined-field exception before this cohort.

The historical entry now delegates to the dashboards-and-exploration creation
owner's public `CreationDestination`. Its versioned semantic model carries the
organization, mission, admitted creation mode and optional clone source identity.
The producer uses the canonical authorized creation read, including source access;
invalid mode/source combinations, extra query keys, foreign missions and inactive
scopes fail closed. The consumer independently matches the model against the host
organization and mission, drops the link on context changes, and constructs only
the compiled canonical creation URL. It accepts no server supplied destination.

The existing published surface, query and compatibility action identities remain.
Both application declarations admit the bounded `mode` and `source_dashboard_id`
query keys. The handoff invokes no legacy validation/save action; creation occurs
in the existing authenticated canonical host page with its current authorization,
source version, submission sequence, receipt and uncertainty guards. Existing
routes and their authentication pipelines are unchanged.

Focused verification passed nine producer/compatibility-action tests, six native
canonical owner tests, 22 creation Vue tests and 19 remote transport tests. Actual
Phoenix models mount through the feature consumer for every mode. Frontend checks
passed for all 20 projects; publication and Phoenix assets both built. The import
ownership audit covers 714 cross-package imports in 20 packages with zero issues.

Authenticated Chrome 152 exercised 12 scenarios from the published entry through
blank, clone and import creation, editor navigation and reload. Native assertions
verified all three fresh persisted identities, exact scoped ownership and copied
placements, with no source mutation or extra document. Invalid import JSON leaves
the draft editable for correction. Desktop and 390-pixel mobile evidence preserves
production styling. There were no page errors or renderer exceptions; the one
console 404 was identified as the fixture endpoint's `/favicon.ico`. This closes
the earlier authenticated creation evidence gap. Full frontend verification passed;
the combined root `mix precommit` verification passed. The full ADR-024 migration goal remains
active pending the remaining ownership and workflow completeness review.

Creation destination combined verification passed 42 plane tests and 3,948 workspace
tests (333 foundation, 2,575 domain, 904 web and 136 simulator). Architecture checks
cover 1,456 production sources and 6,177 dependencies with zero findings. The full
frontend suite passed 1,406 tests, including 65 Chrome component tests. All 5,652
frozen files matched exactly; all 13 changed files belong to this cohort. Only
this ADR status and closure prose changed after the gate. The full migration goal
remains active; a separate review is investigating the historical published
dashboard directory's preference and filter behavior.

### Published dashboard directory recovery (verified)

The authenticated published directory displayed a persisted personal star as false;
search returned an HTTP 200 action receipt but replaced the page with a cross-surface
result error. The historical producer ignored query filters, omitted user preferences
and paging, and maintained a second presentation mapping. The canonical directory
already owned scoped preferences, lifecycle filters, paging and guarded effects.

The published entry now delegates to the directory feature's public
`DirectoryDestination`. Phoenix uses the canonical authorized read and emits a
versioned organization/mission context plus normalized filters. The consumer matches
that context against the independently supplied host identity, validates filter
values and bounds, and builds the compiled canonical directory URL. Context changes
remove stale destinations. The old duplicate presentation producer was removed.
Both application declarations admit only the directory's query/lifecycle/tag/sort/page
keys. Durable surface, query and compatibility action identities remain unchanged;
the handoff emits no legacy filter/star/restore actions. Existing canonical routes
retain their authenticated host pipeline and current sequence, source version,
receipt and uncertainty guards.

Verification passed 15 producer/application/compatibility-action tests, six canonical
native owner tests, 25 directory Vue tests and 20 remote transport tests. Actual
Phoenix output mounts through the consumer. All 20 frontend projects typecheck;
publication and Phoenix assets built; 1,425 frontend tests passed, including 65
Chrome component tests. The production import audit covers 714 cross-package imports
in 20 packages with zero issues.

Authenticated Chrome 152 passed 13 scenarios using 54 persisted dashboards and two
users. It verified preserved filters and page numbers from publication into the
canonical owner, personal star isolation, unstar persistence after reload, empty
search state, bounded paging, archived results and restored active rows after reload.
Native assertions verified persisted preference and lifecycle changes, no preference
for the second user and no extra documents. Desktop and 390-pixel mobile screenshots
preserve production styling. No page errors or application failures occurred; the
fixture endpoint's favicon was the only console 404. The combined root
`mix precommit` gate passed. The full ADR-024 migration goal remains active
pending the remaining ownership and workflow completeness review.

Directory destination combined verification passed 42 plane tests and 3,952 workspace
tests (333 foundation, 2,579 domain, 904 web and 136 simulator). Architecture checks
cover 1,456 production sources and 6,178 dependencies with zero findings. The full
frontend suite passed 1,425 tests, including 65 Chrome component tests. All 5,657
frozen files matched exactly; all 13 changed files belong to this cohort. Only
this ADR status and closure prose changed after the gate. The full migration goal
remains active; a separate review is checking the remaining public handoff
contracts against the ADR requirements.

### Published dashboard identity preservation (verified)

An authenticated diagnostic confirmed that a persisted 149-character dashboard ID
loaded in canonical settings and returned an approved published query, but the
settings compatibility entry rendered no destination. Settings and shared-view
handoffs imposed a 120-character limit despite the canonical consumers' larger
identity range. Both handoffs now admit the same existing identity character set
up to 256 characters. Compiled encoded destinations, route placement, authorization,
malformed/path/control rejection and all durable identities remain unchanged.

Feature-local boundary tests cover 120, 121, 149, 256 and 257 characters, both shared
view kinds, mission identity changes and stale destination removal. All 49 focused
Vue tests and 12 native settings/shared-view tests passed. The full frontend suite
passed 1,453 tests, including 65 Chrome component tests; 20-project type checking,
publication, Phoenix assets and the 714-import ownership audit passed.

Authenticated Chrome 152 passed nine scenarios with actual 240-character dashboard,
share and snapshot identities. The approved settings handoff reaches the exact
canonical document and a guarded metadata save survives reload without changing
its identity, scope or placements. Shared views still show published/captured v1
after the saved draft advances to v2. Native assertions verify the stored document
and retained snapshot version; desktop and 390-pixel mobile screenshots preserve
production styling. No page errors or application failures occurred; the fixture
favicon was the only console 404.

These bounds are distinct: component tests cover 256 characters, database string
columns cap persisted identities at 255, and the existing generic application-host
JSON boundary caps scalar strings at 240 bytes. The browser evidence uses persisted
identities within the existing transport bound and a normally generated mission ID;
it does not claim published reachability for every 256-character identity or a
change to the storage/transport contracts. Earlier fixture attempts and their bounds
failures are retained separately. The combined root `mix precommit` gate passed. The full ADR-024 goal remains active pending the broader completion audit.

Identity preservation combined verification passed 42 plane tests and 3,952
workspace tests (333 foundation, 2,579 domain, 904 web and 136 simulator).
Architecture checks cover 1,456 production sources and 6,178 dependencies with
zero findings. All 5,659 frozen files matched exactly; all five changed files
belong to this cohort. Only this ADR status and closure prose changed after the
gate. The full migration goal remains active while the completion audit checks
feature ownership and authenticated workflow evidence.

### Feature test colocation and authenticated workflow audit (verified)

The Ops workspace frame's controller test and direct navigation/context unit tests
now live beside that feature. Their test bodies and assertions are preserved;
ApplicationShell composition and sidebar integration tests remain beside the shell.
All 75 current feature directories now contain feature-local tests. This structural
inventory is evidence of colocation, not a claim that every workflow is complete.

Authenticated Chrome 152 exercised the canonical contact-plan contribution with
persisted domain records: submission and approval receipts, exact reviewed hashes,
version-pinned execution records, 31 manifest-ordered opportunities across two pages,
historical decision disabling, current and historical navigation, ordinary-member
permission limits and 390-pixel layout. Native assertions check the actual stored
approval and execution item. The fixture deliberately has no ready provider route:
it verifies the governed failed execution record and does not claim a successful
external reservation. Historical version history correctly ends at the reviewed
version; the separate current-version link opens the newer review.

That browser audit found a real projection defect: overlap findings without a
message were labelled as unavailable provider searches. The projection now gives
overlap and minimum-separation findings accurate labels, keeps the provider-search
label for its own code and uses neutral text for unknown codes. Explicit domain
messages, finding codes, order, identities and decision contracts remain intact.
Producer tests cover known and unknown codes and preservation of an explicit message.
The authenticated browser check also verifies actual overlap evidence on the page.

A separate authenticated Data Sources run passed ten scenarios covering configuration
validation, registration with durable event identities, canonical settings navigation,
disable/enable across reloads, a binding move to the exact reviewed destination,
persisted binding version, ordinary-member read access and 390-pixel layout. Native
assertions verify exactly three source events and one binding-version increment.
These are real Phoenix sessions and persisted producer/action workflows; backend
provisioning and external telemetry probes are outside this browser evidence.
Both workflow runs preserve production styling and report no application/page errors;
the fixture favicon is the only console 404. Earlier fixture-only browser evidence
for these workflows is supplemented by these authenticated checks.

Five focused frame/shell tests, the full frontend suite (1,453 passed, including 65
Chrome component tests), 20-project type checking and five plan producer tests passed.
Frontend production source is byte-identical to the preceding built checkpoint;
only test placement changed in the frontend. Root formatting passed. The combined
root `mix precommit` gate passed. The full ADR-024 goal remains active while
the requirement-by-requirement completion audit continues.

The combined gate passed 42 plane tests and 3,953 workspace tests (333 foundation,
2,580 domain, 904 web and 136 simulator). Architecture checks cover 1,456 production
sources and 6,178 dependencies with zero findings. All 5,660 frozen files matched
exactly; all seven changed paths belong to this cohort. Attempt one stopped at a
Credo alias-style finding in the new test; the alias was corrected and attempt two
passed. Only this ADR status, closure prose and a correction of the preceding directory
cohort dependency count (6,178, as recorded by its gate) changed after the passing gate.
The authenticated plan run passed 13 scenarios including the corrected overlap
labels; the source run passed ten. The full migration goal remains active pending
completion of the owner-by-owner evidence reconciliation.

### Telemetry Decom promotion prerequisites (verified)

Authenticated publication checks verified catalog revision selection, exact packet
and source endpoint bindings, immutable packet-field inspection and persisted
reloads. Extending that workflow exposed an activation gap: an imported but
unapproved mission model displayed a ready preflight and an enabled request, then
Phoenix rejected promotion with a generic bridge error.

The feature's preflight now inspects the enabled mission configuration basis, as
the actual promotion path does. All enabled configurations must resolve to one
approved mission model revision. A missing model, an unapproved revision or mixed
model revisions produces a blocking check; when every configuration is disabled,
the triggering configuration supplies the model needed for the removal request.
The normal promotion comparison and activation approval remain authoritative.

The bridge now returns a stable `preflight_blocked` problem, and the browser maps
that code to fixed guidance to resolve the checks, refresh and review again.
Raw server error text remains hidden. Feature action adapters also retain typed
rejections for unapproved or mixed mission-model revisions. No route placement,
authorization grant, durable identity or contribution DTO version changes.

Persisted regressions verify blocked-before-approval and ready-after-approval
behavior, another enabled spacecraft with a different model, exclusion of a
disabled configuration, and an explicitly submitted request rejected without
creating an activation. The browser transport test verifies the useful message,
one dispatch and no session recovery or raw-message exposure. All 29 focused
domain/producer tests, 11 bridge controller tests and 14 feature Vue tests passed.

The authenticated browser run includes an unapproved mission that displays the
prerequisite and disables the request, plus a qualified mission that saves its
revision and packet input, reaches a pending approval and preserves that request
across reload. Native assertions verify exact stored packet/revision/endpoint
identities and the review basis; packet bindings remain unapplied while approval
is pending. Desktop and 390-pixel screenshots preserve production styling.
The final authenticated browser run passed all 13 scenarios with the rebuilt
publication and Phoenix assets. Full frontend checks passed across 20 projects;
1,454 component tests passed, including 65 Chrome tests, alongside the Node tool
and transport suites. The new bridge regression initially omitted the existing
reference ID suffix; its assertion now preserves that behavior. The fixed host
message changed the publication digest: two pinned host builds produced identical
bytes, the generated federation expressions were inspected, and the explicit
accepted digest was updated without relaxing any output validator rule. The final
publication build passed. The combined root `mix precommit` gate passed.
The broader ADR-024 goal remains active.

The combined gate passed 42 plane tests and 3,955 workspace tests (333 foundation,
2,581 domain, 905 web and 136 simulator). Architecture checks cover 1,456 production
sources and 6,180 dependencies with zero findings. All 5,660 frozen files matched
exactly; all ten changed paths belong to this cohort. Attempt one stopped at an
alias-ordering finding in the updated producer test; that ordering was corrected
and attempt two passed. Only this ADR status and closure prose changed after the
passing gate. The full ownership migration goal remains active while the remaining
workflow evidence is reconciled.

### Catalog native upload control recovery (verified)

An authenticated browser upload exposed a mismatch hidden by the constructed
component fixture: Phoenix renders its native file input with the generated upload
reference as its ID, while the Vue bridge searched for a fixed custom ID. The
result was an upload-connection error before either field validation or file
selection reached Phoenix, leaving the visible submit control disabled.

The feature now finds the single file control named `catalog_artifact` inside its
path- and token-bound native form and verifies that its ID equals its nonempty
Phoenix upload reference. Stale or ambiguous controls are rejected. The ineffective
custom ID override is removed; Phoenix retains ownership of the upload input,
DOM reconciliation, upload transport and file consumption. Routes, authorization,
durable identities, original-byte storage and import execution are unchanged.
The component fixture now uses the real native control shape, and a persisted
LiveView regression checks the rendered ID/reference relationship.

Seven focused component tests and ten native Catalog upload/page tests passed.
The initial native test invocation mistakenly enabled the browser-specific LiveVue
diff mode; it was rerun with that flag cleared, matching the root test environment.
Full frontend checks across 20 projects, 1,455 component tests including 65 Chrome
tests, Node tool/transport suites, publication and Phoenix assets builds passed.
The public-import audit covers 20 packages and 714 cross-package imports with no
invalid or unknown imports.

The authenticated browser run passed 13 scenarios across new database upload,
second-revision upload and completed-revision/artifact navigation, including
reloads and a 390-pixel viewport. The native harness executes each enqueued import
through Catalog's public executor between browser stages and asserts exact source
bytes, labels, notes, database identity and preservation of the first immutable
revision. This proves upload-to-import-to-read behavior; it does not claim that a
background production worker was scheduled. The combined root `mix precommit`
gate passed. The full ADR-024 migration goal remains active.

Catalog upload combined verification passed 42 plane tests and 3,955 workspace
tests (333 foundation, 2,581 domain, 905 web and 136 simulator). Architecture
checks cover 1,456 production sources and 6,180 dependencies with zero findings.
All 5,660 frozen source files matched exactly; all five changed paths belong to
this cohort. Only this ADR status and closure prose changed after the passing
gate. The full ownership migration goal remains active.

### Mission provider archive navigation recovery (verified)

An authenticated published browser run confirmed that Archive persisted provider
version two but remained on the detail URL. A same-provider host snapshot arrived
before the receipt and the detail model watcher reset the operation generation,
preventing its confirmed navigation. The detail now preserves pending and locked
operations across same-provider snapshots, rejects older snapshots, and resets
for a changed provider identity. A component regression reproduced the missing
navigation before the fix; fourteen focused component tests and five native
provider-page tests passed afterward. Phoenix authorization, ordered action
sequences, exact observed provider versions and existing routes are unchanged.

Additional authenticated Communications checks passed ten provider-account
scenarios and nine transport, station and routing scenarios, with native persisted
identity and version assertions. Credential backend management and validation were
disabled using existing test options. Transport creation verifies definitions,
not a running TCP endpoint. Full frontend, published browser and root verification
for the archive repair passed. The full ownership goal remains active.

Archive repair combined verification passed 42 plane tests and 3,955 workspace
tests (333 foundation, 2,581 domain, 905 web and 136 simulator), plus 1,456
frontend component tests, type checks, publication and Phoenix assets. The
authenticated provider browser passed six scenarios with persisted active
version one and archived version two pinned to the original mission grant.
Architecture checked 1,456 production sources and 6,180 dependencies with zero
findings. All 5,660 frozen source files matched; the three changed paths belong
to this cohort. Only this ADR status and closure prose changed after the passing
gate. External provider calls are not claimed. The full ownership goal is active.

### Contact schedule host context recovery (verified)

The authenticated contact-scheduling browser reached a populated ready producer
snapshot but the host rejected it. The schedule producer included `resourceId:
null` even though this route has no resource subject; the host correctly requires
an absent resource key in that case. The producer now omits that key for schedule
pages and retains the concrete identity for contact records and reservation
review. The native scheduling test asserts the exact organization/mission-only
context. The host admission rules, route scopes, authorization, reservation
identities and provider-effect boundaries remain unchanged.

Nine focused native tests and the authenticated browser workflow passed. Provider
responses in this browser test use the existing Req test adapter; external network
booking success is not claimed. The full ownership migration remains active.

The contact browser passed seven scenarios including authenticated ready-route
search, booking, explicit cancellation review, reload and mobile bounds. Native
assertions confirm one booking call, one cancellation call, and the same persisted
reservation canceled at provider revision two. The fleet workflow browser passed
ten scenarios: preview-bound creation, explicit continuation and evidence
refresh, then a distinct repair successor pinned to the reviewed source run.
Native assertions retain the approved policy version and unchanged source run.
Fleet continuation records a partial finished outcome in this fixture; successful
external provider planning or booking is not inferred from it. The combined root
verification gate for the contact context repair passed.

Contact context combined verification passed 42 plane tests and 3,955 workspace
tests (333 foundation, 2,581 domain, 905 web and 136 simulator). Architecture
checked 1,456 production sources and 6,180 dependencies with zero findings.
All 5,660 frozen source files matched; the three changed paths belong to this
cohort. Only this ADR status and closure prose changed after the passing gate.
The frontend is unchanged from the preceding verified 1,456-test publication.
The full ownership migration remains active.
