defmodule Cadence.Dashboards.EngineQuestDBDecimationTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Dashboards.{DashboardResolveRequest, Document, Engine, Frame}

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Telemetry.HistoryStore.QuestDB
  alias Cadence.Telemetry.Storage.QuestDB.ObservationReader

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  setup do
    previous_config = Application.get_env(:cadence, :telemetry_history_store, [])

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_history_store, previous_config)
    end)

    :ok
  end

  test "resolves native decimated telemetry through the configured QuestDB reader" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    parent = self()

    exec_fun = fn sql, opts ->
      send(parent, {:questdb_exec, sql, opts})

      if sql =~ "max(receipt_time) AS latest_receipt_time" do
        {:ok,
         %{
           "columns" => Enum.map(ObservationReader.watermark_select_columns(), &%{"name" => &1}),
           "dataset" => [[~N[2026-06-17 12:05:00], ~N[2026-06-17 11:00:00], 120]]
         }}
      else
        {:ok,
         %{
           "columns" => Enum.map(ObservationReader.decimated_select_columns(), &%{"name" => &1}),
           "dataset" => [
             [~N[2026-06-17 12:00:00], 11.5, 12.75, 12.25, 120, "good"]
           ]
         }}
      end
    end

    Application.put_env(:cadence, :telemetry_history_store,
      module: QuestDB,
      exec_fun: exec_fun
    )

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "layout", "w"], 6)
      |> put_in(["placements", Access.at(0), "layout", "h"], 4)
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "widget_type_id"],
        "cadence.time_series"
      )
      |> put_in(
        ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
        "decimated_envelope"
      )
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
          interaction_context: %{
            placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 240}}
          }
        },
        data_sources: [
          %DataSource{
            data_source_id: "native-decimating-questdb",
            adapter: Cadence.Dashboards.Sources.Telemetry,
            capabilities: %{native_decimation?: true, watermarks?: true}
          }
        ],
        data_bindings: [
          %DataBinding{
            binding_id: "flight-telemetry",
            organization_id: "org_dashboards",
            mission_id: "mission_dashboards",
            realm: :flight,
            logical_source: :telemetry,
            data_source_id: "native-decimating-questdb",
            dataset: "flight"
          }
        ]
      )

    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1
    refute result.plan_metadata.degraded?
    assert [%{code: :physical_aggregate_semantics, severity: :info}] = result.dashboard_warnings

    assert [
             %Cadence.DataSources.SourceWatermark{
               confidence: :best_effort,
               complete_through: ~U[2026-06-17 12:05:00Z],
               latest_receipt_time: ~U[2026-06-17 12:05:00Z],
               retention_starts_at: ~U[2026-06-17 11:00:00Z]
             } = watermark
           ] = result.watermarks

    assert watermark.meta.canonical_mode == :physical
    assert watermark.meta.aggregate_semantics == :physical_as_recorded

    assert %{"placement_battery_voltage" => placement_frames} = result.frames_by_placement
    assert [%Frame{source: :telemetry, fields: fields} = frame] = placement_frames.primary
    assert frame.meta.sampling == :decimated_envelope
    assert frame.meta.decimation == :native_min_max_envelope
    assert frame.meta.canonical_mode == :physical
    assert frame.meta.aggregate_semantics == :physical_as_recorded
    assert :physical_aggregate_semantics in frame.meta.warning_codes
    assert Enum.find(fields, &(&1.name == "tlm.hk.battery_voltage_min")).values == [11.5]
    assert Enum.find(fields, &(&1.name == "tlm.hk.battery_voltage_max")).values == [12.75]
    assert Enum.find(fields, &(&1.name == "tlm.hk.battery_voltage_value")).values == [12.25]

    assert_receive {:questdb_exec, watermark_sql, watermark_opts}
    assert watermark_sql =~ "max(receipt_time) AS latest_receipt_time"
    assert watermark_sql =~ "data_source_id = 'native-decimating-questdb'"
    assert watermark_opts[:exec_fun] == exec_fun

    assert_receive {:questdb_exec, decimated_sql, decimated_opts}
    assert decimated_sql =~ "FROM telemetry_observations"
    assert decimated_sql =~ "SAMPLE BY"
    assert decimated_sql =~ "data_source_id = 'native-decimating-questdb'"
    assert decimated_opts[:exec_fun] == exec_fun
  end

  defp load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
