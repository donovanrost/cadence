defmodule CadenceWeb.Console.FleetPushTest do
  # The fleet is read by the mission's FleetSource, a process of its own, so the sandbox is shared.
  use CadenceWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3, push: 3]
  require Phoenix.ChannelTest

  alias Cadence.Platform.ScopedReadUpdates
  import ExUnit.CaptureLog

  alias CadenceWeb.Console.FleetPush
  alias CadenceWeb.Console.FleetSource
  alias CadenceWeb.Console.FleetSources
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures

  @t0 ~U[2026-11-08 02:00:00Z]
  @t1 ~U[2026-11-08 02:00:05Z]
  # A push the mission's source drives: its read runs in another process, so wait for it.
  @load_ms 2_000

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
      %{org: org, mission: mission, socket: join!(token, mission), token: token}
    end

    test "is off until subscribed, then sends a full snapshot", c do
      refute_push("fleet", _payload, 200)

      ref = Phoenix.ChannelTest.push(c.socket, "fleet:subscribe", %{})
      assert_reply(ref, :ok, %{})

      assert_push(
        "fleet",
        %{seq: 1, full: true, spacecraft: [row], counts: %{total: 1}} = payload,
        @load_ms
      )

      assert row.name == "EARENDIL-001"
      assert payload.heard == %{}
      assert payload.removed == []
      assert %{awaiting_viewer: 0} = payload.commands
    end

    test "the tick is a heartbeat; a spacecraft change arrives as a delta row", c do
      subscribed!(c.socket)

      tick!(c)
      assert_push("fleet", %{seq: 2, full: false, spacecraft: [], heard: heard}, @load_ms)
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
      Enum.each(replies, &assert_reply(&1, :ok, %{}))
      assert_push("fleet", %{seq: 1, full: true}, @load_ms)
      refute_push("fleet", _payload, 200)
    end

    test "unsubscribing before the snapshot drops it", c do
      # Queued in this order, the unsubscribe is handled before the subscription the subscribe
      # queues, so no source is ever asked.
      replies = queued(c.socket, ["fleet:subscribe", "fleet:unsubscribe"])
      Enum.each(replies, &assert_reply(&1, :ok, %{}))
      refute_push("fleet", _payload, 300)
      assert source(c) == nil
    end

    # fe-ops: a resubscribe on a seq gap is unsubscribe + subscribe back to back, maybe while the
    # first snapshot is still queued. Exactly one full snapshot either way, never seq 1 twice.
    test "subscribe, unsubscribe, subscribe back to back: exactly one snapshot", c do
      replies = queued(c.socket, ["fleet:subscribe", "fleet:unsubscribe", "fleet:subscribe"])
      Enum.each(replies, &assert_reply(&1, :ok, %{}))
      assert_push("fleet", %{seq: 1, full: true}, @load_ms)
      refute_push("fleet", %{seq: 1}, 200)
    end

    test "unsubscribe stops the push, and the mission's source with its last subscriber", c do
      subscribed!(c.socket)
      source = source(c)
      ref = Process.monitor(source)

      ref_unsub = Phoenix.ChannelTest.push(c.socket, "fleet:unsubscribe", %{})
      assert_reply(ref_unsub, :ok, %{})
      assert_receive {:DOWN, ^ref, :process, ^source, :normal}, 1_000

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

  # #797: a mission's sockets share its fleet reads.
  describe "one fleet read per mission, fanned out" do
    setup do
      org = TestFixtures.persist_org!()
      user = TestFixtures.persist_user!()
      TestFixtures.grant_membership!(user, org)
      mission = TestFixtures.persist_mission!(org)
      TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")
      token = TestFixtures.member_session_token!(user)

      handler = "fleet-source-loads-#{mission.mission_id}"

      :ok =
        :telemetry.attach(
          handler,
          [:cadence_web, :console, :fleet_source, :load, :stop],
          &__MODULE__.forward_load/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler) end)
      %{org: org, mission: mission, token: token}
    end

    test "three subscribed sockets: one read for their snapshots, one per tick", c do
      sockets = for _n <- 1..3, do: join!(c.token, c.mission)
      refs = Enum.map(sockets, &Phoenix.ChannelTest.push(&1, "fleet:subscribe", %{}))
      Enum.each(refs, &assert_reply(&1, :ok, %{}))

      for _n <- 1..3, do: assert_push("fleet", %{seq: 1, full: true}, @load_ms)
      assert_loads(c.mission, 1)

      tick!(c)
      for _n <- 1..3, do: assert_push("fleet", %{seq: 2, full: false}, @load_ms)
      assert_loads(c.mission, 1)
    end

    test "a source that goes down is followed again, without a second snapshot", c do
      socket = join!(c.token, c.mission)
      subscribed!(socket)
      assert_loads(c.mission, 1)

      old = source(c)
      Process.exit(old, :kill)

      # The channel subscribes again, which starts a fresh source; the stream carries on from seq 1.
      new = wait_for_new_source(c, old)
      send(new, :tick)
      assert_push("fleet", %{seq: 2, full: false}, @load_ms)
      refute_push("fleet", %{seq: 1}, 200)
    end
  end

  # console's #820 review: a read that keeps failing must not crash the source, or every channel
  # follows a fresh one at once and the reads fail again as fast as they can.
  describe "a failing fleet read" do
    setup do
      org = TestFixtures.persist_org!()
      user = TestFixtures.persist_user!()
      TestFixtures.grant_membership!(user, org)
      mission = TestFixtures.persist_mission!(org)
      %{org: org, mission: mission, token: TestFixtures.member_session_token!(user)}
    end

    test "keeps the source and its subscriber, logs once, skips ticks, and recovers", c do
      reads = :counters.new(1, [])
      row = %{id: "spacecraft-qa-1", name: "QA-1", state: "nominal", last_received_at: nil}
      shared = %{counts: %{total: 1}, limits: %{configured: false}, spacecraft: [row]}

      # Fails twice, then reads.
      load = fn _organization_id, _mission_id ->
        :counters.add(reads, 1, 1)
        if :counters.get(reads, 1) <= 2, do: raise("qa: the fleet read failed"), else: shared
      end

      key = {c.org.organization_id, c.mission.mission_id}
      source = start_supervised!({FleetSource, key: key, load: load})

      log =
        capture_log(fn ->
          socket = join!(c.token, c.mission)
          ref = Phoenix.ChannelTest.push(socket, "fleet:subscribe", %{})
          assert_reply(ref, :ok, %{})

          # The subscription's read fails: no snapshot, and no read until the next tick.
          refute_push("fleet", _payload, 300)
          assert :counters.get(reads, 1) == 1

          # A tick while reads fail pushes nothing, not even the heartbeat.
          send(source, :tick)
          refute_push("fleet", _payload, 300)

          # The third read succeeds: the waiting socket gets its snapshot.
          send(source, :tick)

          assert_push(
            "fleet",
            %{seq: 1, full: true, spacecraft: [%{id: "spacecraft-qa-1"}]},
            @load_ms
          )
        end)

      assert source(c) == source
      assert :counters.get(reads, 1) == 3
      assert length(Regex.scan(~r/couldn't read the fleet/, log)) == 1
    end
  end

  @doc false
  def forward_load(_event, _measurements, %{mission_id: mission_id}, test),
    do: send(test, {:fleet_load, mission_id})

  defp assert_loads(mission, count) do
    mission_id = mission.mission_id
    for _n <- 1..count, do: assert_receive({:fleet_load, ^mission_id}, @load_ms)
    refute_receive {:fleet_load, ^mission_id}, 300
  end

  defp join!(token, mission) do
    {:ok, socket} =
      Phoenix.ChannelTest.connect(ConsoleSocket, %{},
        connect_info: %{session: %{"user_session_token" => token}}
      )

    {:ok, _reply, socket} = subscribe_and_join(socket, "mission:" <> mission.mission_id, %{})
    socket
  end

  defp subscribed!(socket) do
    ref = Phoenix.ChannelTest.push(socket, "fleet:subscribe", %{})
    assert_reply(ref, :ok, %{})
    assert_push("fleet", %{seq: 1, full: true}, @load_ms)
  end

  defp source(c) do
    case Registry.lookup(FleetSources, {c.org.organization_id, c.mission.mission_id}) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  # The mission's source does its own tick; the test sends it one instead of waiting 10 s.
  defp tick!(c), do: send(source(c), :tick)

  defp wait_for_new_source(c, old, attempts \\ 50) do
    case source(c) do
      pid when is_pid(pid) and pid != old ->
        pid

      _none_yet when attempts > 0 ->
        Process.sleep(20)
        wait_for_new_source(c, old, attempts - 1)
    end
  end

  # Queues the events while the channel is suspended, so they reach it in exactly this order.
  defp queued(socket, events) do
    :sys.suspend(socket.channel_pid)
    refs = Enum.map(events, &Phoenix.ChannelTest.push(socket, &1, %{}))
    :sys.resume(socket.channel_pid)
    refs
  end
end
