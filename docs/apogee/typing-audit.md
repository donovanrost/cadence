# Apogee console: type-system audit

Scope: `frontend/apps/console/src` (710 non-test `.ts`/`.vue` files, 106 test files). Read and grep only; nothing was built, type-checked or run. Paths below are relative to `frontend/apps/console/src` unless they start with `frontend/`.

Snapshot caveat: this is a shared worktree. Teammates were editing it during the audit: 21 files modified and uncommitted, including `api/decode.ts`, which got `known()` in commits `a07bab3b` and `58333eba` at 21:07 on 2026-11-12. Line numbers are as read on 2026-11-12, about 21:10.

Method: counts come from ripgrep plus small read-only Python scanners, kept in the scratchpad `tools/` folder. Where a number is a sample estimate, the report says so. Field-name heuristics can't resolve types, so the "checked versus unchecked" split comes from a hand-classified random sample, not the compiler.

---

## 0. Verdict in one paragraph

The *escape-hatch* hygiene is excellent. There is 0 `any`, 0 `@ts-ignore`/`@ts-expect-error`, 0 non-null assertions, and only 4 lint suppressions, each with a reason. 204 types derive from decoders via `Decoded<typeof …>`, and everything crosses a runtime decoder. The weakness is semantic, not structural: **the decoders validate shape but often not vocabulary or identity**.

- 140 enum-like fields are decoded as plain `token`/`string`. About 88 of them are branched on.
- 0 IDs are branded.
- Server error codes are `string`.
- Route names and params are untyped strings.
- 52 display-word tables are keyed by `string`.

So "stringly typed" is accurate for domain vocabulary and IDs. "Poorly typed" is not accurate for the plumbing. The team's own standard already asks for the missing pieces: branded resource IDs, exhaustive handling of closed sets, and validation that establishes what the type promises. This is migration debt against a standard that already exists, not a missing standard.

---

## 1. Categories of weak typing

### 1.1 Enum-like API fields decoded as `string`/`token`, then compared to literals

**Counts**

- **Decoders:** 140 fields whose name ends in `state|status|kind|role|severity|mode|phase|reason|outcome|condition|source|action|type|code|…` are decoded with `token`/`string` (including `nullable`/`optional` wrappers). 88 of them have a same-named field branched on (`===`, `switch`, or map lookup) in the same feature. Some of the remaining 52 are true free text, such as human `reason` sentences.
- **Unions at the boundary:** for comparison, union decoders appear 192 times: 132 `oneOf`, 39 `known`, 16 `literal`, 5 `variant`.
- **Literal comparisons:** there are 1,264 property-vs-string-literal comparisons (`.x === "lit"` / `!==`) in non-test code, plus 387 `case "lit":` labels.
  - 285 compare `RemoteState.status` ("ready" / "loading" / "failed") and 108 compare `ApiError.kind`. Both are checked unions.
  - 39 compare `ApiError.code` (`.code === "…"`), which is `string` (`api/http.ts:8-11`). These are **unchecked**.
  - The remaining 703 were classified from a random sample of 35. 8 were unchecked (23%; rough 95% range 10–37%), which is about **160 unchecked** comparisons (roughly 70–260).
  - **Estimate:** about 200 of 1,264 literal comparisons (around 16%) are against plain `string`, where a typo or a renamed server value compiles silently. About 1,060 (around 84%) are against unions, where TypeScript rejects a typo with TS2367.
- **Unions declared but not wired:** in several places the union is declared in the same file and never reaches the decoder:
  - `features/contacts/readiness.ts:10-11` declares `readinessStates`/`ReadinessState`, with **0 uses**. The three readers directly below it decode `state: d.token` (`:15`, `:43`, `:53`).
  - `features/audit/api.ts:6-7` declares `AuditKind`, but `kind: token` is decoded at `:18`.
  - `features/dashboards/library/api.ts:20-32` declares a `WidgetKind` map, but `kind: d.token` is decoded at `:39` and `:48`. It also needs a cast, `KIND_WORDS as Readonly<Record<string, string>>`, at `:32`.
  - `features/replan/impact.ts:4-6` declares `LostState` behind a hand-written `isLost` predicate.

**Why it was done:** forward compatibility. The comment at `features/scheduling/api.ts:246-248` says: "kept as a token: a new state reads as plain, it doesn't fail the plan". The new `known()` (`api/decode.ts:84`) solves that, but it maps unknown values to the literal `"unrecognized"` and **drops the raw text**. 40 sites fall back to showing the raw key humanized (`replaceAll("_", " ")`), so a bare `known()` migration would regress them. See fix 2.

**Representative examples, each a real hidden bug class**

1. `features/contacts/readiness.ts:159-188`. `readinessTag(r: { state: string; reason: string | null; … })` branches on `"qualifying"`, `"recovering"`, `"ready"` and `"blocked"`. A typo, or a server rename of `blocked`, makes `readinessTag` return `null` (`:180`). The pass then reads as *fine* instead of "Can't command". This module is imported by Now, Contacts and Commands.
2. `features/contacts/api.ts:24` decodes `pass_phase: d.nullable(d.token)`. Live status is decided by `p.pass_phase === "pass"` at `features/contacts/gantt.ts:30`, `features/contacts/ReleasePass.vue:20` and `features/scheduling/contact.ts:39`. If the phase is renamed, a pass in progress renders as "scheduled".
3. `features/scheduling/api.ts:253` decodes `booking.state: d.token`, with `reason` at `:254`.
   - `features/scheduling/offer-clock.ts:41` and `features/scheduling/booking-state.ts:23` compare it to `"never_sent"`.
   - `features/scheduling/DraftGantt.vue:120` compares `reason` to `"sending"`.
   - `features/scheduling/api.ts:131,136` decodes plan issue `code`/`kind` as `d.string`. `features/scheduling/unavailable.ts:17` and `features/scheduling/DraftGantt.vue:58` compare `code === "station_unavailable"`. If the code is mistyped, blocking station conflicts disappear from the draft.
