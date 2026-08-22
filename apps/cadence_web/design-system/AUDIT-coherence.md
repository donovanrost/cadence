# Design-coherence audit

The design system was written as a *characterization* of UI that grew ad-hoc — it
documents what the app happens to do. This audit asks the question the
characterization couldn't: **does the design make sense as a system?** It was
prompted by three suspicions, all confirmed: hud-corners applied without meaning,
card border colors that fight the status chips inside them, and raw daisyUI
persisting past the component migration.

**Scope:** the management surface. The ops console (`ops_dashboard_*`,
`ops_telemetry_explore`, `ops_shell.ex`) is its own design language by decision
and is exempt — noted only where it leaks. `/ops/data-sources` sits in the ops
shell but is a *setup* surface, so it got a targeted follow-up treatment
(2026-07-04): its local `status_pill` now delegates to `<.status_badge>` (which
gained `:rest` passthrough), `inventory_stat` was replaced by `<.stat_tile>`,
binding-id cyan → base-content, and five dead daisyUI-4 `hover:text-primary-focus`
classes → `hover:underline`. Its selection-state cyan (`border-primary/30` on
matched, the focused-resource rail) and the ops-shell `border-primary/20` frames
were deliberately kept — selection/focus is a legitimate cyan job, and the frames
are the shell's own language.

**Method:** exhaustive greps of `lib/cadence_web/` + the component layer; rendered
screenshots of representative pages (Playwright against the dev app, temp
platform-admin, since removed). Screenshots referenced below live in
`/tmp/ds-verify/audit/` (session artifacts — re-capture with the same tour script
if needed). Each finding names the principle or rule it collides with.

**Status: decisions accepted and APPLIED (2026-07-04).** All six decision-list
answers were taken as recommended and the findings below are now fixed in code:
corners are nav/hero-only (`hover_glow`/`corners` on `<.card>`), `accent` is
retired, `<.callout>` exists and replaced every raw alert, the raw
badge/card/heading/detail-row duplicates are migrated, flash is on tokens at
2px, the severity badge is 2px, and the decorative cyan is swept. This document
is kept as the record of what was found and why the calls were made.

---

## Finding 1 — hud-corners are component chrome pretending to be a signal

**Evidence.** `.hud-corners` (defined `assets/css/components/hud-system.css:250`)
is applied in exactly three places, all component-internal:
`components/card.ex:39` (every `<.card>`, unconditionally), `card.ex:97` and
`card.ex:105` (both `<.stat_tile>` variants). Zero hand-applications anywhere in
`live/`. Screenshot `A1-spacecraft-show.png`: five cards on one page, every one
wearing cyan brackets.

**Why it's incoherent.** The brackets read as a *signal* — bright, saturated cyan,
the color the system reserves for "actionable/live" (choosing-color card). But
they mean nothing: they mark "this element used the card component." Worse, the
signal isn't even reliable as chrome — hand-rolled panels
(`ops_telemetry_explore_live.ex:453`, Finding 5) skip them, so the perceived rule
("some things have corners, some don't") is really "component users get corners,
hand-rollers don't." Principle 1 (density over decoration) and the cyan-scarcity
rule both lose.

**Recommendation.** Three coherent options; the incoherent one is the status quo.

- **(a) Retire the corners** from `<.card>`/`<.stat_tile>` defaults. Keep the CSS
  class for deliberate hero use. Cheapest, calmest; `A3-spacecraft-show-no-corners.png`
  shows the page loses nothing legible — the border still frames, chips still shout.
- **(b) Corners = navigation/hero only.** Make them opt-in (`corners` attr paired
  with or implied by `hover_glow`), so brackets mean "this card takes you
  somewhere / is the page's hero." Gives the flourish a job; costs a migration
  pass and a rule people must remember.
- **(c) Corners on everything** — including the hand-rolled panels (which Finding 5
  wants converted to `<.card>` anyway). Coherent as pure brand texture, but doubles
  down on decorative cyan and dilutes "cyan = act."

**Recommended: (b)**, with (a) as the close second. (b) preserves the HUD identity
where it earns attention (nav cards already glow on hover — brackets complete that
vocabulary) and removes ~90% of the decorative cyan without abandoning the
aesthetic. If, when you see option (b) rendered, the mostly-bracket-less app feels
like it lost its character everywhere that matters — take (a) and let glow alone
mark navigation.

## Finding 2 — card `accent` is 100% redundant with the chip inside it

