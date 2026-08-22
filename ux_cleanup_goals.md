# UX Cleanup — `/goal` prompts

Each block below is a self-contained prompt for `/goal` (or any autonomous-execution surface). They are ordered by priority. Each one:

- Names the outcome and the *why* (so the agent can resolve edge cases).
- Lists the current-state anchors (files / lines / commits).
- States the constraints that override default behavior.
- Defines "done" as something verifiable.
- Calls out where the agent must make a judgment call — and gives it permission to.

Run them one at a time. They are independent unless noted.

---

## P0 — Goal 1: Finish the comms rename

```
/goal

Finish the half-done rename in the comms area so users see one canonical noun for each concept, in URLs, sidebar, page copy, and module names.

WHY
The product renamed "path templates" → "link templates" and "transport profiles" → "protocol behaviors", but only some surfaces moved. Right now:
- Router (apps/cadence_web/lib/cadence_web/router.ex) defines THREE prefixes that all mount the same path-template LiveViews: /comms/links, /comms/path-templates, /comms/link-templates. Same problem for transport profiles: /comms/transport-profiles and /comms/protocol-behaviors both mount the same module.
- The /comms overview's "Links" Network Resources card navigates to /comms/links/new, which renders a "Link Template" page. URL says "links", UI says "link templates".
- Modules and files still use the old names: CommsPathTemplateListLive, CommsTransportProfileListLive, comms_path_template_*.ex, comms_transport_profile_*.ex. The schema/context types likely still say path_template / transport_profile too.
This is a credibility problem (three URLs for one page) and a maintenance problem (future devs will have to learn the old vocabulary to navigate the code).

REASON THEN ACT
1) Decide the canonical user-facing nouns. The recent direction is clearly:
     path template  → link template
     transport profile → protocol behavior
   Confirm by skimming the most-recent commits (`git log --oneline -20 -- apps/cadence_web`) and the /comms overview copy. If the recent direction holds, commit to it.

2) Decide the URL canonical form. Pick the noun-plural form that matches the UI:
     /missions/:id/comms/link-templates
     /missions/:id/comms/protocol-behaviors
   Mark the other prefixes as legacy aliases — they should issue a 301 redirect (Phoenix.LiveView.redirect or a controller redirect) to the canonical path, NOT mount parallel LiveViews. Phoenix routers can express this as a `get` route that redirects, or with a `live_redirect`-on-mount shim. Pick the lowest-ceremony approach that keeps deep links working.

3) Update every place that navigates to a legacy alias to use the canonical one. Greppable targets:
     ~p"/missions/.../comms/links"        → link-templates
     ~p"/missions/.../comms/path-templates" → link-templates
     ~p"/missions/.../comms/transport-profiles" → protocol-behaviors
   Watch for the comms overview card whose CTA points at /comms/links/new — fix that too.

4) Rename modules and files to match. CommsPathTemplate* → CommsLinkTemplate*, CommsTransportProfile* → CommsProtocolBehavior*. File names follow. Update the router and any references. Keep the schema field/struct names (path_template_id, transport_profile_id) as-is unless they're trivially renamed at the same time — the DB rename is a separate, riskier change and is OUT OF SCOPE for this goal. (If the struct/key rename is small and self-contained, fine, but don't start a migration.)

5) Page titles, h1s, sidebar labels, breadcrumbs: ensure they all say the canonical noun.

CONSTRAINTS
- CLAUDE.md rules apply: `mix compile --warnings-as-errors`, `mix credo --strict`, `mix format`, never add CSS rules, never write raw HTML inputs.
- DO NOT rename DB columns or schema field names in this pass. URL aliases and module renames only.
- DO NOT remove the legacy aliases without a redirect — old bookmarks must still work.
- Keep diffs tight: file renames + import updates + router edits should be the bulk. No drive-by refactors.

DONE WHEN
- One canonical URL per concept; legacy URLs 301 to canonical.
- One canonical noun in sidebar, page titles, body copy, card CTAs.
- Modules and filenames match the new noun.
- `mix compile --warnings-as-errors`, `mix credo --strict`, `cd apps/cadence_web && mix test` all pass.
- A grep for "path_template" and "transport_profile" in apps/cadence_web/lib (outside schema-related code) returns no user-visible hits.

VERIFY
- `grep -rn "path-templates\|transport-profiles" apps/cadence_web/lib/cadence_web/live` returns only redirect declarations.
- Hit /missions/<id>/comms/path-templates in dev — confirm 301 to /comms/link-templates.
- Sidebar shows "Link Templates", URL bar shows /comms/link-templates, page h1 says "Link Templates".
```

