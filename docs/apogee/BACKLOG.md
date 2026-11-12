# Apogee backlog: what's left, per screen, against the canvas

Written by lead, 2026-11-09, for the director. **Updated** with DECISIONS #63/#64 (billing out
of scope: money panels hidden; Compose per ux; Investigate tabs link out; Notifications dropped;
New mission links to the existing create page; ux U34, 72f5a5f6). Sources: the ux specs (`ux/screens/*.md`), the canvas
boards (`design-reference/`), `ux/decisions.md`, `DECISIONS.md`, open `qa/issues.md` rows, the
ux reviews, and a read of the built code (`frontend/apps/console/src/features/`). Items marked
*(unverified)* came from a code read that didn't settle them; owners should confirm before starting.

**Owners:** lead · ux · fe-ops · fe-setup · qa · api · api-ops · domain. **Blocked on** names the
missing endpoint or decision; an item with no blocker can start now.

## 0. Live operations and freezes (read first)

- **qa #65 step 3 rerun: ARMED** (director, 11-12). Command group `3r7djzn3ia_P9CS`: SET_MODE 4 to
  EARENDIL-001 on 001's own Svalbard pass **11-14 00:33:52-00:41:52Z** (not_before 00:25Z, expires
  00:42Z; uplink booking confirmed). Negative check: 005 INV 00:27:53-00:35:53Z.
  - **FREEZE 11-13 23:33Z to 11-14 01:00Z:** no lib saves, no :4011 or simulator restarts, no sim
    pause, light load (targeted tests only; no full suites, verify runs or builds).
  - **Until the pass:** don't abort the queued group (it shows as queued in Commanding), and no
    catalog change may touch 001 (it would cancel the command). Catalog step 4 (the other 499)
    lands after 11-14 or must not touch 001.

## 1. Next up, per person (the short version)