4. `features/commands/groups/show.ts:97,155` decodes event `kind: d.token`.
   - `features/commands/groups/needsYou.ts:54` (`"member_failed"`) and `features/commands/groups/words.ts:152` (red-vs-gray log line) compare it.
   - `features/commands/groups/needsYou.ts:58` compares `payload.reason === "verify_timed_out"`.
   - `features/commands/groups/needsYou.ts:74` compares `end_reason === "earlier_command_failed"`; `end_reason` is decoded as token at `show.ts:35`.
   - `features/commands/groups/series.ts:125` compares `verifier_state` to `"failed"`/`"timed_out"`; it is decoded as token at `series.ts:31`.
5. `features/now/attention.ts:13` defines the actor as `who = { kind: d.token, … }`. `features/now/attention.ts:288-289` compares `resolved_by.kind === "user" | "provider"`, and `features/now/actionQueue.ts:358` compares `a.source === "mission_runtime"`. A miss silently falls through to the generic sentence.

### 1.2 IDs as plain `string`, with no brands

**Counts**

- Branded types in the console: **0**. The only brand in the frontend is plugin-sdk's `Href` (`frontend/packages/plugin-sdk/src/routes/index.ts:23-25`).
- 535 id-like decoded fields (`…id: token|string`).
- 523 `xxxId: string` parameters or fields, including 269 `missionId`, 48 `spacecraftId`, 24 `orgId` and 24 `dashboardId`.
- 82 functions take two or more adjacent `string` id parameters (lower bound, `function`/`const` arrow signatures only).
- 48 `.vue` props of the form `xxxId: string`.
- 212 `scid` mentions. SCID is a number; the spacecraft id is a string.

**Concrete swap and confusion sites**

1. **`:scId` means two different things.**
   - `router/ops-routes.ts:22`: `fleet/:scId(\\d+)` is the numeric SCID. About 25 link sites pass `String(sc.scid)`, for example `features/fleet/FleetTable.vue:59`.
   - `router/setup-routes.ts:29`: `setup/spacecraft/:scId` is the spacecraft **id**. It is linked from 5 sites, for example `features/profiles/OverridesList.vue:49` with `params: { scId: o.spacecraft.id }`, and read at `features/spacecraft/SpacecraftDetailScreen.vue:14` as `spacecraftId`.
   - Passing one where the other belongs compiles.
2. **`scId` versus `scid` in one record.** `features/now/sources.ts:79-80` has `scId: string; scid: number`, filled at `features/now/actionQueue.ts:423-424`. Only the letter case separates the id from the SCID, and the route param is also called `scId` but carries the SCID.
3. **An empty route param.** `features/alarms/AlarmTable.vue:47` builds `params: { scId: String(row.sc?.scid ?? ""), … }`, and `row.sc` is nullable (`features/alarms/list.ts:18`). That produces `scId: ""` for a required `(\d+)` param, which vue-router rejects when it resolves the route. A `Scid` number brand would make the `""` fallback a type error.
4. **Inconsistent argument order across siblings.**
   - `features/investigate/api.ts:75,90`: `fetchHistory(missionId, pointId, spacecraftId, …)` and `fetchLimitIntervals(missionId, pointId, spacecraftId, …)`.
   - `features/alarms/episodes.ts:173`: `episodeFor(episodes, spacecraftId, pointId)`.
   - `features/investigate/api.ts:63`: `pointPath(missionId, prefix, pointId)`, three strings in a row.
   - Swapping `pointId` and `spacecraftId` compiles and returns 404 or empty history.
5. **Mission id versus slug.** Routes carry the slug (`shell/scope.ts:23-29`), and the API wants the id. The only guard is a comment at `live/mission.ts:31`: "Pass the mission id (not slug)". Both values are `token` strings, and `.slug` is used 35 times.
6. **Two identifier spaces in one map.** `features/contacts/useStationCodes.ts:15-22` builds one `Map<string, Station>` keyed by station id *and* station code. `features/contacts/readiness.ts:148-149` looks up by `ref` and then by `id` (`s.code(st.ref) ?? s.code(st.id)`).

**Why it matters:** the standard says branded types should be used "when mixing values would cause a concrete error, such as resource IDs" (`frontend/docs/code-standard.md`, "Expose precise operations"). Items 1–6 are those concrete errors.

### 1.3 Type assertions and `Record<string, unknown>`

**Counts**