---

## P0 — Goal 2: Decide what "advanced" means and finish that refactor

```
/goal

Resolve the half-removed "advanced" concept in the comms area: either surface it consistently or remove it everywhere — including URLs, the mission-overview card, and any orphaned navigation.

WHY
Recent commits dropped the "Advanced" card from the comms Network Resources grid (59a0ee0) and the comms sub-tab rail (baa20b3). But:
- apps/cadence_web/lib/cadence_web/live/mission_show_live.ex:54 still renders a card titled "Advanced Objects" that links to /missions/:id/comms/advanced/runtime-identities. That URL path is the ONLY way to reach runtime identities from navigation.
- /comms/source-endpoints exists but has no sidebar entry and no card on the comms overview.
- The sidebar shows three children under Comms (Overview, Providers, Link Templates), but the data model has six user-facing entity types: providers, protocol behaviors, link templates, source endpoints, runtime identities, link assignments.

So the user sees an inconsistent IA: some primary entities are in the sidebar, others are only reachable via deep links on dashboards. The recent removals went halfway.

REASON THEN ACT
This is the judgment call: decide which entities are FIRST-CLASS (sidebar nav, list page, CRUD) and which are SECOND-CLASS (created only via guided workflows, not navigable on their own).

Read the comms LiveViews and components briefly (apps/cadence_web/lib/cadence_web/live/comms_*.ex) to ground your decision. Then commit to ONE of two paths:

PATH A — runtime identities + source endpoints are user-facing primary objects
- Add sidebar entries for both under the Comms section.
- Add Network Resource cards on /comms.
- Rename the URL path: /comms/advanced/runtime-identities → /comms/runtime-identities (with a 301 from the old path).
- Remove the word "advanced" from copy. The mission-overview "Advanced Objects" card becomes "Network Resources" or similar, and links to /comms.
- Module renames: CommsSourceEndpoint* stays; anything named *Advanced* gets renamed.

PATH B — runtime identities and source endpoints are plumbing, created only inside workflows
- Remove their list pages from navigable URLs (keep show pages reachable from deep links / guided flows).
- Delete the mission-overview "Advanced Objects" card outright.
- /comms/advanced/runtime-identities and /comms/source-endpoints get folded into the workflows that produce them (link templates, providers).
- This is the lower-IA-surface answer. Pick this if the entities are genuinely never something a user manages in isolation.

Pick the path that matches the rest of the product. Lean toward PATH A if you find list-page UIs that are clearly designed for direct user management; lean toward PATH B if those pages look like internal admin views.

CONSTRAINTS
- CLAUDE.md rules apply.
- "Advanced" should not appear in any URL, sidebar label, card title, or body copy after this change. If you find it, either rename it (Path A) or remove the surface (Path B).
- The mission-overview "Advanced Objects" card MUST be either renamed (Path A) or deleted (Path B). It is the most prominent surface of the word.
- Keep legacy URL bookmarks working via 301 redirect.

DONE WHEN
- `grep -rn -i "advanced" apps/cadence_web/lib/cadence_web/{live,components,router.ex}` returns no user-visible hits.
- The user can reach every primary entity from the sidebar (Path A) OR no primary entity is orphaned (Path B).
- `mix compile --warnings-as-errors`, `mix credo --strict`, `cd apps/cadence_web && mix test` pass.

VERIFY
- Click through /comms in dev: every Network Resource card lands on a real page; sidebar entries lead to real pages; no dead ends.
- /missions/:id mission overview no longer shows "Advanced Objects".
- Old URL /comms/advanced/runtime-identities either 301s to the canonical path (Path A) or 404s with a sensible message (Path B).
```

