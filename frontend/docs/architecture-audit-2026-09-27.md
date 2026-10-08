# Frontend architecture audit — 2026-09-27

For the current route and freshness inventory and prioritized backlog, see the
[October architecture inventory](frontend-inventory-2026-10-06.md). This document retains
the September baseline and reproduction results.

Implementation follow-up: [contact scheduling](contact-scheduling-architecture.md) now provides
the first shared domain service and durable operation protocol. The host nested-patch watcher
also has a correction and regression coverage. The findings and verification below describe
the original audit baseline; navigation activation and other feature migrations remain open.

The ownership model is a sound foundation, but the migration has unresolved lifecycle
contracts. The highest-priority work is reconciling LiveVue patches with committed Vue
state and keeping server context aligned with cancelled navigation. Removing broad busy
flags helps interaction, but does not resolve these ownership problems by itself.

Baseline: `eb5f2c18` plus the existing working-tree changes. This audit did not change
application code or the in-progress commanding work. It examined the host, SDK, LiveVue
integration, federation lifecycle, and representative commanding, planning, data operations,
settings, and dashboard workflows. This is a sampled architecture review, not an exhaustive
review of every frontend file.

P1 means prioritize before relying on the affected lifecycle in production. P2 means
schedule a focused correction. Findings distinguish executed reproductions from static
design analysis.

**1. P1 — LiveVue patches and committed host snapshots have incompatible update semantics.**

[BrowserHost.vue](../apps/host/src/shell/BrowserHost.vue), lines 228–239, watches
`() => props.snapshot` without observing nested changes. Its committed snapshot comes from
[readHostSnapshot](../apps/host/src/shell/host-snapshot.ts), whose readers reconstruct core
context fields and page envelopes. After navigation, the committed snapshot also comes from
a separate event reply. It is not the object LiveVue subsequently patches.

