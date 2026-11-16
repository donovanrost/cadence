# Parity audit: legacy ops pages before §11c(C) (fe-ops, 11-16)

**Scope (lead):** the legacy ops pages fe-setup deletes in §11c(C): the ops landing and its frame, planning
(directory, new, run) and plans/:id, contacts (schedule, records, reservation review), contact-workspace, alarms,
timeline, and all of commands. For each page, every **action** and every piece of **information** it offers, and
whether the console has it. **Read-only:** code on both sides, nothing run. Legacy code: `frontend/modules/
{planning-and-contacts,commanding,limits-and-alarming}` and `frontend/apps/host/src/ops-workspace`; console:
`frontend/apps/console/src/features`. Each console "Yes" was traced to real code; fe-ops spot-checked the sharpest
claims (single-day drafting `scheduling/api.ts:480`, `priority: 3` / `expires_at: null` in `commands/compose/
draft.ts:103-104`, decoded-but-unrendered fields, the Alarms `?state=` drop, the 200/500 caps).

**Gaps go to lead before fe-setup builds (C).** The triage below is fe-ops' proposal; the per-page tables are the
evidence.

## Triage

### A. Operator capabilities the deletion would lose (decide before (C))
| # | Gap | Legacy | Console today | Proposal |
| --- | --- | --- | --- | --- |
| A1 | **Command priority** can't be set | authoring, workspace, stage editor | Compose sends `priority: 3` | build (Compose field + request field), or decide priority is server policy |
| A2 | **Command expiry** can't be set | same | `expires_at: null` | build (Compose "Expires at"), or decide |
| A3 | **Release-attempt history** of a request (attempt id, state, contact, path, binding, attempted/released time) | requests/:id/history | Investigate U4 shows released_at for 24 h only | build a request "Attempts" section |
| A4 | **Matched verifier evidence** (telemetry packet/evidence ids, quality, raw vs engineering; transport evidence) and verifier deadline/matched time/failure code | requests/:id/history | plot + "last read X"; `verify_by`, `occurred_at` decoded, never shown | build into Uplink & verify |
| A5 | **Commands list search and filters** (text, target, per state incl. failed / indeterminate / in flight) and paging past 1,000 | /ops/commands | 4 tabs, 1,000-group cap | build search + a state filter |
| A6 | **Alarms filters**: severity, spacecraft / mission scope; a mission-wide view of nominal and info conditions | /ops/alarms | lifecycle tabs, By-point click | build severity + spacecraft filters; decide on nominal/info |
| A7 | **Alarm proof links**: producing limit definition id·version ("Inspect producing vN") and "Open exact sample" | /ops/alarms rows | none (definition id/version decoded in investigate, unused) | build both (Technical details + links) |
| A8 | **Timeline event detail**: select an event, its identity/status/source/subject/8 references, copy permalink | /ops/timeline | rows link to their subject only | build a detail panel + `?event=` |
| A9 | **Timeline filters and paging**: severity, kind text; older events past 500 (and a truncation notice: `truncated` is decoded, not shown) | /ops/timeline | coarse kind toggles, window-only | build severity filter + truncation notice; decide on paging |
| A10 | **Plan history**: open an older plan version, version list, full decision history | plans/:id | latest round only | build |
| A11 | **Reservation links and audit**: reservation → plan, requirement, scheduled contact; Requested / Provider-confirmed / Accepted values; reservation audit list | contacts/:reservation_id (L14) | provider change block, partial lines | build into the pass drawer (L14 is already a known gap) |
| A12 | **Contact ledgers beyond the Live window** (scheduled, realized, reservations, paged history) | /ops/contacts | Live 30 min back–6 h ahead; Plan by day; Investigate ±24 h; Review | decide: a Contacts "History" view or accept the split |
| A13 | **Contact record**: scheduled/realized paths and bindings, source endpoints, intents, clock mode, schedule revisions | contacts/records/:id | none | build into the pass drawer's Technical details (needs a console read) |
| A14 | **Planning horizon**: plan over a chosen multi-day window, "Include recurring demand", review pinned inputs before creating, choose the repair window | planning/new, runs/:id | one UTC day; repair window computed | **decide** (day-based planning was a design choice) |
| A15 | **Approve without booking**, and general submission/approval reasons | plans/:id | approve always books; reasons per gap only | **decide** |
| A16 | **Book a pass**: choose the route (provider/transport/service), search past 48 h; offer cost, antenna, availability, synthetic (decoded in `singleBookings.ts:40-47`, not rendered) | /ops/contacts | filters by direction/station | render the decoded fields; decide on route choice + range |
| A17 | **Fleet run directory** (runs, lifecycle filter, failed/partial runs, optimizer decisions, resource pressure, automation history) | /ops/planning, runs/:id | current day's run only | decide |

