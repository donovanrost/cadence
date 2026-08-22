# Expandable Mission Sidebar Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a generic expandable group component for the mission sidebar and use it to disclose a single "Overview" child under Comms.

**Architecture:** New `CadenceWeb.Components.Sidebar` module exporting `nav_item/1` (leaf), `nav_section/1` (expandable group built on native `<details>`), and `section_active?/2` (route-derived expand state). Mission sidebar template stops repeating its 200-char active-class blob and gains one expandable Comms group. The comms overview LiveView gets a new `:comms_overview` nav atom so its child entry can be highlighted distinctly from "section active, no specific child."

**Tech Stack:** Elixir, Phoenix LiveView, Phoenix.Component, Tailwind v4 (`open:` / `group-open:` variants), daisyUI 5, native HTML `<details>`/`<summary>`. No new CSS.

**Spec:** `docs/superpowers/specs/2026-05-02-expandable-sidebar-nav-design.md`.

---

## File map

**New:**
- `apps/cadence_web/lib/cadence_web/components/sidebar.ex` — module with `nav_item/1`, `nav_section/1`, `section_active?/2`.

**Modified:**
- `apps/cadence_web/lib/cadence_web/components/layouts.ex` — adds `import CadenceWeb.Components.Sidebar` so the embedded mission sidebar template can call the new components. Scoped to layouts only — does not pollute every HEEX template in the app.
- `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex` — replaces inlined `<li>` blocks with `<.nav_item>` / `<.nav_section>` calls.
- `apps/cadence_web/lib/cadence_web/live/comms_overview_live.ex` — changes `assign(:nav_item, :comms)` to `assign(:nav_item, :comms_overview)`.
- `apps/cadence_web/test/cadence_web/live/comms_live_test.exs` — extends the existing sidebar test and adds a new collapsed-on-other-route test.

---

## Task 1: Create the `Sidebar` component module with `nav_item/1` and `section_active?/2`

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/components/sidebar.ex`

- [ ] **Step 1: Write the module with `nav_item/1` and `section_active?/2`**

Create `apps/cadence_web/lib/cadence_web/components/sidebar.ex` with:

```elixir
defmodule CadenceWeb.Components.Sidebar do
  @moduledoc """
  Mission sidebar navigation primitives: `nav_item/1` for leaf entries
  and `nav_section/1` for expandable groups. Composes from existing
  Tailwind utilities and HUD classes; adds no new CSS rules.
  """

  use Phoenix.Component

  @doc """
  Returns true when the current `nav_item` belongs to the given section.

  Used to derive the initial expand state for `nav_section/1`. The
  membership table grows as new section children are introduced.
  """
  @spec section_active?(atom() | nil, atom()) :: boolean()
  def section_active?(:comms, :comms), do: true
  def section_active?(:comms_overview, :comms), do: true
  def section_active?(_, _), do: false

  @doc """
  Leaf sidebar entry. Renders the `<li>` row with the active visual
  treatment (primary tint, primary left border, glow inset) when
  `:active` is true.
  """
  attr :navigate, :string, required: true
  attr :icon, :string, required: true, doc: "Heroicon class, e.g. \"hero-signal\""
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def nav_item(assigns) do
    ~H"""
    <li>
      <.link navigate={@navigate} class={["flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", item_classes(@active)]}>
        <span class={[@icon, "h-4 w-4 opacity-80 flex-shrink-0"]}></span>
        <span class="sidebar-label">{@label}</span>
      </.link>
    </li>
    """
  end

  defp item_classes(true),
    do:
      "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]"

  defp item_classes(false),
    do:
      "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30"
end
```

- [ ] **Step 2: Confirm compilation**

Run from project root:

```bash
mix compile --warnings-as-errors
```

Expected: success, zero warnings. (No callers exist yet; module just needs to compile.)

- [ ] **Step 3: Commit**

```bash
HK=0 git add apps/cadence_web/lib/cadence_web/components/sidebar.ex
HK=0 git commit -m "feat(cadence_web): add Sidebar.nav_item and section_active? helper"
```

> Note: `HK=0` is used because the local pre-commit hook depends on `hk`, which is not currently installed in this environment. The user explicitly approved skipping it for this work. If `hk` is installed later, drop the prefix.

---

## Task 2: Add `nav_section/1` to the Sidebar module

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/sidebar.ex`

- [ ] **Step 1: Append `nav_section/1` to the module**

Insert before the final `end` of `CadenceWeb.Components.Sidebar`:

