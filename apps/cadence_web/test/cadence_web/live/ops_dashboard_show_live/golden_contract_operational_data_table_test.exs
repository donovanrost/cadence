defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalDataTableTest do
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

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden operational data table fixture preserves projected row source context" do
    document = load_fixture!("operational_data_table.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_operational_data_table" => %{width_px: 640}})
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["contacts.phase", "ground.station.connection_state"],
               sampling_mode: :latest,
               products: [
                 :contacts_phase,
                 :connection_state,
                 :ground_station,
                 :link_rf,
                 :transport_bitrate,
                 :commanding,
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
          source_opts: operational_source_opts(parent),
          source_result_cache?: false,
          validate_dashboard_contract?: true
        )
      )

    assert_received :scheduled_contacts_called
    assert_received :realized_contacts_called
    assert_received :transports_called
    assert_received :source_endpoints_called
    assert_received :connection_snapshots_called

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 2

    assert %{
             "placement_operational_data_table" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :operational_observables} = contact_frame,
                   %Frame{source: :operational_observables} = connection_frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :ready,
             stale?: false,
             source_status: %{
               state: :fresh,
               severity: :ok,
               data_state: :ready,
               warning_codes: [],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               time_modes: ["live"],
               time_axes: ["generation_time"]
             },
             rows: [contact_row, connection_row]
           } = data

    assert %{
             observable_id: "contacts.phase:scheduled-contact-golden-1",
             frame_observable_id: "contacts.phase",
             label: "contacts.phase / scheduled / scheduled-contact-golden-1",
             source: :operational_observables,
             status_policy: :contact_phase,
             product_family: :contacts_phase,
             source_request_id: contact_source_request_id,
             logical_source: :operational_observables,
             realm: "flight",
             data_source_id: "managed_operational_observables",
             source_binding_id: "default_flight_operational_observables",
             value: :scheduled,
             normalized_state: :scheduled,
             links: contact_links,
             data_management: nil,
             stale?: false
           } = contact_row

    assert %{
             observable_id: "ground.station.connection_state:dss-14",
             frame_observable_id: "ground.station.connection_state",
             label: "Goldstone DSS-14",
             source: :operational_observables,
             status_policy: :connection_state,
             product_family: :connection_state,
             source_request_id: connection_source_request_id,
             logical_source: :operational_observables,
             realm: "flight",
             data_source_id: "managed_operational_observables",
             source_binding_id: "default_flight_operational_observables",
             resource_id: "dss-14",
             scope_kind: :ground_station,
             value: :connected,
             normalized_state: :connected,
             links: connection_links,
             data_management: nil,
             stale?: false
           } = connection_row

    refute Map.has_key?(contact_row, :contact_kind)
    refute Map.has_key?(connection_row, :connection_state)
    assert contact_source_request_id == contact_frame.meta.source_request_id
    assert connection_source_request_id == connection_frame.meta.source_request_id

    assert Enum.any?(
             contact_links,
             &(&1.target == :contact and &1.target_id == "scheduled-contact-golden-1")
           )

    assert Enum.any?(
             connection_links,
             &(&1.target == :source_endpoint and &1.target_id == "source-endpoint-golden-1")
           )

    assert Enum.any?(
             connection_links,
             &(&1.target == :ground_station and &1.target_id == "dss-14")
           )

    assert "source_endpoint" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "source-endpoint-golden-1" in data.source_status.scope_ids
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

  defp operational_source_opts(parent) do
    %{
      operational_observables: [
        contact_phase_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :contact_phase_revision_called)
          "contact-phase-golden-revision"
        end,
        connection_state_revision_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :connection_state_revision_called)
          "connection-state-golden-revision"
        end,
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :scheduled_contacts_called)

          [
            %{
              scheduled_contact_id: "scheduled-contact-golden-1",
              realized_contact_id: nil,
              lifecycle_state: :scheduled,
              starts_at: ~U[2026-06-17 12:00:00Z],
              source_endpoint_refs: ["source-endpoint-golden-1"]
            }
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :realized_contacts_called)
          []
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :transports_called)
          []
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :source_endpoints_called)

          [
            %{
              source_endpoint_id: "source-endpoint-golden-1",
              display_name: "Goldstone DSS-14",
              metadata: %{ground_station_id: "dss-14"}
            }
          ]
        end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          send(parent, :connection_snapshots_called)

          [
            %{
              source_endpoint_id: "source-endpoint-golden-1",
              ground_station_id: "dss-14",
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:00:00Z]
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
end