### B. Evidence and identity fields (mostly Technical details)
Ids, versions, fingerprints and hashes shown as evidence across the legacy pages: policy id/sha, input/run sha, plan
id/content sha, opportunity sha, proposal hash, request id, command id, model revision id, approval id, approved
content sha, queue entry id/lane/queued_by/enqueued_at, provider reference and revision, provider/transport
versions, limit set name, generated/receipt times, server-resolved arguments, significance, subsystem, group,
release policy hint, APID/service/opcode, event raw kind/category, "observed at" stamps. **Proposal:** one batch per
screen into its existing Technical details, where the data is already decoded; anything not on the wire listed for
api.

### C. Gone by design (lead to confirm)
- **Command stages** (directory, create, workbench, shared stages, persisted draft items, batch preview → N formal
  requests). Command groups replace them; Compose keeps one private autosaved draft per user per mission.
- **The separate queue step** (`requests/:id/queue`, "Review for queueing"): GO / Arm queues directly.
- **"I reviewed…" checkboxes** before create/decide/queue: the console gates on checks and ApDecision instead.
- **The ops landing's grouped cards and the frame's context rail**: Now is the landing; rail counts and Now tiles
  carry the posture. Open sub-items: an always-visible posture in the top bar (`App.vue:50-51` slot is empty), a
  latest-alarm-transition time (`latest_transition_at` decoded, unused), in-flight/failed command counts, a "Following"
  command, a positive "Connected" indicator.
- Workspace layout (resizable panes, shelf), rail collapse toggle, Starred/Recent dashboards in the rail (they live in
  the dashboards directory).

### D. Bugs found on the way (fe-ops fixes, own screens)
1. Now's grouped alarm rows link to `ops.alarms?state=critical|caution` (`now/queue.ts:123`), but Alarms reads only
   `?tab` and `?point`: the filter is silently dropped.
2. Timeline decodes `truncated` (`timeline/api.ts:82`) but never says when the 500-event window was cut.
3. Alarms fetches at most 200 episodes (`alarms/episodes.ts:86`) with no notice when there are more.
4. The "expired" end reason of a command reads "Canceled" (`commands/groups/words.ts:49-65`).