- About 62 non-test `as T` assertions, excluding `as const`, import aliases and prose. They break down as follows:
  - **3** in the decoding adapters. These are justified and documented: `api/decode.ts:126,149` and `api/http.ts:50`.
  - **19** `x as Record<string, unknown>` / `Readonly<Record<…>>` narrowing from `unknown`, for example:
    - `features/resolutions/api.ts:123,125,132`
    - `features/providers/api.ts:127`
    - `features/people/services.ts:63`
    - `features/account/api.ts:70`
    - `features/planning/policy.ts:18,135,140`
    - `features/planning/templates.ts:16,82,99,114`
    - `features/planning/targets.ts:14,59`
    - `features/dashboards/library/preview.ts:27,34`
    - `features/telemetry/recent.ts:16`
  - **12** `JSON.parse(key) as {…}`, which turns query keys back into objects (see 1.7). Examples: `features/timeline/TimelineScreen.vue:130,134,165`, `features/telemetry/useSeries.ts:41`, `features/commands/request/RequestBrief.vue:37`, `features/dashboards/library/useLibrary.ts:12,34`.
  - **6** "widen for `.includes`, then narrow": `features/alarms/AlarmsScreen.vue:44-45`, `features/commands/list/list.ts:58-60`, `features/fleet/filters.ts:29`, `features/commands/compose/saved.ts:79`.
  - **4** index-key narrowing: `features/investigate/uplink/UplinkTab.vue:62` (`state as MemberStage`, twice), `features/alarms/api.ts:127`, `features/changes/kindSchema.ts:103`.
  - **2** route params: `features/dashboards/viewer/DashboardScreen.vue:39` and `features/dashboards/shared/SharedViewScreen.vue:26` (`as LocationQueryValue`).
  - **6** harmless `null as string | null` literal widenings, in DefinitionGrid, DashboardGrid and EditBoard.
- `Record<string, unknown>` appears 72 times. `ApiError.details` (typed `unknown`) is read at about 36 sites, by hand.

**Real risks**

1. **The worst site.** `features/auth/InvitationScreen.vue:50-62` decodes only `{ case }` from `e.details`, then asserts `const details = e.details as Partial<Invitation>` and reads `organization`, `role`, `invited_by`, `invited_at` and `email` unchecked.
   - It also invents defaults: `organization: details.organization ?? { id: "", name: "this organization" }` and `email: details.email ?? ""`.
   - Wrong-typed details reach the template as if they were decoded.
   - This breaks two rules in the standard: "Runtime validation must establish what its return type promises" and "do not invent empty objects".
2. **Duplicated error-details parsing.** Field-error extraction from `details` is written six times: `features/providers/api.ts:124`, `features/resolutions/api.ts:129`, `features/planning/requirements.ts:170`, `features/people/services.ts:62`, `features/account/api.ts:49`, `features/changes/actions.ts:314`. The copies handle arrays and strings differently: `resolutions` joins arrays, while others take strings only. So the same server 422 renders differently by screen.
3. **Partial validation behind an assertion.** `features/dashboards/editor/contracts.ts:46-50` (`as WidgetFields`) and `features/changes/rollback.ts:51` (`as { newest_legacy_revision: unknown }`) are narrowing assertions where a decoder would do.
4. **Persisted route locations.** `features/palette/recent.ts:23-33` validates a stored `RouteLocationRaw` from localStorage only as "string or any object". If a route is renamed, the palette's "recent" entry throws on `router.push`.

### 1.4 Route names, params and query strings as raw strings

**Counts**

- There are 64 route names in `router/*.ts`, plus 2 in the unrouted `features/dashboards/library/routes.ts`, all plain strings in `RouteRecordRaw[]`.
- `TypesConfig.RouteNamedMap` is not declared, so every `name` is `string`.
- 169 `name: "…"` literal references outside `router/`.
- 38 `route.params.*` reads, each re-validating with its own default:
  - `""`: `features/dashboards/settings/SettingsScreen.vue:19`
  - `null`: `features/profiles/ProfileScreen.vue:21`
  - `String(...)`: `features/commands/request/RequestScreen.vue:20`, `features/auth/InvitationScreen.vue:31`
  - `Number(...)`: `features/investigate/SpacecraftScreen.vue:24`
- 64 `route.query.*` reads.

**`routes:generate` does not cover the console.** `frontend/tools/generate-route-types.mjs` turns `apps/host/src/routes.json` into `packages/plugin-sdk/src/routes/catalog.generated.ts`, with a typed `href()` and an `Href` brand (`packages/plugin-sdk/src/routes/index.ts:23-50`). Inside the console, plugin-sdk is imported only by `features/apps/*` and `features/dashboards/chart/record.ts`. The console's own router uses none of it.

**Real risks**

1. **Two dangling route names.** `features/dashboards/settings/SettingsScreen.vue:34` uses `"ops.dashboard.settings"` and `features/dashboards/playlists/PresentScreen.vue:43` uses `"ops.dashboards.playlists"`. Neither name is registered anywhere. These screens are unrouted today, so nothing breaks yet. When they are wired, any mismatch with the registered name will throw at runtime ("No match for name"). A typed route map makes this a compile error now.
2. **The `:scId` overload and the empty param** (1.2, items 1 and 3).
3. **`tab` typed as `string`.** `features/investigate/SpacecraftHeader.vue:27` and `features/investigate/NotBuiltTab.vue:11` take `tab: string`, while the router restricts it to `(investigate|telemetry|uplink|passes|configuration|history)`. The union exists only inside a regex string at `router/ops-routes.ts:22`.

**Available fix:** vue-router is 5.3.1 (`apps/console/package.json`), which supports `TypesConfig.RouteNamedMap` with `RouteRecordInfo<Name, Path, ParamsRaw, Params>`. This was confirmed at `apps/console/node_modules/vue-router/dist/index-D7ja2BKs.d.ts:70,2213-2226`.

### 1.5 The same API shape decoded several times

