# Contact planning (Setup) — DECISIONS #27 (4)

Routes `M/setup/contact-planning` (tab Requirements, default) · `…/contact-planning/policy` ·
requirement template `…/contact-planning/templates/:templateId` · **reading layout** · no board.
Owner: fe-setup (endpoints: api). Model: `apps/cadence/lib/cadence/contact_planning/`
(fleet planning policy + versions + approval; contact requirements + recurring templates + versions).

**Question:** "How often must each spacecraft be heard, and how should the scheduler trade cost,
priority and coverage?" It's the **Demand** station of ScheduleFlow (01) and the input K1 Plan
drafts from. Until it's set up, Readiness shows `planning_not_set_up` (not set up, fix → here) and
K1 shows `not_set_up` with `Set up contact planning`.

## Rail
Setup › Mission, after Ground stations: **07 Contact planning** (Data sources, Apps and Mission
settings become 08–10). The count is the number of active requirement templates; `—` with an `off` mark
when there's no policy. **[decision]**

## Layout
```
lbl "EARENDIL · CONTACT PLANNING"
h1 situation: "Every spacecraft has a contact rule" / "312 spacecraft have no contact rule" / "Not set up"
subline: policy v3 · mode advisory · 4 templates cover 500 of 500 spacecraft
tabs: Requirements · Policy
```

## Tab · Requirements (default)
- **P1 Coverage** (stat strip): Spacecraft covered `488/500` · Templates `4` · Contacts per day
  (sum of rule demand) · Uplink-capable passes required. A `—` + reason where it can't be computed (U13).
- **P2 Templates** (ApTable): Name (link) · Applies to (`profile Earendil Block 1` / `planes 03–04` /
  `12 spacecraft`) · Rule in words, mono: `≥ 3 CONTACTS / DAY · NO GAP > 10h00 · ≥ 1 UPLINK` (from
  `contact_count`, `minimum_separation_seconds`, `service_direction`) · Priority (`routine` / `high` /
  `critical`) · Version `v2` · Spacecraft count. Primary `New template`.
- **P3 Not covered** (only when > 0): spacecraft with no rule, grouped by profile/plane ("12 in
  Earendil Block 2 have no contact rule"), action `Add a template for Block 2`.
- **Template page:** the rule as a form generated from the requirement fields (contacts per day,
  window `earliest_start` → `latest_end` in UTC time-of-day, minimum and preferred duration,
  minimum separation = max gap, direction downlink / uplink / both, intent, priority, minimum data
  volume, station/provider constraints as chips, rationale). **Applies to** is a target query (same
  chips as Command C1: profile, plane, spacecraft). A live preview line: "3 contacts a day for 500
  spacecraft = 1,500 passes a day". Before saving, show what it supersedes (from a server dry-run): a caution callout "Saving v3 supersedes 2 open
  drafts: Wed 11 Nov (R1, Mira K.), Thu 12 Nov (R1, you). They'll need drafting again." Save then reads
  `Save v3 · supersede 2 drafts`. Booked plans are untouched (they go to K2 if needed). Save makes **template v3** (versions are immutable), and the history
  lists the versions with who/when/why.

## Tab · Policy
**Billing is out of scope (DECISIONS #63, U34):** the money fields (`max_estimated_cost_micros`, `currency`,
`critical_cost_reserve_micros`, and the cost weight) are hidden and keep their server values. The rest of
the Limits and Reserves panels stay.

One panel per concern, with plain-language labels; the keys sit in `Technical details`:
| Panel | Fields (`fleet_planning_policy_document`) | Notes |
| --- | --- | --- |
| Mode | `mode`: `advisory` (Cadence drafts, a planner submits) / `automatic_submission` | ApOption cards with consequences. Automatic only when policy approval allows it. |
| Limits | `max_contacts`, `max_estimated_cost_micros` + `currency`, `max_horizon_seconds`, `repair_horizon_seconds` | Money shown in the currency; empty = no limit (say "No limit", never 0). |
| Reserves | `critical_contact_reserve`, `critical_cost_reserve_micros` | "Kept back for critical requirements." |
| Diversity | `distinct_station_required`, `distinct_provider_required`, `distinct_service_pool_required` | Checkboxes with one sentence each. |
| Trade-offs | the `*_weight` fields, plus `fragmentation_penalty` and `expiry_risk_penalty` | Numeric with help text, in an **Advanced** disclosure, collapsed. No invented presets: a `Reset to defaults` button only if the server provides defaults. |
| Concurrency | `execution_concurrency`, `provider_search_concurrency`, `requirement_concurrency`, `local_improvement_*`, `max_repair_attempts`, `reuse_freshness_seconds` | Advanced, collapsed; org admins only. |
Save creates **policy v4**. If the policy has an approval rule (`fleet_planning_policy_approval`),
save becomes `Request approval` and the reviewer (≠ author) sees ApDecision. Caption: `APPLIES TO
DRAFTS STARTED AFTER IT'S ACTIVE · v3 KEPT`.

## Relation to change sets
Contact planning **isn't a change-set kind today**: it already has per-entity immutable versions
and its own approval. v1 edits it directly with those versions (like U2's per-entity versions):
no staged bar entries, and saves are immediate with a version and audit. When domain adds
`contact_requirement` / `planning_policy` kinds (backlog), the Save CTA becomes `Stage` and the
version moves into `rN`, with no layout change (the Changes.md §6 seam).

## States
Not set up (no policy): h1 `Contact planning isn't set up`, an `off` callout "The scheduler needs a
policy and at least one contact rule before it can draft a day." + primary `Create policy` (prefilled
with server defaults if any) and secondary `New template`. Read-only (no capability): forms render as
text with "Org admins change contact planning." Errors follow U20.

## Acceptance (for qa)
- Readiness `planning_not_set_up` and K1 `not_set_up` both link here.
- Every rule reads as a sentence in words; raw keys only in Technical details.
- Empty limit fields read "No limit", never 0.
- Saving shows the new version and who/when; approval appears only when the policy requires it.
