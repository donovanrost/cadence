defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractTransportUplinkMetricValueTileTest do
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

  test "golden operational uplink metric value-tile fixture preserves directional resource DataLinks" do
    document = load_fixture!("operational_uplink_metric_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_uplink_bitrate" => %{width_px: 320}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "transport", mode: "one", ids: ["transport-golden-alpha"]}
      })

    plan =
      Engine.plan(request, operational_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["comms.transport.uplink_bitrate"],
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
          source_opts: operational_metric_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :metric_transports_called
    assert_received :transport_metric_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_uplink_bitrate" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :transport_bitrate,
                       source_binding_id: "default_flight_operational_observables",
                       data_source_id: "managed_operational_observables",
                       observable_id: "comms.transport.uplink_bitrate",
                       warning_codes: []
                     }
                   } = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["comms.transport.uplink_bitrate"]
    assert field_values(frame, "resource_id") == ["transport-golden-alpha"]
    assert field_values(frame, "label") == ["Golden Alpha TCP"]
    assert field_values(frame, "scope_kind") == [:transport]
    assert field_values(frame, "transport_id") == ["transport-golden-alpha"]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "ground_station_id") == ["dss-14"]
    assert field_values(frame, "link_id") == ["link-golden-alpha"]
    assert field_values(frame, "adapter_key") == [:tcp_socket]
    assert field_values(frame, "value") == [4_800.0]
    assert field_values(frame, "unit") == ["bit/s"]
    assert field_values(frame, "observed_at") == [~U[2026-06-17 12:04:00Z]]
    assert field_values(frame, "freshness_state") == [:fresh]

    assert link_targets(frame) == [:transport, :source_endpoint, :ground_station, :link]

    transport_link = link_by_target(frame, :transport, "transport-golden-alpha")

    assert_link_runtime_context(transport_link,
      logical_source: "operational_observables",
      observable_id: "comms.transport.uplink_bitrate",
      scope_kind: "transport",
      scope_id: "transport-golden-alpha",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      source_request_id: frame.meta.source_request_id
    )

    assert context_value(transport_link.context, [:operational_resource]) == %{
             adapter_key: :tcp_socket,
             ground_station_id: "dss-14",
             link_id: "link-golden-alpha",
             resource_id: "transport-golden-alpha",
             scope_kind: :transport,
             source_endpoint_id: "source-endpoint-golden-1",
             transport_id: "transport-golden-alpha"
           }

    assert DataLinkSelection.selected_ref(transport_link, %{
             "placement-id" => "placement_uplink_bitrate"
           }) == %{
             "link_id" => transport_link.link_id,
             "target" => "transport",
             "target_id" => "transport-golden-alpha",
             "target_text" => "transport",
             "placement_id" => "placement_uplink_bitrate",
             "source" => "frame",
             "scope_kind" => "transport",
             "scope_id" => "transport-golden-alpha",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_operational_observables",
             "source_binding_id" => "default_flight_operational_observables",
             "transport_id" => "transport-golden-alpha",
             "source_endpoint_id" => "source-endpoint-golden-1",
             "ground_station_id" => "dss-14",
             "scope_link_id" => "link-golden-alpha",
             "observable_id" => "comms.transport.uplink_bitrate"
           }

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             unit: "bit/s",
             label: "Golden Alpha TCP",
             sample: %{
               sample_id: "transport-golden-alpha",
               raw_value: 4_800.0,
               engineering_value: 4_800.0,
               receipt_time: ~U[2026-06-17 12:04:00Z],
               generation_time: ~U[2026-06-17 12:04:00Z],
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

  defp operational_metric_source_opts(parent) do
    %{
      operational_observables: [
        transport_bitrate_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transport_bitrate_revision_called)
          "transport-bitrate-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :metric_transports_called)

          [
            %{
              transport_id: "transport-golden-alpha",
              display_name: "Golden Alpha TCP",
              adapter_key: :tcp_socket,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-1",
                ground_station_id: "dss-14",
                link_assignment_id: "link-golden-alpha"
              }
            },
            %{
              transport_id: "transport-golden-beta",
              display_name: "Golden Beta TCP",
              adapter_key: :tcp_socket,
              metadata: %{
                source_endpoint_id: "source-endpoint-golden-2",
                ground_station_id: "dss-63",
                link_assignment_id: "link-golden-beta"
              }
            }
          ]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transport_metric_snapshots_called)

          [
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              downlink_bitrate: 12_500.5,
              uplink_bitrate: 4_800.0,
              unit: "bit/s",
              observed_at: ~U[2026-06-17 12:04:00Z]
            },
            %{
              transport_id: "transport-golden-beta",
              source_endpoint_id: "source-endpoint-golden-2",
              ground_station_id: "dss-63",
              link_assignment_id: "link-golden-beta",
              downlink_bitrate: 8_500.0,
              unit: "bit/s",
              observed_at: ~U[2026-06-17 12:04:00Z]
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
