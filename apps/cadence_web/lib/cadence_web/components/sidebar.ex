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
  def section_active?(:ops_dashboards, :ops), do: true
  def section_active?(:comms, :comms), do: true
  def section_active?(:comms_overview, :comms), do: true
  def section_active?(:comms_transports, :comms), do: true
  def section_active?(:comms_ground_stations, :comms), do: true
  def section_active?(:comms_routing, :comms), do: true
  def section_active?(:comms_validation, :comms), do: true
  def section_active?(:comms_providers, :comms), do: true
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
    do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]"

  defp item_classes(false),
    do:
      "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30"

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
            <.link navigate={item.navigate} class={["flex items-center gap-2 px-3 py-1.5 text-xs tracking-wide uppercase border-l-2 border-transparent transition-all", child_classes(Map.get(item, :active, false))]}>
              <span class="h-4 w-4 flex items-center justify-center flex-shrink-0">
                <span class={["h-1.5 w-1.5 rounded-full transition-colors", child_dot_classes(Map.get(item, :active, false))]}></span>
              </span>
              <span class="sidebar-label">{render_slot(item)}</span>
            </.link>
          </li>
        </ul>
      </details>
    </li>
    """
  end

  defp child_classes(true), do: "text-primary"
  defp child_classes(false), do: "text-base-content/60 hover:text-base-content"

  defp child_dot_classes(true), do: "bg-primary"
  defp child_dot_classes(false), do: "bg-base-content/30"
end
