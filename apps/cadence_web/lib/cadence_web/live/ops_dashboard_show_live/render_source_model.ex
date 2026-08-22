defmodule CadenceWeb.OpsDashboardShowLive.RenderSourceModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RenderSourceAssigns

  def props(assigns) when is_map(assigns) do
    context = RenderSourceAssigns.source_context(assigns)

    %{
      dashboard_warning_props: %{
        warnings: context.dashboard_warnings,
        degraded?: context.dashboard_degraded?
      },
      source_health_props: %{health: context.source_health},
      source_selection_props: %{
        mission_id: Map.get(assigns, :current_mission) |> mission_id(),
        selections: context.source_selections
      }
    }
  end

  def dashboard_warning_props(assigns) when is_map(assigns) do
    assigns
    |> props()
    |> Map.fetch!(:dashboard_warning_props)
  end

  def source_health_props(assigns) when is_map(assigns) do
    assigns
    |> props()
    |> Map.fetch!(:source_health_props)
  end

  def source_selection_props(assigns) when is_map(assigns) do
    assigns
    |> props()
    |> Map.fetch!(:source_selection_props)
  end

  defp mission_id(%{mission_id: mission_id}) when is_binary(mission_id), do: mission_id
  defp mission_id(_mission), do: nil
end
