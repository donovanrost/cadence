defmodule CadenceWeb.OpsDashboardShowLive.LiveRefreshTest do
  use ExUnit.Case, async: true

  @moduletag :config

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.LiveRefresh
  alias Phoenix.LiveView.Socket

  test "live ticks increment count, refresh fleet health on cadence, and resolve with append state" do
    socket =
      socket(%{
        tick_count: 4,
        widget_data: %{"placement-1" => %{latest: 1}}
      })

    socket = LiveRefresh.handle_tick(socket, test_opts())

    assert socket.assigns.tick_count == 5
    assert socket.assigns.fleet_health == %{status: :nominal, mission_id: "mission-1"}
    assert socket.assigns.resolved_mode == :live_tick

    assert socket.assigns.resolve_opts == [
             refresh_allowed?: true,
             reason: :tick,
             append_previous_data: %{"placement-1" => %{latest: 1}}
           ]
  end

  test "edit mode suppresses live tick refresh and fleet health refresh" do
    socket =
      socket(%{
        tick_count: 4,
        edit_mode?: true
      })

    socket = LiveRefresh.handle_tick(socket, test_opts())

    assert socket.assigns.tick_count == 5
    refute Map.has_key?(socket.assigns, :fleet_health)

    assert socket.assigns.resolve_opts == [
             refresh_allowed?: false,
             reason: :edit_mode,
             append_previous_data: %{}
           ]
  end

  test "non-live time modes suppress live tick refresh with a time-mode reason" do
    socket =
      socket(%{
        dashboard_time_mode: "archive"
      })

    socket = LiveRefresh.handle_tick(socket, test_opts())

    assert socket.assigns.resolve_opts == [
             refresh_allowed?: false,
             reason: :not_live_time_mode,
             append_previous_data: %{}
           ]
  end

  test "default refresh interval ignores invalid configuration" do
    previous = Application.get_env(:cadence_web, :dashboard_live_refresh_ms)

    try do
      Application.put_env(:cadence_web, :dashboard_live_refresh_ms, -1)
      assert LiveRefresh.default_refresh_ms(1_000) == 1_000

      Application.put_env(:cadence_web, :dashboard_live_refresh_ms, 2_500)
      assert LiveRefresh.default_refresh_ms(1_000) == 2_500
    after
      restore_refresh_config(previous)
    end
  end

  defp test_opts do
    [
      constellation_every: 5,
      mission_health_summary: fn organization_id, mission_id, [] ->
        assert organization_id == "org-1"
        %{status: :nominal, mission_id: mission_id}
      end,
      resolve_engine: fn socket, mode, resolve_opts ->
        socket
        |> assign(:resolved_mode, mode)
        |> assign(:resolve_opts, resolve_opts)
      end
    ]
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            tick_count: 0,
            widget_data: %{},
            edit_mode?: false,
            dashboard_time_mode: "live"
          },
          assigns
        )
    }
  end

  defp restore_refresh_config(nil),
    do: Application.delete_env(:cadence_web, :dashboard_live_refresh_ms)

  defp restore_refresh_config(value),
    do: Application.put_env(:cadence_web, :dashboard_live_refresh_ms, value)
end