```elixir
  @doc """
  Expandable sidebar group. Renders a `<details>` element whose `<summary>`
  is the parent row (label, icon, rotating chevron) and whose body is a
  nested list of `:item` slots. Native `<details>` handles the click toggle
  with no JS or LiveView state.

  `:expanded` is the *initial* server-rendered `open` attribute. Sidebar
  navigation uses `<.link navigate={...}>`, which causes a full LiveView
  remount per click, so the open state is re-derived from the route on
  every navigation.
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false, doc: "Parent row active state"
  attr :expanded, :boolean, default: false, doc: "Initial <details open> state"

  slot :item, required: true do
    attr :navigate, :string, required: true
    attr :active, :boolean
  end

  def nav_section(assigns) do
    ~H"""
    <li>
      <details class="group" open={@expanded}>
        <summary class={["list-none cursor-pointer flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", item_classes(@active)]}>
          <span class={[@icon, "h-4 w-4 opacity-80 flex-shrink-0"]}></span>
          <span class="sidebar-label flex-1">{@label}</span>
          <span class="hero-chevron-right h-3 w-3 opacity-60 transition-transform group-open:rotate-90 sidebar-label"></span>
        </summary>
        <ul class="mt-0.5 space-y-0.5">
          <li :for={item <- @item}>
            <.link navigate={item.navigate} class={["flex items-center gap-2 pl-8 pr-3 py-1.5 text-xs tracking-wide uppercase border-l-2 transition-all", item_classes(Map.get(item, :active, false))]}>
              {render_slot(item)}
            </.link>
          </li>
        </ul>
      </details>
    </li>
    """
  end
```

Notes for the implementer:

- `list-none` on `<summary>` removes the default disclosure triangle that browsers render; the chevron span replaces it.
- `group-open:rotate-90` is Tailwind v4's variant tied to the parent `<details>` having the `[open]` attribute. The `class="group"` on `<details>` is what makes the variant resolve.
- Children use `pl-8` for indent vs the parent's `px-3`. They reuse the same `item_classes/1` function so active styling matches leaves.
- The `sidebar-label` class on the chevron makes it disappear when the sidebar collapses to icon-only mode (existing CSS rule).

- [ ] **Step 2: Confirm compilation**

```bash
mix compile --warnings-as-errors
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
HK=0 git add apps/cadence_web/lib/cadence_web/components/sidebar.ex
HK=0 git commit -m "feat(cadence_web): add Sidebar.nav_section expandable group"
```

---

## Task 3: Make the new components importable from layout templates

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts.ex`

- [ ] **Step 1: Add the import to the `Layouts` module**

Open `apps/cadence_web/lib/cadence_web/components/layouts.ex`. The file is currently:

```elixir
defmodule CadenceWeb.Layouts do
  @moduledoc false

  use CadenceWeb, :html

  embed_templates "layouts/*"
end
```

Replace it with:

```elixir
defmodule CadenceWeb.Layouts do
  @moduledoc false

  use CadenceWeb, :html

  import CadenceWeb.Components.Sidebar

  embed_templates "layouts/*"
end
```

Why scope it here rather than in `cadence_web.ex`'s `html_helpers/0`: the sidebar primitives are only used in mission/admin layouts. Importing inside `Layouts` keeps the surface area narrow and prevents every HEEX template in the app from accidentally calling `nav_item/1` / `nav_section/1` outside the sidebar context.

`embed_templates` compiles each template in the context of the host module, so the import flows into `mission_sidebar.html.heex` automatically.

- [ ] **Step 2: Confirm compilation**

```bash
mix compile --warnings-as-errors
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
HK=0 git add apps/cadence_web/lib/cadence_web/components/layouts.ex
HK=0 git commit -m "feat(cadence_web): expose Components.Sidebar to layouts"
```

---

## Task 4: Refactor mission sidebar template to use the new components

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`

- [ ] **Step 1: Replace the four inlined `<li>` blocks**

Open the file. Locate the `<ul class="menu menu-sm space-y-0.5">` block (around line 79). Replace its four child `<li>` blocks with the following, leaving everything else (drawer, header, footer, sign-out button, toggle button) untouched:

