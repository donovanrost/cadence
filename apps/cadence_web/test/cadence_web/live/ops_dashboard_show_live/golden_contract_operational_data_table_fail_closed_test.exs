defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalDataTableFailClosedTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

  alias Cadence.Management.DataSources

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden operational data table fixture fails closed when command queue reader fails" do
    document = load_fixture!("stale_operational_data_table.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_command_queue_data_table" => %{width_px: 640}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "mission", mode: "one", ids: ["mission_dashboards"]}
      })

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_result_cache?: false,
          source_opts: failing_command_queue_source_opts(),
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.returned_frame_count == 0

    assert [%ResolveWarning{code: :source_unavailable, severity: :error} = warning] =
             result.dashboard_warnings

    assert warning.details.logical_source == :operational_observables
    assert warning.details.data_source_id == "managed_operational_observables"
    assert warning.details.source_binding_id == "default_flight_operational_observables"
    assert warning.details.reason =~ "test command queue failure"
    assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
    assert link_targets(warning) == [:telemetry_point]

    assert %{
             "placement_command_queue_data_table" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: [
                   %ResolveWarning{
                     code: :source_unavailable,
                     severity: :error,
                     scope: :placement,
                     placement_id: "placement_command_queue_data_table"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :error,
             lifecycle: %{
               state: :error,
               severity: :error,
               warning_codes: [:source_unavailable]
             },
             source_status: %{
               state: :unavailable,
               severity: :error,
               data_state: :no_data,
               warning_codes: [:source_unavailable],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"]
             },
             rows: []
           } = data
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp operational_source_registry_opts(opts) do
    Keyword.merge(
      [
        source_health_events?: false,
        source_watermark_events?: false,
        data_sources: [
          DataSources.default_operational_observables_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_operational_observables_binding()
        ]
      ],
      opts
    )
  end

  defp failing_command_queue_source_opts do
    %{
      operational_observables: [
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          raise "test command queue failure"
        end
      ]
    }
  end

  defp link_targets(%ResolveWarning{links: links}) do
    Enum.map(links, & &1.target)
  end
end
