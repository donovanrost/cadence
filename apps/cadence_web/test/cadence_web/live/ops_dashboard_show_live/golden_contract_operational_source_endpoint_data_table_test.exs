defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalSourceEndpointDataTableTest do
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

  test "golden stale source-endpoint command queue data table preserves scoped row link" do
    document = load_fixture!("stale_operational_data_table.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{
        "placement_command_queue_data_table" => %{width_px: 640}
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: "source_endpoint", mode: "one", ids: ["source-endpoint-golden-1"]}
      })

    result =
      Engine.resolve(
        request,
        operational_source_registry_opts(
          source_opts: stale_source_endpoint_command_queue_source_opts(),
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
    assert field_values(frame, "resource_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "label") == ["source endpoint / source-endpoint-golden-1"]
    assert field_values(frame, "scope_kind") == [:source_endpoint]
    assert field_values(frame, "source_endpoint_id") == ["source-endpoint-golden-1"]
    assert field_values(frame, "value") == [1]
    assert field_values(frame, "unit") == ["commands"]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :data_table,
             engine_backed?: true,
             lifecycle_state: :stale,
             stale?: true,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: [:stale_data]
             },
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true,
               warning_codes: [:stale_data],
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables"],
               source_binding_ids: ["default_flight_operational_observables"]
             },
             rows: [
               %{
                 observable_id: "commanding.queue_depth:source-endpoint-golden-1",
                 frame_observable_id: "commanding.queue_depth",
                 label: "source endpoint / source-endpoint-golden-1",
                 source: :operational_observables,
                 status_policy: :metric_value,
                 product_family: :commanding,
                 logical_source: :operational_observables,
                 realm: "flight",
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 resource_id: "source-endpoint-golden-1",
                 scope_kind: :source_endpoint,
                 source_endpoint_id: "source-endpoint-golden-1",
                 unit: "commands",
                 value: 1,
                 normalized_state: :observed,
                 data_management: %{
                   warning_codes: ["stale_data"],
                   badges: [],
                   data_view: nil
                 },
                 stale?: true
               } = row
             ]
           } = data

    assert Enum.any?(
             row.links,
             &(&1.target == :source_endpoint and &1.target_id == "source-endpoint-golden-1")
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

  defp stale_source_endpoint_command_queue_source_opts do
    %{
      operational_observables: [
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              command_queue_entry_id: "queue-golden-alpha",
              source_endpoint_ref: "source-endpoint-golden-1",
              queue_lane_key: "source-endpoint-golden-1",
              lifecycle_state: :pending
            },
            %{
              command_queue_entry_id: "queue-golden-beta",
              source_endpoint_ref: "source-endpoint-golden-2",
              queue_lane_key: "source-endpoint-golden-2",
              lifecycle_state: :pending
            }
          ]
        end,
        read_time: ~U[2026-06-17 12:05:00Z]
      ]
    }
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end
end