---

## P1 — Goal 3: Collapse the spacecraft show page duplication

```
/goal

Eliminate the duplicated navigation affordances on the spacecraft show page so each destination has ONE clear entry point on the page, not three.

WHY
apps/cadence_web/lib/cadence_web/live/spacecraft_show_live.ex has, on a single screen:
  - Header buttons: Readiness, Links, Identity (lines ~67–93)
  - A five-card workflow grid: Identity, Telemetry, Links, Command, Readiness (lines ~97–153) — each card already has its own navigate link
  - A standalone "Telemetry Interpretation" card BELOW the grid (lines ~192–197) that duplicates the Telemetry card

Same 4 destinations are reachable 2–3 times within ~1 screen. The duplicate telemetry section is a literal repeat. This is noise that hides the page's real purpose and grows worse with more spacecraft data.

DO
1) Delete the three header buttons (Readiness, Links, Identity). The workflow grid below already covers them. Keep the `← Spacecraft` back-link.
2) Delete the standalone telemetry_decom_section card entirely. The Telemetry workflow card in the grid already shows the same status, label, description, and a navigate to the same destination.
3) After deletion, the page should read: back-link + h1 → workflow grid (5 cards) → Overview card (detail rows + metadata).
4) Audit the helper functions for any dead code (label/1, description/1, configure_label/1, telemetry_decom_section/1) — remove what's no longer used.
5) Confirm no tests broke. If a test asserted on a header-button selector (#spacecraft-readiness-link, #spacecraft-links-link, #spacecraft-identity-link, #spacecraft-telemetry-decom-configure-link), the test is asserting on duplicate UI — update the test to target the workflow card's link instead.

CONSTRAINTS
- CLAUDE.md rules apply.
- DO NOT change the workflow grid itself; it's the right pattern.
- DO NOT introduce a new "actions" dropdown to replace the header buttons — the grid IS the action surface. The page does not need a separate action row.
- Page should remain under 400 lines after the cuts (it's already over; this should help).

DONE WHEN
- No duplicate navigate targets remain on the page.
- `cd apps/cadence_web && mix test` passes.
- `mix compile --warnings-as-errors`, `mix credo --strict`, `mix format` clean.
- Manual: open a spacecraft page in dev, confirm the 5-card grid is the single nav surface and the Overview card sits below it.

VERIFY
- `grep -n "spacecraft-readiness-link\|spacecraft-links-link\|spacecraft-identity-link\|spacecraft-telemetry-decom-configure-link" apps/cadence_web/lib apps/cadence_web/test` only finds test references that have been updated.
```

---

## P1 — Goal 4: Consolidate status vocabulary to three user-visible states