```heex
        <ul class="menu menu-sm space-y-0.5">
          <.nav_item
            :if={assigns[:current_mission]}
            navigate={~p"/missions/#{@current_mission.mission_id}"}
            icon="hero-chart-bar-square"
            label="Overview"
            active={assigns[:nav_item] == :mission_overview}
          />
          <.nav_item
            :if={assigns[:current_mission]}
            navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
            icon="hero-rocket-launch"
            label="Spacecraft"
            active={assigns[:nav_item] == :spacecraft}
          />
          <.nav_item
            :if={assigns[:current_mission]}
            navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
            icon="hero-circle-stack"
            label="Catalog"
            active={assigns[:nav_item] == :catalog}
          />
          <.nav_section
            :if={assigns[:current_mission]}
            icon="hero-signal"
            label="Comms"
            active={section_active?(assigns[:nav_item], :comms)}
            expanded={section_active?(assigns[:nav_item], :comms)}
          >
            <:item
              navigate={~p"/missions/#{@current_mission.mission_id}/comms"}
              active={assigns[:nav_item] == :comms_overview}
            >
              Overview
            </:item>
          </.nav_section>
        </ul>
```

- [ ] **Step 2: Compile and confirm no warnings**

```bash
mix compile --warnings-as-errors
```

Expected: success.

- [ ] **Step 3: Run the existing comms live test**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/comms_live_test.exs
```

Expected: PASS. The existing assertion `assert html =~ "bg-primary/10"` still holds because the section row reuses that active class. The `assert html =~ "Comms"` and `assert html =~ "hero-signal"` assertions remain valid.

If anything fails, fix the template before continuing.

- [ ] **Step 4: Commit**

```bash
HK=0 git add apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex
HK=0 git commit -m "refactor(cadence_web): mission sidebar uses Components.Sidebar"
```

---

## Task 5: Update comms overview LiveView to set `:comms_overview` nav atom

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/comms_overview_live.ex`

- [ ] **Step 1: Change the assignment**

Find the line `|> assign(:nav_item, :comms)` in `apps/cadence_web/lib/cadence_web/live/comms_overview_live.ex` (around line 15) and change it to:

```elixir
     |> assign(:nav_item, :comms_overview)
```

Leave every other comms LiveView's `nav_item: :comms` assignment alone — they continue to mark the section as active without a specific child highlighted.

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors
```

Expected: success.

- [ ] **Step 3: Run the comms live test (will still pass with old assertions)**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/comms_live_test.exs
```

Expected: PASS. The current assertions are loose substring checks (`"Comms"`, `"hero-signal"`, `"bg-primary/10"`) all still match.

- [ ] **Step 4: Commit**

```bash
HK=0 git add apps/cadence_web/lib/cadence_web/live/comms_overview_live.ex
HK=0 git commit -m "feat(cadence_web): tag comms overview LV with :comms_overview nav_item"
```

---

## Task 6: Test — Comms section auto-expands and Overview child is active on `/comms`

**Files:**
- Modify: `apps/cadence_web/test/cadence_web/live/comms_live_test.exs`

- [ ] **Step 1: Replace the existing sidebar test with the stronger assertions**

Locate the test at `comms_live_test.exs` line ~251:

```elixir
    test "marks Comms as the active mission sidebar item" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert html =~ "Comms"
      assert html =~ "hero-signal"
      assert html =~ "bg-primary/10"
    end
```

Replace it with:

```elixir
    test "expands the Comms section and marks Overview active on /comms" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      # The <details> for the Comms section is rendered open.
      assert has_element?(view, "details[open] summary", "Comms")

      # The Overview child link is present and styled active.
      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms"].bg-primary\\/10|,
               "Overview"
             )
    end
```

Why these selectors:

- `has_element?/3` accepts a CSS selector and an optional text filter; it inspects the live rendered DOM, so attribute presence (`details[open]`) and class membership (`.bg-primary\/10`) are both verifiable directly.
- The forward slash in `bg-primary/10` must be CSS-escaped (`\\/`) inside the Elixir string.
- The selector scopes the active assertion to *inside the open details*, which double-checks both that the section opened and that Overview lives inside it.

- [ ] **Step 2: Run the test file**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/comms_live_test.exs
```

Expected: PASS — the new sidebar test plus every other test in the file.

If it fails, the most likely causes are:
- The chevron span's `sidebar-label` class is hiding the chevron in test-rendered HTML (it should not — this is a CSS class, not a server-rendered conditional). If so, inspect rendered HTML with `IO.puts(render(view))`.
- The `details[open]` selector fails because `open` was rendered as `open=""` instead of present-as-attribute. Both forms satisfy `[open]` in CSS; if Floki (the Phoenix.LiveViewTest backend) has issues, fall back to `assert render(view) =~ "<details class=\"group\" open>"`.

- [ ] **Step 3: Commit**

```bash
HK=0 git add apps/cadence_web/test/cadence_web/live/comms_live_test.exs
HK=0 git commit -m "test(cadence_web): assert Comms section auto-expands on /comms"
```

---

## Task 7: Test — Comms section is collapsed when on a non-comms route

**Files:**
- Modify: `apps/cadence_web/test/cadence_web/live/comms_live_test.exs`

- [ ] **Step 1: Add a sibling test asserting the collapsed state**

Insert directly after the test added in Task 6:

```elixir
    test "leaves the Comms section collapsed when not on a /comms route" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

      # The Comms <summary> is rendered inside a <details> WITHOUT open.
      assert has_element?(view, "details:not([open]) summary", "Comms")
      refute has_element?(view, "details[open] summary", "Comms")
    end