Types are mostly derived, with 204 `Decoded<typeof …>` aliases. The duplication sits one level down: **the same server entity has several decoders that disagree.**

- **Actor `{kind, id, name}`:** at least 16 separate decoders. Some use `kind: d.string`, others `d.token`, and `features/commands/groups/api.ts:163` uses `actor_kind`. `id` is `nullable(token)` in some and `nullable(string)` in others. Examples: `features/resolutions/api.ts:16`, `features/alarms/episodes.ts:12`, `features/now/attention.ts:13`, `features/dashboards/editor/contracts.ts:161`, `features/changes/shapes.ts:12` (non-null `id: token`), `features/contacts/api.ts:49,67`, `features/scheduling/api.ts:141`.
- **Spacecraft ref:** 18 inline object decoders that disagree on `scid: integer` versus `nullable(integer)` and `name: string` versus `nullable(string)`. Examples: `features/timeline/api.ts:28`, `features/contacts/api.ts:28`, `features/alarms/episodes.ts:23`, `features/investigate/uplink/api.ts:26`, `features/contacts/singleBookings.ts:30,40`.
- **Station:** 13 inline station objects, among them `features/contacts/api.ts:29-34` and `features/contacts/readiness.ts:26-31`, plus a hand-written `StationRef` at `features/contacts/readiness.ts:147` versus `Decoded` at `features/scheduling/api.ts:38`.
- **Role is decoded 5 ways:**
  - `nullable(token)` at `api/session.ts:21` and `features/auth/api.ts:33`
  - `oneOf(["organization_admin","member"])` at `features/people/api.ts:6,13`
  - `oneOf(["member","organization_admin"])` at `features/account/invitations.ts:9`
  - `d.token` at `features/account/invitations.ts:28`
  - The label map at `features/auth/words.ts:5-10` guesses 4 keys (`organization_admin`, `organization_member`, `member`, `admin`).
  - The labels disagree: "Admin" in auth versus "Org admin" at `features/people/api.ts:74` and `features/account/invitations.ts:43`.
- **Invitation:** 3 decoders (`features/account/invitations.ts:6`, `features/auth/api.ts:30`, `features/people/api.ts:17`). **Change set:** 2 decoders (`features/changes/shapes.ts:55`, `features/now/changeSet.ts:10`).
- **Readiness state/reason:** decoded 3 times in one file (`features/contacts/readiness.ts:14-20, 41-47, 52-57`). The consumer takes a hand-written structural type (`:159`) rather than a decoded one.
- **Trivial readers copied:** `raw: Reader<unknown>` appears 5 times (`features/changes/shapes.ts:10`, `features/changes/kindSchema.ts:6`, `features/profiles/detail.ts:7`, `features/settings/api.ts:12`, `features/planning/api.ts:7`), and `nothing = d.nullable((v) => v)` 4 times. The JSON-object `doc` reader is written 4 times (`features/planning/policy.ts:14`, `features/planning/templates.ts:16`, `features/planning/requirements.ts:12`, `features/comms/api.ts:103`).

**Risk:** when the server tightens or extends an entity, some features update and others don't. Cross-feature joins, such as an actor id from one feature matched to a user id from another, run on shapes that only *look* alike.

### 1.6 Display words in `string`-keyed maps

**Counts**

- 52 lookup tables declared `Readonly<Record<string, …>>` with literal contents, against 47 keyed by a union (`Record<Union, …>`).
- 21 `MAP[x] ?? fallback` lookups.
- 40 `replaceAll("_", " ")` fallbacks that show raw server keys.

With a `string` key, a missing or misspelled entry silently uses the fallback. With a union key, a missing entry is a compile error.

**Examples**

1. `features/investigate/telemetry/model.ts:12-23`. `LIMIT_STATE: Record<string, OpState>` duplicates `LIMIT_MARK` at `features/telemetry/api.ts:37-42`, which is exhaustive over the same union. `pointMark` tests `p.latest.limit_state in LIMIT_STATE ? … : "off"`, but the decoder (`features/telemetry/api.ts:7-13`) only produces those 4 keys. **So the documented "off for a point without limits" branch can never run.** That is a dead branch hidden by the string-keyed copy.
2. `features/auth/words.ts:5-12`. `ROLE` guesses keys that no decoder accepts (see 1.5).
3. `features/alarms/api.ts:88-98`. `CONDITION_WORDS: Record<string, string>` returns `null` for an unknown condition. `CROSSED_BAND` at `:113-127` needs `condition as keyof typeof CROSSED_BAND` because `condition` is `d.nullable(d.token)` (`:36`).
4. `features/scheduling/booking-state.ts:10-16` (`LOOKS`) and `:34` (`REASONS`). An unknown state "draws as drafted" with no type-level check that the 5 known states are all covered.
5. `features/contacts/readiness.ts:73-78` and `:168`. `r.reason in QUALIFYING` uses `in` on an object literal, which also matches prototype keys. This one is minor; the real issue is that the reason vocabulary is open.

### 1.7 Additional: query keys serialized to strings and parsed back

`useRemoteQuery<K, T>` (`api/use-remote-query.ts:22`) already accepts any `K`. Even so, 27 fetchers serialize their key to a string and parse it back:

- 16 build the key with `\`${a}|${b}\`` and split it with `k.split("|")`, defaulting to `""`. Examples: `features/commands/request/yourGo.ts:40-54`, `features/investigate/InvestigateTab.vue:61`, `features/investigate/uplink/UplinkTab.vue:47-49`, `features/contacts/usePasses.ts:18`, `features/replan/useLostBookings.ts:19`.
- 12 use `JSON.stringify` and then `JSON.parse(k) as T`.

