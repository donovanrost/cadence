defmodule CadenceWeb.MissionLive.Index do
  use CadenceWeb, :live_view

  alias Cadence.Missions
  alias Cadence.Missions.Mission

  @impl true
  def mount(_params, _session, socket) do
    # Get missions for current organization
    scope = socket.assigns.current_scope
    current_org = scope.current_organization

    missions =
      if current_org do
        Missions.list_missions(current_org.id)
      else
        []
      end

    {:ok, stream(socket, :missions, missions)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    # Fetch mission - authorization is handled via Bodyguard below
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope

    # Check if user can update this mission
    case Bodyguard.permit(Cadence.Missions.Policy, :update, scope, mission) do
      :ok ->
        socket
        |> assign(:page_title, "Edit Mission")
        |> assign(:mission, mission)

      {:error, _} ->
        socket
        |> put_flash(:error, "You don't have permission to edit this mission")
        |> push_navigate(to: ~p"/missions")
    end
  end

  defp apply_action(socket, :new, params) do
    # Use organization_id from params if provided (admin view), otherwise use current org
    org_id =
      Map.get(params, "organization_id") || socket.assigns.current_scope.current_organization.id

    socket
    |> assign(:page_title, "New Mission")
    |> assign(:mission, %Mission{organization_id: org_id})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Missions")
    |> assign(:mission, nil)
  end

  @impl true
  def handle_info({CadenceWeb.MissionLive.FormComponent, {:saved, mission}}, socket) do
    {:noreply, stream_insert(socket, :missions, mission)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope
    org_id = scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :delete, scope, mission) do
      :ok ->
        case Missions.delete_mission(id, org_id) do
          :ok ->
            {:noreply, stream_delete(socket, :missions, mission)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete mission: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete this mission")}
    end
  end

  @impl true
  def handle_event("start_mission", %{"id" => id}, socket) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope
    org_id = scope.current_organization.id

    # Check if user can manage this mission (start/stop operations)
    case Bodyguard.permit(Cadence.Missions.Policy, :manage, scope, mission) do
      :ok ->
        case Missions.request_start(id, org_id) do
          {:ok, _mission} ->
            {:noreply,
             put_flash(socket, :info, "Mission #{mission.name} start requested successfully")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to request mission start: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to start this mission")}
    end
  end

  @impl true
  def handle_event("stop_mission", %{"id" => id}, socket) do
    mission = Missions.get_mission!(id)
    scope = socket.assigns.current_scope
    org_id = scope.current_organization.id

    # Check if user can manage this mission (start/stop operations)
    case Bodyguard.permit(Cadence.Missions.Policy, :manage, scope, mission) do
      :ok ->
        case Missions.request_stop(id, org_id) do
          {:ok, _mission} ->
            {:noreply, put_flash(socket, :info, "Mission stop requested successfully")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to request mission stop: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to stop this mission")}
    end
  end
end
