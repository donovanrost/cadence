# ux view on the §11c(D) parity audit (Explore and Data operations)

For lead, dashboards and the director, answering `docs/apogee/plans/parity-ops-d.md` (68707f3f9). It covers the
"gone by design" list, where each gap would live and its words, and one gating point.

## The gate first: two of these pages are parked, not deletable

DECISIONS #75 parks **L16 (historical data operations)** and **L20 (Explore's canned questions)**: "their legacy pages
stay until the user revisits." The four empty-state links "don't replace the feature."
- `/ops/data-operations[/manage]` is L16's page, and `/ops/explore` is L20's. Neither can be deleted in §11c(D) by
  building the gaps alone. Each needs the user to revisit its parked row: unpark it and build, or drop it.
- So the canned questions **can't** go on the "gone by design" list; that's the user's call, not ux's. Everything
  else in D can be built now, so it's ready when the user decides.
- This doesn't hold up `/ops/telemetry/explore`: it's only a redirect (D12).

## "Gone by design": confirmations
- **Canned questions:** not confirmed by ux (above). The four links stay as an interim, as shipped.
- **Row limit and order: confirmed** for the bucketed plot. Where raw samples show (Investigate T3, and D6 later),
  the order is fixed newest first and the count is the range's, so neither control comes back.
- **"Refreshed result could not be confirmed": confirmed, with one condition.** Live invalidation replaces it, but a
  re-read that fails must not leave the old plot looking current. The plot keeps the last good data under a stale
  line, "Couldn't refresh at 09:41Z; showing data read at 09:40Z.", plus `Try again`. dashboards checks
  `useSeries` does this; if it doesn't, it's a frontend fix.
- **`add_to_dashboard`: confirmed.** The way in is from the dashboard side (`+ Widget`, From library), and a
  dashboard's Inspect hands a widget to Explore.
- **Federated "Open in workspace" surfaces: confirmed.** They go with their pages.
- **Not equivalents:** agreed. Now's ingress, settlement and archive items, the catalog's import runs and the old
  backfill overlays aren't Data operations.

## Where each gap goes, and its words

**D1 Sample inspection: in Investigate, not Explore.** Explore plots buckets, while Investigate's Telemetry tab
lists real samples (T3), so the sample panel belongs there.
- Selecting a T3 row (its time is a button, `aria-pressed`, as in Timeline's A8) opens a **Sample** aside, 380px. Below
  1100px it's a sheet. U71's "Show the sample that raised it" rings the sample and opens the same panel.
- kv rows:
  - `Value 3.71 V` (engineering, U24 units) and `Raw 0x0E7F` (mono);
  - `Quality Good` (a word, never a code);
  - `Generated 02:08:11.204Z` and `Received 02:08:12.880Z · 1.7 s later`;
  - `Packet HK_EPS v4`;
  - `Valid` / `Not valid: <reason words>`;
  - `Came in through Fairbanks · binding Earendil telemetry v3`;
  - `Replay run 14` only when it's replay data.
- Technical details: sample id, packet id, raw evidence id, binding and endpoint ids, and the raw JSON and hex.
- Fleet Explore's T3 (bucket means) gets no sample panel. Each series links `Open in Investigate` at the same range.
- It needs api's one-sample read.

**D2 Evidence links: agreed.** Repoint both builders to Investigate's Telemetry tab (`?points=<p>&at=<t>`) now, then
to the sample panel once D1 exists. The console's words for the link are U71's "Show the sample that raised it",
not legacy's "Open exact sample and evidence".

**D3–D5 (L16): no design until the user unparks it.** The IA home stays Setup › Data sources › Operations. When it's
built, every group decision and retry needs a required reason with actor and time (U29), and a stale-evidence check
refuses in words. No ux work now.

**D6–D10 (api's later reads): the shape of each, so the reads are built for it.**
- **D6 Raw samples, receipt vs generation:** Generated is the default axis. `Generated | Received` is a choice
  segmented in T2's header, shown only when the read supports both.
- **D7 Non-numeric points:** booleans and enums plot as a step lane (state words in the lane, never colour alone)
  under the numeric charts. Strings get no plot: they show in T3 only.
- **D8 Revisions:** canonical everywhere by default. Other revisions are a disclosure in the Sample panel, "2 other
  revisions of this sample". The plot gets no mode switch, because few operators need it and it's easy to leave on
  by mistake.
- **D9 Realm and replay runs:** replay or simulation data never mixes into an operational plot unnamed. It's
  chosen explicitly (a `Data: Operational | Replay run…` choice), and while it's on, the plot title carries
  `REPLAY RUN 14` as a tag.
- **D10 Non-spacecraft scopes:** these go to their own homes rather than an Explore scope picker: a station's
  telemetry on Ground stations, a contact's on its record, a link's or transport's in Setup. Explore stays spacecraft
  × point.

**D11 Truncation (frontend only): build now.** `truncated` means the raw-sample fallback hit its 20,000-sample cap
(api/ops.md M10).
- An info line under the plot: "This range has more samples than one read returns (20,000), so the plot is
  incomplete. Pick a shorter range to see all of it."
- If api says which end the cap keeps, the line names the part shown ("…showing 02:00–05:40Z"); never a guessed
  range (U20).
- The same line goes on Investigate's Telemetry tab.

**D12 Old telemetry links keep the spacecraft: agreed** (api maps `spacecraft_id` → `sc`). An unknown id drops
silently, as Timeline's scope does. One frontend fix is wanted whatever the redirect does: a point with no spacecraft
must not draw an empty plot. T2 reads "Pick a spacecraft to plot ADCS rate X." with the spacecraft chips focused.

**Tier 3:**
- **Observation count and "Read at": drop.** The plot is live, and D11 covers the honest limit.
- **Bucket `count`: yes,** in the hover readout ("mean of 12 samples").
- **`limit_set_name`: already in U71's B1 line.**
- **The binding's `realm`:** in Sources' Technical details.
- **Source/binding filter and query diagnostics: drop.** They're engine detail.
- **Dashboard → Explore and back:** Inspect plus the browser's Back covers it, so no "Open source dashboard" link.

## Order
Agreed, with the gate added: D11 and the D12 frontend fix now (frontend, S) → D2 + D12 redirect (api) → D1 with A7c
→ D6–D10 as the reads grow. Then the director takes **both parked rows (L16, L20) to the user** before `/ops/explore`
or `/ops/data-operations` can be deleted.
