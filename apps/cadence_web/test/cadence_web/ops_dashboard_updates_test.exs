defmodule CadenceWeb.OpsDashboardUpdatesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.RuntimeInvalidation
  alias CadenceWeb.OpsDashboardPage.Updates
  alias Phoenix.LiveView.Socket

  setup do
    token = Ecto.UUID.generate()

    %{
      socket: %Socket{transport_pid: self(), assigns: %{__changed__: %{}}},
      session: %{token: token, identity: {token, :mission, token, token, "/dashboard"}},
      page: %{data: %{live: %{active: true, refresh_ms: 1_000}}},
      event: %{filters: %{organization_id: token, mission_id: token, dashboard_id: token}},
      token: token
    }
  end

  test "live invalidation bursts do not compete with ticks or queue ticks during resolution", c do
    socket = Updates.sync(c.socket, c.session, c.page)
    broadcast_invalidation(c)
    refute_receive {:dashboard_runtime_invalidated, _}, 100
    socket = Enum.reduce(1..1_000, socket, fn _, acc -> Updates.invalidated(acc, c.event) end)

    refute_receive {:dashboard_live_flush, _}, 300
    assert {:ignore, ^socket} = Updates.flush(socket, c.token)

    assert {:refresh, resolving} = Updates.tick(socket, c.token)
    refute_receive {:dashboard_live_tick, _}, 1_100

    resolved = Updates.sync(resolving, c.session, c.page)
    assert_receive {:dashboard_live_tick, token}, 1_200
    assert token == c.token
    Updates.stop(resolved)
  end

  test "edit mode still coalesces relevant invalidations into one refresh", c do
    session = Map.put(c.session, :mode, :edit)
    socket = Updates.sync(c.socket, session, %{status: "ready"})
    broadcast_invalidation(c)
    assert_receive {:dashboard_runtime_invalidated, event}
    assert event == c.event
    socket = Enum.reduce(1..1_000, socket, fn _, acc -> Updates.invalidated(acc, c.event) end)

    assert_receive {:dashboard_live_flush, token}, 500
    assert token == c.token
    refute_receive {:dashboard_live_flush, _}, 300
    assert {:refresh, refreshed} = Updates.flush(socket, token)
    assert {:ignore, ^refreshed} = Updates.flush(refreshed, token)
    Updates.stop(refreshed)
    broadcast_invalidation(c)
    refute_receive {:dashboard_runtime_invalidated, _}, 100
  end

  defp broadcast_invalidation(c) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      RuntimeInvalidation.mission_topic(c.token, c.token),
      {:dashboard_runtime_invalidated, c.event}
    )
  end
end
