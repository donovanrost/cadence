# Expandable mission sidebar navigation

## Goal

Introduce a generic, reusable mechanism for the mission sidebar to disclose
nested pages under a top-level entry. Apply the mechanism to **Comms** only for
this iteration, with a single child entry ("Overview") that links to the
existing `/missions/:mission_id/comms` route. Other top-level items
(Spacecraft, Catalog) keep working as flat leaves; they can adopt the same
pattern later without further component changes.

This is the first step in a broader UI/UX polish pass on the comms and
spacecraft pages — the navigation enhancement is intentionally minimal so
content (which child pages to surface) can be decided iteratively.

## Non-goals

- Restructuring the comms route tree.
- Deciding which comms sub-pages are eventually surfaced in the sidebar — that
  is a follow-up decision.
- Sidebar-collapsed (icon-only) mode redesign. Existing hover-to-expand CSS
  must continue to work; no new behavior added there.
- Persisted user preference for expand state.

## Component design

A new module `CadenceWeb.Components.Sidebar` exports two function components:

- `nav_item/1` — renders a leaf entry. Replaces the inlined `<li>` blocks that
  currently repeat the same ~200-character `class={[...]}` expression four
  times in `mission_sidebar.html.heex`.
- `nav_section/1` — renders an expandable group. Uses a native HTML
  `<details>` element, with the parent label rendered inside `<summary>` and
  child entries (passed via an `:item` slot) rendered as `<li>` rows in a
  nested `<ul>`.

### `nav_item/1` API

```elixir
attr :navigate, :string, required: true
attr :icon, :string, required: true       # heroicon class, e.g. "hero-signal"
attr :label, :string, required: true
attr :active, :boolean, default: false
```

Renders the existing leaf row style. The active visual treatment
(`bg-primary/10`, primary left border, glow inset) is unchanged.

### `nav_section/1` API

```elixir
attr :icon, :string, required: true
attr :label, :string, required: true
attr :active, :boolean, default: false       # parent row active state
attr :expanded, :boolean, default: false     # initial open state
slot :item do
  attr :navigate, :string, required: true
  attr :active, :boolean
end
```

Rendered structure:

```heex
<li>
  <details open={@expanded}>
    <summary class={summary classes — full-width clickable row}>
      <span class={@icon}></span>
      <span class="sidebar-label">{@label}</span>
      <span class="hero-chevron-right ... section-chevron"></span>
    </summary>
    <ul>
      <li :for={item <- @item}>
        <.link navigate={item.navigate} class={leaf classes with deeper indent}>
          {render_slot(item)}
        </.link>
      </li>
    </ul>
  </details>
</li>
```

Notes:

- `@expanded` is the *initial* server-rendered `open` state. After mount, the
  user can click the summary row to toggle it; native `<details>` handles that
  with no JS or LiveView state.
- Sidebar links use `<.link navigate={...}>`, which causes a full LiveView
  mount on each click, so `@expanded` is re-derived from the new route on
  every navigation. There is no client-side state to drift.
- Chevron rotation uses a Tailwind selector tied to the `[open]` attribute on
  `<details>`, e.g. `group-open:rotate-90` with `group` set on the `<details>`
  element, or an equivalent utility expression. No new CSS rules are added —
  only Tailwind utilities and existing HUD classes.
