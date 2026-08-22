defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalRfMetricNoDataTimeSeriesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem
  }

  alias Cadence.Management.DataSources

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)
  @optional_link_context_paths [
    logical_source: [:logical_source],
    observable_id: [:observable_id],
    scope_kind: [:scope, :primary, :kind],
    time_mode: [:time, :mode],
    time_axis: [:time, :axis],
    realm: [:data, :realm],
    data_source_id: [:data, :data_source_id],
    source_binding_id: [:data, :source_binding_id],
    source_request_id: [:source_request_id]
  ]

  test "golden operational RF metric no-data time-series fixture remains chartable" do
    document = load_fixture!("operational_rf_metric_no_data_time_series.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_link_snr_history_no_data" => %{width_px: 640, height_px: 256}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "link", mode: "one", ids: ["link-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["link.snr_db"],
               sampling_mode: :raw_series,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_metric_history_no_data_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :rf_metric_history_transports_called
    assert_received :link_rf_metric_history_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_link_snr_history_no_data" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :wide,
                     time_axis: :occurred_at,
                     meta: %{
                       supported_capability: :link_rf_metric_history,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       product_family: :link_rf,
                       observable_id: "link.snr_db",
                       observable_ids: ["link.snr_db"],
                       resource_id: "link-golden-alpha",
                       scope_kind: :link,
                       transport_id: "transport-golden-alpha",
                       source_endpoint_id: "source-endpoint-golden-1",
                       ground_station_id: "dss-14",
                       link_id: "link-golden-alpha",
                       adapter_key: :rf_adapter,
                       returned_points: 0,
                       unit: "dB",
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "time") == []
    assert field_values(frame, "link.snr_db") == []
    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")

    assert_link_runtime_context(transport_link,
      logical_source: "operational_observables",
      observable_id: "link.snr_db",
      scope_kind: "link",
      scope_id: "link-golden-alpha",
      time_mode: "archive",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      source_request_id: frame.meta.source_request_id
    )

    assert context_value(transport_link.context, [:operational_resource]) == %{
             adapter_key: :rf_adapter,
             ground_station_id: "dss-14",
             link_id: "link-golden-alpha",
             resource_id: "link-golden-alpha",
             scope_kind: :link,
             source_endpoint_id: "source-endpoint-golden-1",
             transport_id: "transport-golden-alpha"
           }

    assert WidgetPresentation.backfill(nil, placement_frames, render_widget(document)) == nil

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: nil,
             lifecycle_state: :no_data,
             lifecycle: %{state: :no_data, severity: :info, warning_codes: []},
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               warning_codes: [],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               scope_kinds: ["link"],
               scope_ids: ["link-golden-alpha"],
               time_modes: ["archive"],
               time_axes: ["generation_time"],
               empty_reason: :scope_no_data
             }
           } = WidgetPresentation.data(nil, placement_frames, render_widget(document))
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

  defp operational_rf_metric_history_no_data_source_opts(parent) do
    %{
      operational_observables: [
        link_rf_metric_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_history_revision_called)
          "link-rf-metric-history-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_metric_history_transports_called)

          [
            %{
              transport_id: "transport-golden-alpha",
              display_name: "Golden Alpha RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-1",
                ground_station_id: "dss-14",
                link_assignment_id: "link-golden-alpha"
              }
            },
            %{
              transport_id: "transport-golden-beta",
              display_name: "Golden Beta RF",
              adapter_key: :rf_adapter,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-2",
                ground_station_id: "dss-63",
                link_assignment_id: "link-golden-beta"
              }
            }
          ]
        end,
        link_rf_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_history_snapshots_called)
          []
        end
      ]
    }
  end

  defp request_summary(request) do
    %{
      logical_source: request.logical_source,
      observables: request.observables,
      sampling_mode: request.sampling.mode,
      products: Map.get(request.sampling, :products, []),
      overlays: request.overlays,
      target_points: Map.get(request.sampling, :target_points),
      time_axis: request.time_context.axis,
      data_source_id: request.metadata.capability_provenance.data_source_id,
      source_binding_id: request.metadata.capability_provenance.binding_id
    }
  end

  defp render_widget(%Document{} = document) do
    [render_item] = RenderItem.from_document(document)
    render_item.widget
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end

  defp link_targets(%Frame{meta: meta}) do
    meta
    |> Map.get(:links, [])
    |> Enum.map(& &1.target)
  end

  defp link_by_target(%Frame{meta: meta}, target, target_id) do
    Enum.find(Map.get(meta, :links, []), &(&1.target == target and &1.target_id == target_id))
  end

  defp assert_link_runtime_context(link, opts) do
    refute is_nil(link)

    assert_context_texts(link, [
      {[:organization_id], "org_dashboards"},
      {[:mission_id], "mission_dashboards"}
    ])

    assert_context_texts(link, optional_context_texts(opts))
    assert_scope_id(link, Keyword.get(opts, :scope_id))
  end

  defp optional_context_texts(opts) do
    for {key, path} <- @optional_link_context_paths,
        expected = Keyword.get(opts, key),
        not is_nil(expected),
        do: {path, expected}
  end

  defp assert_context_texts(link, expected_values) do
    Enum.each(expected_values, fn {path, expected} ->
      assert context_text(context_value(link.context, path)) == expected
    end)
  end

  defp assert_scope_id(_link, nil), do: :ok

  defp assert_scope_id(link, expected) do
    assert context_value(link.context, [:scope, :primary, :ids]) == [expected]
  end

  defp context_value(context, path) when is_map(context) and is_list(path) do
    Enum.reduce(path, context, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key, Map.get(acc, Atom.to_string(key)))
        _other -> nil
      end
    end)
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
  defp context_text(value) when is_integer(value), do: Integer.to_string(value)
end
