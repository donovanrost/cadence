# Apogee backlog: what's left, per screen, against the canvas

Written by lead, 2026-11-09, for the director. Sources: the ux specs (`ux/screens/*.md`), the canvas
boards (`design-reference/`), `ux/decisions.md`, `DECISIONS.md`, open `qa/issues.md` rows, the
ux reviews, and a read of the built code (`frontend/apps/console/src/features/`). Items marked
*(unverified)* came from a code read that didn't settle them; owners should confirm before starting.

**Owners:** lead · ux · fe-ops · fe-setup · qa · api · api-ops · domain. **Blocked on** names the
missing endpoint or decision; an item with no blocker can start now.

## 1. Next up, per person (the short version)

| Who | Start now (unblocked) | Waiting on |
| --- | --- | --- |
| **lead** | K1 C panel (focused spacecraft 24 h strip); `ApSheet` kit primitive (four hand-rolled dialogs today); `ApStatTile` `to` link; Palette `>` commands and `@` stations groups (with fe-ops) | api: K1 send-back, `approval.exceptions`, interrupted-draft stop time |
| **fe-ops** | Now tile links + A4 pass select + approval rows → request review; Investigate tabs link to existing pages (spec) + add-point chips; Contacts D3 outage bands (S7 exists); Telemetry `Dashboards ↗` → existing pages (#11); Timeline sc/plane filter; Fleet/Alarms Next contact; Mobile GO block | api-ops: M8 spacecraft topic, M22 findings, M24 encode preview, M26 retries, catalog revision, Swap/Release; ux: Compose layout ruling |
| **fe-setup** | K2 Covered tile; Profile edit → stage (op + preview exist); People command policies tab (O4 exists); Changes compare (`/config/compare`) + Keep mine / Take live (`rebase`); Readiness R2 from revisions; Audit actor filter; qa #19 copy ("unclear, check now" on 5xx) | api: catalog diff, people/invite/service-identity writes, account password/sessions, provider history, mission create; domain: catalog generations (C3) |
| **ux** | Visual review of the unreviewed boards (§9); Compose C1 layout ruling; specs for Notifications and New mission | — |
| **qa** | Accessibility pass (§9) once the current fixes land; K1 booking header live check (cf3cd37a); U31 callout clearing on resolve; K2 Propose → Apply after #52/#56 | — |
| **api** | §8 list | — |
| **api-ops** | §8 list | domain #34 for uplink items |
| **domain** | qa #34 (uplink after the first command, #58/#59); qa #19 server side; catalog-path generations (#36) | — |

## 2. Ops

### Now (`Now.md`, J1): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| Stat tiles link (Critical/Caution/Stale → Alarms/Fleet, In contact → Contacts, Uplinks → Commands) | fe-ops + lead (`ApStatTile` gets `to`) | — |
| Queue kinds `missed_pass`, `station`, `flight_event` and the `Station` (→ Re-plan) action | fe-ops | api-ops queue sources *(unverified)* |
| Header meta names the worst station issue | fe-ops | — (S7 status exists) |
| A4 pass bars open the contact drawer | fe-ops | — |
| Approval rows open the request's review, not the Commands list | fe-ops | — |
| New P1 rows slide in / flash (the 5 s "Resolved by" fade exists) | fe-ops | — |

### Investigate (`Investigate.md`, J2): J2 tab built; five tabs not started
| Item | Owner | Blocked on |
| --- | --- | --- |
| Telemetry, Uplink, Passes, Configuration, History tabs: today `NotBuiltTab` without the spec's "link to the existing page"; ship the links first, then build | fe-ops | — |
| B1 add points (chips, max 3, search this spacecraft's points) | fe-ops | — (M23 point search) |
| No active alarm: show the latest resolved alarm "back in limits" | fe-ops | — |
| B4 sisters: plane ring, sparklines, next AOS | fe-ops | — |
| Live chart tail + event log | fe-ops | api-ops M8 `spacecraft:<id>` topic |
| `FULL TIMELINE →` carries `?sc=` | fe-ops | — |

### Command a group / Compose (`Command.md`, `CommandFlow.md` C1): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| **Ruling first:** Compose follows Command.md's C1–C5; CommandFlow C1's three-column board (catalog listbox, form, clickable targets matrix, action bar, Manual release) isn't built. Accept or schedule. | ux → fe-ops | — |
| Draft autosave / `Save draft` / `DRAFT SAVED` | fe-ops | api-ops: draft persistence *(unverified)* |
| Per-target values (Same for all / Per target, Paste CSV, Now column) | fe-ops | — |
| Verifier line / "No verifier: this command can't turn green" | fe-ops | catalog read carrying verifiers *(unverified)* |
| Keep/Drop callout when a target leaves a live query | fe-ops | — |
| Reorder by drag and Alt+↑/↓ | fe-ops | — |
| `CATALOG rev N` meta | fe-ops | api-ops: catalog revision number |
| `ABORT AVAILABLE UNTIL…` caption *(unverified)* | fe-ops | — |

### Approve and Uplink (`CommandFlow.md` C2/C3): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| A1 `5.0 → 8.0` readout, histogram of current values, hand-set overwrite callouts | fe-ops | api-ops: current values + prior requests in the brief |
| A3 encoded packet bytes (honest "not available" today) | fe-ops | api-ops M24 encode preview |
| U2 verifier plot, "Needs you" cards with Re-send / Open, plane matrix, Pause, retry on no ACK | fe-ops | api-ops M26 retries + verifier series; domain qa #34 for live testing |

### Contacts (`Contacts.md`, J4): Live built; detail route pending
| Item | Owner | Blocked on |
| --- | --- | --- |
| D3 outage / maintenance bands (K1 already draws them from S7) | fe-ops | — |
| `ops.contact` route (`contacts/:contactId`); today the drawer on `?contact=` covers it, so ship a redirect | fe-ops | — |
| `sc any` filter chip, "highlight queued uplinks" | fe-ops | — |
| D2: queued requests bound to the pass, state trail; `Swap station`, `Release` | fe-ops | api-ops: swap/release endpoints |
| D4 "Needs a decision" | fe-ops | api-ops M22 conflict/gap findings |
| `Book passes` | fe-ops | — (K1 Plan covers part) |

### Query line ⌘K (`Palette.md`, J5): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| Commands (`>`) and Stations (`@`) groups | lead + fe-ops | — (M17 catalog, stations reads exist) |
| Recent items on empty query, `SEARCHING…`, Setup-mode ranking | lead | — |
| One server search endpoint instead of client-side fleet search | api-ops | ask when fleets exceed the client list |

### Fleet, Alarms, Telemetry, Timeline (`OpsLists.md`): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| Fleet: "in contact" filter, Next contact column; virtualization past 200 rows *(unverified)* | fe-ops | — |
| Alarms: group identical point+condition across spacecraft, Next contact, "Last cleared…" empty state; Cleared tab re-check (investigate review #20) | fe-ops | — |
| Telemetry: `Dashboards ↗` goes to the existing dashboard pages (#11), not the pending route; empty state's three suggested points | fe-ops | — |
| Timeline: sc / plane filter (API supports plane), custom range, E1 brush, live prepend + "N new events ↑" | fe-ops | live prepend: api-ops events topic *(unverified)* |

## 3. Scheduling (`ScheduleFlow.md`)

### K0 · Pass prediction: deferred (#4). Nothing to build until server-side propagation.

### K1 · Plan the day (`contacts/plan`): built; gaps against the SchedulePlan board
| Item | Owner | Blocked on |
| --- | --- | --- |
| C · focused spacecraft 24 h strip (rule chips, pass and gap strip) | lead | — |
| Admin `pending_approval` review: ApDecision `Approve and book` / `Send back` with a comment | lead | api: reject / send-back on contact plans (S5 has submit/approve/execute only) |
| Accepted gaps as `GAP ACCEPTED · <reason>` rows and in revision history | lead | api: `approval.exceptions` on plan detail |
| Per-contact Requested → Confirmed / Rejected on the Gantt; rejections become Demand rows | lead | — (passes read + `execution`, cf3cd37a) |
| `Drafting stopped at 02:31Z` | lead | api: stop time on interrupted draft runs |
| `PROVIDER FREEZE T−…` header clock | lead | api/domain: no provider freeze time in any read |
| Minutes / Cost budgets in the footer; Cost, Link, Max el in D | lead | billing terms + budgets (api "not yet"); Max el only when provider-supplied |
| Done today: U26, U28, U30, U31, U32, superseded, execution header (live check pending, qa) | — | — |

### K2 · Re-plan (`contacts/replan…`): built (fe-setup); gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| `Covered N` tile (#56) | fe-setup | — (decoder 5925fb35) |
| Footer cost ("the footer shows the cost", acceptance) | fe-setup | billing terms (api) |
| Live Propose → Apply after #52/#56 | qa + fe-setup | — |

### K3 · Close the books (`contacts/review`): built (fe-setup); gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| `Export CSV`, `Monthly close` | fe-setup | api: export + close endpoints |
| R5 provider reconciliation, `Dispute` / `Draft dispute`, money in h1 / R4, minutes flown vs billed | fe-setup | provider billing data (api "not yet"); no dispute flow exists |

## 4. Setup

### Readiness (`Setup.md`, S1): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| R2 Recent changes (last 4 revisions + `Compare revisions`) and the subline's latest change: api sends `recent_changes: null` | fe-setup (read `GET /config/revisions`) or api (fill the field) | agree which; change sets exist now |
| pass-1 #8 copy (Apps tile names missing apps, Catalog wording) *(unverified)* | fe-setup | api *(unverified)* |

### Add spacecraft (`AddSpacecraft.md`, S2): mostly built
| Item | Owner | Blocked on |
| --- | --- | --- |
| Step 03 routing: transport/station pick, "generates N routes" summary (A4 says "added later") | fe-setup | — profile routing exists *(unverified)* |
| NORAD id on the profile path; `New profile` link in the picker | fe-setup | — |

### Catalog (`Catalog.md`, S3): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| `setup/catalog/:databaseId` route (pending) | fe-setup | — |
| C1 diff (UI ready, shows "not available") | fe-setup | api: server-side revision diff + breaking rules (#9 keeps v1 diff in scope) |
| C3 Roll out to / `Request activation` | fe-setup | domain: catalog-path generations (#36) |
| Commands vs Telemetry split; `Replace file`; warnings disclosure *(unverified)* | fe-setup | api: `command_count` / `telemetry_count` |

### Profile (`Profile.md`, S4): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| P1 edit + P4 staged aside (`Stage edit`, `Changes N / Keeps M`); the update op and preview exist | fe-setup | — |
| The #19 read-only framing callout looks stale after #33/#45 | fe-setup | ux/domain confirm #19 is lifted |
| `New profile`, `Duplicate as new profile` (create op exists) | fe-setup | — |
| List: Overrides, Last changed columns; Limits notice; History field diffs, `Compare`, pin; conflict chip | fe-setup | — |

### Staged changes / revisions (`Changes.md`): mostly built
| Item | Owner | Blocked on |
| --- | --- | --- |
| Compare revisions (`r4...r6`) | fe-setup | — (`GET /config/compare`) |
| `Keep mine` / `Take live` on conflicts | fe-setup | — (`POST /ops/:op_id/rebase`) |
| Staged bar conflict / applying / apply-failed states; top bar `CONVERGING` / `RUNTIME DEGRADED`; live apply steps | fe-setup | apply progress source *(unverified)* |
| qa #19: a 5xx on submit reads "Nothing was applied"; should read "unclear, check now" | fe-setup (copy) + domain/api (the 500) | — |
| Now P3 row when a set sits > 24 h; Timeline `Config r6 applied` | fe-ops | *(unverified)* |

### Contact planning (`ContactPlanning.md`): built. Review 6/7 in progress (sort is in; uppercase rule line *(unverified)*). Owner fe-setup.

### People & access (`People.md`, S5): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| Command policies tab / aside (U4); `GET /command-policies` (O4) exists, unused | fe-setup | — |
| `org.people.invite` / `org.people.services` routes are pending though both render inline: wire or drop | fe-setup | — |
| Person page (Access, Activity, change role, remove) | fe-setup | api: role change, remove member, per-person activity |
| Invitation Resend / Revoke; service identity create / rotate / revoke (secret shown once) | fe-setup | api: write endpoints (reads + invite only today) |

### Settings, Audit log, Provider accounts (`SettingsAuditProviders.md`): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| Settings: `Override` on inherited fields *(unverified)* | fe-setup | — |
| Audit: actor filter (api supports `actor_id`), kind chips, `Export CSV` | fe-setup | export: api or client-side |
| Provider accounts: version history | fe-setup | api: history read |

### Org / account
| Item | Owner | Blocked on |
| --- | --- | --- |
| `org/missions/new` (pending) | ux (spec) → fe-setup | api: console mission-create endpoint |
| Account: password change, active sessions | fe-setup | api: no endpoints |
| `/notifications` (pending) | ux (spec) → lead | — no spec beyond the IA table |

## 5. Phase 4 · Mobile on call (`Mobile.md`, J6)
| Item | Owner | Blocked on |
| --- | --- | --- |
| Alarm page "Your GO is requested" block (GO / NO-GO + confirm sheet) | fe-ops | — |
| Mobile Approve layout (GO opens the desktop takeover today) | fe-ops + lead (shell) | — |
| Search as a full-screen sheet limited to spacecraft, alarms, requests | lead | — |
| "N sisters in P07 trending" line *(unverified)* | fe-ops | — |

## 6. Phase 4 · Accessibility pass
| Item | Owner | Blocked on |
| --- | --- | --- |
| axe + keyboard traversal + focus order on every route, 1440 and 390, as admin and member; file per screen | qa | — |
| Fixes per screen | the screen's owner | qa's findings |
| Kit-level fixes (focus trap/return, scrollable regions, contrast on hatches) | lead | — |

## 7. Phase 4 · Visual review and dashboards
| Item | Owner | Blocked on |
| --- | --- | --- |
| Board-by-board visual review for boards without a review in `ux/reviews/`: Approve, Uplink, CommandFlow, Replan, PassReview, Mobile, Palette, People, Settings/Audit/Providers *(check list against reviews)* | ux | — |
| Dashboards (#11): decide rebuild in the console vs keep the existing engine; until then `Dashboards ↗` links to the existing pages | user/director + ux; then fe-ops | everything else shipping |

## 8. Endpoint queue per backend team (collected from above)

**api**
1. Contact plans: send-back / reject for `pending_approval`; `approval.exceptions` on plan detail; stop time on interrupted draft runs (K1).
2. Catalog: server-side revision diff + breaking rules; `command_count` / `telemetry_count` (Catalog C1).
3. People: role change, remove member, per-person activity; invitation resend/revoke; service identity create/rotate/revoke.
4. Account: password change, sessions. Org: console mission create. Provider accounts: version history.
5. Readiness `recent_changes` (or agree fe-setup reads revisions).
6. Billing terms + budgets (K1 cost, K2 footer cost, K3 money): needs a scope call first (see §10).
7. K3 `Export CSV` / `Monthly close`.
8. qa #19 (submit 500 after commit), with domain.

**api-ops**
1. M8 `spacecraft:<id>` topic (Investigate live tail and log).
2. M22 conflict/gap findings (Contacts D4); swap / release (Contacts D2).
3. Catalog revision number (Compose meta); current values + prior requests in the request brief (Approve A1).
4. M24 encode preview (Approve A3); M26 retries + verifier series (Uplink U2).
5. Now queue sources: missed pass, station, flight event *(unverified)*.

**domain**
1. qa #34: uplink after the first command per route (#58/#59), which blocks live uplink testing.
2. qa #19 server side.
3. Catalog-path generations (#36), which unblock Catalog C3 rollout.
4. Spacecraft archive model (#50) for rollback of spacecraft creation.

## 9. Deferred by decision (not backlog)
#2 roles/Cedar · #4 propagation (K0, ground track, umbra, sky plot, max elevation) · #5 procedures ·
#7 command policies read-only in v1 · #8 command waves/gates · #9 catalog impact / used-by ·
#11 dashboards last · #15 profile limits and VC/FEC/randomizer fields · "save as group" on Compose.

## 10. Questions for the director
1. **Billing:** K1 cost/budgets, K2 footer cost and all of K3's money and disputes need provider
   prices. In scope for this project, or do those panels stay "not reported"?
2. **Compose layout:** accept Command.md's C1–C5 as built, or schedule the CommandFlow C1 board?
3. **Investigate:** ship the five missing tabs as links to the existing pages now (the spec's own
   fallback), and build them later?
4. **Pending routes** with no spec (Notifications, New mission): spec them, or drop them for now?