| Who | Start now (unblocked) | Waiting on |
| --- | --- | --- |
| **lead** | K1 C panel (focused spacecraft 24 h strip); `ApSheet` kit primitive (five hand-rolled dialogs today); `ApStatTile` `to` link; Palette `>` commands and `@` stations groups (with fe-ops) | — (api's K1 items shipped: send back, approval, stop time) |
| **fe-ops** | Now tile links + A4 pass select + approval rows → request review; Investigate's five tabs link to the existing pages (#64) + add-point chips; Contacts D3 outage bands (S7 exists); Telemetry `Dashboards ↗` → existing pages (#11); Timeline sc/plane filter; Fleet/Alarms Next contact; Mobile GO block | — (api's M22, A1, M24 and drafts are in) |
| **fe-setup** | Profile edit → stage (op + preview exist); People command policies tab (O4 exists); Changes compare (`/config/compare`) + Keep mine / Take live (`rebase`); Readiness R2 from revisions; Audit actor filter; qa #19 copy ("unclear, check now" on 5xx) | api: catalog diff, people/invite/service-identity writes, account password/sessions, provider history; domain: catalog generations (C3) |
| **ux** | Visual review of the unreviewed boards (§7); Compose C1 layout ruling (default: accept as built, #64) | — |
| **qa** | Accessibility pass (§9) once the current fixes land; K1 booking header live check (cf3cd37a); U31 callout clearing on resolve; K2 Propose → Apply after #52/#56 | — |
| **api** | Done: C3 rollout read + profiles `catalog_revision` (34b8cc27). Port the #42 fix to `develop` (DECISIONS #72). Done: #42 verify race 32b945f3 (advisory lock, mission-then-attempt order, timeout reconcile, call-site tests; api-ops reviewed); Compose drafts a4d19e69 (`GET/PUT/DELETE /missions/:id/command-draft`, migration). Next with the director | — |
| **api-ops** | queue empty; next with the director. Done: qa #46 simulator Orchestrator survives Store timeouts (3ea527b2: ETS-mirrored Store reads, guarded tick steps, linked-stream sweep; live after qa's sim restart); flight_event v1 (a02c2cee, 1b3be7f7, e07969bb, docs 291744b7); #42 review (32b945f3) | flight_event: qa sees a row live; #46: qa sim restart |
| **domain** | the monitoring-enabled fixture with the end-to-end catalog-rule test, then catalog-path generations (#36; plan to the director first, it touches activation) | — (done tonight: #71 settlement + replay 1d6be29f, mission_runtime 7a6c596a, lost-item acknowledge e99cd89d, reconciler rescue 292c8e6b) |

## 2. Ops

### Now (`Now.md`, J1): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| Stat tiles link (Critical/Caution/Stale → Alarms/Fleet, In contact → Contacts, Uplinks → Commands) | fe-ops + lead (`ApStatTile` gets `to`) | — |
| ~~Queue kinds `missed_pass`, `station` + `Station` → Re-plan~~ done (de131e9b); `flight_event`: source landed (api-ops a02c2cee, 1b3be7f7, e07969bb), fe-ops reader 591bc06c | fe-ops | qa: a flight_event row seen live after the :4011 restart |
| ~~Attention source `contact_settlement` (#71) reader~~ done (14330a4a, U37 words, no Acknowledge, Review opens Contacts by contact_id); unknown kinds/sources now drop one row, not Now | fe-ops | — (source live 22:14Z) |
| ~~`contact_settlement` manual retry (#71 replay): needs-operator line, `Retry storing`, 'Next try at HH:MMZ.'~~ done (c10265fd; ux 294e67c6) | fe-ops | — (domain ships the manual state after 00:30Z) |
| ~~Attention source `mission_runtime` row (U38)~~ done (751ac5f5; reasons spec_mismatch, reconcile_crashed, runtime_not_running, apply_failed) | fe-ops | — (domain cleared to ship) |
| Mission-wide runtime banner (U38 4f8b796c): crit strip under the top bar on every mission page, Ops and Setup, not dismissable, `Details` → Now's row; turns nominal for 5 s on resolve ('Telemetry processing resumed at HH:MMZ.') | lead | built and ux-accepted (e585d19c, d8102e0d); `/counts` runtime landed (api-ops c69f0578, shape verified against the reader); live on :4011 since 00:57Z |
| ~~`contact_settlement` journal off (U37 lost) and `Mark as seen`~~ done (171ecd43, bbe5e8fe) | fe-ops | — |
| Header meta names the worst station issue | fe-ops | — (S7 status exists) |
| ~~A4 pass bars open the contact drawer~~ done (51cc6133) | fe-ops | — |
| ~~Approval rows open the request's review~~ done for a single group (a0e33fe1) | fe-ops | — |
| New P1 rows slide in / flash (the 5 s "Resolved by" fade exists) | fe-ops | — |

### Investigate (`Investigate.md`, J2): J2 tab built; five tabs not started
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Telemetry, Uplink, Passes, Configuration, History tabs link to the existing pages (#64)~~ done (0d05d195); build later | fe-ops | — |
| B1 add points (chips, max 3, search this spacecraft's points) | fe-ops | — (M23 point search) |
| No active alarm: show the latest resolved alarm "back in limits" | fe-ops | — |
| B4 sisters: plane ring, sparklines, next AOS | fe-ops | — |
| ~~Live chart tail~~ done (f38a4dfb); live event log | fe-ops | *(check whether M8 covers events)* |
| ~~`FULL TIMELINE →` carries `?sc=`~~ done (cb5767c9) | fe-ops | — |

### Command a group / Compose (`Command.md`, `CommandFlow.md` C1): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| Compose layout: ux rules; default is to accept Command.md's C1–C5 as built (#64) | ux | — |
| ~~Draft autosave / `Save draft` / `DRAFT SAVED`~~ done (c0510343, e262c233; ux 601a32f9; api a4d19e69) | fe-ops | — |
| Per-target values (Same for all / Per target, Paste CSV, Now column) | fe-ops | — |
| Verifier line / "No verifier: this command can't turn green" | fe-ops | catalog read carrying verifiers *(unverified)* |
| Keep/Drop callout when a target leaves a live query | fe-ops | — |
| Reorder by drag and Alt+↑/↓ | fe-ops | — |
| `CATALOG rev N` meta | fe-ops | — (`catalog_revision` in the command-catalog basis) |
| `ABORT AVAILABLE UNTIL…` caption *(unverified)* | fe-ops | — |

### Approve and Uplink (`CommandFlow.md` C2/C3): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| A1 `5.0 → 8.0` readout, histogram of current values, hand-set overwrite callouts | fe-ops | api: current values + prior requests in the brief |
| ~~A3 encoded packet bytes~~ done (90d1c43c) | fe-ops | — |
| U2 verifier plot, "Needs you" cards with Re-send / Open, plane matrix, Pause, retry on no ACK | fe-ops | — (api-ops M26 2b50e7d1) |

### Contacts (`Contacts.md`, J4): Live built; detail route pending
| Item | Owner | Blocked on |
| --- | --- | --- |
| D3 outage / maintenance bands (K1 already draws them from S7) | fe-ops | — |
| ~~`ops.contact` route~~ done: redirects to the drawer (abc4b36e) | fe-ops | — |
| `sc any` filter chip, "highlight queued uplinks" | fe-ops | — |
| D2: queued requests bound to the pass, state trail; ~~`Release`~~ done (a311cc8a); `Swap station` out (#68) | fe-ops | — |
| ~~D4 "Needs a decision"~~ done (cab58d3d) | fe-ops | — |
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
| ~~Telemetry `Dashboards ↗` → existing pages (#11)~~ done (718fd269); empty state's three suggested points | fe-ops | — |
| Timeline: ~~sc scope~~ done (cb5767c9); plane filter (api done); custom range, E1 brush, live prepend + "N new events ↑" (refetch the newest page on the existing `events` invalidation, throttled) | fe-ops | — |

## 3. Scheduling (`ScheduleFlow.md`)

### K0 · Pass prediction: deferred (#4). Nothing to build until server-side propagation.

### K1 · Plan the day (`contacts/plan`): built; gaps against the SchedulePlan board
| Item | Owner | Blocked on |
| --- | --- | --- |
| C · focused spacecraft 24 h strip (rule chips, pass and gap strip) | lead | — |
| Admin `pending_approval` review: `Send back` with a comment beside `Approve and book` | lead | in progress (api c7c7b277) |
| Accepted gaps as `GAP ACCEPTED · <reason>` rows; a sent-back draft says who and why | lead | in progress (api 97523716) |
| Per-contact Requested → Confirmed / Rejected on the Gantt; rejections become Demand rows | lead | — (passes read + `execution`, cf3cd37a) |
| `Drafting stopped at or after 02:31Z` | lead | in progress (api 413c8e18) |
| `PROVIDER FREEZE T−…` header clock | lead | api/domain: no provider freeze time in any read |
| Cost tiles / column: **hidden** (#63). Minutes `/ budget` and D's Link, Max el | lead | a minutes budget setting; Max el only when provider-supplied |
| Done today: U26, U28, U30, U31, U32, superseded, execution header (live check pending, qa) | — | — |

### K2 · Re-plan (`contacts/replan…`): built (fe-setup); gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~`Covered N` tile (#56)~~ done (1f8ff914, d9c614da, 42c27039) | fe-setup | — |
| ~~Hide money (#63)~~ done: K2 showed none (d50ca428) | fe-setup | — |
| Live Propose → Apply after #52/#56 | qa + fe-setup | — |

### K3 · Close the books (`contacts/review`): built (fe-setup); gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~`Export CSV`~~ done, live-checked (review/export.ts); `Monthly close` dropped (#63, ux af1c78d1) | fe-setup | — |
| ~~Hide money (#63)~~ done: R4 Disputable tag/count removed (d50ca428) | fe-setup | — |

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
| ~~C1 diff + stat strip~~ done (30b69efc, live on r3) | fe-setup | — |
| ~~C3 Roll out to~~ built (96256074, 1d5335e6, 0391a9a5; api 34b8cc27, domain 2ef4ca79). 'Request activation' is gone after #65 (ux re-spec: 'Stage rev N for <profiles>') | fe-setup | qa: live check (no catalog change touching 001 before the 11-14 00:33Z pass) |
| ~~Commands vs Telemetry split~~ done (30b69efc); `Replace file`; warnings disclosure *(unverified)* | fe-setup | — |

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
| qa #19: a 5xx on submit reads "Nothing was applied"; should read "unclear, check now" (server side done, domain 33529f29: `:apply_interrupted`) | fe-setup (copy), then qa closes | — |
| Now P3 row when a set sits > 24 h; Timeline `Config r6 applied` | fe-ops | *(unverified)* |

### Contact planning (`ContactPlanning.md`): built. Money policy fields hidden (d50ca428, #63). Review 6/7 in progress (sort is in; uppercase rule line *(unverified)*). Owner fe-setup.

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
| ~~`New mission` → existing create page; pending route dropped (#64)~~ done (d50ca428) | fe-setup | — |
| Account: password change, active sessions | fe-setup | api: no endpoints |
| `/notifications`: **dropped** (#64; the Now attention queue is the notification surface). Route and menu item removed (lead) | — | done |

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
1. ~~Contact plans: send back, `approval`, run `stopped_at`~~ done (c7c7b277, 97523716, 413c8e18).
2. ~~Catalog: server-side revision diff + breaking rules; `command_count` / `telemetry_count` on `current_revision`~~ done (cab661fe; revision list rows keep null).
3. ~~People: role change, remove member, activity; invitations; service identities~~ done (api).
4. ~~Account: password, sessions; provider history~~ done (api). (Console mission create dropped, #64.)
5. ~~Readiness `recent_changes`~~ done (api).
5b. ~~Events read: a `plane` filter (Timeline)~~ done.
6. ~~Billing terms + budgets~~ out of scope (#63).
7. ~~K3 Export CSV / Monthly close~~ not needed: CSV is client-side; Monthly close dropped (#63, ux af1c78d1).
8. qa #19: map domain's `:apply_interrupted` (33529f29), in progress (api).
8b. ~~qa #42 verify race~~ done (32b945f3, DECISIONS #72; api-ops reviewed; both follow-ups in: call-site lock tests and the global mission-then-attempt order). Waiting: the :4011 restart, then qa's 'Accepted on board' rerun on 023's next pass, and the port to `develop`. (#38 release targeting verified live 21:15Z, issues 3953f19e.)

**api-ops** (director, in this order)
1. ~~M26 retries + verifier series (Uplink U2)~~ done (2b50e7d1).
2. ~~M8 `spacecraft:<id>` topic~~ done (d79aaad4; Investigate live tail f38a4dfb).
3. ~~Contacts Release~~ done (50c5e572, 04755d23; fe-ops a311cc8a, d43d2315). Swap station out (#68).
4. ~~Catalog revision number~~ already there: `GET /command-catalog` basis carries `catalog_revision`.
5. ~~Investigate Uplink tab read~~ done (aa1f493e); Telemetry tab needs no new endpoint (M23 + M10 + M11 + M8, agreed with fe-ops).
7. ~~Investigate Configuration tab read~~ done (8d8f5c83).
6. ~~Timeline live prepend topic~~ not needed: `invalidate` with `events` already fires on mission:<id> (api-ops); a row push only if ux wants it.

**api** (moved from api-ops, director rebalance)
9. ~~M22 conflict/gap findings (Contacts D4)~~ done (985c00dc; fe-ops cab58d3d).
10. ~~A1 current values + prior requests in the request brief~~ done (4f9cd275, a4c0e807).
11. ~~M24 encode preview~~ done (4d0255f3; fe-ops 90d1c43c).
12. ~~Now queue sources `missed_pass`, `station`~~ done by api-ops (81a4c8d0; fe-ops de131e9b). `flight_event` landed (a02c2cee, 1b3be7f7, e07969bb; flight-events.md §3a as built, 291744b7); closes when qa sees a row live.
13. ~~Investigate History (c839d0b9) and Passes (324428aa) reads~~ done; fe-ops History d80c8d5d. ~~Compose draft persistence~~ done (a4d19e69). Waiting: palette search endpoint.

**domain**
1. ~~qa #34~~ done (#59, e683b3e2).
2. ~~qa #19 server side~~ done (33529f29).
3. Catalog-path generations (#36), which unblock Catalog C3 rollout. Plan to the director first.
4. ~~Spacecraft archive model (#50)~~ done (7dbd3994, e0232291, 5ee6d6e8; rollback of create verified c8526c57).
4b. ~~Reconciler give-up~~ fixed (292c8e6b: a raising reconcile is rescued as `reconcile_crashed`, polling continues). Original: the mission runtime reconciler has crash-looped since the 22:14Z restart (`binary_to_existing_atom("criteria")` in `MissionModel.Reference.new`). No runtime spec, so no spacecraft ingress. No live remedy during the #65 pass (director). Then one qa restart, plus an `active_spec` check in the runbook.
4c. ~~`mission_runtime` attention source~~ landed (7a6c596a; fe-ops row 751ac5f5; `MissionRuntimeStatus` 292c8e6b; `/counts` runtime api-ops c69f0578). Live on :4011 since 00:57Z (gen 8 applied on boot, so no item open).
4d. ~~`contact_settlement` journal off and acknowledging a lost item~~ landed (96307ac5, e99cd89d; fe-ops 171ecd43, bbe5e8fe).
5. ~~#71 `contact_settlement` attention source~~ landed (9e8145fa, 551cb796, 8f7066b1; live on :4011 22:14Z; fe-ops reader 14330a4a). Replay follow-up next.
6. ~~#71 replay~~ landed (1d6be29f; reloaded on :4011, no restart): one replay per mission, 30 min deadline, backoff 5 min doubling to 2 h, manual after 6 failures, `POST …/retry` (409 `retry_not_manual` / 404 / `operate_mission`); also drains journals on disk that were never inspected (pre-#71). fe-ops copy c10265fd.

## 9. Deferred by decision (not backlog)
#2 roles/Cedar · #4 propagation (K0, ground track, umbra, sky plot, max elevation) · #5 procedures ·
#7 command policies read-only in v1 · #8 command waves/gates · #9 catalog impact / used-by ·
#11 dashboards last · #63 billing/money · #15 profile limits and VC/FEC/randomizer fields · "save as group" on Compose.

## 10. Answered (DECISIONS #63/#64)
1. **Billing:** out of scope (user). Money panels are hidden, not "not reported"; layouts reflow (U34).
2. **Compose layout:** ux rules; default accept as built.
3. **Investigate:** the five tabs link to the existing pages for now.
4. **Notifications** dropped; **New mission** links to the existing create page.
