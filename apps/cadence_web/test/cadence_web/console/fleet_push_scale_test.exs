defmodule CadenceWeb.Console.FleetPushScaleTest do
  @moduledoc """
  The server half of the fleet push after the read (#798): fan-out and diff. 1,000 spacecraft,
  every row changed on each read (a full-fleet push, the worst case), to 20 joined `mission:`
  channels, each with its own transport process as in production. For each read it times from
  the end of the `[:cadence_web, :console, :fleet_source, :load]` span to the last socket's `fleet`
  push. It also times the parts apart: the source's sends (one deep copy per subscriber), one
  channel's diff, one channel's `CommandCounts` read, and the JSON encode each socket's transport
  adds (ChannelTest doesn't serialize).

  The read itself is `FleetStatus.load`, measured by `Cadence.Reads.FleetStatusScaleTest`; here it
  is a prepared fleet, so only what follows the read is timed. In the test sandbox every
  channel's `CommandCounts` query shares one connection, so they run one after another; in
  production they spread over the pool, so the fan-out here is an upper bound.

  Excluded by default (`--include scale`). It REPORTS p50 and p99 and asserts only a loose
  regression bound (fan-out p99 under 150 ms): the budget (30 ms, #798) is a number to read on a
  CI runner, not a gate a busy machine can flake.
  """
  use CadenceWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3, push: 3]
  require Phoenix.ChannelTest

  alias Cadence.Reads.{CommandCounts, FleetStatus}
  alias Cadence.Repo
  alias CadenceWeb.Console.{FleetJSON, FleetPush, FleetSource}
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures
  alias Phoenix.Socket.Message

  # MEASUREMENT ONLY (#798, do not merge): untagged so it runs in CI's core tests.
  @moduletag timeout: 600_000

  @crafts 1_000
  @sockets 20
  @rounds 100
  @event [:cadence_web, :console, :fleet_source, :load, :stop]

  test "fan-out and diff of a full-fleet push to #{@sockets} channels at #{@crafts} spacecraft" do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    key = {org.organization_id, mission.mission_id}
    persist_fleet(org, mission)

    # Two versions of the whole fleet that differ in every row; each read returns the other one.
    base = FleetJSON.mission(FleetStatus.load(org.organization_id, mission.mission_id), true)
    assert length(base.spacecraft) == @crafts
    flipped = %{base | spacecraft: Enum.map(base.spacecraft, &%{&1 | state: "critical"})}
    reads = :counters.new(1, [])

    load = fn _org, _mission ->
      :counters.add(reads, 1, 1)
      if rem(:counters.get(reads, 1), 2) == 0, do: flipped, else: base
    end

    {:ok, _source} =
      DynamicSupervisor.start_child(
        CadenceWeb.Console.FleetSourceSupervisor,
        {FleetSource, key: key, load: load}
      )

    test_pid = self()
    handler = "fleet-push-scale-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      @event,
      fn _event, _measurements, _meta, _config ->
        send(test_pid, {:load_stop, System.monotonic_time(:microsecond)})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    # Each socket gets its own transport process, as in production (one per websocket): it joins,
    # subscribes and reports when each `fleet` push reaches it.
    token = TestFixtures.member_session_token!(user)
    for _ <- 1..@sockets, do: transport(token, mission, test_pid)
    for _ <- 1..@sockets, do: assert_receive(:subscribed, 10_000)
    flush_loads()

    {fanouts, encodes} =
      Enum.reduce(1..@rounds, {[], []}, fn _round, {fanouts, encodes} ->
        FleetSource.note(org.organization_id, mission.mission_id)
        assert_receive {:load_stop, stopped}, 5_000
        {last, payload} = await_pushes(@sockets, nil, nil)
        assert length(payload.spacecraft) == @crafts
        {encode_us, _json} = :timer.tc(fn -> Jason.encode!(payload) end)
        {[last - stopped | fanouts], [encode_us | encodes]}
      end)

    fanout = stats(fanouts)
    encode = stats(encodes)

    # The source's own fan-out: one `send` of the shared fleet per subscriber, each a deep copy.
    sinks = for _ <- 1..@sockets, do: spawn_link(fn -> Process.sleep(:infinity) end)

    sends =
      stats(
        for _ <- 1..@rounds,
            do:
              elem(
                :timer.tc(fn -> Enum.each(sinks, &send(&1, {:fleet_loaded, flipped, false})) end),
                0
              )
      )

    # Each channel's own work, apart: the diff of the whole fleet, and its viewer's command counts.
    rows = Map.new(base.spacecraft, &{&1.id, &1})

    diff =
      stats(
        for _ <- 1..@rounds,
            do: elem(:timer.tc(fn -> FleetPush.diff(rows, flipped.spacecraft, false) end), 0)
      )

    counts =
      stats(
        for _ <- 1..@rounds,
            do:
              elem(
                :timer.tc(fn ->
                  CommandCounts.load(org.organization_id, mission.mission_id, user.user_id)
                end),
                0
              )
      )

    IO.puts(
      "\nFLEET_PUSH_SCALE #{Jason.encode!(%{crafts: @crafts, sockets: @sockets, rounds: @rounds, fanout_to_last_push_ms: fanout, json_encode_per_push_ms: encode, diff_per_channel_ms: diff, command_counts_per_channel_ms: counts, source_sends_all_ms: sends, payload_bytes: :erlang.external_size(flipped)})}"
    )

    assert fanout.p99 < 150
  end

  defp persist_fleet(org, mission) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      for n <- 1..@crafts do
        %{
          spacecraft_id: "sc-#{mission.mission_id}-#{n}",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          display_name: "SC-#{String.pad_leading(Integer.to_string(n), 4, "0")}",
          scid: n,
          inserted_at: now
        }
      end

    {@crafts, _} = Repo.insert_all("mission_spacecraft", rows)
  end

  # ChannelTest connects only from the test process; the socket then joins from its own process,
  # which becomes its transport.
  defp transport(token, mission, test_pid) do
    socket = connect!(token)

    spawn_link(fn ->
      subscribe!(join!(%{socket | transport_pid: self()}, mission))
      send(test_pid, :subscribed)
      relay(test_pid)
    end)
  end

  # Tells the test when each push arrived; the first carries the payload, to encode once.
  defp relay(test_pid) do
    receive do
      %Message{event: "fleet", payload: payload} ->
        send(test_pid, {:pushed, System.monotonic_time(:microsecond), payload})
        relay(test_pid)
    end
  end

  # When the last of `n` sockets got its push, and one payload.
  defp await_pushes(0, last, payload), do: {last, payload}

  defp await_pushes(n, last, payload) do
    assert_receive {:pushed, at, pushed}, 5_000
    await_pushes(n - 1, max(at, last || at), payload || pushed)
  end

  defp flush_loads do
    receive do
      {:load_stop, _at} -> flush_loads()
      {:pushed, _at, _payload} -> flush_loads()
    after
      200 -> :ok
    end
  end

  defp stats(microseconds) do
    sorted = Enum.sort(microseconds)
    at = fn q -> Enum.at(sorted, min(length(sorted) - 1, ceil(q * length(sorted)) - 1)) / 1000 end
    %{p50: at.(0.5), p99: at.(0.99), max: List.last(sorted) / 1000}
  end

  defp connect!(token) do
    {:ok, socket} =
      Phoenix.ChannelTest.connect(ConsoleSocket, %{},
        connect_info: %{session: %{"user_session_token" => token}}
      )

    socket
  end

  defp join!(socket, mission) do
    {:ok, _reply, socket} = join(socket, "mission:" <> mission.mission_id, %{})
    socket
  end

  defp subscribe!(socket) do
    ref = Phoenix.ChannelTest.push(socket, "fleet:subscribe", %{})
    assert_reply(ref, :ok, %{})
    assert_push("fleet", %{full: true}, 5_000)
  end
end