`features/timeline/TimelineScreen.vue:155-165` mixes both: it builds `` `${key}|data` `` and then calls `JSON.parse(k.slice(0, -5)) as Key`.

**Risks:**

- The `""` defaults turn a missing part into a request to `/missions//…`.
- An id containing `|` splits wrongly. `token` forbids whitespace, not `|`.
- Every reparse is an unchecked assertion.

The likely motive is value equality, because `watch` compares keys by identity. That is solvable once inside `useRemoteQuery`.

### 1.8 Additional: server error codes are `string`

`ApiError.code` is `string` (`api/http.ts:8-11`). There are 63 comparison sites against 50 distinct codes, for example:

- `features/dashboards/editor/api.ts:134-159`
- `features/auth/InvitationScreen.vue:50,111-115`
- `features/scheduling/errors.ts:37,49`
- `shell/admin-mode.ts:41-43`

There are also 6 code-keyed `Record<string, string>` message maps, among them `features/scheduling/errors.ts:7` and `features/commands/request/decision.ts:111`. Two helpers probe structurally with `"code" in error && typeof error.code === "string"` (`features/changes/actions.ts:186`, `features/replan/errors.ts:6`).

A typo or server rename here silently drops the specific recovery path: "version conflict, rebase" becomes a generic failure. These paths are the safety-relevant ones: conflicts, `plan_superseded`, `uplink_recovery_refused`.

### 1.9 Additional: the dashboards chart engine is a bag of strings

- `features/dashboards/chart/chart-input.ts:6-99` defines `ChartMarker = Partial<Record<57 text fields, string | null>> & …`. One untyped shape covers every marker kind.
- `features/dashboards/chart/` contains 95 literal comparisons, including 34 on `marker_type`, 7 on `freshness_state`, 6 on `severity` and 4 on `normalized_state`. None of them are checked.
- `features/dashboards/chart/chart-props.ts:10,15,25` types `legend_mode`, `axis_mode` and `time_mode` as `string`. Yet `features/dashboards/model/snapshot.ts:148,153,203` decodes those same fields as `known([...])` unions, so the precision is thrown away at the chart boundary.
- The editor's `WidgetFields` (`features/dashboards/editor/contracts.ts:11-37`) is `Record<key, string>`, including `shared_tooltip: "true"` and `repeat_max_instances: "12"`. This mirrors the server's string encoding, which is defensible as wire format but leaks into the editor logic, for example `features/dashboards/editor/widget-form.ts:86`.

The chart module is about 4,360 lines, so this is the largest single stringly area.

### 1.10 Minor and lower risk

- `RequestOptions.body` is `unknown` (`api/http.ts:40-44`). There are 81 writes and 43 inline body literals. The risk is mitigated because bodies are built inside typed api functions, so each snake_case mapping lives in one place.
- Live channels: payloads are decoded (`live/useChannelEvent.ts:29-33`, good). Topic and event names are free strings, with 15 subscription sites.
- The `null as string | null` widenings (6 sites) would read better as annotated literals. No risk.

---

## 2. The 10 worst files or modules, ranked

1. **`features/contacts/readiness.ts` (with `features/contacts/useStationCodes.ts`).** It declares `ReadinessState` and never uses it. It decodes readiness `state` and `reason` as `token` three times, and `readinessTag(state: string)` branches on 4 literals. It uses `in QUALIFYING` and a station map keyed by both id and code. It is shared by Now, Contacts and Commands, so the looseness spreads to all three.
2. **`features/scheduling/api.ts` and its consumers** (`booking-state.ts`, `offer-clock.ts`, `unavailable.ts`, `DraftGantt.vue`, `PlanScreen.vue`, `SupersededCallout.vue`). 14 enum fields are `string`/`token`: booking state and reason, plan issue code and kind, superseded change kind, actor kind. The consumers compare `"never_sent"`, `"sending"`, `"station_unavailable"`, `"system"` and `"template"` unchecked. There are 8 functions with multiple string ids, and the file is 775 lines.
3. **`features/dashboards/chart/*`** (`chart-input.ts`, `chart-props.ts`, `chart-model.ts`). A 57-field string bag `ChartMarker` with 95 unchecked literal comparisons, and mode fields re-widened to `string` after `snapshot.ts` decoded them as unions.
4. **The router** (`router/ops-routes.ts`, `router/setup-routes.ts`, and 169 link sites). Names and params are untyped. `:scId` is overloaded (SCID versus spacecraft id). Two route names dangle. `AlarmTable.vue:47` can pass an empty required param. 38 ad hoc param reads each have their own default.
5. **`features/commands/groups/{show,needsYou,series,words}.ts`.** Event `kind`, `end_reason`, `verifier_state`, payload `reason` and `abort_reason` are all `token`/`string`, and they decide which commands are flagged red or "needs you".
6. **`features/now/{actionQueue,attention,sources}.ts`.**
   - `status: d.token` at `actionQueue.ts:80`, with 13 comparisons in the feature.
   - `source` compared to `"mission_runtime"` and `"pass_resolution"`.
   - `resolved_by.kind` compared to `"user"` and `"provider"`.
   - the `scId`/`scid` pair.
   - three `string`-keyed word maps: `ACTION_WORDS`, `CAUSES`, `OWNER`.
