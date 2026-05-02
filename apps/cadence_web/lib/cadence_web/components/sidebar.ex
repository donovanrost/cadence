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
    do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]"

  defp item_classes(false),
    do:
      "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30"
end
