defmodule CadenceWeb.OpsShellHook do
  alias Cadence.Applications.OpsDock
  alias CadenceWeb.OpsContextSnapshot
  alias CadenceWeb.OpsShellHook.ContextDeps

  @moduledoc """
  on_mount hook for the ops console live_session: loads the assigns the
  `:ops` layout's status bar, navigation, and mission-scoped context render so
  each Ops LiveView does not repeat them. The show page overrides
  `:active_dashboard_id` and keeps the fleet-health projection fresh on its
  tick.
  """

  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  def on_mount(:default, params, _session, socket) do
    context_deps = ContextDeps.from_config()

    {:cont,
     socket
     |> assign(:ops_context_deps, context_deps)
     |> refresh_context(context_deps)
     |> pin_context_from_params(params)
     |> refresh_dashboard_navigation()
     |> refresh_ops_dock()
     |> assign(:active_dashboard_id, nil)
     |> assign(:ops_nav_item, :dashboards)
     |> attach_context_refresh(context_deps)}
  end

  @doc false
  def refresh_ops_dock(socket, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    surfaces =
      case Keyword.get(opts, :ops_dock_surfaces) do
        callback when is_function(callback, 2) -> callback.(scope, mission.mission_id)
        _missing -> resolve_ops_dock_surfaces(scope, mission.mission_id)
      end

    assign(socket, :ops_dock_surfaces, surfaces)
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
  def refresh_context(socket, deps_or_opts \\ nil)

  def refresh_context(socket, nil) do
    deps = Map.get(socket.assigns, :ops_context_deps, ContextDeps.new())
    refresh_context(socket, deps)
  end

  def refresh_context(socket, []), do: refresh_context(socket, nil)

  def refresh_context(socket, opts) when is_list(opts) do
    refresh_context(socket, ContextDeps.new(opts))
  end

  def refresh_context(socket, %ContextDeps{} = deps) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    fleet_health =
      deps.mission_health_summary.(scope.organization_id, mission.mission_id, [])

    alarm_summary = deps.alarm_summary.(scope.organization_id, mission.mission_id, [])
    command_summary = deps.command_summary.(scope.organization_id, mission.mission_id, [])
    observed_at = deps.observed_at.()

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
    ContextDeps.from_config().refresh_interval_ms
  end

  @doc false
  def context_refresh_ms(opts) when is_list(opts) do
    ContextDeps.new(opts).refresh_interval_ms
  end

  defp attach_context_refresh(socket, %ContextDeps{} = deps) do
    if connected?(socket) do
      schedule_context_refresh(deps)

      attach_hook(socket, :ops_context_refresh, :handle_info, fn
        :ops_context_refresh, socket ->
          schedule_context_refresh(deps)
          {:halt, refresh_context(socket, deps)}

        _message, socket ->
          {:cont, socket}
      end)
    else
      socket
    end
  end

  defp schedule_context_refresh(%ContextDeps{} = deps) do
    Process.send_after(self(), :ops_context_refresh, deps.refresh_interval_ms)
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

  defp resolve_ops_dock_surfaces(scope, mission_id) do
    case OpsDock.list(scope, mission_id) do
      {:ok, surfaces} -> surfaces
      {:error, _reason} -> []
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
end
