defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalLatestTest do
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

  test "golden operational fixture resolves source override through operational frames" do
    document = load_fixture!("operational_status_matrix.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_operational_status" => %{width_px: 480}})
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
               target_points: 480,
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
             "placement_operational_status" => %PlacementFrames{
               primary: [
                 %Frame{source: :operational_observables} = contact_frame,
                 %Frame{source: :operational_observables} = connection_frame
               ],
               overlays: %{},
               warnings: []
             }
           } = result.frames_by_placement

    assert contact_frame.meta.supported_capability == :contacts_phase
    assert contact_frame.meta.source_binding_id == "default_flight_operational_observables"
    assert contact_frame.meta.data_source_id == "managed_operational_observables"
    assert field_values(contact_frame, "observable_id") == ["contacts.phase"]
    assert field_values(contact_frame, "phase") == [:scheduled]

    contact_link = link_by_target(contact_frame, :contact)

    assert_link_runtime_context(contact_link,
      logical_source: "operational_observables",
      observable_id: "scheduled-contact-golden-1",
      scope_kind: "source_endpoint",
      scope_id: "source-endpoint-golden-1",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables",
      source_request_id: contact_frame.meta.source_request_id
    )

    assert connection_frame.meta.supported_capability == :connection_state
    assert connection_frame.meta.source_binding_id == "default_flight_operational_observables"
    assert connection_frame.meta.data_source_id == "managed_operational_observables"
    assert field_values(connection_frame, "observable_id") == ["ground.station.connection_state"]
    assert field_values(connection_frame, "connection_state") == [:connected]

    placement_frames = result.frames_by_placement["placement_operational_status"]
    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :ready,
             stale?: false,
             source_status: source_status,
             rows: [contact_row, connection_row]
           } = data

    assert %{
             state: :fresh,
             severity: :ok,
             data_state: :ready,
             stale?: false,
             warning_codes: [],
             logical_sources: [:operational_observables],
             data_source_ids: ["managed_operational_observables"],
             source_binding_ids: ["default_flight_operational_observables"],
             time_modes: ["live"],
             time_axes: ["generation_time"]
           } = source_status

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
             contact_id: "scheduled-contact-golden-1",
             contact_kind: :scheduled,
             value: :scheduled,
             normalized_state: :scheduled,
             links: contact_links,
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
             source_endpoint_id: "source-endpoint-golden-1",
             ground_station_id: "dss-14",
             value: :connected,
             normalized_state: :connected,
             links: connection_links,
             stale?: false
           } = connection_row

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

  defp render_widget(%Document{} = document) do
    [render_item] = RenderItem.from_document(document)
    render_item.widget
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end

  defp link_by_target(%Frame{meta: meta}, target) do
    Enum.find(Map.get(meta, :links, []), &(&1.target == target))
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
