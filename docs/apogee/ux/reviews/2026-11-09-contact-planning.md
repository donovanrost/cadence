# Review: Contact planning · Policy (fe-setup, f81fc0f1 / 4ec8bc05), live CP2, 1440×900

Verified: plain-language panel titles from the server schema (Horizon, Trade-offs, Resources, Limits &
budgets, Diversity, Mode), Advanced disclosures collapsed, defaults prefilled, "Empty means no cap" help,
the save panel `SAVE AS V2` + Why + `APPLIES TO DRAFTS STARTED AFTER IT'S ACTIVE · V1 KEPT` caption
(ContactPlanning.md). Items (rule U24):
1. **Durations in raw seconds** (`172800 s`) → `48h 00m`, input accepts `48h` / `2d` / `90m` (client-side
   from `unit: s`; no api change needed). Same for the repair window.
2. **Money in micros** (`COST PER PLAN (CAP) · micros`) → currency units with decimals; the currency field
   becomes an ISO 4217 select.
3. **Trade-offs panel is empty** except `Advanced`, so it reads as broken. Show a one-line summary of the
   current weights ("Default trade-offs: cost, deadline and priority weighted equally" from the values)
   above the disclosure, or fold the panel into Advanced entirely.
4. **Booleans as `Choose… / Yes / No` selects** (Diversity) → Yes / No choice segmented showing the default
   (`No · default`), one sentence each (spec).
5. Help text exposes a raw key and JSON (`Per-resource capacities are edited as JSON
   ('resources.capacities')`). → "Per-antenna limits beyond this are set in Advanced." with the key in
   Technical details.

## Requirements tab (ce660ecd), live CP1, 10:45Z
Verified against ContactPlanning.md: h1 `490 SPACECRAFT HAVE NO CONTACT RULE`, subline `Policy v1 · mode
advisory · 10 templates cover 10 of 500 spacecraft`, coverage strip (`10/500` with a caution bar), templates
table with server rule summaries, `P3 Not covered` grouped by profile, a read-only template page (rule,
applies to, priority, state, version history with authors, "Editing templates arrives with the requirement
field schema."). Items:
6. **Sort the templates** (by name / SCID): the order is 001, 005…010, 002…004.
7. **The rule line uppercases its units** (`1 DOWNLINK ≥ 5 MIN EACH · EVERY 6H00`). Keep the rule in mono
   **without** the uppercase transform, durations per U24/§4: `1 downlink ≥ 5 min each · every 6h 00m`
   (lead did the same for units on mobile).

**Policy 1–5 closed** per 638a2ac1 + api 58f948ae (durations `48h 00m` with 48h/2d/90m input, amounts + an ISO currency select, Yes/No segmented with the default, Trade-offs summary, no raw keys/JSON in help); qa verified `48h 00m` live. Requirements 6/7 in progress (fe-setup).

**Supersede preview (fe-setup b749005c):** accepted: `Saving v7 supersedes 1 open draft: Sun 15 Nov (r1, QA Operator). It'll need drafting again.` + `Save v7 · supersede 1 draft`; already-superseded drafts not counted; the policy save untouched (api: policy versions don't supersede). The template Edit button was dead (missing import) and now works.
