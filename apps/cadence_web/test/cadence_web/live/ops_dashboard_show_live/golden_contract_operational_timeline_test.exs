defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalTimelineTest do
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

  test "golden operational RF state timeline fixture resolves event histories into timeline lanes" do
    document = load_fixture!("operational_rf_state_timeline.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_link_rf_state_timeline" => %{width_px: 720}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "link", mode: "one", ids: ["link-golden-alpha"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["link.rf_lock_state", "link.frame_sync_state"],
               sampling_mode: :event_history,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :runtime_managed,
                 :runtime_transport,
                 :transport_execution_state
               ],
               overlays: [],
               target_points: 720,
               time_axis: "generation_time",
               data_source_id: "managed_operational_observables",
               source_binding_id: "default_flight_operational_observables"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: operational_rf_state_timeline_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received {:rf_state_transports_opts, transport_opts}
    assert_received {:rf_state_lock_snapshots_opts, lock_opts}
    assert_received {:rf_state_frame_sync_snapshots_opts, frame_sync_opts}

    assert Keyword.fetch!(transport_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(transport_opts, :to) == ~U[2026-06-17 12:03:00Z]
    assert Keyword.fetch!(lock_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(lock_opts, :to) == ~U[2026-06-17 12:03:00Z]
    assert Keyword.fetch!(frame_sync_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(frame_sync_opts, :to) == ~U[2026-06-17 12:03:00Z]

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert %{
             "placement_link_rf_state_timeline" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :operational_observables, shape: :events} = lock_frame,
                   %Frame{source: :operational_observables, shape: :events} = frame_sync_frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert lock_frame.meta.supported_capability == :link_rf_lock_state_history
    assert lock_frame.meta.source_binding_id == "default_flight_operational_observables"
    assert lock_frame.meta.data_source_id == "managed_operational_observables"

    assert field_values(lock_frame, "time") == [
             ~U[2026-06-17 12:00:30Z],
             ~U[2026-06-17 12:01:30Z]
           ]

    assert field_values(lock_frame, "resource_id") == [
             "link-golden-alpha",
             "link-golden-alpha"
           ]

    assert field_values(lock_frame, "state") == [:acquiring, :locked]
    assert field_values(lock_frame, "normalized_state") == [:blue, :green]
    assert link_by_target(lock_frame, :transport, "transport-golden-alpha")
    assert link_by_target(lock_frame, :source_endpoint, "source-endpoint-golden-1")
    assert link_by_target(lock_frame, :ground_station, "dss-14")

    assert frame_sync_frame.meta.supported_capability == :link_rf_frame_sync_state_history

    assert field_values(frame_sync_frame, "time") == [
             ~U[2026-06-17 12:00:45Z],
             ~U[2026-06-17 12:02:00Z]
           ]

    assert field_values(frame_sync_frame, "resource_id") == [
             "link-golden-alpha",
             "link-golden-alpha"
           ]

    assert field_values(frame_sync_frame, "state") == [:acquiring, :synchronized]
    assert field_values(frame_sync_frame, "normalized_state") == [:blue, :green]
    assert link_by_target(frame_sync_frame, :transport, "transport-golden-alpha")

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :state_timeline,
             engine_backed?: true,
             lanes: lanes,
             rows: rows
           } = data

    assert Enum.map(lanes, & &1.lane_key) == [
             "operational_observables:link.rf_lock_state:link-golden-alpha",
             "operational_observables:link.frame_sync_state:link-golden-alpha"
           ]

    assert Enum.map(rows, & &1.normalized_state) == [:blue, :green, :blue, :green]

    assert Enum.map(rows, & &1.resource_id) == [
             "link-golden-alpha",
             "link-golden-alpha",
             "link-golden-alpha",
             "link-golden-alpha"
           ]

    assert Enum.all?(rows, fn row ->
             Enum.any?(
               row.links,
               &(&1.target == :transport and &1.target_id == "transport-golden-alpha")
             )
           end)
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

  defp operational_source_registry_opts do
    operational_source_registry_opts([])
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

  defp operational_rf_state_timeline_source_opts(parent) do
    %{
      operational_observables: [
        link_rf_lock_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_state_lock_revision_called)
          "link-rf-lock-state-golden-revision"
        end,
        link_rf_frame_sync_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :rf_state_frame_sync_revision_called)
          "link-rf-frame-sync-state-golden-revision"
        end,
        transports_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:rf_state_transports_opts, opts})

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
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:rf_state_lock_snapshots_opts, opts})

          [
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              lock_state: :acquiring,
              observed_at: ~U[2026-06-17 12:00:30Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              transport_id: "transport-golden-beta",
              source_endpoint_id: "source-endpoint-golden-2",
              ground_station_id: "dss-63",
              link_assignment_id: "link-golden-beta",
              adapter_key: :rf_adapter,
              lock_state: :unlocked,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              lock_state: :degraded,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:rf_state_frame_sync_snapshots_opts, opts})

          [
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :acquiring,
              observed_at: ~U[2026-06-17 12:00:45Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-golden-beta",
              source_endpoint_id: "source-endpoint-golden-2",
              ground_station_id: "dss-63",
              link_assignment_id: "link-golden-beta",
              adapter_key: :rf_adapter,
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-golden-alpha",
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              link_assignment_id: "link-golden-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :lost,
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

  defp render_widget(%Document{} = document) do
    [render_item] = RenderItem.from_document(document)
    render_item.widget
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end

  defp link_by_target(%Frame{meta: meta}, target, target_id) do
    meta
    |> Map.get(:links, [])
    |> Enum.find(&(&1.target == target and &1.target_id == target_id))
  end
end
