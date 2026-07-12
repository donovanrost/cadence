defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractTransportExecutionTimelineTest do
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

  alias Cadence.OperationalEvents.EffectiveInterval
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden operational transport execution timeline fixture resolves interval history into lanes" do
    document = load_fixture!("operational_transport_execution_state_timeline.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_transport_execution_state_timeline" => %{width_px: 720}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "transport", mode: "one", ids: ["transport-golden-alpha"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["comms.transport.execution_state"],
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
          source_opts: operational_transport_execution_timeline_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received {:transport_execution_intervals_opts, interval_opts}
    assert Keyword.fetch!(interval_opts, :from) == ~U[2026-06-17 12:00:00Z]
    assert Keyword.fetch!(interval_opts, :to) == ~U[2026-06-17 12:04:00Z]

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert %{
             "placement_transport_execution_state_timeline" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :operational_observables, shape: :events} = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert frame.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.source_binding_id == "default_flight_operational_observables"
    assert frame.meta.data_source_id == "managed_operational_observables"
    assert frame.meta.observable_id == "comms.transport.execution_state"
    assert frame.meta.returned_points == 2

    assert field_values(frame, "time") == [
             ~U[2026-06-17 12:00:10Z],
             ~U[2026-06-17 12:01:30Z]
           ]

    assert field_values(frame, "ends_at") == [
             ~U[2026-06-17 12:01:30Z],
             ~U[2026-06-17 12:03:30Z]
           ]

    assert field_values(frame, "resource_id") == [
             "transport-golden-alpha",
             "transport-golden-alpha"
           ]

    assert field_values(frame, "contact_id") == [
             "contact-golden-alpha",
             "contact-golden-alpha"
           ]

    assert field_values(frame, "path_id") == ["uplink-golden-alpha", "uplink-golden-alpha"]
    assert field_values(frame, "state") == [:initialized, :transport_event_handled]
    assert field_values(frame, "normalized_state") == [:initialized, :transport_event_handled]

    assert Enum.map(frame.meta.evidence_refs, &{&1.kind, &1.id, &1.confidence}) == [
             {:transport_execution_interval, "transport-execution-interval-golden-alpha-1",
              :projected},
             {:operational_interval, "transport-execution-event-golden-alpha-1", :direct},
             {:transport_execution_interval, "transport-execution-interval-golden-alpha-2",
              :projected},
             {:operational_interval, "transport-execution-event-golden-alpha-2", :direct}
           ]

    assert link_by_target(frame, :transport, "transport-golden-alpha")

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :state_timeline,
             engine_backed?: true,
             lanes: lanes,
             rows: rows
           } = data

    assert Enum.map(lanes, & &1.lane_key) == [
             "operational_observables:comms.transport.execution_state:transport-golden-alpha"
           ]

    assert Enum.map(rows, & &1.normalized_state) == [
             :initialized,
             :transport_event_handled
           ]

    assert Enum.map(rows, & &1.ends_at) == [
             ~U[2026-06-17 12:01:30Z],
             ~U[2026-06-17 12:03:30Z]
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

  defp operational_transport_execution_timeline_source_opts(parent) do
    %{
      operational_observables: [
        transport_execution_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transport_execution_revision_called)
          "transport-execution-golden-revision"
        end,
        transport_execution_intervals_fun: fn _organization_id, _mission_id, opts ->
          send(parent, {:transport_execution_intervals_opts, opts})

          [
            transport_execution_interval(
              "transport-execution-interval-golden-alpha-1",
              "transport-golden-alpha",
              :initialized,
              ~U[2026-06-17 12:00:10Z],
              ~U[2026-06-17 12:01:30Z],
              source_event_id: "transport-execution-event-golden-alpha-1"
            ),
            transport_execution_interval(
              "transport-execution-interval-golden-alpha-2",
              "transport-golden-alpha",
              :transport_event_handled,
              ~U[2026-06-17 12:01:30Z],
              ~U[2026-06-17 12:03:30Z],
              source_event_id: "transport-execution-event-golden-alpha-2",
              transport_record_id: "transport-record-golden-alpha-2"
            ),
            transport_execution_interval(
              "transport-execution-interval-golden-beta-1",
              "transport-golden-beta",
              :timer_handled,
              ~U[2026-06-17 12:02:00Z],
              ~U[2026-06-17 12:03:00Z],
              contact_id: "contact-golden-beta",
              path_id: "uplink-golden-beta",
              source_event_id: "transport-execution-event-golden-beta-1"
            )
          ]
        end
      ]
    }
  end

  defp transport_execution_interval(
         interval_id,
         transport_id,
         event_kind,
         starts_at,
         ends_at,
         opts
       ) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      kind: :transport_execution,
      subject_kind: :transport,
      subject_id: transport_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: Keyword.fetch!(opts, :source_event_id),
      payload: %{
        "capability_instance_id" => transport_id,
        "transport_record_id" =>
          Keyword.get(opts, :transport_record_id, "transport-record-#{interval_id}"),
        "contact_id" => Keyword.get(opts, :contact_id, "contact-golden-alpha"),
        "path_id" => Keyword.get(opts, :path_id, "uplink-golden-alpha"),
        "event_kind" => Atom.to_string(event_kind)
      }
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