**Evidence.** `accent` renders a colored `border-l-2` (`card.ex:66-70`). All six
call sites pair it with a `<.status_badge>` computed from the same status, inside
the same card:

| accent | badge |
|---|---|
| `spacecraft_show_live.ex:211` | `:214` |
| `spacecraft_show_components.ex:15` | `:80/:86/:92` |
| `spacecraft_applications_live.ex:111` | `:117` |
| `spacecraft_applications_live.ex:57` (hardcoded `:warning`) | `:82` |
| `spacecraft_readiness_live.ex:122` | `:125` |
| `comms_components.ex:17` | `:20` |

No accent exists without a chip; no colored card border exists outside status duty
(sole `class` border override is a `border-dashed` empty state,
`ops_dashboard_list_live.ex:118`). Screenshots: `A1` (accent + chip + corners
stacked three-deep) vs `A2-spacecraft-show-no-accent.png` (chip only — status
survives intact).

**Why it's incoherent.** "Status is always a color" (principle 3) doesn't mean
"status is every color available." Two encodings of one fact on one card isn't
reinforcement, it's noise — and it collides with the corners (cyan bracket, orange
left edge, orange chip: three colored frame elements per card in `A1`). The
glanceability argument for the border ("read status at distance") is real for a
*wall* of cards, but these are 3-4 card workflow rows where the chips are already
the most salient element.

**Recommendation: chip owns status; retire `accent` from `<.card>`.** The six call
sites drop one attr each. If a genuine at-distance case appears later (a dense
grid of dozens of status cards), reintroduce the border *as a documented variant
that replaces the chip* — one encoding, chosen per context — rather than stacking.
The alternative (codify both, always) is defensible only if you decide the
double-signal *is* the house style; it wasn't chosen, it accreted.

## Finding 3 — cyan spent decoratively on data

**Evidence.** Non-interactive text set in the action color:
`spacecraft_show_live.ex:96` (SCID value, `text-primary/80` + legacy `mc-value-small`
class), `spacecraft_list_components.ex:109` (whole Protocols column,
`uppercase text-primary/80`), `:219` (SCID cell), `comms_routing_show_live.ex:121`
(event type). Screenshot `E1-spacecraft-list-decorative-cyan.png` — the Protocols
column glows like a link column; nothing in it is clickable. Also
`spacecraft_routing_live.ex:73`: a hand-rolled card with `hover-glow-cyan` — a
*navigation* card, so the glow is legitimate, but it bypasses `<.card hover_glow>`
(double finding with 4).

Related: E1 also shows status color *saturation* — 300 rows each carrying an
orange setup chip. That's partly demo data, but the pattern (a per-row chip for a
state most rows share) spends warning-orange like a default, not an exception.

**Why it's incoherent.** The system's sharpest rule — saturated cyan means "you
can act on this / it is live" — is exactly the rule that makes a dense console
scannable. Every decorative use taxes it. (This is the already-locked "cyan
reallocation" direction; these are the concrete violations on the management
surface.)

