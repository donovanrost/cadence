defmodule Cadence.Telemetry.ETSInstanceIsolationTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.CurrentValueStore.ETS, as: CurrentValueETS
  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.HistoryStore.ETS, as: HistoryETS
  alias Cadence.Telemetry.Sample

  @current_a_name __MODULE__.CurrentA
  @current_b_name __MODULE__.CurrentB
  @current_a_table :cadence_test_telemetry_current_values_a
  @current_b_table :cadence_test_telemetry_current_values_b
  @current_a_child_id {:telemetry_current_value_store, :a}
  @current_b_child_id {:telemetry_current_value_store, :b}

  @history_a_name __MODULE__.HistoryA
  @history_b_name __MODULE__.HistoryB
  @history_a_table :cadence_test_telemetry_history_a
  @history_b_table :cadence_test_telemetry_history_b
  @history_a_config_table :cadence_test_telemetry_history_config_a
  @history_b_config_table :cadence_test_telemetry_history_config_b
  @history_a_child_id {:telemetry_history_store, :a}
  @history_b_child_id {:telemetry_history_store, :b}

  @mission_id "shared-mission"
  @other_mission_id "other-mission"
  @point_id "HK.counter"

  test "current-value and history instances isolate lifecycle, data, and history config" do
    current_a = current_policy(:a)
    current_b = current_policy(:b)
    history_a = history_policy(:a)
    history_b = history_policy(:b)

    start_supervised!(CurrentValueStore.child_spec(current_a))
    start_supervised!(CurrentValueStore.child_spec(current_b))
    start_supervised!(HistoryStore.child_spec(history_a))
    start_supervised!(HistoryStore.child_spec(history_b))

    assert Process.whereis(@current_a_name) |> Process.alive?()
    assert Process.whereis(@current_b_name) |> Process.alive?()
    assert Process.whereis(@history_a_name) |> Process.alive?()
    assert Process.whereis(@history_b_name) |> Process.alive?()
    assert :ets.whereis(@current_a_table) != :undefined
    assert :ets.whereis(@current_b_table) != :undefined
    assert :ets.whereis(@history_a_table) != :undefined
    assert :ets.whereis(@history_b_table) != :undefined
    assert :ets.whereis(@history_a_config_table) != :undefined
    assert :ets.whereis(@history_b_config_table) != :undefined

    current_sample_a = sample("shared-current", @mission_id, 10, 1_700_000_100)
    current_sample_b = sample("shared-current", @mission_id, 20, 1_700_000_100)

    assert :ok = CurrentValueStore.record_samples(current_a, [current_sample_a])
    assert :ok = CurrentValueStore.record_samples(current_b, [current_sample_b])
    assert current_value(current_a).raw_value == 10
    assert current_value(current_b).raw_value == 20

    assert CurrentValueStore.latest_value(current_a, @mission_id, @point_id,
             table_name: @current_b_table
           ).raw_value == 10

    assert [current_b_latest] =
             CurrentValueStore.latest_values_for_mission(current_b, @mission_id, [])

    assert current_b_latest.raw_value == 20

    replacement_a = sample("shared-current", @mission_id, 11, 1_700_000_200)

    assert :ok =
             CurrentValueStore.replace_value(current_a, @mission_id, @point_id, replacement_a, [])

    assert current_value(current_a).raw_value == 11
    assert current_value(current_b).raw_value == 20

    assert :ok =
             CurrentValueStore.replace_value(current_a, @mission_id, @point_id, nil,
               table_name: @current_b_table
             )

    assert current_value(current_a) == nil
    assert current_value(current_b).raw_value == 20

    scoped_replacement_a = sample("shared-current", @mission_id, 12, 1_700_000_300)

    assert :ok =
             CurrentValueStore.replace_values_for_scope(
               current_a,
               @mission_id,
               [scoped_replacement_a],
               []
             )

    assert current_value(current_a).raw_value == 12
    assert current_value(current_b).raw_value == 20

    other_mission_sample = sample("other-current", @other_mission_id, 99, 1_700_000_400)
    assert :ok = CurrentValueStore.record_samples(current_a, [other_mission_sample])
    assert :ok = CurrentValueStore.reset(current_a, @mission_id)
    assert current_value(current_a) == nil

    assert CurrentValueStore.latest_value(current_a, @other_mission_id, @point_id, []).raw_value ==
             99

    assert current_value(current_b).raw_value == 20

    assert :ok = CurrentValueStore.record_samples(current_a, [current_sample_a])
    assert :ok = CurrentValueStore.reset(current_a)
    assert CurrentValueStore.latest_values_for_mission(current_a, @other_mission_id, []) == []
    assert current_value(current_b).raw_value == 20

    history_samples_a = history_samples(100)
    history_samples_b = history_samples(200)

    assert Enum.map(history_samples_a, & &1.sample_id) ==
             Enum.map(history_samples_b, & &1.sample_id)

    assert :ok = HistoryStore.persist_samples(history_a, history_samples_a)
    assert :ok = HistoryStore.persist_samples(history_b, history_samples_b)
    assert Enum.map(history_values(history_a), & &1.raw_value) == [102]
    assert Enum.map(history_values(history_b), & &1.raw_value) == [200, 201, 202]

    assert HistoryStore.sample_history(history_a, @mission_id, @point_id,
             table_name: @history_b_table,
             order: :asc,
             limit: 10
           )
           |> Enum.map(& &1.raw_value) == [102]

    assert {:ok, %{samples: history_b_samples, diagnostics: %{}}} =
             HistoryStore.sample_history_result(history_b, @mission_id, @point_id,
               order: :asc,
               limit: 10
             )

    assert Enum.map(history_b_samples, & &1.raw_value) == [200, 201, 202]

    assert :ok = HistoryStore.reset(history_a)
    assert history_values(history_a) == []
    assert Enum.map(history_values(history_b), & &1.raw_value) == [200, 201, 202]

    assert :ok = CurrentValueStore.record_samples(current_a, [current_sample_a])
    assert :ok = HistoryStore.persist_samples(history_a, history_samples_a)
    assert :ok = stop_supervised(@current_a_child_id)
    assert :ok = stop_supervised(@history_a_child_id)
    assert Process.whereis(@current_a_name) == nil
    assert Process.whereis(@history_a_name) == nil
    assert :ets.whereis(@current_a_table) == :undefined
    assert :ets.whereis(@history_a_table) == :undefined
    assert :ets.whereis(@history_a_config_table) == :undefined
    assert :ets.whereis(@history_b_config_table) != :undefined
    assert Process.whereis(@current_b_name) |> Process.alive?()
    assert Process.whereis(@history_b_name) |> Process.alive?()
    assert current_value(current_b).raw_value == 20
    assert Enum.map(history_values(history_b), & &1.raw_value) == [200, 201, 202]

    start_supervised!(CurrentValueStore.child_spec(current_a))
    start_supervised!(HistoryStore.child_spec(history_a))
    assert current_value(current_a) == nil
    assert history_values(history_a) == []
    assert :ok = CurrentValueStore.record_samples(current_a, [current_sample_a])
    assert :ok = HistoryStore.persist_samples(history_a, history_samples_a)
    assert current_value(current_a).raw_value == 10
    assert Enum.map(history_values(history_a), & &1.raw_value) == [102]
    assert :ets.whereis(@history_b_config_table) != :undefined
    assert Process.whereis(@current_b_name) |> Process.alive?()
    assert Process.whereis(@history_b_name) |> Process.alive?()
    assert current_value(current_b).raw_value == 20
    assert Enum.map(history_values(history_b), & &1.raw_value) == [200, 201, 202]
  end

  defp current_policy(:a) do
    CurrentValueStore.policy(
      module: CurrentValueETS,
      name: @current_a_name,
      child_id: @current_a_child_id,
      table_name: @current_a_table
    )
  end

  defp current_policy(:b) do
    CurrentValueStore.policy(
      module: CurrentValueETS,
      name: @current_b_name,
      child_id: @current_b_child_id,
      table_name: @current_b_table
    )
  end

  defp history_policy(:a) do
    HistoryStore.policy(
      module: HistoryETS,
      name: @history_a_name,
      child_id: @history_a_child_id,
      table_name: @history_a_table,
      config_table_name: @history_a_config_table,
      max_samples_per_point: 1
    )
  end

  defp history_policy(:b) do
    HistoryStore.policy(
      module: HistoryETS,
      name: @history_b_name,
      child_id: @history_b_child_id,
      table_name: @history_b_table,
      config_table_name: @history_b_config_table,
      max_samples_per_point: 3
    )
  end

  defp current_value(policy),
    do: CurrentValueStore.latest_value(policy, @mission_id, @point_id, [])

  defp history_values(policy) do
    HistoryStore.sample_history(policy, @mission_id, @point_id, order: :asc, limit: 10)
  end

  defp history_samples(raw_value_base) do
    for offset <- 0..2 do
      sample(
        "shared-history-#{offset}",
        @mission_id,
        raw_value_base + offset,
        1_700_000_500 + offset
      )
    end
  end

  defp sample(sample_id, mission_id, raw_value, receipt_unix) do
    receipt_time = DateTime.from_unix!(receipt_unix)

    %Sample{
      sample_id: sample_id,
      mission_id: mission_id,
      point_id: @point_id,
      point_name: @point_id,
      packet_definition_id: "packet-1",
      packet_definition_version: 1,
      packet_id: "packet-#{sample_id}",
      evidence_id: "evidence-#{sample_id}",
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      receipt_time: receipt_time,
      generation_time: receipt_time,
      provenance: %{}
    }
  end
end
