defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractEbN0MetricValueTileTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem
  }

  alias CadenceWeb.OpsDashboardShowLive.{DataLinkSelection, WidgetPresentation}

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
    dataset: [:data, :dataset],
    source_request_id: [:source_request_id]
  ]

  test "golden operational Eb/N0 metric value-tile fixture preserves link-scoped DataLinks through presenter data" do
    document = load_fixture!("operational_eb_n0_metric_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_link_eb_n0" => %{width_px: 320}})
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
               observables: ["link.eb_n0_db"],
               sampling_mode: :latest,
               products: [
                 :transport_bitrate,
                 :link_rf,
                 :commanding,
                 :runtime_ingress
               ],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_metric_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :rf_metric_transports_called
    assert_received :link_rf_metric_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_link_eb_n0" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :link_rf_metric,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       product_family: :link_rf,
                       observable_ids: ["link.eb_n0_db"],
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["link.eb_n0_db"]
    assert field_values(frame, "resource_id") == ["link-golden-alpha"]
    assert field_values(frame, "label") == ["RF Eb/N0 / link-golden-alpha"]
    assert field_values(frame, "scope_kind") == [:link]
    assert field_values(frame, "transport_id") == ["transport-golden-alpha"]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "ground_station_id") == ["dss-14"]
    assert field_values(frame, "link_id") == ["link-golden-alpha"]
    assert field_values(frame, "adapter_key") == [:rf_adapter]
    assert field_values(frame, "value") == [9.25]
    assert field_values(frame, "unit") == ["dB"]
    assert field_values(frame, "observed_at") == [~U[2026-06-17 12:06:30Z]]
    assert field_values(frame, "freshness_state") == [:fresh]

    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")
    source_endpoint_link = link_by_target(frame, :source_endpoint, "source-endpoint-golden-1")
    ground_station_link = link_by_target(frame, :ground_station, "dss-14")
    link_link = link_by_target(frame, :link, "link-golden-alpha")

    for link <- [transport_link, source_endpoint_link, ground_station_link, link_link] do
      assert_link_runtime_context(link,
        logical_source: "operational_observables",
        observable_id: "link.eb_n0_db",
        scope_kind: "link",
        scope_id: "link-golden-alpha",
        time_mode: "live",
        time_axis: "generation_time",
        realm: "flight",
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        source_request_id: frame.meta.source_request_id
      )

      assert context_value(link.context, [:operational_resource]) == %{
               adapter_key: :rf_adapter,
               ground_station_id: "dss-14",
               link_id: "link-golden-alpha",
               resource_id: "link-golden-alpha",
               scope_kind: :link,
               source_endpoint_id: "source-endpoint-golden-1",
               transport_id: "transport-golden-alpha"
             }
    end

    assert DataLinkSelection.selected_ref(transport_link, %{
             "placement-id" => "placement_link_eb_n0"
           }) == %{
             "link_id" => transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-alpha",
             "target_text" => "transport",
             "placement_id" => "placement_link_eb_n0",
             "source" => "frame",
             "scope_kind" => "link",
             "scope_id" => "link-golden-alpha",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-alpha",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "observable_id" => "link.eb_n0_db"
           }

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             unit: "dB",
             label: "RF Eb/N0 / link-golden-alpha",
             sample: %{
               sample_id: "link-golden-alpha",
               raw_value: 9.25,
               engineering_value: 9.25,
               receipt_time: ~U[2026-06-17 12:06:30Z],
               generation_time: ~U[2026-06-17 12:06:30Z],
               quality_state: :observed
             }
           } = data

    assert Enum.map(data.links, &{&1.target, &1.target_id}) == [
             {:link, "link-golden-alpha"},
             {:transport, "transport-golden-alpha"},
             {:source_endpoint, "source-endpoint-golden-1"},
             {:ground_station, "dss-14"}
           ]
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

  defp operational_rf_metric_source_opts(parent) do
    %{
      operational_observables: [
        link_rf_metric_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :link_rf_metric_revision_called)
          "link-rf-metric-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_metric_transports_called)

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
          send(parent, :link_rf_metric_snapshots_called)

          [
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:06:00Z]
            },
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              value: 9.25,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:06:30Z]
            }
          ]
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
    meta
    |> Map.get(:links, [])
    |> Enum.find(&(&1.target == target and &1.target_id == target_id))
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
