defmodule Cadence.Runtime.Telemetry.Lanes.RouterBatchDispatchTest do
  use Cadence.PureCase, async: false

  alias Cadence.Runtime.Telemetry.Lanes.Router
  alias Cadence.Telemetry.PacketEnvelope

  setup_mission_registry()

  setup do
    case Process.whereis(Cadence.PubSub) do
      nil -> start_supervised!({Phoenix.PubSub, name: Cadence.PubSub})
      _pid -> :ok
    end

    :ok
  end

  test "dispatches queued events to shard workers in bounded batches" do
    mission_id = random_id()
    lanes = [%{name: :payload, shard_count: 1, virtual_shards: 1, selectors: %{}}]

    {:ok, router_pid} =
      start_supervised(
        {Router,
         mission_id: mission_id, lanes: lanes, max_inflight: 10, max_dispatch_batch_size: 4}
      )

    {:ok, _registry_value} =
      Registry.register(
        Cadence.MissionRegistry,
        {:lanes, mission_id, {:shard, :payload, 0}},
        :capture
      )

    GenServer.cast(router_pid, {:shard_ready, :payload, 0, 10})

    Enum.each(1..12, fn _ ->
      send(router_pid, {:packet_envelope, PacketEnvelope.new(mission_id, <<1>>)})
    end)

    assert_eventually(
      fn ->
        {:messages, messages} = Process.info(self(), :messages)

        batch_sizes =
          messages
          |> Enum.filter(fn
            {:"$gen_cast", {:telemetry_batch, _events, _dispatch_ns}} -> true
            _ -> false
          end)
          |> Enum.map(fn {:"$gen_cast", {:telemetry_batch, events, _dispatch_ns}} ->
            length(events)
          end)

        router_state = :sys.get_state(router_pid)

        batch_sizes == [4, 4, 2] and
          get_in(router_state, [:lane_state, :payload, :credits, 0]) == 0 and
          get_in(router_state, [:lane_state, :payload, :queue_depth]) == 2
      end,
      timeout: 3_000
    )
  end
end