```
/goal

Reduce the status vocabulary the user sees to a clear, fixed set of three states (plus an "info/placeholder" for non-actionable cards), and keep the richer internal lifecycle states as sub-labels rather than separate colors.

WHY
The codebase currently surfaces at least six status atoms across two parallel vocabularies:
  status_badge: :ready, :warning, :missing, :info
  status_dot:   :nominal, :info, :warning, :offline
And spacecraft_show_live.ex:321–325 has a mapping function (dot_status/1) translating one to the other. A user has to learn that :nominal == :ready, that :offline and :missing are different shades of "bad", and that :info is sometimes "you have nothing to do" and sometimes "this feature is unfinished".

Three states is enough for the user to scan a screen:
  :ready     — green-ish, "this is good"
  :attention — amber-ish, "do something here" (covers what's now :warning, :outdated, :configured pending)
  :blocked   — red-ish, "this can't work yet" (covers what's now :missing, :disabled, :offline)
Plus an :info state for placeholders / informational rows that have no badge color, just text.

REASON THEN ACT
1) Audit all callers of status_badge/1 and status_dot/1 (grep across apps/cadence_web/lib/cadence_web). Catalog each atom used and what it means in context.
2) Define the new atoms in CadenceWeb.CommsComponents (or wherever status_badge lives): :ready, :attention, :blocked, :info. Update status_badge to render those four.
3) Map every legacy atom call site to the new vocabulary. Example mappings (verify per-site):
     :warning, :outdated, :configured  → :attention
     :missing, :disabled, :offline     → :blocked
     :nominal                          → :ready
     :info                             → :info (no change)
   Keep the sub-label text (e.g., "Configured — not yet applied", "Out of date") as the label passed to status_badge — the COLOR collapses, the WORDS don't.
4) Delete status_dot/1 and dot_status/1 — fold the dot rendering into status_badge so there's one component for status presentation. (If status_dot is needed for a denser layout, keep it but make it consume the same three atoms.)
5) Update tests that assert on the old atoms.

CONSTRAINTS
- CLAUDE.md rules apply. No new CSS.
- DO NOT change the internal lifecycle atoms in the domain layer (Cadence.* contexts). The domain may still emit :applied, :configured, :outdated, :disabled, :not_configured — those are valid internal states. The presentation-layer mapping is what changes.
- Keep accessibility in mind: badges must still have a text label, not color only.

DONE WHEN
- status_badge accepts only :ready, :attention, :blocked, :info.
- status_dot is either deleted or refactored to the same vocabulary.
- No LiveView calls status_badge with a legacy atom.
- `mix compile --warnings-as-errors`, `mix credo --strict`, `cd apps/cadence_web && mix test` pass.

VERIFY
- `grep -rn "status_badge\|status_dot" apps/cadence_web/lib` shows only the canonical atoms.
- Visual sweep: open /missions/:id, /missions/:id/comms, /missions/:id/spacecraft/:id — confirm badges still convey the right intent with the new collapsed vocabulary.
```

---

## P1 — Goal 5: Brand the sign-in page and unify the sidebar component usage

```
/goal

Two small fixes that improve first-impression and reduce maintenance fragility.

PART A — sign-in branding
WHY
apps/cadence_web/lib/cadence_web/live/user_session_live.ex is the first authenticated touchpoint and currently shows only "Sign in" + form. No wordmark, no helper hint for users who don't have access. For a multi-tenant SaaS the "no account? contact your admin" line is meaningful.

DO
1) Add the Cadence wordmark above the form. Match the sidebar treatment (in sidebar.html.heex, line 54: "◆ CADENCE" in primary color, tracking-[0.15em]). Reuse the same visual treatment so the brand reads as one product.
2) Below the submit button, add: "Need access? Contact your organization admin." in text-base-content/60, text-xs.
3) Keep the form behavior unchanged.

PART B — sidebar component unification
WHY
apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex (lines 69, 75, 94, 100) open-codes nav items with long copy-pasted class strings, while mission_sidebar.html.heex correctly uses the <.nav_item> component. Same visual output, but maintenance lives in two places.

DO
1) Replace the four open-coded <li><a class="..."> blocks in sidebar.html.heex with <.nav_item> calls. The component is in apps/cadence_web/lib/cadence_web/components/sidebar.ex.
2) Confirm the active-state visuals match exactly. The component handles border-l-2, active background, glow, text color.
3) After the swap, the two layout files should both use <.nav_item> identically; sidebar.html.heex should be meaningfully shorter.

CONSTRAINTS
- CLAUDE.md rules apply.
- No new CSS. No new component variants — the existing <.nav_item> should be sufficient. If it isn't, surface the gap and stop (don't invent a variant for one caller).
- For PART A, do NOT add a "forgot password" link unless that flow exists; placeholder links are worse than no links.

DONE WHEN
- Sign-in renders the wordmark and the helper text.
- sidebar.html.heex uses <.nav_item> for all entries; no inline `class={[... if(active, ...)]}` blocks for nav items remain.
- `mix compile --warnings-as-errors`, `mix credo --strict`, `mix format`, `cd apps/cadence_web && mix test` pass.

VERIFY
- Open /sign-in: wordmark visible, helper text present.
- Open /admin and / (org home): sidebar items still highlight active state correctly.
```

