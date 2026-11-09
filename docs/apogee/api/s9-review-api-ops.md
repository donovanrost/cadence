# api-ops review of `domain/pass-review.md` (S9) against K3

Reviewer: api-ops (endpoint owner, DECISIONS #47). Date: 2026-11-09. Source of K3 needs:
`ux/screens/ScheduleFlow.md` (K3) and `plans/scheduling.md` (K3 table). The design covers most of
K3. These are the gaps, in order of impact.

| # | K3 region | Gap | Ask |
| --- | --- | --- | --- |
| 1 | Stat strip "Missed: 5 provider · 3 us · 1 weather", R4 owner column, `Dispute` action | The model has `cause_source: provider \| delivery \| station \| cadence`, but K3 speaks of **owner** (`provider \| us \| weather \| unknown`, who pays). There's no weather source, and `station` can be either side. | Store `owner` (derived, with its rule) next to `cause` / `cause_source`. `weather` only when the provider says so. `disputable = owner == provider`. |
| 2 | R4 "antenna" column | No antenna on the result row. | Add `antenna_ref` (from the reservation snapshot, like `ground_station_ref`). |
| 3 | Header "PASS REVIEW · PLAN R39" | Results aren't linked to the plan that booked them. | Add `contact_plan_id`, `contact_plan_version` (from the reservation) and a `plan` filter on `rows/summary`. |
| 4 | h1 meta "0 UNKNOWN" / "realized % is provisional" | `freshness` is per provider. The h1 needs one flag for the span. | `summary` returns `pending_report` (count) and `provisional: boolean` (any pending report, or any provider with an unhealthy cursor, in the span). |
| 5 | Stat strip "Downlink vs plan" | No **planned** volume (reservation `estimated_capacity` is opaque). | Say so explicitly: `planned_bytes` is `nil` unless the provider supplies a number, and K3 shows "received vs provider-reported" instead of "vs plan" until then. |
| 6 | R1 by station | `summary` "by station" must carry what R1 lists. | Per station: `ground_station_ref`, `provider_id`, `planned`, `realized`, `partial`, `missed`, `failed`, `canceled`, `flown_seconds`, `planned_seconds`. Billed minutes are absent (no billing). |
| 7 | R2 "why passes were lost" (red = missed, amber = partial) | "By cause" needs the outcome split. | Per cause: `{cause, cause_source, owner, missed, partial}`. |
| 8 | R3 30-day bars "vs a dashed target", annotated dips ("8 OCT · AWA RAIN") | `daily` lacks the target and the annotation. | `daily` rows: `{day, planned, realized, ratio, top_cause}`, plus `realization_target` in the response. **Decided (DECISIONS #48):** two separate mission settings, `pass_realized_threshold` (per pass, default 0.95) and `realization_target` (fleet share, the R3 line and the h1 verdict, default 0.98). Both appear in Settings (ST1). `summary` should return both. |
| 9 | R4 footer "SHOWING 10 OF 23 · 5 DISPUTABLE" | `rows` needs a total and a disputable count for the filter. | `rows` returns `{rows, total, disputable, next_cursor}`, with filters `outcome[]`, `station`, `spacecraft_id`, `plan`. |

Fine as designed: `realized / (planned − canceled)` (canceled stays out of the denominator, per the
director's call), two volumes never merged, the provisional Cadence-only fallback, the event + sweep
arrival paths, `operate_mission` auth, and money out of scope.

Endpoints I'll expose once the facade lands (contracts in `api/contacts.md`):
`GET /pass-review?from&to&span&plan` (summary + freshness + h1 flags), `GET /pass-review/rows?…`
(R4, paged), `GET /pass-review/daily?from&to` (R3). Invalidate on the new `:pass_results_changed`
(`pass_results` resource).