## Gap list for the director (lead 11-16)
Rule (director): a gap that removes an operator capability defaults to **build**; **accept-drop** only for what ux
confirms is a by-design omission; dropping a capability is the **user's call**. Sizes: S ≤ half a day, M about a
day, L 2-3 days (console side; api's own size is theirs). "Frontend" = the data is already on the wire.

| Gap | Tier | Size | Data | Mark |
| --- | --- | --- | --- | --- |
| A1 command **priority**: set in Compose, shown on the request | 1 safety | S | frontend (submit takes `priority`; the request read returns it, `show.ts:229`); api to confirm the allowed range | build |
| A2 command **expiry**: set in Compose, shown on the request | 1 safety | S | frontend (submit takes `expires_at`; read returns it, `show.ts:228`) | build |
| A3 **release-attempt history** per request | 1 | M | api: per member/target attempts {attempt id, state, uncertain, contact id+label, path, transport binding, encoded size, attempted_at, released_at} | build |
| A4a verifier **deadline, matched time** | 1 | S | frontend (`verify_by`, `occurred_at` decoded, `show.ts:73-74`) | build |
| A4b verifier **failure code, severity, id** | 1 | S | api: on the series/verifier entry | build |
| A4c **matched evidence**: telemetry (packet id, evidence id, quality, raw vs engineering, received/generated) and transport (action, signal phase, event/recorded times) | 1 | M | api: matched record per verifier | build |
| A7a alarm's **producing limit definition id·vN** | 1 | S | frontend in Investigate (decoded `investigate/api.ts:56-57`); api: add to the alarms list episode | build |
| A7b **"Inspect producing vN"** link | 1 | S | the limits app (owner) must accept a definition-version deep link | build |
| A7c **"Open exact sample"** | 1 | M | api: the triggering sample id/time on the episode; console: Telemetry deep link at that time | build |
| A5a commands **state filter** (failed, indeterminate, in flight, release pending…) | 2 | S | frontend (`?state=` exists, `groups/api.ts:302`) | build |
| A5b commands **text search + target filter** | 2 | M | api: `q=`, `target=` | build |
| A5c commands **paging** past 1,000 | 2 | M | api: cursor | build |
| A6a alarms **spacecraft filter** | 2 | S | frontend (`spacecraft_id=` exists, `alarms/episodes.ts:87`) | build |
| A6b alarms **severity filter** | 2 | S | frontend over the read (≤200), or api `severity=` | build |
| A6c mission-wide **nominal / info conditions** | 2 | M | api: a current limit-state read (per point, mission-wide) | **user (11-16): build after #92 phase 3; legacy /ops/alarms stays until then** |
| A6d alarms **paging** past 200 (+ the notice, bug D3) | 2 | M | api: cursor | build |
| A8a Timeline **event detail** panel | 2 | M | frontend for id, occurred, subject, 4 refs; api: status, source record, source endpoint, realized contact, path, capability instance, activation, correlation | build |
| A8b Timeline **permalink** `?event=` | 2 | S | api: read one event by id | build |
| A9a Timeline **severity filter** | 2 | S | frontend over the window, or api `severity=` | build |
| A9b Timeline **raw-kind filter** | 2 | S | api `raw_kind=` | build |
| A9c Timeline **truncation notice** (bug D2) | 2 | S | frontend (`truncated` decoded) | build (in D now) |
| A9d Timeline **older-events paging** | 2 | M | api: cursor | build |
| A10 plan **version + decision history**, open an older version | 3 | M | api: versions list, read by version, decisions list | build |
| A12 contact **ledgers beyond the Live window** (a Contacts History view) | 3 | M | mostly frontend (passes read by window; review read); api if paging | build |
| A16a Book a pass offer **cost, antenna, availability, synthetic** | 3 | S | frontend (decoded `singleBookings.ts:40-47`) | build |
| A16b Book a pass **route choice + search past 48 h** | 3 | M | api: search by route; the range limit | **user (11-16): build: route picker + start/end range, server-set max reach** |
| A11, A13 reservation links/audit; contact record paths, bindings, endpoints, intents | with L14 | M | api: a contact-record read | with L14 (not in (C)) |
| A14 horizon, recurring toggle, input review, repair window; A15 approve without booking; A17 run directory | design | — | — | ux + director (user call if dropped); **A14 held with the user (11-16)** |
| C1-C5 stages, queue step, review checkboxes, context rail, workspace layout | — | — | — | accept-drop only if ux confirms (asked 11-16) |
| B evidence/identity fields | fold-in | S each | mostly frontend where decoded; api for resolved arguments, approval id + content sha, queue entry details, provider reference + revision, plan/opportunity hashes | build, per screen as touched |

**Order (fe-ops):** D now → A1, A2 (frontend, safety) → A4a, A7a, A5a, A6a, A6b, A9a, A16a (frontend, small) →
the api-backed ones as api lands them (A3, A4b/c, A7b/c, A5b/c, A6c/d, A8, A9b/d, A10) → A12.

## Per-page evidence

Path prefixes: **C** = `frontend/apps/console/src/features`; legacy files named per page. "Partial" says what's
missing. Legacy Refresh buttons map to the console's live invalidation throughout (not repeated).

### /ops (landing) and the ops frame (`apps/host/src/ops-workspace/features/{landing,frame,module-pages}`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| "Choose a workspace…" + grouped cards Observe / Act / Plan / System | info | Partial: Now is the landing (`shell/ConsoleHome.vue`), flat Ops rail + mode switch | no grouping/descriptions |
| Links Dashboards, Explore, Alarms, Timeline, Commands, Contacts | action | Yes: rail / Telemetry tabs | |
| Links Approvals, Planning, Requirements, Data sources, Data operations | action | Partial: Setup mode routes; Data operations has no page (L16) | |
| Mission back-link with slug | action | Partial: ScopeSwitcher (names, no slug) | |
| Posture "N Critical / N Warning / Nominal" in the top bar | info | Partial: rail tint, Now headline; top-bar slot empty | |
| UTC clock; account menu | info/action | Yes | |
| Connected / connection lost | info | Partial: offline tag only (`shell/LinkStatus.vue`) | no positive state |
| Nav rail collapse toggle; group labels | action/info | No | |
| Starred / Recent dashboards, New dashboard in the rail | action | Partial: in the dashboards directory | |
| Context rail: alarms Critical/Warning/Info, "no active", latest transition | info | Partial: rail count tint; `latest_transition_at` unused | |
| Context rail: commands queued / release pending / in flight / failed; "Following" a command | info | Partial: rail open count, Now tile; no in-flight/failed, no following | |
| Context rail: fleet Red/Yellow/Blue/Green, violating points total | info | Partial: Now stat strip per spacecraft; no blue, no total | |
| Section freshness + observed at; section Open links | info/action | Partial: Now header freshness; Yes for links | |
| Module failure with diagnostic reference id; Retry | info/action | Partial: ApRemote retry, no reference id | |

### /ops/alarms (`limits-and-alarming/src/features/alarm-conditions`, `shared/LimitStateList.vue`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Header links "Limit definitions", "Current posture" | action | Partial: `setup.app` limits/manage, /activity; not linked from Alarms | |
| Severity count tiles critical / warning / info / nominal; "loaded at" | info | Partial: lifecycle tab counts; no severity counts or timestamp | |
| Severity filter | action | No | console severities are crit/caution only |
| Condition filter All / Active / Nominal | action | Partial: tabs New / Acknowledged / Cleared 24 h; nominal states not listed | |
| Spacecraft / "Mission states" scope filter; Find spacecraft + paging | action | No | per spacecraft via Investigate |
| Text search point or limit set | action | Partial: By-point click filter; mobile search | |
| Apply / Reset filters | action | Partial: immediate URL filters; no reset | |
| "N conditions · scope" total | info | Partial | |
| Condition paging (25) | action | Partial: one list, 200 cap, no notice | bug D3 |
| Row: point, spacecraft or Mission, severity + raw state, value | info | Yes (`alarms/AlarmTable.vue`) | console adds the crossed limit |
| Row: point id | info | Partial: Investigate Technical details | |
| Row: limit set name | info | No | decoded `alarms/api.ts:65` |
| Row: generated time, received time | info | No / Partial | decoded, not shown |
| Row: "Produced by definition · vN" + "Inspect producing vN" | info/action | No | decoded `investigate/api.ts:56-57` |
| Row: "Open exact sample" | action | Partial: Investigate trend chart; "Open in Explore" | not the exact sample |
| (console only) Acknowledge, Assign, Hand off, owner/source columns, By-point panel, 90-day History | | | |

### /ops/timeline (`ops-workspace/features/timeline`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Category filter | action | Partial: kind toggles (different groupings) | |
| Kind free-text filter; severity filter | action | No | |
| Spacecraft filter | action | Partial: Scope fleet/plane/current spacecraft; only via `?sc=` | |
| From / To | action | Yes: ApTimeRange + density brush | |
| Reset (keeps source dashboard) | action | No | |
| "Up to N per page"; "Observed at" | info | No | `truncated` decoded, not shown (bug D2) |
| Newest events / Older events paging | action | Partial / No | "N new events ↑"; window-only |
| Select an event; detail (identity, occurred, kind, status, source record, subject, 8 references); Clear; Copy event link | action/info | No (occurred: Yes) | rows link to the subject instead |
| Row: occurred, title, summary | info | Yes (`timeline/EventLog.vue`) | |
| Row: category, raw kind | info | Partial / No | severity shows as a mark |
| Empty / error + Retry | info/action | Yes | |

### /ops/planning, /ops/planning/new, /ops/planning/runs/:id (`planning-and-contacts/src/features/fleet-planning`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| "Plan horizon" / Horizon start-end inputs | action | Partial: "Draft the day" (`scheduling/PlanScreen.vue`), one UTC day | A14 |
| "Include recurring demand" | action | No | A14 |
| Review pinned inputs (requirements, templates, occurrences) before creating; input fingerprint | action/info | No (Partial: `StartLimits.vue` caps) | A14 |
| "Create queued run" | action | Partial: draft starts and runs at once | |
| Policy required + "Review policy" | info/action | Yes (`PlanStatePanel.vue`) | |
| Policy vN, id, sha, max horizon, contact/cost limits, concurrency | info | Partial: Setup › Contact planning › Policy | B |
| Run directory: list, lifecycle filter, paging, run links | action/info | No | A17 |
| Run: lifecycle, phase, failure message | info | Partial/Yes: current day's run (`plan-state.ts`) | failure code not shown |
| Run: trigger, algorithm, pinned policy, fingerprints | info | No | B |
| "Continue planning" | action | Yes: "Continue drafting" | |
| Requirement inputs per run (state, coverage, priority, search id) | info | Partial: `DemandPanel.vue` per spacecraft | |
| Optimizer decisions (rank, score, rationale, constraints), resource pressure, automation history | info | No (Partial: `AlternativesList.vue`) | A17 |
| Repair: unavailable reason, locked commitments | info | Partial (`replan/`) | |
| Repair: window inputs, max horizon, repair policy, attempt N/max | action/info | No | A14 |
| "Create queued repair run" | action | Yes: Re-plan propose (`replan/useReplan.ts`) | |
| Run receipts / "outcome unconfirmed" panels | info | No (idempotent operation_id) | |

### /ops/plans/:contact_plan_id (`planning-and-contacts/src/features/contact-plans/OpsContactPlanShow.vue`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Title "Contact plan vN", current state | info | Yes (`PlanScreen.vue`, `plan-primary.ts`) | |
| Historical-version banner, "Review current version", version list | info/action | No | A10 |
| Selected / locked / rejected counts; coverage; conflicts | info | Yes / Partial / No / Yes / Yes | |
| Rationale, plan id, content hash | info | No | B |
| Submit for review (+ reason) | action | Partial: `SubmitSheet.vue`; reasons per gap | A15 |
| Approve (+ reason) | action | Partial: approve always books | A15 |
| Reject (+ reason) | action | Yes: Send back (`SendBackSheet.vue`) | |
| "Governed by an automation approval policy" | info | No | |
| Execute approved version | action | Yes: Book N passes / Continue booking | |
| Opportunity: station, window, synthetic | info | Yes | |
| Opportunity: provider, expires at, eligibility, availability, route key, versions, evidence sha, "Review requirement" | info/action | Partial/No | B |
| Requirement coverage (approval mode, failures) | info | Partial: `DemandPanel.vue` | |
| Review findings (with requirement links) | info/action | Partial: `StationIssues.vue`, conflict marks | |
| Execution: state, attempts, reservation link | info/action | Partial: booking state, `BookingIssues.vue` | no attempts or link |
| Decision history (all rounds) | info | Partial: latest round | A10 |

### /ops/contacts (`planning-and-contacts/src/features/contact-scheduling/OpsContactSchedule.vue`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Pending / unconfirmed provider operation | info | Yes: Book a pass "unclear" + Try again; release outcomes | |
| Receipt with revision | info | Partial: "Booked … ref X", no revision | |
| Find / choose spacecraft | action | Yes: Book a pass select | |
| Ready route select | action | Partial: direction + station filters | A16 |
| Start / end of search | action | Partial: now…+48 h | A16 |
| Search opportunities; permission gate | action | Yes (`contacts/BookPassSheet.vue`) | |
| Ready routes list with versions; readiness findings with ids; comms-setup link | info/action | No / Partial | B |
| Offer: window, station, expiry; Reserve; reserve disabled when not reservable | info/action | Yes | |
| Offer: id, antenna, availability, synthetic, cost | info | No | decoded, not rendered (A16) |
| Scheduled / realized ledgers with ids, revisions, paging | info/action | Partial: Live window, Plan by day, Investigate, Review | A12 |
| Reservations: open, "Review cancellation", state, window | action/info | Yes: drawer + Release pass | |
| Reservation provider id·version, reference, "Scheduled contact" link | info/action | Partial/No | A11, B |
| Cancel confirm with id/ref/revision | info/action | Partial: `ReleasePass.vue` (no id/ref/revision shown) | |
| Scheduling operations journal + "Retry acceptance"; section paging | info/action | No | |

### /ops/contacts/records/:contact_id (`OpsContactRecord.vue`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Scheduled / realized: state, window, realized at | info | Yes/Partial: pass drawer, state trail, telemetry-stored line | |
| Ids, revision, provider reference, clock mode, initial clock time | info | No | B, A13 |
| Reviewed revision (window, state, author) + "Review current revision" | info/action | Partial: window moves in `PassChangeHistory.vue` | A13 |
| Origin provider change link + hash | info/action | Partial: "Open the change" | |
| Scheduled / realized paths, bindings, source endpoints, intents (+ paging) | info | No | A13 |
| Schedule history | info/action | Partial | A13 |

### /ops/contacts/:provider_reservation_id (`OpsContactDetail.vue`; L14)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Provider change: from→to, before/after table, deadline, historical, admin-only | info | Yes (`contacts/ProviderChangeBlock.vue`, `PassChangeHistory.vue`) | revisions/policy version: No |
| Approve / Reject / Acknowledge + reason | action | Yes (also from Now) | |
| Restricted provider data notice | info | No | |
| Requested / provider-confirmed / accepted values | info | No | A11 |
| Spacecraft | info | Yes | |
| Provider·version, transport·version, scheduled contact id | info | Partial/No | B |
| Contact plan link, requirement link | action | No | A11 |
| Change history (paged) | info/action | Partial: latest 50 | |
| Reservation audit list | info/action | Partial: off-plan, ended, decision lines | A11 |

### contact-workspace (`ops-workspace/features/contact-workspace`; HTML `/ops/contact-workspace[/records/:id]`)
Renders the same schedule and record components, so the two tables above apply. Its own items: nav links (Yes:
Contacts tabs, Now), 5-second refresh (Yes: live invalidation), offline notice (Yes), "session changed, reload"
(Partial: `session_changed` decoded, shell handling unverified), "Refreshing…" (No). Its HTML routes already
redirect to `ops.contacts` / `ops.contact`.

### /ops/commands (`commanding/src/features/mission-commands`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Facts: queued, release pending, in flight, failed | info | Partial: tab counts, per-row "need you", Now row | |
| Create request | action | Yes (`commands/list/CommandsScreen.vue`) | |
| "Command stages" link | action | No | C |
| Observed / "live updates interrupted" | info | No | |
| Focus a command + its evidence; Clear focus | action/info | No (opening the request replaces it) | |
| Open full history | action | Partial: request page log | A3 |
| Review request | action | Yes | |
| State filter (12 states), target filter, search, Apply / Reset | action | Partial (4 tabs) / No | A5 |
| Row: state, requested by, requested at | info | Yes | |
| Row: command name, target name | info | Partial: group title, "N targets × M" | |
| Row: request id, command id | info | No | B |
| Paging | action | No (1,000 cap) | A5 |
| Evidence: release held / uncertain | info | Yes: Needs-you cards | |
| Evidence: queue entry, release attempt, verifier records with deadline | info | Partial/No | A3, A4 |

### /ops/commands/workspace, /ops/commands/new (`commanding/src/features/{workspace,command-authoring}`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| No-access state; feedback; prerequisite (no command model) | info | Yes (`commands/compose/ComposeScreen.vue`, `CatalogSearch.vue`) | |
| Target search (text), select visible / first 25, clear all | action | Partial: query chips, add select, matrix; no text search or clear-all | |
| Target tile: name, SCID; endpoint, source_ref; endpoints without a spacecraft | info/action | Partial: name, SCID, profile; endpoint in Delivery plan; no source_ref | |
| Per-target catalog status | info | Partial: catalog revision + preflight check | |
| Command search, open | action | Yes (`CatalogSearch.vue`) | |
| Command display_name + id; Critical tag; catalog paging | info/action | Partial: name+description; Hazardous only; 200 cap | |
| Value mode all / per spacecraft | action | Partial: numeric args only | |
| Argument editor (types, fixed, enum, boolean, text) | action | Yes (`ArgField.vue`); no type labels; hazardous values flagged after entry | |
| **Priority** | action | No | A1 |
| Not before | action | Yes ("Hold until a set time") | |
| **Expires at** | action | No | A2 |
| Draft notes | action | Partial: one group-level log entry | |
| Validation, auto-preview, Retry | info/action | Yes: preflight | |
| Preview: reserved id, model revision, command id, priority, significance, **resolved arguments** | info | Partial/No | B |
| Requires approval before queueing | info | Yes: "Needs a second GO" | |
| Enqueue / Request approval / Submit | action | Yes: Arm / Request GO | |
| "I reviewed…" checkbox | action | No | C |
| Result / unconfirmed / rejected; open request; start another | info/action | Yes (`SubmitOutcome.vue`) | |
| Shelf, stage picker, add drafts to a stage, item inspector, batch preview | all | No | C (stages) |

### /ops/commands/stages, /stages/new, /stages/:id (`commanding/src/features/{command-stages,stage-create,stage-workbench}`)
Directory (search, state filter, private/shared, paging), create (name, description, visibility), settings
(name/visibility/description/state, cancel), items (filter, select, order, notes, cancel), batch preview with
"Create N formal requests": **none exist in the console** (C). Partial overlaps: Compose (add commands, arguments,
targets, not-before, preflight, Arm / Request GO) and its one autosaved private draft.

### /ops/commands/requests/:id (`commanding/src/features/command-review/CommandReview.vue`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Title, lifecycle badge, hazardous/critical, target, not before, verification, submitted arguments | info | Yes (`commands/request/RequestScreen.vue`, `RequestBrief.vue`) | |
| "Review for queueing" / queue page | action | No (by design) | C |
| Request id, command id, priority, significance, subsystem, group, release policy hint, APID/service/opcode, uplink service | info | No/Partial | B (payload bytes shown) |
| Model revision, requested at, expires at | info | Partial | |
| **Resolved arguments** | info | No | B |
| "The request changed…" | info | Yes (review_stale) | |
| Approve / Reject + reason; read-only reasons | action/info | Yes, and more (GO excluding, Send back, NO-GO) | |
| "I reviewed…" checkbox | action | No | C |
| Decision receipt / history with approval id | info | Yes, no approval id | B |

### /ops/commands/requests/:id/history (`command-history`, `MatchedEvidence.vue`)
| Item | Kind | Console | Note |
| --- | --- | --- | --- |
| Request id, command id, model revision | info | No/Partial | B |
| Target, request state, verification | info | Yes | |
| Release attempts (id, state, contact, path, binding, encoded size, attempted, released) + list + paging | info/action | No (Partial: Investigate U4, 24 h) | A3 |
| Verifier: name, state, phase (Partial); id, severity, failure code, matched at, deadline | info | No | A4 |
| Matched telemetry evidence (packet, evidence id, quality, raw, engineering) | info | Partial: plot samples, "last read X" | A4 |
| Matched transport evidence | info | No | A4 |

### /ops/commands/requests/:id/queue (`queue-submission/QueueSubmission.vue`)
By design the queue step is merged into GO / Arm (C). Information that goes with it: request id, APID, opcode,
priority, resolved arguments, approval id, approved content sha, queue entry id / queued by / queued at, queue
receipt (B; queue details partly in Investigate U3). "Expired" reads "Canceled" (bug D4).

## Console-only (for context)
Alarms acknowledge / assign / hand off and a 90-day history; Timeline density strip, folding and plane scope;
Commands Abort remaining, GO excluding, Send back, Edit and resend, per-target Re-send, release into an unbooked
contact, Recover uplink, HOLD acknowledgements, endpoint override, value changes, bound requests on a pass.