- Child rows indent further (`pl-8` vs the parent's `pl-3`) so hierarchy is
  visible. Inactive child rows render with `border-transparent`, hovering
  promotes to `border-primary/20`, active state matches the existing leaf
  active treatment.

### Helper

A small helper `section_active?/2` lives in the same module and returns true
when the current `nav_item` belongs to a given section. It encodes the
membership of `nav_item` atoms in each section so call sites stay tidy:

```elixir
def section_active?(:comms, :comms), do: true
def section_active?(:comms_overview, :comms), do: true
def section_active?(_, _), do: false
```

The membership table grows as new comms children are added in later
iterations.

## Sidebar template changes

`apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`:

- Replaces the four inlined `<li>` blocks for Overview / Spacecraft / Catalog /
  Comms with calls to `<.nav_item>` / `<.nav_section>`.
- Comms uses `<.nav_section>` with one `<:item>` slot (Overview, navigating to
  `/missions/:mission_id/comms`).
- The other three remain `<.nav_item>` leaves.

The template stops having the same long class expression repeated four times.

## LiveView assignment changes

A new `nav_item` value is introduced: `:comms_overview`. It identifies the
comms overview page (`/missions/:mission_id/comms`) specifically, so the
sidebar can show the Overview child as active distinct from "section active,
unspecified child."

- `comms_overview_live.ex` switches its `assign(:nav_item, :comms)` to
  `:comms_overview`.
- All other comms LiveViews keep `:nav_item, :comms` for now. They render
  inside the section but no specific child entry is highlighted (because none
  exists yet).

In the sidebar template, `section_active?(@nav_item, :comms)` is true for both
`:comms` and `:comms_overview`, so the section auto-expands when the user is
on any `/comms/*` route.

## Visual treatment

- **Section row active** (any `/comms/*` route): existing primary-tinted
  treatment — `bg-primary/10`, primary left border, glow inset.
- **Child row active** (specific child page): same primary treatment, applied
  to the child `<li>`.
- When both are true (e.g., on `/comms` with the Overview child also active),
  both rows show the active style. This is intentional — it shows the path
  through the tree.
- No new CSS rules in any file under `apps/cadence_web/assets/css/`. All
  styling is composed from existing Tailwind utilities, daisyUI classes, and
  HUD utilities (`sidebar-label`, etc.).

## Collapsed sidebar interaction

The existing sidebar collapse toggle (`sidebar-collapsed` / `sidebar-expanded`)
already has CSS rules in `component-overrides.css` for `details > summary`
inside a collapsed sidebar (hover reveals labels and details). The new
component must continue to work under that toggle. No new CSS is required.

## Files

**New:**

- `apps/cadence_web/lib/cadence_web/components/sidebar.ex` — module exporting
  `nav_item/1`, `nav_section/1`, and `section_active?/2`.

**Edited:**

- `apps/cadence_web/lib/cadence_web/components/layouts.ex` — imports the new
  module so layout templates can use it.
- `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`
  — replaces the four inlined `<li>` blocks with `<.nav_item>` /
  `<.nav_section>` calls.
- `apps/cadence_web/lib/cadence_web/live/comms_overview_live.ex` — changes its
  `nav_item` assignment from `:comms` to `:comms_overview`.

**No CSS files are modified.**

## Tests

A LiveView test (in the existing mission sidebar test file, or a new one if
none exists yet) asserts:

1. Visiting `/missions/:id/spacecraft` (or any non-comms mission route)
   renders the mission sidebar with the Comms `<details>` element *not*
   carrying the `open` attribute.
2. Visiting `/missions/:id/comms` renders the Comms `<details>` with `open`
   set, the Overview child entry visible, and the Overview child marked with
   the active visual class.
3. The Spacecraft and Catalog leaf entries render unchanged on
   non-comms routes.

The assertions key off attribute presence and active-class substrings — no
DOM-snapshot fragility. Existing mission LiveView tests that incidentally
render the sidebar must keep passing.

## Quality gates

- `mix compile --warnings-as-errors` from the project root.
- `mix credo --strict` on touched files at minimum; do not regress overall
  count.
- `mix format` on every touched `.ex` and `.heex` file.
- `cd apps/cadence_web && mix test`.
- Manual smoke check in a browser: load `/missions/:id`, `/missions/:id/comms`,
  `/missions/:id/spacecraft`; toggle the sidebar collapse button; click the
  Comms section row to confirm expand/collapse works; navigate between routes
  to confirm auto-expand state derives from the route.
