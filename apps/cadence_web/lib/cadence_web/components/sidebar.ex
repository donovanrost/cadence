defmodule CadenceWeb.Components.Sidebar do
  @moduledoc "Mission sidebar navigation grouping helpers."

  @doc """
  Returns true when the current `nav_item` belongs to the given section.

  Used to derive the initial expanded state for a navigation section. The
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
end