```

This relies on the mission-overview route (`/missions/:mission_id`) being reachable in the existing test setup. If `signed_in_org_and_mission/0` already supports it (it does — `mission_show_live_test.exs` uses the same fixtures), no further setup is needed.

- [ ] **Step 2: Run the test file**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/comms_live_test.exs
```

(ExUnit doesn't have a name-based filter — file:line works, but the line will shift after edits, so running the whole file is simpler here.)

Expected: PASS for both new sidebar tests, plus everything else previously passing.

- [ ] **Step 3: Commit**

```bash
HK=0 git add apps/cadence_web/test/cadence_web/live/comms_live_test.exs
HK=0 git commit -m "test(cadence_web): assert Comms section collapsed off-route"
```

---

## Task 8: Quality gates and manual smoke check

**Files:** none (verification only)

- [ ] **Step 1: Format every touched Elixir file**

```bash
cd apps/cadence_web && mix format \
  lib/cadence_web/components/sidebar.ex \
  lib/cadence_web.ex \
  lib/cadence_web/components/layouts/mission_sidebar.html.heex \
  lib/cadence_web/live/comms_overview_live.ex \
  test/cadence_web/live/comms_live_test.exs
```

If the formatter rewrites any file, stage the result.

- [ ] **Step 2: Compile with warnings as errors**

```bash
cd /Users/donovanrost/projects/cadence/cadence && mix compile --warnings-as-errors
```

Expected: success, zero warnings.

- [ ] **Step 3: Credo on touched files**

```bash
cd /Users/donovanrost/projects/cadence/cadence && mix credo --strict \
  apps/cadence_web/lib/cadence_web/components/sidebar.ex \
  apps/cadence_web/lib/cadence_web.ex \
  apps/cadence_web/lib/cadence_web/live/comms_overview_live.ex
```

Expected: no new findings on touched files. Pre-existing findings elsewhere are out of scope.

- [ ] **Step 4: Run the cadence_web test suite**

```bash
cd /Users/donovanrost/projects/cadence/cadence/apps/cadence_web && mix test
```

Expected: full suite green.

- [ ] **Step 5: Manual smoke check in a browser**

Start the dev server (`mix phx.server` from project root) and verify:

1. Visit `/missions/<id>` — Comms in the sidebar shows a chevron pointing right and the section is collapsed.
2. Visit `/missions/<id>/comms` — Comms section is auto-expanded; chevron points down; "Overview" child is visible and styled active; the parent "Comms" row is also styled active.
3. From `/missions/<id>` click on the "Comms" row — section expands; chevron rotates; "Overview" child appears.
4. Click the sidebar collapse toggle (bottom-left chevron) — sidebar shrinks to icons; hover the sidebar to verify the existing hover-expand still works and reveals the Comms section content.
5. Visit `/missions/<id>/comms/links` — Comms section is auto-expanded; the "Comms" parent row is styled active; "Overview" child is *not* active (its `nav_item` is still `:comms`, not `:comms_overview`).

If any step misbehaves, debug before committing.

- [ ] **Step 6: Final commit if formatter changed anything**

If `mix format` rewrote files in Step 1, commit the formatting:

```bash
HK=0 git add -u
HK=0 git commit -m "chore(cadence_web): mix format after sidebar refactor"
```

Otherwise skip this step.

---

## Notes for follow-up iterations

- Adding more comms children: append entries to `section_active?/2` for the new `nav_item` atoms (e.g., `section_active?(:comms_links, :comms)`), tag the corresponding LiveViews with the new atoms, and add `<:item>` slots to the `<.nav_section>` call in `mission_sidebar.html.heex`.
- Generalizing to Spacecraft: the same `<.nav_section>` works as-is. Just add a Spacecraft-specific clause to `section_active?/2` and convert the Spacecraft `<.nav_item>` to a `<.nav_section>` with `<:item>` slots when the time comes.
- If the membership table in `section_active?/2` becomes large or repetitive, consider replacing it with a static `@section_membership` map, but only when it pays off — YAGNI for now.
