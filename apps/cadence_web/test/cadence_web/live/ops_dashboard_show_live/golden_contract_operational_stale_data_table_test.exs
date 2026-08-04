defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalStaleDataTableTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

  alias Cadence.Management.DataSources

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden stale operational data table fixture carries stale public row projection" do
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

    plan = Engine.plan(request, operational_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :operational_observables,
               observables: ["commanding.queue_depth"],
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
          source_opts: stale_operational_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z],
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :stale_data, severity: :warning, scope: :dashboard}] =
             result.dashboard_warnings

    assert %{
             "placement_command_queue_data_table" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :command_queue_depth,
                       product_family: :commanding,
                       warning_codes: [:stale_data],
                       freshness_policy: %{stale_after_ms: 1_000},
                       freshness_checked_at: ~U[2026-06-17 12:05:02Z],
                       data_source_id: "managed_operational_observables",
                       source_binding_id: "default_flight_operational_observables"
                     }
                   } = frame
                 ],
                 warnings: [
                   %ResolveWarning{
                     code: :stale_data,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_command_queue_data_table"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["commanding.queue_depth"]
    assert field_values(frame, "resource_id") == ["mission_dashboards"]
    assert field_values(frame, "label") == ["Pending commands"]
    assert field_values(frame, "scope_kind") == [:mission]
    assert field_values(frame, "value") == [0]
    assert field_values(frame, "unit") == ["commands"]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :stale,
             stale?: true,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: [:stale_data],
               reason_codes: [:stale, :stale_data]
             },
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true,
               warning_codes: [:stale_data],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"],
               time_modes: ["live"],
               time_axes: ["generation_time"]
             },
             data_management: %{
               warning_codes: ["stale_data"],
               badges: [],
               data_views: []
             },
             rows: [
               %{
                 observable_id: "commanding.queue_depth:mission_dashboards",
                 frame_observable_id: "commanding.queue_depth",
                 label: "Pending commands",
                 source: :operational_observables,
                 status_policy: :metric_value,
                 product_family: :commanding,
                 source_request_id: source_request_id,
                 logical_source: :operational_observables,
                 realm: "flight",
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 resource_id: "mission_dashboards",
                 scope_kind: :mission,
                 unit: "commands",
                 value: 0,
                 normalized_state: :observed,
                 links: [],
                 data_management: %{
                   warning_codes: ["stale_data"],
                   badges: [],
                   data_view: nil
                 },
                 stale?: true
               }
             ]
           } = data

    assert source_request_id == frame.meta.source_request_id
    assert "mission" in Enum.map(data.source_status.scope_kinds, &to_string/1)
    assert "mission_dashboards" in data.source_status.scope_ids
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

  defp operational_source_registry_opts(opts \\ []) do
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

  defp stale_operational_source_opts do
    %{
      operational_observables: [
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
        read_time: ~U[2026-06-17 12:05:00Z]
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
end
