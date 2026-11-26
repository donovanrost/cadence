defmodule Cadence.Runtime.PartitionOwner.CurrentValueSeedTest do
  @moduledoc """
  A starting partition seeds the ETS current-value store from QuestDB's latest values for its source
  endpoint (#831). QuestDB is replaced here by the reader's `exec_fun`; the statement it is sent and
  the rows it answers are the real shapes (the QuestDB suite runs the statement for real).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Runtime.PartitionOwner.CurrentValueSeed
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Sample, Storage}
  alias Cadence.Telemetry.CurrentValueStore.ETS
  alias Cadence.Telemetry.Storage.QuestDB.ObservationReader

  @mission "mission-seed-start"
  @org "org-seed-start"
  @old ~U[2026-11-20 10:00:00Z]

  setup do
    persist_mission_scope(@org, @mission)
    table = :"seed_start_#{System.unique_integer([:positive])}"
    cache = CurrentValueStore.policy(module: ETS, table_name: table, name: table)
    start_supervised!(CurrentValueStore.child_spec(cache))

    storage =
      Storage.policy(
        [
          writer: Cadence.TestSupport.CapturingTelemetryStorageWriter,
          writer_opts: [test_pid: self()],
          organization_id: @org,
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        ],
        current_value_store_policy: cache
      )

    %{cache: cache, storage: storage}
  end

  # A QuestDB answer: one row per {spacecraft, point, value, receipt time}.
  defp answer(rows) do
    columns = ObservationReader.select_columns()

    dataset =
      for {craft, point, value, at} <- rows do
        values = %{
          "sample_id" => "q-#{craft}-#{point}",
          "mission_id" => @mission,
          "spacecraft_id" => craft,
          "point_id" => point,
          "point_name" => point,
          "packet_definition_id" => "pd",
          "packet_definition_version" => 1,
          "packet_id" => "pk",
          "evidence_id" => "ev",
          "value_kind" => "double",
          "value_double" => value,
          "quality_state" => "good",
          "generation_time" => DateTime.to_iso8601(at),
          "receipt_time" => DateTime.to_iso8601(at),
          "realm" => "flight",
          "data_source_id" => "managed_questdb_primary",
          "binding_id" => "default_flight_telemetry",
          "source_endpoint_id" => "station-1",
          "validity_state" => "canonical"
        }

        Enum.map(columns, &Map.get(values, &1))
      end

    {:ok, %{"columns" => Enum.map(columns, &%{"name" => &1}), "dataset" => dataset}}
  end

  defp state(c) do
    %{
      mission_id: @mission,
      persist_runtime_records?: true,
      partition_key: PartitionKey.new(%{affinity: :source_endpoint, value: "station-1"}),
      active_activation: %{organization_id: @org},
      persistence_policy: %{telemetry_storage: c.storage}
    }
  end

  defp history(exec), do: %{backend: HistoryStore.QuestDB, backend_opts: [exec_fun: exec]}

  defp start(c, exec) do
    CurrentValueSeed.start(state(c),
      history_store_policy: history(exec),
      spread_ms: 0,
      notify: self()
    )
  end

  defp values(c) do
    Map.new(
      CurrentValueStore.latest_values_for_mission(c.cache, @mission, []),
      &{{&1.spacecraft_id, &1.point_id}, &1}
    )
  end

  test "asks QuestDB once for the endpoint's latest per spacecraft and point, and seeds them",
       c do
    parent = self()

    exec = fn sql, _opts ->
      send(parent, {:sql, sql})

      answer([
        {"sc-1", "HK.a", 11.0, @old},
        {"sc-1", "HK.b", 12.0, @old},
        {"sc-2", "HK.a", 21.0, DateTime.add(@old, 60)}
      ])
    end

    assert :ok = start(c, exec)
    assert_receive {:current_values_seeded, {:ok, 3}}, 2_000

    assert_receive {:sql, sql}
    assert sql =~ "LATEST ON observed_at PARTITION BY spacecraft_id, point_id"
    assert sql =~ "source_endpoint_id = 'station-1'"
    assert sql =~ "mission_id = '#{@mission}'"
    assert sql =~ "validity_state = 'canonical'"
    refute_receive {:sql, _}, 50

    seeded = values(c)

    assert Map.keys(seeded) |> Enum.sort() == [
             {"sc-1", "HK.a"},
             {"sc-1", "HK.b"},
             {"sc-2", "HK.a"}
           ]

    # Truth before calm: each value keeps its own time, however long ago it was.
    assert %Sample{engineering_value: 11.0, receipt_time: at} = seeded[{"sc-1", "HK.a"}]
    assert DateTime.compare(at, @old) == :eq
  end

  test "never overwrites a newer value the store already has", c do
    newer = %Sample{
      sample_id: "live",
      mission_id: @mission,
      spacecraft_id: "sc-1",
      point_id: "HK.a",
      point_name: "HK.a",
      packet_definition_id: "pd",
      packet_definition_version: 1,
      packet_id: "pk",
      evidence_id: "ev",
      raw_value: 99,
      engineering_value: 99.0,
      quality_state: :good,
      generation_time: DateTime.utc_now(),
      receipt_time: DateTime.utc_now(),
      provenance: %{}
    }

    :ok = Storage.persist_samples(c.storage, [newer], organization_id: @org)

    assert :ok = start(c, fn _sql, _opts -> answer([{"sc-1", "HK.a", 11.0, @old}]) end)
    assert_receive {:current_values_seeded, {:ok, 1}}, 2_000
    assert %Sample{engineering_value: 99.0} = values(c)[{"sc-1", "HK.a"}]
  end

  test "an unreachable QuestDB is a logged failure, never a crash or a delay", c do
    assert :ok = start(c, fn _sql, _opts -> {:error, :econnrefused} end)
    assert_receive {:current_values_seeded, {:error, :econnrefused}}, 2_000
    assert values(c) == %{}

    assert :ok = start(c, fn _sql, _opts -> raise "boom" end)
    assert_receive {:current_values_seeded, {:error, %RuntimeError{}}}, 2_000
  end

  test "it applies only to an ETS cache, a QuestDB history, and a partition that persists", c do
    exec = fn _sql, _opts -> answer([{"sc-1", "HK.a", 1.0, @old}]) end

    # The Postgres current-value store is not seeded.
    postgres =
      Storage.policy([realm: :flight],
        current_value_store_policy: %{backend: CurrentValueStore.Postgres, backend_opts: []}
      )

    assert :ok =
             CurrentValueSeed.start(
               %{state(c) | persistence_policy: %{telemetry_storage: postgres}},
               history_store_policy: history(exec),
               spread_ms: 0,
               notify: self()
             )

    # A history store that is not QuestDB.
    assert :ok =
             CurrentValueSeed.start(state(c),
               history_store_policy: %{backend: HistoryStore.Postgres, backend_opts: []},
               spread_ms: 0,
               notify: self()
             )

    # A partition that does not persist runtime records, and one not keyed by a source endpoint.
    assert :ok =
             CurrentValueSeed.start(%{state(c) | persist_runtime_records?: false},
               history_store_policy: history(exec),
               spread_ms: 0,
               notify: self()
             )

    mission_root = PartitionKey.new(%{affinity: :mission, value: @mission})

    assert :ok =
             CurrentValueSeed.start(%{state(c) | partition_key: mission_root},
               history_store_policy: history(exec),
               spread_ms: 0,
               notify: self()
             )

    refute_receive {:current_values_seeded, _}, 100
    assert values(c) == %{}
  end
end
