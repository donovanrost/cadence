defmodule CadenceWeb.TargetLive.Index do
  use CadenceWeb, :live_view

  alias Cadence.{Targets, Missions}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    scope = socket.assigns.current_scope
    current_org = scope.current_organization

    # Get all missions for the organization to determine which targets are viewable
    missions = if current_org do
      Missions.list_missions(current_org)
    else
      []
    end

    # Collect all targets from viewable missions
    all_targets = missions
    |> Enum.flat_map(fn mission ->
      # Check if user can view this mission
      case Bodyguard.permit(Cadence.Missions.Policy, :view, scope, mission) do
        :ok -> Targets.list_targets(mission)
        {:error, _} -> []
      end
    end)
    |> Enum.sort_by(& &1.identifier)

    # Optionally filter by mission_id if provided
    targets = case Map.get(params, "mission_id") do
      nil -> all_targets
      mission_id -> Enum.filter(all_targets, &(&1.mission_id == mission_id))
    end

    socket
    |> assign(:page_title, "Targets")
    |> assign(:targets, targets)
    |> assign(:filter_mission_id, Map.get(params, "mission_id"))
  end
end