7. **Auth and roles** (`features/auth/InvitationScreen.vue`, `features/auth/words.ts`, `api/session.ts`, `features/account/invitations.ts`). The unsound `as Partial<Invitation>` with invented defaults, role decoded 5 ways, a role map built on guessed keys, and two different labels for the same role.
8. **Error-details handling** (`features/resolutions/api.ts`, `features/providers/api.ts`, `features/people/services.ts`, `features/account/api.ts`, `features/planning/requirements.ts`, `features/changes/actions.ts`). `details: unknown` is parsed by hand with `Record` assertions, there are 6 diverging copies of field-error extraction, and error codes are strings.
9. **Query-key reparsing** (`features/timeline/TimelineScreen.vue`, `features/dashboards/library/useLibrary.ts`, `features/telemetry/TelemetryScreen.vue`, `features/telemetry/PointsPanel.vue`, plus the 16 `split("|")` sites). Typed keys are flattened to strings and asserted back.
10. **`features/planning/{policy,templates,targets,requirements}.ts` and `features/profiles/newProfile.ts`.** Schema-driven documents are handled as `Record<string, unknown>`, with 4 copies of the `doc` reader and nested `as Record<string, unknown>` writes. The dynamism is legitimate because the server drives the schema, but there is no shared `JsonObject` type or path helper.

---

## 3. What's already done well (keep it)

- **Escape-hatch discipline.**
  - 0 `any` (the only grep hit is a comment).
  - 0 `@ts-ignore`, `@ts-nocheck` or `@ts-expect-error`.
  - 0 non-null assertions.
  - 4 lint suppressions, all rule-scoped with a reason (`main.ts:15`, `features/dashboards/editor/board-grid.ts:58`, and 2 in a test).
  - The ast-grep rule `no-double-assertion` holds; no `as unknown as` was found.
- **A strict compiler and a typed lint baseline.**
  - Compiler: `frontend/tsconfig.strict.json` sets `strict`, `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`.
  - Lint: `frontend/vite.config.ts` enables the `no-unsafe-*` family, `switch-exhaustiveness-check` and `no-non-null-assertion` as errors, with `denyWarnings`.
- **One decoding boundary.** `api/http.ts:114-156` (`request`) means nothing undecoded leaves transport. `api/decode.ts` holds composable readers, and types are derived from them: 204 `Decoded<typeof …>` aliases.
- **Good discriminated unions to copy.**
  - `RemoteState` (`api/remote-state.ts:4-7`).
  - `ApiError` (`api/http.ts:6-17`), with an exhaustive `describeApiError` (`:159-171`).
  - `ConsoleScope` (`shell/scope.ts:6-11`).
  - Readiness fix targets (`features/readiness/api.ts:94-125`), a validated variant with an explicit "unknown target becomes no action" policy.
  - `WriteOutcome` (`features/commands/groups/api.ts:231-233`).
- **Exhaustive maps where unions exist.** `LIMIT_MARK: Record<PointLatest["limit_state"], OpState>` (`features/telemetry/api.ts:37`) and `KIND: Record<PassStatus, …>` (`features/contacts/gantt.ts:35`). `MissionResource` (`live/mission.ts:6-24`) is a closed union that the server can still extend.
- **`known()`** (`api/decode.ts:84`) is the right primitive for open server vocabularies. It is already adopted at 39 sites, mostly in dashboards, and reports each unrecognized value once per field path.
- **Live payloads are decoded** (`live/useChannelEvent.ts:29-33`).

A fix must not reintroduce assertions in feature code, weaken `exactOptionalPropertyTypes`, or make a single new server value fail a whole read. That last point is the forward-compatibility goal the `token` decoding was protecting.

---

## 4. Fixes, ordered by value per effort

| # | Fix | Enforcement | Sites | Effort |
|---|-----|-------------|-------|--------|
| 1 | Enable `typescript/no-unsafe-type-assertion` | oxlint 1.77 supports it (present in `node_modules/.pnpm/oxlint@1.77.0…/configuration_schema.json`) | about 45–50 flagged: 19 `Record` narrowings, 12 `JSON.parse as`, about 15 others. Adapters `api/decode.ts:126,149` get a scoped disable with a reason. | Low |
| 2 | Make `known()` keep the raw text, then migrate enum-like `token` fields to it | ast-grep rule `vocabulary-field-decoded-as-text` | 140 fields (88 branched on); 19 existing `"unrecognized"` consumers; 40 humanize fallbacks | Medium (needs vocabularies from `docs/apogee/api`) |
| 3 | Typed error codes and typed error details | Helper in `api/`, plus ast-grep rule banning `$E.code === $S` and `"code" in $E` outside `src/api/**` | 63 code comparisons (50 codes), about 36 `details` reads, 6 field-error copies | Low–medium |
| 4 | Typed console routes via `TypesConfig.RouteNamedMap` | The compiler, through vue-router 5.3.1 types. Optional ast-grep rule banning `route.params.$X` outside router helpers. | 66 route entries, 169 `name:` literals, 38 param reads; 2 dangling names surface | Medium |
| 5 | Give `useRemoteQuery` structured keys | Change in the composable; ast-grep rule banning `JSON.parse($X) as $T` and `$K.split("|")` inside fetchers | 27 fetchers, 12 assertions | Low |
| 6 | Branded IDs | `api/ids.ts` plus `d.id(...)` readers; the compiler does the rest | Phase 1: `MissionId` (269 params), `SpacecraftId` (48), `Scid` (212 mentions). Eventually 535 decoded id fields and 523 id params. | High (do in phases) |
| 7 | Exhaustive word maps | ast-grep rule banning `const $N: Readonly<Record<string, $V>> = { … }` with literal keys in `features/**`; later `typescript/no-unnecessary-condition` | 52 tables, 21 `?? fallback` lookups | Low once #2 lands |
| 8 | Shared entity decoders | Convention, plus code review | about 16 actor, 18 spacecraft, 13 station, 3 invitation and 5 role decoders | Medium |
| 9 | Lint option tweaks | oxlint | see below | Low |
| 10 | Chart marker union | Refactor | `features/dashboards/chart/*` (about 4.3k lines) | High (schedule with the dashboards work) |

