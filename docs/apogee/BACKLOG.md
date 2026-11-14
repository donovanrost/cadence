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
  - **Also from 11-13 23:00Z to 01:00Z (director):** no saves to `config/`, `mix.exs` or `mix.lock`,
    and no dev-env `mix` at all (it was already banned while :4011 runs).
  - **Until the pass:** don't abort the queued group (it shows as queued in Commanding), and no
    catalog change may touch 001 (it would cancel the command). Catalog step 4 (the other 499)
    lands after 11-14 or must not touch 001.

- **Reservation-window change reverted before the pass (director 11-13):** domain's cfe2e95fa (window follows the accepted snapshot) failed reservations when a timing shift crossed the old activation window; reverted as 40873a5a2 (qa reloads, confirms 001's _39GIA). The fixed version (window and the snapshot's own activation_window together, with a +60 s shift test) re-lands after 11-14 01:30Z through qa. Until 01:00Z nothing on the reservation, contact or uplink path lands without qa's OK. The two failed 008 test rows stay as they are.

- **P9CS result (11-14 00:35Z, qa):** released ~73 s after AOS into the right contact, no pre-AOS release; Uplink started, Accepted on board (0.55 s, the #42 path) and the on-board effect (HK.sc_mode 4 from 00:35:09.75Z, held) all PASS. **FAIL:** the 'Mode applied' verifier (equal 4) timed out with no match although matching samples landed inside its window. Cause confirmed (domain write-up 00:41Z): verifier_evaluation.ex matches the subject only against point_id/point_name, never sample.semantic_id, so every mission-model telemetry verifier times out; develop and main are identical (production affected). Fix: one shared Sample.subject_refs/1 for the verifier and constraint matchers, tested on tonight's exact sample shape (domain; after 01:00Z through qa), gated by an in-node replay of tonight's samples (no writes); develop port right after landing; main built and evidenced in parallel, ready when the user agrees (director raising it as the case for porting non-security fixes); a live no-op SET_MODE on a non-001 pass later. Side issues for later: the transmission-constraint check and the U2 plot read Postgres samples (empty here). **After LOS (qa):** SCIENCE held to LOS; the contact closed and settled. New, after 01:00Z: (1) the first dispatch failed with eaddrinuse starting the provider listener (provider_profile_i4467s4fie_3F; probably 005's overlapping pass), causing the 73 s delay; overlapping passes on one profile, domain; (2) one ingress persistence_failed at 00:39:09Z (error_class unknown, possible TM loss), api-ops; (3) PointCatalog parameter_id nil for HK.sc_mode, likely by design (DECISIONS #73: parameter_id comes from the mission-model plan), domain confirms in one line.

- **Uplink dispatch has no clock gate (domain 11-13; director: fix after 01:00Z):** ReleaseTargetSelection releases to a :defined/:active contact by lifecycle only. Director approved (i) a dispatch-time window gate and (ii) closing the command window when an accepted change drops the uplink leg, as release-path work after 11-14 01:00Z through qa with tests, then develop/main ports. Tonight: no release-path code. domain: P9CS can't release into its planned pass before AOS (no realized contact until then; admission needs its uplink session), but from not_before 00:25Z it would release into any other releasable 001 contact. Guard: qa's read-only check at ~00:20Z and 00:25Z that 001 has no realized :defined/:active contact (domain's query), and nobody starts a 001 contact by hand before AOS (director-approved, broadcast); qa also watches every minute 00:25Z→AOS. **15:29Z:** the check found three stale realized 001 contacts still 'defined' (11-09/11-10, telemetry_downlink). A release needs an {:uplink, :selected} path; qa verified 15:34Z: precise query 0 rows; each has only a downlink path, so none is a release target; left unchanged for the post-pass sweep. Cause: a failed runtime start after realization leaves an orphan 'defined' contact (the expiry sweep only covers 'active'); domain's post-pass fix: sweep defined past window, a one-off orphan sweep, plus the clock gate. **00:20Z/00:25Z runs (director):** both the broad query and a precise one (defined/active WITH {:uplink, :selected}); only a precise hit triggers the fallback. Post-pass orphan fix approved (sweep, one-off cleanup, clock gate; develop/main ports). **Fallback (director):** if a realized 001 contact with a selected uplink path is found, qa closes it through the normal end-contact path; if that can't be done cleanly by 00:24Z, qa cancels P9CS, since a lost test beats a release into the wrong contact.

- **Template-version duplicates (domain 11-13; director's go):** editing a requirement template bumps its version, and occurrence identity includes the version, so a fleet run re-materializes days already generated (no dedup). EARENDIL-001's template phouvt4y5m_I (v6) is NOT paused (the director reversed the pause: no state change on 001 before the pass). qa found no active automation grants, so a second 001 booking would need a manual draft, approve and execute. Rule until 11-14 01:00Z: no contact-plan drafts, plan approvals or automation horizons touching 11-13, or 11-14 before AOS; no template edits. Narrower than first thought: ContactPlanning.TemplateSupersession cancels the older version's active, unstarted, not-taken-up requirements after each materialize. Duplicates remain only when (a) the old requirement is already in a plan past draft, or (b) it has already started at catch-up; domain's post-pass fix covers those two, plus develop/main evidence. domain's fix brings develop/main evidence of whether production is exposed.

- **A lib save isn't live on the next request (qa 11-13):** three times today the :4011 reloader didn't recompile on ordinary requests (and never retries after a broken compile). If you need a save live, ask qa for an in-node `Phoenix.CodeReloader.reload(CadenceWeb.Endpoint)` (runbook 9b8e3197e). A save that doesn't compile still takes :4011 down (09:59Z), so compile under `MIX_ENV=test` first.

- **Legacy pages (director 11-13):** the old LiveView pages are being deleted. No new features in them; bug fixes only if something live depends on them. §11 lists what still exists only there.

- **:4011 outage 11-13 03:45:59Z → 04:12:48Z** (dev-env mix builds in the shared tree purged `Cadence.Repo`). Back with gen 8, `modified_modules` [], P9CS still queued. Rules since: Elixir checks only with `MIX_ENV=test` (check-slot enforces it); dev-DB migrations through qa (in-node `Ecto.Migrator` or a planned restart). Runbook e53a9c00. The queued commits went live early with that restart; qa #51 verified (Audit 1.5 s).

## 1. Next up, per person (the short version)

| Who | Start now (unblocked) | Waiting on |
| --- | --- | --- |
| **lead** | §11 L5 SPA auth screens (sign-in, invitation, no-organization) once api-ops ships L5; L21 switcher footer; dashboards kit asks as they come. Done today: L6 admin-mode client (3b819ce1, lights up with api-ops' endpoint), shared 429 countdown (8f189986), `ApSheet` side placement (886feb41), shell cockpit exports (5faabdac), K1 booking reasons + next steps (3eba781e), K1 clock expired-offer rules (eed357e4), per-contact booking (47ef6310), gap effect (7d7221ff), C panel measures (4d80d394), offer clock (4b58ff8c), phone search (6f7e3f87), §11 inventory and DECISIONS #75/#76 | api-ops L5/L6 endpoints |
| **fe-ops** | In order: Mobile GO block (§5); §11c checks (`/spacecraft/:sid/commanding` interpretation on the configuration tab; legacy commanding stage-only features); then §11 L14 provider-change decisions (with api) and L20 Explore empty-state links (ux ruled: four links, no api). Done today: B1 add points / resolved (e12c5111, 193a6816), B4 (e6865967), U39 stale change sets + Timeline config link (0078e4f6), ux §7 #13–#17 (bfc49b37, 8aa49203), Fleet in-contact + Next contact on Fleet and Alarms (3ebcc9f8), Now tile links (b2792cd9), dialogs on `ApSheet` (a0069f2e), D4 fold (4ade99dd), Now h1 (b94b0163), palette hooks, U2 Needs you | — |
| **fe-setup** | In order: #19 lift (framing editable; callout only when ST1 has `profile_framing_generations` off); ux §7 #3; New profile + Duplicate as new profile; R2 `Compare revisions` link; Audit kind chips + `Export CSV`; the console contact requirement form (with `max_gap_seconds`) once api 8g lands. Done: ux §7 pass 1 fixes incl. the `org.people.invite` and `catalog/:databaseId` redirects (b42b2358, 7fe01991, 02e87cee), P4 tiles (b136754d), Audit actor select (d21aad0b), R2 (d03eea14), P1/P4 (217feb23), Compare (8b58f513), Keep mine / Take live (3ced6cea, 433bcd0f), Command policies (11374b5a) | qa: C3 live check |
| **ux** | Review lead's new copy in code (K1 C panel 4ea2e4e7; Palette groups c45fd134, Recent / Searching… b2830045); then rule the mobile search sheet (§5: spacecraft, alarms, requests) before lead builds it. Done: §7 board review passes 1 and 2 (reviews/2026-11-12-s7-boards.md; fixes b42b2358, 7fe01991, 02e87cee, 2d94506d, 4ade99dd, b94b0163); rulings U39 (staged changes left waiting), the K1 clock wording, Profile framing editable; Compose C1 accepted (#64) | — |
| **qa** | ~~§6 accessibility sweep~~ done (fd9a30177, docs/apogee/qa/a11y/: 25 of 36 screens clean; routed: kit 8fa0f9e9e, fe-setup (3)+(5), dashboards (4), fe-ops→api command-draft 200 {draft:null} (6), api #53 (7)); re-check the kit fixes at 390; live checks of L4/L2/L3/L11 after the next restart; ~~K1 booking header live check~~ PASS; after the next restart: invitation security fix (748fcbc9 + 49bc1bfc), change_set_stale, requirements form, K1 per-pass booking; K2 Propose → Apply after #52/#56. Done: U31 live PASS (11-13: callout appears, count updates, clears in 1.8 s on Resolve, axe clean) | — |
| **api** | L9 (shaping) → D14–D19 → L15 single bookings (when domain's facade lands; fe-ops' proposal cd842bb2) → revisions by entity (fe-setup History) → L4 → L2+L3 → L17 (+ L22 fields) → L18 → L14 → per-target values (fe-ops) → slice 6 (D20/D23/D24) → library (D21/D22). Done today: 8d 947cc9d8, 8e a6aaa60a, 8g + close/cancel fb7510be, 8f 098a3fd8. Done: C3 rollout read + profiles `catalog_revision` (34b8cc27). Done: #42 port to `develop` (f9d89f83). Done: #42 verify race 32b945f3 (advisory lock, mission-then-attempt order, timeout reconcile, call-site tests; api-ops reviewed); Compose drafts a4d19e69 (`GET/PUT/DELETE /missions/:id/command-draft`, migration). Next with the director | — |
| **api-ops** | ~~Main evidence rerun~~ all PASS (partition 25 from main's own migrations: #81 10/10, #79 40/40, #75 22/22). Then L4 after 01:00Z. Earlier: ~~L7~~ (f50da0b2) → the L5 302s (go given) → dependency audit (triage table first; mint → runtime → dev-only) → ~~L11~~ (2e3c8c5ab) → data-sources develop/main ports → the director's security batch (L1 run_id, L3 dashboard authz, L4 policy mission ∈ org; L2 done abeca3a80) → L12–L13 writes → the legacy dashboards redirect after qa's smoke PASS. Done today: C1 30295106, L5 JSON e3c5d19b, L6 a3cf61b0, attempt limit + account audit 2ba5cd57 (qa PASS), invitation security fix + develop port (PR #54), qa #51 + prune, M26, D1–D6 + D4 default | — |
| **domain** | Ports of the dashboards readiness fix 46a02f740 (develop branch; a main answer to the director first) → ~~L15 single bookings~~ (237baf01f; develop port merged #76, main #77 waits on the user) → post-L15 batch (~~a freshness gate + c breaker~~ d2dec0178: Postgres pool errors under a TSDB source are a platform-store failure (`details.cause: platform_store`), no longer trip the circuit or write 'unavailable' health; ~~b probe~~ 1b4902845: a failed schema query reports no capabilities; d activation fail-safe (A+B+C done, C 9b8456132: manual audited resume under the execution lock; `activation_apply` Now source; api wraps the endpoint, fe-setup 'Retry apply' (U41 on the review page, 0a7a3492f, behind ACTIVATIONS_LIVE), ~~fe-ops Now item~~ (32aee5864; needs approved_by/approved_at, retryable and P1-when-runtime_not_applied from api); develop port next, load-gated; then dashboards Q6): a 500-craft activation runs ~2,000 queries in one 15 s transaction and can end half-applied with the execution stuck :in_progress; director approved A remove the quadratic queries, B record :failed (`activation_execution_interrupted`), C a manual audited resume under the advisory lock + a Now attention item, no automatic sweep without the user; develop gets A+B (+C) as a director-pushed branch; main waits on the user's non-security-fixes decision; C's shape: fe-setup in plans/activations.md, api endpoint, fe-ops Now item): the managed source adapter's capability report (a latent downgrade hazard on the next probe), qa's freshness question, the dashboard read path letting a slow Postgres lookup trip the TSDB source circuit (source_unavailable under load; likely 007's 11-12 'No data in this range'), and the fleet tests '500 spacecraft activate together' / '550-spacecraft fleet' dropping their Postgres connection under load (`tcp recv: closed` in ControlActivations.execute → TelemetryDecom.applied_configuration_ids; predates L22; develop CI passes the 500 test in 19.9 s, so locally it's load; the 550 test hasn't been through CI): the real question is whether an activation that loses its DB connection mid-way fails safe (rolled back, runtime not told) and retries cleanly. Check the transaction boundaries in ControlActivations.execute and why connections drop, before touching any timeout → dashboards Q6 → L9 B (#77). Done today: L22 (a78eb466, 9251b745, 20d1933d8; baseline A B A B 11-13: no L22 regression, B faster in both pairs; the 2 fleet tests fail in all 4 runs incl. pre-L22), dashboards StatelessAuthoring + Q1, #74, booking fixes, XTCE fix, runtime invalidation f0570c8e, readiness 46a02f740 | — |

## 2. Ops

### Now (`Now.md`, J1): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Stat tiles link (Critical/Caution/Stale → Alarms/Fleet, In contact → Contacts, Uplinks → Commands)~~ done (b2792cd9 on `ApStatTile` `to` 86187004) | fe-ops + lead | — |
| ~~Queue kinds `missed_pass`, `station` + `Station` → Re-plan~~ done (de131e9b); `flight_event`: source landed (api-ops a02c2cee, 1b3be7f7, e07969bb), fe-ops reader 591bc06c | fe-ops | qa: a flight_event row seen live after the :4011 restart |
| ~~Attention source `contact_settlement` (#71) reader~~ done (14330a4a, U37 words, no Acknowledge, Review opens Contacts by contact_id); unknown kinds/sources now drop one row, not Now | fe-ops | — (source live 22:14Z) |
| ~~`contact_settlement` manual retry (#71 replay): needs-operator line, `Retry storing`, 'Next try at HH:MMZ.'~~ done (c10265fd; ux 294e67c6) | fe-ops | — (domain ships the manual state after 00:30Z) |
| ~~Attention source `mission_runtime` row (U38)~~ done (751ac5f5; reasons spec_mismatch, reconcile_crashed, runtime_not_running, apply_failed) | fe-ops | — (domain cleared to ship) |
| ~~Mission-wide runtime banner (U38 4f8b796c): crit strip under the top bar on every mission page, Ops and Setup, not dismissable, `Details` → Now's row; turns nominal for 5 s on resolve~~ done (e585d19c, d8102e0d, f21e8aa1) | lead | — (`/counts` runtime api-ops c69f0578; live on :4011 since 00:57Z) |
| ~~`contact_settlement` journal off (U37 lost) and `Mark as seen`~~ done (171ecd43, bbe5e8fe) | fe-ops | — |
| ~~Header meta names the worst station issue~~ done ('SVA down since 01:10Z (+1)', 06b2abcd) | fe-ops | — |
| ~~A4 pass bars open the contact drawer~~ done (51cc6133) | fe-ops | — |
| ~~Approval rows open the request's review~~ done for a single group (a0e33fe1) | fe-ops | — |
| ~~New P1 rows slide in / flash~~ done: a new crit P1 flashes once, no slide (06b2abcd; design-language §6) | fe-ops | — |

### Investigate (`Investigate.md`, J2): J2 tab built; five tabs not started
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Telemetry, Uplink, Passes, Configuration, History tabs link to the existing pages (#64)~~ done (0d05d195); build later | fe-ops | — |
| ~~B1 add points (chips, max 3, search this spacecraft's points)~~ done (e12c5111) | fe-ops | — |
| ~~No active alarm: show the latest resolved alarm "back in limits"~~ done (193a6816) | fe-ops | — |
| ~~B4 sisters: plane ring, sparklines, next AOS~~ done (e6865967) | fe-ops | — |
| ~~Live chart tail~~ done (f38a4dfb); ~~live event log~~ done (e62f05fe: refetches on the `events` and `alarms` invalidations) | fe-ops | — |
| ~~`FULL TIMELINE →` carries `?sc=`~~ done (cb5767c9) | fe-ops | — |

### Command a group / Compose (`Command.md`, `CommandFlow.md` C1): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Compose layout: ux rules; default is to accept Command.md's C1–C5 as built (#64)~~ accepted as built (ux 198d12ca; fe-ops b8fe16e0) | ux | — |
| ~~Draft autosave / `Save draft` / `DRAFT SAVED`~~ done (c0510343, e262c233; ux 601a32f9; api a4d19e69) | fe-ops | — |
| Per-target values (Same for all / Per target, Paste CSV, Now column) | fe-ops | api: the group create body has one argument set per command (fe-ops sent api a proposal) |
| ~~Verifier line / "No verifier: this command can't turn green"~~ done (b8fe16e0) | fe-ops | — |
| ~~Keep/Drop callout when a target leaves a live query~~ done (fd776880) | fe-ops | — |
| ~~Reorder: move up / down, drag and Alt+↑/↓~~ done (f2085bfd, fd776880) | fe-ops | — |
| ~~`CATALOG rev N` meta~~ done (531715e4) | fe-ops | — |
| ~~`ABORT AVAILABLE UNTIL…` caption~~ done: 'Abort available until each uplink starts' (fd776880) | fe-ops | — |

### Approve and Uplink (`CommandFlow.md` C2/C3): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~A1 `5.0 → 8.0` readout, histogram of current values, hand-set overwrite callouts~~ built (512c96f2 on api 4f9cd275, a4c0e807) | fe-ops | — |
| ~~A3 encoded packet bytes~~ done (90d1c43c) | fe-ops | — |
| ~~U2 verifier plot, Needs you cards, plane matrix~~ done (c64fb2d1, 0ea3b97b, 23fa7147); ~~Pause~~ dropped (lead 11-13: no group pause or held state server-side, none planned; Abort covers 'stop the rest'); retry on no ACK out (#69) | fe-ops | — |

### Contacts (`Contacts.md`, J4): Live built; detail route pending
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~D3 outage / maintenance bands (K1 already draws them from S7)~~ done (181fb5d1) | fe-ops | — |
| ~~`ops.contact` route~~ done: redirects to the drawer (abc4b36e) | fe-ops | — |
| ~~`sc any` filter chip, "highlight queued uplinks"~~ done (6e378485 on kit dim/notch ba5d4773) | fe-ops | — |
| ~~D2: queued requests bound to the pass, state trail~~ done (c5117566); ~~`Release`~~ done (a311cc8a); `Swap station` out (#68) | fe-ops | — |
| ~~D4 "Needs a decision"~~ done (cab58d3d) | fe-ops | — |
| ~~`Book passes`~~ done: the header shortcut to Plan (8a442858); planned booking is K1, single bookings L15 | fe-ops | — |

### Query line ⌘K (`Palette.md`, J5): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Commands (`>`) and Stations (`@`) groups~~ done (c45fd134; fe-ops hooks 63588467, 7807e12b) | lead + fe-ops | — |
| ~~Recent items on empty query, `SEARCHING…`, Setup-mode ranking~~ done (b2830045) | lead | — |
| One server search endpoint instead of client-side fleet search | api-ops | ask when fleets exceed the client list |

### Fleet, Alarms, Telemetry, Timeline (`OpsLists.md`): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| Fleet: ~~"in contact" filter, Next contact column~~ done (3ebcc9f8); past 200 rows: no virtualization (fe-ops measured, 11-13); the 1 s clock in Last TLM / Next contact moves to a 10 s tick | fe-ops | — |
| ~~Alarms: group identical point+condition across spacecraft~~ done (784726fc), ~~Next contact~~ done (3ebcc9f8), ~~"Last cleared…" empty state~~ done (784726fc); ~~#20 Source column clipped~~ fixed (ApTable scrolls in its panel); Cleared tab visual re-check once something clears on :4011 | ux (browser pass) | — |
| ~~Telemetry `Dashboards ↗` → existing pages (#11)~~ done (718fd269); empty state's three suggested points | fe-ops | — |
| Timeline: ~~sc scope~~ done (cb5767c9); ~~plane filter~~ done (97e12555); ~~custom range, E1 brush~~ done (6c123796); ~~live prepend + "N new events ↑"~~ done (0521f407) | fe-ops | — |

## 3. Scheduling (`ScheduleFlow.md`)

### K0 · Pass prediction: deferred (#4). Nothing to build until server-side propagation.

### K1 · Plan the day (`contacts/plan`): built; gaps against the SchedulePlan board
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~C · focused spacecraft 24 h strip~~ built (4ea2e4e7, 4d80d394 server measures; alternatives 'Longest gap 6h10 → 3h05' 7d7221ff) | lead | gap HOLD after domain 7b (#74) |
| ~~Admin `pending_approval` review: `Send back` with a comment beside `Approve and book`~~ done (cd7b3fcb; api c7c7b277) | lead | — |
| ~~Accepted gaps as `GAP ACCEPTED · <reason>` rows; a sent-back draft says who and why~~ done (cd7b3fcb, 9df61cc0; api 97523716) | lead | — |
| ~~Per-contact Requested → Confirmed / Rejected on the Gantt; rejections become Demand rows~~ built (47ef6310) on api 8e's agreed shape; lights up when 8e ships | lead | api 8e (built, shipping with 8d); ux: words for provider reason codes |
| ~~`Drafting stopped at or after 02:31Z`~~ done (cd7b3fcb, copy 9df61cc0; api 413c8e18) | lead | — |
| ~~K1 header clock `NEXT OFFER EXPIRES T−… · KSAT`~~ built (4b58ff8c; domain c38bb5de), with detail, providers and 'N more offers expire in the next hour' | lead | ux: OK the expired-offer wording |
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
| ~~R2 Recent changes (latest revisions, `All revisions →`) and the subline's latest change~~ done (d03eea14; api e7ac418d); `Compare revisions` link from R2 (Compare exists, 8b58f513) | fe-setup | — |
| ~~pass-1 #8 copy (Apps tile names missing apps, Catalog wording)~~ done (api d3a9e123; Install 995ba6d0) | fe-setup | — |

### Add spacecraft (`AddSpacecraft.md`, S2): mostly built
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Step 03 routing summary from the profile's rules~~ done (a935be0b) | fe-setup | — |
| ~~NORAD id on the profile path~~ done (a935be0b); ~~`New profile` link in the picker~~ done (ce12d02d) | fe-setup | — |

### Catalog (`Catalog.md`, S3): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~`setup/catalog/:databaseId` route (pending)~~ redirects (fe-setup, ux §7 pass 1: b42b2358, 7fe01991, 02e87cee) | fe-setup | — |
| ~~C1 diff + stat strip~~ done (30b69efc, live on r3) | fe-setup | — |
| ~~C3 Roll out to~~ built (96256074, 1d5335e6, 0391a9a5; api 34b8cc27, domain 2ef4ca79). 'Request activation' is gone after #65 (ux re-spec: 'Stage rev N for <profiles>') | fe-setup | qa: live check (no catalog change touching 001 before the 11-14 00:33Z pass) |
| ~~Commands vs Telemetry split~~ done (30b69efc); ~~`Replace file`; warnings disclosure~~ done (e343f9d3: import verdict, 'Show N warnings', failed → Diagnostics) | fe-setup | — |

### Profile (`Profile.md`, S4): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~P1 edit + P4 staged aside (`Stage edit`, `Changes N / Keeps M`)~~ done (217feb23, b136754d) | fe-setup | — |
| ~~The #19 read-only framing callout is stale~~ done (b2f92dba3): #19 is lifted (domain: `profile_framing_generations` defaults on, #45). Drop it; show a note only when a mission has turned that setting off in ST1 (profile framing then doesn't reach ingress) | fe-setup | — |
| ~~`New profile`, `Duplicate as new profile`~~ done (ProfileNewScreen, newProfile.ts) | fe-setup | — |
| List: ~~Overrides, Last changed columns~~ done (2646dcf5 on api 890412a6); ~~Limits notice~~ done; ~~History field diffs and per-version counts~~ done (a15664580 on api c3b07440d); ~~Compare~~; ~~pin~~ dropped (ux); ~~conflict chip~~ done | fe-setup | — |

### Staged changes / revisions (`Changes.md`): mostly built
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Compare revisions (`r4...r6`)~~ done (8b58f513) | fe-setup | — |
| ~~`Keep mine` / `Take live` on conflicts~~ done (3ced6cea, 433bcd0f) | fe-setup | — |
| ~~Top bar runtime state and the Changes outcome's runtime line~~ done (ba5ad77a, ux words: `CONFIG r6 · APPLYING` / `NOT APPLIED`, outcome 'r6 is active and the runtime has applied it'). ~~Staged bar 'APPLYING · N OF 5 STEPS' / 'Apply failed'~~ no source | fe-setup | — (domain f0570c8e publishes on each generation step) |
| ~~qa #19: a 5xx on submit reads "Nothing was applied"; should read "unclear, check now"~~ copy done (c16546c4; domain 33529f29) | qa closes | — |
| ~~Now P3 row when a set sits > 24 h; Timeline `Config r6 applied`~~ done: P3 row 947cc9d8 + 0078e4f6; Timeline shows `config_revision_applied` ("Applied r9 · 1 change", seen live 11-13) and `config_revision_rolled_back` ("Rolled back to r4"), linked to Setup › Revisions (0078e4f6) | fe-ops | done |

### Contact planning (`ContactPlanning.md`): built. Money policy fields hidden (d50ca428, #63). ~~Review 6/7 (template sort; rule line without uppercase, `6h 00m`)~~ done (238a1b06). Owner fe-setup.

### People & access (`People.md`, S5): partial
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Command policies tab (U4); `GET /command-policies` (O4)~~ done (11374b5a; copy a4b42eca) | fe-setup | — |
| ~~`org.people.invite` route~~ redirects to People (fe-setup, ux §7 pass 1); ~~`org.people.services`~~ wired to the Services tab (19b2ba55) | fe-setup | — |
| ~~Person page (Access, Activity, change role, remove)~~ done (f9e79c71; api 1b4defb8, activity `GET /audit?actor_id=`) | fe-setup | — |
| ~~Invitation Resend / Revoke; service identity create / rotate / revoke (secret shown once)~~ done (f9e79c71, 19b2ba55) | fe-setup | — |

### Settings, Audit log, Provider accounts (`SettingsAuditProviders.md`): built; gaps
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Settings: section-level override~~ done (ux 823e4f7a1): the source tag on the section header, `Override for this mission` on an inherited section, `Use the organization's settings` on an overridden one | fe-setup | — |
| Settings per-field override (**director 11-13: after api's three items; governance/approval fields stay explicit overrides in the migration, never auto-collapsed; a dry-run report per mission for qa and the director before the real run**; ux: no per-field Override / Reset to inherited until this lands): the mission document stores only the overridden paths; effective = the org value merged with them; each field's source is mission, organization or default; null removes the path. Plus a migration of today's full-copy overrides to sparse ones (a diff against the org value). api's estimate: half a day plus the migration | api | lead to schedule |
| Audit: ~~actor filter~~ done (d21aad0b); kind chips (a Kind select exists), `Export CSV` | fe-setup | export: api or client-side |
| ~~Provider accounts: version history~~ done (2fdd2692, dded6585) | fe-setup | — |

### Org / account
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~`New mission` → existing create page; pending route dropped (#64)~~ done (d50ca428) | fe-setup | — |
| ~~Account: password change, active sessions~~ done (a3df522d; api 386438bf) | fe-setup | — |
| ~~`/notifications`~~ dropped (#64; the Now attention queue is the notification surface); route and menu item removed (96c5dda2) | — | — |

## 5. Phase 4 · Mobile on call (`Mobile.md`, J6)
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Alarm page "Your GO is requested" block (GO / NO-GO + confirm sheet)~~ done (ca6fccb0) | fe-ops | — |
| ~~Mobile Approve layout (GO opens the desktop takeover today)~~ done (235e2b42; kit commit button 48px on phones 6112a828) | fe-ops + lead (shell) | — |
| ~~Search as a full-screen sheet limited to spacecraft, alarms, requests~~ done (6f7e3f87, ux ruling 68d12603) | lead | — |
| ~~"N sisters in P07 trending"~~ done as 'N sisters in P07 out of limits' (3330f6c2, honest wording) | fe-ops | — |

## 6. Phase 4 · Accessibility pass
| Item | Owner | Blocked on |
| --- | --- | --- |
| axe + keyboard traversal + focus order on every route, 1440 and 390, as admin and member; file per screen | qa | — |
| Fixes per screen | the screen's owner | qa's findings |
| ~~Kit-level fixes (focus trap/return, scrollable regions, contrast on hatches)~~ done: `ApSheet` trap/return (86187004) and focusable scroll body (ffeecd46), ApPanel scroll bodies, hatch labels on a solid base (U30 #4). Sweep 11-13: scrolling ApTable and the ApTakeoverHeader steps row get tabindex, role and a name while they scroll (8fa0f9e9e) | lead | — |

## 7. Phase 4 · Visual review and dashboards
| Item | Owner | Blocked on |
| --- | --- | --- |
| ~~Board-by-board visual review~~ done (reviews/2026-11-12-s7-boards.md: pass 1 in a browser, 11 findings fixed; pass 2 by code and spec, five Lows to fe-ops). Audit log and org Settings tabs are unverified without a browser: CI captures or qa | ux | — |
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
8. ~~qa #19: map domain's `:apply_interrupted` (33529f29)~~ done (config_json 503; fe copy c16546c4). qa closes.
8c. ~~Port the lane fix to `develop`~~ built: `fix/lane-session-recovery-wait` 341c80531 on develop 08d5c2acb, unpushed, with the director.
8d. ~~Now P3 "change set staged > 24 h" attention source~~ done (947cc9d8; fe-ops 0078e4f6), and Timeline `config` events for applied revisions ("Applied r6 · 2 changes", "Rolled back to r4"; the Audit read has them, organization_audit.ex). Check first what exists; send fe-ops the shape before shipping (lead, 11-12).
8e. ~~K1 per-contact booking state~~ done (a6aaa60a, with detail / retryable / retry_after_seconds / resolved; lead 47ef6310, 3eba781e): plan detail `passes[].booking {state: never_sent | confirmed | uncertain | rejected | failed, reason, at} | null`; `sent` dropped (it's the umbrella in the counts); reason `sending` while requesting. Joined within the approved version.
8f. ~~Profile kind schema for New profile~~ done (098a3fd8; fe-setup e15333bd).
8g. ~~Console requirement writes (create + new version) + list + close/cancel~~ done (fb7510be). fe-setup then builds the console requirement form with `max_gap_seconds` on it. About 1-2 days across api and fe-setup.
8b. ~~qa #42 verify race~~ done (32b945f3, DECISIONS #72; api-ops reviewed; both follow-ups in: call-site lock tests and the global mission-then-attempt order). Ported to `develop` (f9d89f83). Waiting: qa's 'Accepted on board' rerun on 023's next pass. (#38 release targeting verified live 21:15Z, issues 3953f19e.)

**Security dependency (api-ops, 11-13):** `mix deps.get` reports a Bandit advisory (HTTP/2 `StreamError` recovery bypasses per-connection limits). A separate Bandit bump on our branch, `develop` and `main`: **director's go given 11-13**; the team branch only through a qa-planned restart and never 11-13 23:00Z to 11-14 01:00Z (it touches `mix.lock`). The invitation security fix is merged on `develop` (PR #54) and `main` (#57). Bandit 1.12.5 → 1.14.1 (clears all 14 advisories) is ready unpushed: `fix/bandit-security-develop` 28f36112, `fix/bandit-security-main` 6fdcb295; team branch via a qa-planned restart. **Still open (api-ops' audit 11-13):** mint 1.9.3 (6 advisories); decimal, ecto, lazy_html, phoenix_html, plug_crypto 2.2.0, ssl_verify_fun, tidewave (1 each): **Security, data sources (api-ops 11-13):** a cross-tenant write bug in `OpsConsole.Actions.DataSources` (operate_mission only; lookups include platform-shared rows; register upserted). Fixed on the team branch (e80c9d872); `develop` has the same adapter (port = the same commit); `main` is WORSE (the LiveView `ops_data_sources_live.ex` acts on client-supplied ids with no scoping, any org admin): its own fix with tests. Ports ready, unpushed, for the director (api-ops 11-13): `fix/data-sources-cross-tenant-develop` 944bab5d8 (cherry-pick of e80c9d872 on origin/develop d7729d076) and `fix/data-sources-cross-tenant-main` 29fc8d049 (new `OpsDataSourcesLive.WriteGuard` before every write handler, plus credential-belongs-to-source and run-belongs-to-mission checks; on origin/main ec46e7f23); format, warnings-as-errors and credo clean, tests pass. Scan of the other 25 adapters: no high or medium. LOW, with the director: (L1) client-chosen run_id is unique across all orgs (pre-claim DoS, existence probe); (L2) historical backfill read input accepts org/mission nil (trace the writer); (L3) dashboard_workflows authorizes operate_mission while deep actions need author_dashboards; (L4) Policy :operate_mission doesn't check mission ∈ org (defence in depth). Director ruled (11-13): api-ops does ~~L1 fix~~ (8b67492f4, tenant-namespaced run ids; main gets its own L1-only fix with tests: director 11-13), ~~L3 align~~ (89adfa38b), ~~L2 trace~~ (abeca3a80: the backfill stays partitioned by the scope's org and mission on read and write, so no fix needed), L4 policy check (written, reverted from the shared tree, sized in api-ops' own worktree; hot (per live dashboard tick, 3×N on GET /session), so a positive-only (org, mission) cache in ETS; lands through qa after 11-14 01:00Z); develop port ready, unpushed: `fix/run-ids-dashboard-authz-develop` (c2f0a7bf9 L1, b70961ce5 L3, on origin/develop 7a10ae118; client run_id limit 232 → 220 for the suffix); main L1 merged (#79): 53c243f51 + 6d9acdfa6 on origin/main f17157ac6 (too-long ids refused cleanly instead of a 22001 crash; a late-data decision naming another tenant's run id revealed that job's id/status/failure on the dashboard events view, now refused; develop has no client path to it). Job-lookup mission checks done (api-ops ca734fce4: backfill_lifecycle_rows, workflow_corrections) + presentation.ex (6aa74962f); ports ready, unpushed: `fix/job-lookups-mission-develop` (bd2cd1a1d, 810d0985e on 54f5eeab1) and `fix/job-lookups-mission-main` (cd715b2e6, d2c514a2d on c02c113a6, SECURITY), tests 63/63 and 62/62. Note: main's architecture.check exits non-zero because its baseline review date (2026-10-18) expired, which predates these. L4 targeted files 36/36 with the check in place; full suite after the 01:00Z restart. Provider defects all fixed on the team branch (#1 acd119360, #2 eaba50aa5, #3 ed8bf8b6a → 409 `account_archived`, #4 807075074, #5 f7df7d8f1, portable alone); api-ops now on the L13 then L12 endpoints; each its own commit with develop/main evidence. Order: finish L11 → data-sources ports → this batch → L12–L13.

**Dependency audit (director 11-13, api-ops, ahead of L11–L13):** triage each advisory as prod-reachable or dev/test only; order mint → runtime (plug_crypto, phoenix_html, ecto, decimal, ssl_verify_fun) → dev-only; grouped compatible bumps, branch per target, unpushed for the director; lock changes never 23:00Z–01:00Z and on the team branch only via qa; majors or code changes go to the director first. Then devops makes `mix hex.audit` blocking in CI once develop is clean. Bandit: PR #60 (develop), #61 (main, merged).

**api-ops** (director, in this order)
1. ~~M26 retries + verifier series (Uplink U2)~~ done (2b50e7d1).
2. ~~M8 `spacecraft:<id>` topic~~ done (d79aaad4; Investigate live tail f38a4dfb).
3. ~~Contacts Release~~ done (50c5e572, 04755d23; fe-ops a311cc8a, d43d2315). Swap station out (#68).
4. ~~Catalog revision number~~ already there: `GET /command-catalog` basis carries `catalog_revision`.
5. ~~Investigate Uplink tab read~~ done (aa1f493e); Telemetry tab needs no new endpoint (M23 + M10 + M11 + M8, agreed with fe-ops).
7. ~~Investigate Configuration tab read~~ done (8d8f5c83).
8. ~~Account security~~ done (2ba5cd57): `Accounts.AttemptLimit` on every password check (sign-in, Account current password, admin mode), with waits from 1 s doubling to 5 min and no lockout; an unknown email pays the hash; `429 too_many_attempts {retry_after}` + `Retry-After` (fe-setup's reader is in); `account_events` in the Audit log (kind `account`). Live needs a migration + :4011 restart (qa). **Deploy check:** buckets key on `remote_ip`, so behind a proxy that doesn't forward the client address all clients share the IP bucket; per-node memory.
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
3. ~~Catalog-path generations (#36)~~ done (0c615544, a01cf95f, 59a7433c, 450369b9; C3 2ef4ca79; >100 spacecraft 7533d50a; monitoring fixture and end-to-end test 865d51fd). #65 steps 3 and 4 are ops (qa 11-14 00:33Z; step 4 on the director's go).
7. ~~K1 demand measures~~ done (c38bb5de): `longest_gap` (edges count), `uplink_passes` (requested), alternatives' `longest_gap` and `longest_gap_after_seconds`. Lead reads them (4d80d394).
7b. ~~`max_gap_seconds` on contact requirements~~ done (#74). **Follow-up next (domain 11-13):** templates carry it (shape to api + fe-setup first; migration via qa). Original (DECISIONS #74): evaluator hard failure `max_gap_exceeded`, fills `limit_seconds`, counts in `rule_met`. No legacy form change (director 11-13). About 1 day of domain work. Then K1 C's gap HOLD and S4 'closes gap' become real (lead).
8. ~~Provider freeze~~ done (c38bb5de): `provider_freeze {at, provider, snapshot_id, by_provider}` and `passes[].expires_at`. Lead builds the 'Next offer expires' clock.
9. ~~UplinkQualification readiness reason normalization~~ done (02f71d649).
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

## 11. Legacy-parity inventory (director 11-13: the old pages get deleted)

Drafted by lead, 11-12, from a read of `router.ex` (lines 89–745), the legacy host app (`frontend/apps/host`, served by `HostPageLive` and `ApplicationHostLive`, writes in `*_page.ex` and `ops_console/actions/*.ex`) and the console's routes and `/api/console/v1` endpoints; plus ux's six "existing page" handoffs. **Rule:** no new features in the legacy pages; bug fixes only if something live depends on them. A page is deleted only when its row is done or explicitly dropped. **Deletion manifest:** `plans/legacy-deletion.md` (fe-setup 4722cb1b0): deletable now L5, L6, L21; after qa's live checks L1+L2+L3 (one batch), L4, L7, L11; blocked L10, L12/L13, L19. Covered-already host pages added (0f4065d98): apps/host can't go whole (LiveVue's vue_root, routes.json, @cadence/plugin-host); not covered yet L14, L15 (off), L17, L18, L22 and L8's pending routes; admin_federated goes with L7; L12's trim also drops the comms provider tabs from the console's L9 host. The 3 legacy redirect controllers still target legacy pages (repoint with each batch). Next: covered-already host pages (§11c) added; Redirects ready (api, branch api/legacy-redirects, unpushed): 53c6cb123 L1+L2+L3, 9fb865e63 L4, 78b406a26 L7, a072ae6cb L11, each landing with fe-setup's deletion of that row; ~~db58dfa61 repoints the 3 legacy redirect-only controllers~~ landed as c1396fba2, qa PASS live 14:57Z. qa's parity (11-13): L1 edit/close/cancel PASS and L2 pause/resume PASS (non-001; pause/activate keep the template version, nothing regenerated); template edits held until domain tests version-keyed occurrence identity after the pass; plan-from only up to the proposal before the pass; L1 plan submit, L3, L4 and L11 writes after the pass; L7 service identities PASS live after api-ops d547ef7e5 (issue shows the token once, rotate, revoke, audit); L7's Create organization click after the pass. Batches: 1 = L5+L6+L21 (tonight, with L8a: fe-setup/legacy-l8a 5ad9c9716..6c9bf6348); 2 = L1+L2+L3+L4 built (fe-setup/legacy-batch2 7172308b5, 8f6b8ce0e with api's redirects; waits on qa's live results, then the director); 3 = L7+L11 (qa: the L7 service-identities bug was fixed in 7fa0edbd8; dead /admin/runtime dropped). The federated planning and mission surfaces keep L1–L4's reads, actions and Missions.Creation: a later federated batch (fe-ops). DECISIONS #79: fe-setup deletes, one commit per row, through qa-planned restarts; first batch L5+L6+L21: qa GO (all console replacements PASS live, 11-13); ready on fe-setup/legacy-batch1 (62c4dc8d5, d4c546c11, bf11315c3; compile clean); fe-setup lands it after 01:00Z right before qa's ~11-14 01:30Z restart; later batches to the director with qa's result. Rulings: DECISIONS #75 (user, 11-13). Owned rows are handed out as queues empty.

### 11a. Missing or partial in the console, with owners
| # | Capability (legacy route) | What's missing in the console | Owner → console home | Status |
| --- | --- | --- | --- | --- |
| L1 | Contact requirements (`/ops/requirements…`): declare, edit, plan from one | ~~Writes, list, form, close/cancel, rule_summary, by-template counts~~ built (api fb7510be, df98dcd3; fe-setup f6abf785, da9ca3a7; close/cancel copy 0dace065, 3d660167). Live with qa's next restart | — | done |
| L2 | Requirement templates (`/ops/requirement-templates`): pause, activate, close | Lifecycle verbs (create/edit exist) | api + fe-setup → `setup.contact-planning.template` | done: UI 48d652840 + api 002e3ed7e (checked against the real endpoints, matches) |
| L3 | Fleet planning policy (`/ops/planning/policy`): automation grant issue/revoke | Grant verbs (policy save/decide exist) | api + fe-setup → `setup.contact-planning.policy` | done: UI 48d652840 + 51a2d65c0 (deleted identity shows its id; 422s shown) + api 12562f5ca (policy_version present) |
| L4 | Mission creation (`/missions/new`) | ~~Done~~: console form (fe-setup 083ec272f) on api's endpoint (7e4aa50bf); `org.missions` no longer links to the legacy page | — | done |
| L5 | Sign-in, invitation acceptance, no-organization | ~~Done~~: SPA screens + JSON, qa PASS live 11-13 (fe-ops da5eabe6, 2136ca04, 53bf72a6, f58d4e53; api-ops e3c5d19b), and the old GET paths 302 to `/console/*` (api-ops ecdddab10; legacy POSTs stay for open pages). The LiveView auth pages can go with the §11 deletion | — | done |
| L6 | Admin mode step-up (`/admin-mode`) | ~~Enter/leave admin mode~~ done: api-ops a3cf61b0 (session.md §Admin mode) + lead's client 3b819ce1, ebfa4b93 (sheet, countdown chip, account menu) | — | done |
| L7 | Platform admin (`/admin/**`) | Screens on the `admin` shell mode (fe-setup a3587d62, d3c82f2d, 0698ba78; lead 8b0f2cd2, 96cb7af7); endpoints + platform-admin audit landed (api-ops f50da0b2; migration with qa) | — | done: readers on the real endpoints (fe-setup 41aef370a); legacy /admin/runtime 'Dashboard Invalidation Decisions' is dead (no writers), dropped with L7 (lead, dashboards 11-13); qa found a console bug: service identities never load (null query key; fe-setup) |
| L8 | Dashboards (spec `ux/Dashboards.md`; `/ops/dashboards/**`, shares, snapshots, playlists, export) | Everything | **User (#75, reverses #11): rebuild in the console, starting now.** Owner: **dashboards** (w0R:pG, brief `briefs/dashboards.md`). Plans first, reports to lead; endpoints via api/api-ops, layout via ux | in progress (planning) |
| L9 | App configuration and app surfaces (spec `ux/AppSurfaces.md`, aed431cb) (`/applications/:key[/:surface]`, federated routes): limits definitions, derived telemetry, CFDP, decom bindings, `request_activation` | A surface host (limits and derived telemetry can't be authored without it) | **User (#75): a console surface host; apps own their UI (managed-application framework). #77: each app's own save semantics now (A); change-set kinds for app config queued for domain (B).** api (surface context + token endpoint, staging/activation through Changes) + fe-setup (host frame, Setup › Apps routes) | host + endpoints built, readers verified against 386c3e54 (fe-setup f6a646f9; api 386c3e54; live after qa's next restart) |
| L10 | Activation approvals for apps (`/ops/activations`) | A reviewer for application activations | api + fe-setup, with L9 | endpoints in (api be59d4f32, activations.md: resume, retryable, `activations` invalidate, Now row); fe-setup wired it (1de70ac18), readers for withdrawn/superseded in; ACTIVATIONS_LIVE flip waits on qa's go; withdraw / reject without the policy check / superseded landed (domain 444c6126b, api 6e289aa35, migration 20261113130000 applied by qa). UI built against fixtures (fe-setup 1165841d8: Changes' 'Waiting for activation' panel + `setup.activation` review page; the approve gate is `mayDecide` in features/activations/api.ts, 572c9382a); shapes plans/activations.md c5428cfbf (fe-ops reads `can_decide` for Now); api endpoint next. Asks: reject skips the policy check + requester withdraw (stuck requests), the apply error on `application_needs_review`, superseded requests. todo(authz): approve rule differs by path (operate_mission vs + manage_missions): with the user (director 11-13); fe-setup keeps the gate in one function; `Activations.fetch/2` checks only the org, but api verified 11-13 that no live path is affected (every decision authorizes against the request's own mission; REST and LiveView callers also compare it); the console endpoint compares it explicitly too |
| L11 | Data sources (`/ops/data-sources/**`): register, binding, enable/disable, probe, rotate, provision/reconcile TSDB, retry runs | All writes (read exists) | api + fe-setup → `setup.data-sources` | done: screens 07ca0518f + 13292ad2a (fe-setup), endpoints 2e3c8c5ab (api-ops, on the e80c9d872 security fix) |
| L12 | Mission ground-network providers (`/comms/providers`): create (bind org account), validate, sync, archive | Writes (read exists) | api-ops + fe-setup → `setup.stations.providers` | shapes proposed (plans/providers.md bc785ad6a, with L13; lists 5 defects in the existing writes; they're in domain code the live legacy pages share, and lead OK'd fixing them on the team branch, one commit each, no ports for now); UI built against fixtures (fe-setup 06db9359c, which also fixes the Providers tab reading `{providers}` as a bare array); endpoints landed (api-ops 4f81a1d0d, setup.md §L12; shape diff: `grant` nullable for old direct bindings; validate/sync give up at 25 s with ok:false); fe-setup wires, then qa |
| L13 | Provider accounts: grant/revoke for a mission, explicit credential revoke | Those verbs (register/edit/test exist) | api-ops + fe-setup → `org.provider-accounts` | shapes proposed (plans/providers.md bc785ad6a, with L12; todo(authz): grant-to-mission has no mission-side check); UI built against fixtures (fe-setup 9c96febab); live in the console (fe-setup b90f5401a, PA2_LIVE on); endpoints api-ops 74ad20816 (contract setup.md §L13; new codes account_changed, grant_changed, grant_already_revoked, account_grant_not_found, credential_changed, credential_already_revoked; PA1 `credential_revoked` live, `auth_failed` retired); fe-setup wires + flips PA2_LIVE, then qa |
| L14 | Contacts: provider-change decisions (approve/reject/acknowledge) | The decision UI | api + fe-ops → `ops.contacts` (a Now attention item?) | built: api 30b3f60b9, 84f58b73d, b5ecefaa2 + fe-ops c782080d7, 1fc6bc14e, 4cb6b221d (ux U44); qa live check needs a sim provider change. Lead 11-13: provider changes for flown passes leave Now; pending_approval becomes expired (409 if decided), acknowledgment_required stays acknowledgeable from the pass detail (domain: read-side Now filter + derived 'expired' on reads, no sweep; api fa633da37 (one state 'expired'; pass provider_changes from pass_history; 409 provider_change_expired); ux words final U44: history 'Not decided: the pass ended first.', 409 `provider_change_expired` 'The pass has ended, so this change can't be decided any more.', EXPIRED block line; fe-ops renders) |
| L15 | Contacts: direct search-and-reserve outside a plan | Single bookings | **User (#75): keep; add them.** domain (after #74, ~1 d): `Contacts.SingleBookings` facade over `ScheduleCommands` (routes, search with 15-min signed reserve tokens, reserve, cancel by `{reservation_id, provider_revision}` → 409 `booking_changed`, status; closed error set). Lead rulings 11-13: drafts and repairs treat live off-plan bookings as fixed occupancy (same spacecraft or same antenna), not counted toward requirements (a DECISIONS entry); cancel by the booking's own operator, else `manage_missions` (todo(authz)). api wraps the endpoints; fe-ops builds the UI in `ops.contacts` | domain 237baf01f + api 1ef9e85ef landed; fe-ops UI (9b71bbc5) aligned to the real endpoints (1fdf40e9c; live search decodes on :4011); live: mostly PASS (qa 11-13); FAIL: an org admin can't release a member's booking (DECISIONS #78 says manage_missions may), with fe-ops + api; then the flag flip |
| L16 | Historical data operations (`/ops/data-operations`) | Everything | **Parked (#75):** the legacy page stays until the user revisits | parked |
| L17 | Spacecraft identity edit / archive (`/spacecraft/:sid/edit`) | Staged `spacecraft` update/archive (create exists) | api (kind schema) + fe-setup → `setup.spacecraft.one` | built: api 8243895f1 + fe-setup 02caace33 (edit, archive sheet, read-only Operation panel; blocking holds stop Apply); follow-up: staging a switch from the Operation panel (L22); then qa. Shape OK'd by lead 11-13 (GET /config/kinds/spacecraft/schema with L22's two switches, prefilled from the configuration read; edit = stage update, archive = stage delete; GET /catalog/revisions/:id/apids). Changes: null in an update is a 422; an unchanged inactive profile still stages; switch help copy from ux (done: U40 1008dd2f4, help texts, HOLD sentences, archive sheet). Archive (lead 11-13, ux's split): waiting command requests are a blocking HOLD; future booked passes an acknowledged HOLD with the count and from-date (words final: ux U40 7d01cd2f7, incl. the archive sheet and `spacecraft_archived`; Compose hides archived targets), plus a guard refusing release/uplink for an archived spacecraft (`spacecraft_archived`, shape to fe-ops first); api builds both with L17, domain reviews. api builds, fe-setup builds on the contract |
| L18 | Catalog extras: reimport, artifact page, download | Those | api + fe-setup → `setup.catalog` | live: api 05aa7e399 + fe-setup d72327020, 72fb52c0f (switch on 703cee96a); qa check |
| L19 | Spacecraft-scope apps (`/spacecraft/:sid/applications`) | Spacecraft scope | fe-setup, with L9 | live: api b18dcf7b5 + fe-setup 704960442, 7836fc692 (switch on 703cee96a); qa check; status-label question with api |
| L19b | App host sessions bind one scope per browser session today (a second surface at another scope gets `host_session_mismatch`); v1 re-pins on focus or mismatch | Per-scope session binding so several surfaces can be open at once | api (after L19) | done (api eecfc73d5; fe-setup dropped the focus re-pin 2de1531c1) |
| L20 | Telemetry explore canned questions | The feature | **Parked (#75):** the legacy page stays until the user revisits. ux's four empty-state links to console homes may still ship (fe-ops, no api); they don't replace the feature | parked |
| L21 | Accept an invitation as a signed-in user | ~~Account invitations + switcher footer~~ built (api cfdf79f7; fe-setup f147dea3; lead 0bb33f80) | api + fe-setup + lead | done |
| L22 | Per-spacecraft runtime switches from the old spacecraft config workspace. All four still feed the runtime and survive in change sets, but can't be edited in the console (domain 11-13) | (1) `commanding_enabled` (safety: authoring and release refuse with `spacecraft_commanding_not_active`) and (2) `telemetry_enabled` (installs telemetry_decom, toggles packet bindings) → **spacecraft-level settings changed through a change set** (with L17's spacecraft kind). (3) `handled_apids` → an **overridable profile field** next to `catalog_revision_id`, default 'all the catalog's APIDs'. (4) `telemetry_source_endpoint_id` → **no field**: derived; the ambiguous multi-endpoint case becomes a Readiness finding pointing at Data sources (L11) | domain (kinds/fields + finding, after #74, before L15) → api (with L17's spacecraft kind) → fe-setup (spacecraft page section; profile field) · ux: wording for turning commanding off | domain done: (1)+(2) a78eb466, (3) 9251b745, (4) 20d1933d8; two config.exs lines (APID HOLDs, catalog_apids) after the 11-14 01:00Z freeze (qa) → api (L17 kind fields + `GET /catalog/revisions/:id/apids`) → fe-setup |

### 11d. Hand-out order (lead, 11-13; after each person's current items)
- **api:** L1 (8g + close/cancel) → L21 invitations → L9 surface context + token endpoint, staging/activation through Changes (director 11-13; ux spec `ux/AppSurfaces.md`, aed431cb) → L4 mission create → ~~L2 template verbs + L3 grant verbs~~ (002e3ed7e, 12562f5ca) → ~~L17~~ (8243895f1) → ~~operation_id~~ (66875fb39) → ~~L10 endpoints + resume~~ (be59d4f32) → ~~duplicate staged delete no-op~~ (b4c0bf8d5, 32a637465) → ~~governance copy~~ (3bb80ce99) → Q6 dashboards wrap + L10 withdraw/superseded wrap (after domain) → L15 Timeline event → ~~L18~~ (05aa7e399) → ~~L19 read~~ (b18dcf7b5) → ~~derived_telemetry schema~~ (fa7e9e463) → ~~L14~~ (30b3f60b9, 84f58b73d) → ~~per-target values~~ (f1bed1880) → ~~8c port~~ (341c80531) → ~~L19b~~ (eecfc73d5) → ~~§11c configuration-read extra~~ (c61444ede) → ~~activation_pending per spacecraft~~ (4652a2044) → ~~limit_definition schema~~ (6cbd137e6) → ~~outline library~~ (domain 73e5f126e) → ~~redirect prep~~ (api/legacy-redirects, waits on batches) → ~~B2 latest-values read~~ (540b8ac55) → **director 11-13:** GitHub #56 text ORDER BY collation audit + fixes (team branch and develop; report the prod collation) → GitHub #50 test.exs pid/partition entries to runtime config (develop PR) → ~~todo(authz) inventory~~ (eb50fd7dd, docs/apogee/authz-inventory.md: 30 markers; most rest on :operate_mission = any org member on every mission, so per-mission roles come first in Cedar) → ~~#50~~ (e9cea8eee, with the director) → ~~#56~~ (R3–R5 2ade4c3c8; develop port fix/collation-order-56 c8772dd99 with the director; R1 uplink lock order and R2 binding-set hash order held until after 01:00Z through qa, R2 to deploy only with no pending approved activation; collation recommendation with the director and devops) → ~~per-field settings storage + dry run~~ (14455857d; qa runs the dry run for the director; :4011 has 1 override, kept) → ~~per-field settings~~ (server a85b1799e + fe-setup 424a17138; :4011 run skipped; qa check) → ~~contract-drift sweep~~ (docs/apogee/api/drift-sweep-2026-11-13.md ecea3744c; server fixes 4d92b1f5e, 67187baea, 6956b31e5, df82d460b; readers fe-ops 3aec78162, fe-setup 05cb18eb7, lead ce69ef978; api-ops 4b203c504; contact/reservation-path items held until 01:00Z through qa) → R1/R2 after 01:00Z; redirects with fe-setup's batches.
- **api-ops:** qa #51 → M26 → L6 admin-mode step-up → L5 SPA sign-in / invitation accept (JSON, with the attempt limit) → L7 admin endpoints → ~~L11 data-source writes~~ → security batch → L12 mission-provider writes → L13 provider-account grants.
- **domain:** ~~#74~~, ~~booking fixes~~, ~~dashboards StatelessAuthoring + Q1~~ (done) → ~~XTCE alarm-range importer bug~~ (050dfacf) → ~~L22 (1)–(4)~~ → ~~L15 single bookings~~ → ~~post-L15 batch~~ → ~~dashboards Q6~~ (a594da7ec) → ~~L10 withdraw/superseded~~ (444c6126b) → **#77 / L9 B** (stage 1 done: derived_telemetry kind 5504322a8, HOLD derived_point_in_use with used_by[].definition_id; api's kind schema fa7e9e463; fe-setup stages derived points + U42 links; plan docs/apogee/domain/app-config-change-sets.md; director 11-13: (3)+(4) agreed, (1)+(2) with the user; start the derived_telemetry kind now without touching direct save paths) and the #74 template follow-up (no migration), shapes out to api + fe-setup, built in whichever order they're OK'd → ~~§8 item 9~~ (02f71d649) → ~~#74 templates~~ (e99fe3830) → ~~D20 override + revoked_by, library stale guard~~ (dd757dae0) → ~~#77 stage 2~~ limit_definition kind (c495f6d9f; registers via config.exs at qa's post-pass restart; api's schema after L19b).
- **fe-setup:** ~~L21~~, ~~L9 frame~~, ~~L7~~ done; now proposing shapes and building against fixtures for ~~L4~~ → ~~L2/L3 UI~~ (48d652840) → ~~L11~~ (3eb56be4c), ~~L18 against fixtures~~ (d72327020, waits on api's review); ~~L12+L13 shapes + fixtures~~ (bc785ad6a, 06db9359c, 9c96febab) → ~~L10 UI~~ (1165841d8) → ~~qa §6 (3)+(5)~~ (1fdae0866: a 403 is an access state in ApRemote, members keep their rail) → ~~L19 UI~~ (704960442, waits on api's read) → ~~§12C setup adoption~~ (c32bc2db6), ~~Settings Override check~~ (with ux) → now: legacy deletion manifest (plans/legacy-deletion.md); L17 + L22 UI when api's kind schema lands.
- **fe-ops:** L5 SPA auth screens (from lead), L14 decisions UI, ~~L15 single bookings UI~~ (9b71bbc5, behind a flag), ~~L20 empty-state links~~ (5d7e882d).
- **lead:** ~~L6 admin-mode client~~ (3b819ce1), ~~L21 switcher footer~~ (0bb33f80); L5 screens handed to fe-ops (lead owns the architecture).
- **dashboards:** L8 (plan 6dc7421b approved; slices in §11e).

### 11e. L8 dashboards: endpoint routing (lead, 11-13; plan `plans/dashboards.md`, DECISIONS #76)
| Slice (ships) | Server asks | Owner | Order in their queue |
| --- | --- | --- | --- |
| 1 Read-only viewer (core 7ba5e167, routed 272bb119 as `ops.dashboard`; D5 + D0 api-ops 04639f11) · 2 Live (step 1) + directory | D5 viewer read, D0 `dashboard.author` in the session; D1–D4, D6 directory, star, archive/restore, create/import/duplicate, record view (`binding_summary` new) | **api-ops** | done: D5 + D0 04639f11, D1–D4 + D6 3e2a6632 |
| 3 Edit in place · 4 Versions + conflict (api D7–D13 landed b5f724a6; dashboards wiring) | domain: Q1 fix (settings + library through `CurrentVersions`) and the stateless entry (open at version + replay); then api: D7 preview, D9 save, D8 observable search, D10–D13 rebase, copy, versions, restore | **domain** (core) → **api** (endpoints) | domain: after #74 and the booking fixes, before L22 (api is blocked on it). api: after requirement close/cancel, before 8f |
| 5 Settings, sharing, activity, diagnostics, export | D14–D19 (fe-setup proposes the shapes to api, cc dashboards) | **api**; UI **fe-setup** (dashboards hands it over 11-13: `features/dashboards/settings/`, dashboards reviews) | after D7–D13 |
| 6 Shares, snapshots, playlists | D20, D23, D24; Q6 playlist and library update/delete (domain functions) | **domain** (functions) → **api** | domain Q6 landed (a594da7ec; ExecutionLock hardening 4671ec5b7); api wraps next with lead's codes. Playlists + present mode live (dashboards 178a6c9e4, D23/D24; directory 'Playlists' entry pending ux); slice 6 done; api wrapped all of Q6 (D14–D16 f4ef739b9, D20 f622f0772, D23/D24 475cf1295, D21/D22 ffd5c6d69); library wired (fe-ops 4f3989724, 901c821c7; qa check after the restart); ~~LibraryPicker in WidgetSheet~~ (dashboards 7667363c4). **All L8 slices built**; library + From library qa PASS 13:33Z stale-tab rename fixed and qa PASS live (domain dd757dae0, api d8de53662, fe-ops 8929d11fe; Preview wording too); retired-widget caution qa PASS (domain 73e5f126e + dashboards 83d5ecdc7, 4f027fb7d): **slice 8 closed**. Open: the overlay look (needs history), the ChartMarker union after it, and the L8a deletion: **director's GO 11-13** (fe-setup builds, one commit per piece; qa-planned restart outside 23:00Z–01:00Z, maybe with batch 1 at ~01:30Z; qa re-runs the dashboards smoke after); qa checks shares, snapshots, playlists, library and add-from-library after the reload; then L8a/L8b deletion to the director. Open: share runtime override + revoked_by (domain, after derived_telemetry). Shared views live (dashboards 8ea00c842, D20; Take snapshot, Export 3c4bb7765); gaps: share revoked_by, share runtime params (api/domain); qa smoke queued. Q6 shapes OK'd by lead 11-13 with amendments (stale code, atomic in-use check, snapshot delete revokes its shares, audited deletes); UI built against fixtures (dashboards) |
| 7 Channel push | ~~C1 `dashboard:<m>:<d>`~~ landed (api-ops 30295106); client built behind `LIVE_PUSH` (0d59123a), flip after checking | **api-ops** / dashboards | flip |
| 8 Library | D21, D22 (fe-ops proposes the shapes, cc dashboards) + domain Q6 update/retire | **api**; UI **fe-ops** (dashboards hands it over 11-13: `features/dashboards/library/`, `LibraryPicker.vue` for the editor, dashboards reviews) | last |
**Cutover (lead 11-13):** the console directory, New and viewer are live (35d3e03f, 3680e721; D8 b92f380b). Slices 3–4 are wired (fe1ecd0b on api b5f724a6). The legacy directory + viewer + `/edit` redirect to the console in ONE step after qa's live smoke on :4011 (edit → save → versions → restore → copy + a conflict) passes, so authors never lose editing; api-ops does the redirects. **qa's smoke PASSED 11-13 11:52–11:56Z** (edit, save, versions, compare, restore, copy, conflict with live push); **Legacy redirect landed (api-ops 5e151d4a3: directory, viewer and /edit → console in one hop, params kept; legacy tests moved or deleted per lead's rule; qa PASS live 11-13 12:4xZ)**, earlier plan: no /edit?candidate exemption: dashboards traced add_to_dashboard as dead at both ends, so it's retired with the federated batch). 'Saved by Someone' was client-side (dashboards 5e5015c48, 0ce17529f). L8 deletion plan: legacy-deletion.md §L8 (f3fa14ff9): L8a directory/viewer/editor/new (after qa confirms New live), federated surfaces (devops' smoke move 9f0927b4c goes in this batch on our branch, not develop: fe-setup cherry-picks it, director 11-13), L8b with their slices.
Kit (lead): K1 `uplot` + `gridstack` in the console, dashboards-only lazy imports; K2 `--chart-*` tokens in `apogee-ui` tokens (ux supplies values); K3 a side placement for `ApSheet` (400px, right-anchored, non-modal while editing); the cockpit cluster composes the shell's exported `ClockCluster` and counts. Q8: dashboards edits fe-ops' three Telemetry/Timeline files itself, telling fe-ops first.

### 11b. Console places that still send people to a legacy page (ux)
Telemetry Explore and Investigate `Dashboards ↗` (L8); ~~account menu and admin chip `Admin area ↗` (L7)~~ now the console admin area (lead c57c815ea); Setup › Apps surfaces (L9); `org.missions` New mission (L4); PendingScreen "use the existing Cadence pages" and the K1 template link. ux amends the IA and specs as each row gets its home.

### 11c. Verify, then keep or delete
- ~~`/spacecraft/:sid/commanding` (command interpretation)~~ checked by fe-ops: covered by Investigate › Configuration G1–G3 and Compose's resolved endpoints; deletable. ~~Parity extra~~ done (api c61444ede, fe-ops 2fe77a84c).
- ~~Legacy commanding stage-only features (batch preview, `restart_draft`)~~ checked by fe-ops: not needed (live preflight M18 + submit digest; Compose drafts with 409 Load / Keep mine). Deletable.
- ~~Profile overrides cover every per-spacecraft field of the old spacecraft config workspace~~ checked by fe-setup: partly. `protocol.*` and `catalog_revision_id` are covered; the other four keys became L22.
- ~~Redirect-only controllers point at console routes~~ done (api c1396fba2, qa PASS 11-13); delete them with the pages later.
- Keep: DELETE `/session`, PUT `/session/organization` (plain controllers the console uses); the downloads `/catalog/artifacts/:id/download` and `/ops/dashboards/:id/export` until L18/L8 decide.
- Covered already (no work): org home, missions, timeline, settings, spacecraft create, profiles, routing (replacement model), transports, stations, catalog import, planning runs, commanding (replacement model), alarms, app install, people.

## 12. Typing (director 11-13; audit `typing-audit.md`, 7025e879)

The plumbing is clean (0 `any`, everything crosses a decoder). The debt is vocabulary and identity: 140 enum-like fields decoded as text, 0 branded ids, string error codes, untyped routes, 52 `string`-keyed word maps. Rules in force for all new and touched code (lead broadcast 11-13): enum-like fields decode with `known()`/`oneOf`, word maps are `Record<Union, string>` or exhaustive, no new `as X` on decoded data. About a day of A; parity work keeps moving.

### 12A. Infrastructure (one owner per area, so the api layer isn't edited by seven people)
| # | Item | Owner | Status |
| --- | --- | --- | --- |
| A0 | ~~Raw word for unknown values~~ done (d9dc435a): `known()` unchanged (`"unrecognized"` literal; 50 adopted sites stay), plus `knownText()` → `T \| { unrecognized: string }` (an object, can't widen to `string`; a typo literal is TS2367, proven by a `@ts-expect-error` test), `isKnown`, `vocabularyText`. Owners move display fields to `knownText` in 12B | lead | done |
| A1 | ~~`no-unsafe-type-assertion`~~ done (6e3a5f84): on for the console and kit (tests and legacy apps exempt); 45 hits fixed with `api/json.ts` guards; 3 scoped disables in decoder internals/adapters | lead | done |
| A2 | ~~Typed error codes~~ done (a7a1095e): `api/errors.ts` `ErrorCode`, `isError` (typo = compile error), `codeOf`, `knownErrorCode`, `detailsOf(e, reader)`, one `fieldErrors()`; ast-grep `error-code-compared-as-text` blocks new raw comparisons (29 offender files ignored until migrated) | lead | done |
| A3 | ~~Typed routes~~ done (dashboards 6c337129): `router/route-map.ts` `RouteNamedMap` for all 76 routes with a sync test both ways; `useRoute('name')` instead of raw param reads; `SpacecraftTab` union; setup `:scId` → `:spacecraftId`; the dangling names registered (pending) | dashboards | done |
| A4 | ~~`useRemoteQuery` compares keys structurally~~ done (6e3a5f84); the JSON reparse sites went with A1; owners drop their `split("\|")` keys in 12B | lead | done |
| A5 | Shared entity decoders `api/entities.ts`: actor, spacecraftRef, stationRef, role (+ `roleText`, `roleWords`), invitation state / invitedBy / core | **fe-setup** | step 1 done (0f436237: People, Account, admin migrated); actor migration in fe-setup's features next, then a list of others' sites |
| A6 | ~~Gates~~ done (a7a1095e): ast-grep `vocabulary-field-decoded-as-text` (178 sites in 59 files ignored until migrated; `// free-text:` opt-out); `requireDefaultForNonUnion` on the console and kit | lead | done |

### 12B. Owners migrate their own features (normal queue, gated by A's rules), worst first
**How to migrate a file:** switch its enum-like fields to `known`/`knownText` (display the raw word with `vocabularyText`), its error checks to `isError`/`fieldErrors`/`detailsOf`, its word maps to `Record<Union, string>`, its query keys to typed objects; then delete the file from the `ignores` list in `frontend/ast-grep/rules/vocabulary-field-decoded-as-text.yml` and `error-code-compared-as-text.yml` AND from `frontend/ast-grep/migration-baselines.json`, so the gate holds it.

**Ratchet (director 11-13):** the ignore lists only shrink. `test:structure` fails if a rule's ignores gain a file not in the baseline or grow past it. Not yet migrated (update when a file comes off):
| Rule | Files left | Baseline 11-13 |
| --- | --- | --- |
| `error-code-compared-as-text` | 1: apps/hostBridge kept (fe-setup): it compares plugin-sdk's HostBridgeError.code, not an ApiError. Done 11-13: contacts, commands, mobile, now, auth, resolutions (fe-ops), dashboards 5 | 29 |
| `vocabulary-field-decoded-as-text` | 0. Done 11-13: resolutions, dashboards 2, lead's, fe-setup's own, contacts 5, commands 6 and now 4 (fe-ops), and fe-ops' investigate 6, timeline, telemetry, fleet, alarms 2 (fe-setup, e3eaeedff..3dc518802) | 59 |
| Order | Area (audit §2) | Owner |
| --- | --- | --- |
| 1 | `features/contacts/readiness.ts` + `useStationCodes.ts` (shared by Now, Contacts, Commands); plus fe-ops' own `d.token` list: library kind, single-bookings availability / overlaps.reason / not_ready.code / reason, change_set.state, groups target.blocked.reason | fe-ops |
| 2 | ~~`features/scheduling/*` (booking state and reason, plan issue codes, actor kinds)~~ done (95f07ecc, with runtime status and session role) | lead |
| 3 | `features/dashboards/chart/*` (the `ChartMarker` string bag; Fix 10 marker union) | dashboards |
| 4 | Router link sites (comes with A3) | dashboards |
| 5 | `features/commands/groups/*` | fe-ops |
| 6 | `features/now/*` | fe-ops |
| 7 | Auth and roles (`features/auth`, `api/session.ts`, `features/account/invitations.ts`) | fe-ops (auth) + lead (session) |
| 8 | Error-details handling (comes with A2) | lead, then each owner switches to `fieldErrors()` |
| 9 | Query-key reparsing (comes with A4) | each owner |
| 10 | `features/planning/*`, `features/profiles/newProfile.ts`: a shared `JsonObject` type and path helper | fe-setup |

**A5 shared entity decoders: sites left for their owners** (fe-setup's survey 11-13; `api/entities.ts` makes name / scid / code nullable, so rendering sites need a fallback):
- **fe-ops:** actor in investigate/configuration/api.ts:8, investigate/history/api.ts:14, alarms/episodes.ts:12, contacts/api.ts:49,67, now/actionQueue.ts:70, now/attention.ts:13, now/changeSet.ts:20, commands/request/brief.ts:37, timeline/api.ts:36, resolutions/api.ts:17 (commands/groups `actor_kind`/`user_id` is a different wire shape: keep, or ask api to align); spacecraft ref in investigate/uplink/api.ts:26, contacts/api.ts:28, contacts/findings.ts:34, contacts/singleBookings.ts:30,40, alarms/episodes.ts:23, timeline/api.ts:28; station ref in contacts/api.ts, contacts/readiness.ts (+ the hand-written StationRef), contacts/singleBookings.ts, contacts/findings.ts, investigate/uplink, investigate/passes, now/sources.ts.
- **dashboards:** ~~actor in dashboards/editor/contracts.ts:197~~ done (91568857).
- **lead:** role in api/session.ts:21, auth/api.ts:33, auth/words.ts (four guessed keys → `roleText`); StationRef in scheduling/api.ts:38.

### 12C. Branded ids, last and phased
`api/ids.ts`: `MissionId`, `SpacecraftId`, `Scid`, `StationId` first (decoders mint them, so no assertions outside `api/`), then the rest by audit §1.2. Lead owns `ids.ts`; owners adopt it per feature.

**Step 1 done (lead 10ac63a9e):** `api/ids.ts` with the four brands, decoders (`missionId`, `spacecraftId`, `stationId`, `scid`) and route-param readers (`spacecraftIdParam`, `stationIdParam`, `scidParam`, `scidText`), exported from `@/api`. **Step 2 done for setup (fe-setup c32bc2db6) and ops Scid/SpacecraftId/StationId (fe-ops a08319044, 1ff51415e, cd5c5c12d). ~~MissionId~~ done (fe-ops 611adb507: the session decoder mints it; every mission-scoped fetch, hook and prop takes MissionId; leftover split/JSON keys became typed keys). ~~StationId in scheduling~~ done (fe-ops 47bb3c625).** §12C step 2 complete. Original step 2: fe-setup: setup routes' `:scId` (spacecraft id), OverridesList, SpacecraftDetailScreen, profiles, stations; fe-ops: fleet/alarms `:scId` (SCID; AlarmTable's `""` fallback), now/sources.ts `scId`/`scid`, investigate/api.ts and alarms/episodes.ts argument order, useStationCodes' mixed id/code map; everyone: `missionId` params where the slug could slip in (live/mission.ts). Add a brand to ids.ts through lead.
