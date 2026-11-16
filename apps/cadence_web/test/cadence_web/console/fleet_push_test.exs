defmodule CadenceWeb.Console.FleetPushTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3, push: 3]
  require Phoenix.ChannelTest

  alias Cadence.Platform.ScopedReadUpdates
  alias CadenceWeb.Console.FleetPush
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures

  @t0 ~U[2026-11-08 02:00:00Z]
  @t1 ~U[2026-11-08 02:00:05Z]

  defp row(id, fields \\ %{}),
    do: Map.merge(%{id: id, state: "nominal", stale: false, last_received_at: @t0}, fields)

  describe "diff/3" do
    test "reports material changes, new rows and removals; heard-only changes wait for the tick" do
      baseline = Map.new([row("a"), row("b"), row("gone")], &{&1.id, &1})

      rows = [
        row("a", %{state: "critical", last_received_at: @t1}),
        row("b", %{last_received_at: @t1}),
        row("new")
      ]

      {changed, heard, removed, next} = FleetPush.diff(baseline, rows, false)

      assert Enum.map(changed, & &1.id) == ["a", "new"]
      assert heard == %{}
      assert removed == ["gone"]
      # b keeps its old row so the newer receipt is reported on the next tick.
      assert next["b"].last_received_at == @t0

      assert {[], %{"b" => @t1}, [], next} = FleetPush.diff(next, rows, true)
      assert next["b"].last_received_at == @t1
    end

    test "unchanged rows produce nothing" do
      baseline = %{"a" => row("a")}
      assert {[], %{}, [], ^baseline} = FleetPush.diff(baseline, [row("a")], true)
    end
  end

  describe "fleet push on mission:<id>" do
    setup do
      org = TestFixtures.persist_org!()
      user = TestFixtures.persist_user!()
      TestFixtures.grant_membership!(user, org)
      mission = TestFixtures.persist_mission!(org)
      TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")
      token = TestFixtures.member_session_token!(user)

      {:ok, socket} =
        Phoenix.ChannelTest.connect(ConsoleSocket, %{},
          connect_info: %{session: %{"user_session_token" => token}}
        )

      {:ok, _reply, socket} = subscribe_and_join(socket, "mission:" <> mission.mission_id, %{})
      %{org: org, mission: mission, socket: socket}
    end

    test "is off until subscribed, then sends a full snapshot", c do
      refute_push("fleet", _payload, 200)

      ref = Phoenix.ChannelTest.push(c.socket, "fleet:subscribe", %{})
      # The reply no longer waits on the fleet read; settle/1 makes reply and snapshot certain.
      settle(c.socket)
      assert_reply(ref, :ok, %{})

      assert_push(
        "fleet",
        %{seq: 1, full: true, spacecraft: [row], counts: %{total: 1}} = payload
      )

      assert row.name == "EARENDIL-001"
      assert payload.heard == %{}
      assert payload.removed == []
      assert %{awaiting_viewer: 0} = payload.commands
    end

    test "the tick is a heartbeat; a spacecraft change arrives as a delta row", c do
      ref = Phoenix.ChannelTest.push(c.socket, "fleet:subscribe", %{})
      settle(c.socket)
      assert_reply(ref, :ok, %{})
      assert_push("fleet", %{seq: 1})

      send(c.socket.channel_pid, :fleet_tick)
      settle(c.socket)
      assert_push("fleet", %{seq: 2, full: false, spacecraft: [], heard: heard})
      assert heard == %{}

      TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-002")

      :ok =
        ScopedReadUpdates.publish(
          :spacecraft_configuration_changed,
          c.org.organization_id,
          c.mission.mission_id
        )

      assert_push(
        "fleet",
        %{seq: 3, spacecraft: [%{name: "EARENDIL-002"}], counts: %{total: 2}},
        2_000
      )
    end

    test "subscribing twice before the snapshot sends one snapshot", c do
      # Suspended, the channel queues both subscribes before it handles either, so the second
      # one meets the :pending state.
      replies = queued(c.socket, ["fleet:subscribe", "fleet:subscribe"])
      settle(c.socket)
      Enum.each(replies, &assert_reply(&1, :ok, %{}))
      assert_push("fleet", %{seq: 1, full: true})
      refute_push("fleet", _payload, 50)
    end

    test "unsubscribing before the snapshot drops it", c do
      # Queued in this order, the unsubscribe is handled before the snapshot the subscribe queues.
      replies = queued(c.socket, ["fleet:subscribe", "fleet:unsubscribe"])
      settle(c.socket)
      Enum.each(replies, &assert_reply(&1, :ok, %{}))
      refute_push("fleet", _payload, 50)
    end

    # fe-ops: a resubscribe on a seq gap is unsubscribe + subscribe back to back, maybe while the
    # first snapshot is still queued. Exactly one full snapshot either way, never seq 1 twice.
    test "subscribe, unsubscribe, subscribe back to back: exactly one snapshot", c do
      replies = queued(c.socket, ["fleet:subscribe", "fleet:unsubscribe", "fleet:subscribe"])
      settle(c.socket)
      Enum.each(replies, &assert_reply(&1, :ok, %{}))
      assert_push("fleet", %{seq: 1, full: true})
      refute_push("fleet", %{seq: 1}, 50)
    end

    test "unsubscribe stops the push", c do
      ref = Phoenix.ChannelTest.push(c.socket, "fleet:subscribe", %{})
      settle(c.socket)
      assert_reply(ref, :ok, %{})
      assert_push("fleet", %{seq: 1})

      ref = Phoenix.ChannelTest.push(c.socket, "fleet:unsubscribe", %{})
      settle(c.socket)
      assert_reply(ref, :ok, %{})

      send(c.socket.channel_pid, :fleet_tick)

      :ok =
        ScopedReadUpdates.publish(
          :commanding_changed,
          c.org.organization_id,
          c.mission.mission_id
        )

      assert_push("invalidate", %{resources: ["commanding"]}, 2_000)
      refute_push("fleet", _payload, 1_200)
    end
  end

  # Two round trips to the channel: the first returns once it has handled everything queued
  # before it (replies sent, the snapshot message queued), the second once it has handled that.
  # Deterministic whatever the load: no reply or push waits on a timeout.
  defp settle(socket) do
    :sys.get_state(socket.channel_pid)
    :sys.get_state(socket.channel_pid)
  end

  # Queues the events while the channel is suspended, so they reach it in exactly this order.
  defp queued(socket, events) do
    :sys.suspend(socket.channel_pid)
    refs = Enum.map(events, &Phoenix.ChannelTest.push(socket, &1, %{}))
    :sys.resume(socket.channel_pid)
    refs
  end
end