### Fix 1: `typescript/no-unsafe-type-assertion` (do first; it stops new debt)

Add `"typescript/no-unsafe-type-assertion": "error"` to `frontend/vite.config.ts` lint rules. The rule is supported in the installed oxlint 1.77.0. It flags assertions that *narrow* a type, such as `unknown → Record`, `JSON.parse → T` or `string → Union`, and allows widening (`as unknown`, `null as string | null`).

The standard already demands "unavoidable interop assertions in small adapters", so this rule enforces existing policy. Expect about 45–50 hits. Fix them with decoders, or with a scoped `oxlint-disable-next-line typescript/no-unsafe-type-assertion -- <reason>` in the 3 adapter sites.

### Fix 2: keep raw text in `known()`, then wire the vocabularies

**API change.** Today `known()` returns `T | "unrecognized"` (`api/decode.ts:84-91`). That type is checked, but it drops the raw value, and 40 places display the raw key for unknown values (for example `features/audit/api.ts:74-79` and `features/dashboards/library/api.ts:31-32`). Proposed:

```ts
export type Unrecognized = Readonly<{ unrecognized: string }>;
export const known = <const T extends readonly string[]>(values: T): Reader<T[number] | Unrecognized> => …
```

- A literal compared with `"typo"` stays a compile error (TS2367): an object type is not comparable to a string literal.
- `typeof x === "string"` narrows to the known union, and `x.unrecognized` keeps the raw text for display.
- Before adopting this, add a `@ts-expect-error` test in `api/decode.test.ts` proving that `known([...])` output rejects a misspelled literal comparison. The standard allows exactly this kind of documented `@ts-expect-error`.
- Migrating the 19 current `"unrecognized"` comparisons is mechanical.
- Fallback option: keep `known()` as it is and add a sibling such as `knownText()`, so the 39 current call sites are untouched.

**Migration.** Change the 140 `token`/`string` enum-like decoders to `known([...])`, starting with the 88 that are branched on and the unwired unions (`ReadinessState`, `AuditKind`, `WidgetKind`, `LostState`). Most consumers then gain TS2367 protection automatically, and `switch-exhaustiveness-check` (already on) starts covering them.

**Gate.** Add an ast-grep rule, `frontend/ast-grep/rules/vocabulary-field-decoded-as-text.yml`. It matches a `pair` whose key matches `(^|_)(state|status|kind|phase|reason|outcome|severity|role|mode|stage|condition|source|action|code|type)$` and whose value matches `$D.token`, `token`, `$D.string`, `string`, or those wrapped in `nullable(…)` / `optional(…)`. Allow a preceding `// free-text: <why>` comment for genuine human-text fields. ast-grep handles this pattern because it is purely syntactic.

Per the standard ("first inspect existing matches, then enable blocking rules for migrated code"), block per directory as each feature migrates. The rule matches 140 sites today.

### Fix 3: typed error codes and details

- In `api/`, add `export const errorCodes = [...] as const; export type ErrorCode = …` covering the 50 codes in use, sourced from `docs/apogee/api`.
- Add a helper: `isError(e: ApiError, kind: ApiError["kind"], code: ErrorCode)`.
- Better still, add a per-call option `request(path, read, { errors: { invitation_unavailable: unavailableDetails } })` that returns details already decoded. This removes the `InvitationScreen.vue:53` assertion and the 6 field-error copies.
- Add a single `fieldErrors(error)` in `api/http.ts` built on a decoder.
- Gate: an ast-grep rule matching `$E.code === $S`, `$E.code !== $S` and `"code" in $E`, with `ignores: ["**/api/**"]`. It covers 63 sites.

### Fix 4: typed routes

- In `router/meta.ts`, extend the existing `declare module "vue-router"` with `interface TypesConfig { RouteNamedMap: ConsoleRoutes }`.
- Define `ConsoleRoutes` with `RouteRecordInfo<"ops.spacecraft", "/:org/:mission/fleet/:scId(\\d+)/:tab?", { org: string; mission: string; scId: string | number; tab?: SpacecraftTab }, …>` for each of the 66 routes.
- Either hand-write it, or extend `frontend/tools/generate-route-types.mjs` to read the console route files. That generator currently projects only the host catalog for plugin-sdk.
- Outcome: the 169 `name:` literals and their params are checked, the 2 dangling names (`SettingsScreen.vue:34`, `PresentScreen.vue:43`) become compile errors, and `useRoute("ops.spacecraft").params` replaces the 38 hand-rolled reads.
- In the same change, rename the setup param `:scId` to `:spacecraftId` (`router/setup-routes.ts:29`, 5 link sites, `features/spacecraft/SpacecraftDetailScreen.vue:14`).
- Gate: the compiler, plus optionally an ast-grep rule banning `route.params.$X` outside `router/` and `shell/scope.ts`.

