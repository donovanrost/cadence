defmodule CadenceWeb.TargetLive.Show do
  use CadenceWeb, :live_view

  alias Cadence.{Interfaces, Targets, Missions}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    # Use schema version for LiveView form compatibility (changesets work with Ecto schemas)
    # Authorization is enforced via Bodyguard below
    target = Targets.get_target_schema_unscoped!(id)
    mission = Missions.get_mission!(target.mission_id)
    scope = socket.assigns.current_scope

    # Check if user can view the mission (and thus the target)
    case Bodyguard.permit(Cadence.Missions.Policy, :view, scope, mission) do
      :ok ->
        # Load interfaces associated with this target
        interfaces = Interfaces.list_interfaces_for_target(target)

        {:noreply,
         socket
         |> assign(:page_title, "Target Details")
         |> assign(:target, target)
         |> assign(:mission, mission)
         |> assign(:interfaces, interfaces)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this target")
         |> push_navigate(to: ~p"/targets")}
    end
  end
end