The installed LiveVue 1.2.2 hook applies JSON patches to reactive props in place. Vue getter
watchers ordinarily react to replacement of the returned object. This matches both the
installed dependency and the documented [Vue watcher semantics](https://vuejs.org/guide/essentials/watchers#deep-watchers)
and [LiveVue diff behavior](https://live-vue.hexdocs.pm/component_reference.html).

Three mounted reproductions failed: changing the organization's name in place left the old
shell name; replacing nested page data left the old observation time; and changing a leaf
after navigation through a context reply left the displayed page stale. Existing tests
mostly replace whole snapshots with `setProps`, which exercises a different contract.

Establish one host snapshot ingestion boundary. It should consume complete patch batches
and replies, validate route/visit identity, and publish an explicitly versioned snapshot to
features. Keep editable drafts separate. Test actual nested patches and reply/patch ordering;
adding independent deep watchers throughout the feature tree would spread the problem.

**2. P1 — Cancelled navigation can leave the server and browser on different pages.**

[BrowserHost.vue](../apps/host/src/shell/BrowserHost.vue), lines 188–221, requests context
before Vue Router commits navigation, then ignores failed navigation in `afterEach`.
[HostPageLive.prepare_context](../../apps/cadence_web/lib/cadence_web/live/host_page_live.ex),
starting at line 1211, already changes `host_path`, resource context, page sessions, and
subscriptions while preparing that response.

Reproduction: display A, request B, click A again before B replies, then deliver B's reply.
Vue keeps A and sends no request to restore A's server context. The mounted test confirmed
that behavior; the server-side consequence follows from the inspected handler. Page actions
check the active server path/token, so the remaining page can have invalid capabilities or
lose its live subscription. A response arriving after the host's ten-second deadline has
the same underlying risk. This is a consistency problem; the server's authorization checks
should remain intact.

Define a navigation activation contract: either separate preparation from activation or
explicitly reconcile the last committed route after cancellation and late responses.
Include the visit identity in the protocol. Test A→B→A, timeout followed by a late reply,
and an action on A after cancellation against the real Phoenix session.

**3. P2 — Navigation has two completion contracts, and the weaker one can strand controls.**

[OpsPageNavigationPort](../packages/plugin-sdk/src/ops-page-contribution.ts), lines 17–27,
returns `void`, while a separate port reports completed/cancelled/unchanged/failed.
[CommandMonitor.vue](../modules/commanding/src/features/mission-commands/CommandMonitor.vue),
lines 25–52, sets `pending` before navigation and clears it only when model/port props change.
[CommandHistory.vue](../modules/commanding/src/features/command-history/CommandHistory.vue)
uses the same pattern.

A mounted host reproduction confirmed that submitting unchanged command filters leaves
Apply and Refresh disabled: Vue Router reports duplicate navigation, but the feature never
receives completion and no replacement props arrive. The affected monitor logic is also in
HEAD; this is not introduced by the current target-label/busy-state work.

Make settled navigation the normal feature contract. Await the result, release local state
in `finally`, and retain inputs after failed/cancelled navigation. The existing
[playlist playback](../modules/dashboards-and-exploration/src/features/playlists/usePlaylistPlayback.ts)
already demonstrates the intended outcome model.

**4. P2 — The shared federation action lifecycle treats durable effects as disposable reads.**

[createFederatedActionLifecycle](../packages/plugin-sdk/src/bridge.ts), lines 218–265,
uses one generation across all action names. A later invocation discards an earlier action's
completion even when it changed durable state. This is appropriate for superseded search
results, but not for accounting for submitted writes.

An SDK reproduction started `save`, started `validate`, completed validation, and then
completed the save. Only validation reached `onCompleted`; the save receipt was discarded
and its completion caused no refresh. The existing SDK test explicitly expects earlier
action completions to be ignored. The federation
[mission/catalog wrapper](../apps/mission-catalog/src/MissionCatalogApplication.vue) routes
validation and save through this same lifecycle and does not forward its `actionPending`
state to the child form. This finding concerns the supported federation/compatibility path;
the ordinary host mission-creation wrapper has a different lifecycle.

Separate read supersession from effect accounting. Capture immutable inputs and an operation
identity for each effect; serialize conflicting writes or track their independent outcomes.
Retiring a page may prevent UI updates, but a newer validation must not erase knowledge of
a completed write. Keep refresh failure distinct from mutation failure.

**5. P2 — Some operation recovery is scoped to a mounted page rather than the operation.**

This is a static finding with a concrete lifecycle gap. In
[OpsContactSchedulingPage](../../apps/cadence_web/lib/cadence_web/ops_contact_scheduling_page.ex),
lines 24–51, a new visit starts at sequence zero with no operation/recovery; leaving clears
the session. Lines 99–120 retain the action receipt only in socket assigns after execution.
[useContactWorkflow](../modules/planning-and-contacts/src/features/contact-scheduling/contact-workflow-state.ts),
lines 168–188, asks the operator to keep an unconfirmed review open, but releases its leave
guard once the request settles, even when the outcome remains unresolved. A new LiveView
process also loses that page-session correlation.

Underlying reservation records and domain idempotency still exist. The finding is loss of
the exact attempted operation, receipt correlation, and unresolved-state protection—not
proof that a duplicate external booking occurs. The
[data-source page](../../apps/cadence_web/lib/cadence_web/ops_data_sources_page.ex) has a
similar socket-local operation record and warrants the same recovery review.

Make recovery lifetime follow the durable operation. Persist a bounded record keyed by
actor, scope, and operation identity before the effect; reconstruct its outcome after
navigation/reconnect. The existing
[fleet-policy recovery](../../apps/cadence_web/lib/cadence_web/ops_fleet_policy_recovery.ex)
is a useful local precedent. Verify a lost reply followed by navigation/re-entry and a new
LiveView process. Navigation guards alone cannot provide this guarantee.

**6. P2 — Feature boundaries are clearer than the shared orchestration contracts.**

[BrowserHost.vue](../apps/host/src/shell/BrowserHost.vue) contains route commitment,
transport promises, navigation guards, draft stores, subscriptions, and domain-specific
mutation adapters. [HostPageLive](../../apps/cadence_web/lib/cadence_web/live/host_page_live.ex)
contains a corresponding domain dispatch and preparation chain. Meanwhile,
[OpsPagePort](../packages/plugin-sdk/src/ops-page-contribution.ts) exposes
`execute(string, Record<string, unknown>): Promise<unknown>` directly to workflows such as
[data sources](../modules/data-operations/src/features/data-sources/native-state.ts).

This is a maintainability finding rather than a claim that large files are inherently wrong.
Lifecycle policy is repeatedly implemented at these boundaries: navigation completion,
sequence advancement, timeout classification, refresh ownership, and unresolved outcomes.
The federation path uses different policies again. The concrete inconsistencies above are
the cost of that duplication.

Keep the wire protocol generic inside a small adapter. Expose typed domain operations and
decoded outcomes to features, following the existing
[policy action port](../modules/planning-and-contacts/src/features/fleet-planning/policy-action-port.ts).
Move domain adapters out of the shell and use explicit server page registrations for
preparation/read/action dispatch. Preserve the existing authorization and envelope readers.
Use shared lifecycle contracts rather than a universal workflow controller.

**Ownership rules to keep and make explicit**

| State                                  | Owner                                    | Required behavior                                                            |
| -------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| Authorization and durable domain state | Phoenix/domain contexts                  | Reauthorize every operation and enforce concurrency/idempotency server-side. |
| Active page visit                      | Host plus server activation protocol     | One agreed identity after success, cancellation, timeout, and reconnect.     |
| Server snapshot                        | Host/feature read boundary               | One accepted revision; older reads cannot overwrite newer evidence.          |
| Editable draft                         | Feature or explicitly scoped draft store | Refresh retains user edits; replacement/discard is deliberate.               |
| Search/preview request                 | Feature read lifecycle                   | Supersede obsolete results and clean up with the owner.                      |
| Submitted effect                       | Durable operation protocol               | Keep its identity and outcome independently of the mounted component.        |
| Loading/disabled presentation          | Derived UI state                         | Disable only interactions that conflict with the active operation.           |

Phoenix still runs a stateful LiveView transport under LiveVue. Changing the template owner
to Vue does not remove that server lifecycle. The host's synchronous event handlers also
share one LiveView mailbox; slow domain work can delay navigation and live updates. Treat
that as a latency risk to measure, rather than assuming removal of a frontend lock makes
the whole path concurrent.

The existing router placement is appropriate: ordinary pages are in the `/` scope with
`[:browser, :require_authenticated_scope]`, under the `:application` LiveView session.
That retains session authentication for entry and server-owned policy for context requests.
No route changes are proposed by this audit.

Other strengths worth preserving are feature-owned runtime decoders, captured capability
invalidation, lazy page boundaries, release admission, the bounded HTTP bridge, and independent
frontend/producer/browser CI gates. They provide useful seams for incremental corrections.

**Suggested implementation order**

1. Fix host patch ingestion and cancelled-navigation reconciliation together, with real
   LiveVue/Phoenix lifecycle coverage.
2. Standardize settled navigation and separate read supersession from write outcomes across
   both native and federated paths.
3. Inventory effect recovery lifetimes and extend the existing durable recovery pattern to
   the workflows that need it.
4. Extract domain adapters and strengthen feature ports while making those corrections.
   Keep domain validation local and retain the existing package boundaries.

The reusable acceptance matrix should cover nested diffs, unchanged routes, cancelled
navigation, late replies, failed reads after successful writes, unmount during requests,
and reconnect after an unresolved effect. Run it through both supported transport paths.

**Verification and limits**

- Existing host tests passed: 199 tests across `BrowserHost`, page admission, page boundaries,
  the HTTP bridge, and remote loading.
- Existing SDK bridge tests passed: 4 tests. They also ran in the copied diagnostic suite;
  those duplicate executions are not counted again.
- Six additional diagnostic assertions failed as described above: three patch scenarios,
  one cancelled-navigation scenario, one unchanged-navigation scenario, and one overlapping
  action scenario. These are mounted Vue/SDK reproductions, not live browser/server runs.
- The diagnostic files were removed from the workspace after execution. Copies and logs
  remain locally at `/tmp/cadence-frontend-architecture-audit/` for reproduction.
- The document's formatting and relative links were checked. No application source changes
  remain from this audit. Full frontend acceptance, publication/browser builds, and
  `mix precommit` were not run for this documentation-only change, following
  [frontend validation instructions](../AGENTS.md).

Commands used for the existing checks, from `frontend/`:

```sh
corepack pnpm --filter @cadence/plugin-host exec vp test --run src/shell/BrowserHost.test.ts src/shell/module-pages/page-admission.test.ts src/shell/module-pages/use-page-boundary.test.ts src/http-host-bridge.test.ts src/remote-loader.test.ts
corepack pnpm --filter @cadence/plugin-sdk exec vp test --run src/bridge.test.ts src/bridge.architecture-audit.test.ts
```

The second command included the temporary regression probe; its overall exit code was one
because that diagnostic assertion failed. The original bridge test file passed.
