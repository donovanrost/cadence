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