---

## P1 — Goal 6: Tighten the mission overview and comms overview copy + empty states

```
/goal

Three small textual / structural fixes on the two main overview pages.

DO
1) apps/cadence_web/lib/cadence_web/live/mission_show_live.ex
   - Around line 84: the empty state and the readiness table both render. Wrap the <table>...</table> in `<div :if={not @spacecraft_readiness_empty?}>` so the headers don't appear below the empty-state message.

2) apps/cadence_web/lib/cadence_web/live/comms_overview_live.ex
   - Around line 65: the body copy says "Runtime contact health belongs under the future ops workspace." That's roadmap leakage. Rewrite to describe what this section DOES cover, without referencing unbuilt surfaces. Suggested: "These checks cover saved comms setup. Runtime link health is shown elsewhere." Adjust to fit voice.

3) apps/cadence_web/lib/cadence_web/live/spacecraft_show_live.ex
   - The "Command Interpretation" workflow card (around lines 131–141) ships a placeholder with hardcoded value "Not tracked" and description "...will live here." Decide: if the /commanding LiveView is real and usable, replace the placeholder values with real data (read from the commanding context). If it's not yet usable, DELETE the card entirely — placeholders in production UI look like broken features. Audit SpacecraftCommandingLive to make the call.

CONSTRAINTS
- CLAUDE.md rules apply.
- DO NOT add a roadmap disclosure ("Coming soon", a <details> stub) unless the placeholder removal would leave a visibly unbalanced grid that misleads users. The grid going from 5 to 4 cards is fine.

DONE WHEN
- Mission overview empty state shows only the empty hint, not headerless tables.
- Comms overview copy contains no reference to "future ops workspace" or other unbuilt surfaces.
- Spacecraft show "Command Interpretation" is either a real card with real data or removed.
- `mix compile --warnings-as-errors`, `mix credo --strict`, `cd apps/cadence_web && mix test` pass.

VERIFY
- In dev, open a mission with zero spacecraft: see only the empty hint, no table headers.
- /comms overview reads cleanly without referencing unbuilt areas.
- Spacecraft page: grid is consistent, no obvious placeholder.
```

---

## P2 — Goal 7: Build out the organization home and mission list density

```
/goal

The two top-of-funnel landing pages (org home and mission list) are anemic and don't give an operator anything to scan. Add fleet-relevant density.

WHY
- apps/cadence_web/lib/cadence_web/live/organization_home_live.ex is one card showing mission count + a "View Missions" CTA. For a multi-mission org this is a wasted landing.
- apps/cadence_web/lib/cadence_web/live/mission_list_live.ex has only display_name + slug + a kebab menu with one item ("View"). Operators landing here can't tell which mission needs attention.

REASON THEN ACT
For the org home, decide what's high-signal for a fleet operator landing fresh:
  - Recent missions (top 3, sorted by last activity timestamp if available, else by created_at desc)
  - Mission count, spacecraft count, member count (compact stats row)
  - If notifications exist for the user, show top 3 unread
Read the existing Cadence context functions before inventing new ones. If `Cadence.list_missions/1` doesn't return last-activity data, that's fine — sort by what exists and call it "Recent".

For the mission list, add at least:
  - Spacecraft count column (Cadence.list_spacecraft/2 already exists per mission_show_live)
  - A "Status" column showing :ready or :attention based on whether any spacecraft has setup issues (reuse SpacecraftCommsReadiness — same logic the mission overview uses)
  - Make the whole row navigate to the mission (drop the single-item action menu; if a future second action shows up, reintroduce it then)

CONSTRAINTS
- CLAUDE.md rules apply. <.action_menu> is for multiple actions only; with one, prefer a row-level click target.
- DO NOT introduce N+1 queries. If computing readiness per mission is expensive, batch it or compute a cheap proxy (e.g., spacecraft count alone is fine for a first pass; defer the status pill if it's expensive).
- DO NOT add charts, sparklines, or any new visual primitives. Use cards + tables + status badges that already exist.

DONE WHEN
- Org home shows at least: recent missions list (or empty state if none) + a compact stats row.
- Mission list shows display_name + slug + spacecraft count + status; rows navigate on click; no kebab menu unless there are ≥2 actions.
- `mix compile --warnings-as-errors`, `mix credo --strict`, `cd apps/cadence_web && mix test` pass. New tests for the added columns/affordances.

VERIFY
- Open / with several missions: see a usable landing page.
- Open /missions: see actionable density, not a sparse table.
```