**Recommendation.** Mechanical: data values go `text-base-content` /
`font-mono`; identifiers that want emphasis use full base-content, not primary.
The one judgment call: whether SCID in the page header keeps a brand-cyan tint as
"identity" — recommend no (it's data). For the chip wall, consider showing the
setup chip only for non-nominal states once real fleets are mostly configured —
absence of a chip is the calm state.

## Finding 4 — raw daisyUI residue: small, mappable, two-thirds migration debt

**Evidence (non-ops).** Buttons: **zero** raw `btn` — that migration completed.
Remaining:

- **Badges duplicating `<.status_badge>` (~10):** worst is
  `catalog/components.ex:11-22` — a local `import_run_status_badge/1` component
  reimplements the status badge wholesale; plus one-off `badge badge-outline`/`badge-sm`
  pills at `comms_routing_show_live.ex:56`, `comms_transport_show_live.ex:74`,
  `admin_organization_show_live.ex:70`, `catalog_index_live.ex:124`.
- **Cards duplicating `<.card>` (~10):** `notifications_live.ex:110,113`,
  `spacecraft_routing_live.ex:73,75` (the glow card from Finding 3),
  `catalog/components.ex:242`.
- **Alerts (5) — a real component gap:** `catalog_import_run_show_live.ex:303`,
  `catalog/components.ex:174,193`, `spacecraft_telemetry_decom_live/components.ex:193`.
  No `<.alert>`/inline-callout component exists; flash is the only sanctioned
  message surface, and it's a toast, not an inline callout.
- **Hand-rolled near-duplicates:** section headings rebuilt at
  `admin_runtime_live.ex:307,324,340,356` and `notifications_live.ex:152`
  (vs `<.section_header>`); `dt/dd` key-value grids at
  `catalog_artifact_show_live.ex:120-126`, `catalog_revision_show_live.ex:77-87`,
  `catalog_import_run_show_live.ex:263-271` (vs `<.detail_row>`,
  `core_components.ex:121`).

(Ops console, for the record and out of scope: raw btn=79, badge=226, dropdown=24.)

**Why it matters.** Each duplicate is a place the next visual decision (Findings
1-2, the Phase 5 token work) silently won't apply. The catalog area is the
hotspot — it grew its own mini component layer.

**Recommendation.** Mechanical migration list, no design decision needed except
one: **add an inline `<.callout>` component** (the alert gap) rather than
migrating alerts to flash — those five sites are contextual warnings that belong
in-page. Fold this list into Phase 5 as its opening (lowest-risk) step.

## Finding 5 — same content, forked chrome

**Evidence.** The canonical content panel is `<.card>` (`bg-base-200
border-base-300` + corners). Forks: `ops_telemetry_explore_live.ex:453` builds
`border border-base-300/70 bg-base-100/40` sections (ops-exempt, but the pattern
tempts); `historical_workflow_request_form_components.ex:109,125` use `rounded`
(4px) containers against the app-wide 2px radius; `notifications_live.ex:110` and
`spacecraft_routing_live.ex:73` hand-build card chrome with drifted values.

**Why it's incoherent.** Principle 6 — one way to do each thing. Every fork also
invalidates Finding 1's premise ("cards have corners") from the other side.

**Recommendation.** Management surface: content panels are `<.card>`, full stop
(the Finding 4 migrations get most of the way). If a genuinely lighter container
is wanted (the explore-style quiet panel), mint it once as a documented `<.card
variant={:quiet}>` — don't let each page pick its own opacity.

## Finding 6 — the component layer disagrees with itself

**Evidence.**

- **Flash toasts are off-system entirely:** `components/ui.ex:28,34` —
  `rounded-[1rem]` (vs 2px everywhere), raw `rgba(147,242,200,…)` /
  `rgba(255,142,133,…)` literals (vs oklch tokens; that green isn't even hue 175),
  bespoke mega-shadow. The most-seen transient surface in the app follows none of
  the system's rules.
- **`<.severity_badge>` uses Tailwind `rounded`** (4px, `badges.ex:67`) while
  `<.status_badge>` is `rounded-full` and everything else is 2px — three radii
  across two sibling badges and the cards they sit on.
- **Contrast-tier drift:** `ui.ex` leans `/60` (5 uses) where `page_header`/
  `list_controls`/`form_inputs` use `/70` for equivalent informational text —
  the codified tiers (CLAUDE.md) say informational is `/70` minimum.

**Recommendation.** Flash restyle to tokens + 2px (one file); pick one badge
radius story (recommend: status pills stay `rounded-full`, severity moves to 2px
to match the data-density aesthetic); sweep `ui.ex` `/60`s against the tier table.
All small, none blocked on a decision except the badge radius.

---

## Decision list

1. **hud-corners** — retire / navigation-and-hero-only / everywhere?
   **Recommended: navigation + hero only** (opt-in, paired with the glow
   vocabulary); fallback: retire.
2. **Card status** — does the chip own it? **Recommended: yes** — drop `accent`
   from `<.card>`; border-as-status returns only as a chip-replacing variant if a
   dense-grid case ever demands it.
3. **Inline callout** — add `<.callout>` for the five in-page alerts, or force
   them into flash? **Recommended: add `<.callout>`.**
4. **Quiet panel** — sanction a `<.card variant={:quiet}>` or forbid lighter
   panels on the management surface? **Recommended: forbid until a real need,
   then mint once.**
5. **Badge radius** — unify severity badge on 2px? **Recommended: yes.**
6. **SCID/identifier tint** — plain data color or brand cyan? **Recommended:
   plain.**

Everything else in this report is mechanical once these are answered. Suggested
sequencing after decisions: Finding 4 migrations first (they make the surface
uniform), then 1+2 together (one visual-change PR, reviewed as a pair since both
recompose card chrome), then 6, then 3.
