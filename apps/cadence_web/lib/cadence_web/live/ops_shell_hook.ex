defmodule CadenceWeb.OpsShellHook do
  alias Cadence.Reads.{Alarms, Commands}
  alias Cadence.Reads.MissionHealth, as: MissionHealthReads
  alias CadenceWeb.OpsContextSnapshot

  @moduledoc """
  on_mount hook for the ops console live_session: loads the assigns the
  `:ops` layout's status bar, navigation, and mission-scoped context render so
  each Ops LiveView does not repeat them. The show page overrides
  `:active_dashboard_id` and keeps the fleet-health projection fresh on its
  tick.
  """

  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  @default_context_refresh_ms 15_000

  def on_mount(:default, params, _session, socket) do
    {:cont,
     socket
     |> refresh_context()
     |> pin_context_from_params(params)
     |> refresh_dashboard_navigation()
     |> assign(:active_dashboard_id, nil)
     |> assign(:ops_nav_item, :dashboards)
     |> attach_context_refresh()}
  end

  @doc false
  def refresh_dashboard_navigation(socket, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    summaries =
      dashboard_summaries(scope.organization_id, mission.mission_id, opts)

    navigation =
      case current_user_id(scope) do
        user_id when is_binary(user_id) ->
          dashboard_navigation(
            scope.organization_id,
            mission.mission_id,
            user_id,
            summaries,
            opts
          )

        _missing_user ->
          %{starred: [], recent: []}
      end

    socket
    |> assign(:ops_dashboards, summaries)
    |> assign(:ops_dashboard_navigation, navigation)
    |> assign(
      :dashboard_author?,
      CadenceWeb.DashboardAuthorAuth.authorized?(scope, mission.mission_id)
    )
  end

  @doc false
  def refresh_context(socket, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    fleet_health = mission_health_summary(scope.organization_id, mission.mission_id, opts)
    alarm_summary = alarm_summary(scope.organization_id, mission.mission_id, opts)
    command_summary = command_summary(scope.organization_id, mission.mission_id, opts)
    observed_at = observed_at(opts)

    pinned_command_id = get_in(socket.assigns, [:ops_context, :pinned_focus, :id])

    ops_context =
      socket.assigns
      |> Map.get(:ops_context)
      |> OpsContextSnapshot.put_fleet_health(
        mission.mission_id,
        fleet_health,
        observed_at
      )
      |> OpsContextSnapshot.put_alarm_summary(alarm_summary, observed_at)
      |> OpsContextSnapshot.put_command_summary(command_summary, observed_at)
      |> OpsContextSnapshot.pin_command_focus(pinned_command_id)

    socket
    |> assign(:fleet_health, fleet_health)
    |> assign(:ops_context, ops_context)
  end

  @doc false
  def context_refresh_ms do
    case Application.get_env(
           :cadence_web,
           :ops_context_refresh_ms,
           @default_context_refresh_ms
         ) do
      refresh_ms when is_integer(refresh_ms) and refresh_ms > 0 -> refresh_ms
      _invalid -> @default_context_refresh_ms
    end
  end

  defp attach_context_refresh(socket) do
    if connected?(socket) do
      schedule_context_refresh()

      attach_hook(socket, :ops_context_refresh, :handle_info, fn
        :ops_context_refresh, socket ->
          schedule_context_refresh()
          {:halt, refresh_context(socket)}

        _message, socket ->
          {:cont, socket}
      end)
    else
      socket
    end
  end

  defp schedule_context_refresh do
    Process.send_after(self(), :ops_context_refresh, context_refresh_ms())
  end

  defp mission_health_summary(organization_id, mission_id, opts) do
    case Keyword.get(opts, :mission_health_summary) do
      callback when is_function(callback, 3) -> callback.(organization_id, mission_id, [])
      _missing -> MissionHealthReads.summary(organization_id, mission_id, [])
    end
  end

  defp alarm_summary(organization_id, mission_id, opts) do
    case Keyword.get(opts, :alarm_summary) do
      callback when is_function(callback, 3) -> callback.(organization_id, mission_id, [])
      _missing -> Alarms.summary(organization_id, mission_id)
    end
  end

  defp command_summary(organization_id, mission_id, opts) do
    case Keyword.get(opts, :command_summary) do
      callback when is_function(callback, 3) -> callback.(organization_id, mission_id, [])
      _missing -> Commands.summary(organization_id, mission_id)
    end
  end

  defp dashboard_summaries(organization_id, mission_id, opts) do
    case Keyword.get(opts, :dashboard_summaries) do
      callback when is_function(callback, 2) -> callback.(organization_id, mission_id)
      _missing -> Cadence.Dashboards.list_dashboard_summaries(organization_id, mission_id)
    end
  end

  defp dashboard_navigation(organization_id, mission_id, user_id, summaries, opts) do
    case Keyword.get(opts, :dashboard_navigation) do
      callback when is_function(callback, 4) ->
        callback.(organization_id, mission_id, user_id, summaries)

      _missing ->
        Cadence.Dashboards.dashboard_navigation(
          organization_id,
          mission_id,
          user_id,
          summaries
        )
    end
  end

  defp current_user_id(scope) do
    scope
    |> Map.get(:user)
    |> case do
      %{user_id: user_id} when is_binary(user_id) -> user_id
      _missing -> nil
    end
  end

  defp pin_context_from_params(socket, params) do
    assign(
      socket,
      :ops_context,
      OpsContextSnapshot.pin_command_focus(
        socket.assigns.ops_context,
        Map.get(params, "focus_command_id")
      )
    )
  end

  defp observed_at(opts) do
    case Keyword.get(opts, :observed_at) do
      callback when is_function(callback, 0) -> callback.()
      _missing -> DateTime.utc_now()
    end
  end
end
