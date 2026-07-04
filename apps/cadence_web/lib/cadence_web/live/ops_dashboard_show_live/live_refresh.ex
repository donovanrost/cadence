defmodule CadenceWeb.OpsDashboardShowLive.LiveRefresh do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.Runtime

  @default_constellation_every 5

  def handle_tick(socket, opts \\ []) do
    tick_count = socket.assigns.tick_count + 1
    socket = assign(socket, :tick_count, tick_count)

    refresh_allowed? = refresh_allowed?(socket)
    refresh_fleet_health? = refresh_allowed? and rem(tick_count, constellation_every(opts)) == 0
    previous_data = socket.assigns.widget_data

    socket
    |> maybe_refresh_fleet_health(refresh_fleet_health?, opts)
    |> resolve_engine(
      :live_tick,
      [
        refresh_allowed?: refresh_allowed?,
        reason: refresh_reason(socket),
        append_previous_data: previous_data
      ],
      opts
    )
  end

  def refresh_allowed?(socket) do
    not socket.assigns.edit_mode? and socket.assigns.dashboard_time_mode == "live"
  end

  def refresh_reason(socket) do
    cond do
      socket.assigns.edit_mode? -> :edit_mode
      socket.assigns.dashboard_time_mode != "live" -> :not_live_time_mode
      true -> :tick
    end
  end

  def default_refresh_ms(default_ms) do
    case Application.get_env(:cadence_web, :dashboard_live_refresh_ms, default_ms) do
      refresh_ms when is_integer(refresh_ms) and refresh_ms > 0 -> refresh_ms
      _other -> default_ms
    end
  end

  defp maybe_refresh_fleet_health(socket, false, _opts), do: socket

  defp maybe_refresh_fleet_health(socket, true, opts) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    assign(
      socket,
      :fleet_health,
      mission_health_summary(scope.organization_id, mission.mission_id, opts)
    )
  end

  defp mission_health_summary(organization_id, mission_id, opts) do
    case Keyword.get(opts, :mission_health_summary) do
      callback when is_function(callback, 3) -> callback.(organization_id, mission_id, [])
      _missing -> Cadence.mission_health_summary(organization_id, mission_id, [])
    end
  end

  defp resolve_engine(socket, mode, resolve_opts, opts) do
    case Keyword.get(opts, :resolve_engine) do
      callback when is_function(callback, 3) ->
        callback.(socket, mode, resolve_opts)

      _missing ->
        Runtime.resolve_engine(socket, mode, resolve_opts)
    end
  end

  defp constellation_every(opts) do
    case Keyword.get(opts, :constellation_every, @default_constellation_every) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> @default_constellation_every
    end
  end
end
