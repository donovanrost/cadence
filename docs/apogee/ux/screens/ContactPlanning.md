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
  `12 spacecraft`) · Rule in words, mono: `≥ 3 CONTACTS / DAY · AT LEAST 2h00 APART · ≥ 1 UPLINK` (from
  `contact_count`, `minimum_separation_seconds`, `service_direction`) · Priority (`routine` / `high` /
  `critical`) · Version `v2` · Spacecraft count. Primary `New template`.
- **P3 Not covered** (only when > 0): spacecraft with no rule, grouped by profile/plane ("12 in
  Earendil Block 2 have no contact rule"), action `Add a template for Block 2`.
- **P4 Requirements** (one-off requirements; §11 L1, #74; fe-setup builds, api fb7510be):
  - Filter segmented: `One-off` (default) · `From templates` · `All`. Template-generated requirements can number
    thousands a day, so `From templates` groups them by template (`Block 1 daily · 1,500 for 11-14`) and links to
    P2. They're never listed one per row by default.
  - Columns: Spacecraft (link) · Window (`11-14 00:00Z → 11-15 00:00Z`, §4) · Rule in words (P2's mono format) ·
    State (`ACTIVE` nominal, `CLOSED` and `CANCELED` off) · Source (`One-off` / the template's name as a link) ·
    Updated (by, when). Primary `New requirement`.
  - **Requirement page** `…/contact-planning/requirements/:requirementId` (`new` for create): a form generated
    from `GET /requirements/schema`, in the groups `Window` then `Requirement`. Advanced fields are collapsed,
    including `Longest time without a contact` (`max_gap_seconds`, #74; empty reads "No limit"). Save creates a
    new version and shows the supersedes sentence first (as for templates). Template-generated requirements are
    read-only, with "Change it in its template: Block 1 daily." and a link.
  - **Planning it** (director, 11-14: whole-day planning is the model). An active requirement whose window hasn't
    ended offers the secondary `Plan 11-14`, which opens `M/contacts/plan?day=2026-11-14`. The day is the window's
    start UTC day (`earliest_start`), since the read has no planning day (fe-setup).
    - Under it, a `text-3` line: "Cadence plans a whole day at a time: this requirement is planned with the rest
      of 11-14's requirements, so it can't take capacity another one needs."
    - Then: "For a one-off pass outside any plan, book a pass instead." The link opens Contacts' `Book a pass`
      sheet (L15), prefilled with the spacecraft and the requirement's window.
    - Already held by a plan past draft: the button reads `Open plan R41` and goes to that plan; the line stays.
      This waits for api's `held_by`; until then it's always `Plan 11-14`.
    - Closed, canceled or ended requirements show none of this. Template-generated occurrences get it as well,
      because they're planned the same way.
    - Gates follow the places the links lead to. `Plan 11-14` shows for every member, as Contacts › Plan lets any
      member draft. The Book a pass sentence uses the same gate as Contacts' own `Book a pass` entry, so it never
      opens a sheet the person can't use.
    - The prefill carries the spacecraft, plus the window once Contacts takes `book_from` / `book_to` (fe-ops).
      Until then the sheet uses its default window.
  - **Close… / Cancel…** (secondary, each confirms with a required reason). Each sheet says what it does, in the
    server's terms:
    - Domain: both behave the same today. Booked passes stay booked, draft and pending plans that use it read
      superseded, and it leaves demand. Only the recorded state differs, so each sheet says when to use it:
    - Close: "Use this when it's done or no longer needed. Cadence stops planning for it. Passes already
      booked stay booked."
    - Cancel: "Use this when it was a mistake. It's withdrawn and nothing more is planned for it. Passes
      already booked stay booked."
    - Both add "Draft plans that use it will need drafting again." (only when the dry run finds some) and end
      "This is final: declare a new requirement to plan it again." (fe-setup 0dace065)
    - Releasing future bookings on Cancel would be a director decision, and isn't specified here.
  - Ended rows read `Closed by Mira K. on 11-12: <reason>` / `Canceled by …`.
  - **A template-generated occurrence** (fe-setup 11-13) has no Edit, because edits go to its template. It does
    offer `Close…` and `Cancel…` for that one day. The sheet's scope line comes first: "This closes only the
    11-15 occurrence of “Daily downlink”. The template's other days aren't affected." (Cancel: "This cancels
    only…"). Then the same "Use this when…" sentence, and it ends: "This is final for this day: the template won't
    bring it back, even when the template is edited. To plan 11-15 again, add a one-off requirement for it." (U48:
    closed stays closed. Until domain's template-version fix is live, the old ending stays: "The template won't bring
    this day back, unless the template is edited." Once domain adds an explicit reopen, the last sentence becomes
    "To plan it again, reopen it.")
  - Template-generated rows show their version in Source (`Block 1 daily · v2`), because days from different
    versions sit side by side after an edit (U48).
- **Template page:** the rule as a form generated from the requirement fields (contacts per day,
  window `earliest_start` → `latest_end` in UTC time-of-day, minimum and preferred duration,
  minimum separation (contacts at least this far apart; it's **not** a maximum gap, which isn't modelled), direction downlink / uplink / both, intent, priority, minimum data
  volume, station/provider constraints as chips, rationale). **Applies to** is a target query (same
  chips as Command C1: profile, plane, spacecraft). A live preview line: "3 contacts a day for 500
  spacecraft = 1,500 passes a day". Before saving, show what it supersedes (from a server dry-run): a caution callout "Saving v3 supersedes 2 open
  drafts: Wed 11 Nov (R1, Mira K.), Thu 12 Nov (R1, you). They'll need drafting again." Above it, the dry run's
  count line (U48), as a neutral info line: "v3 applies to every day that's still open. 3 days already planned or
  started keep their requirement: 11-14, 11-15, 11-16. 2 closed days stay closed: 11-12, 11-13. 1 canceled day
  stays canceled: 11-11." For a template on many spacecraft it leads with requirements: "1,500 requirements on 3 days, already
  planned or started, stay as they are: …". Save then reads
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
