defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractFailClosedTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden unknown widget fixture is retained as placement warning" do
    document = load_fixture!("unknown_widget_retained.v1.json")

    result = Engine.plan(resolve_request(document), source_registry_opts([]))

    assert result.planned_source_requests == []
    assert result.plan_metadata.degraded?

    assert [
             %ResolveWarning{code: :unknown_widget_type, scope: :dashboard},
             %ResolveWarning{code: :unknown_widget_type, scope: :placement}
           ] = result.dashboard_warnings

    assert %{"placement_legacy" => %PlacementFrames{primary: [], overlays: %{}} = frames} =
             result.frames_by_placement

    assert [%ResolveWarning{code: :unknown_widget_type, placement_id: "placement_legacy"}] =
             frames.warnings
  end

  test "golden unsupported source pairing fixture fails closed as unsupported lifecycle" do
    document = load_fixture!("unsupported_operational_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: false, errors: validation_errors} =
             Dashboards.validate_document(document)

    assert [
             %{
               code: :unsupported_widget_frame_contract,
               details: validation_details
             }
           ] = validation_errors

    assert validation_details.placement_id == "placement_operational_series_unsupported"
    assert validation_details.widget_type_id == "cadence.time_series"
    assert validation_details.requested_source == :operational_observables
    assert validation_details.contract_source == :telemetry

    assert validation_details.supported_products == [
             :transport_bitrate,
             :link_rf,
             :runtime_ingress
           ]

    assert validation_details.supported_value_kinds == [:metric]
    assert validation_details.requested_products == [:contacts_phase]
    assert validation_details.requested_value_kinds == [:state]
    assert validation_details.unsupported_observables == ["contacts.phase"]

    result =
      Engine.plan(
        resolve_request(document, %{
          "placement_operational_series_unsupported" => %{width_px: 640, height_px: 256}
        }),
        operational_source_registry_opts(validate_dashboard_contract?: true)
      )

    assert result.planned_source_requests == []
    assert result.plan_metadata.degraded?
    assert result.plan_metadata.source_request_count == 0

    assert [
             %ResolveWarning{
               code: :unsupported_widget_frame_contract,
               severity: :error,
               scope: :dashboard,
               details: dashboard_details
             },
             %ResolveWarning{
               code: :unsupported_widget_frame_contract,
               severity: :warning,
               scope: :placement,
               placement_id: "placement_operational_series_unsupported",
               details: placement_details
             }
           ] = result.dashboard_warnings

    assert dashboard_details.placement_id == "placement_operational_series_unsupported"
    assert placement_details.widget_type_id == "cadence.time_series"
    assert placement_details.requested_source == :operational_observables
    assert placement_details.contract_source == :telemetry

    assert placement_details.supported_products == [
             :transport_bitrate,
             :link_rf,
             :runtime_ingress
           ]

    assert placement_details.supported_value_kinds == [:metric]
    assert placement_details.requested_products == [:contacts_phase]
    assert placement_details.requested_value_kinds == [:state]
    assert placement_details.unsupported_observables == ["contacts.phase"]
    assert placement_details.fallback == :none

    assert %{
             "placement_operational_series_unsupported" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: [
                   %ResolveWarning{
                     code: :unsupported_widget_frame_contract,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_operational_series_unsupported"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.unresolved? == false
    assert data.engine_backed?
    assert data.kind == :point
    assert data.sample == nil
    assert data.lifecycle_state == :unsupported
    assert data.lifecycle.warning_codes == [:unsupported_widget_frame_contract]

    assert %{
             state: :no_data,
             severity: :info,
             data_state: :no_data,
             warning_codes: [:unsupported_widget_frame_contract]
           } = data.source_status
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes \\ nil) do
    placement_sizes =
      placement_sizes ||
        %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}

    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp source_registry_opts(opts) do
    Keyword.merge(
      [
        data_sources: [
          DataSources.default_managed_data_source(),
          DataSources.default_limits_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_telemetry_binding(),
          DataSources.default_flight_limits_binding()
        ]
      ],
      opts
    )
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
end