### Fix 5: structured keys in `useRemoteQuery`

Add a key-equality option, or compare keys by a stable JSON encoding internally (`api/use-remote-query.ts:55-67`), so callers pass typed object keys and the fetcher receives `K` directly. This deletes 27 reparse sites and 12 assertions.

`features/dashboards/settings/SettingsScreen.vue:27` already passes an object key, so the API supports it. What's missing is equality semantics. The same ast-grep rule as above can then forbid the reparse patterns.

### Fix 6: branded IDs, in phases

Add `api/ids.ts`:

- `declare const idBrand: unique symbol; export type Id<K extends string> = string & { readonly [idBrand]: K };`
- `export type MissionId = Id<"mission">`
- a reader factory `d.id<K>(kind: K): Reader<Id<K>>` built on `token`
- `type Scid = number & { readonly [scidBrand]: true }` with `d.scid`.

Rollout:

- **Phase 1:** `MissionId`, `SpacecraftId`, `Scid`, `StationId`. These cover every concrete hazard in 1.2: the scId overload, scId versus scid, slug versus id, argument order, and the station id/code map.
- **Later phases:** `ChangeSetId`, `DashboardId`, `PlanId`, `CommandRequestId`.

Typed route params (fix 4) should produce brands at the route boundary through `useMissionScope`. Test fixtures need explicit builders such as `missionId("m-1")`, which the standard prefers over assertion-based fixtures.

Effort: it touches about 269 `missionId` params, but the change is mostly a type annotation with almost no logic change. There is no lint rule for this; brands work through the compiler.

### Fix 7: exhaustive word maps

Once fix 2 is in, convert the 52 `Record<string, …>` tables to `Record<Union, …>` (or `satisfies Record<Union, …>`), with one `words(map, value)` helper that handles `Unrecognized`.

- Gate: an ast-grep rule matching `const $N: Readonly<Record<string, $V>> = $OBJ` where `$OBJ` is a non-empty object literal. Empty `= {}` accumulators, such as error collectors, are exempt.
- Then enable `typescript/no-unnecessary-condition` (supported by oxlint) to catch the now-dead `?? fallback`s and impossible branches. Run it report-only first; it flags broadly.

### Fix 8: shared entity decoders

Put `actorRef`, `spacecraftRef`, `stationRef`, `roles`/`role` and `invitation` decoders in one shared module, for example `api/refs.ts` or a `features/shared` public API, and import them everywhere. This removes about 55 duplicate decoders. Where the server really sends different shapes, name each variant explicitly, for example `spacecraftRefWithScid`.

This is a convention enforced in review. An ast-grep rule for "inline `object({ kind, id, name })`" would be noisy.

### Fix 9: lint option tweaks (supported by oxlint)

- `typescript/switch-exhaustiveness-check`: set `{ "requireDefaultForNonUnion": true }`. A `switch` over a plain `string` then needs an explicit `default`, which exposes stringly switches. Keep `considerDefaultExhaustiveForUnions: false` (the default) so a `default:` does not hide a missing union case.
- `typescript/no-unsafe-enum-comparison` is **not** useful here: it targets TypeScript `enum`s, and the codebase uses string unions.
- Optional tsconfig flag: `noPropertyAccessFromIndexSignature: true` makes `Record<string, …>` reads visibly bracketed. The impact was not measured.

### Fix 10: chart marker union

Turn `ChartMarker` into a discriminated union on `marker_type`, decoded with `known()`. Pass `legend_mode`, `axis_mode` and `time_mode` through as the union types `snapshot.ts` already produces, instead of widening them in `chart-props.ts`. This is the largest change, so schedule it with the dashboards overhaul rather than as a standalone typing pass.

---

## Appendix: how the numbers were produced

- **Enum fields:** regex over decoder lines, `^\s*"?[a-z_]*(state|status|kind|…)"?\s*:\s*(d\.)?(nullable(|optional()*(token|string)` → 140. "Branched on" means a same-named property is compared, switched on or used as a map index within the same feature directory → 88.
- **Comparisons:** `\.(\w+)\??\s*(===|!==)\s*"…"` → 1,264 (non-test). Subtracted: `RemoteState.status` (285), `ApiError.kind` (108), `.code` (39). The remaining 703 were sampled with `random.seed(7)`, n=35 (one `typeof` comparison excluded), and each was classified by hand: 8 unchecked (`chart-model.ts:134`, `SupersededCallout.vue:20`, `DraftGantt.vue:120`, `PlanScreen.vue:124`, `passes/api.ts:109`, `encoding.ts:47`, `offer-clock.ts:41`, `words.ts:152`).
- **Assertions:** a Python scan for `as <Type>` excluding `as const`, import and export aliases, comments, and string or template text. Prose false positives were removed by hand.
- **Lint rule support:** checked by name in `frontend/node_modules/.pnpm/oxlint@1.77.0…/node_modules/oxlint/configuration_schema.json`. `no-unsafe-type-assertion`, `no-unnecessary-condition`, `switch-exhaustiveness-check` (with `requireDefaultForNonUnion` / `considerDefaultExhaustiveForUnions`), `consistent-type-assertions` and `no-unsafe-enum-comparison` are all present.
- **Typed routes:** confirmed in `apps/console/node_modules/vue-router` 5.3.1 (`TypesConfig`, `RouteRecordInfo`).