---

## P2 — Goal 8: Add a lightweight breadcrumb / context line for deep pages

```
/goal

Help users orient inside the org → mission → spacecraft → sub-page hierarchy with a single-line breadcrumb component.

WHY
The IA is up to four levels deep. Currently the spacecraft show page has a `← Spacecraft` back-link (one step), but there's no context for "which mission am I in" beyond the sidebar (which collapses) and no orientation on spacecraft sub-pages (identity, links, telemetry, readiness, commanding).

DO
1) Add a `<.breadcrumbs>` component to apps/cadence_web/lib/cadence_web/components/ui.ex (or a new file in components/). It takes a list of `{label, path_or_nil}` tuples and renders them separated by a chevron, last item un-linked and in stronger text.
2) Add the component to the top of these LiveView render functions, above the page h1:
   - spacecraft_show_live.ex                  → Mission · Spacecraft · <name>
   - spacecraft_edit_live.ex (identity/edit)  → Mission · Spacecraft · <name> · Identity
   - spacecraft_links_live.ex                 → Mission · Spacecraft · <name> · Links
   - spacecraft_readiness_live.ex             → Mission · Spacecraft · <name> · Readiness
   - spacecraft_telemetry_decom_live.ex       → Mission · Spacecraft · <name> · Telemetry
   - spacecraft_commanding_live.ex            → Mission · Spacecraft · <name> · Commanding
   - catalog/*                                 → Mission · Catalog · <database/revision/etc>
3) The "Mission" link goes to /missions/<id>. The "Spacecraft" link goes to the spacecraft list. The last segment is non-linked text.
4) On the spacecraft show page specifically, drop the existing `← Spacecraft` back-link in favor of the breadcrumb — they're redundant.

CONSTRAINTS
- CLAUDE.md rules apply. No new CSS rules.
- Use text-xs text-base-content/60, chevron between segments (hero-chevron-right h-3 w-3), last segment text-base-content (full strength).
- Mobile: the breadcrumb should wrap, not overflow. A simple `flex flex-wrap items-center gap-1.5` handles it.
- DO NOT replace page h1s. Breadcrumbs sit ABOVE the h1, they don't replace it.

DONE WHEN
- Breadcrumb component exists and is reused across the listed pages.
- Spacecraft show no longer has the `← Spacecraft` back-link.
- `mix compile --warnings-as-errors`, `mix credo --strict`, `cd apps/cadence_web && mix test` pass.

VERIFY
- Navigate to /missions/<id>/spacecraft/<sid>/telemetry; the breadcrumb shows the full path and each linked segment works.
```

---

## How to run

- Run them in order. Goals 1 and 2 are the highest-value; the rest can be sequenced as time allows.
- Each prompt expects the agent to make small judgment calls and document them in the commit message — don't paste these into a tool that's been told to "ask before anything", because the prompts themselves authorize the judgment calls.
- After each goal completes, manually verify in the browser before moving on — type-checks confirm correctness, not feature correctness.
